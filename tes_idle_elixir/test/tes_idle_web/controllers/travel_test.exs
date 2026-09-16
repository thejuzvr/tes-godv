defmodule TesIdleWeb.Controllers.TravelTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, Location}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_travel_#{suffix}",
        email: "qa_travel_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    loc_a =
      Repo.insert!(%Location{name: "QA Деревня #{suffix}", location_type: "village",
        region: "Скайрим", danger_level: "Низкая", min_level: 1, max_level: 10,
        has_shop: false, has_inn: false, weather: "Ясно", flags: %{}})

    loc_b =
      Repo.insert!(%Location{name: "QA Город #{suffix}", location_type: "city",
        region: "Скайрим", danger_level: "Низкая", min_level: 1, max_level: 10,
        has_shop: true, has_inn: true, weather: "Ясно", flags: %{}})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Путник", race: "Nord", hero_class: "Warrior",
        level: 1, location_id: loc_a.id, brain_hash: "x", personality: %{}, skills: %{},
        gold: 100, sp: 100, state_data: "{}"})

    %{user: user, hero: hero, loc_a: loc_a, loc_b: loc_b}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  test "travel: свободный герой начинает путь, план/мозг в state_data не затираются", %{user: user, hero: hero, loc_b: loc_b} do
    # Пре-существующий план в state_data — travel обязан его сохранить
    hero
    |> Ecto.Changeset.change(%{state_data: Jason.encode!(%{"plan" => %{"steps" => ["explore"]}, "brain" => %{"generation" => 1}})})
    |> Repo.update!()

    conn = authed_conn(user) |> post("/api/v1/locations/#{loc_b.id}/travel")
    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["travel_ticks"] in 2..5

    reloaded = Repo.reload!(hero)
    sd = Jason.decode!(reloaded.state_data)
    assert sd["travel"]["destination_id"] == to_string(loc_b.id)
    assert reloaded.state == "traveling"
    # Ключевое: единственный писатель — план и мозг живы
    assert sd["plan"]["steps"] == ["explore"]
    assert sd["brain"]["generation"] == 1
    assert reloaded.gold == 95
  end

  test "travel: герой в бою → 409, state_data не тронут", %{user: user, hero: hero, loc_b: loc_b} do
    hero
    |> Ecto.Changeset.change(%{state_data: Jason.encode!(%{"combat" => %{"round" => 1}})})
    |> Repo.update!()

    conn = authed_conn(user) |> post("/api/v1/locations/#{loc_b.id}/travel")
    assert conn.status == 409

    reloaded = Repo.reload!(hero)
    sd = Jason.decode!(reloaded.state_data)
    assert sd["combat"]["round"] == 1
    refute Map.has_key?(sd, "travel")
  end

  test "travel: несуществующая локация → 404", %{user: user} do
    conn = authed_conn(user) |> post("/api/v1/locations/00000000-0000-0000-0000-000000000000/travel")
    assert conn.status == 404
  end

  test "travel без героя → 404" do
    suffix = System.unique_integer([:positive])
    admin =
      Repo.insert!(%User{username: "qa_travel_admin_#{suffix}",
        email: "qa_travel_admin_#{suffix}@test.gg", password_hash: "x", is_admin: true})

    conn = authed_conn(admin) |> post("/api/v1/locations/00000000-0000-0000-0000-000000000000/travel")
    assert conn.status == 404
  end
end
