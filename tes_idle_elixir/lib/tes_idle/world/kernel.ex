defmodule TesIdle.World.Kernel do
  @moduledoc """
  Ядро мира (W-2): одиночный GenServer со своим тиком (60с, независим от героев).

  Единственный писатель world_state. Герои читают снапшот через ETS
  (`TesIdle.World.Snapshot.current/0`) — атомарно, без блокировки.

  Порядок систем: погода → экономика → миграции → фракции → события.
  """

  use GenServer
  require Logger

  alias TesIdle.Repo
  alias TesIdle.World.{Snapshot, Weather, Economy, Migration, Factions, Events, Construction, Gates}
  alias TesIdle.Schemas.WorldState
  import Ecto.Query

  @default_tick_ms 60_000
  @flush_interval :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Публичный API ---

  @doc "Снапшот мира для читателей (ETS, не блокирует Kernel). Стройка — в публичном виде (summary)."
  def snapshot, do: Snapshot.current() |> public_snapshot()

  # Читателям (REST/WS) стройку отдаём как summary (имена/цель/прогресс),
  # внутри снапшота и в персисте — сырой блок для чистых функций Construction
  defp public_snapshot(snap) do
    snap =
      case snap["construction"] do
        nil -> snap
        block -> Map.put(snap, "construction", Construction.summary(block, TesIdle.Game.ContextBuilder.load_configs()))
      end

    # C-3: врата наружу — summary (статус/фонд/срок), внутри снапшота — сырой блок
    case snap["gates"] do
      nil -> snap
      block -> Map.put(snap, "gates", Gates.summary(block, snap["tick"] || 0))
    end
  end

  @doc "Форс мирового события (админ)."
  def force_event(type, location_id \\ nil) do
    GenServer.cast(__MODULE__, {:force_event, type, location_id})
  end

  @doc "Применить агрегированное влияние героев (вызывает World.Aggregator)."
  def apply_pressure(pressure), do: GenServer.cast(__MODULE__, {:apply_pressure, pressure})

  @doc """
  Пожертвование на стройку (C-1). Kernel жив → синхронный call (прогресс сразу в ответе);
  Kernel выключен (тесты) → офлайн-применение через Snapshot (единственный писатель не нарушен:
  параллельных писателей в тестах нет).
  """
  def donate(donor_name, amount) do
    case GenServer.whereis(__MODULE__) do
      nil -> Construction.apply_offline(donor_name, amount)
      _pid -> GenServer.call(__MODULE__, {:donate, donor_name, amount})
    end
  end

  @doc "Ручной тик (тесты/отладка)."
  def tick_now, do: GenServer.call(__MODULE__, :tick_now)

  @doc "Форс открытия врат (админ/демо C-3)."
  def open_gates_now, do: GenServer.call(__MODULE__, :open_gates_now)

  @doc """
  Взнос в фонд врат (C-3). Kernel жив → синхронный call; выключен (тесты) →
  офлайн-применение через Snapshot.
  """
  def gate_donate(hero_id, hero_name, amount) do
    case GenServer.whereis(__MODULE__) do
      nil -> Gates.apply_offline(hero_id, hero_name, amount)
      _pid -> GenServer.call(__MODULE__, {:gate_donate, hero_id, hero_name, amount})
    end
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    Snapshot.ensure_ets()

    snap =
      case load_persisted() do
        nil -> Snapshot.init_snapshot()
        persisted -> Snapshot.put(persisted)
      end

    schedule_tick(tick_ms())
    {:ok, %{snapshot: snap}}
  end

  @impl true
  def handle_info(:tick, %{snapshot: snap} = state) do
    snap2 = run_systems(snap)
    persist(snap2)
    Snapshot.put(snap2)

    Phoenix.PubSub.broadcast(TesIdle.PubSub, "world:lobby", {:world_update, public_snapshot(snap2)})

    schedule_tick(tick_ms())
    {:noreply, %{state | snapshot: snap2}}
  end

  @impl true
  def handle_call(:tick_now, _from, state) do
    snap2 = run_systems(state.snapshot)
    persist(snap2)
    Snapshot.put(snap2)
    Phoenix.PubSub.broadcast(TesIdle.PubSub, "world:lobby", {:world_update, public_snapshot(snap2)})
    {:reply, public_snapshot(snap2), %{state | snapshot: snap2}}
  end

  @impl true
  def handle_call(:open_gates_now, _from, %{snapshot: snap} = state) do
    tick = (snap["tick"] || 0) + 1
    cfg = TesIdle.Game.ContextBuilder.load_configs()
    {block, events} = Gates.open(snap["gates"] || Gates.init_block(), Gates.cfg(cfg), tick, world_locations())

    snap2 =
      snap
      |> Map.put("gates", block)
      |> Map.put("events", (snap["events"] || []) ++ events)

    persist(snap2)
    Snapshot.put(snap2)
    Phoenix.PubSub.broadcast(TesIdle.PubSub, "world:lobby", {:world_update, public_snapshot(snap2)})
    {:reply, {:ok, Gates.summary(block, tick)}, %{state | snapshot: snap2}}
  end

  @impl true
  def handle_call({:donate, donor_name, amount}, _from, %{snapshot: snap} = state) do
    cfg = TesIdle.Game.ContextBuilder.load_configs()
    {block, events} =
      Construction.donate(snap["construction"] || Construction.init_block(), donor_name, amount, cfg, snap["tick"] || 0)

    snap2 =
      snap
      |> Map.put("construction", block)
      |> Map.put("events", (snap["events"] || []) ++ events)

    persist(snap2)
    Snapshot.put(snap2)
    Phoenix.PubSub.broadcast(TesIdle.PubSub, "world:lobby", {:world_update, public_snapshot(snap2)})
    {:reply, {:ok, block}, %{state | snapshot: snap2}}
  end

  @impl true
  def handle_call({:gate_donate, hero_id, hero_name, amount}, _from, %{snapshot: snap} = state) do
    cfg_all = TesIdle.Game.ContextBuilder.load_configs()
    tick = snap["tick"] || 0

    case Gates.donate(snap["gates"] || Gates.init_block(), hero_id, hero_name, amount, Gates.cfg(cfg_all), tick) do
      {:ok, block, events, closed?} ->
        snap2 =
          snap
          |> Map.put("gates", block)
          |> Map.put("events", (snap["events"] || []) ++ events)

        persist(snap2)
        Snapshot.put(snap2)
        Phoenix.PubSub.broadcast(TesIdle.PubSub, "world:lobby", {:world_update, public_snapshot(snap2)})

        if closed? do
          # Весть о запечатанных вратах — мировой фид (лучшее имя = топ-вкладчик)
          top =
            (block["donor_names"] || %{})
            |> Enum.map(fn {hid, name} -> {Map.get(block["donors"] || %{}, hid, 0), name} end)
            |> Enum.sort(:desc)
            |> List.first()

          TesIdle.Game.Guilds.News.broadcast("gate_closed", nil, %{
            "location" => block["location_name"] || "Скайрим",
            "fund" => Integer.to_string(block["fund"] || 0),
            "hero" => (top && elem(top, 1)) || "безымянные герои"
          })
        end

        {:reply, {:ok, Gates.summary(block, tick), closed?}, %{state | snapshot: snap2}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:force_event, type, location_id}, %{snapshot: snap} = state) do
    events = Events.force(snap["events"], type, location_id, config_pool(), snap["tick"])
    persist_events(events)
    {:noreply, %{state | snapshot: Map.put(snap, "events", events)}}
  end

  def handle_cast({:apply_pressure, pressure}, %{snapshot: snap} = state) do
    prices = Economy.apply_pressure(snap["prices"], pressure[:purchases] || %{})

    density =
      (pressure[:kills] || %{})
      |> Enum.reduce(snap["density"], fn {loc_id, n}, acc ->
        # Охота героев разрежает популяцию (в пределах коридора)
        factor = max(0.8, 1.0 - 0.002 * n)
        Map.update(acc, loc_id, 1.0, &(&1 * factor |> max(0.5)))
      end)

    {:noreply, %{state | snapshot: %{snap | "prices" => prices, "density" => density}}}
  end

  # --- Системы ---

  defp run_systems(snap) do
    tick = (snap["tick"] || 0) + 1
    day = if rem(tick, 24) == 0, do: (snap["day"] || 1) + 1, else: snap["day"] || 1
    season = Snapshot.season_for(day)

    weather = Weather.step(snap["weather"], season)

    # События шагают первыми — экономика/миграции читают их же тик
    locations = world_locations()
    events = Events.step(snap["events"], config_pool(), locations, tick)

    relations = snap["relations"] || %{}
    wars = snap["wars"] || []
    {relations, new_wars, war_events} = Factions.step(relations, wars)
    events = events ++ Enum.map(war_events, &Map.put(&1, "id", Ecto.UUID.generate()))

    # Дефекция города (редко)
    {factions, events} =
      case Factions.maybe_defect(snap["factions"]) do
        nil ->
          {snap["factions"], events}

        {city_id, from, to} ->
          Logger.info("world: city #{city_id} defects from #{from} to #{to}")
          factions = Map.update!(snap["factions"], from, &List.delete(&1, city_id)) |> Map.update(to, [city_id], &[city_id | &1])

          events =
            events ++
              [%{"id" => Ecto.UUID.generate(), "type" => "defection", "name" => "Переметнулся",
                 "desc" => "Город меняет сторону: из «#{from}» в «#{to}»", "location_id" => city_id, "ttl" => 12, "started_tick" => tick}]

          {factions, events}
      end

    war_city_ids = Factions.war_city_ids(factions, new_wars)
    prices = Economy.step(snap["prices"], war_city_ids, events)
    density = Migration.step(snap["density"], events)

    # C-1 стройка: паломники понемногу достраивают сами; события стадии/проекта — в мировой фид
    cfg = TesIdle.Game.ContextBuilder.load_configs()
    {construction, construction_events} =
      Construction.step(snap["construction"] || Construction.init_block(), cfg, tick)
    events = events ++ construction_events

    # C-3 врата: редкое открытие над городом, срок/фонд; события oblivion_gate/gate_closed/gate_fallen
    {gates, gates_events} = Gates.step(snap["gates"] || Gates.init_block(), Gates.cfg(cfg), tick, locations)
    events = events ++ gates_events

    # Редкая фактическая миграция монстра
    if :rand.uniform() < Migration.move_chance(), do: Migration.move_one_monster()

    # Map.put, не %{snap | ...}: у старых персистов ключа "construction" ещё нет
    snap
    |> Map.put("tick", tick)
    |> Map.put("day", day)
    |> Map.put("season", season)
    |> Map.put("weather", weather)
    |> Map.put("events", events)
    |> Map.put("relations", relations)
    |> Map.put("wars", new_wars)
    |> Map.put("factions", factions)
    |> Map.put("prices", prices)
    |> Map.put("density", density)
    |> Map.put("construction", construction)
    |> Map.put("gates", gates)
  end

  defp world_locations do
    # Schema-запрос: Ecto сам декодирует id в UUID-строку (schemaless отдаёт raw binary
    # → binary в location_id события ронял Jason при персисте снапшота, S-1)
    Repo.all(from l in TesIdle.Schemas.Location, select: {l.id, l.name, l.region, l.location_type})
  rescue
    _ -> []
  end

  defp config_pool do
    (kernel_config()["event_pool"] || Events.default_pool())
  end

  defp kernel_config do
    TesIdle.Game.ContextBuilder.load_configs()["world_kernel"] || %{}
  rescue
    _ -> %{}
  end

  defp tick_ms do
    kernel_config()["tick_ms"] || @default_tick_ms
  end

  defp schedule_tick(ms) when is_integer(ms) and ms > 0, do: Process.send_after(self(), :tick, ms)
  defp schedule_tick(_), do: Process.send_after(self(), :tick, @default_tick_ms)

  # --- Персистентность ---

  defp load_persisted do
    case Repo.get_by(WorldState, key: "snapshot") do
      nil -> nil
      row -> row.value
    end
  rescue
    _ -> nil
  end

  defp persist(snap) do
    upsert("snapshot", snap)
  end

  defp persist_events(events) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(events, fn e ->
      Repo.insert!(
        %TesIdle.Schemas.WorldEvent{
          event_type: e["type"],
          title: e["name"] || e["type"],
          payload: e,
          active: true,
          started_at: now,
          expires_at: if(e["ttl"], do: DateTime.add(now, e["ttl"] * 60, :second)),
          created_at: now,
        },
        on_conflict: :nothing,
        conflict_target: :id
      )
    end)
  end

  defp upsert(key, value) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %WorldState{key: key, value: value, updated_at: now},
      on_conflict: [set: [value: value, updated_at: now]],
      conflict_target: :key
    )
  end

  # Держим flush-интервал для читаемости (Aggregator сам решает, когда слать)
  def flush_interval, do: @flush_interval
end
