defmodule TesIdle.Game.Actions.ExploreAction do
  @moduledoc """
  Hero explores the current location.
  S-1: засада — шанс = encounter_chance[тип локации] × Migration.encounter_factor(density мира).
  Плотный мир чаще подкидывает бой; при отсутствии монстров FightAction тихо вернёт exploring.
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.GameContext

  @impl true
  def score(%GameContext{} = ctx) do
    base = location_weight(ctx.location_type, :exploring)

    # Time-of-day adjustments
    base = cond do
      ctx.hour >= 6 and ctx.hour < 12 -> base + 10
      ctx.hour >= 12 and ctx.hour < 18 -> base + 5
      true -> base
    end

    base
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    if ambush?(ctx) do
      # FightAction.execute всегда {:ok, _}: без монстра вернёт exploring
      {:ok, result} = TesIdle.Game.Actions.FightAction.execute(ctx)
      {:ok, Map.update(result, :context, %{"ambush" => "true"}, &Map.put(&1, "ambush", "true"))}
    else
      gold_found = if :rand.uniform() < 0.15, do: Enum.random(1..10), else: 0

      {:ok, %{
        state_to: "exploring",
        gold_change: gold_found,
        events: if(gold_found > 0, do: ["found_gold"], else: []),
      }}
    end
  end

  @doc "S-1: случится ли засада на этом тике (открыт для статистических тестов)."
  def ambush?(ctx) do
    cfg = ((ctx.configs || %{})["activities"] || %{})["exploration"] || %{}
    base = Map.get(cfg["encounter_chance"] || %{}, ctx.location_type || "wilderness", 0.08)
    density = density_of(ctx)
    # «Тень»: каждый ранг чуть снижает шанс засады, но не обнуляет его.
    shade = TesIdle.Game.Passives.bonus(ctx.hero).stealth
    factor = max(0.6, 1 - shade / 200)
    :rand.uniform() < base * TesIdle.World.Migration.encounter_factor(density) * factor
  end

  defp density_of(ctx) do
    case ctx.world do
      w when is_map(w) ->
        loc_id = ctx.location && to_string(ctx.location.id)
        get_in(w, ["density", loc_id]) || 1.0

      _ ->
        1.0
    end
  end

  defp location_weight("wilderness", :exploring), do: 35
  defp location_weight("dungeon", :exploring), do: 25
  defp location_weight("village", :exploring), do: 20
  defp location_weight("city", :exploring), do: 15
  defp location_weight(_, :exploring), do: 20
end
