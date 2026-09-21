defmodule TesIdleWeb.Controllers.AdminContentTest do
  @moduledoc """
  Ручной CRUD каталога контента (предметы/монстры) через админ-API.
  """
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Item, Location, Monster, User}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    admin =
      Repo.insert!(%User{
        username: "content_admin_#{suffix}",
        email: "content_admin_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: true
      })

    plain =
      Repo.insert!(%User{
        username: "content_plain_#{suffix}",
        email: "content_plain_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    location =
      Repo.insert!(%Location{
        name: "Тестовая пещера #{suffix}",
        description: "локация для теста",
        location_type: "dungeon",
        danger_level: "Средняя"
      })

    %{admin: admin, plain: plain, location: location, suffix: suffix}
  end

  defp conn_for(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  # ─── Предметы ────────────────────────────────────────

  test "create item casts numeric strings from form input", %{admin: admin} do
    conn = conn_for(admin)

    body = %{
      "name" => "Тестовое зелье",
      "item_type" => "consumable",
      "rarity" => "rare",
      "icon" => "🧪",
      "weight" => "0,3",
      "sell_price" => "12",
      "heal_hp" => "40",
      "reduce_hunger" => "15.5",
      "boost_morale" => "3",
      "tags" => "herb, component"
    }

    resp = post(conn, "/api/v1/admin/items", body)
    assert resp.status == 201

    payload = json_response(resp, 201)
    assert payload["name"] == "Тестовое зелье"
    assert payload["item_type"] == "consumable"
    assert payload["weight"] == 0.3
    assert payload["sell_price"] == 12
    assert payload["heal_hp"] == 40
    assert payload["reduce_hunger"] == 15.5
    assert payload["tags"] == ["herb", "component"]

    assert Repo.get(Item, payload["id"])
  end

  test "create item without a name is rejected", %{admin: admin} do
    resp = post(conn_for(admin), "/api/v1/admin/items", %{"item_type" => "junk"})
    assert resp.status == 400

    payload = json_response(resp, 400)
    assert payload["detail"] == "validation_failed"
    assert Enum.any?(payload["errors"], &(&1["field"] == "name"))
  end

  test "update and delete a catalog item", %{admin: admin} do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{name: "Старый клинок", item_type: "equipment", equip_slot: "weapon", weight: 3.5})
      )

    conn = conn_for(admin)

    patch_resp =
      patch(conn, "/api/v1/admin/items/#{item.id}", %{"name" => "Новый клинок", "attack_bonus" => "7"})

    assert patch_resp.status == 200
    updated = json_response(patch_resp, 200)
    assert updated["name"] == "Новый клинок"
    assert updated["attack_bonus"] == 7
    # частичный PATCH не обнуляет NOT NULL-колонки
    assert updated["equip_slot"] == "weapon"
    assert updated["weight"] == 3.5

    del_resp = delete(conn_for(admin), "/api/v1/admin/items/#{item.id}")
    assert del_resp.status == 200
    assert json_response(del_resp, 200)["status"] == "deleted"
    refute Repo.get(Item, item.id)
  end

  test "used item is deactivated instead of deleted", %{admin: admin, location: loc} do
    {:ok, item} = Repo.insert(Item.changeset(%Item{}, %{name: "Носимый хлам", item_type: "junk"}))

    hero =
      Repo.insert!(%Hero{
        user_id: admin.id,
        name: "Носитель #{System.unique_integer([:positive])}",
        race: "Норд",
        hero_class: "Воин",
        location_id: loc.id
      })

    # инвентарь ссылается на предмет — жёсткое удаление порвало бы FK
    Repo.insert_all("inventory_items", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        hero_id: Ecto.UUID.dump!(hero.id),
        item_id: Ecto.UUID.dump!(item.id),
        quantity: 1
      }
    ])

    resp = delete(conn_for(admin), "/api/v1/admin/items/#{item.id}")
    assert resp.status == 200
    assert json_response(resp, 200)["status"] == "deactivated"

    reloaded = Repo.get(Item, item.id)
    assert reloaded
    assert reloaded.is_active == false
  end

  test "items index filters by type and reports counts", %{admin: admin} do
    Repo.insert!(Item.changeset(%Item{}, %{name: "Индексный расходник", item_type: "consumable"}))

    resp = get(conn_for(admin), "/api/v1/admin/items?type=consumable")
    assert resp.status == 200

    payload = json_response(resp, 200)
    assert is_list(payload["items"])
    assert Enum.all?(payload["items"], &(&1["item_type"] == "consumable"))
    assert payload["total"] >= 1
    assert is_map(payload["counts"])
  end

  # ─── Монстры ─────────────────────────────────────────

  test "create monster with a location and form-typed numbers", %{admin: admin, location: loc} do
    body = %{
      "name" => "Тестовый драугр",
      "description" => "Создан вручную",
      "min_level" => "2",
      "max_level" => "6",
      "hp" => "75",
      "attack_min" => "6",
      "attack_max" => "14",
      "defense" => "3",
      "xp_reward" => "35",
      "gold_min" => "4",
      "gold_max" => "22",
      "location_id" => loc.id
    }

    resp = post(conn_for(admin), "/api/v1/admin/monsters", body)
    assert resp.status == 201

    payload = json_response(resp, 201)
    assert payload["name"] == "Тестовый драугр"
    assert payload["hp"] == 75
    assert payload["attack_max"] == 14
    assert payload["location_id"] == loc.id
    assert payload["location_name"] == loc.name
  end

  test "create monster without a location keeps location_id nil", %{admin: admin} do
    resp =
      post(conn_for(admin), "/api/v1/admin/monsters", %{
        "name" => "Бездомный волк",
        "hp" => "40",
        "location_id" => ""
      })

    assert resp.status == 201
    payload = json_response(resp, 201)
    assert payload["location_id"] == nil
    assert payload["location_name"] == nil
  end

  test "monster requires a name", %{admin: admin} do
    resp = post(conn_for(admin), "/api/v1/admin/monsters", %{"hp" => "10"})
    assert resp.status == 400
    assert json_response(resp, 400)["detail"] == "validation_failed"
  end

  test "update and delete a monster", %{admin: admin} do
    {:ok, monster} = Repo.insert(%Monster{name: "Старый скевер", hp: 30})

    patch_resp =
      patch(conn_for(admin), "/api/v1/admin/monsters/#{monster.id}", %{
        "name" => "Новый скевер",
        "hp" => "90",
        "is_active" => "false"
      })

    assert patch_resp.status == 200
    updated = json_response(patch_resp, 200)
    assert updated["name"] == "Новый скевер"
    assert updated["hp"] == 90
    assert updated["is_active"] == false

    del_resp = delete(conn_for(admin), "/api/v1/admin/monsters/#{monster.id}")
    assert del_resp.status == 200
    refute Repo.get(Monster, monster.id)
  end

  test "missing records return 404", %{admin: admin} do
    ghost = Ecto.UUID.generate()
    conn = conn_for(admin)

    assert get(conn, "/api/v1/admin/items/#{ghost}").status == 404
    assert patch(conn_for(admin), "/api/v1/admin/items/#{ghost}", %{"name" => "x"}).status == 404
    assert delete(conn_for(admin), "/api/v1/admin/items/#{ghost}").status == 404
    assert patch(conn_for(admin), "/api/v1/admin/monsters/#{ghost}", %{"name" => "x"}).status == 404
    assert delete(conn_for(admin), "/api/v1/admin/monsters/#{ghost}").status == 404
  end

  test "options endpoint returns form dictionaries with locations", %{admin: admin, location: loc} do
    resp = get(conn_for(admin), "/api/v1/admin/content/options")
    assert resp.status == 200

    payload = json_response(resp, 200)
    assert "consumable" in payload["item_types"]
    assert "equipment" in payload["item_types"]
    assert "weapon" in payload["equip_slots"]
    assert "legendary" in payload["rarities"]
    assert Enum.any?(payload["locations"], &(&1["id"] == loc.id))
  end

  test "non-admin cannot touch the catalog", %{plain: plain} do
    conn = conn_for(plain)

    assert get(conn, "/api/v1/admin/items").status == 403
    assert post(conn_for(plain), "/api/v1/admin/items", %{"name" => "x", "item_type" => "junk"}).status == 403
    assert post(conn_for(plain), "/api/v1/admin/monsters", %{"name" => "x"}).status == 403
  end
end
