defmodule TesIdle.Game.Actions.TravelAction do
  @moduledoc "Hero travels to another location — multi-tick journey."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Repo
  alias TesIdle.Game.GameContext
  alias TesIdle.Schemas.Location
  import Ecto.Query

  @impl true
  def score(%GameContext{} = ctx) do
    # Don't score if already traveling
    if traveling?(ctx), do: 0, else: location_weight(ctx.location_type, :traveling)
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    state_data = decode_state_data(ctx.hero)

    if state_data["travel"] do
      # Continue existing travel
      travel_cfg = get_in(ctx.configs || %{}, ["travel"]) || %{}
      tick_fatigue_cost = travel_cfg["tick_fatigue_cost"] || 3
      tick_sp_cost = travel_cfg["tick_sp_cost"] || 2
      travel = state_data["travel"]
      new_ticks = travel["ticks_left"] - 1

      if new_ticks <= 0 do
        # Arrive at destination
        dest_id = travel["destination_id"]
        dest = Repo.get(Location, dest_id)

        {:ok,
         %{
           state_to: "exploring",
           location_change: dest_id,
           fatigue_change: -tick_fatigue_cost,
           sp_change: -tick_sp_cost,
           events: ["arrived_#{dest && dest.name}"],
           context: %{"travel_arrived" => true, "destination_name" => dest && dest.name}
         }}
      else
        # Still traveling
        new_travel = %{travel | "ticks_left" => new_ticks}

        {:ok,
         %{
           state_to: "traveling",
           state_data_update: %{"travel" => new_travel},
           fatigue_change: -tick_fatigue_cost,
           sp_change: -tick_sp_cost
         }}
      end
    else
      # Start new journey
      travel_cfg = get_in(ctx.configs, ["travel"]) || %{}
      fatigue_cost = travel_cfg["fatigue_cost"] || 15
      gold_cost = travel_cfg["gold_cost"] || 5
      sp_cost = travel_cfg["sp_cost"] || 10

      # Find destination: random location with min_level <= hero level, different from current
      hero_level = ctx.hero.level
      current_id = ctx.hero.location_id

      destinations =
        Repo.all(
          from l in Location,
            where: l.id != ^current_id and l.min_level <= ^hero_level,
            select: [:id, :name, :location_type]
        )

      if destinations != [] do
        # Фаза 2 (аудит): активный квест задаёт цель поездки — шаг collect
        # требует город/деревню с лавкой, kill/explore — дикие земли.
        # Без этого герой с ослабленным квестом метался между случайными
        # локациями и не выполнял шаг.
        dest =
          if ctx.active_quest do
            wanted = quest_wanted_types(ctx)

            # Грабля: Enum.random/1 на пустом списке кидает Enum.EmptyError и валит
            # ВЕСЬ тик (воркер глотает — хроника молчит, герой стоит). Если квестовых
            # типов среди доступных назначений нет — честный фоллбек на любые.
            case Enum.filter(destinations, &(&1.location_type in wanted)) do
              [] -> Enum.random(destinations)
              wanted_dests -> Enum.random(wanted_dests)
            end
          else
            Enum.random(destinations)
          end

        ticks = rand_in(travel_cfg["ticks"] || [2, 5])

        travel_data = %{
          "destination_id" => to_string(dest.id),
          "destination_name" => dest.name,
          "ticks_left" => ticks,
          "total_ticks" => ticks
        }

        {:ok,
         %{
           state_to: "traveling",
           fatigue_change: -fatigue_cost,
           gold_change: -gold_cost,
           sp_change: -sp_cost,
           state_data_update: %{"travel" => travel_data},
           events: ["departed_to_#{dest.name}"]
         }}
      else
        # No valid destination — stay
        {:ok, %{state_to: "exploring"}}
      end
    end
  end

  defp traveling?(ctx) do
    state_data = decode_state_data(ctx.hero)
    ctx.hero.state == "traveling" || state_data["travel"] != nil
  end

  defp decode_state_data(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end

  defp rand_in([lo, hi]) when is_number(lo) and is_number(hi),
    do: Enum.random(round(lo)..round(hi))

  defp rand_in(value) when is_number(value), do: round(value)

  defp location_weight("city", :traveling), do: 10
  defp location_weight("village", :traveling), do: 15
  defp location_weight(_, :traveling), do: 5

  # Типы локаций, где можно выполнить текущий шаг квеста (для выбора цели).
  defp quest_wanted_types(ctx) do
    step_type = quest_step_type(ctx)

    case step_type do
      "collect" -> ["city", "village"]
      "kill" -> ["wilderness", "dungeon"]
      "explore" -> ["wilderness", "dungeon", "village"]
      _ -> []
    end
  end

  defp quest_step_type(ctx) do
    alias TesIdle.Repo
    alias TesIdle.Schemas.QuestStep
    import Ecto.Query

    aq = ctx.active_quest

    if aq do
      step =
        Repo.one(
          from s in QuestStep,
            where: s.quest_id == ^aq.quest_id and s.step_order == ^aq.current_step,
            limit: 1,
            select: s.step_type
        )

      step || "explore"
    else
      "explore"
    end
  end
end
