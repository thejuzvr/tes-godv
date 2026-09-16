defmodule TesIdle.Game.SkyforgeTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Skyforge
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Equipment, Hero, Item, JournalEntry, NarrativeTemplate, Sharpening, User}

  @cfg %{"base_cost" => 50, "growth" => 1.8, "cap" => 10, "fail_chance" => 0}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_smith_#{suffix}",
        email: "qa_smith_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Кузнец", race: "Nord", hero_class: "Warrior",
        level: 8, brain_hash: "s", personality: %{}, skills: %{}, gold: 5000, sp: 100, state_data: "{}"})

    weapon =
      Repo.insert!(%Item{name: "Меч Тестовый #{suffix}", description: "d", item_type: "equipment", rarity: "common",
        icon: "⚔️", weight: 3.0, sell_price: 40, is_active: true, tags: [],
        reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0,
        equip_slot: "weapon", attack_bonus: 4, speed_bonus: 0.0})

    Repo.insert!(%Equipment{hero_id: hero.id, weapon_id: weapon.id})

    Repo.insert!(%NarrativeTemplate{
      template_type: "enhance_success",
      text_template: "{hero_name} закаляет «{item}» в небесном горне — ступень {level}.",
      source: "system", is_active: true})

    %{user: user, hero: hero, weapon: weapon, suffix: suffix}
  end

  test "price: квадратичная формула 50 × level^1.8" do
    assert Skyforge.price(1, @cfg) == 50
    assert Skyforge.price(2, @cfg) == 174   # 50 × 2^1.8 = 174.11
    assert Skyforge.price(10, @cfg) == 3155 # 50 × 10^1.8 = 3154.8
  end

  test "enhance: заточка оружия — золото списано, уровень растёт, журнал пишет", %{user: user, hero: hero, weapon: weapon} do
    {:ok, res} = Skyforge.enhance(user, hero, "weapon", %{"skyforge" => @cfg})

    assert res.level == 1
    assert res.price == 50
    assert res.gold_left == 5000 - 50

    hero = Repo.get!(Hero, hero.id)
    assert hero.gold == 4950
    assert Repo.get_by!(Sharpening, hero_id: hero.id, item_id: weapon.id).level == 1

    entry =
      Repo.one!(from j in JournalEntry,
        where: j.hero_id == ^hero.id and j.entry_type == "enhance_success")
    assert entry.text =~ "Меч Тестовый"
    assert entry.text =~ "1"
  end

  test "enhance: накопительно до кэпа, кэп → cap_reached", %{user: user, hero: hero, weapon: weapon} do
    Repo.insert!(%Sharpening{hero_id: hero.id, item_id: weapon.id, level: 10})

    assert Skyforge.enhance(user, hero, "weapon", %{"skyforge" => @cfg}) == {:error, :cap_reached}
  end

  test "enhance: нехватка золота — ничего не списано", %{user: user, hero: hero, weapon: weapon} do
    poor =
      Repo.get!(Hero, hero.id)
      |> Ecto.Changeset.change(gold: 30)
      |> Repo.update!()

    assert Skyforge.enhance(user, poor, "weapon", %{"skyforge" => @cfg}) == {:error, :not_enough_gold}
    assert Repo.get!(Hero, hero.id).gold == 30
    assert Repo.get_by(Sharpening, hero_id: hero.id, item_id: weapon.id) == nil
  end

  test "enhance: пустой слот и невалидный слот", %{user: user, hero: hero} do
    assert Skyforge.enhance(user, hero, "ring", %{"skyforge" => @cfg}) == {:error, :empty_slot}
    assert Skyforge.enhance(user, hero, "flute", %{"skyforge" => @cfg}) == {:error, :empty_slot}
  end

  test "equipment_bonus: weapon/amulet дают attack, броня — defense", %{hero: hero, weapon: weapon} do
    equip = Repo.get_by!(Equipment, hero_id: hero.id)
    assert Skyforge.equipment_bonus(equip) == {0, 0}

    Repo.insert!(%Sharpening{hero_id: hero.id, item_id: weapon.id, level: 3})
    assert Skyforge.equipment_bonus(equip) == {3, 0}
  end
end
