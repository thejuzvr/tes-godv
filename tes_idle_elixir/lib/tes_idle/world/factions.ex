defmodule TesIdle.World.Factions do
  @moduledoc """
  Фракции и войны (W-6, решение 4).

  - Состав фракций динамический: 0.5%/тик один город может переметнуться
    к другой фракции (мировое событие, попадает в events)
  - relations[a,b] дрейфуют ±3; ≤ −60 → война, ≥ −30 → мир
  - Война бьёт по экономике вовлечённых городов (Economy)
  """

  @drift 3
  @war_threshold -60
  @peace_threshold -30
  @defection_chance 0.005

  @doc "Шаг отношений. Чистая. Возвращает {relations, wars, new_events}."
  def step(relations, wars) when is_map(relations) do
    relations =
      Map.new(relations, fn {key, value} ->
        v2 = value + (:rand.uniform() * 2 - 1) * @drift |> round()
        {key, v2 |> max(-100) |> min(100)}
      end)

    # Война объявляется при ≤ −60; мир — только после оттепели до ≥ −30 (гистерезис)
    entered = relations |> Enum.filter(fn {_k, v} -> v <= @war_threshold end) |> Enum.map(&elem(&1, 0))
    still_at_war = Enum.filter(wars, fn k -> Map.get(relations, k, 0) < @peace_threshold end)
    new_wars = Enum.uniq(entered ++ still_at_war)

    # События смены состояния войны
    new_events =
      (new_wars -- wars)
      |> Enum.map(&%{"type" => "war_declared", "pair" => &1})
      |> Kernel.++(Enum.map(wars -- new_wars, &%{"type" => "war_ended", "pair" => &1}))

    {relations, new_wars, new_events}
  end

  @doc """
  Возможная дефекция города. Чистая часть: возвращает {city_id, from, to} | nil.
  БД и events дополняет Kernel.
  """
  def maybe_defect(factions) when is_map(factions) do
    if :rand.uniform() < @defection_chance and map_size(factions) > 1 do
      faction_list = Map.to_list(factions)

      {from_faction, city_ids} = Enum.random(faction_list)

      if length(city_ids) > 1 do
        city_id = Enum.random(city_ids)
        to_faction = factions |> Map.keys() |> Enum.random()

        if to_faction != from_faction do
          {city_id, from_faction, to_faction}
        else
          nil
        end
      else
        nil
      end
    else
      nil
    end
  end

  @doc "Фракции городов, вовлечённых в войну (для экономики)."
  def war_city_ids(factions, wars) do
    wars
    |> Enum.flat_map(fn pair ->
      [a, b] = String.split(pair, "|")
      Map.get(factions, a, []) ++ Map.get(factions, b, [])
    end)
    |> Enum.uniq()
  end
end
