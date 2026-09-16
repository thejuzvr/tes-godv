defmodule TesIdle.World.Aggregator do
  @moduledoc """
  Обратное влияние героев на мир (III.2.2).

  Герои НЕ пишут в world_state напрямую. Aggregator копит события тиков
  (purchases/kills/thefts по локациям) и раз в 5 минут отдаёт накопленное
  Kernel'у с масштабом √(n/10) — один герой экономику не сдвинет.
  """

  use GenServer

  @flush_interval :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Покупка героя: давление на цену категории в городе."
  def purchase(city_id, category) do
    GenServer.cast(__MODULE__, {:purchase, city_id, category})
  end

  @doc "Убийство монстра героем: разрежение популяции локации."
  def kill(location_id) do
    GenServer.cast(__MODULE__, {:kill, location_id})
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :flush, @flush_interval)
    {:ok, %{purchases: %{}, kills: %{}}}
  end

  @impl true
  def handle_cast({:purchase, city_id, category}, state) do
    purchases =
      Map.update(state.purchases, city_id, %{category => 1}, fn cats ->
        Map.update(cats, category, 1, &(&1 + 1))
      end)

    {:noreply, %{state | purchases: purchases}}
  end

  def handle_cast({:kill, location_id}, state) do
    {:noreply, %{state | kills: Map.update(state.kills, location_id, 1, &(&1 + 1))}}
  end

  @impl true
  def handle_info(:flush, state) do
    if map_size(state.purchases) > 0 or map_size(state.kills) > 0 do
      TesIdle.World.Kernel.apply_pressure(%{purchases: state.purchases, kills: state.kills})
    end

    Process.send_after(self(), :flush, @flush_interval)
    {:noreply, %{purchases: %{}, kills: %{}}}
  end
end
