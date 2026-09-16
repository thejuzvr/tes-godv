defmodule TesIdle.Game.Actions.LootAction do
  @moduledoc "Hero loots — gold (30% chance) + items from MonsterLoot (10% chance)."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Repo
  alias TesIdle.Game.GameContext
  alias TesIdle.Schemas.{Item, InventoryItem, MonsterLoot}
  import Ecto.Query

  @impl true
  def score(%GameContext{} = ctx) do
    location_weight(ctx.location_type, :looting)
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    hero_id = ctx.hero.id
    location_id = ctx.hero.location_id

    # 30% chance for gold
    gold = if :rand.uniform() < 0.3, do: Enum.random(1..10), else: 0

    # 10% chance for item drop from MonsterLoot at current location
    {item_name, item_icon} = if location_id != nil && :rand.uniform() < 0.1 do
      loot_entry = Repo.one(
        from ml in MonsterLoot,
          join: m in assoc(ml, :monster),
          where: m.location_id == ^location_id and m.is_active == true,
          order_by: fragment("RANDOM()"),
          limit: 1,
          select: %{item_id: ml.item_id}
      )

      if loot_entry do
        item = Repo.get(Item, loot_entry.item_id)
        if item do
          # Add to inventory
          inv = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero_id and ii.item_id == ^item.id)
          if inv do
            inv |> Ecto.Changeset.change(%{quantity: inv.quantity + 1}) |> Repo.update!()
          else
            %InventoryItem{hero_id: hero_id, item_id: item.id, quantity: 1} |> Repo.insert!()
          end
          {item.name, item.icon}
        else
          {nil, nil}
        end
      else
        {nil, nil}
      end
    else
      {nil, nil}
    end

    {:ok, %{
      state_to: "looting",
      gold_change: gold,
      item_name: item_name,
      item_icon: item_icon,
      loot: %{type: if(item_name, do: "item", else: "gold"), amount: if(item_name, do: item_name, else: to_string(gold))},
    }}
  end

  defp location_weight("dungeon", :looting), do: 20
  defp location_weight("wilderness", :looting), do: 15
  defp location_weight(_, :looting), do: 5
end
