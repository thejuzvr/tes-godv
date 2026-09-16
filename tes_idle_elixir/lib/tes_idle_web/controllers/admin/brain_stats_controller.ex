defmodule TesIdleWeb.Admin.BrainStatsController do
  @moduledoc """
  S-5: телеметрия ядра решений — какие цели выбирают герои и почему.

  Aggregate по decision_log всех героев (ротация 50 на героя).
  """
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  import Ecto.Query

  def show(conn, _params) do
    rows =
      Repo.all(
        from h in "heroes",
          select: %{
            hero_id: h.id,
            name: h.name,
            level: h.level,
            log: fragment("?::jsonb->'brain'->'decision_log'", h.state_data)
          }
      )

    entries =
      Enum.flat_map(rows, fn row ->
        case row.log do
          log when is_list(log) ->
            Enum.map(log, fn e ->
              %{
                hero: row.name,
                level: row.level,
                day: e["day"],
                goal: e["goal"],
                utility: e["utility"],
                world: e["world"] || %{},
              }
            end)

          _ ->
            []
        end
      end)

    by_goal =
      entries
      |> Enum.group_by(& &1.goal)
      |> Enum.map(fn {goal, list} ->
        %{goal: goal, count: length(list), avg_utility: avg(Enum.map(list, & &1.utility))}
      end)
      |> Enum.sort_by(&(-&1.count))

    by_hero =
      Enum.map(rows, fn row ->
        hero_entries = Enum.filter(entries, &(&1.hero == row.name))

        %{
          hero: row.name,
          level: row.level,
          decisions: length(hero_entries),
          top_goal: hero_entries |> Enum.frequencies_by(& &1.goal) |> Enum.max_by(fn {_g, n} -> n end, fn -> {nil, 0} end) |> elem(0)
        }
      end)
      |> Enum.sort_by(&(-&1.decisions))

    world_map = %{
      with_events: Enum.count(entries, fn e -> e.world["events"] != [] and e.world["events"] != nil end),
      with_war: Enum.count(entries, fn e -> (e.world["wars"] || 0) > 0 end),
      total: length(entries),
    }

    json(conn, %{
      total_decisions: length(entries),
      by_goal: by_goal,
      by_hero: by_hero,
      world_context: world_map,
    })
  end

  defp avg([]), do: 0.0

  defp avg(values) do
    nums = Enum.filter(values, &is_number/1)
    if nums == [], do: 0.0, else: Float.round(Enum.sum(nums) / length(nums) * 1.0, 3)
  end
end
