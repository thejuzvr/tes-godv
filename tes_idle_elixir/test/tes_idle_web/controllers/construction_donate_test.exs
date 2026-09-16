defmodule TesIdleWeb.Controllers.ConstructionDonateTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, JournalEntry, NarrativeTemplate}

  @endpoint TesIdleWeb.Endpoint

  # В тестовой среде Kernel выключен (supervisor) — donate идёт офлайн-фоллбеком
  # через Snapshot; проверяем контракт контроллера: списание, ошибки, журнал.

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_build_#{suffix}",
        email: "qa_build_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Жертвователь", race: "Nord", hero_class: "Warrior",
        level: 1, brain_hash: "x", personality: %{}, skills: %{},
        gold: 500, sp: 100, state_data: "{}"})

    %{user: user, hero: hero}
  end

  defp authed_conn(%User{} = user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  test "donate: золото списывается, прогресс растёт, топ-донатеров видно", %{user: user, hero: hero} do
    conn = authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => 120})
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["gold"] == 380
    assert body["construction"]["collected"] == 120
    assert body["construction"]["target"] > 0
    assert body["construction"]["stage"] == "фундамент"
    assert [%{"name" => "QA Жертвователь", "gold" => 120}] = body["construction"]["top_donors"]

    assert Repo.reload!(hero).gold == 380
  end

  test "donate: не хватает золота → 409, списания нет", %{user: user, hero: hero} do
    conn = authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => 501})
    assert conn.status == 409
    assert %{"error" => "not_enough_gold"} = json_response(conn, 409)
    assert Repo.reload!(hero).gold == 500
  end

  test "donate: меньше минимума и не-число → 400, строка-число валидна", %{user: user} do
    conn = authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => 5})
    assert conn.status == 400

    conn = authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => "abc"})
    assert conn.status == 400

    # целое может прийти строкой (грабля approve-batch max)
    conn = authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => "40"})
    assert conn.status == 200
  end

  test "donate: журнал по шаблону из БД (нет шаблона — честная тишина, без фейков)", %{user: user, hero: hero} do
    # Сначала без шаблона
    authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => 30})

    assert Repo.one(
             from j in JournalEntry,
               where: j.entry_type == "construction_donation" and j.hero_id == ^hero.id
           ) == nil

    # Сидим шаблон (системный источник) — запись появляется
    Repo.insert!(%NarrativeTemplate{
      template_type: "construction_donation",
      text_template: "{hero_name} кладёт {amount} золота в фонд «{project}».",
      source: "system",
      is_active: true
    })

    authed_conn(user) |> post("/api/v1/construction/donate", %{"amount" => 60})

    entry =
      Repo.one!(
        from j in JournalEntry,
          where: j.entry_type == "construction_donation" and j.hero_id == ^hero.id
      )

    assert entry.text =~ "QA Жертвователь"
    assert entry.text =~ "60"
    refute entry.text =~ "{"
  end
end
