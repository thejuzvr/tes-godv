defmodule TesIdle.World.Snapshot do
  @moduledoc """
  Снапшот состояния мира — единственная структура, которую читают герои.

  Живёт в ETS (`:world_snapshot`, атомарное чтение без блокировки Kernel)
  и персистится в `world_state` (key = "snapshot") для восстановления.

  Все случайности сидируются детерминированно от (day, tick) — реплей и отладка.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.Location
  import Ecto.Query

  @ets_table :world_snapshot
  @seasons ["весна", "лето", "осень", "зима"]
  @weathers ["clear", "cloud", "rain", "storm", "snow"]

  # --- ETS доступ ---

  def ensure_ets do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Текущий снапшот (из ETS). Если мира ещё нет — инициализирует."
  def current do
    ensure_ets()

    case :ets.lookup(@ets_table, :snapshot) do
      [{:snapshot, snap}] -> snap
      [] ->
        snap = init_snapshot()
        put(snap)
        snap
    end
  end

  def put(snap) do
    ensure_ets()
    :ets.insert(@ets_table, {:snapshot, snap})
    snap
  end

  # --- Инициализация из БД ---

  def init_snapshot do
    locations = Repo.all(from l in Location, select: {l.id, l.name, l.region, l.location_type})
    cities = Enum.filter(locations, fn {_id, _name, _region, type} -> type == "city" end)
    all_locs = Enum.map(locations, fn {id, _n, _r, _t} -> id end)

    # Фракции городов: из лор-конфига (game_configs "law".factions_by_region по имени города)
    lore = lore_faction_map()

    factions =
      cities
      |> Enum.map(fn {id, name, _r, _t} -> {id, Map.get(lore, name, "Независимые")} end)
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))

    weather = Map.new(Enum.uniq(Enum.map(locations, fn {_i, _n, region, _t} -> region end)), fn region ->
      {region, initial_weather(region)}
    end)

    %{
      "day" => current_game_day(),
      "tick" => 0,
      "season" => season_for(current_game_day()),
      "weather" => weather,
      "prices" => init_prices(cities),
      "density" => Map.new(all_locs, fn id -> {id, 1.0} end),
      "factions" => factions,
      "relations" => init_relations(Map.keys(factions)),
      "wars" => [],
      "events" => [],
      "construction" => TesIdle.World.Construction.init_block(),
    }
  end

  defp lore_faction_map do
    alias TesIdle.Game.ContextBuilder
    (ContextBuilder.load_configs()["law"] || %{})["factions_by_region"] || %{}
  rescue
    _ -> %{}
  end

  defp initial_weather(region) do
    # Детерминированный старт: холодный север — облачно, иначе ясно
    if region in ["Скайрим", "Test"], do: "cloud", else: "clear"
  end

  defp current_game_day do
    alias TesIdle.Schemas.Hero
    case Repo.one(from h in Hero, select: max(h.game_day)) do
      nil -> 1
      day -> day
    end
  rescue
    _ -> 1
  end

  defp init_prices(cities) do
    Map.new(cities, fn {id, _n, _r, _t} ->
      {id, %{"food" => 1.0, "gear" => 1.0, "rare" => 1.0, "lodging" => 1.0}}
    end)
  end

  defp init_relations(factions) do
    base = Map.new(pairs(factions), fn {a, b} -> {relation_key(a, b), 0} end)

    # Лор: Империя против Братьев Бури — почти война
    base
    |> Map.put(relation_key("Империя", "Братья Бури"), -70)
    |> Map.put(relation_key("Империя", "Независимые"), 10)
  end

  defp pairs(list), do: for({a, idx} <- Enum.with_index(list), b <- Enum.drop(list, idx + 1), into: [], do: {a, b})

  @doc "Ключ пары фракций (порядок не важен)."
  def relation_key(a, b) when a <= b, do: "#{a}|#{b}"
  def relation_key(a, b), do: "#{b}|#{a}"

  # --- Сезоны (год 360 дней) ---

  def season_for(day) do
    idx = rem(max(1, day) - 1, 360) |> div(90) |> min(3)
    Enum.at(@seasons, idx)
  end

  @doc "Русское название погоды для UI."
  def weather_ru(w) do
    case w do
      "clear" -> "Ясно"
      "cloud" -> "Облачно"
      "rain" -> "Дождь"
      "storm" -> "Гроза"
      "snow" -> "Снег"
      other -> other
    end
  end

  def weathers, do: @weathers
  def seasons, do: @seasons
end
