defmodule TesIdle.Worker.ActivityFlushWorker do
  @moduledoc """
  Periodically flushes hero activity to database.
  WebSocket heartbeats update in-memory state,
  this worker persists it to DB.
  """

  use GenServer

  alias TesIdle.Repo
  alias TesIdle.Schemas.Hero
  import Ecto.Query

  @flush_interval :timer.seconds(30)

  # In-memory activity tracker
  @table :hero_activity

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table])
    schedule_flush()
    {:ok, %{}}
  end

  def mark_activity(hero_id) do
    :ets.insert(@table, {hero_id, DateTime.utc_now()})
  end

  @impl true
  def handle_info(:flush, state) do
    # Get all pending activity
    activities = :ets.tab2list(@table)
    :ets.delete_all_objects(@table)

    # Batch update DB
    if activities != [] do
      Enum.each(activities, fn {hero_id, timestamp} ->
        Repo.update_all(
          from(h in Hero, where: h.id == ^hero_id),
          set: [last_activity: timestamp, is_online: true]
        )
      end)
    end

    schedule_flush()
    {:noreply, state}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
