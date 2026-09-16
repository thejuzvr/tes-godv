defmodule TesIdleWeb.EquipmentController do
  use TesIdleWeb, :controller

  alias TesIdle.Game.{ContextBuilder, Skyforge}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Equipment, InventoryItem, Item}
  import Ecto.Query

  @slot_map %{
    "weapon" => :weapon_id, "head" => :head_id, "body" => :body_id,
    "legs" => :legs_id, "ring" => :ring_id, "amulet" => :amulet_id,
  }

  def index(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      equip = Repo.one(from e in Equipment, where: e.hero_id == ^hero.id)
      configs = ContextBuilder.load_configs()
      forge_cfg = Skyforge.cfg(configs)
      levels = TesIdle.Game.Skyforge.levels_for_hero(hero.id)
      cap = forge_cfg["cap"]

      slots = if equip do
        ["weapon", "head", "body", "legs", "ring", "amulet"]
        |> Enum.map(fn slot ->
          item_id = Map.get(equip, String.to_existing_atom("#{slot}_id"))
          item = if item_id, do: Repo.get(Item, item_id)
          {slot, if(item, do: %{
            id: item.id, name: item.name, icon: item.icon, rarity: item.rarity,
            attack_bonus: item.attack_bonus, defense_bonus: item.defense_bonus, hp_bonus: item.hp_bonus,
            sharpen_level: Map.get(levels, item.id, 0),
            sharpen_cap: cap,
            next_sharpen_cost: if(Map.get(levels, item.id, 0) < cap, do: TesIdle.Game.Skyforge.price(Map.get(levels, item.id, 0) + 1, forge_cfg))
          })}
        end)
        |> Map.new()
      else
        %{"weapon" => nil, "head" => nil, "body" => nil, "legs" => nil, "ring" => nil, "amulet" => nil}
      end

      json(conn, %{
        slots: slots,
        hero_gold: hero.gold
      })
    end
  end

  # ── C-2: Небесная кузня — заточка экипировки ─────────────────────────────────

  @doc "Заточка слота: POST /equipment/enhance/:slot"
  def enhance(conn, %{"slot" => slot}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    configs = ContextBuilder.load_configs()

    cond do
      is_nil(hero) ->
        conn |> put_status(404) |> json(%{detail: "Hero not found"})

      true ->
        case TesIdle.Game.Skyforge.enhance(user, hero, slot, configs) do
          {:ok, result} ->
            json(conn, %{
              slot: slot,
              item: %{id: result.item.id, name: result.item.name, icon: result.item.icon},
              level: result.level,
              price: result.price,
              gold_left: result.gold_left
            })

          {:error, :empty_slot} ->
            conn |> put_status(404) |> json(%{detail: "Slot is empty"})

          {:error, :cap_reached} ->
            conn |> put_status(409) |> json(%{error: "cap_reached"})

          {:error, :not_enough_gold} ->
            conn |> put_status(409) |> json(%{error: "not_enough_gold"})

          {:error, reason} ->
            conn |> put_status(400) |> json(%{error: inspect(reason)})
        end
    end
  end

  def equip(conn, %{"id" => item_id}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    inv_item = if hero, do: Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^item_id)
    item = if inv_item, do: Repo.get(Item, item_id)
    slot_field = if item && item.equip_slot, do: @slot_map[item.equip_slot]

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(inv_item) or is_nil(item) ->
        conn |> put_status(:not_found) |> json(%{detail: "Item not in inventory"})

      is_nil(item.equip_slot) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Item is not equippable"})

      is_nil(slot_field) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Invalid slot: #{item.equip_slot}"})

      true ->
        equip = Repo.one(from e in Equipment, where: e.hero_id == ^hero.id)
        equip = if equip, do: equip, else: Repo.insert!(%Equipment{hero_id: hero.id})

        # Unequip current
        current_id = Map.get(equip, slot_field)
        if current_id do
          existing = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^current_id)
          if existing do
            existing |> Ecto.Changeset.change(%{quantity: existing.quantity + 1}) |> Repo.update!()
          else
            Repo.insert!(%InventoryItem{hero_id: hero.id, item_id: current_id, quantity: 1})
          end
        end

        # Remove new item from inventory
        if inv_item.quantity > 1 do
          inv_item |> Ecto.Changeset.change(%{quantity: inv_item.quantity - 1}) |> Repo.update!()
        else
          Repo.delete!(inv_item)
        end

        # Set new equipped item
        equip |> Ecto.Changeset.change(%{slot_field => item.id}) |> Repo.update!()

        json(conn, %{message: "Equipped #{item.name} in #{item.equip_slot}", slot: item.equip_slot})
    end
  end

  def unequip(conn, %{"slot" => slot}) do
    valid_slots = ["weapon", "head", "body", "legs", "ring", "amulet"]
    slot_field = @slot_map[slot]

    user = conn.assigns.current_user
    hero = if slot_field, do: Repo.one(from h in Hero, where: h.user_id == ^user.id)
    equip = if hero, do: Repo.one(from e in Equipment, where: e.hero_id == ^hero.id)
    item_id = if equip, do: Map.get(equip, slot_field)

    cond do
      is_nil(slot_field) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Invalid slot. Valid: #{inspect(valid_slots)}"})

      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(equip) ->
        conn |> put_status(:not_found) |> json(%{detail: "No equipment found"})

      is_nil(item_id) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Nothing equipped in #{slot}"})

      true ->
        # Move item back to inventory
        existing = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^item_id)
        if existing do
          existing |> Ecto.Changeset.change(%{quantity: existing.quantity + 1}) |> Repo.update!()
        else
          Repo.insert!(%InventoryItem{hero_id: hero.id, item_id: item_id, quantity: 1})
        end

        # Clear slot
        equip |> Ecto.Changeset.change(%{slot_field => nil}) |> Repo.update!()

        json(conn, %{message: "Unequipped item from #{slot}", slot: slot})
    end
  end
end
