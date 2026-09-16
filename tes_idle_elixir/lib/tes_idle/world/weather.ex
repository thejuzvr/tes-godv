defmodule TesIdle.World.Weather do
  @moduledoc """
  Погода по регионам — марковские цепи (W-3).

  Каждый тик ядра: с шансом 0.25 регион меняет погоду по матрице переходов.
  Зима смещает вероятности к снегу, лето — к ясности.
  """

  # Матрица переходов: {from → [(to, weight)]}
  @chain %{
    "clear" => [{"clear", 6}, {"cloud", 3}, {"rain", 1}],
    "cloud" => [{"cloud", 4}, {"clear", 3}, {"rain", 2}, {"snow", 1}],
    "rain" => [{"rain", 4}, {"cloud", 3}, {"storm", 2}, {"clear", 1}],
    "storm" => [{"storm", 2}, {"rain", 5}, {"cloud", 3}],
    "snow" => [{"snow", 4}, {"cloud", 4}, {"clear", 2}],
  }

  @doc "Один шаг погоды для всех регионов. Чистая функция."
  def step(weather, season, change_chance \\ 0.25) when is_map(weather) do
    Map.new(weather, fn {region, w} ->
      {region, step_region(w, season, change_chance)}
    end)
  end

  defp step_region(current, season, change_chance) do
    if :rand.uniform() < change_chance do
      chain =
        current
        |> chain_for(season)
        |> Enum.flat_map(fn {to, w} -> List.duplicate(to, w) end)

      Enum.random(chain)
    else
      current
    end
  end

  defp chain_for(w, season) do
    base = Map.get(@chain, w, [{"clear", 1}])

    cond do
      season == "зима" and w in ["cloud", "clear"] ->
        Enum.map(base, fn {to, weight} ->
          {to, if(to == "snow", do: weight * 3, else: weight)}
        end)

      season == "лето" and w in ["cloud", "rain"] ->
        Enum.map(base, fn {to, weight} ->
          {to, if(to == "clear", do: weight * 2, else: weight)}
        end)

      true ->
        base
    end
  end

  @doc "Эффекты погоды на потребности героя: {hunger_delta, fatigue_delta, morale_delta}"
  def needs_effects(weather) do
    case weather do
      "rain" -> {0.0, 2.0, -1.0}
      "storm" -> {0.0, 2.0, -2.0}
      "snow" -> {1.0, 1.5, -0.5}
      "cloud" -> {0.0, 0.0, 0.0}
      _ -> {0.0, 0.0, 0.0}
    end
  end

  @doc "Бонус клёва (FishingAction, S-1): дождь +30%, гроза +15%."
  def fishing_bonus("rain"), do: 0.30
  def fishing_bonus("storm"), do: 0.15
  def fishing_bonus(_), do: 0.0

  @doc "Бонус скрытности вора (Law.witness_roll, S-1): гроза глушит шум, дождь мягчит шаги, снег мёрзлый скрип — чуть хуже."
  def stealth_bonus("storm"), do: 0.15
  def stealth_bonus("rain"), do: 0.10
  def stealth_bonus("snow"), do: 0.05
  def stealth_bonus(_), do: 0.0
end
