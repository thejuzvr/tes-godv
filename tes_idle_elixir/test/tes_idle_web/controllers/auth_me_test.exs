defmodule TesIdleWeb.Controllers.AuthMeTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, Location, Reputation}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    admin =
      Repo.insert!(%User{username: "qa_admin_#{suffix}",
        email: "qa_admin_#{suffix}@test.gg", password_hash: "x", is_admin: true})

    plain =
      Repo.insert!(%User{username: "qa_plain_#{suffix}",
        email: "qa_plain_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    %{admin: admin, plain: plain, suffix: suffix}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  test "GET /api/v1/me: is_admin=true для админа, 200 без 403-шума", %{admin: admin} do
    conn = authed_conn(admin) |> get("/api/v1/me")
    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["is_admin"] == true
    assert body["username"] == admin.username
  end

  test "GET /api/v1/me: is_admin=false для обычного пользователя", %{plain: plain} do
    conn = authed_conn(plain) |> get("/api/v1/me")
    assert conn.status == 200
    assert json_response(conn, 200)["is_admin"] == false
  end

  test "GET /api/v1/me без токена → 401" do
    conn = build_conn() |> put_req_header("accept", "application/json") |> get("/api/v1/me")
    assert conn.status == 401
  end

  test "GET /api/v1/hero/reputations: список репутаций героя", %{plain: plain, suffix: suffix} do
    location =
      Repo.insert!(%Location{name: "QA Репутация #{suffix}", location_type: "village",
        region: "Скайрим", danger_level: "Низкая", min_level: 1, max_level: 10,
        has_shop: false, has_inn: false, weather: "Ясно", flags: %{}})

    hero =
      Repo.insert!(%Hero{user_id: plain.id, name: "QA Вор", race: "Nord", hero_class: "Thief",
        level: 1, location_id: location.id, brain_hash: "x", personality: %{}, skills: %{},
        state_data: "{}"})

    Repo.insert!(%Reputation{hero_id: hero.id, faction: "Имперский Легион", value: -12, level: "hostile"})
    Repo.insert!(%Reputation{hero_id: hero.id, faction: "Братья Бури", value: -30, level: "unfriendly"})

    conn = authed_conn(plain) |> get("/api/v1/hero/reputations")
    assert conn.status == 200
    reps = json_response(conn, 200)["reputations"]
    assert length(reps) == 2
    assert %{"faction" => "Имперский Легион", "value" => -12, "level" => "hostile"} in reps
  end

  test "GET /api/v1/hero/reputations: герой без записей → пустой список", %{plain: plain, suffix: suffix} do
    location =
      Repo.insert!(%Location{name: "QA Чист #{suffix}", location_type: "village",
        region: "Хаммерфелл", danger_level: "Низкая", min_level: 1, max_level: 10,
        has_shop: false, has_inn: false, weather: "Ясно", flags: %{}})

    Repo.insert!(%Hero{user_id: plain.id, name: "QA Честный", race: "Nord", hero_class: "Warrior",
      level: 1, location_id: location.id, brain_hash: "x", personality: %{}, skills: %{},
      state_data: "{}"})

    conn = authed_conn(plain) |> get("/api/v1/hero/reputations")
    assert conn.status == 200
    assert json_response(conn, 200)["reputations"] == []
  end

  test "GET /api/v1/hero/reputations без героя → 404", %{admin: admin} do
    conn = authed_conn(admin) |> get("/api/v1/hero/reputations")
    assert conn.status == 404
  end
end
