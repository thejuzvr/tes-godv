defmodule TesIdle.Game.GuildRolesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildApplication, GuildMember, GuildMessage, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])

    leader =
      Repo.insert!(%User{username: "qa_leader_#{suffix}",
        email: "qa_leader_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%TesIdle.Schemas.Hero{user_id: leader.id, name: "QA Лидер", race: "Nord", hero_class: "Warrior",
        level: 10, brain_hash: "l", personality: %{}, skills: %{}, gold: 2000, sp: 100, state_data: "{}"})

    {:ok, guild} =
      Guilds.create(leader, hero, %{name: "Знамя Теста #{suffix}", emblem: "⚔️", policy: "request", motto: nil, description: nil}, %{})

    %{leader: leader, guild: guild, suffix: suffix}
  end

  defp joiner_user(suffix, tag) do
    u =
      Repo.insert!(%User{username: "qa_#{tag}_#{suffix}",
        email: "qa_#{tag}_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    Repo.insert!(%TesIdle.Schemas.Hero{user_id: u.id, name: "QA #{tag}", race: "Nord", hero_class: "Warrior",
      level: 5, brain_hash: tag, personality: %{}, skills: %{}, gold: 1000, sp: 100, state_data: "{}"})

    u
  end

  test "apply_to_join: заявка создаётся, дубликат — already_applied, open-гильдия — policy_open", %{leader: leader, guild: guild, suffix: suffix} do
    applicant = joiner_user(suffix + 10, "app")

    assert {:ok, %GuildApplication{}} = Guilds.apply_to_join(applicant, guild.id)
    assert {:error, :already_applied} = Guilds.apply_to_join(applicant, guild.id)
    assert {:error, :already_in_guild} = Guilds.apply_to_join(leader, guild.id)

    open =
      Repo.insert!(%TesIdle.Schemas.Guild{name: "Открытое Знамя #{suffix}", leader_id: leader.id, emblem: "🔥", policy: "open"})

    assert {:error, :policy_open} = Guilds.apply_to_join(applicant, open.id)
  end

  test "decide_application: member не может — forbidden; officer одобряет → member + системное сообщение", %{leader: leader, guild: guild, suffix: suffix} do
    applicant = joiner_user(suffix + 11, "cand")
    officer = joiner_user(suffix + 12, "off")

    Repo.insert!(%GuildMember{guild_id: guild.id, user_id: officer.id, role: "officer"})
    {:ok, app} = Guilds.apply_to_join(applicant, guild.id)

    # лидер назначает офицера — проверка set_role тут же
    assert {:ok, _} = Guilds.set_role(leader, guild.id, officer.id, "officer")

    # офицер одобряет
    assert {:ok, "approved"} = Guilds.decide_application(officer, app.id, "approved")

    {g, m} = Guilds.membership(applicant.id)
    assert g.id == guild.id
    assert m.role == "member"

    sys =
      Repo.all(from(m in GuildMessage, where: m.guild_id == ^guild.id and m.kind == "system"))

    assert Enum.any?(sys, &(&1.body =~ "вступает в знамя"))
  end

  test "decide_application: reject меняет статус без членства", %{guild: guild, suffix: suffix} do
    applicant = joiner_user(suffix + 13, "rej")
    {:ok, app} = Guilds.apply_to_join(applicant, guild.id)

    assert {:ok, "rejected"} = Guilds.decide_application(leader_of_test(guild), app.id, "rejected")
    assert Repo.reload!(app).status == "rejected"
    assert Guilds.membership(applicant.id) == nil
  end

  test "set_role: только лидер, кап 3 офицеров, лидера менять нельзя", %{leader: leader, guild: guild, suffix: suffix} do
    m1 = joiner_user(suffix + 14, "m1")
    m2 = joiner_user(suffix + 15, "m2")
    m3 = joiner_user(suffix + 16, "m3")
    m4 = joiner_user(suffix + 17, "m4")

    for u <- [m1, m2, m3, m4] do
      Repo.insert!(%GuildMember{guild_id: guild.id, user_id: u.id, role: "member"})
    end

    # member не может менять роли
    assert {:error, :forbidden} = Guilds.set_role(m1, guild.id, m2.id, "officer")

    # лидер назначает троих
    assert {:ok, _} = Guilds.set_role(leader, guild.id, m1.id, "officer")
    assert {:ok, _} = Guilds.set_role(leader, guild.id, m2.id, "officer")
    assert {:ok, _} = Guilds.set_role(leader, guild.id, m3.id, "officer")

    # четвёртый — кап
    assert {:error, :officers_cap} = Guilds.set_role(leader, guild.id, m4.id, "officer")

    # понижение освобождает слот
    assert {:ok, _} = Guilds.set_role(leader, guild.id, m3.id, "member")
    assert {:ok, _} = Guilds.set_role(leader, guild.id, m4.id, "officer")

    # лидера менять нельзя
    assert {:error, :cannot_change_leader} = Guilds.set_role(leader, guild.id, leader.id, "member")
  end

  test "kick: member кикается с сообщением, офицера нельзя, не-офицер — forbidden", %{leader: leader, guild: guild, suffix: suffix} do
    officer = joiner_user(suffix + 18, "kickoff")
    member = joiner_user(suffix + 19, "kickme")
    plain = joiner_user(suffix + 20, "plain")

    Repo.insert!(%GuildMember{guild_id: guild.id, user_id: officer.id, role: "officer"})
    Repo.insert!(%GuildMember{guild_id: guild.id, user_id: member.id, role: "member"})
    Repo.insert!(%GuildMember{guild_id: guild.id, user_id: plain.id, role: "member"})

    # обычный member не может кикать
    assert {:error, :forbidden} = Guilds.kick(plain, guild.id, member.id)

    # офицера кикать нельзя (даже лидером)
    assert {:error, :cannot_kick_officer} = Guilds.kick(leader, guild.id, officer.id)

    # офицер кикает member
    assert {:ok, :kicked} = Guilds.kick(officer, guild.id, member.id)
    assert Guilds.membership(member.id) == nil

    sys =
      Repo.all(from(m in GuildMessage, where: m.guild_id == ^guild.id and m.kind == "system"))

    assert Enum.any?(sys, &(&1.body =~ "кикнут"))
  end

  defp leader_of_test(guild) do
    Repo.one!(from(u in User, where: u.id == ^guild.leader_id, limit: 1))
  end
end
