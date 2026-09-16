defmodule TesIdleWeb.Controllers.AdminNarrativeBatchTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Game.Narrative.BatchImporter
  alias TesIdle.Repo
  alias TesIdle.Schemas.{NarrativeTemplate, User}
  import Ecto.Query

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    admin =
      Repo.insert!(%User{
        username: "batch_admin_#{suffix}",
        email: "batch_admin_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: true
      })

    plain =
      Repo.insert!(%User{
        username: "batch_plain_#{suffix}",
        email: "batch_plain_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    %{admin: admin, plain: plain, suffix: suffix}
  end

  defp conn_for(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  test "validate accepts a bare top-level template array" do
    payload = [
      %{
        "template_type" => "mining",
        "text_template" => "{hero_name} нашёл {ore_name}."
      }
    ]

    result = BatchImporter.validate(payload)
    assert result.valid
    assert result.activation_policy == "pending"
  end

  test "validate produces safe normalized preview including mining and encounters", %{admin: admin} do
    conn =
      post(conn_for(admin), "/api/v1/admin/narrative-batches/validate", %{
        "templates" => [
          %{
            "template_type" => "mining",
            "text_template" => "{hero_name} нашёл {ore_name}.",
            "source" => "community",
            "variables" => ["hero_name", "ore_name"]
          },
          %{
            "template_type" => "hero_encounter_initiator",
            "text_template" => "{hero_name} встретил {other_hero_name} в {location_name}.",
            "source" => "system"
          }
        ]
      })

    body = json_response(conn, 200)
    assert body["valid"]
    assert Enum.all?(body["rows"], & &1["valid"])
    assert hd(body["rows"])["preview"] == "Хальвар нашёл железная жила."
    assert hd(body["rows"])["normalized"]["is_active"] == false
  end

  test "validate rejects unknown unsafe and missing declared variables", %{admin: admin} do
    conn =
      post(conn_for(admin), "/api/v1/admin/narrative-batches/validate", %{
        "templates" => [
          %{
            "template_type" => "explore",
            "text_template" => "{hero_name} {__struct__}",
            "variables" => ["hero_name"]
          }
        ]
      })

    row = json_response(conn, 200)["rows"] |> hd()
    refute row["valid"]
    assert Enum.any?(row["errors"], &String.contains?(&1, "Unknown or unrenderable"))
    assert "variables must exactly match placeholders" in row["errors"]
  end

  test "validate rejects duplicates and active_system for non-system sources", %{admin: admin} do
    payload = %{
      "activation_policy" => "active_system",
      "templates" => [
        %{
          "template_type" => "explore",
          "text_template" => "Один и тот же текст",
          "source" => "community"
        },
        %{
          "template_type" => "explore",
          "text_template" => "Один и тот же текст",
          "source" => "system"
        }
      ]
    }

    rows =
      post(conn_for(admin), "/api/v1/admin/narrative-batches/validate", payload)
      |> json_response(200)
      |> Map.fetch!("rows")

    assert Enum.all?(rows, &(not &1["valid"]))

    assert Enum.all?(rows, fn row ->
             "Duplicate template_type + text_template in batch" in row["errors"]
           end)

    assert "active_system requires source=system" in hd(rows)["errors"]
  end

  test "rejects same-type narratives with a highly similar long opening" do
    opening =
      "На рассвете {hero_name} медленно шёл по мокрой тропе к старому мосту, слушал ветер в соснах и считал следы у обочины"

    rows = [
      %{"template_type" => "explore", "text_template" => opening <> ", пока не заметил волчий след."},
      %{"template_type" => "explore", "text_template" => String.upcase(opening) <> ", пока не заметил лисий след!"}
    ]

    result = BatchImporter.validate(rows)

    refute result.valid

    assert Enum.all?(result.rows, fn row ->
             "Near-duplicate opening sentence in batch" in row.errors
           end)
  end

  test "bare top-level array near-duplicate rejection is type-scoped" do
    opening =
      "На рассвете {hero_name} медленно шёл по мокрой тропе к старому мосту, слушал ветер в соснах и считал следы у обочины"

    result =
      BatchImporter.validate([
        %{"template_type" => "explore", "text_template" => opening <> ", пока не заметил волчий след."},
        %{"template_type" => "rest", "text_template" => opening <> ", пока не заметил лисий след."}
      ])

    assert result.valid
  end

  test "pending cleanup requires an explicit scope", %{admin: admin} do
    conn = post(conn_for(admin), "/api/v1/admin/narrative-templates/delete-pending", %{})
    assert json_response(conn, 400)["detail"] =~ "Уточните"
  end

  test "pending cleanup deletes only inactive templates in the explicit scope", %{admin: admin, suffix: suffix} do
    pending = "Cleanup pending #{suffix}"
    active = "Cleanup active #{suffix}"

    Repo.insert!(%NarrativeTemplate{template_type: "rest", text_template: pending, source: "community", is_active: false})
    Repo.insert!(%NarrativeTemplate{template_type: "rest", text_template: active, source: "community", is_active: true})

    body =
      conn_for(admin)
      |> post("/api/v1/admin/narrative-templates/delete-pending", %{"template_type" => "rest"})
      |> json_response(200)

    assert body["deleted"] >= 1
    refute Repo.exists?(from t in NarrativeTemplate, where: t.text_template == ^pending)
    assert Repo.exists?(from t in NarrativeTemplate, where: t.text_template == ^active)
  end

  test "pending import creates inactive templates atomically", %{admin: admin, suffix: suffix} do
    text = "Пакет #{suffix}: {hero_name} отдыхает."

    conn =
      post(conn_for(admin), "/api/v1/admin/narrative-batches/import", %{
        "templates" => [
          %{"template_type" => "rest", "text_template" => text, "source" => "community"}
        ]
      })

    assert json_response(conn, 201)["imported"] == 1

    template =
      Repo.one!(
        from t in NarrativeTemplate, where: t.template_type == "rest" and t.text_template == ^text
      )

    assert template.source == "community"
    refute template.is_active
  end

  test "active system import is admin-only and creates active system template", %{
    admin: admin,
    plain: plain,
    suffix: suffix
  } do
    text = "Системный #{suffix}: {hero_name} отдыхает."

    payload = %{
      "activation_policy" => "active_system",
      "templates" => [%{"template_type" => "rest", "text_template" => text, "source" => "system"}]
    }

    assert post(conn_for(plain), "/api/v1/admin/narrative-batches/import", payload).status == 403

    assert json_response(
             post(conn_for(admin), "/api/v1/admin/narrative-batches/import", payload),
             201
           )["imported"] == 1

    assert Repo.one!(from(t in NarrativeTemplate, where: t.text_template == ^text)).is_active
  end
end
