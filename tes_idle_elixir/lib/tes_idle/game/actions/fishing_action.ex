defmodule TesIdle.Game.Actions.FishingAction do
  @moduledoc """
  Рыбалка (ROADMAP Часть II): нужна локация с flags.water.
  Мульти-тик 1–5: закинул удочку → ловит несколько тиков → улов.
  Шанс улова: base + skill + погода ядра мира (дождь/гроза, Weather.fishing_bonus) + рассвет;
  причуда dawn_fisher усиливает утро. Рыба = еда (item tag "fish").
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Repo
  alias TesIdle.Game.{GameContext, Skills}
  alias TesIdle.Schemas.{Item, InventoryItem}
  import Ecto.Query

  @impl true
  def score(%GameContext{} = _ctx), do: 50

  @impl true
  def execute(%GameContext{} = ctx) do
    cfg = get_cfg(ctx)
    sd_fishing = fishing_state(ctx)

    cond do
      # Продолжение рыбалки (мульти-тик): тик ловли
      is_map(sd_fishing) -> fishing_tick(ctx, sd_fishing, cfg)
      # Начать рыбалку
      true -> start_fishing(ctx, cfg)
    end
  end

  defp start_fishing(ctx, cfg) do
    if water?(ctx) do
      ticks = Enum.random(cfg["ticks"] || [1, 5])

      {:ok,
       %{
         state_to: "fishing",
         state_data_update: %{
           "fishing" => %{"ticks_left" => ticks, "total_ticks" => ticks}
         },
         context: %{"fish_start" => "true"}
       }}
    else
      # Нет воды — тихо переключаемся на исследование
      TesIdle.Game.Actions.ExploreAction.execute(ctx)
    end
  end

  defp fishing_tick(ctx, fishing, cfg) do
    ticks_left = (fishing["ticks_left"] || 1) - 1

    cond do
      ticks_left > 0 and :rand.uniform() > catch_chance(ctx, cfg) ->
        # Пустой тик — продолжаем ждать клёва
        {:ok,
         %{
           state_to: "fishing",
           state_data_update: %{"fishing" => Map.put(fishing, "ticks_left", ticks_left)},
           context: %{}
         }}

      true ->
        # Улов! (или срок вышел с уловом в последний тик)
        catch_fish(ctx, cfg)
    end
  end

  defp catch_fish(ctx, cfg) do
    fish_item =
      Repo.one(
        from i in Item,
          where: "fish" in i.tags and i.is_active == true,
          order_by: fragment("RANDOM()"),
          limit: 1
      )

    {item_name, xp} =
      if fish_item do
        inv =
          Repo.one(
            from ii in InventoryItem,
              where: ii.hero_id == ^ctx.hero.id and ii.item_id == ^fish_item.id
          )

        if inv do
          inv |> Ecto.Changeset.change(%{quantity: inv.quantity + 1}) |> Repo.update!()
        else
          %InventoryItem{hero_id: ctx.hero.id, item_id: fish_item.id, quantity: 1}
          |> Repo.insert!()
        end

        {fish_item.name, rand_in(cfg["xp"] || [3, 8])}
      else
        {nil, rand_in(cfg["xp"] || [3, 8])}
      end

    # Навык растёт
    {skills, _} = Skills.gain(ctx.hero, :fishing, cfg["skill_xp"] || 1, Skills.rate(ctx.configs, ctx.hero))
    ctx.hero |> Ecto.Changeset.change(%{skills: skills}) |> Repo.update!()

    {:ok,
     %{
       state_to: "fishing",
       activity_complete: true,
       xp: xp,
       state_data_update: %{"fishing" => nil},
       context: %{"fish_name" => item_name || "что-то блеснуло и сорвалось"},
       item_name: item_name
     }}
  end

  @doc "S-1: шанс улова тика (открыт для статистических тестов)."
  def catch_chance(ctx, cfg) do
    base = cfg["catch_chance"] || 0.45
    skill = Skills.get(ctx.hero, :fishing) / 200.0

    # S-1: погода из ядра мира (ctx.weather), дождь/гроза улучшают клёв
    scale = cfg["weather_scale"] || 1.0
    weather_bonus = TesIdle.World.Weather.fishing_bonus(ctx.weather) * scale

    [d1, d2] = cfg["dawn_hours"] || [5, 8]
    dawn = if ctx.hour >= d1 and ctx.hour <= d2, do: cfg["dawn_bonus"] || 0.15, else: 0.0

    min(0.95, base + skill + weather_bonus + dawn)
  end

  defp water?(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}
    flags["water"] == true
  end

  defp fishing_state(ctx) do
    case Jason.decode(ctx.hero.state_data || "{}") do
      {:ok, %{"fishing" => f}} when is_map(f) -> f
      _ -> nil
    end
  end

  defp get_cfg(ctx), do: ((ctx.configs || %{})["activities"] || %{})["fishing"] || %{}

  defp rand_in([lo, hi]) when is_number(lo) and is_number(hi),
    do: Enum.random(round(lo)..round(hi))

  defp rand_in(v) when is_number(v), do: v
  defp rand_in(_), do: 5
end
