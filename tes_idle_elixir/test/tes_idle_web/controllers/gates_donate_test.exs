defmodule TesIdleWeb.Controllers.GatesDonateTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, JournalEntry, Location}
  alias TesIdle.World.{Gates, Snapshot}

  @endpoint TesIdleWeb.Endpoint

  # Kernel выключен в тестах — gate_donate идёт офлайн-фоллбеком через Snapshot.
  # Врата принудительно открываются в снапшоте перед запросом.

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_gate_#{suffix}",
        email: "qa_gate_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Вратарь", race: "Nord", hero_class: "Warrior",
        level: 1, brain_hash: "x", personality: %{}, skills: %{},
        gold: 500, sp: 100, state_data: "{}"})

    # имя локации UNIQUE — ищем существующий город, иначе создаём тестовый
    loc =
      Repo.one(from l in Location, where: l.location_type == "city", order_by: l.name, limit: 1) ||
        Repo.insert!(%Location{name: "QA Гейт-город #{suffix}", region: "QA", location_type: "city",
          danger_level: "Низкая", description: "тест", flags: %{}})

    %{user: user, hero: hero, loc_id: loc.id, loc_name: loc.name}
  end

  defp open_gates!(loc_id, loc_name, target \\ 300) do
    snap = Snapshot.current()

    block =
      Gates.init_block()
      |> Map.put("status", "open")
      |> Map.put("location_id", loc_id)
      |> Map.put("location_name", loc_name)
      |> Map.put("target", target)
      |> Map.put("opened_tick", (snap["tick"] || 0) + 1)
      |> Map.put("deadline_tick", (snap["tick"] || 0) + 1 + 72)

    Snapshot.put(Map.put(snap, "gates", block))
    block
  end

  defp authed_conn(%User{} = user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  test "gate_donate: золото списывается, фонд растёт, донатер виден, журнал по шаблону", %{user: user, hero: hero, loc_id: loc_id, loc_name: loc_name} do
    # шаблон журнала из БД (тест самодостаточен — test-БД без сидов)
    Repo.insert!(%JournalEntry{id: Ecto.UUID.generate(), hero_id: hero.id, entry_type: "skip",
      text: "placeholder", created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})

    Repo.insert!(%TesIdle.Schemas.NarrativeTemplate{
      template_type: "gate_donation", text_template: "{hero_name} кладёт {amount} 🪙 в фонд: {fund}. {status}.",
      source: "system", is_active: true})

    open_gates!(loc_id, loc_name)

    conn = authed_conn(user) |> post("/api/v1/gates/donate", %{"amount" => 100})
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["gold"] == 400
    assert body["closed"] == false
    assert body["gates"]["status"] == "open"
    assert body["gates"]["fund"] == 100
    assert body["gates"]["location_name"] == loc_name
    assert [%{"name" => "QA Вратарь", "amount" => 100}] = body["gates"]["top_donors"]

    assert Repo.reload!(hero).gold == 400

    entry =
      Repo.one!(from j in JournalEntry,
        where: j.entry_type == "gate_donation" and j.hero_id == ^hero.id)

    assert entry.text =~ "QA Вратарь"
    assert entry.text =~ "100"
    assert entry.text =~ "разлом всё ещё зияет"
  end

  test "gate_donate: кит-взнос закрывает врата → closed, событие gate_closed в мире", %{user: user, loc_id: loc_id, loc_name: loc_name} do
    open_gates!(loc_id, loc_name, 300)

    conn = authed_conn(user) |> post("/api/v1/gates/donate", %{"amount" => 300})
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["closed"] == true
    assert body["gates"]["status"] == "closed"
    assert body["gates"]["fund"] == 300

    # событие в мировом фиде
    snap = Snapshot.current()
    assert Enum.any?(snap["events"] || [], &(&1["type"] == "gate_closed"))
  end

  test "gate_donate: врата закрыты → 409 gates_closed, золото возвращено", %{user: user, hero: hero} do
    conn = authed_conn(user) |> post("/api/v1/gates/donate", %{"amount" => 100})
    assert conn.status == 409
    assert %{"error" => "gates_closed", "gold" => 500} = json_response(conn, 409)
    assert Repo.reload!(hero).gold == 500
  end

  test "gate_donate: нехватка золота → 409, минимум и строка-число", %{user: user, hero: hero, loc_id: loc_id, loc_name: loc_name} do
    open_gates!(loc_id, loc_name)

    conn = authed_conn(user) |> post("/api/v1/gates/donate", %{"amount" => 501})
    assert conn.status == 409
    assert %{"error" => "not_enough_gold"} = json_response(conn, 409)
    assert Repo.reload!(hero).gold == 500

    conn = authed_conn(user) |> post("/api/v1/gates/donate", %{"amount" => 5})
    assert conn.status == 400

    conn = authed_conn(user) |> post("/api/v1/gates/donate", %{"amount" => "50"})
    assert conn.status == 200
    assert json_response(conn, 200)["gold"] == 450
  end
end
