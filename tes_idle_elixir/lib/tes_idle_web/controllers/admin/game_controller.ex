defmodule TesIdleWeb.Admin.GameController do
  @moduledoc """
  Управление игровым циклом (GameTickWorker).

  Раньше отдавал захардкоженный `%{count: 0}` и «перезапускал» циклы
  пустым ответом. Теперь состояние читается у живого воркера, а tick_all
  действительно прогоняет волну тиков.
  """

  use TesIdleWeb, :controller

  require Logger

  alias TesIdle.Repo
  alias TesIdle.Schemas.Hero
  import Ecto.Query

  @tick_interval_seconds 30

  def loops(conn, _params) do
    heroes = Repo.aggregate(Hero, :count)
    online = Repo.one(from h in Hero, where: h.is_online == true, select: count(h.id)) || 0

    json(conn, %{
      count: if(Process.whereis(TesIdle.Worker.GameTickWorker), do: 1, else: 0),
      running: Process.whereis(TesIdle.Worker.GameTickWorker) != nil,
      interval_seconds: @tick_interval_seconds,
      heroes: heroes,
      online_heroes: online,
      tick_concurrency: Application.get_env(:tes_idle, :tick_concurrency, 10),
      offline_tick_minutes: Application.get_env(:tes_idle, :offline_tick_minutes, 15),
      loops: [
        %{
          name: "GameTickWorker",
          running: Process.whereis(TesIdle.Worker.GameTickWorker) != nil,
          interval_seconds: @tick_interval_seconds,
          description: "Волна тиков по героям: онлайн — каждый тик, офлайн — по расписанию"
        }
      ]
    })
  end

  @doc """
  Перезапуск воркера тиков. Раньше модуль писал «Loops restarted», ничего
  не делая. Теперь воркер честно останавливается через главный Supervisor —
  супервизор сразу поднимает свежий (strategy one_for_one), и расписание
  офлайн-тиков сбрасывается.
  """
  def restart_loops(conn, _params) do
    case Process.whereis(TesIdle.Worker.GameTickWorker) do
      nil ->
        # Воркер выключен конфигом (game_tick_enabled: false) — перезапускать нечего.
        Logger.warning("GameTickWorker не запущен — перезапуск пропущен")
        json(conn, %{message: "Воркер тиков не запущен (game_tick_enabled: false)", restarted: false})

      _pid ->
        Supervisor.terminate_child(TesIdle.Supervisor, TesIdle.Worker.GameTickWorker)
        {:ok, _} = Supervisor.restart_child(TesIdle.Supervisor, TesIdle.Worker.GameTickWorker)
        json(conn, %{message: "Циклы тиков перезапущены", restarted: true})
    end
  end

  @doc "Немедленная волна тиков по всем героям (не дожидаясь расписания)."
  def tick_all(conn, _params) do
    case Process.whereis(TesIdle.Worker.GameTickWorker) do
      nil ->
        conn |> put_status(:service_unavailable) |> json(%{detail: "tick_worker_not_running"})

      pid ->
        send(pid, :tick)
        json(conn, %{message: "Волна тиков запущена", heroes: Repo.aggregate(Hero, :count)})
    end
  end
end
