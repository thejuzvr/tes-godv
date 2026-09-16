defmodule TesIdle.Game.Actions.ShopAction do
  @moduledoc "Hero visits a shop — sells junk, buys items, auto-equip."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Repo
  alias TesIdle.Game.GameContext
  alias TesIdle.Schemas.{Item, InventoryItem, Equipment}
  import Ecto.Query

  @impl true
  def score(%GameContext{} = ctx) do
    base = if ctx.location && ctx.location.has_shop, do: 20, else: 0
    base = if ctx.needs.hunger > 70, do: base + 15, else: base
    if ctx.hour >= 6 and ctx.hour < 12, do: base + 5, else: base
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    cost = get_in(ctx.configs, ["shopping", "cost"]) || 10
    hunger_range = get_in(ctx.configs, ["shopping", "hunger_reduction"]) || [15, 30]
    _ = cost

    # Step 1: Sell junk items
    hero_id = ctx.hero.id
    junk_items = Repo.all(
      from ii in InventoryItem,
        join: i in Item, on: i.id == ii.item_id,
        where: ii.hero_id == ^hero_id and i.item_type == "junk",
        select: %{inv: ii, item: i}
    )

    gold_from_junk = Enum.reduce(junk_items, 0, fn %{inv: inv, item: item}, acc ->
      sell_value = (item.sell_price || 0) * inv.quantity
      Repo.delete!(inv)
      acc + sell_value
    end)

    # Step 2: Check gold after selling junk
    total_gold = ctx.hero.gold + gold_from_junk

    if total_gold < cost do
      # Window shopping
      hunger_reduction = Enum.random(hunger_range)
      {:ok, %{
        state_to: "shopping",
        gold_change: gold_from_junk,
        events: ["no_gold"],
        hunger_change: -hunger_reduction,
      }}
    else
      # Step 3: Buy item
      # 30% equipment, 70% consumable
      item_type = if :rand.uniform() < 0.3, do: "equipment", else: "consumable"

      items = Repo.all(
        from i in Item,
          where: i.item_type == ^item_type and i.is_active == true,
          limit: 10
      )

      if items != [] do
        item = Enum.random(items)

        # W-4: цена с мировым множителем (категория предмета × город)
        city_id = if ctx.location, do: ctx.location.id, else: nil
        category = TesIdle.World.Economy.to_category(item.item_type)
        multiplier = TesIdle.World.Economy.price_for(ctx.world && ctx.world["prices"], city_id, category)
        cost = round((get_in(ctx.configs, ["shopping", "cost"]) || 10) * multiplier)

        if total_gold < cost do
          # Мировая цена выше базовой — не хватило
          hunger_reduction = Enum.random(hunger_range)
          {:ok, %{
            state_to: "shopping",
            gold_change: gold_from_junk,
            events: ["no_gold"],
            hunger_change: -hunger_reduction,
          }}
        else
        # Давление на экономику (√(n/10) агрегация — один герой ничего не сдвинет)
        if city_id, do: TesIdle.World.Aggregator.purchase(city_id, category)

        # Add to inventory
        inv = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero_id and ii.item_id == ^item.id)
        if inv do
          inv |> Ecto.Changeset.change(%{quantity: inv.quantity + 1}) |> Repo.update!()
        else
          %InventoryItem{hero_id: hero_id, item_id: item.id, quantity: 1} |> Repo.insert!()
        end

        # Apply consumable effects immediately
        updates = %{gold: total_gold - cost}
        updates = if item.item_type == "consumable" && item.heal_hp && item.heal_hp > 0,
          do: Map.put(updates, :hp, min(ctx.hero.max_hp, ctx.hero.hp + item.heal_hp)),
          else: updates
        updates = if item.item_type == "consumable" && item.reduce_hunger && item.reduce_hunger > 0,
          do: Map.put(updates, :hunger, max(0, ctx.hero.hunger - item.reduce_hunger)),
          else: updates
        updates = if item.item_type == "consumable" && item.boost_morale && item.boost_morale > 0,
          do: Map.put(updates, :morale, min(100, ctx.hero.morale + item.boost_morale)),
          else: updates

        # Auto-equip equipment
        equip_events = if item.item_type == "equipment" && item.equip_slot do
          auto_equip(hero_id, item)
        else
          []
        end

        hunger_reduction = Enum.random(hunger_range)

        # Полировка (аудит Хроники): реальные имя/цена покупки пробрасываются
        # через context: — он мерджится ПОВЕРХ заглушек simple_context в
        # TemplateEngine. Раньше {item_name} был «припасы», {gold_spent} — «10».
        {:ok, Map.merge(%{
          state_to: "shopping",
          gold_change: gold_from_junk - cost,
          gold_spent: cost,
          item_name: item.name,
          item_icon: item.icon,
          hunger_change: -hunger_reduction,
          events: equip_events ++ ["bought_#{item.name}"],
          context: %{
            "item_name" => item.name,
            "gold_spent" => cost,
          },
        }, updates)}
        end
      else
        # No items available — just reduce hunger
        hunger_reduction = Enum.random(hunger_range)
        {:ok, %{
          state_to: "shopping",
          gold_change: gold_from_junk - cost,
          hunger_change: -hunger_reduction,
        }}
      end
    end
  end

  defp auto_equip(hero_id, item) do
    slot_map = %{
      "weapon" => :weapon_id, "head" => :head_id, "body" => :body_id,
      "legs" => :legs_id, "ring" => :ring_id, "amulet" => :amulet_id,
    }
    slot_field = Map.get(slot_map, item.equip_slot)

    if slot_field do
      equip = Repo.one(from e in Equipment, where: e.hero_id == ^hero_id)
      if equip do
        equip |> Ecto.Changeset.change(%{slot_field => item.id}) |> Repo.update!()
        ["equipped_#{item.name}"]
      else
        %Equipment{hero_id: hero_id} |> Map.put(slot_field, item.id) |> Repo.insert!()
        ["equipped_#{item.name}"]
      end
    else
      []
    end
  end
end
