defmodule TesIdleWeb.Controllers.HeroSkillsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, User, Location}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "skills_#{suffix}",
        email: "skills_#{suffix}@example.test",
        password_hash: "hash"
      })

    location =
      Repo.insert!(%Location{
        name: "Skills Water #{suffix}",
        region: "Test",
        location_type: "wilderness",
        danger_level: "Низкая"
      })

    Repo.insert!(%Hero{
      user_id: user.id,
      location_id: location.id,
      name: "Рыбак #{suffix}",
      race: "Nord",
      hero_class: "Warrior",
      brain_hash: "skills-hash-#{suffix}",
      personality: %{},
      skills: %{"fishing" => 27.5, "gathering" => 4.0},
      state: "fishing",
      state_data: Jason.encode!(%{"fishing" => %{"ticks_left" => 2, "total_ticks" => 5}})
    })

    {:ok, token, _claims} = TesIdle.Guardian.encode_and_sign(user)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")

    %{conn: conn}
  end

  test "hero response exposes mastery and normalized activity progress", %{conn: conn} do
    body = conn |> get("/api/v1/hero/me") |> json_response(200)

    assert body["skills"]["fishing"] == 27.5
    assert body["skills"]["gathering"] == 4.0
    assert body["skills"]["stealth"] == 0

    assert body["activity"] == %{
             "kind" => "fishing",
             "phase" => "in_progress",
             "target_name" => nil,
             "ticks_done" => 3,
             "ticks_left" => 2,
             "total_ticks" => 5
           }
  end
end
