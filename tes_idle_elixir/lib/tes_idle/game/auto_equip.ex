defmodule TesIdle.Game.AutoEquip do
  @moduledoc """
  Periodic auto-equip: hero checks inventory and equips items.
  70% best stats, 30% random (motivation).
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Equipment, InventoryItem, Item}
  import Ecto.Query

  @slot_map %{
    "weapon" => :weapon_id, "head" => :head_id, "body" => :body_id,
    "legs" => :legs_id, "ring" => :ring_id, "amulet" => :amulet_id,
  }

  def check_and_equip(hero_id) do
    hero = Repo.get!(Hero, hero_id) |> Repo.preload([:equipment])

    # Get inventory items that are equippable
    inv_items = Repo.all(
      from ii in InventoryItem,
        where: ii.hero_id == ^hero_id,
        join: item in Item, on: item.id == ii.item_id,
        where: not is_nil(item.equip_slot),
        select: {ii, item}
    )

    if inv_items == [] do
      []
    else
      # Group by slot
      by_slot = Enum.group_by(inv_items, fn {_ii, item} -> item.equip_slot end)

      equip = hero.equipment || Repo.insert!(%Equipment{hero_id: hero_id})

      Enum.flat_map(by_slot, fn {slot, items} ->
        slot_field = @slot_map[slot]
        if slot_field do
          process_slot(equip, slot_field, items, hero)
        else
          []
        end
      end)
    end
  end

  defp process_slot(equip, slot_field, items, hero) do
    current_id = Map.get(equip, slot_field)

    # Sort by score descending
    sorted = Enum.sort_by(items, fn {_ii, item} -> item_score(item) end, :desc)
    {_best_inv, best_item} = hd(sorted)
    best_score = item_score(best_item)

    current_score = if current_id do
      case Enum.find(items, fn {_ii, item} -> item.id == current_id end) do
        {_, item} -> item_score(item)
        _ -> 0
      end
    else
      0
    end

    # Motivation: 70% best, 30% random
    should_equip = cond do
      :rand.uniform() < 0.7 -> best_score > current_score
      true ->
        candidates = Enum.filter(sorted, fn {_ii, item} ->
          is_nil(current_id) or item.id != current_id
        end)
        candidates != []
    end

    if should_equip do
      # Choose item
      chosen = if :rand.uniform() < 0.7 do
        best_item
      else
        candidates = Enum.filter(sorted, fn {_ii, item} ->
          is_nil(current_id) or item.id != current_id
        end)
        if candidates != [] do
          {_, item} = Enum.random(candidates)
          item
        else
          best_item
        end
      end

      # Unequip current
      if current_id do
        existing = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^current_id)
        if existing do
          existing |> Ecto.Changeset.change(%{quantity: existing.quantity + 1}) |> Repo.update!()
        else
          Repo.insert!(%InventoryItem{hero_id: hero.id, item_id: current_id, quantity: 1})
        end
      end

      # Remove new item from inventory
      inv_item = Enum.find(items, fn {ii, _} -> ii.item_id == chosen.id end) |> elem(0)
      if inv_item.quantity > 1 do
        inv_item |> Ecto.Changeset.change(%{quantity: inv_item.quantity - 1}) |> Repo.update!()
      else
        Repo.delete!(inv_item)
      end

      # Equip
      equip |> Ecto.Changeset.change(%{slot_field => chosen.id}) |> Repo.update!()

      ["equipped_#{chosen.name}"]
    else
      []
    end
  end

  defp item_score(item) do
    (item.attack_bonus || 0) + (item.defense_bonus || 0) + (item.hp_bonus || 0)
  end
end
