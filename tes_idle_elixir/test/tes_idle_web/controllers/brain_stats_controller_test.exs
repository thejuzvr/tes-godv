defmodule TesIdleWeb.Controllers.BrainStatsControllerTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{DecisionAuditEvent, Hero, User}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    admin =
      Repo.insert!(%User{
        username: "audit_admin_#{suffix}",
        email: "audit_admin_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: true
      })

    plain =
      Repo.insert!(%User{
        username: "audit_plain_#{suffix}",
        email: "audit_plain_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    hero =
      Repo.insert!(%Hero{
        name: "Combat QA #{suffix}",
        race: "Nord",
        hero_class: "Warrior",
        user_id: admin.id
      })

    other =
      Repo.insert!(%Hero{
        name: "Peace QA #{suffix}",
        race: "Nord",
        hero_class: "Mage",
        user_id: plain.id
      })

    %{admin: admin, plain: plain, hero: hero, other: other}
  end

  defp conn_for(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp audit(hero, type, attrs \\ %{}) do
    Repo.insert!(%DecisionAuditEvent{
      hero_id: hero.id,
      event_type: type,
      game_day: 4,
      game_hour: 12.0,
      goal: attrs[:goal] || "fight",
      action: attrs[:action],
      utility: attrs[:utility],
      reasons: %{"items" => attrs[:reasons] || []},
      metadata: attrs[:metadata] || %{}
    })
  end

  test "reports combat concentration separately from noncombat outcomes", %{
    admin: admin,
    hero: hero,
    other: other
  } do
    audit(hero, "intent_selected", %{goal: "fight", utility: 0.91, reasons: ["danger"]})
    audit(hero, "intent_held", %{goal: "fight", utility: 0.87})
    audit(hero, "intent_switched", %{goal: "fight", utility: 0.9})
    audit(hero, "action_completed", %{goal: "fight", action: "fight"})
    audit(hero, "action_failed", %{goal: "fight", action: "fight"})
    audit(other, "intent_selected", %{goal: "rest", utility: 0.62})
    audit(other, "action_completed", %{goal: "rest", action: "rest"})

    body =
      conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7&limit=1") |> json_response(200)

    fight = Enum.find(body["intent_by_goal"], &(&1["goal"] == "fight"))

    assert fight == %{
             "goal" => "fight",
             "selected" => 1,
             "held" => 1,
             "switched" => 1,
             "avg_utility" => 0.893
           }

    assert %{"goal" => "fight", "action" => "fight", "completed" => 1, "failed" => 1} in body[
             "action_outcomes"
           ]

    assert %{"goal" => "rest", "action" => "rest", "completed" => 1, "failed" => 0} in body[
             "action_outcomes"
           ]

    assert length(body["recent_events"]) == 1
  end

  test "S-6: report exposes totals, event counts, timeline and anomalies", %{admin: admin, hero: hero} do
    for _ <- 1..8, do: audit(hero, "intent_selected", %{goal: "fight", utility: 0.9})
    for _ <- 1..4, do: audit(hero, "action_failed", %{goal: "fight", action: "fight"})
    audit(hero, "action_completed", %{goal: "fight", action: "fight"})

    body = conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7") |> json_response(200)

    assert body["totals"]["intents"] == 8
    assert body["totals"]["actions"] == 5
    assert body["totals"]["failed_actions"] == 4
    assert body["totals"]["failure_rate"] == 0.8

    counts = Map.new(body["event_counts"], fn row -> {row["event_type"], row["count"]} end)
    assert counts["intent_selected"] == 8
    assert counts["action_failed"] == 4
    # все типы присутствуют, даже нулевые — UI рисует стабильный набор
    assert counts["intent_held"] == 0
    assert map_size(counts) == 6

    assert is_list(body["timeline"])
    assert body["timeline"] != []

    # сбои 80% и перекос в одну цель → должны быть аномалии
    anomaly_kinds = Enum.map(body["anomalies"], & &1["kind"])
    assert "action_broken" in anomaly_kinds
    assert body["anomaly_summary"]["total"] == length(body["anomalies"])
    assert body["anomaly_summary"]["critical"] >= 1
  end

  test "S-6: filters narrow the report by event type, goal and hero", %{
    admin: admin,
    hero: hero,
    other: other
  } do
    audit(hero, "intent_selected", %{goal: "fight"})
    audit(hero, "action_completed", %{goal: "fight", action: "fight"})
    audit(other, "intent_selected", %{goal: "rest"})
    audit(other, "action_failed", %{goal: "rest", action: "rest"})

    by_type =
      conn_for(admin)
      |> get("/api/v1/admin/brain/stats?days=7&event_type=intent_selected")
      |> json_response(200)

    assert Enum.all?(by_type["recent_events"], &(&1["event_type"] == "intent_selected"))
    # event_counts — фиксированный список типов, а не map
    assert is_list(by_type["event_counts"])
    assert Enum.map(by_type["event_counts"], & &1["event_type"]) |> Enum.sort() ==
             ~w(action_completed action_failed action_started intent_held intent_selected intent_switched) |> Enum.sort()

    by_goal =
      conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7&goal=rest") |> json_response(200)

    assert Enum.map(by_goal["intent_by_goal"], & &1["goal"]) == ["rest"]
    assert Enum.all?(by_goal["recent_events"], &(&1["goal"] == "rest"))

    by_hero =
      conn_for(admin)
      |> get("/api/v1/admin/brain/stats?days=7&hero_id=#{other.id}")
      |> json_response(200)

    assert Enum.all?(by_hero["recent_events"], &(&1["hero"] == other.name))

    # мусорный UUID не должен валить запрос — фильтр просто игнорируется
    garbage = conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7&hero_id=not-a-uuid")
    assert garbage.status == 200

    # неизвестный event_type игнорируется, а не отдаёт пустоту молча
    unknown = conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7&event_type=hax")
    assert unknown.status == 200
    assert unknown |> json_response(200) |> Map.get("recent_events") |> length() == 4
  end

  test "S-6: search filter matches goal and action text", %{admin: admin, hero: hero} do
    audit(hero, "action_completed", %{goal: "explore", action: "explore"})
    audit(hero, "action_completed", %{goal: "fight", action: "fight"})

    body =
      conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7&q=expl") |> json_response(200)

    assert length(body["recent_events"]) == 1
    assert hd(body["recent_events"])["goal"] == "explore"
  end

  test "S-6: recent events include reasons and metadata, and offset paginates", %{
    admin: admin,
    hero: hero
  } do
    audit(hero, "intent_selected", %{goal: "fight", reasons: ["danger", "low_hp"]})
    audit(hero, "intent_selected", %{goal: "rest"})

    body = conn_for(admin) |> get("/api/v1/admin/brain/stats?days=7&limit=10") |> json_response(200)
    fight_row = Enum.find(body["recent_events"], &(&1["goal"] == "fight"))
    rest_row = Enum.find(body["recent_events"], &(&1["goal"] == "rest"))

    # reasons приходят распакованными из JSONB-обёртки {"items": [...]}
    assert fight_row["reasons"] == ["danger", "low_hp"]
    assert rest_row["reasons"] == []
    assert is_map(fight_row["metadata"])

    first =
      conn_for(admin)
      |> get("/api/v1/admin/brain/stats?days=7&limit=1&offset=0")
      |> json_response(200)

    second =
      conn_for(admin)
      |> get("/api/v1/admin/brain/stats?days=7&limit=1&offset=1")
      |> json_response(200)

    assert first["offset"] == 0
    assert second["offset"] == 1
    assert length(first["recent_events"]) == 1
    assert length(second["recent_events"]) == 1
    # страницы не пересекаются: второй запрос отдаёт другую запись
    refute hd(second["recent_events"])["goal"] == hd(first["recent_events"])["goal"]
  end

  test "S-6: export returns a markdown file with anomalies and summary", %{
    admin: admin,
    hero: hero
  } do
    for _ <- 1..6, do: audit(hero, "intent_selected", %{goal: "fight", utility: 0.9})
    for _ <- 1..4, do: audit(hero, "action_failed", %{goal: "fight", action: "fight"})

    resp = conn_for(admin) |> get("/api/v1/admin/brain/export?days=7")

    assert resp.status == 200
    assert get_resp_header(resp, "content-type") |> hd() =~ "text/markdown"
    assert get_resp_header(resp, "content-disposition") |> hd() =~ "attachment"
    assert get_resp_header(resp, "content-disposition") |> hd() =~ ".md"

    body = resp.resp_body
    assert body =~ "# Аналитика решений ИИ"
    assert body =~ "## Аномалии"
    assert body =~ "## Распределение целей"
    assert body =~ "## Исходы действий"
    assert body =~ "action_broken"
  end

  test "S-6: export supports json and csv formats", %{admin: admin, hero: hero} do
    audit(hero, "intent_selected", %{goal: "fight", utility: 0.9})
    audit(hero, "action_failed", %{goal: "fight", action: "fight"})

    json_resp = conn_for(admin) |> get("/api/v1/admin/brain/export?days=7&format=json")
    assert json_resp.status == 200
    assert get_resp_header(json_resp, "content-type") |> hd() =~ "application/json"
    assert get_resp_header(json_resp, "content-disposition") |> hd() =~ ".json"

    decoded = Jason.decode!(json_resp.resp_body)
    assert decoded["totals"]["intents"] == 1
    assert is_list(decoded["anomalies"])

    csv_resp = conn_for(admin) |> get("/api/v1/admin/brain/export?days=7&format=csv")
    assert csv_resp.status == 200
    assert get_resp_header(csv_resp, "content-type") |> hd() =~ "text/csv"
    assert csv_resp.resp_body =~ "section,kind,severity"
    assert csv_resp.resp_body =~ "action_outcome"
  end

  test "admin telemetry is not leaked to plain users", %{plain: plain} do
    assert conn_for(plain) |> get("/api/v1/admin/brain/stats") |> response(403)
    assert conn_for(plain) |> get("/api/v1/admin/brain/export") |> response(403)
    assert build_conn() |> get("/api/v1/admin/brain/stats") |> response(401)
    assert build_conn() |> get("/api/v1/admin/brain/export") |> response(401)
  end
end
