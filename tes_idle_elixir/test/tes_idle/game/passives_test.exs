defmodule TesIdle.Game.PassivesTest do
  use ExUnit.Case, async: true

  alias TesIdle.Game.{HeroCanon, Passives, Personality}

  defp hero(class, sparks \\ 10, passives \\ %{}) do
    %{hero_class: class, soul_sparks: sparks, passives: passives}
  end

  test "russian class label reaches the personality modifier" do
    warrior = Personality.generate("Норд", "Воин")
    bare = Personality.generate("неизвестно", "неизвестно")
    assert warrior.bravery > bare.bravery
  end

  test "old english class still resolves" do
    assert HeroCanon.class_key("Warrior") == "warrior"
    assert HeroCanon.race_key("Nord") == "nord"
  end

  test "class grants its first node for free and the next rank costs more" do
    assert Passives.rank(hero("Воин", 0), "steel_1") == 1
    assert Passives.next_cost(hero("Воин", 0), "steel_1") == 2
  end

  test "a locked node cannot be bought" do
    assert Passives.buy(hero("Воин"), "steel_3") == {:error, :locked}
  end

  test "buying spends sparks and raises the rank" do
    assert {:ok, passives, 2} = Passives.buy(hero("Маг", 3), "sign_1")
    assert passives["sign_1"] == 2
  end

  test "no sparks means no purchase" do
    assert Passives.buy(hero("Маг", 0), "sign_1") == {:error, :not_enough_sparks}
  end

  test "full ranks never multiply experience" do
    hero = hero("Воин", 0, %{"steel_1" => 3, "steel_2" => 3, "steel_3" => 3, "steel_4" => 3})
    bonus = Passives.bonus(hero)
    refute Map.has_key?(bonus, :xp)
    assert bonus.defense > 0
  end
end
