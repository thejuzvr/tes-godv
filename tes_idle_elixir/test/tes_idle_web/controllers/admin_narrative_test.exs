defmodule TesIdleWeb.Controllers.AdminNarrativeTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, NarrativeTemplate}
  import Ecto.Query

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    admin =
      Repo.insert!(%User{username: "qa_narr_admin_#{suffix}",
        email: "qa_narr_admin_#{suffix}@test.gg", password_hash: "x", is_admin: true})

    plain =
      Repo.insert!(%User{username: "qa_narr_plain_#{suffix}",
        email: "qa_narr_plain_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    %{admin: admin, plain: plain, suffix: suffix}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp template(attrs) do
    Repo.insert!(Map.merge(%NarrativeTemplate{
      template_type: "explore",
      text_template: "QA шаблон {hero_name}",
      source: "system",
      is_active: true,
    }, attrs))
  end

  # ─── GET /admin/narrative-templates/stats ─────────────

  test "stats: суммы по типам и источникам, тонкие типы первыми", %{admin: admin} do
    template(%{template_type: "explore"})
    template(%{template_type: "explore", is_active: false})
    template(%{template_type: "world_news", source: "community", is_active: false})

    conn = authed_conn(admin) |> get("/api/v1/admin/narrative-templates/stats")
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["total"] == 3
    assert body["active"] == 1

    types = body["types"]
    assert length(types) == 2
    # Сортировка по возрастанию — тонкие первыми
    assert hd(types)["template_type"] == "world_news"
    assert hd(types)["total"] == 1
    assert hd(types)["active"] == 0

    explore = Enum.find(types, &(&1["template_type"] == "explore"))
    assert explore["total"] == 2
    assert explore["active"] == 1

    assert %{"source" => "community", "count" => 1} in body["sources"]
    assert %{"source" => "system", "count" => 2} in body["sources"]
  end

  test "stats: не-админ → 403", %{plain: plain} do
    conn = authed_conn(plain) |> get("/api/v1/admin/narrative-templates/stats")
    assert conn.status == 403
  end

  # ─── GET index с q-поиском ────────────────────────────

  test "index: q ищет по подстроке текста, % и _ экранируются", %{admin: admin} do
    template(%{text_template: "Хальвар ловит рыбу у реки"})
    template(%{text_template: "Герой спит в таверне"})
    template(%{text_template: "старая_карта найдена"})

    conn = authed_conn(admin) |> get("/api/v1/admin/narrative-templates?q=#{URI.encode_www_form("рыб")}")
    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["total"] == 1
    assert hd(body["templates"])["text_template"] == "Хальвар ловит рыбу у реки"

    # подчёркивание — литерал, а не any-char wildcard
    conn2 = authed_conn(admin) |> get("/api/v1/admin/narrative-templates?q=старая_карта")
    assert json_response(conn2, 200)["total"] == 1
  end

  # ─── POST bulk ────────────────────────────────────────

  test "bulk activate/deactivate меняет is_active у списка id", %{admin: admin} do
    t1 = template(%{is_active: false})
    t2 = template(%{is_active: false})

    conn =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/admin/narrative-templates/bulk",
        %{"ids" => [t1.id, t2.id], "action" => "activate"})
    assert conn.status == 200
    assert json_response(conn, 200)["updated"] == 2

    assert Repo.reload!(t1).is_active == true
    assert Repo.reload!(t2).is_active == true

    conn2 =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/admin/narrative-templates/bulk",
        %{"ids" => [t1.id], "action" => "deactivate"})
    assert json_response(conn2, 200)["updated"] == 1
    assert Repo.reload!(t1).is_active == false
  end

  test "bulk delete удаляет шаблоны", %{admin: admin} do
    t1 = template(%{})
    t2 = template(%{})

    conn =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/admin/narrative-templates/bulk",
        %{"ids" => [t1.id, t2.id], "action" => "delete"})
    assert json_response(conn, 200)["deleted"] == 2

    refute Repo.reload(t1)
    refute Repo.reload(t2)
  end

  test "bulk: неизвестное действие и пустой список → 400", %{admin: admin} do
    t1 = template(%{})

    conn =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/admin/narrative-templates/bulk",
        %{"ids" => [t1.id], "action" => "explode"})
    assert conn.status == 400

    conn2 =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/admin/narrative-templates/bulk", %{"ids" => [], "action" => "activate"})
    assert conn2.status == 400
  end

  # ─── PATCH update с mood_* ────────────────────────────

  test "update: JSON-тело задаёт text, type, is_active и mood-диапазон", %{admin: admin} do
    t = template(%{mood_min: nil, mood_max: nil})

    conn =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v1/admin/narrative-templates/#{t.id}",
        %{"text_template" => "Обновлённый текст", "template_type" => "rest",
          "is_active" => false, "mood_min" => 30.5, "mood_max" => ""})
    assert conn.status == 200

    fresh = Repo.reload!(t)
    assert fresh.text_template == "Обновлённый текст"
    assert fresh.template_type == "rest"
    assert fresh.is_active == false
    assert fresh.mood_min == 30.5
    assert fresh.mood_max == nil
  end

  test "update: mood_* числа из JSON приходят строкой — парсятся", %{admin: admin} do
    t = template(%{})

    conn =
      authed_conn(admin)
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v1/admin/narrative-templates/#{t.id}", %{"mood_min" => "45"})
    assert conn.status == 200
    assert Repo.reload!(t).mood_min == 45.0
  end

  # ─── A-1b: массовое одобрение ─────────────────────────────

  test "approve_batch: без фильтров и без all → 400", %{admin: admin} do
    conn = authed_conn(admin) |> post("/api/v1/admin/narrative-templates/approve-batch", %{})
    assert conn.status == 400
  end

  test "approve_batch: по source=llm одобряет только неактивные llm", %{admin: admin} do
    pending = [
      Repo.insert!(%NarrativeTemplate{template_type: "combat_result", text_template: "п1", source: "llm", is_active: false}),
      Repo.insert!(%NarrativeTemplate{template_type: "combat_result", text_template: "п2", source: "llm", is_active: false}),
      Repo.insert!(%NarrativeTemplate{template_type: "combat_result", text_template: "п3", source: "llm", is_active: false})
    ]

    already_active =
      Repo.insert!(%NarrativeTemplate{template_type: "combat_result", text_template: "жив", source: "llm", is_active: true})

    other_source =
      Repo.insert!(%NarrativeTemplate{template_type: "combat_result", text_template: "комьюнити", source: "community", is_active: false})

    conn = authed_conn(admin) |> post("/api/v1/admin/narrative-templates/approve-batch", %{"source" => "llm"})
    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["approved"] == 3
    assert body["remaining"] == 1

    ids = Enum.map(pending ++ [already_active], & &1.id)
    assert Repo.all(from t in NarrativeTemplate, where: t.id in ^ids, select: t.is_active) |> Enum.all?(& &1 == true)
    assert Repo.reload!(other_source).is_active == false
  end

  test "approve_batch: all=true одобряет всё, max ограничивает", %{admin: admin} do
    for i <- 1..5, do: Repo.insert!(%NarrativeTemplate{template_type: "rest", text_template: "т#{i}", source: "llm", is_active: false})

    conn = authed_conn(admin) |> post("/api/v1/admin/narrative-templates/approve-batch", %{"all" => "true", "max" => "2"})
    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["approved"] == 2
    assert body["remaining"] >= 1
  end
end
