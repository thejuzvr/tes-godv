defmodule TesIdleWeb.Controllers.HeroSocialTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Repo

  alias TesIdle.Schemas.{
    EncounterParticipant,
    GameConfig,
    Hero,
    HeroBlock,
    HeroEncounter,
    HeroRelationship,
    HeroRelationshipSide,
    Location,
    User
  }

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    location =
      Repo.insert!(%Location{
        name: "Social QA #{suffix}",
        location_type: "village",
        region: "Скайрим",
        danger_level: "Низкая",
        min_level: 1,
        max_level: 10,
        has_shop: false,
        has_inn: false,
        weather: "Ясно",
        flags: %{}
      })

    {user, hero} = identity("owner", suffix, location.id)
    {other_user, other} = identity("other", suffix, location.id)
    {_foreign_user, foreign} = identity("foreign", suffix, location.id)

    %{
      user: user,
      hero: hero,
      other_user: other_user,
      other: other,
      foreign: foreign,
      location: location
    }
  end

  test "social endpoints require authentication" do
    for path <- [
          "/api/v1/hero/encounters",
          "/api/v1/hero/relationships",
          "/api/v1/hero/social-settings"
        ] do
      assert build_conn() |> get(path) |> json_response(401) == %{"detail" => "Not authenticated"}
    end
  end

  test "encounters are scoped, paginated and expose only safe participant label", ctx do
    own = encounter(ctx.hero, ctx.other, ctx.location, "own:1")

    Repo.insert!(%EncounterParticipant{
      encounter_id: own.id,
      hero_id: ctx.hero.id,
      role: "initiator",
      private_payload: %{
        "counterpart_label" => "Странник в капюшоне",
        "secret_roll" => 99,
        "email" => "never@example.test"
      }
    })

    Repo.insert!(%EncounterParticipant{
      encounter_id: own.id,
      hero_id: ctx.other.id,
      private_payload: %{"counterpart_label" => "Should not leak", "secret" => true}
    })

    foreign = encounter(ctx.other, ctx.foreign, ctx.location, "foreign:1")

    Repo.insert!(%EncounterParticipant{
      encounter_id: foreign.id,
      hero_id: ctx.other.id,
      private_payload: %{"counterpart_label" => "Foreign"}
    })

    body = authed_conn(ctx.user) |> get("/api/v1/hero/encounters?limit=1") |> json_response(200)

    assert [%{"id" => id, "counterpart_label" => "Странник в капюшоне"} = item] =
             body["encounters"]

    assert id == own.id
    assert item["role"] == "initiator"
    refute Map.has_key?(item, "private_payload")
    refute Map.has_key?(item, "shared_payload")
    refute Map.has_key?(item, "hero_low_id")
    refute Map.has_key?(item, "hero_high_id")
    refute id == foreign.id
  end

  test "relationships include only current hero's asymmetric side", ctx do
    {low, high} = ordered(ctx.hero, ctx.other)

    relationship =
      Repo.insert!(%HeroRelationship{
        hero_low_id: low.id,
        hero_high_id: high.id,
        familiarity: 7,
        encounter_count: 2,
        shared_tags: ["met"]
      })

    Repo.insert!(%HeroRelationshipSide{
      relationship_id: relationship.id,
      hero_id: ctx.hero.id,
      affinity: 4,
      tags: ["trusted"],
      private_payload: %{"secret" => "mine"}
    })

    Repo.insert!(%HeroRelationshipSide{
      relationship_id: relationship.id,
      hero_id: ctx.other.id,
      affinity: -50,
      tags: ["enemy"],
      private_payload: %{"secret" => "theirs"}
    })

    body = authed_conn(ctx.user) |> get("/api/v1/hero/relationships") |> json_response(200)

    assert [%{"affinity" => 4, "tags" => ["trusted"], "counterpart_id" => counterpart_id} = item] =
             body["relationships"]

    assert counterpart_id == ctx.other.id
    refute Map.has_key?(item, "private_payload")
    refute item["affinity"] == -50
  end

  test "settings return safe config-driven defaults and ignore supplied hero_id", ctx do
    Repo.insert!(
      %GameConfig{
        key: "hero_social",
        value:
          Jason.encode!(%{
            "default_daily_cap" => 5,
            "max_daily_cap" => 8,
            "default_cooldown_seconds" => 90
          }),
        description: "test"
      },
      on_conflict: {:replace, [:value, :description]},
      conflict_target: :key
    )

    defaults = authed_conn(ctx.user) |> get("/api/v1/hero/social-settings") |> json_response(200)

    assert defaults == %{
             "encounter_mode" => "live_only",
             "reveal_name" => "encounter",
             "daily_cap" => 5,
             "cooldown_seconds" => 90,
             "limits" => %{"daily_cap_max" => 8}
           }

    updated =
      authed_conn(ctx.user)
      |> patch("/api/v1/hero/social-settings", %{
        "hero_id" => ctx.other.id,
        "encounter_mode" => "async",
        "reveal_name" => "guild",
        "daily_cap" => 7
      })
      |> json_response(200)

    assert updated["encounter_mode"] == "async"
    assert updated["reveal_name"] == "guild"
    assert updated["daily_cap"] == 7
    assert Repo.get_by!(TesIdle.Schemas.HeroSocialSetting, hero_id: ctx.hero.id)
    refute Repo.get_by(TesIdle.Schemas.HeroSocialSetting, hero_id: ctx.other.id)
  end

  test "settings validate enums and configured daily cap", ctx do
    Repo.insert!(
      %GameConfig{
        key: "hero_social",
        value: Jason.encode!(%{"max_daily_cap" => 4}),
        description: "test"
      },
      on_conflict: {:replace, [:value, :description]},
      conflict_target: :key
    )

    body =
      authed_conn(ctx.user)
      |> patch("/api/v1/hero/social-settings", %{
        "encounter_mode" => "always",
        "reveal_name" => "friends",
        "daily_cap" => 5
      })
      |> json_response(422)

    assert body["errors"]["encounter_mode"]
    assert body["errors"]["reveal_name"]
    assert body["errors"]["daily_cap"]
  end

  test "block and unblock always use authenticated hero as blocker", ctx do
    blocked =
      authed_conn(ctx.user)
      |> put("/api/v1/hero/blocks/#{ctx.other.id}", %{"blocker_id" => ctx.foreign.id})
      |> json_response(200)

    assert blocked == %{"blocked" => true, "hero_id" => ctx.other.id}
    assert Repo.get_by(HeroBlock, blocker_id: ctx.hero.id, blocked_id: ctx.other.id)
    refute Repo.get_by(HeroBlock, blocker_id: ctx.foreign.id, blocked_id: ctx.other.id)

    assert authed_conn(ctx.user)
           |> put("/api/v1/hero/blocks/#{ctx.hero.id}", %{})
           |> json_response(422)

    assert %{"blocked" => false} =
             authed_conn(ctx.user)
             |> delete("/api/v1/hero/blocks/#{ctx.other.id}")
             |> json_response(200)

    refute Repo.get_by(HeroBlock, blocker_id: ctx.hero.id, blocked_id: ctx.other.id)
  end

  defp identity(label, suffix, location_id) do
    user =
      Repo.insert!(%User{
        username: "social_#{label}_#{suffix}",
        email: "social_#{label}_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Hero #{label} #{suffix}",
        race: "Nord",
        hero_class: "Warrior",
        level: 1,
        location_id: location_id,
        brain_hash: "x",
        personality: %{},
        skills: %{},
        state_data: "{}"
      })

    {user, hero}
  end

  defp encounter(first, second, location, key) do
    {low, high} = ordered(first, second)

    Repo.insert!(%HeroEncounter{
      hero_low_id: low.id,
      hero_high_id: high.id,
      round: System.unique_integer([:positive]),
      location_id: location.id,
      kind: "meeting",
      status: "resolved",
      shared_payload: %{"server_secret" => true},
      idempotency_key: key <> ":" <> Integer.to_string(System.unique_integer([:positive]))
    })
  end

  defp ordered(first, second) do
    if first.id < second.id, do: {first, second}, else: {second, first}
  end

  defp authed_conn(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end
end
