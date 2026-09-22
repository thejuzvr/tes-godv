defmodule TesIdle.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        TesIdle.Repo,
        {DNSCluster, query: Application.get_env(:tes_idle, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: TesIdle.PubSub},
        {Task.Supervisor, name: TesIdle.TaskSupervisor},
        TesIdleWeb.Endpoint
      ] ++ background_children()

    opts = [strategy: :one_for_one, name: TesIdle.Supervisor]

    # ETS-таблица ограничителя атмосферных записей: advisory-лимит одного узла.
    # Создаём ДО супервизора. Если init() стоит после start_link, первый тик
    # успевает вызвать Throttle.check до появления таблицы и падает.
    TesIdle.Game.Journal.Throttle.init()

    Supervisor.start_link(children, opts)
  end

  # Фоновые воркеры отключаются в тестах через config :tes_idle, <flag>: false
  defp background_children do
    [
      maybe_child(TesIdle.Worker.GameTickWorker, :game_tick_enabled),
      maybe_child(TesIdle.Worker.ActivityFlushWorker, :activity_flush_enabled),
      maybe_child(TesIdle.Worker.EncounterWorker, :encounter_worker_enabled),
      maybe_child(TesIdle.Worker.OutboxDispatcher, :outbox_dispatcher_enabled),
      maybe_child(TesIdle.World.Kernel, :world_kernel_enabled),
      maybe_child(TesIdle.World.Aggregator, :world_aggregator_enabled)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_child(module, flag) do
    if Application.get_env(:tes_idle, flag, true), do: module
  end

  @impl true
  def config_change(changed, _new, removed) do
    TesIdleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
