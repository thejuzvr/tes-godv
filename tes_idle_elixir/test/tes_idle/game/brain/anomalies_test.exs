defmodule TesIdle.Game.Brain.AnomaliesTest do
  @moduledoc "S-6: пороговые правила детектора аномалий (чистые, без БД)."
  use ExUnit.Case, async: true

  alias TesIdle.Game.Brain.Anomalies

  defp goal(name, selected, held, switched, utility) do
    %{goal: name, selected: selected, held: held, switched: switched, avg_utility: utility}
  end

  defp outcome(goal_name, action, completed, failed) do
    %{goal: goal_name, action: action, completed: completed, failed: failed}
  end

  defp hero(name, events, selected, held, switched, completed, failed) do
    %{
      hero: name,
      level: 3,
      events: events,
      selected: selected,
      held: held,
      switched: switched,
      completed: completed,
      failed: failed
    }
  end

  defp totals(overrides) do
    Map.merge(
      %{
        events: 100,
        intents: 100,
        actions: 50,
        failed_actions: 0,
        distinct_goals: 4,
        distinct_actions: 6,
        heroes: 2,
        failure_rate: 0.0,
        switch_rate: 0.2,
        hold_rate: 0.3
      },
      overrides
    )
  end

  defp analysis(overrides) do
    Map.merge(
      %{totals: totals(%{}), intent_by_goal: [], action_outcomes: [], heroes: []},
      overrides
    )
  end

  defp kinds(anomalies), do: Enum.map(anomalies, & &1.kind)

  test "balanced decisions produce no anomalies" do
    result =
      Anomalies.detect(
        analysis(%{
          intent_by_goal: [
            goal("explore", 20, 10, 5, 0.7),
            goal("fight", 18, 8, 4, 0.6),
            goal("rest", 10, 5, 0, 0.4)
          ],
          action_outcomes: [
            outcome("explore", "explore", 20, 1),
            outcome("fight", "fight", 18, 2)
          ],
          heroes: [
            hero("A", 50, 30, 15, 5, 20, 1),
            hero("B", 50, 28, 17, 5, 18, 2)
          ]
        })
      )

    assert result == []
  end

  test "concentration above 60% warns, above 80% is critical" do
    warn =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{intents: 100, switch_rate: 0.2}),
          intent_by_goal: [goal("fight", 55, 10, 0, 0.9), goal("rest", 20, 10, 5, 0.4)]
        })
      )

    assert "goal_dominance" in kinds(warn)

    critical =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{intents: 100, switch_rate: 0.2}),
          intent_by_goal: [goal("fight", 85, 5, 0, 0.9), goal("rest", 10, 0, 0, 0.4)]
        })
      )

    assert "goal_starvation" in kinds(critical)
    refute "goal_dominance" in kinds(critical)
  end

  test "high switch rate is flagged as thrashing" do
    thrashed =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{intents: 100, switch_rate: 0.62}),
          intent_by_goal: [goal("fight", 20, 10, 40, 0.6), goal("rest", 10, 10, 10, 0.5)]
        })
      )

    assert "intent_thrashing" in kinds(thrashed)
  end

  test "a goal held too long is flagged as stuck" do
    stuck =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{intents: 100, switch_rate: 0.05}),
          intent_by_goal: [
            goal("explore", 2, 90, 3, 0.7),
            goal("rest", 3, 1, 1, 0.5)
          ]
        })
      )

    assert "intent_stuck" in kinds(stuck)
  end

  test "an action that always fails is critical" do
    broken =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{actions: 20, failed_actions: 12, failure_rate: 0.6}),
          intent_by_goal: [goal("fight", 20, 10, 5, 0.6)],
          action_outcomes: [
            outcome("fight", "fight", 2, 10),
            outcome("rest", "rest", 10, 0)
          ]
        })
      )

    assert "action_broken" in kinds(broken)

    broken_anomaly = Enum.find(broken, &(&1.kind == "action_broken"))
    assert broken_anomaly.severity == :critical
    assert broken_anomaly.action == "fight"
    assert broken_anomaly.value > broken_anomaly.threshold
  end

  test "moderate failure rate warns without critical" do
    fragile =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{actions: 20, failed_actions: 6, failure_rate: 0.3}),
          intent_by_goal: [goal("fight", 20, 10, 5, 0.6)],
          action_outcomes: [outcome("fight", "fight", 14, 6)]
        })
      )

    assert "action_fragile" in kinds(fragile)
    refute "action_broken" in kinds(fragile)
  end

  test "low event volume suppresses rate-based rules" do
    # Все смены намерений, но событий мало — правило не должно сработать.
    quiet =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{events: 4, intents: 4, actions: 1, switch_rate: 1.0}),
          intent_by_goal: [goal("fight", 0, 0, 4, 0.6)]
        })
      )

    refute "intent_thrashing" in kinds(quiet)
  end

  test "one hero owning nearly all events flags hero silence" do
    silent =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{events: 100, heroes: 3}),
          intent_by_goal: [goal("explore", 30, 20, 10, 0.6)],
          heroes: [
            hero("Talker", 95, 40, 40, 15, 10, 2),
            hero("Mute", 3, 1, 1, 1, 1, 0),
            hero("Quiet", 2, 1, 1, 0, 1, 0)
          ]
        })
      )

    assert "hero_silence" in kinds(silent)
    assert Enum.find(silent, &(&1.kind == "hero_silence")).hero == "Talker"
  end

  test "near-identical utilities are reported as info" do
    flat =
      Anomalies.detect(
        analysis(%{
          intent_by_goal: [
            goal("explore", 20, 10, 5, 0.501),
            goal("fight", 20, 10, 5, 0.500),
            goal("rest", 20, 10, 5, 0.499)
          ]
        })
      )

    assert "utility_flat" in kinds(flat)
    assert Enum.find(flat, &(&1.kind == "utility_flat")).severity == :info
  end

  test "anomalies are sorted critical first and summary counts severities" do
    mixed =
      Anomalies.detect(
        analysis(%{
          totals: totals(%{intents: 100, switch_rate: 0.62}),
          intent_by_goal: [
            goal("fight", 90, 4, 2, 0.9),
            goal("rest", 1, 1, 1, 0.4)
          ],
          action_outcomes: [outcome("fight", "fight", 1, 9)]
        })
      )

    severities = Enum.map(mixed, & &1.severity)
    assert hd(severities) == :critical

    summary = Anomalies.summary(mixed)
    assert summary.total == length(mixed)
    assert summary.critical >= 1
    assert summary.critical + summary.warning + summary.info == summary.total
  end

  test "empty analysis yields no anomalies and a zeroed summary" do
    result =
      Anomalies.detect(%{totals: %{events: 0, intents: 0, actions: 0}, intent_by_goal: [], action_outcomes: [], heroes: []})

    assert result == []
    assert Anomalies.summary(result) == %{critical: 0, warning: 0, info: 0, total: 0}
  end
end
