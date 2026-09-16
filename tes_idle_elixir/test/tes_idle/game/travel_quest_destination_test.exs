defmodule TesIdle.Game.TravelQuestDestinationTest do
  @moduledoc """
  Регрессия 2026-09: TravelAction с активным квестом падал Enum.EmptyError,
  когда фильтр назначений по типу шага квеста давал пустой список
  (wanted_dest = nil-фоллбек был мёртв — краш происходил раньше него).

  Симптом: тик героя абортится целиком, воркер глотает ошибку — хроника
  молчит часами, герой «застревает» (реальный кейс: Джозец, дыры 125+ мин).
  """
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Location, User, Quest, QuestStep, ActiveQuest}
  alias TesIdle.Game.{Actions.TravelAction, GameContext}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_trav_#{suffix}",
        email: "qa_trav_#{suffix}@test.gg", password_hash: "x"})

    cities = Repo.all(from l in Location, where: l.location_type == "city")
    city = Enum.find(cities, &(&1.name == "Вайтран")) || List.first(cities)

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "QA-Путник",
        race: "Nord",
        hero_class: "Warrior",
        level: 5,
        hp: 100,
        max_hp: 100,
        sp: 50,
        max_sp: 100,
        gold: 500,
        state: "idle",
        location_id: city.id,
        personality: %{"bravery" => 50, "curiosity" => 50, "greed" => 50, "sociability" => 50,
          "tenacity" => 50, "caution" => 50, "patience" => 50, "dexterity" => 50, "empathy" => 50},
        state_data: "{}",
        brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id),
      })

    %{user: user, hero: hero, city: city}
  end

  defp ctx_for(hero, city, active_quest) do
    hero = Repo.get!(Hero, hero.id)

    %GameContext{
      hero: hero,
      location: city,
      location_type: city.location_type,
      inventory: [],
      equipment: %{},
      needs: %{hunger: hero.hunger, fatigue: hero.fatigue, morale: hero.morale},
      configs: %{},
      personality: hero.personality,
      memories: [],
      hour: hero.game_hour,
      weather: "clear",
      world: %{},
      combat_state: nil,
      travel_state: nil,
      active_quest: active_quest,
      state_data: %{},
    }
  end

  test "квест-шаг без подходящих локаций не роняет выбор назначения", %{hero: hero, city: city} do
    # step_type "talk" не входит в маппинг quest_wanted_types → wanted = []
    # → раньше: Enum.filter → [] → Enum.random([]) → Enum.EmptyError (тик абортится)
    quest =
      Repo.insert!(%Quest{
        name: "Квест без адресата #{System.unique_integer([:positive])}",
        xp_reward: 10,
        gold_reward: 5,
        is_active: true,
      })

    Repo.insert!(%QuestStep{quest_id: quest.id, step_order: 1,
      description: "Поговори с кем-нибудь", step_type: "talk", target_count: 1})

    aq = Repo.insert!(%ActiveQuest{hero_id: hero.id, quest_id: quest.id,
      current_step: 1, current_progress: 0})

    assert {:ok, result} = TravelAction.execute(ctx_for(hero, city, aq))
    assert result.state_to == "traveling"
    assert result.state_data_update["travel"]["destination_id"]
  end

  test "без квеста назначение выбирается как раньше", %{hero: hero, city: city} do
    assert {:ok, result} = TravelAction.execute(ctx_for(hero, city, nil))
    assert result.state_to == "traveling"
  end
end
