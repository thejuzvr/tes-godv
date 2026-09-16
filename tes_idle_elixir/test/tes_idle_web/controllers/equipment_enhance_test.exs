defmodule TesIdleWeb.Controllers.EquipmentEnhanceTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint TesIdleWeb.Endpoint

  alias TesIdle.Guardian
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Equipment, Hero, Item, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_eq_#{suffix}",
        email: "qa_eq_#{suffix}@t.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Экипировщик", race: "Nord", hero_class: "Warrior",
        level: 8, brain_hash: "e", personality: %{}, skills: %{}, gold: 1000, sp: 100, state_data: "{}"})

    body =
      Repo.insert!(%Item{name: "Кольчуга Теста #{suffix}", description: "d", item_type: "equipment", rarity: "common",
        icon: "🧥", weight: 5.0, sell_price: 30, is_active: true, tags: [],
        reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0,
        equip_slot: "body", defense_bonus: 2, hp_bonus: 5, speed_bonus: 0.0})

    Repo.insert!(%Equipment{hero_id: hero.id, body_id: body.id})

    {:ok, token, _} = Guardian.encode_and_sign(user)
    conn = make_conn() |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, user: user, hero: hero, body: body}
  end

  defp make_conn do
    Phoenix.ConnTest.build_conn()
    |> put_req_header("accept", "application/json")
  end

  test "index: отдаёт слоты с уровнем заточки и ценой следующей", %{conn: conn} do
    conn = conn |> get("/api/v1/equipment")
    assert conn.status == 200

    body = json_response(conn, 200)
    assert body["hero_gold"] == 1000
    slot = body["slots"]["body"]
    assert slot["name"] =~ "Кольчуга"
    assert slot["sharpen_level"] == 0
    assert slot["sharpen_cap"] == 10
    assert slot["next_sharpen_cost"] == 50
  end

  test "enhance через API: 200, списание, повторная цена растёт", %{conn: conn, hero: hero} do
    ok = conn |> post("/api/v1/equipment/enhance/body")
    assert ok.status == 200
    res = json_response(ok, 200)
    assert res["level"] == 1
    assert res["price"] == 50
    assert res["gold_left"] == 950

    index = json_response(conn |> get("/api/v1/equipment"), 200)
    assert index["slots"]["body"]["sharpen_level"] == 1
    assert index["slots"]["body"]["next_sharpen_cost"] == 174
    assert index["hero_gold"] == 950
    assert Repo.get!(Hero, hero.id).gold == 950
  end

  test "enhance: пустой слот → 404", %{conn: conn} do
    missing = conn |> post("/api/v1/equipment/enhance/ring")
    assert missing.status == 404
  end
end
