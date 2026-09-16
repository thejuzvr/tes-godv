defmodule TesIdleWeb.SuggestionController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Suggestion}
  import Ecto.Query

  def create(conn, %{"suggestion_type" => type, "title" => title, "content" => content}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    suggestion = Repo.insert!(%Suggestion{
      user_id: user.id,
      suggestion_type: type,
      title: title,
      content: content,
    })

    json(conn, %{message: "Suggestion created", id: suggestion.id})
  end

  def index(conn, _params) do
    user = conn.assigns.current_user
    suggestions = Repo.all(
      from s in Suggestion,
        where: s.user_id == ^user.id,
        order_by: [desc: s.created_at]
    )

    json(conn, Enum.map(suggestions, fn s ->
      %{
        id: s.id, suggestion_type: s.suggestion_type,
        title: s.title, content: s.content, status: s.status,
        admin_comment: s.admin_comment, created_at: s.created_at,
      }
    end))
  end
end
