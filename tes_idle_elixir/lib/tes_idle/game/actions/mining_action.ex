defmodule TesIdle.Game.Actions.MiningAction do
  @moduledoc """
  Добыча руды на локациях с `flags.ore_nodes`.

  Работа занимает несколько тиков: Action возвращает изменения `state_data`,
  а единственный писатель Pipeline/FSM сохраняет их вместе с остальным состоянием.
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Repo
  alias TesIdle.Game.{GameContext, Skills}
  alias TesIdle.Schemas.{InventoryItem, Item}
  import Ecto.Query

  @impl true
  def score(%GameContext{} = _ctx), do: 50

  @impl true
  def execute(%GameContext{} = ctx) do
    cfg = get_cfg(ctx)

    case mining_state(ctx) do
      mining when is_map(mining) -> mining_tick(ctx, mining, cfg)
      nil -> start_mining(ctx, cfg)
    end
  end

  defp start_mining(ctx, cfg) do
    if ore_nodes?(ctx) do
      ticks = rand_in(cfg["ticks"] || [2, 4])

      {:ok,
       %{
         state_to: "mining",
         state_data_update: %{"mining" => %{"ticks_left" => ticks, "total_ticks" => ticks}},
         context: %{"mining_phase" => "start", "ore_name" => "жила ещё не поддалась"}
       }}
    else
      TesIdle.Game.Actions.ExploreAction.execute(ctx)
    end
  end

  defp mining_tick(ctx, mining, cfg) do
    ticks_left = max(0, (mining["ticks_left"] || 1) - 1)

    if ticks_left > 0 do
      {:ok,
       %{
         state_to: "mining",
         state_data_update: %{"mining" => Map.put(mining, "ticks_left", ticks_left)},
         context: %{"mining_phase" => "wait", "ore_name" => "звон кирки о камень"}
       }}
    else
      finish_mining(ctx, cfg)
    end
  end

  defp finish_mining(ctx, cfg) do
    ore =
      if :rand.uniform() < (cfg["find_chance"] || 0.0) do
        Repo.one(
          from i in Item,
            where: "ore" in i.tags and i.is_active == true,
            order_by: fragment("RANDOM()"),
            limit: 1
        )
      end

    item_name = if ore, do: add_to_inventory(ctx.hero.id, ore), else: nil
    xp = rand_in(cfg["xp"] || [3, 7])
    {skills, _} = Skills.gain(ctx.hero, :mining, cfg["skill_xp"] || 1, Skills.rate(ctx.configs))
    ctx.hero |> Ecto.Changeset.change(%{skills: skills}) |> Repo.update!()

    {:ok,
     %{
       state_to: "mining",
       activity_complete: true,
       xp: xp,
       item_name: item_name,
       state_data_update: %{"mining" => nil},
       context: %{"mining_phase" => "found", "ore_name" => item_name || "только каменная крошка"}
     }}
  end

  defp add_to_inventory(hero_id, ore) do
    case Repo.one(
           from ii in InventoryItem, where: ii.hero_id == ^hero_id and ii.item_id == ^ore.id
         ) do
      nil -> Repo.insert!(%InventoryItem{hero_id: hero_id, item_id: ore.id, quantity: 1})
      inv -> inv |> Ecto.Changeset.change(%{quantity: inv.quantity + 1}) |> Repo.update!()
    end

    ore.name
  end

  defp ore_nodes?(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}
    flags["ore_nodes"] == true
  end

  defp mining_state(ctx) do
    case Jason.decode(ctx.hero.state_data || "{}") do
      {:ok, %{"mining" => mining}} when is_map(mining) -> mining
      _ -> nil
    end
  end

  defp get_cfg(ctx), do: ((ctx.configs || %{})["activities"] || %{})["mining"] || %{}

  defp rand_in([lo, hi]) when is_number(lo) and is_number(hi),
    do: Enum.random(round(lo)..round(hi))

  defp rand_in(v) when is_number(v), do: round(v)
  defp rand_in(_), do: 5
end
