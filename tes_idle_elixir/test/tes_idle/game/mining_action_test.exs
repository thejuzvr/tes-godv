defmodule TesIdle.Game.MiningActionTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Game.{GameContext, Skills}
  alias TesIdle.Game.Actions.MiningAction
  alias TesIdle.Schemas.{Hero, InventoryItem, Item, Location, User}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "mining_#{suffix}",
        email: "mining_#{suffix}@test.gg",
        password_hash: "x"
      })

    location =
      Repo.insert!(%Location{
        name: "Шахта #{suffix}",
        location_type: "wilderness",
        region: "Скайрим",
        danger_level: "Низкая",
        min_level: 1,
        max_level: 20,
        has_shop: false,
        has_inn: false,
        weather: "Ясно",
        flags: %{"ore_nodes" => true}
      })

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Шахтёр",
        race: "Nord",
        hero_class: "Warrior",
        level: 1,
        hp: 100,
        max_hp: 100,
        sp: 50,
        max_sp: 100,
        gold: 0,
        xp: 0,
        xp_to_next: 100,
        state: "idle",
        location_id: location.id,
        personality: %{},
        skills: %{},
        state_data: "{}",
        brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id)
      })

    %{hero: hero, location: location}
  end

  test "starts, waits, then completes with ore, XP, and mining skill", %{
    hero: hero,
    location: location
  } do
    ore =
      Repo.insert!(%Item{
        name: "QA Ore",
        item_type: "material",
        icon: "o",
        sell_price: 1,
        tags: ["ore"],
        is_active: true
      })

    ctx =
      context(
        hero,
        location,
        mining_cfg(%{"ticks" => [2, 2], "find_chance" => 1.0, "xp" => [4, 4]})
      )

    {:ok, started} = MiningAction.execute(ctx)
    assert started.state_to == "mining"
    assert started.state_data_update["mining"] == %{"ticks_left" => 2, "total_ticks" => 2}

    hero = with_state(hero, started.state_data_update)

    {:ok, waiting} =
      MiningAction.execute(
        context(
          hero,
          location,
          mining_cfg(%{"ticks" => [2, 2], "find_chance" => 1.0, "xp" => [4, 4]})
        )
      )

    assert waiting.state_data_update["mining"]["ticks_left"] == 1
    refute Map.get(waiting, :activity_complete)

    hero = with_state(hero, waiting.state_data_update)

    {:ok, completed} =
      MiningAction.execute(
        context(
          hero,
          location,
          mining_cfg(%{"ticks" => [2, 2], "find_chance" => 1.0, "xp" => [4, 4]})
        )
      )

    assert completed.activity_complete == true
    assert completed.state_data_update == %{"mining" => nil}
    assert completed.xp == 4
    assert completed.item_name == ore.name

    inventory =
      Repo.one!(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^ore.id)

    assert inventory.quantity == 1
    assert Skills.get(Repo.reload!(hero), :mining) > 0
  end

  test "empty ore catalog completes honestly with experience and no item", %{
    hero: hero,
    location: location
  } do
    hero = with_state(hero, %{"mining" => %{"ticks_left" => 1, "total_ticks" => 1}})

    {:ok, completed} =
      MiningAction.execute(
        context(hero, location, mining_cfg(%{"find_chance" => 1.0, "xp" => [5, 5]}))
      )

    assert completed.activity_complete == true
    assert completed.item_name == nil
    assert completed.xp == 5
    assert completed.context["ore_name"] == "только каменная крошка"
    assert Repo.aggregate(InventoryItem, :count, :id) == 0
    assert Skills.get(Repo.reload!(hero), :mining) > 0
  end

  test "without an ore node falls back to exploration", %{hero: hero, location: location} do
    location = %{location | flags: %{}}
    {:ok, result} = MiningAction.execute(context(hero, location, mining_cfg()))

    assert result.state_to == "exploring"
    refute Map.get(result, :state_data_update, %{})["mining"]
  end

  defp mining_cfg(overrides \\ %{}) do
    Map.merge(
      %{"ticks" => [2, 2], "find_chance" => 1.0, "skill_xp" => 1, "xp" => [3, 3]},
      overrides
    )
  end

  defp context(hero, location, mining) do
    %GameContext{
      hero: hero,
      location: location,
      location_type: location.location_type,
      inventory: [],
      equipment: %{},
      needs: %{hunger: 0, fatigue: 0, morale: 50},
      configs: %{"activities" => %{"mining" => mining}},
      personality: %{},
      memories: [],
      hour: 12.0,
      weather: "clear",
      world: %{},
      state_data: Jason.decode!(hero.state_data || "{}")
    }
  end

  defp with_state(hero, update) do
    state = hero.state_data |> Jason.decode!() |> Map.merge(update)
    hero |> Ecto.Changeset.change(state_data: Jason.encode!(state)) |> Repo.update!()
  end
end
