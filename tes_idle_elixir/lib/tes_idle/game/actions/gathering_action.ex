defmodule TesIdle.Game.Actions.GatheringAction do
  @moduledoc """
  Собирательство (ROADMAP Часть II): локации с flags.gather_nodes.
  Травы и компоненты (tag herb/component) для алхимии (задел на Фазу 4).
  Истощение узлов — Часть III (ядра мира); здесь честный шанс + навык.
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
    cfg = ((ctx.configs || %{})["activities"] || %{})["gathering"] || %{}

    if gather?(ctx) do
      chance = min(0.95, (cfg["find_chance"] || 0.55) + Skills.get(ctx.hero, :gathering) / 250.0)

      if :rand.uniform() < chance do
        find_herb(ctx, cfg)
      else
        {:ok, %{
          state_to: "gathering",
          context: %{"herb_name" => "ничего, кроме пыльцы на рукавах"},
        }}
      end
    else
      # Нет узлов — исследуем
      TesIdle.Game.Actions.ExploreAction.execute(ctx)
    end
  end

  defp find_herb(ctx, cfg) do
    herb = Repo.one(
      from i in Item,
        where: ("herb" in i.tags or "component" in i.tags) and i.is_active == true,
        order_by: fragment("RANDOM()"),
        limit: 1
    )

    {item_name, xp} =
      if herb do
        inv = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^ctx.hero.id and ii.item_id == ^herb.id)

        if inv do
          inv |> Ecto.Changeset.change(%{quantity: inv.quantity + 1}) |> Repo.update!()
        else
          %InventoryItem{hero_id: ctx.hero.id, item_id: herb.id, quantity: 1} |> Repo.insert!()
        end

        {herb.name, rand_in(cfg["xp"] || [2, 6])}
      else
        {nil, rand_in(cfg["xp"] || [2, 6])}
      end

    {skills, _} = Skills.gain(ctx.hero, :gathering, cfg["skill_xp"] || 1, Skills.rate(ctx.configs, ctx.hero))
    ctx.hero |> Ecto.Changeset.change(%{skills: skills}) |> Repo.update!()

    {:ok, %{
      state_to: "gathering",
      xp: xp,
      item_name: item_name,
      context: %{"herb_name" => item_name || "пучок сушёных кореньев"},
    }}
  end

  defp gather?(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}
    flags["gather_nodes"] == true or ctx.location_type in ["wilderness", "village"]
  end

  defp rand_in([lo, hi]) when is_number(lo) and is_number(hi), do: Enum.random(round(lo)..round(hi))
  defp rand_in(v) when is_number(v), do: v
  defp rand_in(_), do: 4
end
