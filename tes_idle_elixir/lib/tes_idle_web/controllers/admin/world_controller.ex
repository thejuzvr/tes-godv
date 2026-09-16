defmodule TesIdleWeb.Admin.WorldController do
  @moduledoc "W-6: просмотр состояния ядра мира + ручной тик + форс событий."
  use TesIdleWeb, :controller

  alias TesIdle.World.Kernel
  import Ecto.Query

  def show(conn, _params) do
    snap = Kernel.snapshot()
    events = TesIdle.Repo.all(from TesIdle.Schemas.WorldEvent, order_by: [desc: :created_at], limit: 20)

    json(conn, %{
      snapshot: snap,
      events: Enum.map(events, &%{id: &1.id, event_type: &1.event_type, title: &1.title,
        active: &1.active, created_at: &1.created_at}),
    })
  end

  def tick(conn, _params) do
    snap = Kernel.tick_now()
    json(conn, %{snapshot: snap})
  end

  def force_event(conn, %{"type" => type} = params) do
    Kernel.force_event(type, params["location_id"])
    json(conn, %{ok: true, forced: type})
  end

  def force_event(conn, _params), do: conn |> put_status(400) |> json(%{error: "type required"})

  # C-3: форс открытия врат (демо/отладка)
  def open_gates(conn, _params) do
    case Kernel.open_gates_now() do
      {:ok, summary} -> json(conn, %{ok: true, gates: summary})
      _ -> conn |> put_status(500) |> json(%{error: "kernel_unavailable"})
    end
  end
end
