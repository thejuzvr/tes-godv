defmodule TesIdle.World.Gates do
  @moduledoc """
  C-3 «Врата Обливиона»: событийный коммунальный сток (план PLAN_RETENTION_GUILDS).

  Ядро (Kernel) — единственный писатель: ключ `"gates"` в снапшоте мира — сырой блок
  (чистые функции), наружу REST/WS — `summary/1` через `Kernel.public_snapshot/1`.
  Пока врата открыты: регион в опасности (Economy: цены города ×1.3, событие oblivion_gate).
  Игроки наполняют «фонд экспедиции» — когда собран, врата запечатываются (весть + событие).
  Не собрали за срок — врата схлопываются сами (cooldown, «штраф» — новые врата позже).

  Конфиг — `game_configs["gates"]` (fallback `default_config/0`):
    open_chance — шанс открытия за тик (0.02),
    fund_target — цель фонда (2000),
    deadline_ticks — срок сбора (72 тика = 3 игровых дня),
    cooldown_ticks — пауза после закрытия/провала (48 тика = 2 дня).
  """

  alias TesIdle.World.Snapshot

  @default_cfg %{
    "open_chance" => 0.02,
    "fund_target" => 2000,
    "deadline_ticks" => 72,
    "cooldown_ticks" => 48
  }

  def default_config, do: @default_cfg

  @doc "Блок конфига gates из полного configs (fallback — тестам не нужен ContextBuilder)."
  def cfg(configs) when is_map(configs) do
    Map.merge(@default_cfg, configs["gates"] || %{})
  end

  @doc "Сырой блок врат по умолчанию (закрыты, cooldown истёк)."
  def init_block do
    %{
      "status" => "closed",
      "location_id" => nil,
      "location_name" => nil,
      "fund" => 0,
      "target" => 0,
      "opened_tick" => nil,
      "deadline_tick" => nil,
      "donors" => %{},
      "donor_names" => %{},
      "cooldown_until_tick" => 0
    }
  end

  @doc """
  Тик врат. roll — инъекция случайности (чистая функция, тесты передают 0.0/1.0).
  Возвращает {block, events}.
  """
  def step(block, cfg, tick, locations, roll \\ :rand.uniform())

  # Закрыты: пауза после прошлых врат — молчим
  def step(%{"status" => "closed", "cooldown_until_tick" => until} = block, _cfg, tick, _locations, _roll)
      when is_integer(tick) and tick < until do
    {block, []}
  end

  # Закрыты: редкий шанс открыть врата над городом
  def step(%{"status" => "closed"} = block, cfg, tick, locations, roll) do
    if roll < Map.get(cfg, "open_chance", 0.02) do
      open(block, cfg, tick, locations)
    else
      {block, []}
    end
  end

  # Открыты: срок вышел — врата схлопываются сами (фонд сгорает)
  def step(%{"status" => "open", "deadline_tick" => deadline} = block, cfg, tick, _locations, _roll)
      when tick >= deadline do
    fallen =
      block
      |> Map.put("status", "closed")
      |> Map.put("cooldown_until_tick", tick + Map.get(cfg, "cooldown_ticks", 48))

    events = [
      %{
        "id" => Ecto.UUID.generate(),
        "type" => "gate_fallen",
        "name" => "Врата схлопнулись",
        "desc" => "Фонд экспедиции не собран — «#{Map.get(block, "location_name") || "?"}» терпит ущерб ещё долго",
        "location_id" => block["location_id"],
        "ttl" => 12,
        "started_tick" => tick
      }
    ]

    {fallen, events}
  end

  # Открыты: срок не вышел — ждём фонд
  def step(block, _cfg, _tick, _locations, _roll), do: {block, []}

  def open(%{"status" => "open"} = block, _cfg, _tick, _locations), do: {block, []}

  def open(block, cfg, tick, locations) do
    cities = Enum.filter(locations, fn {_id, _name, _region, type} -> type == "city" end)

    case cities do
      [] ->
        {block, []}

      cities ->
        {loc_id, loc_name, _region, _type} = Enum.random(cities)
        target = Map.get(cfg, "fund_target", 2000)
        deadline = tick + Map.get(cfg, "deadline_ticks", 72)

        opened =
          block
          |> Map.put("status", "open")
          |> Map.put("location_id", loc_id)
          |> Map.put("location_name", loc_name)
          |> Map.put("fund", 0)
          |> Map.put("target", target)
          |> Map.put("opened_tick", tick)
          |> Map.put("deadline_tick", deadline)
          |> Map.put("donors", %{})
          |> Map.put("donor_names", %{})

        events = [
          %{
            "id" => Ecto.UUID.generate(),
            "type" => "oblivion_gate",
            "name" => "Врата Обливиона",
            "desc" => "Над «#{loc_name}» зияет багровый разлом — фонд экспедиции: #{target} золота",
            "location_id" => loc_id,
            "ttl" => Map.get(cfg, "deadline_ticks", 72),
            "started_tick" => tick
          }
        ]

        {opened, events}
    end
  end

  @doc """
  Взнос героя в фонд. Возвращает {:ok, block, events, closed?} | {:error, :not_open} | {:error, :bad_amount}.
  """
  def donate(block, hero_id, hero_name, amount, cfg, tick)

  def donate(%{"status" => "open"} = block, hero_id, hero_name, amount, cfg, tick)
      when is_integer(amount) and amount > 0 do
    fund = block["fund"] + amount
    target = block["target"]

    donors =
      Map.update(block["donors"] || %{}, hero_id, amount, &(&1 + amount))

    donor_names = Map.put(block["donor_names"] || %{}, hero_id, hero_name)

    if fund >= target do
      closed =
        block
        |> Map.put("status", "closed")
        |> Map.put("fund", fund)
        |> Map.put("donors", donors)
        |> Map.put("donor_names", donor_names)
        |> Map.put("cooldown_until_tick", tick + Map.get(cfg, "cooldown_ticks", 48))

      events = [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "gate_closed",
          "name" => "Врата запечатаны",
          "desc" => "Фонд экспедиции собран (#{fund} золота) — над «#{block["location_name"]}» снова тихо",
          "location_id" => block["location_id"],
          "ttl" => 12,
          "started_tick" => tick
        }
      ]

      {:ok, closed, events, true}
    else
      updated =
        block
        |> Map.put("fund", fund)
        |> Map.put("donors", donors)
        |> Map.put("donor_names", donor_names)

      {:ok, updated, [], false}
    end
  end

  def donate(%{"status" => "closed"}, _hero_id, _hero_name, _amount, _cfg, _tick), do: {:error, :not_open}
  def donate(_block, _hero_id, _hero_name, _amount, _cfg, _tick), do: {:error, :bad_amount}

  @doc "Наружу (REST/WS): статус, прогресс, срок, топ вкладчиков."
  def summary(block, tick \\ 0) do
    %{
      "status" => block["status"],
      "location_id" => block["location_id"],
      "location_name" => block["location_name"],
      "fund" => block["fund"],
      "target" => block["target"],
      "ticks_left" => if(block["status"] == "open", do: max(0, (block["deadline_tick"] || tick) - tick), else: nil),
      "top_donors" =>
        (block["donor_names"] || %{})
        |> Enum.map(fn {hid, name} -> %{hero_id: hid, name: name, amount: Map.get(block["donors"] || %{}, hid, 0)} end)
        |> Enum.sort_by(& &1.amount, :desc)
        |> Enum.take(5)
    }
  end

  @doc """
  Офлайн-применение (Kernel выключен в тестах): снапшот через Snapshot —
  единственный писатель не нарушен (параллельных писателей в тестах нет).
  Возвращает summary-подобную карту.
  """
  def apply_offline(hero_id, hero_name, amount) do
    snap = Snapshot.current()
    cfg = TesIdle.Game.ContextBuilder.load_configs()
    tick = snap["tick"] || 0

    case donate(snap["gates"] || init_block(), hero_id, hero_name, amount, cfg(cfg), tick) do
      {:ok, block, events, closed?} ->
        snap2 =
          snap
          |> Map.put("gates", block)
          |> Map.put("events", (snap["events"] || []) ++ events)

        Snapshot.put(snap2)
        {:ok, summary(block, tick), closed?}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
