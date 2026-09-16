defmodule TesIdleWeb.InventoryController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, InventoryItem, Item}
  import Ecto.Query

  def index(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      items = Repo.all(
        from ii in InventoryItem,
          where: ii.hero_id == ^hero.id,
          join: item in Item, on: item.id == ii.item_id,
          select: %{
            id: ii.id,
            item_id: item.id,
            name: item.name,
            icon: item.icon,
            type: item.item_type,
            rarity: item.rarity,
            quantity: ii.quantity,
            weight: item.weight,
            sell_price: item.sell_price,
          }
      )

      weight = Enum.reduce(items, 0.0, fn i, acc -> acc + (i.weight * i.quantity) end)
      max_weight = hero.max_weight || 160.0

      json(conn, %{
        items: items,
        weight: %{
          current: Float.round(weight, 1),
          max: max_weight,
          percentage: if(max_weight > 0, do: Float.round(weight / max_weight * 100, 1), else: 0),
          overweight: weight > max_weight,
          heavily_overweight: weight > max_weight * 1.5,
        }
      })
    end
  end

  def status(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      weight_result = Repo.one(
        from ii in InventoryItem,
          where: ii.hero_id == ^hero.id,
          join: item in Item, on: item.id == ii.item_id,
          select: sum(ii.quantity * item.weight)
      )
      weight = weight_result || 0.0
      max_weight = hero.max_weight || 160.0

      json(conn, %{
        weight: %{
          current: Float.round(weight, 1),
          max: max_weight,
          percentage: if(max_weight > 0, do: Float.round(weight / max_weight * 100, 1), else: 0),
          overweight: weight > max_weight,
          heavily_overweight: weight > max_weight * 1.5,
        }
      })
    end
  end

  def use_item(conn, %{"id" => item_id}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    inv_item = if hero, do: Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^item_id)
    item = if inv_item, do: Repo.get(Item, item_id)

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(inv_item) ->
        conn |> put_status(:not_found) |> json(%{detail: "Item not in inventory"})

      is_nil(item) or item.item_type != "consumable" ->
        conn |> put_status(:bad_request) |> json(%{detail: "Item is not consumable"})

      true ->
        # Apply effects
        updates = %{}
        updates = if item.heal_hp > 0, do: Map.put(updates, :hp, min(hero.max_hp, hero.hp + item.heal_hp)), else: updates
        updates = if item.reduce_hunger > 0, do: Map.put(updates, :hunger, max(0, hero.hunger - item.reduce_hunger)), else: updates
        updates = if item.boost_morale > 0, do: Map.put(updates, :morale, min(100, hero.morale + item.boost_morale)), else: updates

        if map_size(updates) > 0 do
          Repo.update!(Hero.changeset(hero, updates))
        end

        # Remove from inventory
        if inv_item.quantity > 1 do
          inv_item |> Ecto.Changeset.change(%{quantity: inv_item.quantity - 1}) |> Repo.update!()
        else
          Repo.delete!(inv_item)
        end

        json(conn, %{message: "Used #{item.name}", item: %{name: item.name, icon: item.icon}})
    end
  end

  def drop_item(conn, %{"id" => item_id}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    inv_item = if hero, do: Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^item_id)
    item = if inv_item, do: Repo.get(Item, item_id)

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(inv_item) or is_nil(item) ->
        conn |> put_status(:not_found) |> json(%{detail: "Item not in inventory"})

      true ->
        if inv_item.quantity > 1 do
          inv_item |> Ecto.Changeset.change(%{quantity: inv_item.quantity - 1}) |> Repo.update!()
        else
          Repo.delete!(inv_item)
        end

        json(conn, %{message: "Dropped #{item.name}"})
    end
  end
end
