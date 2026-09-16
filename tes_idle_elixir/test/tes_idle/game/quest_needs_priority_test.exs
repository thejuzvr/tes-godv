defmodule TesIdle.Game.QuestNeedsPriorityTest do
  @moduledoc """
  Фаза 2 (аудит поведения 2026-09): нужды важнее квеста.

  Проверки (юнит, Goal.base_goals — чистый Utility-слой):
    1. Квест с base 0.45 не выигрывает у rest/heal при критических нуждах
       (fatigue > 75 / hp < 50%) — urgent-режим режет квест на −0.3.
    2. Свежий герой: квест по-прежнему конкурентоспособен.
  """
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Quest, QuestStep, ActiveQuest}
  alias TesIdle.Game.{GameContext, Goal}
  alias TesIdle.Game.Brain.Genome

  # --- Хелперы ---------------------------------------------------------------

  defp hero(hp_ratio, state \\ "idle") do
    %TesIdle.Schemas.Hero{
      name: "Тест", race: "Nord", hero_class: "Warrior", game_day: 4, game_hour: 12.0,
      hp: trunc(100 * hp_ratio), max_hp: 100, gold: 30,
      state: state,
      skills: %{},
      brain_hash: Genome.brain_hash("quest-urgent-user"),
      personality: %{bravery: 50, curiosity: 50, greed: 50, sociability: 50,
                     tenacity: 50, caution: 50, patience: 50, dexterity: 50, empathy: 50},
      state_data: "{}",
    }
    |> Map.put(:sp, 10)
    |> Map.put(:max_sp, 100)
  end

  defp ctx(h, fatigue, quest) do
    %GameContext{
      hero: h,
      personality: h.personality,
      needs: %{hunger: 40, fatigue: fatigue, morale: 60},
      hour: 12.0,
      location_type: "wilderness",
      weather: "clear",
      world: %{"events" => [], "wars" => []},
      configs: %{},
      inventory: [],
      memories: [],
      active_quest: quest,
    }
  end

  defp goal_by(goals, name), do: Enum.find(goals, &(&1.name == name))

  # Квест в БД — eval_quest/query ходит в Repo (step_type, name).
  # ActiveQuest НЕ вставляем (hero_id NOT NULL, герой — чистая структура) —
  # ctx.active_quest достаточно структуры с quest_id: Goal делает только
  # SELECT по quest_id, INSERT не нужен.
  defp seed_quest do
    suffix = System.unique_integer([:positive])

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    quest =
      Repo.insert!(%Quest{
        name: "Тестовый квест #{suffix}",
        xp_reward: 50,
        gold_reward: 30,
        is_active: true,
      })

    Repo.insert!(%QuestStep{quest_id: quest.id, step_order: 1,
      description: "Найди покой", step_type: "explore", target_count: 1})

    %ActiveQuest{quest_id: quest.id, current_step: 1, current_progress: 0}
  end

  test "критическая усталость: rest бьёт квест" do
    aq = seed_quest()
    rested_hero = hero(1.0)
    fresh_hero = hero(1.0)

    # Уставший герой: rest получает urgent-бонус +0.35, quest режется −0.3
    urgent_goals = Goal.base_goals(ctx(rested_hero, 85, aq))
    calm_goals = Goal.base_goals(ctx(fresh_hero, 30, aq))

    rest_urgent = goal_by(urgent_goals, :rest)
    rest_calm = goal_by(calm_goals, :rest)
    quest_urgent = goal_by(urgent_goals, :complete_quest)
    quest_calm = goal_by(calm_goals, :complete_quest)

    assert rest_urgent, "при fatigue 85 rest должен быть в списке целей"
    assert rest_urgent.utility > rest_calm.utility + 0.2, "urgent-бонус применён"
    assert quest_urgent.utility < quest_calm.utility - 0.25, "urgent-режим режет квест"

    # Итоговый порядок: rest выше quest у уставшего героя
    assert rest_urgent.utility > quest_urgent.utility
  end

  test "низкий HP: heal получает приоритет над квестом" do
    aq = seed_quest()
    wounded = hero(0.4)

    goals = Goal.base_goals(ctx(wounded, 30, aq))
    heal = goal_by(goals, :heal)
    quest = goal_by(goals, :complete_quest)

    assert heal, "hp 40% → heal активен"
    assert heal.utility > quest.utility, "heal бьёт quest при hp < 50%"
  end

  test "свежий герой: квест по-прежнему ведёт (нет urgent-режима)" do
    aq = seed_quest()
    fresh = hero(1.0)

    goals = Goal.base_goals(ctx(fresh, 30, aq))
    quest = goal_by(goals, :complete_quest)

    assert quest.utility > 0.4, "без критических нужд квест силён"
  end
end
