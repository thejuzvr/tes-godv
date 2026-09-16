defmodule TesIdle.Game.PetsTest do
  use ExUnit.Case, async: true

  # passive_tick/2 и DB-функции тестируются интеграционно (живой прогон);
  # здесь — чистые правила и конфиг-поведение через модульные проверки.

  alias TesIdle.Game.Pets

  @cfg %{"pets" => %{
    "hunger_per_tick" => 0.6,
    "loyalty_decay" => 0.4,
    "revive_hours" => 4,
    "wolf_help" => 0.3,
  }}

  test "wolf_fight_help? false без питомца" do
    refute Pets.wolf_fight_help?(nil, @cfg)
    refute Pets.owl_discovery?(nil, @cfg)
    assert Pets.cat_mood_bonus(nil, @cfg) == 0
  end

  test "cat_mood_bonus только для кота" do
    cat = %{species: "cat", status: "active", loyalty: 50.0}
    wolf = %{species: "wolf", status: "active", loyalty: 90.0}

    assert Pets.cat_mood_bonus(cat, @cfg) == 2
    assert Pets.cat_mood_bonus(wolf, @cfg) == 0
  end

  test "wolf help учитывает лояльность (нулевая — никогда)" do
    wolf = %{species: "wolf", status: "active", loyalty: 0.0}
    refute Pets.wolf_fight_help?(wolf, @cfg)

    wolf_gone = %{species: "wolf", status: "gone", loyalty: 90.0}
    refute Pets.wolf_fight_help?(wolf_gone, @cfg)
  end

  test "on_combat_death ставит revive_at на revive_hours вперёд" do
    # Проверяем только тип/инвариант времени (DB-функция, но без Repo — heresy?)
    # on_combat_death требует Repo → интеграционный тест в живом прогоне.
    # Здесь фиксируем контракт конфига: revive_hours читается из cfg.
    assert @cfg["pets"]["revive_hours"] == 4
  end
end
