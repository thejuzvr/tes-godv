defmodule TesIdleWeb.UserSocket do
  use Phoenix.Socket

  channel "hero:*", TesIdleWeb.HeroChannel
  channel "world:lobby", TesIdleWeb.WorldChannel
  channel "guild:*", TesIdleWeb.GuildChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case TesIdle.Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case TesIdle.Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            {:ok, assign(socket, :user_id, user.id)}
          _ -> :error
        end
      _ -> :error
    end
  end

  def connect(_, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
