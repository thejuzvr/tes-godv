defmodule TesIdle.Game.GuildTreasuryTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Guild, GuildMessage, GuildNews, Hero, NarrativeTemplate, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    leader =
      Repo.insert!(%User{username: "qa_treas_#{suffix}",
        email: "qa_treas_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%Hero{user_id: leader.id, name: "QA Кладовщик", race: "Nord", hero_class: "Warrior",
        level: 10, brain_hash: "n", personality: %{}, skills: %{}, gold: 5000, sp: 100, state_data: "{}"})

    {:ok, guild} =
      Guilds.create(leader, hero, %{name: "Казначейское Знамя #{suffix}", emblem: "🛡️", policy: "open",
        motto: nil, description: nil}, %{})

    # шаблон вести пира — для теста broadcast
    Repo.insert!(%NarrativeTemplate{
      template_type: "guild_feast",
      text_template: "🍻 «{guild_name}» {emblem} справляет пир — {hours} ч рогов и вдохновения!",
      source: "system", is_active: true})

    %{user: leader, hero: hero, guild: guild, suffix: suffix}
  end

  test "вклад в казну: золото списывается, казна копится, лог пишется", %{user: user, hero: hero, guild: guild} do
    {:ok, res} = Guilds.treasury_deposit(user, hero, guild.id, 300)
    assert res.treasury == 300
    assert res.gold == hero.gold - 300

    fresh = Repo.get!(Hero, hero.id)
    assert fresh.gold == hero.gold - 300

    log = Guilds.treasury_log(guild.id)
    assert [%{kind: "deposit", amount: 300, balance_after: 300}] = log
  end

  test "вклад: нехватка золота → not_enough_gold; чужая гильдия → not_in_guild", %{user: user, hero: hero, guild: guild, suffix: suffix} do
    broke =
      Repo.get!(Hero, hero.id)
      |> Ecto.Changeset.change(gold: 50)
      |> Repo.update!()

    assert Guilds.treasury_deposit(user, broke, guild.id, 300) == {:error, :not_enough_gold}

    outsider =
      Repo.insert!(%User{username: "qa_out_#{suffix}", email: "out_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    assert Guilds.treasury_deposit(outsider, hero, guild.id, 100) == {:error, :not_in_guild}
    assert Repo.get!(Guild, guild.id).treasury == 0
  end

  test "пир: казна −300, boost_until в будущем, системное сообщение + весть", %{user: user, hero: hero, guild: guild} do
    {:ok, _} = Guilds.treasury_deposit(user, hero, guild.id, 400)

    {:ok, res} = Guilds.feast(user, guild.id, %{})
    assert res.treasury == 100
    assert NaiveDateTime.compare(res.boost_until, NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)) == :gt

    assert Repo.get!(Guild, guild.id).boost_until == res.boost_until

    sys = Repo.one!(from m in GuildMessage, where: m.guild_id == ^guild.id and m.kind == "system")
    assert sys.body =~ "Пир"

    news = Repo.one!(from n in GuildNews, where: n.template_type == "guild_feast")
    assert news.text =~ "Казначейское Знамя"
  end

  test "пир: рядовой не может (forbidden), пустая казна → not_enough_treasury", %{user: user, guild: guild, suffix: suffix} do
    member =
      Repo.insert!(%User{username: "qa_member_#{suffix}", email: "member_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    assert {:ok, {_g, %{role: "member"}}} = Guilds.join(member, guild.id)
    assert Guilds.feast(member, guild.id, %{}) == {:error, :forbidden}

    assert Guilds.feast(user, guild.id, %{}) == {:error, :not_enough_treasury}
    assert Repo.get!(Guild, guild.id).treasury == 0
  end

  test "buff_for_user: активный пир добавляет +0.05 xp_mult к бафу уровня", %{user: user, hero: hero, guild: guild} do
    cfg = %{}
    base = Guilds.buff_for_user(user.id, cfg)
    assert base["xp_mult"] == 0.0 # уровень 1 — бафов нет

    {:ok, _} = Guilds.treasury_deposit(user, hero, guild.id, 400)
    {:ok, _} = Guilds.feast(user, guild.id, cfg)

    buffed = Guilds.buff_for_user(user.id, cfg)
    assert_in_delta buffed["xp_mult"], 0.05, 0.0001
    assert buffed["attack_flat"] == 0 # пир не трогает атаку
  end

  test "feast_active?: nil и прошлое — false, будущее — true" do
    assert Guilds.feast_active?(nil) == false
    assert Guilds.feast_active?(~N[2000-01-01 00:00:00]) == false
    assert Guilds.feast_active?(NaiveDateTime.add(NaiveDateTime.utc_now(), 3600)) == true
  end
end
