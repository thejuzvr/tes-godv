defmodule TesIdleWeb.Controllers.AdminStatsTest do
  @moduledoc "«Пульс мира»: сводка владения без заглушек (S-7)."
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Item, JournalEntry, Location, Monster, NarrativeTemplate, User}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    admin =
      Repo.insert!(%User{
        username: "pulse_admin_#{suffix}",
        email: "pulse_admin_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: true
      })

    plain =
      Repo.insert!(%User{
        username: "pulse_plain_#{suffix}",
        email: "pulse_plain_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    location =
      Repo.insert!(%Location{
        name: "Пульс-пещера #{suffix}",
        description: "тест",
        location_type: "dungeon",
        danger_level: "Средняя"
      })

    %{admin: admin, plain: plain, location: location, suffix: suffix}
  end

  defp conn_for(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp hero!(user, location, attrs) do
    Repo.insert!(%Hero{
      user_id: user.id,
      name: "Пульс-герой #{System.unique_integer([:positive])}",
      race: "Nord",
      hero_class: "Warrior",
      location_id: location.id
    })
    |> then(fn h -> Repo.update!(Ecto.Changeset.change(h, attrs)) end)
  end

  test "returns real totals instead of hardcoded zeros", %{admin: admin, location: loc} do
    hero!(admin, loc, %{state: "fighting", level: 7, gold: 500, total_kills: 12, is_online: true})
    hero!(admin, loc, %{state: "exploring", level: 2, gold: 100, is_online: false})

    Repo.insert!(%Monster{name: "Пульс-волк", hp: 40, location_id: loc.id, is_active: true})
    Repo.insert!(%Item{name: "Пульс-меч", item_type: "equipment", weight: 1.0})
    Repo.insert!(%NarrativeTemplate{
      template_type: "explore",
      text_template: "Текст {hero_name}",
      source: "system",
      is_active: true
    })

    body = conn_for(admin) |> get("/api/v1/admin/stats?days=7") |> json_response(200)

    totals = body["totals"]
    assert totals["users"] >= 2
    assert totals["heroes"] == 2
    assert totals["monsters"] == 1
    # раньше здесь всегда был 0 — теперь настоящий счётчик
    assert totals["items"] >= 1
    assert totals["locations"] >= 1
    assert totals["narrative_templates"] >= 1
    assert totals["active_templates"] >= 1
  end

  test "hero breakdown reports states, vitals and treasure", %{admin: admin, location: loc} do
    hero!(admin, loc, %{state: "fighting", level: 8, gold: 300, total_kills: 5, is_online: true})
    hero!(admin, loc, %{state: "dead", level: 3, gold: 50, is_online: false})
    hero!(admin, loc, %{state: "exploring", level: 12, gold: 200, is_online: true})

    body = conn_for(admin) |> get("/api/v1/admin/stats?days=7") |> json_response(200)
    heroes = body["heroes"]

    states = Map.new(heroes["by_state"], fn s -> {s["state"], s["count"]} end)
    assert states["fighting"] == 1
    assert states["dead"] == 1
    assert states["exploring"] == 1

    assert heroes["online"] == 2
    assert heroes["dead"] == 1
    assert heroes["max_level"] == 12
    assert heroes["total_gold"] == 550
    assert heroes["total_kills"] == 5
    assert is_float(heroes["avg_level"])
  end

  test "level distribution keeps all buckets, including empty ones", %{admin: admin, location: loc} do
    hero!(admin, loc, %{level: 3})
    hero!(admin, loc, %{level: 4})
    hero!(admin, loc, %{level: 15})

    body = conn_for(admin) |> get("/api/v1/admin/stats?days=7") |> json_response(200)
    levels = Map.new(body["levels"], fn l -> {l["label"], l["count"]} end)

    assert levels["1–5"] == 2
    assert levels["11–20"] == 1
    # пустые полосы остаются в ответе, чтобы график не «прыгал»
    assert levels["6–10"] == 0
    assert levels["41+"] == 0
  end

  test "activity fills empty days with zeros for a continuous chart", %{admin: admin, location: loc} do
    h = hero!(admin, loc, %{})

    Repo.insert!(%JournalEntry{
      hero_id: h.id,
      entry_type: "explore",
      text: "Сходил в пещеру",
      xp_gained: 25,
      gold_gained: 10
    })

    body = conn_for(admin) |> get("/api/v1/admin/stats?days=7") |> json_response(200)
    activity = body["activity"]

    assert length(activity) == 7
    # дни идут подряд без разрывов
    dates = Enum.map(activity, & &1["date"])
    assert dates == Enum.sort(dates)

    today_entry =
      Enum.find(activity, fn d -> d["date"] == Date.to_iso8601(Date.utc_today()) end)

    assert today_entry["entries"] == 1
    assert today_entry["xp"] == 25
    assert today_entry["gold"] == 10
    assert today_entry["heroes"] == 1

    # остальные дни — честные нули
    assert Enum.count(activity, &(&1["entries"] == 0)) == 6

    economy = body["economy"]
    assert economy["xp"] == 25
    assert economy["gold"] == 10
    assert economy["heroes"] == 1
  end

  test "days parameter is bounded and invalid input falls back", %{admin: admin} do
    ok = conn_for(admin) |> get("/api/v1/admin/stats?days=30") |> json_response(200)
    assert length(ok["activity"]) == 30

    fallback = conn_for(admin) |> get("/api/v1/admin/stats?days=abc") |> json_response(200)
    # дефолт 14 дней, без 500
    assert length(fallback["activity"]) == 14

    huge = conn_for(admin) |> get("/api/v1/admin/stats?days=9999") |> json_response(200)
    assert length(huge["activity"]) == 14
  end

  test "content breakdown groups journal types and monsters by location", %{
    admin: admin,
    location: loc
  } do
    h = hero!(admin, loc, %{})
    Repo.insert!(%JournalEntry{hero_id: h.id, entry_type: "explore", text: "a"})
    Repo.insert!(%JournalEntry{hero_id: h.id, entry_type: "explore", text: "b"})
    Repo.insert!(%JournalEntry{hero_id: h.id, entry_type: "combat", text: "c"})
    Repo.insert!(%Monster{name: "Пульс-монстр", hp: 10, location_id: loc.id, is_active: true})

    body = conn_for(admin) |> get("/api/v1/admin/stats?days=7") |> json_response(200)
    types = Map.new(body["content"]["journal_types"], fn t -> {t["entry_type"], t["count"]} end)

    assert types["explore"] == 2
    assert types["combat"] == 1

    assert Enum.any?(
             body["content"]["monsters_by_location"],
             &(&1["location"] == loc.name and &1["count"] == 1)
           )

    assert Enum.any?(
             body["content"]["locations_by_type"],
             &(&1["location_type"] == "dungeon")
           )
  end

  test "server_time is present so the panel can show freshness", %{admin: admin} do
    body = conn_for(admin) |> get("/api/v1/admin/stats") |> json_response(200)
    assert is_binary(body["server_time"])
    assert {:ok, _, _} = DateTime.from_iso8601(body["server_time"])
    assert is_map(body["online"])
  end

  test "loops endpoint reports the real worker state, not a hardcoded zero", %{admin: admin} do
    body = conn_for(admin) |> get("/api/v1/admin/game/loops") |> json_response(200)

    # В test-окружении воркер выключен (game_tick_enabled: false) — это честный false
    assert is_boolean(body["running"])
    assert body["count"] in [0, 1]
    assert body["interval_seconds"] == 30
    assert is_integer(body["heroes"])
    assert is_list(body["loops"])
    assert [%{"name" => "GameTickWorker"}] = body["loops"]
  end

  test "stats are not leaked to plain users", %{plain: plain} do
    assert conn_for(plain) |> get("/api/v1/admin/stats") |> response(403)
    assert build_conn() |> get("/api/v1/admin/stats") |> response(401)
  end
end
