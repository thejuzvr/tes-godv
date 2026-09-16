defmodule TesIdle.Game.FSMStage0RegressionTest do
  use ExUnit.Case, async: false

  alias TesIdle.Game.{FSMExecutor, GameContext, Memory}
  alias TesIdle.Game.Actions.{FishingAction, MiningAction, SocialAction, TravelAction}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Location, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "stage0_#{suffix}",
        email: "stage0_#{suffix}@test.gg",
        password_hash: "x"
      })

    origin = location!("Stage0 Берег #{suffix}", "wilderness", %{"water" => true})
    destination = location!("Stage0 Город #{suffix}", "city", %{})

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Stage0 Герой",
        race: "Nord",
        hero_class: "Warrior",
        level: 5,
        hp: 100,
        max_hp: 100,
        sp: 50,
        max_sp: 100,
        gold: 100,
        state: "idle",
        location_id: origin.id,
        personality: personality(),
        skills: %{},
        state_data: "{}",
        brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id)
      })

    %{hero: hero, origin: origin, destination: destination}
  end

  test "terminal fishing declares completion and advances its plan", %{hero: hero, origin: origin} do
    state_data = %{
      "fishing" => %{"ticks_left" => 1, "total_ticks" => 1},
      "plan" => plan([FishingAction])
    }

    hero = save_state(hero, "fishing", state_data)
    {:ok, FishingAction, result, fsm_state_data} = FSMExecutor.tick(ctx(hero, origin))

    assert result.activity_complete == true
    assert result.state_data_update["fishing"] == nil
    refute Map.has_key?(fsm_state_data, "plan")
  end

  test "terminal mining declares completion and advances its plan", %{hero: hero, origin: origin} do
    state_data = %{
      "mining" => %{"ticks_left" => 1, "total_ticks" => 1},
      "plan" => plan([MiningAction])
    }

    hero = save_state(hero, "mining", state_data)
    {:ok, MiningAction, result, fsm_state_data} = FSMExecutor.tick(ctx(hero, origin))

    assert result.activity_complete == true
    assert result.state_data_update["mining"] == nil
    refute Map.has_key?(fsm_state_data, "plan")
  end

  test "plan travel resumes through travel branch and advances only on arrival", %{
    hero: hero,
    origin: origin,
    destination: destination
  } do
    travel = %{
      "destination_id" => to_string(destination.id),
      "destination_name" => destination.name,
      "ticks_left" => 2,
      "total_ticks" => 2
    }

    hero = save_state(hero, "traveling", %{"travel" => travel, "plan" => plan([TravelAction])})
    {:ok, TravelAction, progress, progress_sd} = FSMExecutor.tick(ctx(hero, origin))

    assert progress.state_to == "traveling"
    assert progress_sd["travel"]["ticks_left"] == 1
    assert progress_sd["plan"]["current_step"] == 0

    hero = save_state(hero, "traveling", progress_sd)
    {:ok, TravelAction, arrived, arrived_sd} = FSMExecutor.tick(ctx(hero, origin))

    assert arrived.context["travel_arrived"] == true
    assert arrived.context["destination_name"] == destination.name
    assert arrived.location_change == destination.id
    refute Map.has_key?(arrived_sd, "travel")
    refute Map.has_key?(arrived_sd, "plan")
  end

  test "jail discards the interrupted crime plan before and after release", %{
    hero: hero,
    origin: origin
  } do
    jail = %{
      "mode" => "serve",
      "ticks_left" => 1,
      "total_ticks" => 1,
      "reason" => "кража",
      "location_id" => to_string(origin.id)
    }

    crime_plan = plan([TesIdle.Game.Actions.StealingAction])
    hero = save_state(hero, "jailed", %{"jail" => jail, "plan" => crime_plan})

    {:ok, TesIdle.Game.Actions.JailAction, result, state_data} =
      FSMExecutor.tick(ctx(hero, origin))

    assert result.state_to == "exploring"
    refute Map.has_key?(state_data, "jail")
    refute Map.has_key?(state_data, "plan")
  end

  test "memory helpers are pure and preserve caller state", %{hero: hero} do
    original = %{"plan" => %{"goal" => "explore"}}
    updated = Memory.add_travel(%{hero | state_data: Jason.encode!(original)}, "Вайтран")

    assert updated["plan"] == original["plan"]
    assert List.last(updated["memories"])["destination"] == "Вайтран"
    assert Repo.reload!(hero).state_data == "{}"
  end

  test "memory tracking records literal arrival, skips unknown companion, and names max-round outcome",
       %{
         hero: hero
       } do
    arrival = %{
      context: %{"travel_arrived" => true, "destination_name" => "Рифтен"},
      events: ["arrived_Рифтен"]
    }

    state_data = Memory.track_action(%{}, hero, TravelAction, arrival)
    assert List.last(state_data["memories"])["destination"] == "Рифтен"

    unchanged = Memory.track_action(state_data, hero, SocialAction, %{state_to: "socializing"})
    assert unchanged == state_data

    stalemate = %{
      combat_result: %{
        victory: false,
        hero_defeated: false,
        monster_name: "Тролль",
        rounds: 20
      }
    }

    tracked = Memory.track_action(state_data, hero, TesIdle.Game.Actions.FightAction, stalemate)
    memory = List.last(tracked["memories"])
    assert memory["type"] == "combat_stalemate"
    assert memory["monster"] == "Тролль"
    assert memory["rounds"] == 20
  end

  defp location!(name, type, flags) do
    Repo.insert!(%Location{
      name: name,
      location_type: type,
      region: "Скайрим",
      danger_level: "Низкая",
      min_level: 1,
      max_level: 20,
      has_shop: type == "city",
      has_inn: type == "city",
      weather: "Ясно",
      flags: flags
    })
  end

  defp ctx(hero, location) do
    %GameContext{
      hero: hero,
      location: location,
      location_type: location.location_type,
      inventory: [],
      equipment: %{},
      needs: %{hunger: hero.hunger, fatigue: hero.fatigue, morale: hero.morale},
      configs: %{
        "travel" => %{
          "tick_fatigue_cost" => 3,
          "tick_sp_cost" => 2,
          "encounter_chance" => %{"default" => 0.0}
        },
        "activities" => %{
          "fishing" => %{"catch_chance" => 1.0, "skill_xp" => 1, "xp" => [3, 3]},
          "jail" => %{"jail_feed" => [2, 2]}
        }
      },
      personality: personality(),
      memories: [],
      hour: hero.game_hour,
      weather: "clear",
      world: %{},
      combat_state: nil,
      travel_state: nil,
      active_quest: nil,
      state_data: Jason.decode!(hero.state_data || "{}")
    }
  end

  defp save_state(hero, state, state_data) do
    hero
    |> Ecto.Changeset.change(%{state: state, state_data: Jason.encode!(state_data)})
    |> Repo.update!()
  end

  defp plan(actions) do
    %{
      "goal" => "test",
      "steps" => Enum.map(actions, &to_string/1),
      "current_step" => 0
    }
  end

  defp personality do
    %{
      bravery: 50,
      curiosity: 50,
      greed: 50,
      sociability: 50,
      tenacity: 50,
      caution: 50,
      patience: 50,
      dexterity: 50,
      empathy: 50
    }
  end
end
