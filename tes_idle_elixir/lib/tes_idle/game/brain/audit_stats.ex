defmodule TesIdle.Game.Brain.AuditStats do
  @moduledoc "Read-only aggregate queries for long-lived Brain audit telemetry."

  import Ecto.Query
  alias TesIdle.Repo
  alias TesIdle.Schemas.{DecisionAuditEvent, Hero}

  @default_days 30
  @default_limit 50
  @max_days 365
  @max_limit 200

  def report(params) do
    %{from: from, limit: limit} = parse_params(params)
    base = from e in DecisionAuditEvent, where: e.created_at >= ^from

    %{
      range: %{from: NaiveDateTime.to_iso8601(from), days: days_until(from)},
      # Query parameters are bounded, allowing safe dashboard pagination.
      limit: limit,
      intent_by_goal: intent_by_goal(base),
      action_outcomes: action_outcomes(base),
      heroes: heroes(base),
      recent_events: recent_events(base, limit)
    }
  end

  defp intent_by_goal(base) do
    Repo.all(
      from e in base,
        where: e.event_type in ["intent_selected", "intent_held", "intent_switched"],
        group_by: e.goal,
        order_by: [desc: count(e.id), asc: e.goal],
        select: %{
          goal: e.goal,
          selected: filter(count(e.id), e.event_type == "intent_selected"),
          held: filter(count(e.id), e.event_type == "intent_held"),
          switched: filter(count(e.id), e.event_type == "intent_switched"),
          avg_utility: avg(e.utility)
        }
    )
    |> Enum.map(&Map.update!(&1, :avg_utility, fn v -> round_number(v) end))
  end

  defp action_outcomes(base) do
    Repo.all(
      from e in base,
        where: e.event_type in ["action_completed", "action_failed"],
        group_by: [e.goal, e.action],
        order_by: [desc: count(e.id), asc: e.goal, asc: e.action],
        select: %{
          goal: e.goal,
          action: e.action,
          completed: filter(count(e.id), e.event_type == "action_completed"),
          failed: filter(count(e.id), e.event_type == "action_failed")
        }
    )
  end

  defp heroes(base) do
    Repo.all(
      from e in base,
        join: h in Hero,
        on: h.id == e.hero_id,
        group_by: [h.id, h.name, h.level],
        order_by: [desc: count(e.id), asc: h.name],
        select: %{
          hero: h.name,
          level: h.level,
          events: count(e.id),
          selected: filter(count(e.id), e.event_type == "intent_selected"),
          held: filter(count(e.id), e.event_type == "intent_held"),
          switched: filter(count(e.id), e.event_type == "intent_switched"),
          completed: filter(count(e.id), e.event_type == "action_completed"),
          failed: filter(count(e.id), e.event_type == "action_failed")
        }
    )
  end

  defp recent_events(base, limit) do
    Repo.all(
      from e in base,
        join: h in Hero,
        on: h.id == e.hero_id,
        order_by: [desc: e.created_at, desc: e.id],
        limit: ^limit,
        select: %{
          hero: h.name,
          game_day: e.game_day,
          game_hour: e.game_hour,
          event_type: e.event_type,
          goal: e.goal,
          action: e.action,
          utility: e.utility,
          created_at: e.created_at
        }
    )
  end

  defp parse_params(params) do
    days = bounded(params["days"], @default_days, 1, @max_days)
    limit = bounded(params["limit"], @default_limit, 1, @max_limit)
    %{from: NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400, :second), limit: limit}
  end

  defp bounded(value, _default, lower, upper) when is_integer(value),
    do: Kernel.min(Kernel.max(value, lower), upper)

  defp bounded(value, default, min, max) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> bounded(number, default, min, max)
      _ -> default
    end
  end

  defp bounded(_, default, _, _), do: default

  defp days_until(from),
    do: Kernel.max(1, NaiveDateTime.diff(NaiveDateTime.utc_now(), from, :second) |> div(86_400))

  defp round_number(nil), do: 0.0
  defp round_number(value), do: Float.round(value * 1.0, 3)
end
