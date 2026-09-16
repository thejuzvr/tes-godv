defmodule TesIdle.Game.Brain.IntentIntegrationTest do
  @moduledoc "S-2-T: ядро решений с БД — дракон разводит храбрых и осторожных при живом монстре."
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Game.Brain.Intent
  alias TesIdle.Schemas.{Hero, Location, Monster, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])

    user = Repo.insert!(%User{username: "qa_s2_#{suffix}",
      email: "qa_s2_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    location = Repo.insert!(%Location{
      name: "QA Драконье поле #{suffix}",
      location_type: "wilderness",
      region: "Скайрим",
      danger_level: "Средняя",
      min_level: 1, max_level: 10,
      has_shop: false, has_inn: false,
      weather: "Ясно",
      flags: %{},
    })

    _monster = Repo.insert!(%Monster{
      name: "QA Дракончик",
      hp: 30, attack_min: 2, attack_max: 5, defense: 1,
      min_level: 1, max_level: 5,
      xp_reward: 20, gold_min: 5, gold_max: 12,
      is_active: true, location_id: location.id,
    })

    %{user: user, location: location}
  end

  test "дракон: храбрый хочет боя, осторожный в сторону", %{user: user, location: location} do
    brave = hero_for(user, location, %{bravery: 85, caution: 15, curiosity: 50, greed: 40,
      sociability: 50, tenacity: 50, patience: 50, dexterity: 50, empathy: 50})
    timid = hero_for(user, location, %{bravery: 15, caution: 85, curiosity: 50, greed: 40,
      sociability: 50, tenacity: 50, patience: 50, dexterity: 50, empathy: 50})

    dragon_world = %{"events" => [%{"type" => "dragon", "ttl" => 10}], "wars" => [],
                     "density" => %{}, "prices" => %{}}

    brave_goals = Intent.evaluate(ctx_for(brave, location, dragon_world))
    timid_goals = Intent.evaluate(ctx_for(timid, location, dragon_world))

    brave_fight = Enum.find(brave_goals, &(&1.name == :fight))
    timid_fight = Enum.find(timid_goals, &(&1.name == :fight))

    assert brave_fight, "храбрый с монстром рядом должен оценивать бой"
    assert timid_fight, "осторожный тоже может драться, но слабее"
    assert brave_fight.utility > timid_fight.utility + 0.05,
           "храбрый: #{Float.round(brave_fight.utility, 3)} vs осторожный: #{Float.round(timid_fight.utility, 3)}"
    assert Enum.any?(brave_fight.brain_reasons, &String.contains?(&1, "дракон"))
  end

  defp hero_for(user, location, personality) do
    Repo.insert!(%Hero{
      user_id: user.id,
      name: "QA Ядро",
      race: "Nord", hero_class: "Warrior",
      level: 1, hp: 100, max_hp: 100, mp: 20, max_mp: 20, sp: 40, max_sp: 80,
      attack: 5, defense: 3, gold: 50, xp: 0, xp_to_next: 100,
      state: "idle", mood: 60.0, hunger: 40.0, fatigue: 30.0, morale: 60.0,
      soul_energy: 50.0, max_soul_energy: 100.0,
      game_hour: 12.0, game_day: 5, game_era: "4E",
      location_id: location.id,
      brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id),
      personality: personality,
      skills: %{},
      state_data: "{}",
    })
    |> then(&Repo.get!(Hero, &1.id))
  end

  defp ctx_for(hero, location, world) do
    %TesIdle.Game.GameContext{
      hero: hero,
      location: location,
      location_type: location.location_type,
      inventory: [],
      equipment: %{},
      needs: %{hunger: hero.hunger, fatigue: hero.fatigue, morale: hero.morale},
      configs: %{},
      personality: hero.personality,
      memories: [],
      hour: hero.game_hour,
      weather: "clear",
      world: world,
      combat_state: nil,
      travel_state: nil,
      active_quest: nil,
      state_data: %{},
    }
  end
end
