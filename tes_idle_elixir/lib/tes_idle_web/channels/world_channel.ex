defmodule TesIdleWeb.WorldChannel do
  @moduledoc """
  Мировой канал (W-7): topic "world:lobby".

  Ядро мира шлёт {:world_update, snapshot} — канал пересылает снапшот клиенту
  (погода/цены/события/войны). Джойн требует авторизованный сокет.
  """
  use TesIdleWeb, :channel

  @impl true
  def join("world:lobby", _payload, socket) do
    {:ok, socket}
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_info({:world_update, snapshot}, socket) do
    push(socket, "world_update", %{"snapshot" => snapshot})
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
