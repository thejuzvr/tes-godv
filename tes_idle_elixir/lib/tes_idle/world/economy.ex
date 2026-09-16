defmodule TesIdle.World.Economy do
  @moduledoc """
  Экономика (W-4): множители цен по городам и категориям (решение 8).

  - Категории: food / gear / rare / lodging
  - Дрейф к базису 2%/тик
  - Война ×1.4 на вовлечённые города
  - Ярмарка −20%
  - Покупки героев давят цену вверх (+0.5% за покупку, агрегатор масштабирует √(n/10))
  - Пределы: 0.6–1.8 (world_limits.price_cap)
  """

  @categories ["food", "gear", "rare", "lodging"]
  @base_return 0.02
  @war_multiplier 1.4
  @fair_discount 0.8
  @gate_surcharge 1.3
  @min 0.6
  @max 1.8

  def categories, do: @categories

  @doc "Шаг экономики. Чистая функция."
  def step(prices, wars, events) when is_map(prices) do
    war_cities = war_cities(prices, wars)

    Map.new(prices, fn {city_id, cats} ->
      cats =
        Map.new(cats, fn {cat, price} ->
          p =
            price
            |> drift_to_base()
            |> apply_war(war_cities, city_id)
            |> apply_fair(events, city_id)
            |> apply_gate(events, city_id)
            |> clamp()

          {cat, round2(p)}
        end)

      {city_id, cats}
    end)
  end

  defp drift_to_base(p), do: p + (1.0 - p) * @base_return

  defp apply_war(p, war_cities, city_id) do
    if city_id in war_cities, do: p * @war_multiplier, else: p
  end

  defp apply_fair(p, events, city_id) do
    fair? = Enum.any?(events || [], fn e -> e["type"] == "fair" and e["location_id"] == city_id end)
    if fair?, do: p * @fair_discount, else: p
  end

  # C-3: открытые врата над городом — цены ×1.3 (регион в опасности)
  defp apply_gate(p, events, city_id) do
    gate? = Enum.any?(events || [], fn e -> e["type"] == "oblivion_gate" and e["location_id"] == city_id end)
    if gate?, do: p * @gate_surcharge, else: p
  end

  @doc "Давление покупок от агрегатора: +0.5% × √(n/10) на категорию города."
  def apply_pressure(prices, purchases) when is_map(purchases) do
    Map.new(prices, fn {city_id, cats} ->
      city_purchases = purchases[city_id] || %{}

      cats =
        Map.new(cats, fn {cat, price} ->
          n = city_purchases[cat] || 0

          if n > 0 do
            factor = 1.0 + 0.005 * :math.sqrt(n / 10)
            {cat, price * factor |> clamp() |> round2()}
          else
            {cat, price}
          end
        end)

      {city_id, cats}
    end)
  end

  @doc "Множитель для конкретного города/категории (с защитой)."
  def price_for(prices, city_id, category) do
    prices
    |> Map.get(city_id, %{})
    |> Map.get(to_category(category), 1.0)
    |> clamp()
  end

  # Маппинг предмета в категорию экономики
  def to_category("food"), do: "food"
  def to_category("gear"), do: "gear"
  def to_category("rare"), do: "rare"
  def to_category("lodging"), do: "lodging"
  def to_category(item_type) when item_type in ["consumable"], do: "food"
  def to_category(item_type) when item_type in ["equipment"], do: "gear"
  def to_category(item_type) when item_type in ["material", "junk"], do: "rare"
  def to_category(_), do: "gear"

  defp clamp(p), do: p |> max(@min) |> min(@max)
  defp round2(p), do: Float.round(p * 1.0, 3)

  defp war_cities(_prices, wars) do
    # war_cities вычисляются из снапшота снаружи (factions) — тут войны это
    # пары фракций; города передаются готовым списком через apply_pressure?
    # В step/3 wars — уже список city_id (разворачивается в Kernel).
    if is_list(wars) and wars != [] and is_binary(hd(wars)), do: wars, else: []
  end
end
