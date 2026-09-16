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
    refute Map.has_key?(hd(body["recent_events"]), "metadata")
    refute Map.has_key?(hd(body["recent_events"]), "reasons")
  end

  test "admin telemetry is not leaked to plain users", %{plain: plain} do
    assert conn_for(plain) |> get("/api/v1/admin/brain/stats") |> response(403)
    assert build_conn() |> get("/api/v1/admin/brain/stats") |> response(401)
  end
end
