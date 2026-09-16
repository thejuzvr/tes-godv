defmodule TesIdle.Game.GuildShopTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildMember, InventoryItem, Item, JournalEntry, NarrativeTemplate, User}

  @catalog [
    %{"name" => "Плащ Тестовый", "points" => 50},
    %{"name" => "Эликсир Тестовый", "points" => 20}
  ]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_shopper_#{suffix}",
        email: "qa_shopper_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%TesIdle.Schemas.Hero{user_id: user.id, name: "QA Покупатель", race: "Nord", hero_class: "Warrior",
        level: 5, brain_hash: "s", personality: %{}, skills: %{}, gold: 1000, sp: 100, state_data: "{}"})

    guild = Repo.insert!(%TesIdle.Schemas.Guild{name: "Лавка Теста #{suffix}", leader_id: user.id, emblem: "⚔️"})
    Repo.insert!(%GuildMember{guild_id: guild.id, user_id: user.id, role: "leader", points: 100, contributed: 300})

    cloak =
      Repo.insert!(%Item{name: "Плащ Тестовый", description: "d", item_type: "equipment", rarity: "uncommon",
        icon: "🧥", weight: 2.0, sell_price: 30, is_active: true, tags: ["guild"], reduce_hunger: 0.0,
        reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0, equip_slot: "body",
        defense_bonus: 3, hp_bonus: 10, speed_bonus: 0.0})

    potion =
      Repo.insert!(%Item{name: "Эликсир Тестовый", description: "d", item_type: "consumable", rarity: "common",
        icon: "🧪", weight: 1.0, sell_price: 10, is_active: true, tags: ["guild"], reduce_hunger: 0.0,
        reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0, heal_hp: 40, heal_sp: 30,
        buff_attack: 2, buff_duration_ticks: 10, speed_bonus: 0.0})

    Repo.insert!(%NarrativeTemplate{
      template_type: "guild_shop_purchase",
      text_template: "{hero_name} выменивает «{item}» — осталось {points} очков.",
      source: "system", is_active: true})

    %{user: user, hero: hero, guild: guild, cloak: cloak, potion: potion, suffix: suffix}
  end

  test "buy: очки списываются, предмет в инвентаре, журнал пишет", %{user: user, hero: hero, cloak: cloak} do
    {:ok, res} = Guilds.Shop.buy(user, hero, "Плащ Тестовый", %{"guild_shop" => %{"catalog" => @catalog}})

    assert res.item.id == cloak.id
    assert res.points_left == 50   # 100 − 50

    member = Repo.get_by!(GuildMember, user_id: user.id)
    assert member.points == 50

    inv = Repo.get_by!(InventoryItem, hero_id: hero.id, item_id: cloak.id)
    assert inv.quantity == 1

    entry =
      Repo.one!(from j in JournalEntry, where: j.hero_id == ^hero.id and j.entry_type == "guild_shop_purchase")
    assert entry.text =~ "Плащ Тестовый"
    assert entry.text =~ "50"
  end

  test "buy: consumable накапливается quantity, а не плодит строки", %{user: user, hero: hero, potion: potion} do
    assert {:ok, _} = Guilds.Shop.buy(user, hero, "Эликсир Тестовый", %{"guild_shop" => %{"catalog" => @catalog}})
    assert {:ok, _} = Guilds.Shop.buy(user, hero, "Эликсир Тестовый", %{"guild_shop" => %{"catalog" => @catalog}})

    inv = Repo.get_by!(InventoryItem, hero_id: hero.id, item_id: potion.id)
    assert inv.quantity == 2

    member = Repo.get_by!(GuildMember, user_id: user.id)
    assert member.points == 60   # 100 − 20 − 20
  end

  test "buy: нехватка очков → not_enough_points, ничего не списано", %{user: user, hero: hero, cloak: cloak} do
    member = Repo.get_by!(GuildMember, user_id: user.id)
    Repo.update!(Ecto.Changeset.change(member, points: 30))

    assert Guilds.Shop.buy(user, hero, "Плащ Тестовый", %{"guild_shop" => %{"catalog" => @catalog}}) ==
             {:error, :not_enough_points}

    assert Repo.get_by!(GuildMember, user_id: user.id).points == 30
    assert Repo.get_by(InventoryItem, hero_id: hero.id, item_id: cloak.id) == nil
  end

  test "buy: неизвестный предмет и не в гильдии", %{hero: hero, user: _user} do
    assert Guilds.Shop.buy(hero, hero, "Плащ Тестовый", %{"guild_shop" => %{"catalog" => @catalog}}) ==
             {:error, :not_in_guild}

    suffix = System.unique_integer([:positive])
    u2 = Repo.insert!(%User{username: "qa_lone_s_#{suffix}", email: "lones#{suffix}@t.gg", password_hash: "x", is_admin: false})
    assert Guilds.Shop.buy(u2, hero, "Плащ Тестовый", %{"guild_shop" => %{"catalog" => @catalog}}) ==
             {:error, :not_in_guild}

    member_user = Repo.one!(from m in GuildMember, limit: 1, select: m.user_id)
    u3 = Repo.get!(User, member_user)
    assert Guilds.Shop.buy(u3, hero, "Нет такого", %{"guild_shop" => %{"catalog" => @catalog}}) ==
             {:error, :unknown_item}
  end

  test "catalog: берётся из конфига", %{} do
    assert Guilds.Shop.catalog(%{"guild_shop" => %{"catalog" => @catalog}}) == @catalog
    assert Guilds.Shop.catalog(%{}) == []
  end
end
