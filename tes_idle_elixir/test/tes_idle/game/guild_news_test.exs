defmodule TesIdle.Game.GuildNewsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.{Guilds, Guardian}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Equipment, GuildNews, Hero, Item, NarrativeTemplate, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_news_#{suffix}",
        email: "qa_news_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Глашатай", race: "Nord", hero_class: "Warrior",
        level: 10, brain_hash: "n", personality: %{}, skills: %{}, gold: 5000, sp: 100, state_data: "{}"})

    weapon =
      Repo.insert!(%Item{name: "Меч Вестника #{suffix}", description: "d", item_type: "equipment", rarity: "common",
        icon: "⚔️", weight: 3.0, sell_price: 40, is_active: true, tags: [],
        reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0,
        equip_slot: "weapon", attack_bonus: 4, speed_bonus: 0.0})

    Repo.insert!(%Equipment{hero_id: hero.id, weapon_id: weapon.id})

    Repo.insert!(%NarrativeTemplate{
      template_type: "guild_founded",
      text_template: "Знамя «{guild_name}» ({emblem}) поднято — {leader} зовёт соратников!",
      source: "system", is_active: true})

    Repo.insert!(%NarrativeTemplate{
      template_type: "guild_levelup",
      text_template: "«{guild_name}» {emblem} вступает в {level} уровень!",
      source: "system", is_active: true})

    %{user: user, hero: hero, suffix: suffix}
  end

  test "основание гильдии — весть в фиде с именем и лидером", %{user: user, hero: hero, suffix: suffix} do
    {:ok, guild} =
      Guilds.create(user, hero, %{name: "Вестниково Знамя #{suffix}", emblem: "⚔️", policy: "open", motto: nil, description: nil}, %{})

    feed = Guilds.News.feed()
    entry = Enum.find(feed, &(&1.template_type == "guild_founded"))
    assert entry != nil
    assert entry.text =~ "Вестниково Знамя"
    assert entry.text =~ user.username
    assert Repo.get_by!(GuildNews, guild_id: guild.id).template_type == "guild_founded"
  end

  test "подношение до порога — весть о новом уровне", %{user: user, hero: hero, suffix: suffix} do
    {:ok, guild} =
      Guilds.create(user, hero, %{name: "Уровневое Знамя #{suffix}", emblem: "🔥", policy: "open", motto: nil, description: nil}, %{})

    {:ok, res} = Guilds.offer_gold(user, hero, 1200, %{})
    assert res.level_ups >= 1

    feed = Guilds.News.feed()
    entry = Enum.find(feed, &(&1.template_type == "guild_levelup"))
    assert entry != nil
    assert entry.text =~ "Уровневое Знамя"
  end

  test "нет шаблона — записи нет (паттерн честного фида)", %{suffix: suffix} do
    clean =
      Repo.insert!(%User{username: "qa_no_tpl_#{suffix}", email: "no_tpl_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    # выгружаем шаблон уровня и пробуем напрямую
    from(t in NarrativeTemplate, where: t.template_type == "nonexistent_event") |> Repo.delete_all()

    assert Guilds.News.broadcast("nonexistent_event", nil, %{"guild_name" => "X"}) == :skip
    assert Repo.get_by(GuildNews, template_type: "nonexistent_event") == nil
    assert clean.username =~ "qa_no_tpl"
  end

  test "feed: отсортирован новыми первыми" do
    feed = Guilds.News.feed(50)
    assert length(feed) <= 50

    times = Enum.map(feed, & &1.created_at)
    assert times == Enum.sort(times, {:desc, NaiveDateTime})
  end

  # Guardian держится в алиасах для будущих API-тестов фида
  defp _guardian_probe(), do: Guardian != nil
end
