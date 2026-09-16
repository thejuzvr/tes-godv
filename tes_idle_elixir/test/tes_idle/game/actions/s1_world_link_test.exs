defmodule TesIdle.Game.Actions.S1WorldLinkTest do
  @moduledoc "S-1-T: мир → действия (клёв от погоды ядра, засады от плотности)."
  use ExUnit.Case, async: true

  alias TesIdle.Game.{GameContext, Actions.FishingAction, Actions.ExploreAction}
  alias TesIdle.Schemas.{Hero, Location}

  defp hero do
    %Hero{
      name: "Тест", race: "Nord", hero_class: "Warrior", game_day: 2,
      skills: %{},
      personality: %{bravery: 50, caution: 50, curiosity: 50, greed: 50,
                     sociability: 50, tenacity: 50, patience: 50, dexterity: 50, empathy: 50},
      state_data: "{}",
      gold: 50,
    }
  end

  # --- Клёв: погода ядра мира ---

  test "S-1: дождь ядра мира повышает шанс улова (0.45 → +0.30)" do
    base_ctx = %GameContext{
      hero: hero(),
      hour: 12.0,
      weather: "clear",
      configs: %{"activities" => %{"fishing" => %{}}},
    }

    rain_ctx = %{base_ctx | weather: "rain"}
    storm_ctx = %{base_ctx | weather: "storm"}

    clear_chance = FishingAction.catch_chance(base_ctx, %{})
    rain_chance = FishingAction.catch_chance(rain_ctx, %{})

    assert abs(clear_chance - 0.45) < 1.0e-9
    assert abs(rain_chance - 0.75) < 1.0e-9
    assert rain_chance > clear_chance
    assert FishingAction.catch_chance(storm_ctx, %{}) > clear_chance
  end

  test "S-1: легаси-погода локации больше не влияет (только ctx.weather)" do
    # Локация говорит «Дождь», но ядро мира — clear: бонуса быть не должно
    ctx = %GameContext{
      hero: hero(),
      hour: 12.0,
      weather: "clear",
      location: %Location{id: "loc-1", weather: "Дождь"},
      configs: %{"activities" => %{"fishing" => %{}}},
    }

    assert abs(FishingAction.catch_chance(ctx, %{}) - 0.45) < 1.0e-9
  end

  # --- Засады: плотность мира ---

  defp explore_ctx(density) do
    %GameContext{
      hero: hero(),
      location: %Location{id: "loc-1"},
      location_type: "wilderness",
      weather: "clear",
      configs: %{"activities" => %{"exploration" => %{"encounter_chance" => %{"wilderness" => 0.12}}}},
      world: if(density, do: %{"density" => %{"loc-1" => density}}, else: nil),
    }
  end

  defp ambush_rate(ctx, n) do
    Enum.count(1..n, fn _ -> ExploreAction.ambush?(ctx) end) / n
  end

  test "S-1: плотный мир чаще подкидывает засады" do
    high = ambush_rate(explore_ctx(2.0), 4000)
    low = ambush_rate(explore_ctx(0.5), 4000)

    # ожидание: 0.12×1.3=0.156 против 0.12×0.7=0.084
    assert high > low + 0.02,
           "плотность должна поднимать засады: high=#{Float.round(high, 3)}, low=#{Float.round(low, 3)}"
  end

  test "S-1: без снапшота мира — базовый шанс (fallback 1.0)" do
    rate = ambush_rate(explore_ctx(nil), 4000)
    assert rate > 0.09 and rate < 0.15, "ожидание ~0.12, получено #{Float.round(rate, 3)}"
  end
end
