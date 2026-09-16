defmodule TesIdle.Game.GuildAltarTest do
  use ExUnit.Case, async: false

  alias TesIdle.Game.{Guilds, Pipeline}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildMessage, GuildOffering, User}

  import Ecto.Query, only: [from: 2]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_altar_#{suffix}",
        email: "qa_altar_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%TesIdle.Schemas.Hero{user_id: user.id, name: "QA Алтарник", race: "Nord", hero_class: "Warrior",
        level: 1, brain_hash: "x", personality: %{}, skills: %{},
        gold: 10_000, sp: 100, state_data: "{}"})

    guild = Repo.insert!(%TesIdle.Schemas.Guild{name: "Алтарная #{suffix}", leader_id: user.id, emblem: "🕯️"})
    member = Repo.insert!(%TesIdle.Schemas.GuildMember{guild_id: guild.id, user_id: user.id, role: "leader"})

    %{user: user, hero: hero, guild: guild, member: member}
  end

  defp cfg(overrides \\ %{}), do: %{"guild" => Map.merge(%{"exp_per_gold" => 1, "points_per_gold" => 0.1, "daily_points_cap" => 150, "level_exp_base" => 1000, "level_exp_growth" => 1.4, "max_level" => 20}, overrides)}

  test "offer_gold: золото сгорает, exp/points/contributed растут, хроника пишет", %{user: user, hero: hero, guild: guild} do
    {:ok, res} = Guilds.offer_gold(user, hero, 200, cfg())

    assert Repo.reload!(hero).gold == 9_800
    assert res.guild.level == 1
    assert res.guild.exp == 200
    assert res.member.points == 20        # 200 × 0.1
    assert res.member.contributed == 200
    assert res.points_awarded == 20
    assert res.level_ups == 0

    g = Repo.reload!(guild)
    assert g.exp == 200 and g.level == 1

    member_row = TesIdle.Repo.get_by!(TesIdle.Schemas.GuildMember, user_id: user.id)
    assert member_row.points == 20 and member_row.contributed == 200

    offering = Repo.get_by!(GuildOffering, guild_id: guild.id, user_id: user.id)
    assert offering.amount == 200 and offering.points == 20 and offering.kind == "gold"

    assert Guilds.offerings_recent(guild.id) == [%{username: user.username, amount: 200, points: 20, inserted_at: offering.inserted_at}]
  end

  test "offer_gold: дневной кап очков, exp не режется", %{user: user, hero: hero, guild: guild} do
    {:ok, res1} = Guilds.offer_gold(user, hero, 200, cfg(%{"daily_points_cap" => 10}))
    assert res1.points_awarded == 10        # earned 20 → кап 10
    assert res1.guild.exp == 200            # exp за всё золото

    {:ok, res2} = Guilds.offer_gold(user, hero, 40, cfg(%{"daily_points_cap" => 10}))
    assert res2.points_awarded == 0         # кап исчерпан
    assert res2.guild.exp == 240

    assert Guilds.points_today(user.id, guild.id) == 10
  end

  test "offer_gold: level-up цикл + системное сообщение", %{user: user, hero: hero, guild: guild} do
    # пороги 100 и 140: 250 exp → уровень 3, остаток 10
    {:ok, res} = Guilds.offer_gold(user, hero, 250, cfg(%{"level_exp_base" => 100, "level_exp_growth" => 1.4}))

    assert res.level_ups == 2
    assert res.guild.level == 3
    assert res.guild.exp == 10

    g = Repo.reload!(guild)
    assert g.level == 3 and g.exp == 10

    sys = Repo.all(from m in GuildMessage, where: m.guild_id == ^guild.id and m.kind == "system")
    assert length(sys) == 1
    assert hd(sys).body =~ "3 уровня"
  end

  test "offer_gold: не в гильдии и нехватка золота", %{hero: hero} do
    suffix = System.unique_integer([:positive])
    # не в гильдии
    u3 = Repo.insert!(%User{username: "qa_lone_#{suffix}", email: "qa_lone_#{suffix}@t.gg", password_hash: "x", is_admin: false})
    h3 = Repo.insert!(%TesIdle.Schemas.Hero{user_id: u3.id, name: "QA Одинокий", race: "Nord", hero_class: "Warrior",
      level: 1, brain_hash: "l", personality: %{}, skills: %{}, gold: 500, sp: 100, state_data: "{}"})
    assert Guilds.offer_gold(u3, h3, 100, cfg()) == {:error, :not_in_guild}
    assert Repo.reload!(h3).gold == 500

    # в гильдии, но золота мало
    u2 = Repo.insert!(%User{username: "qa_poor_#{suffix}", email: "qa_poor_#{suffix}@t.gg", password_hash: "x", is_admin: false})
    h2 = Repo.insert!(%TesIdle.Schemas.Hero{user_id: u2.id, name: "QA Бедный", race: "Nord", hero_class: "Warrior",
      level: 1, brain_hash: "p", personality: %{}, skills: %{}, gold: 50, sp: 100, state_data: "{}"})
    g2 = Repo.insert!(%TesIdle.Schemas.Guild{name: "Бедная #{suffix}", leader_id: u2.id, emblem: "🛡️"})
    Repo.insert!(%TesIdle.Schemas.GuildMember{guild_id: g2.id, user_id: u2.id, role: "leader"})

    assert Guilds.offer_gold(u2, h2, 100, cfg()) == {:error, :not_enough_gold}
    assert Repo.reload!(h2).gold == 50
  end

  test "buff_for: на 1 уровне бафов нет, растёт с уровнем", %{guild: _guild} do
    b1 = Guilds.buff_for(1, Guilds.cfg(%{}))
    assert b1["xp_mult"] == 0.0 and b1["attack_flat"] == 0 and b1["hp_flat"] == 0

    b3 = Guilds.buff_for(3, Guilds.cfg(%{}))
    assert b3["xp_mult"] == 0.04 and b3["attack_flat"] == 2 and b3["hp_flat"] == 20
  end

  test "buff_for_user: nil вне гильдии, баф по уровню внутри" do
    suffix = System.unique_integer([:positive])
    outsider = Repo.insert!(%User{username: "qa_out_#{suffix}", email: "qa_out_#{suffix}@t.gg", password_hash: "x", is_admin: false})
    assert Guilds.buff_for_user(outsider.id, %{}) == nil
  end

  test "apply_progression: гильдейский xp-баф множит xp, золото не трогает" do
    result = %{xp: 100, gold_change: 50}

    out = Pipeline.apply_progression(result, %{}, %{"xp_mult" => 0.04, "attack_flat" => 2, "hp_flat" => 20})
    assert out.xp == 104
    assert out.gold_change == 50

    out0 = Pipeline.apply_progression(result, %{}, nil)
    assert out0.xp == 100

    # баф × прогрессия S-4: xp × 1.0 (прогрессия) × 1.38 (20 уровень)
    out_max = Pipeline.apply_progression(result, %{}, %{"xp_mult" => 0.38})
    assert out_max.xp == 138
  end

  test "threshold_for: геометрический рост", %{} do
    c = Guilds.cfg(%{})
    assert Guilds.threshold_for(1, c) == 1000
    assert Guilds.threshold_for(2, c) == 1400
    assert Guilds.threshold_for(3, c) == 1960
  end
end
