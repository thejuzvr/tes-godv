defmodule TesIdleWeb.Admin.ContentController do
  @moduledoc """
  Ручное управление каталогом контента: предметы и монстры.

  Отличие от SimulationController: тот генерирует случайные пачки,
  здесь — явное создание/правка/удаление одиночных записей (админка).
  Схемы и changeset'ы те же (`Schemas.Item`, `Schemas.Monster`), так что
  валидация не дублируется.
  """
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Item, Location, Monster}
  import Ecto.Query

  @item_types ~w(consumable equipment junk)
  @rarities ~w(common uncommon rare epic legendary)
  @equip_slots ~w(weapon head body legs ring amulet)
  @per_page 40

  # ─── Предметы ────────────────────────────────────────

  def items_index(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = @per_page
    search = params["q"]
    type = params["type"]

    query =
      from(i in Item,
        order_by: [asc: i.name],
        limit: ^per_page,
        offset: ^((page - 1) * per_page)
      )

    query =
      if type in @item_types do
        where(query, [i], i.item_type == ^type)
      else
        query
      end

    query =
      if is_binary(search) and String.trim(search) != "" do
        pattern = "%#{String.trim(search)}%"
        where(query, [i], ilike(i.name, ^pattern))
      else
        query
      end

    total = Repo.aggregate(Item, :count)
    counts =
      Repo.all(from i in Item, group_by: i.item_type, select: {i.item_type, count(i.id)})
      |> Map.new()

    json(conn, %{
      items: Enum.map(Repo.all(query), &item_json/1),
      total: total,
      page: page,
      per_page: per_page,
      counts: counts
    })
  end

  def item_show(conn, %{"id" => id}) do
    case Repo.get(Item, id) do
      nil -> conn |> put_status(:not_found) |> json(%{detail: "not_found"})
      item -> json(conn, item_json(item))
    end
  end

  def item_create(conn, params) do
    attrs = item_attrs(params)

    case %Item{} |> Item.changeset(attrs) |> Repo.insert() do
      {:ok, item} ->
        conn |> put_status(:created) |> json(item_json(item))

      {:error, changeset} ->
        conn |> put_status(:bad_request) |> json(%{detail: "validation_failed", errors: errors(changeset)})
    end
  end

  def item_update(conn, %{"id" => id} = params) do
    case Repo.get(Item, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{detail: "not_found"})

      item ->
        case item |> Item.changeset(item_attrs(params, item)) |> Repo.update() do
          {:ok, updated} ->
            json(conn, item_json(updated))

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{detail: "validation_failed", errors: errors(changeset)})
        end
    end
  end

  def item_delete(conn, %{"id" => id}) do
    case Repo.get(Item, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{detail: "not_found"})

      item ->
        # Жёсткое удаление каталога: инвентарь ссылается на item_id —
        # если предмет у кого-то есть, честнее выключить (soft), чем рвать FK.
        if in_use?(item.id) do
          {:ok, updated} = item |> Item.changeset(%{is_active: false}) |> Repo.update()
          json(conn, %{status: "deactivated", item: item_json(updated)})
        else
          {:ok, _} = Repo.delete(item)
          json(conn, %{status: "deleted", id: item.id})
        end
    end
  end

  defp in_use?(item_id) do
    inventory? =
      Repo.exists?(from ii in TesIdle.Schemas.InventoryItem, where: ii.item_id == ^item_id)

    equipped? =
      Repo.exists?(
        from e in TesIdle.Schemas.Equipment,
          where:
            e.weapon_id == ^item_id or e.head_id == ^item_id or e.body_id == ^item_id or
              e.legs_id == ^item_id or e.ring_id == ^item_id or e.amulet_id == ^item_id
      )

    inventory? or equipped?
  end

  defp item_attrs(params, existing \\ %Item{}) do
    %{
      name: params["name"] || existing.name,
      description: params["description"] || existing.description || "",
      item_type: params["item_type"] || existing.item_type,
      rarity: params["rarity"] || existing.rarity || "common",
      icon: params["icon"] || existing.icon || "?",
      weight: num(params["weight"], existing.weight || 1.0),
      sell_price: int(params["sell_price"], existing.sell_price || 1),
      is_active: bool(params["is_active"], if(is_nil(existing.id), do: true, else: existing.is_active)),
      tags: parse_tags(params["tags"], existing.tags),
      heal_hp: int(params["heal_hp"], existing.heal_hp || 0),
      heal_mp: int(params["heal_mp"], existing.heal_mp || 0),
      heal_sp: int(params["heal_sp"], existing.heal_sp || 0),
      reduce_hunger: num(params["reduce_hunger"], existing.reduce_hunger || 0.0),
      reduce_fatigue: num(params["reduce_fatigue"], existing.reduce_fatigue || 0.0),
      boost_morale: num(params["boost_morale"], existing.boost_morale || 0.0),
      buff_attack: int(params["buff_attack"], existing.buff_attack || 0),
      buff_duration_ticks: int(params["buff_duration_ticks"], existing.buff_duration_ticks || 0),
      soul_restore: num(params["soul_restore"], existing.soul_restore || 0.0),
      equip_slot: params["equip_slot"] || existing.equip_slot,
      attack_bonus: int(params["attack_bonus"], existing.attack_bonus || 0),
      defense_bonus: int(params["defense_bonus"], existing.defense_bonus || 0),
      hp_bonus: int(params["hp_bonus"], existing.hp_bonus || 0),
      speed_bonus: num(params["speed_bonus"], existing.speed_bonus || 0.0)
    }
  end

  defp item_json(item) do
    %{
      id: item.id,
      name: item.name,
      description: item.description,
      item_type: item.item_type,
      rarity: item.rarity,
      icon: item.icon,
      weight: item.weight,
      sell_price: item.sell_price,
      is_active: item.is_active,
      tags: item.tags,
      heal_hp: item.heal_hp,
      reduce_hunger: item.reduce_hunger,
      reduce_fatigue: item.reduce_fatigue,
      boost_morale: item.boost_morale,
      buff_attack: item.buff_attack,
      buff_duration_ticks: item.buff_duration_ticks,
      soul_restore: item.soul_restore,
      equip_slot: item.equip_slot,
      attack_bonus: item.attack_bonus,
      defense_bonus: item.defense_bonus,
      hp_bonus: item.hp_bonus,
      speed_bonus: item.speed_bonus
    }
  end

  # ─── Монстры ─────────────────────────────────────────

  def monsters_index(conn, params) do
    page = parse_int(params["page"], 1)
    per_page = @per_page
    location_id = params["location_id"]

    query =
      from(m in Monster,
        left_join: l in Location,
        on: l.id == m.location_id,
        order_by: [asc: m.min_level, asc: m.name],
        limit: ^per_page,
        offset: ^((page - 1) * per_page),
        select: {m, l.name}
      )

    query =
      if is_binary(location_id) and location_id != "" do
        where(query, [m, _l], m.location_id == ^location_id)
      else
        query
      end

    rows = Repo.all(query)
    total = Repo.aggregate(Monster, :count)

    json(conn, %{
      monsters: Enum.map(rows, fn {m, loc_name} -> monster_json(m, loc_name) end),
      total: total,
      page: page,
      per_page: per_page
    })
  end

  def monster_create(conn, params) do
    attrs = monster_attrs(params)

    case %Monster{} |> Monster.changeset(attrs) |> Repo.insert() do
      {:ok, monster} ->
        conn |> put_status(:created) |> json(monster_json(monster, location_name(monster.location_id)))

      {:error, changeset} ->
        conn |> put_status(:bad_request) |> json(%{detail: "validation_failed", errors: errors(changeset)})
    end
  end

  def monster_update(conn, %{"id" => id} = params) do
    case Repo.get(Monster, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{detail: "not_found"})

      monster ->
        case monster |> Monster.changeset(monster_attrs(params, monster)) |> Repo.update() do
          {:ok, updated} ->
            json(conn, monster_json(updated, location_name(updated.location_id)))

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{detail: "validation_failed", errors: errors(changeset)})
        end
    end
  end

  def monster_delete(conn, %{"id" => id}) do
    case Repo.get(Monster, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{detail: "not_found"})

      monster ->
        {:ok, _} = Repo.delete(monster)
        json(conn, %{status: "deleted", id: monster.id})
    end
  end

  defp monster_attrs(params, existing \\ %Monster{}) do
    %{
      name: params["name"] || existing.name,
      description: params["description"] || existing.description || "",
      min_level: int(params["min_level"], existing.min_level || 1),
      max_level: int(params["max_level"], existing.max_level || 5),
      hp: int(params["hp"], existing.hp || 50),
      attack_min: int(params["attack_min"], existing.attack_min || 5),
      attack_max: int(params["attack_max"], existing.attack_max || 10),
      defense: int(params["defense"], existing.defense || 0),
      xp_reward: int(params["xp_reward"], existing.xp_reward || 20),
      gold_min: int(params["gold_min"], existing.gold_min || 5),
      gold_max: int(params["gold_max"], existing.gold_max || 15),
      is_active: bool(params["is_active"], if(is_nil(existing.id), do: true, else: existing.is_active)),
      location_id: blank_to_nil(params["location_id"]) || existing.location_id
    }
  end

  defp monster_json(monster, loc_name) do
    %{
      id: monster.id,
      name: monster.name,
      description: monster.description,
      min_level: monster.min_level,
      max_level: monster.max_level,
      hp: monster.hp,
      attack_min: monster.attack_min,
      attack_max: monster.attack_max,
      defense: monster.defense,
      xp_reward: monster.xp_reward,
      gold_min: monster.gold_min,
      gold_max: monster.gold_max,
      is_active: monster.is_active,
      location_id: monster.location_id,
      location_name: loc_name
    }
  end

  defp location_name(nil), do: nil

  defp location_name(id) do
    Repo.one(from l in Location, where: l.id == ^id, select: l.name)
  end

  # ─── Справочники для форм ────────────────────────────

  def options(conn, _params) do
    locations =
      Repo.all(from l in Location, order_by: [asc: l.name], select: %{id: l.id, name: l.name})

    json(conn, %{
      item_types: @item_types,
      rarities: @rarities,
      equip_slots: @equip_slots,
      locations: locations
    })
  end

  # ─── Хелперы ─────────────────────────────────────────

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> %{field: to_string(field), messages: msgs} end)
  end

  defp parse_int(value, default) do
    case Integer.parse(to_string(value || "")) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp int(nil, default), do: default
  defp int("", default), do: default
  defp int(value, _default) when is_integer(value), do: value
  defp int(value, _default) when is_float(value), do: trunc(value)

  defp int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp num(nil, default), do: default
  defp num("", default), do: default
  defp num(value, _default) when is_number(value), do: value * 1.0

  defp num(value, default) when is_binary(value) do
    normalized = String.replace(String.trim(value), ",", ".")

    case Float.parse(normalized) do
      {n, _} -> n
      _ -> default
    end
  end

  defp num(_value, default), do: default

  defp bool(nil, default), do: default
  defp bool(value, _default) when is_boolean(value), do: value
  defp bool("true", _default), do: true
  defp bool("false", _default), do: false
  defp bool(_value, default), do: default

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_tags(nil, default), do: default
  defp parse_tags([], _default), do: []

  defp parse_tags(tags, _default) when is_list(tags) do
    tags |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_tags(text, _default) when is_binary(text) do
    text |> String.split([",", " "]) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_tags(_value, default), do: default
end