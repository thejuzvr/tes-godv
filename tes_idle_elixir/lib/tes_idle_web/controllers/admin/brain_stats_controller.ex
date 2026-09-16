defmodule TesIdleWeb.Admin.BrainStatsController do
  @moduledoc "Long-lived, paginated Brain decision telemetry for administrators."

  use TesIdleWeb, :controller

  alias TesIdle.Game.Brain.AuditStats

  def show(conn, params) do
    report = AuditStats.report(params)

    json(conn, %{
      range: report.range,
      limit: report.limit,
      # Intent telemetry diagnoses concentration (not state_data's capped decision_log).
      intent_by_goal: report.intent_by_goal,
      action_outcomes: report.action_outcomes,
      heroes: report.heroes,
      recent_events: report.recent_events,
      # Compatibility aliases for consumers of the original admin shape.
      total_decisions:
        Enum.sum(Enum.map(report.intent_by_goal, &(&1.selected + &1.held + &1.switched))),
      by_goal: report.intent_by_goal,
      by_hero: report.heroes
    })
  end
end
