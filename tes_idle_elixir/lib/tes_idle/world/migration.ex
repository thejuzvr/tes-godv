defmodule TesIdle.World.Migration do
  @moduledoc """
  Миграция монстров (W-5): плотности по локациям + реальный переток.

  - density[location_id] — случайное блуждание 0.5–2.0
  - Событие "monster_wave"/"dragon" поднимает плотность в затронутых локациях
  - С шансом ~10%/тик один активный монстр переезжает в соседнюю локацию
    того же региона (Kernel — единственный писатель мира, БД-запрос допустим)
  """

  @walk 0.05
  @min 0.5
  @max 2.0
  @move_chance 0.10

  @doc "Шаг плотностей. Чистая функция (события задают множители)."
  def step(density, events) when is_map(density) do
    boosted = event_boosts(events)

    Map.new(density, fn {loc_id, d} ->
      d2 = d + (:rand.uniform() * 2 - 1) * @walk
      d3 = d2 * Map.get(boosted, loc_id, 1.0)
      {loc_id, d3 |> max(@min) |> min(@max) |> Float.round(3)}
    end)
  end

  defp event_boosts(events) do
    (events || [])
    |> Enum.reduce(%{}, fn e, acc ->
      case e["type"] do
        t when t in ["monster_wave", "dragon"] ->
          loc = e["location_id"]
          if loc, do: Map.update(acc, loc, 1.8, &max(&1, 1.8)), else: acc

        _ ->
          acc
      end
    end)
  end

  @doc "Множитель вероятности встречи (±30% по world_limits.encounter_cap)."
  def encounter_factor(density) do
    1.0 + (density - 1.0) * 0.6
    |> max(0.7)
    |> min(1.3)
  end

  @doc "Шанс фактического переезда монстра за тик ядра."
  def move_chance, do: @move_chance

  @doc """
  Перемещение одного активного монстра в другую локацию того же региона.
  Возвращает :moved | :no_move | :error. Пишет в БД (вызывает Kernel).
  """
  def move_one_monster do
    alias TesIdle.Repo
    alias TesIdle.Schemas.{Monster, Location}
    import Ecto.Query

    monsters =
      Repo.all(
        from m in Monster,
          join: l in Location, on: l.id == m.location_id,
          where: m.is_active == true,
          select: {m.id, m.location_id, l.region},
          limit: 200
      )

    case monsters do
      [] ->
        :no_move

      monsters ->
        {monster_id, from_loc, region} = Enum.random(monsters)

        targets =
          Repo.all(
            from l in Location,
              where: l.region == ^region and l.location_type in ["wilderness", "dungeon", "village"],
              select: l.id
          )
          |> Enum.reject(&(&1 == from_loc))

        case targets do
          [] ->
            :no_move

          targets ->
            target = Enum.random(targets)
            {count, _} = Repo.update_all(from(m in Monster, where: m.id == ^monster_id), set: [location_id: target])
            if count > 0, do: :moved, else: :error
        end
    end
  rescue
    _ -> :error
  end
end
