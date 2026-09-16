defmodule TesIdleWeb.Channels.GuildChannelTest do
  use TesIdleWeb.ChannelCase, async: false

  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildMessage, User}
  alias TesIdleWeb.{GuildChannel, UserSocket}

  import Ecto.Query, only: [from: 2]

  setup do
    # sandbox открывает ChannelCase (start_owner! + shared) — здесь только данные

    suffix = System.unique_integer([:positive])
    member =
      Repo.insert!(%User{username: "qa_chatter_#{suffix}",
        email: "qa_chatter_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    outsider =
      Repo.insert!(%User{username: "qa_stayer_#{suffix}",
        email: "qa_stayer_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    guild = Repo.insert!(%TesIdle.Schemas.Guild{name: "Чатовая #{suffix}", leader_id: member.id, emblem: "💬"})
    Repo.insert!(%TesIdle.Schemas.GuildMember{guild_id: guild.id, user_id: member.id, role: "leader"})

    {:ok, _, member_socket} =
      UserSocket
      |> socket("user_socket:#{member.id}", %{user_id: member.id})
      |> subscribe_and_join(GuildChannel, "guild:#{guild.id}")

    %{member: member, outsider: outsider, guild: guild, socket: member_socket, suffix: suffix}
  end

  test "join: участник входит, посторонний получает not_a_member", %{outsider: outsider, guild: guild} do
    assert {:error, %{reason: "not_a_member"}} =
             UserSocket
             |> socket("user_socket:#{outsider.id}", %{user_id: outsider.id})
             |> subscribe_and_join(GuildChannel, "guild:#{guild.id}")
  end

  test "join: без user_id — отказ", %{guild: guild} do
    assert {:error, _} =
             UserSocket
             |> socket("user_socket:anon", %{})
             |> subscribe_and_join(GuildChannel, "guild:#{guild.id}")
  end

  test "new_msg: пишется в БД и broadcast'ится", %{socket: socket, member: member} do
    push(socket, "new_msg", %{"body" => "Первое слово за короля!"})
    assert_broadcast("chat_message", payload)
    assert payload.username == member.username
    assert payload.body == "Первое слово за короля!"

    msg = Repo.one!(from m in GuildMessage, where: m.user_id == ^member.id)
    assert msg.kind == "chat"
    assert msg.body == "Первое слово за короля!"
  end

  test "new_msg: пустое и слишком длинное отклоняются", %{socket: socket, member: member} do
    ref = push(socket, "new_msg", %{"body" => "   "})
    assert_reply(ref, :error, %{reason: "empty"})

    long = String.duplicate("ж", 201)
    ref2 = push(socket, "new_msg", %{"body" => long})
    assert_reply(ref2, :error, %{reason: "too_long"})

    assert Repo.aggregate(from(m in GuildMessage, where: m.user_id == ^member.id), :count) == 0
  end

  test "new_msg: rate-limit 2 секунды", %{socket: socket, member: member} do
    ref = push(socket, "new_msg", %{"body" => "раз"})
    assert_reply(ref, :ok, %{id: _})

    ref2 = push(socket, "new_msg", %{"body" => "два"})
    assert_reply(ref2, :error, %{reason: "rate_limited"})

    assert Repo.aggregate(from(m in GuildMessage, where: m.user_id == ^member.id), :count) == 1
  end

  test "prune: хвост чистится до 500", %{guild: guild} do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    for i <- 1..520 do
      Repo.insert!(%GuildMessage{guild_id: guild.id, user_id: nil, body: "sys #{i}", kind: "system",
        inserted_at: NaiveDateTime.add(now, i)})
    end

    assert Repo.aggregate(from(m in GuildMessage, where: m.guild_id == ^guild.id), :count) == 520

    deleted = Guilds.Prune.prune(guild.id)
    assert deleted == 20

    left = Repo.aggregate(from(m in GuildMessage, where: m.guild_id == ^guild.id), :count)
    assert left == 500
  end
end
