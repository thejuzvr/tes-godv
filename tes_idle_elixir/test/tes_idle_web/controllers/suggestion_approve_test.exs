defmodule TesIdleWeb.Controllers.SuggestionApproveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.{NarrativeTemplate, Suggestion, User}

  @endpoint TesIdleWeb.Endpoint

  # P-0: канал предложений — approve narrative-предложения с template_type
  # превращает текст в активный community-шаблон (в ротации TemplateEngine).

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_author_#{suffix}",
        email: "qa_author_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    admin =
      Repo.insert!(%User{username: "qa_admin_#{suffix}",
        email: "qa_admin_#{suffix}@test.gg", password_hash: "x", is_admin: true})

    suggestion =
      Repo.insert!(%Suggestion{
        user_id: user.id,
        suggestion_type: "narrative",
        title: "Шаблон: Проверка канала",
        content: "{hero_name} проверяет канал предложений — QA-текст #{suffix}.",
        status: "pending"
      })

    %{user: user, admin: admin, suggestion: suggestion}
  end

  defp admin_conn(%User{} = admin) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(admin)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  test "approve с template_type → community-шаблон активен", %{admin: admin, suggestion: s} do
    conn =
      admin_conn(admin)
      |> patch("/api/v1/admin/suggestions/#{s.id}/approve", %{"template_type" => "explore"})

    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["template_id"]
    assert body["template_type"] == "explore"

    template = Repo.get!(NarrativeTemplate, body["template_id"])
    assert template.source == "community"
    assert template.is_active == true
    assert template.text_template == s.content
    assert Repo.reload!(s).status == "approved"
  end

  test "approve без template_type — только статус, шаблона нет", %{admin: admin, suggestion: s} do
    conn = admin_conn(admin) |> patch("/api/v1/admin/suggestions/#{s.id}/approve", %{})

    assert conn.status == 200
    assert json_response(conn, 200)["template_id"] == nil
    assert Repo.reload!(s).status == "approved"
    assert Repo.one(from t in NarrativeTemplate, where: t.text_template == ^s.content) == nil
  end

  test "двойной approve того же текста не дублирует шаблон", %{admin: admin} do
    # предложение уже одобрено и шаблон создан — повторный approve другого предложения
    # с тем же текстом не должен создать второй шаблон
    s1 = Repo.insert!(%Suggestion{user_id: admin.id, suggestion_type: "narrative",
      title: "A", content: "Дубль-текст {hero_name}.", status: "pending"})
    s2 = Repo.insert!(%Suggestion{user_id: admin.id, suggestion_type: "narrative",
      title: "B", content: "Дубль-текст {hero_name}.", status: "pending"})

    admin_conn(admin) |> patch("/api/v1/admin/suggestions/#{s1.id}/approve", %{"template_type" => "socialize"})
    conn = admin_conn(admin) |> patch("/api/v1/admin/suggestions/#{s2.id}/approve", %{"template_type" => "socialize"})

    assert conn.status == 200
    assert json_response(conn, 200)["template_id"] == nil

    count =
      Repo.one(
        from t in NarrativeTemplate,
          where: t.text_template == "Дубль-текст {hero_name}.",
          select: count(t.id)
      )

    assert count == 1
  end

  test "reject — статус и комментарий, шаблона нет", %{admin: admin, suggestion: s} do
    conn =
      admin_conn(admin)
      |> patch("/api/v1/admin/suggestions/#{s.id}/reject", %{"admin_comment" => "не в тон"})

    assert conn.status == 200
    reloaded = Repo.reload!(s)
    assert reloaded.status == "rejected"
    assert reloaded.admin_comment == "не в тон"
    assert Repo.one(from t in NarrativeTemplate, where: t.text_template == ^s.content) == nil
  end
end
