defmodule TesIdle.Game.LawTest do
  use ExUnit.Case, async: true

  alias TesIdle.Game.{Law, Skills}
  alias TesIdle.Schemas.Hero

  defp hero(state_data \\ "{}") do
    %Hero{
      name: "Тест", race: "Nord", hero_class: "Thief", game_day: 3,
      brain_hash: nil,
      skills: %{"stealth" => 20},
      personality: %{bravery: 50, curiosity: 50, greed: 50, sociability: 50,
                     tenacity: 50, caution: 50, patience: 50, dexterity: 70, empathy: 50},
      state_data: state_data,
      gold: 100,
    }
  end

  test "bounties читаются из state_data" do
    h = hero(Jason.encode!(%{"law" => %{"bounties" => %{"loc-1" => 30, "loc-2" => 20}}}))
    assert Law.total_bounty(h) == 50
    assert Law.bounties(h)["loc-1"] == 30
  end

  test "add_bounty — чистая функция, аккумулирует по городу" do
    law = %{"bounties" => %{}}
    law = Law.add_bounty(law, "loc-1", 25)
    law = Law.add_bounty(law, "loc-1", 15)
    law = Law.add_bounty(law, "loc-2", 40)

    assert law["bounties"]["loc-1"] == 40
    assert law["bounties"]["loc-2"] == 40
  end

  test "clear_bounties точечно по городу, :all — полностью" do
    law = Law.add_bounty(%{"bounties" => %{}}, "loc-1", 30)
    law = Law.add_bounty(law, "loc-2", 10)

    cleared = Law.clear_bounties(law, "loc-1")
    assert Map.has_key?(cleared["bounties"], "loc-1") == false
    assert cleared["bounties"]["loc-2"] == 10

    assert Law.clear_bounties(law, :all)["bounties"] == %{}
  end

  test "witness_roll детерминированно валиден: один из трёх исходов" do
    ctx = %TesIdle.Game.GameContext{
      hero: hero(),
      personality: %{dexterity: 70},
      hour: 23.0,
      location_type: "city",
      configs: %{},
    }

    outcome = Law.witness_roll(ctx)
    assert outcome in [:clean, :spotted, :caught]
  end

  # --- S-1: мир влияет на воровство ---

  defp caught_rate(ctx, n) do
    outcomes = Enum.map(1..n, fn _ -> Law.witness_roll(ctx) end)
    Enum.count(outcomes, &(&1 == :caught)) / n
  end

  test "S-1: затмение снижает долю поимок вора" do
    base_ctx = %TesIdle.Game.GameContext{
      hero: hero(),
      personality: %{dexterity: 70},
      hour: 12.0,
      location_type: "city",
      weather: "clear",
      configs: %{"activities" => %{"stealing" => %{"eclipse_bonus" => 1.0}}},
      world: %{"events" => []},
    }

    eclipse_ctx = %{base_ctx | world: %{"events" => [%{"type" => "eclipse", "ttl" => 3}]}}

    caught_base = caught_rate(base_ctx, 3000)
    caught_eclipse = caught_rate(eclipse_ctx, 3000)

    assert caught_eclipse < caught_base - 0.03,
           "затмение должно помогать вору: base=#{Float.round(caught_base, 3)}, eclipse=#{Float.round(caught_eclipse, 3)}"
  end

  test "S-1: ярмарка в городе усиливает стражу (больше поимок)" do
    base_ctx = %TesIdle.Game.GameContext{
      hero: hero(),
      personality: %{dexterity: 70},
      hour: 12.0,
      location_type: "city",
      weather: "clear",
      configs: %{"activities" => %{"stealing" => %{"fair_guard_multiplier" => 3.0}}},
      world: %{"events" => []},
    }

    fair_ctx = %{base_ctx | world: %{"events" => [%{"type" => "fair", "ttl" => 5}]}}

    caught_base = caught_rate(base_ctx, 3000)
    caught_fair = caught_rate(fair_ctx, 3000)

    assert caught_fair > caught_base + 0.05,
           "ярмарка должна множить стражу: base=#{Float.round(caught_base, 3)}, fair=#{Float.round(caught_fair, 3)}"
  end

  test "start_jail строит корректную структуру с тиками" do
    ctx = %TesIdle.Game.GameContext{
      hero: hero(),
      location: nil,
      location_type: "city",
      hour: 12.0,
      configs: %{},
    }

    jail = Law.start_jail(ctx, "steal")
    assert jail["reason"] == "steal"
    assert jail["ticks_left"] >= 3 and jail["ticks_left"] <= 10
    assert jail["total_ticks"] == jail["ticks_left"]
    assert jail["mode"] == nil
  end

  test "навык stealth растёт с замедлением" do
    h = hero()
    {skills, v1} = Skills.gain(h, :stealth, 1)
    assert v1 > 20.0 and v1 <= 21.0
    assert skills[:stealth] == v1
  end
end
