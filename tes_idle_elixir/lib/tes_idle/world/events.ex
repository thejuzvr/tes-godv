defmodule TesIdle.World.Events do
  @moduledoc """
  Мировые события с TTL (W-6): ярмарка, волна монстров, дракон, затмение.

  Спавн вероятностный; ручной форс — через Kernel.force_event/2 (админ).
  """

  @default_pool [
    %{"type" => "fair", "name" => "Ярмарка", "desc" => "Торговцы съехались: цены ниже на 20%", "ttl" => 24, "where" => "city"},
    %{"type" => "monster_wave", "name" => "Волна монстров", "desc" => "Из пустошей идёт нечисть", "ttl" => 12, "where" => "wilderness"},
    %{"type" => "dragon", "name" => "Дракон", "desc" => "Над землёй кружит тень дракона", "ttl" => 48, "where" => "any"},
    %{"type" => "eclipse", "name" => "Затмение", "desc" => "Солнце скрыто — тени длиннее", "ttl" => 6, "where" => "any"},
  ]

  @spawn_chance 0.15
  @max_active 3

  def default_pool, do: @default_pool

  @doc "Шаг событий: старение, истечение, вероятностный спавн. Чистая функция."
  def step(events, pool, locations, tick, spawn_chance \\ @spawn_chance) do
    pool = pool || @default_pool

    alive =
      (events || [])
      |> Enum.map(fn e -> Map.put(e, "ttl", Map.get(e, "ttl", 0) - 1) end)
      |> Enum.filter(&(&1["ttl"] > 0))

    spawned =
      if length(alive) < @max_active and :rand.uniform() < spawn_chance do
        template = Enum.random(pool)
        loc = pick_location(template, locations)

        [
          %{
            "id" => Ecto.UUID.generate(),
            "type" => template["type"],
            "name" => template["name"],
            "desc" => template["desc"],
            "location_id" => loc,
            "ttl" => template["ttl"],
            "started_tick" => tick,
          }
        ]
      else
        []
      end

    alive ++ spawned
  end

  @doc "Форс события (админ). Возвращает новое событие."
  def force(events, type, location_id, pool, tick) do
    pool = pool || @default_pool

    template =
      Enum.find(pool, &(&1["type"] == type)) ||
        %{"type" => type, "name" => type, "desc" => "Мировое событие", "ttl" => 12, "where" => "any"}

    event = %{
      "id" => Ecto.UUID.generate(),
      "type" => template["type"],
      "name" => template["name"],
      "desc" => template["desc"],
      "location_id" => location_id,
      "ttl" => template["ttl"],
      "started_tick" => tick,
    }

    (events || []) ++ [event]
  end

  defp pick_location(template, locations) do
    where = template["where"] || "any"

    candidates =
      locations
      |> Enum.filter(fn {_id, _name, _region, type} ->
        where == "any" or type == where
      end)

    case candidates do
      [] -> nil
      candidates -> candidates |> Enum.random() |> elem(0)
    end
  end

  @doc "Влияние затмения на воровство (ночной бонус усилится)."
  def eclipse_active?(events), do: Enum.any?(events || [], &(&1["type"] == "eclipse"))
end
