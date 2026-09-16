defmodule TesIdleWeb.Controllers.LocationsIndexTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Location}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_map_#{suffix}",
        email: "qa_map_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    %{user: user}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  test "index отдаёт координаты карты и флаги активностей", %{user: user} do
    Repo.insert!(%Location{name: "QA Карта #{System.unique_integer([:positive])}",
      region: "Скайрим", location_type: "village", danger_level: "Низкая",
      min_level: 1, max_level: 5, has_shop: true, has_inn: true,
      map_x: 540, map_y: 560, flags: %{"water" => true, "gather_nodes" => true}})

    conn = authed_conn(user) |> get("/api/v1/locations")
    assert conn.status == 200
    body = json_response(conn, 200)
    loc = Enum.find(body, &String.starts_with?(&1["name"], "QA Карта "))
    assert loc["map_x"] == 540
    assert loc["map_y"] == 560
    assert loc["flags"]["water"] == true
    assert loc["flags"]["gather_nodes"] == true
  end

  test "index: локация без координат отдаёт nil (не крашит карту)", %{user: user} do
    Repo.insert!(%Location{name: "QA БезКоорд #{System.unique_integer([:positive])}",
      region: "Скайрим", location_type: "city", danger_level: "Средняя",
      min_level: 1, max_level: 5, has_shop: false, has_inn: false})

    conn = authed_conn(user) |> get("/api/v1/locations")
    assert conn.status == 200
    body = json_response(conn, 200)
    loc = Enum.find(body, &String.starts_with?(&1["name"], "QA БезКоорд "))
    assert Map.has_key?(loc, "map_x")
    assert is_nil(loc["map_x"]) and is_nil(loc["map_y"])
    assert loc["flags"] == %{}
  end
end
