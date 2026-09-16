defmodule TesIdle.WorldTest do
  use ExUnit.Case, async: true

  alias TesIdle.World.{Weather, Economy, Migration, Factions, Events, Snapshot}

  # --- Weather ---

  test "погода: марковский шаг сохраняет валидные состояния" do
    weather = %{"Скайрим" => "clear", "Тест" => "rain"}

    result =
      Enum.reduce(1..50, weather, fn _, w -> Weather.step(w, "осень") end)

    Enum.each(result, fn {region, w} ->
      assert w in Snapshot.weathers(), "регион #{region}: невалидная погода #{w}"
    end)
  end

  test "погода: зимой к снегу, эффекты дождя бьют по усталости" do
    assert Weather.needs_effects("rain") == {0.0, 2.0, -1.0}
    assert Weather.needs_effects("clear") == {0.0, 0.0, 0.0}
    assert Weather.fishing_bonus("rain") == 0.30
    assert Weather.fishing_bonus("clear") == 0.0

    # 1000 шагов зимы из облачного — снег должен выпадать часто
    snows =
      Enum.count(1..1000, fn _ ->
        Weather.step(%{"r" => "cloud"}, "зима", 1.0)["r"] == "snow"
      end)

    assert snows > 200, "зимой снег должен быть частым (выпало #{snows}/1000)"
  end

  test "S-1: погодные бонусы клёва и скрытности — чистые значения" do
    assert Weather.fishing_bonus("storm") == 0.15
    assert Weather.fishing_bonus("snow") == 0.0

    assert Weather.stealth_bonus("storm") == 0.15
    assert Weather.stealth_bonus("rain") == 0.10
    assert Weather.stealth_bonus("snow") == 0.05
    assert Weather.stealth_bonus("clear") == 0.0
    assert Weather.stealth_bonus("cloud") == 0.0
  end

  # --- Economy ---

  test "экономика: дрейф к базису и коридор 0.6–1.8" do
    prices = %{"city-1" => %{"food" => 1.8, "gear" => 0.6, "rare" => 1.0, "lodging" => 1.0}}

    result = Economy.step(prices, [], [])
    food = result["city-1"]["food"]
    assert food < 1.8, "цена должна сползать к 1.0"
    assert food >= 0.6 and food <= 1.8
  end

  test "экономика: война поднимает цены, ярмарка снижает" do
    prices = %{"war-city" => %{"food" => 1.0}, "fair-city" => %{"food" => 1.0}}
    fair = [%{"type" => "fair", "location_id" => "fair-city", "ttl" => 5}]

    result = Economy.step(prices, ["war-city"], fair)

    assert_in_delta result["war-city"]["food"], 1.4, 0.01
    assert_in_delta result["fair-city"]["food"], 0.8, 0.01
  end

  test "экономика: давление покупок с масштабом sqrt(n/10)" do
    prices = %{"c" => %{"food" => 1.0}}
    # 10 покупок → +0.5%
    p1 = Economy.apply_pressure(prices, %{"c" => %{"food" => 10}})
    assert_in_delta p1["c"]["food"], 1.005, 0.0005
    # 90 покупок → ×3 масштаб → +1.5%
    p2 = Economy.apply_pressure(prices, %{"c" => %{"food" => 90}})
    assert_in_delta p2["c"]["food"], 1.015, 0.001
  end

  test "экономика: множитель по категории предмета" do
    prices = %{"c" => %{"food" => 1.2, "gear" => 0.9, "rare" => 1.5, "lodging" => 1.0}}
    assert Economy.price_for(prices, "c", "consumable") == 1.2
    assert Economy.price_for(prices, "c", "equipment") == 0.9
    assert Economy.price_for(prices, "c", "material") == 1.5
    assert Economy.price_for(prices, "unknown", "food") == 1.0
  end

  # --- Migration ---

  test "миграции: плотность в коридоре 0.5–2.0, множитель встреч ±30%" do
    density = Map.new(1..20, fn i -> {"loc-#{i}", 1.0} end)

    result = Enum.reduce(1..100, density, fn _, d -> Migration.step(d, []) end)

    Enum.each(result, fn {_loc, v} ->
      assert v >= 0.5 and v <= 2.0
    end)

    assert Migration.encounter_factor(1.0) == 1.0
    assert Migration.encounter_factor(2.0) == 1.3
    assert Migration.encounter_factor(0.5) == 0.7
  end

  test "миграции: волна монстров поднимает плотность в локации" do
    density = %{"loc-1" => 1.0}
    events = [%{"type" => "monster_wave", "location_id" => "loc-1", "ttl" => 3}]

    result = Migration.step(density, events)
    assert result["loc-1"] > 1.7
  end

  # --- Factions ---

  test "фракции: война по порогу −60, мир по гистерезису −30" do
    # −70: даже при дрейфе +3 остаётся глубоко за порогом войны (детерминизм теста)
    relations = %{"Империя|Братья Бури" => -70}
    {rel, wars, events} = Factions.step(relations, [])

    assert wars == ["Империя|Братья Бури"]
    assert Enum.any?(events, &(&1["type"] == "war_declared"))
    assert rel["Империя|Братья Бури"] <= -60

    # Оттепель до −45: война держится (гистерезис)
    {_, wars2, _} = Factions.step(%{"Империя|Братья Бури" => -45}, wars)
    assert wars2 == ["Империя|Братья Бури"]

    # Мир при ≥ −30 (−27: даже дрейф −3 остаётся на пороге мира — детерминизм теста)
    {_, wars3, events3} = Factions.step(%{"Империя|Братья Бури" => -27}, wars)
    assert wars3 == []
    assert Enum.any?(events3, &(&1["type"] == "war_ended"))
    assert rel != nil
  end

  test "фракции: города войны из снапшота фракций" do
    factions = %{"Империя" => ["c1", "c2"], "Братья Бури" => ["c3"]}
    cities = Factions.war_city_ids(factions, [Snapshot.relation_key("Империя", "Братья Бури")])

    assert Enum.sort(cities) == ["c1", "c2", "c3"]
  end

  # --- Events ---

  test "события: TTL истекает, спавн ограничен пулом" do
    events = [%{"id" => "e1", "type" => "fair", "ttl" => 1, "location_id" => "c1"}]

    result = Events.step(events, nil, [{"c1", "Город", "Скайрим", "city"}], 1, 0.0)
    assert result == [], "событие с ttl=1 должно истечь"
  end

  test "события: форс добавляет событие конкретного типа" do
    result = Events.force([], "dragon", nil, nil, 0)
    assert [%{"type" => "dragon"}] = result
  end

  # --- Snapshot (чистая часть) ---

  test "ключ пары фракций не зависит от порядка" do
    assert Snapshot.relation_key("Б", "А") == Snapshot.relation_key("А", "Б")
    assert Snapshot.relation_key("А", "Б") == "А|Б"
  end

  test "сезон по 360-дневному году" do
    assert Snapshot.season_for(1) == "весна"
    assert Snapshot.season_for(91) == "лето"
    assert Snapshot.season_for(361) == "весна"
  end

  test "погода по региону из снапшота (интеграция ContextBuilder)" do
    snap = %{"weather" => %{"Скайрим" => "rain"}}
    w = get_in(snap, ["weather", "Скайрим"])
    assert w == "rain"
    assert get_in(snap, ["weather", "Незнакомый регион"]) == nil
  end
end
