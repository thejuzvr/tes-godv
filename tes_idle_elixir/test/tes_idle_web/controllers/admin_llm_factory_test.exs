defmodule TesIdleWeb.Controllers.AdminLlmFactoryTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, NarrativeTemplate, NarrativeFragment, JournalEntry}
  alias TesIdle.Test.FragmentIsolation
  import Ecto.Query

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    # N-5: сид наполнил пулы сцен в тестовой БД — «пустые пулы» и «точные
    # тексты кандидатов» требуют изоляции от ВСЕГО сид-контента
    # (fragments_available?/0 считает любые активные фрагменты).
    hidden = FragmentIsolation.hide_seed_fragments(:all)
    on_exit(fn -> FragmentIsolation.restore(hidden) end)

    suffix = System.unique_integer([:positive])
    admin =
      Repo.insert!(%User{username: "qa_llm_admin_#{suffix}",
        email: "qa_llm_admin_#{suffix}@test.gg", password_hash: "x", is_admin: true})

    plain =
      Repo.insert!(%User{username: "qa_llm_plain_#{suffix}",
        email: "qa_llm_plain_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    %{admin: admin, plain: plain}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp hero!(user) do
    Repo.insert!(%Hero{name: "QA", race: "Nord", hero_class: "Воин",
      user_id: user.id, brain_hash: String.duplicate("cd", 32)})
  end

  defp fragment(pool, text) do
    Repo.insert!(%NarrativeFragment{pool_key: pool, text: text, source: "system", is_active: true})
  end

  defp seed_scene_pools do
    # Опенеры всех 5 погод: фабрика тянет погоду случайно — любой ключ должен дать строку
    fragment("openers_rain", "Моросил частый дождь.")
    fragment("openers_clear", "Небо было чистым.")
    fragment("openers_cloud", "Тучи висели низко.")
    fragment("openers_storm", "Молнии резали небо.")
    fragment("openers_snow", "Валил мокрый снег.")
    fragment("closers_high", "{hero_name} шагал легко.")
    fragment("closers_mid", "Дорога стелилась вперёд.")
    fragment("closers_low", "Ноги несли, но сердце отставало.")
  end

  test "generate: 403 для не-админа", %{plain: plain} do
    conn = authed_conn(plain) |> post("/api/v1/admin/llm-generate", %{"template_type" => "explore"})
    assert conn.status == 403
  end

  test "generate: без template_type → 400", %{admin: admin} do
    conn = authed_conn(admin) |> post("/api/v1/admin/llm-generate", %{})
    assert conn.status == 400
  end

  test "generate: пустые пулы → 409, не вставляет", %{admin: admin} do
    hero!(admin)
    Repo.insert!(%NarrativeTemplate{template_type: "explore", text_template: "Костяк.", source: "system", is_active: true})

    # N-5: изоляция прячет сид-фрагменты только в своём sandbox-коннекте —
    # HTTP-пайплайн контроллера ходит в БД через тот же коннект, поэтому
    # fragments_available?/0 видит спрятанные строки как пустой пул.
    conn = authed_conn(admin) |> post("/api/v1/admin/llm-generate", %{"template_type" => "explore"})
    assert conn.status == 409
    assert Repo.one(from t in NarrativeTemplate, where: t.source == "llm", select: count()) == 0
  end

  test "generate: кандидаты source=llm is_active=false, дедуп, cap 20", %{admin: admin} do
    seed_scene_pools()
    hero!(admin)
    Repo.insert!(%NarrativeTemplate{template_type: "explore", text_template: "Костяк один.", source: "system", is_active: true})
    Repo.insert!(%NarrativeTemplate{template_type: "explore", text_template: "Костяк два.", source: "system", is_active: true})

    conn = authed_conn(admin) |> post("/api/v1/admin/llm-generate", %{"template_type" => "explore", "count" => "25"})
    assert conn.status == 200
    body = json_response(conn, 200)

    # cap 20 по параметру, дедуп по тексту может уменьшить
    assert body["inserted"] in 1..20
    assert body["pending_count"] == body["inserted"]

    inserted = Repo.all(from t in NarrativeTemplate, where: t.source == "llm")
    assert length(inserted) == body["inserted"]
    assert Enum.all?(inserted, &(&1.is_active == false))
    # Каждый кандидат — сцена: опенер (не костяк первым) + костяк + closer
    assert Enum.all?(inserted, fn t ->
      t.text_template =~ "Костяк" and not String.starts_with?(t.text_template, "Костяк") and
        (t.text_template =~ "шагал легко" or t.text_template =~ "Дорога стелилась" or
           t.text_template =~ "сердце отставало")
    end)
  end

  test "generate: тип без активных system-шаблонов → inserted 0, не падает", %{admin: admin} do
    seed_scene_pools()
    hero!(admin)

    conn = authed_conn(admin) |> post("/api/v1/admin/llm-generate", %{"template_type" => "ghost_type"})
    assert conn.status == 200
    assert json_response(conn, 200)["inserted"] == 0
  end

  # ─── A-2b: batch-генерация по целям аналитики ─────────────

  defp journal!(hero, entry_type, text) do
    Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: entry_type, text: text})
  end

  test "generate_batch: 403 для не-админа", %{plain: plain} do
    conn = authed_conn(plain) |> post("/api/v1/admin/llm-generate-batch", %{})
    assert conn.status == 403
  end

  test "generate_batch: тонкие типы + мёртвые шаблоны, сумма вставок", %{admin: admin} do
    seed_scene_pools()
    h = hero!(admin)

    # Тонкий тип: 2 записи журнала (< 5) + system-шаблон для фабрики
    journal!(h, "explore", "текст один")
    journal!(h, "explore", "текст два")
    Repo.insert!(%NarrativeTemplate{template_type: "explore", text_template: "Костяк.", source: "system", is_active: true})

    # Мёртвый шаблон: активный, без записей журнала
    Repo.insert!(%NarrativeTemplate{template_type: "ghost_xyz", text_template: "Мёртвый костяк.", source: "system", is_active: true})

    conn = authed_conn(admin) |> post("/api/v1/admin/llm-generate-batch", %{"count_per_type" => "3"})
    assert conn.status == 200
    body = json_response(conn, 200)

    assert Map.has_key?(body["per_type"], "explore")
    assert Map.has_key?(body["per_type"], "ghost_xyz")
    assert body["per_type"]["explore"] > 0
    assert body["per_type"]["ghost_xyz"] > 0
    assert body["inserted"] == body["per_type"]["explore"] + body["per_type"]["ghost_xyz"]
    assert body["pending_count"] == body["inserted"]
  end

  test "approve_batch: max числом из JSON не роняет endpoint (N-5 баг)", %{admin: admin} do
    seed_scene_pools()
    hero!(admin)
    Repo.insert!(%NarrativeTemplate{template_type: "explore", text_template: "Костяк.", source: "llm", is_active: false})
    Repo.insert!(%NarrativeTemplate{template_type: "explore", text_template: "Костяк два.", source: "llm", is_active: false})

    # max приходит ЦЕЛЫМ числом (JSON) — Integer.parse(700) раньше ронял 500
    conn = authed_conn(admin) |> post("/api/v1/admin/narrative-templates/approve-batch", %{"source" => "llm", "max" => 700})
    assert conn.status == 200

    body = json_response(conn, 200)
    # cap 200: 2 кандидата ≤ 200 → одобрены оба
    assert body["approved"] == 2
    assert Repo.one(from t in NarrativeTemplate, where: t.is_active == false, select: count()) == 0
  end
end
