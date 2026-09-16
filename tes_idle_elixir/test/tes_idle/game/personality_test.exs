defmodule TesIdle.Game.PersonalityTest do
  use ExUnit.Case, async: true

  alias TesIdle.Game.Brain.Genome
  alias TesIdle.Game.Personality

  @user_id "22222222-2222-2222-2222-222222222222"

  test "generate/3 с brain_hash детерминирован" do
    hash = Genome.brain_hash(@user_id)
    p1 = Personality.generate("Nord", "Warrior", brain_hash: hash)
    p2 = Personality.generate("Nord", "Warrior", brain_hash: hash)
    assert p1 == p2
  end

  test "геном + модификаторы расы/класса, все 9 черт в 0..100" do
    hash = Genome.brain_hash(@user_id)
    p = Personality.generate("Khajiit", "Thief", brain_hash: hash)

    assert MapSet.new(Map.keys(p)) == MapSet.new(Genome.traits())
    assert Enum.all?(Map.values(p), &(&1 in 0..100))

    # Khajiit: dexterity +20, Thief: dexterity +20 → у каджита-вора ловкость выше базы
    base = Genome.base_traits(hash)
    assert p.dexterity >= base.dexterity + 40 - 100 or p.dexterity == 100
    assert p.dexterity > Map.get(base, :dexterity, 50) - 1
  end

  test "разные мозги → разные личности (при прочих равных)" do
    h1 = Personality.generate("Nord", "Mage", brain_hash: Genome.brain_hash("user-a"))
    h2 = Personality.generate("Nord", "Mage", brain_hash: Genome.brain_hash("user-b"))
    assert h1 != h2
  end

  test "normalize дополняет недостающие черты (обратная совместимость старых героев)" do
    old = %{"bravery" => 80, "caution" => 20}
    p = Personality.normalize(old)
    assert p.bravery == 80
    assert p.caution == 20
    assert p.patience == 50
    assert p.dexterity == 50
    assert p.empathy == 50
  end
end
