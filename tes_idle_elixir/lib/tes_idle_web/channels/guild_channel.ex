defmodule TesIdleWeb.GuildChannel do
  @moduledoc """
  G-2: чат гильдии — topic "guild:<guild_id>".

  Джойн требует авторизованный сокет И членство в гильдии.
  Клиент шлёт "new_msg" {body} — сервер валидирует (200 симв., rate-limit 2с),
  пишет в guild_messages и broadcast'ит "chat_message" всем участникам.
  REST-фоллбеки — GuildController (send_message тоже broadcast'ит).
  """
  use TesIdleWeb, :channel

  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildMessage, User}

  @impl true
  def join("guild:" <> guild_id = topic, _payload, socket) do
    user_id = socket.assigns[:user_id]

    member? =
      user_id != nil and
        match?({%TesIdle.Schemas.Guild{id: ^guild_id}, _}, Guilds.membership(user_id))

    if member? do
      {:ok, %{topic: topic}, assign(socket, :guild_id, guild_id)}
    else
      {:error, %{reason: "not_a_member"}}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_in("new_msg", %{"body" => body}, socket) do
    guild_id = socket.assigns.guild_id
    user_id = socket.assigns.user_id

    text = body |> to_string() |> String.trim()

    cond do
      text == "" ->
        {:reply, {:error, %{reason: "empty"}}, socket}

      String.length(text) > chat_max_len() ->
        {:reply, {:error, %{reason: "too_long"}}, socket}

      rate_limited?(user_id) ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}

      true ->
        user = Repo.get!(User, user_id)

        msg =
          Repo.insert!(%GuildMessage{
            guild_id: guild_id,
            user_id: user_id,
            body: text,
            kind: "chat"
          })

        broadcast!(socket, "chat_message", %{
          id: msg.id,
          user_id: user_id,
          username: user.username,
          body: msg.body,
          kind: msg.kind,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        })

        Guilds.Prune.prune(guild_id)
        {:reply, {:ok, %{id: msg.id}}, socket}
    end
  end

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  defp chat_max_len, do: Map.get(Guilds.cfg(%{}), "chat_max_len", 200)

  # Rate-limit по последнему сообщению пользователя (БД — источник правды)
  defp rate_limited?(user_id) do
    import Ecto.Query

    last =
      from(m in GuildMessage,
        where: m.user_id == ^user_id and m.kind == "chat",
        order_by: [desc: m.inserted_at],
        limit: 1,
        select: m.inserted_at
      )
      |> Repo.one()

    case last do
      nil ->
        false

      dt ->
        limit = Map.get(Guilds.cfg(%{}), "chat_rate_limit_sec", 2)
        NaiveDateTime.diff(NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second), dt) < limit
    end
  end
end
