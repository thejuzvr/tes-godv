defmodule TesIdle.Game.Phase2IntegrationTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Game.Pets
  alias TesIdle.Schemas.{Hero, Item, Location, Pet, User}
  import Ecto.Query

  # NOTE: FishingAction тестируется через повторные execute с ручным
  # сохранением state_data (как в pipeline). Helpers-модуль не нужен —
  # импортируем модуль напрямую и вызываем публичный execute/1.

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    user = Repo.insert!(%User{username: "qa_p2_#{System.unique_integer([:positive])}",
      email: "qa_p2_#{System.unique_integer([:positive])}@test.gg", password_hash: "x", is_admin: false})

    location = Repo.insert!(%Location{
      name: "QA Озеро #{System.unique_integer([:positive])}",
      location_type: "wilderness",
      region: "Скайрим",
      danger_level: "Низкая",
      min_level: 1, max_level: 10,
      has_shop: false, has_inn: false,
      weather: "Ясно",
      flags: %{"water" => true, "gather_nodes" => true},
    })

    fish_item = Repo.insert!(%Item{name: "QA Fish", item_type: "consumable", icon: "🐟",
      sell_price: 4, tags: ["fish"], is_active: true})

    _herb_item = Repo.insert!(%Item{name: "QA Herb", item_type: "material", icon: "🌿",
      sell_price: 3, tags: ["herb"], is_active: true})

    hero = Repo.insert!(%Hero{
      user_id: user.id,
      name: "QA Рыбак",
      race: "Nord", hero_class: "Warrior",
      level: 1, hp: 100, max_hp: 100, mp: 20, max_mp: 20, sp: 40, max_sp: 80,
      attack: 5, defense: 3, gold: 50, xp: 0, xp_to_next: 100,
      state: "idle", mood: 60.0, hunger: 40.0, fatigue: 30.0, morale: 60.0,
      soul_energy: 50.0, max_soul_energy: 100.0,
      game_hour: 6.5, game_day: 3, game_era: "4E",
      location_id: location.id,
      brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id),
      personality: %{bravery: 50, curiosity: 50, greed: 50, sociability: 50,
                     tenacity: 50, caution: 50, patience: 60, dexterity: 50, empathy: 50},
      skills: %{},
      state_data: "{}",
    })

    %{hero: Repo.get!(Hero, hero.id), location: location, fish_item: fish_item}
  end

  test "рыбалка: старт → ожидание → улов (item + навык)", %{hero: hero, location: location, fish_item: fish_item} do
    ctx = build_ctx(hero, location)
    {:ok, r1} = TesIdle.Game.Actions.FishingAction.execute(ctx)

    assert r1.state_to == "fishing"
    ticks = r1.state_data_update["fishing"]["ticks_left"]
    assert ticks >= 1 and ticks <= 5

    # Эмулируем тики: сохраняем state_data и снова execute
    hero2 = %{hero | state_data: Jason.encode!(Map.merge(dec(hero), r1.state_data_update))}

    result = catch_until(hero2, location, 20)

    assert %{state_to: "fishing"} = result
    assert result.state_data_update["fishing"] == nil, "улов завершает рыбалку"
    assert result.context["fish_name"] != nil

    # Навык вырос и предмет в инвентаре
    hero3 = Repo.reload!(hero)
    assert (hero3.skills["fishing"] || hero3.skills[:fishing] || 0) > 0

    inv = Repo.one(from ii in TesIdle.Schemas.InventoryItem,
      where: ii.hero_id == ^hero.id and ii.item_id == ^fish_item.id)
    assert inv != nil
  end

  test "собирательство: находит траву (вероятностно) или честный пустой тик", %{hero: hero, location: location} do
    ctx = build_ctx(hero, location)

    # До 10 попыток — find_chance 0.55 + навык, почти наверняка что-то найдёт
    found = Enum.find_value(1..10, fn _ ->
      case TesIdle.Game.Actions.GatheringAction.execute(ctx) do
        {:ok, %{item_name: name}} when not is_nil(name) -> name
        _ -> nil
      end
    end)

    assert found != nil
    assert (Repo.reload!(hero).skills["gathering"] || Repo.reload!(hero).skills[:gathering] || 0) > 0
  end

  test "питомец: cooldown с прошедшим revive_at → возрождение", %{hero: hero} do
    _pet = Repo.insert!(%Pet{
      hero_id: hero.id, species: "wolf", name: "Клык",
      mood: 30.0, hunger: 60.0, loyalty: 30.0,
      status: "cooldown",
      revive_at: DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second),
      created_at: DateTime.utc_now() |> DateTime.truncate(:second),
    })

    {_pet, events} = Pets.passive_tick(Repo.reload!(hero), %{"pets" => %{"revive_hours" => 4}})
    assert Enum.any?(events, &(&1.type == "pet_revived"))

    revived = Pets.active(hero.id)
    assert revived != nil and revived.name == "Клык"
  end

  test "питомец: голод съедает лояльность → уходит навсегда при нуле", %{hero: hero} do
    pet = Repo.insert!(%Pet{
      hero_id: hero.id, species: "cat", name: "Наглый",
      mood: 20.0, hunger: 99.5, loyalty: 0.3,
      status: "active",
      created_at: DateTime.utc_now() |> DateTime.truncate(:second),
    })

    {_pet, events} = Pets.passive_tick(Repo.reload!(hero), %{"pets" => %{"loyalty_zero_leave" => true}})
    assert Enum.any?(events, &(&1.type == "pet_left"))

    gone = Repo.get!(Pet, pet.id)
    assert gone.status == "gone"
  end

  # --- Helpers ---

  defp build_ctx(hero, location) do
    inventory = Repo.all(
      from ii in TesIdle.Schemas.InventoryItem,
        where: ii.hero_id == ^hero.id,
        join: item in assoc(ii, :item),
        select: {ii, item}
    )

    %TesIdle.Game.GameContext{
      hero: hero,
      location: location,
      configs: TesIdle.Game.ContextBuilder.load_configs(),
      inventory: inventory,
      hour: hero.game_hour,
      location_type: location.location_type,
      needs: %{hunger: hero.hunger, fatigue: hero.fatigue, morale: hero.morale},
      personality: TesIdle.Game.Personality.normalize(hero.personality),
      memories: [],
      state_data: dec(hero),
    }
  end

  defp dec(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, m} when is_map(m) -> m
      _ -> %{}
    end
  end

  defp catch_until(hero, location, tries_left)

  defp catch_until(_hero, _location, 0), do: flunk("рыба не клюнула за 20 тиков")

  defp catch_until(hero, location, tries_left) do
    ctx = build_ctx(hero, location)
    {:ok, result} = TesIdle.Game.Actions.FishingAction.execute(ctx)

    case result.state_data_update["fishing"] do
      nil -> result
      _fishing ->
        hero2 = %{hero | state_data: Jason.encode!(Map.merge(dec(hero), result.state_data_update))}
        catch_until(hero2, location, tries_left - 1)
    end
  end
end
