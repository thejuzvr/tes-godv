defmodule TesIdle.Game.Brain.IntentV2Test do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Game.{Brain.Graph, Brain.Intent, GameContext}
  alias TesIdle.Schemas.Hero

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  defp context(opts) do
    personality = %{
      bravery: 40,
      caution: 40,
      curiosity: Keyword.get(opts, :curiosity, 50),
      greed: Keyword.get(opts, :greed, 60),
      sociability: 20,
      tenacity: 20,
      patience: 20,
      dexterity: 20,
      empathy: 20
    }

    state_data = Keyword.get(opts, :state_data, %{})

    hero = %Hero{
      id: "00000000-0000-0000-0000-000000000001",
      name: "Намерение",
      race: "Nord",
      hero_class: "Warrior",
      game_day: 8,
      game_hour: 13.0,
      state: "exploring",
      hp: Keyword.get(opts, :hp, 100),
      max_hp: 100,
      gold: 20,
      skills: %{},
      personality: personality,
      state_data: Jason.encode!(state_data)
    }

    intent = %{
      "enabled" => true,
      "switch_margin" => Keyword.get(opts, :switch_margin, 0.08),
      "min_hold_decisions" => Keyword.get(opts, :min_hold_decisions, 2),
      "repeat_window" => Keyword.get(opts, :repeat_window, 5),
      "repeat_penalty" => Keyword.get(opts, :repeat_penalty, 0.025),
      "frustration_step" => 0.1,
      "frustration_max" => 0.3,
      "novelty" => Keyword.get(opts, :novelty, 0.0)
    }

    %GameContext{
      hero: hero,
      personality: personality,
      needs: %{hunger: 20, fatigue: Keyword.get(opts, :fatigue, 10), morale: 80},
      hour: 13.0,
      location_type: "wilderness",
      weather: "clear",
      world: %{"events" => [], "wars" => []},
      configs: %{
        "brain" => %{"enabled" => false, "intent" => intent},
        "needs_urgent" => %{"fatigue" => 75, "hp_ratio" => 0.5, "rest_boost" => 0.35}
      },
      inventory: [],
      memories: [],
      state_data: state_data,
      combat_state: Keyword.get(opts, :combat_state),
      travel_state: nil
    }
  end

  defp with_intent(goal, held, log \\ [], frustration \\ 0.0) do
    %{
      "brain" => %{
        "intent" => %{
          "goal" => to_string(goal),
          "held_decisions" => held,
          "frustration" => frustration
        },
        "decision_log" => Enum.map(log, &%{"goal" => to_string(&1)})
      }
    }
  end

  test "держит текущее намерение до min_hold_decisions" do
    ctx = context(state_data: with_intent(:loot, 1), curiosity: 50, greed: 60)
    [best | _] = Intent.evaluate(ctx)

    assert best.name == :loot
    assert Enum.any?(best.brain_reasons, &String.contains?(&1, "удержание намерения"))
  end

  test "переключается, когда преимущество превышает switch_margin" do
    ctx = context(state_data: with_intent(:loot, 3), curiosity: 100, greed: 0, switch_margin: 0.08)
    [best | _] = Intent.evaluate(ctx)

    assert best.name == :explore
    assert Enum.any?(best.brain_reasons, &String.contains?(&1, "смена намерения"))
  end

  test "срочный отдых прерывает минимальное удержание" do
    ctx = context(state_data: with_intent(:explore, 0), fatigue: 95)
    [best | _] = Intent.evaluate(ctx)

    assert best.name == :rest
    assert Enum.any?(best.brain_reasons, &String.contains?(&1, "критическая цель"))
  end

  test "анти-повтор штрафует часто выбранную цель" do
    state_data = with_intent(:explore, 3, [:explore, :explore, :explore])
    ctx = context(state_data: state_data, curiosity: 50, greed: 60, repeat_penalty: 0.1, switch_margin: 0.0)
    goals = Intent.evaluate(ctx)
    explore = Enum.find(goals, &(&1.name == :explore))

    assert hd(goals).name == :loot
    assert Enum.any?(explore.brain_reasons, &String.contains?(&1, "анти-повтор"))
  end

  test "tiny novelty детерминирована для героя и игрового часа" do
    ctx = context(novelty: 0.001)

    assert Intent.evaluate(ctx) == Intent.evaluate(ctx)
  end

  test "log_decision атомарно обновляет intent metadata и журнал" do
    ctx = context(state_data: with_intent(:loot, 2))
    goal = %TesIdle.Game.Goal{name: :explore, utility: 0.7, reason: "Исследование", brain_reasons: []}
    updated = Graph.log_decision(ctx.state_data, goal, ctx)

    assert updated["brain"]["intent"]["goal"] == "explore"
    assert updated["brain"]["intent"]["previous_goal"] == "loot"
    assert updated["brain"]["intent"]["switched"] == true
    assert updated["brain"]["intent"]["held_decisions"] == 1
    assert List.last(updated["brain"]["decision_log"])["goal"] == "explore"
  end

  test "record_outcome повышает только явную failure-фрустрацию и сбрасывает её при progress" do
    configs = %{"brain" => %{"intent" => %{"enabled" => true, "frustration_step" => 0.1, "frustration_max" => 0.25}}}
    state_data = with_intent(:explore, 2, [], 0.2)

    failed = Intent.record_outcome(state_data, :failure, configs)
    unknown = Intent.record_outcome(failed, %{}, configs)
    progressed = Intent.record_outcome(unknown, %{progress: true}, configs)

    assert failed["brain"]["intent"]["frustration"] == 0.25
    assert unknown["brain"]["intent"]["frustration"] == 0.25
    assert progressed["brain"]["intent"]["frustration"] == 0.0
  end
end
