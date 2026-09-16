defmodule TesIdle.Worker.GameTickWorker do
  @moduledoc """
  Periodic game tick worker (W-0).

  Каждые 30 секунд запускает тик героев **параллельно** через
  Task.Supervisor (max_concurrency из конфига), чтобы тик героев и тик
  мира (WorldKernel) не блокировали друг друга.

  Ленивые офлайн-тики: герой с `is_online = false` тикается не в каждой
  волне, а раз в `offline_tick_minutes` минут (конфиг, дефолт 15) —
  мир живёт медленнее, пока за героем никто не наблюдает. Оффлайн-тик
  приходит с offset-джиттером, чтобы офлайн-герои не тикали синхронно
  одной волной после рестарта сервера. Онлайн-герой определяется флагом
  `is_online` (WS/REST-heartbeat → ActivityFlushWorker; sendBeacon на
  закрытии страницы → false).

  Ошибка одного героя не роняет волну — задача гасится с логом.
  """

  use GenServer
  require Logger

  alias TesIdle.Repo
  alias TesIdle.Game.Pipeline
  alias TesIdle.Schemas.Hero
  import Ecto.Query

  @tick_interval :timer.seconds(30)
  @task_timeout :timer.seconds(120)
  @hero_fields [
    :hp, :max_hp, :mp, :max_mp, :sp, :max_sp, :gold, :xp, :level,
    :state, :mood, :soul_energy,
    :hunger, :fatigue, :morale,
    :game_hour, :game_day, :game_era,
    :location_id, :state_data,
    :total_kills, :total_gold_earned, :total_play_time_seconds,
    :attack, :defense,
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{prev_state: %{}, offline_marks: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    # is_online нужен ДО волны: офлайн-герои пропускаются детерминированно
    heroes = Repo.all(from h in Hero, select: {h.id, h.is_online})
    concurrency = Application.get_env(:tes_idle, :tick_concurrency, 10)
    offline_minutes = Application.get_env(:tes_idle, :offline_tick_minutes, 15)
    now_ms = System.system_time(:millisecond)
    offline_interval_ms = offline_minutes * 60_000

    # Офлайн-герой тикает, если прошло ≥ интервала (± джиттер до ±20%).
    # Джиттер считается детерминированно от hero_id — рестарт воркера не
    # сбрасывает расписание (ленивый тик "должен случиться раз в N минут",
    # а не "первая волна после N минут простоя").
    {online_ids, offline_due_ids, offline_marks} =
      Enum.reduce(heroes, {[], [], state.offline_marks}, fn {hero_id, online?}, {on, off, marks} ->
        if online? do
          {[hero_id | on], off, Map.delete(marks, hero_id)}
        else
          last = Map.get(marks, hero_id, 0)
          jitter = deterministic_jitter(hero_id) * 0.2
          interval = offline_interval_ms * (1.0 + jitter)

          if now_ms - last >= interval do
            {on, [hero_id | off], Map.put(marks, hero_id, now_ms)}
          else
            {on, off, marks}
          end
        end
      end)

    hero_ids = Enum.reverse(online_ids) ++ Enum.reverse(offline_due_ids)

    {new_prev, results} =
      Task.Supervisor.async_stream(
        TesIdle.TaskSupervisor,
        hero_ids,
        &tick_hero/1,
        max_concurrency: concurrency,
        timeout: @task_timeout,
        ordered: false
      )
      |> Enum.reduce({state.prev_state, []}, fn
        {:ok, {:ok, hero_id, result, current}}, {prev, outs} ->
          delta = compute_delta(Map.get(prev, hero_id, %{}), current)
          {prev, [{hero_id, Map.put(result, :hero_delta, delta), current} | outs]}

        {:ok, {:error, hero_id, reason}}, {prev, outs} ->
          Logger.warning("tick of hero #{hero_id} failed: #{inspect(reason)}")
          {prev, outs}

        {:exit, reason}, {prev, outs} ->
          Logger.warning("tick task exited: #{inspect(reason)}")
          {prev, outs}
      end)

    Enum.each(results, fn {hero_id, result, _current} ->
      Phoenix.PubSub.broadcast(TesIdle.PubSub, "hero:#{hero_id}", {:hero_tick, result})
    end)

    schedule_tick()
    {:noreply, %{state | prev_state: new_prev, offline_marks: offline_marks}}
  end

  # Один герой — изолированная задача. Возвращает:
  # {:ok, hero_id, result, current_map} | {:error, hero_id, reason}
  defp tick_hero(hero_id) do
    try do
      {:ok, result} = Pipeline.tick(hero_id)
      hero = Repo.get!(Hero, hero_id)
      {:ok, hero_id, result, Map.take(hero, @hero_fields)}
    rescue
      e -> {:error, hero_id, Exception.message(e)}
    catch
      kind, value -> {:error, hero_id, "#{kind}: #{inspect(value)}"}
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  # Детерминированный джиттер 0..1 из UUID героя (первый байт) —
  # без :rand, чтобы расписание офлайн-тика переживало рестарт воркера.
  defp deterministic_jitter(hero_id) when is_binary(hero_id) do
    case Integer.parse(String.slice(hero_id, 0, 2), 16) do
      {v, _} -> v / 255.0
      :error -> 0.5
    end
  end

  defp deterministic_jitter(_), do: 0.5

  defp compute_delta(prev, current) do
    if map_size(prev) == 0 do
      current
    else
      Enum.reduce(current, %{}, fn {key, value}, acc ->
        if Map.get(prev, key) != value, do: Map.put(acc, key, value), else: acc
      end)
    end
  end
end
