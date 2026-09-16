defmodule TesIdle.Game.Brain.IntentTest do
  @moduledoc "S-2-T: единое ядро решений — мир влияет по характеру, трассировка полная."
  use ExUnit.Case, async: true

  alias TesIdle.Game.{GameContext, Brain.Intent, Brain.Graph}
  alias TesIdle.Schemas.{Hero, Location}

  defp hero(caution, bravery, greed \\ 40) do
    %Hero{
      name: "Тест", race: "Nord", hero_class: "Warrior", game_day: 4,
      hp: 100, max_hp: 100, gold: 30,
      skills: %{},
      personality: %{bravery: bravery, caution: caution, curiosity: 50, greed: greed,
                     sociability: 50, tenacity: 50, patience: 50, dexterity: 50, empathy: 50},
      state_data: "{}",
    }
  end

  defp ctx(hero, world, weather \\ "clear") do
    %GameContext{
      hero: hero,
      personality: hero.personality,
      needs: %{hunger: 40, fatigue: 30, morale: 60},
      hour: 12.0,
      location_type: "wilderness",
      weather: weather,
      world: world,
      configs: %{},
      inventory: [],
      memories: [],
    }
  end

  defp goal_by(goals, name), do: Enum.find(goals, &(&1.name == name))

  # --- Дракон и характер ---

  test "S-2: дракон — осторожный пережидает (travel ниже), трассировка с причиной" do
    dragon_world = %{"events" => [%{"type" => "dragon", "ttl" => 10}], "wars" => []}
    calm_world = %{"events" => [], "wars" => []}

    cautious = hero(80, 30)

    base = Intent.evaluate(%{ctx(cautious, calm_world) | world: calm_world})
    scared = Intent.evaluate(%{ctx(cautious, dragon_world) | world: dragon_world})

    travel_base = goal_by(base, :travel)
    travel_scared = goal_by(scared, :travel)

    assert travel_scared.utility < travel_base.utility - 0.05
    assert Enum.any?(travel_scared.brain_reasons, &String.contains?(&1, "дракон"))
    assert String.contains?(travel_scared.reason, "мир")
  end

  test "S-2: мир не воскрешает отброшенные цели (затмение не вернёт вора в пустоши)" do
    # В пустошах нет steal/break_in (utility 0 на стадии 1) — затмение не должно их вернуть
    eclipse_world = %{"events" => [%{"type" => "eclipse", "ttl" => 4}], "wars" => []}
    goals = Intent.evaluate(%{ctx(hero(50, 50), eclipse_world) | world: eclipse_world})

    refute goal_by(goals, :steal), "steal должен остаться отброшенным вне города"
    refute goal_by(goals, :break_in), "break_in должен остаться отброшенным без locked_buildings"
  end

  # --- Ярмарка и торговля ---

  test "S-2: ярмарка в городе тянет на шопинг и гулянье" do
    city = %Location{id: "city-1", location_type: "city", has_shop: true, has_inn: true}
    fair_world = %{"events" => [%{"type" => "fair", "location_id" => "city-1", "ttl" => 6}], "wars" => []}
    calm_world = %{"events" => [], "wars" => []}

    h = hero(50, 50, 60)

    base_ctx = %{ctx(h, calm_world) | location: city, location_type: "city",
                  needs: %{hunger: 60, fatigue: 30, morale: 60}}
    fair_ctx = %{ctx(h, fair_world) | location: city, location_type: "city",
                  needs: %{hunger: 60, fatigue: 30, morale: 60}}

    shop_base = goal_by(Intent.evaluate(base_ctx), :shop)
    shop_fair = goal_by(Intent.evaluate(fair_ctx), :shop)

    assert shop_fair.utility > shop_base.utility + 0.05
    assert Enum.any?(shop_fair.brain_reasons, &String.contains?(&1, "ярмарка"))
  end

  # --- Война и регион ---

  test "S-2: война в регионе — осторожный не путешествует" do
    war_world = %{"events" => [], "wars" => ["Империя|Братья Бури"]}
    calm_world = %{"events" => [], "wars" => []}

    # Локация в регионе Империи (default_faction = "Империя")
    village = %Location{id: "v-1", location_type: "village", region: "Вайтран"}
    h = hero(75, 30)

    base = Intent.evaluate(%{ctx(h, calm_world) | location: village, location_type: "village"})
    at_war = Intent.evaluate(%{ctx(h, war_world) | location: village, location_type: "village"})

    travel_base = goal_by(base, :travel)
    travel_war = goal_by(at_war, :travel)

    assert travel_war.utility < travel_base.utility - 0.05
    assert Enum.any?(travel_war.brain_reasons, &String.contains?(&1, "война"))
  end

  # --- Погода и путь ---

  test "S-2: гроза — осторожный не идёт в путь, зато дома уютнее" do
    h = hero(75, 30)

    calm = Intent.evaluate(ctx(h, %{"events" => [], "wars" => []}, "clear"))
    storm = Intent.evaluate(ctx(h, %{"events" => [], "wars" => []}, "storm"))

    travel_calm = goal_by(calm, :travel)
    travel_storm = goal_by(storm, :travel)
    rest_calm = goal_by(calm, :rest)
    rest_storm = goal_by(storm, :rest)

    assert travel_storm.utility < travel_calm.utility
    assert rest_storm.utility > rest_calm.utility
  end

  # --- Лог решений ---

  test "S-2: decision_log содержит контекст мира" do
    world = %{"events" => [%{"type" => "eclipse", "ttl" => 2}], "wars" => ["Империя|Братья Бури"]}
    goal = %TesIdle.Game.Goal{name: :steal, utility: 0.4, reason: "Тени зовут",
                              brain_reasons: ["затмение: тени длиннее, глаза короче (0.10)"]}

    c = %{ctx(hero(50, 50), world, "rain") | hero: %{hero(50, 50) | game_day: 7}}
    sd = Graph.log_decision(%{}, goal, c)
    [entry | _] = sd["brain"]["decision_log"]

    assert entry["goal"] == "steal"
    assert entry["world"]["weather"] == "rain"
    assert entry["world"]["events"] == ["eclipse"]
    assert entry["world"]["wars"] == 1
    assert Enum.any?(entry["reasons"], &String.contains?(&1, "затмение"))
  end
end
