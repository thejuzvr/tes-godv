defmodule TesIdleWeb.Controllers.HeroPetsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, Location, Pet}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_pets_#{suffix}",
        email: "qa_pets_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    location =
      Repo.insert!(%Location{name: "QA Питомцы #{suffix}", location_type: "village",
        region: "Скайрим", danger_level: "Низкая", min_level: 1, max_level: 10,
        has_shop: false, has_inn: false, weather: "Ясно", flags: %{}})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Зверолов", race: "Nord", hero_class: "Warrior",
        level: 1, location_id: location.id, brain_hash: "x", personality: %{}, skills: %{},
        state_data: "{}"})

    %{user: user, hero: hero, suffix: suffix}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp pet(hero_id, name, status, created_at \\ nil) do
    Repo.insert!(%Pet{hero_id: hero_id, species: "cat", name: name, status: status,
      mood: 50.0, hunger: 30.0, loyalty: 60.0,
      created_at: created_at || DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  defp pet_names(conn) do
    body = json_response(conn, 200)
    Enum.map(body["pets"], & &1["name"])
  end

  # ─── GET /hero/me: видимость ушедшего питомца (P-1) ─────────────────

  test "hero/me: ушедший питомец виден, пока нет живого", %{user: user, hero: hero} do
    pet(hero.id, "Мурчелло", "gone")

    conn = authed_conn(user) |> get("/api/v1/hero/me")
    assert conn.status == 200
    assert pet_names(conn) == ["Мурчелло"]
  end

  test "hero/me: ушедший скрывается, как только появился новый питомец", %{user: user, hero: hero} do
    pet(hero.id, "Мурчелло", "gone", ~U[2026-09-01 10:00:00Z])
    pet(hero.id, "Лапка", "active", ~U[2026-09-02 10:00:00Z])

    conn = authed_conn(user) |> get("/api/v1/hero/me")
    assert conn.status == 200
    assert pet_names(conn) == ["Лапка"]
  end

  test "hero/me: ушедший скрывается и когда живой питомец лечится (cooldown)", %{user: user, hero: hero} do
    pet(hero.id, "Мурчелло", "gone", ~U[2026-09-01 10:00:00Z])
    pet(hero.id, "Соня", "cooldown", ~U[2026-09-02 10:00:00Z])

    conn = authed_conn(user) |> get("/api/v1/hero/me")
    assert pet_names(conn) == ["Соня"]
  end

  test "hero/me: активный и лечащийся видны вместе", %{user: user, hero: hero} do
    pet(hero.id, "Лапка", "active", ~U[2026-09-02 10:00:00Z])
    pet(hero.id, "Соня", "cooldown", ~U[2026-09-03 10:00:00Z])

    conn = authed_conn(user) |> get("/api/v1/hero/me")
    names = pet_names(conn)
    assert "Лапка" in names and "Соня" in names
    refute "Мурчелло" in names
  end

  # ─── GET /hero/pets/history ──────────────────────────────────────────

  test "pets/history: только ушедшие, новые первыми", %{user: user, hero: hero} do
    pet(hero.id, "Мурчелло", "gone", ~U[2026-09-01 10:00:00Z])
    pet(hero.id, "Наглый", "gone", ~U[2026-09-05 10:00:00Z])
    pet(hero.id, "Лапка", "active", ~U[2026-09-06 10:00:00Z])

    conn = authed_conn(user) |> get("/api/v1/hero/pets/history")
    assert conn.status == 200
    assert pet_names(conn) == ["Наглый", "Мурчелло"]
  end

  test "pets/history: пустая история → пустой список", %{user: user, hero: hero} do
    pet(hero.id, "Лапка", "active")

    conn = authed_conn(user) |> get("/api/v1/hero/pets/history")
    assert conn.status == 200
    assert pet_names(conn) == []
  end

  test "pets/history без героя → 404" do
    suffix = System.unique_integer([:positive])
    admin =
      Repo.insert!(%User{username: "qa_pets_admin_#{suffix}",
        email: "qa_pets_admin_#{suffix}@test.gg", password_hash: "x", is_admin: true})

    conn = authed_conn(admin) |> get("/api/v1/hero/pets/history")
    assert conn.status == 404
  end
end
