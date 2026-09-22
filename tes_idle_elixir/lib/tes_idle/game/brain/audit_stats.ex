defmodule TesIdle.Game.Brain.AuditStats do
  @moduledoc """
  Read-only aggregate queries for long-lived Brain audit telemetry.

  S-6: помимо исходных разрезов модуль собирает **аналитическую сводку**
  (`analysis/1`) — объёмы по типам событий, таймлайн по дням, фильтры и набор
  аномалий от `Brain.Anomalies`. Всё это отдаётся в админку и в файл выгрузки.
  """

  import Ecto.Query
  alias TesIdle.Game.Brain.Anomalies
  alias TesIdle.Repo
  alias TesIdle.Schemas.{DecisionAuditEvent, Hero}

  @default_days 30
  @default_limit 50
  @max_days 365
  @max_limit 500
  @max_offset 100_000

  @event_types ~w(intent_selected intent_held intent_switched action_started action_completed action_failed)

  @doc "Типы событий аудита — для фильтров UI."
  def event_types, do: @event_types

  def report(params) do
    %{from: since_dt, limit: limit, offset: offset} = parse_params(params)
    filters = parse_filters(params)
    scoped = scope(since_dt, filters)

    %{
      range: %{from: NaiveDateTime.to_iso8601(since_dt), days: days_until(since_dt)},
      limit: limit,
      offset: offset,
      filters: filters,
      intent_by_goal: intent_by_goal(scoped),
      action_outcomes: action_outcomes(scoped),
      heroes: heroes(scoped),
      recent_events: recent_events(scoped, limit, offset),
      goals: distinct_goals(since_dt)
    }
  end

  @doc """
  Полная аналитическая сводка: разрезы + объёмы по типам + таймлайн + аномалии.
  Именно её рендерит панель «Аудит решений» и выгружает файл аналитики.
  """
  def analysis(params) do
    report = report(params)
    %{from: since_dt} = parse_params(params)
    scoped = scope(since_dt, report.filters)

    intent_by_goal = report.intent_by_goal
    action_outcomes = report.action_outcomes
    heroes = report.heroes
    event_counts = event_counts(scoped)

    totals =
      totals(
        Enum.reduce(intent_by_goal, %{selected: 0, held: 0, switched: 0}, fn row, acc ->
          %{
            selected: acc.selected + row.selected,
            held: acc.held + row.held,
            switched: acc.switched + row.switched
          }
        end),
        Enum.reduce(action_outcomes, %{completed: 0, failed: 0}, fn row, acc ->
          %{completed: acc.completed + row.completed, failed: acc.failed + row.failed}
        end),
        event_counts,
        length(heroes),
        length(intent_by_goal)
      )

    analysis = %{
      totals: totals,
      intent_by_goal: intent_by_goal,
      action_outcomes: action_outcomes,
      heroes: heroes
    }

    anomalies = Anomalies.detect(analysis)

    %{
      range: report.range,
      limit: report.limit,
      offset: report.offset,
      filters: report.filters,
      goals: report.goals,
      event_types: @event_types,
      intent_by_goal: intent_by_goal,
      action_outcomes: action_outcomes,
      heroes: heroes,
      recent_events: report.recent_events,
      event_counts: event_counts,
      totals: totals,
      timeline: timeline(since_dt, report.filters),
      anomalies: anomalies,
      anomaly_summary: Anomalies.summary(anomalies),
      total_decisions: totals.intents
    }
  end

  # ─── Фильтры ─────────────────────────────────────────

  # scope принимает "от какого времени" и сами фильтры, а не готовый query —
  # иначе вызов с датой случайно превращался в Ecto.Queryable по NaiveDateTime.
  defp scope(since_dt, filters) do
    base = from e in DecisionAuditEvent, where: e.created_at >= ^since_dt

    Enum.reduce(filters, base, fn
      {:event_type, value}, query when is_binary(value) ->
        where(query, [e], e.event_type == ^value)

      {:goal, value}, query when is_binary(value) ->
        where(query, [e], e.goal == ^value)

      {:hero_id, value}, query when is_binary(value) ->
        where(query, [e], e.hero_id == ^value)

      {:q, value}, query when is_binary(value) ->
        pattern = "%#{value}%"
        where(query, [e], ilike(e.goal, ^pattern) or ilike(e.action, ^pattern))

      _, query ->
        query
    end)
  end

  defp parse_filters(params) do
    %{
      event_type: filter_value(params["event_type"], @event_types),
      goal: blank(params["goal"]),
      hero_id: uuid(params["hero_id"]),
      q: blank(params["q"])
    }
  end

  defp filter_value(value, allowed) do
    case blank(value) do
      nil -> nil
      candidate -> if candidate in allowed, do: candidate, else: nil
    end
  end

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank(_), do: nil

  # Отфильтрованный по UUID аргумент не должен ронять запрос — иначе 500 на мусоре.
  defp uuid(value) do
    case blank(value) do
      nil ->
        nil

      candidate ->
        case Ecto.UUID.cast(candidate) do
          {:ok, uuid} -> uuid
          :error -> nil
        end
    end
  end

  # ─── Разрезы ─────────────────────────────────────────

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
          hero_id: h.id,
          hero: h.name,
          level: h.level,
          events: count(e.id),
          selected: filter(count(e.id), e.event_type == "intent_selected"),
          held: filter(count(e.id), e.event_type == "intent_held"),
          switched: filter(count(e.id), e.event_type == "intent_switched"),
          completed: filter(count(e.id), e.event_type == "action_completed"),
          failed: filter(count(e.id), e.event_type == "action_failed"),
          avg_utility: avg(e.utility)
        }
    )
    |> Enum.map(&Map.update!(&1, :avg_utility, fn v -> round_number(v) end))
  end

  defp recent_events(base, limit, offset) do
    Repo.all(
      from e in base,
        join: h in Hero,
        on: h.id == e.hero_id,
        order_by: [desc: e.created_at, desc: e.id],
        limit: ^limit,
        offset: ^offset,
        select: %{
          hero: h.name,
          hero_id: e.hero_id,
          game_day: e.game_day,
          game_hour: e.game_hour,
          event_type: e.event_type,
          goal: e.goal,
          action: e.action,
          utility: e.utility,
          reasons: e.reasons,
          metadata: e.metadata,
          created_at: e.created_at
        }
    )
    |> Enum.map(&normalize_event/1)
  end

  # Причины лежат в JSONB под стабильным ключом `items`; metadata отдаём как есть.
  defp normalize_event(event) do
    %{
      event
      | reasons: get_in(event.reasons || %{}, ["items"]) || [],
        metadata: event.metadata || %{}
    }
  end

  defp event_counts(base) do
    counts =
      Repo.all(
        from e in base,
          group_by: e.event_type,
          select: {e.event_type, count(e.id)}
      )

    counts
    |> Map.new()
    |> then(fn map ->
      Enum.map(@event_types, fn type -> %{event_type: type, count: Map.get(map, type, 0)} end)
    end)
  end

  defp timeline(since_dt, filters) do
    base = scope(since_dt, filters)

    Repo.all(
      from e in base,
        group_by: fragment("date_trunc('day', ?)", e.created_at),
        order_by: [asc: fragment("date_trunc('day', ?)", e.created_at)],
        select: %{
          bucket: fragment("date_trunc('day', ?)", e.created_at),
          intent:
            filter(
              count(e.id),
              e.event_type in ["intent_selected", "intent_held", "intent_switched"]
            ),
          action: filter(count(e.id), e.event_type == "action_completed"),
          failed: filter(count(e.id), e.event_type == "action_failed")
        }
    )
  end

  defp distinct_goals(since_dt) do
    Repo.all(
      from e in DecisionAuditEvent,
        where: e.created_at >= ^since_dt,
        where: not is_nil(e.goal),
        distinct: true,
        select: e.goal,
        order_by: [asc: e.goal]
    )
  end

  # ─── Сводка ──────────────────────────────────────────

  defp totals(intents, actions, event_counts, heroes, distinct_goals) do
    events = Enum.reduce(event_counts, 0, &(&1.count + &2))
    intent_total = intents.selected + intents.held + intents.switched
    action_total = actions.completed + actions.failed

    %{
      events: events,
      intents: intent_total,
      actions: action_total,
      failed_actions: actions.failed,
      distinct_goals: distinct_goals,
      distinct_actions: 0,
      heroes: heroes,
      failure_rate: ratio(actions.failed, action_total),
      switch_rate: ratio(intents.switched, intent_total),
      hold_rate: ratio(intents.held, intent_total)
    }
  end

  defp ratio(_part, 0), do: 0.0
  defp ratio(part, whole), do: Float.round(part / whole, 4)

  # ─── Параметры ───────────────────────────────────────

  defp parse_params(params) do
    days = bounded(params["days"], @default_days, 1, @max_days)
    limit = bounded(params["limit"], @default_limit, 1, @max_limit)
    offset = bounded(params["offset"], 0, 0, @max_offset)
    %{from: NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400, :second), limit: limit, offset: offset}
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
