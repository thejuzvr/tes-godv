defmodule TesIdleWeb.Admin.SuggestionController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{NarrativeTemplate, Suggestion}
  import Ecto.Query

  def index(conn, params) do
    status = Map.get(params, "status")
    page = params |> Map.get("page", "1") |> String.to_integer()
    per_page = params |> Map.get("per_page", "20") |> String.to_integer() |> min(100)
    offset = (page - 1) * per_page

    base_query = from(s in Suggestion)
    base_query = if status, do: from(s in base_query, where: s.status == ^status), else: base_query

    total = Repo.one(from(s in base_query, select: count(s.id)))
    suggestions = Repo.all(from(s in base_query, order_by: [desc: s.created_at], limit: ^per_page, offset: ^offset))

    json(conn, %{
      total: total,
      page: page,
      per_page: per_page,
      suggestions: Enum.map(suggestions, fn s ->
        %{id: s.id, user_id: s.user_id, suggestion_type: s.suggestion_type,
          title: s.title, content: s.content, status: s.status,
          admin_comment: s.admin_comment, created_at: s.created_at, reviewed_at: s.reviewed_at}
      end),
    })
  end

  @doc """
  Одобрить предложение. Для narrative с переданным template_type (валидным: 2..40 символов)
  текст предложения сразу становится активным шаблоном (source="community") —
  попадает в ротацию. Без template_type — только статус (поведение по умолчанию).
  """
  def approve(conn, %{"id" => id} = params) do
    suggestion = Repo.get(Suggestion, id)
    if !suggestion, do: conn |> put_status(:not_found) |> json(%{detail: "Not found"}) |> halt()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    suggestion
    |> Ecto.Changeset.change(%{status: "approved", reviewed_at: now})
    |> Repo.update!()

    {template_id, template_type} = maybe_create_template(suggestion, params)

    json(conn, %{message: "Suggestion approved", template_id: template_id, template_type: template_type})
  end

  def reject(conn, %{"id" => id} = params) do
    suggestion = Repo.get(Suggestion, id)
    if !suggestion, do: conn |> put_status(:not_found) |> json(%{detail: "Not found"}) |> halt()

    comment = Map.get(params, "admin_comment", "")
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    suggestion
    |> Ecto.Changeset.change(%{status: "rejected", admin_comment: comment, reviewed_at: now})
    |> Repo.update!()

    json(conn, %{message: "Suggestion rejected"})
  end

  # P-0: narrative-предложение + template_type → текст становится community-шаблоном
  defp maybe_create_template(suggestion, params) do
    tt_raw = Map.get(params, "template_type")

    with "narrative" <- suggestion.suggestion_type,
         tt when is_binary(tt) <- tt_raw,
         trimmed = String.trim(tt),
         true <- byte_size(trimmed) >= 2 and byte_size(trimmed) <= 40,
         false <- template_exists?(trimmed, suggestion.content) do
      template =
        Repo.insert!(%NarrativeTemplate{
          template_type: trimmed,
          text_template: suggestion.content,
          source: "community",
          is_active: true
        })

      {template.id, template.template_type}
    else
      _ -> {nil, nil}
    end
  end

  defp template_exists?(type, text) do
    Repo.exists?(
      from t in NarrativeTemplate,
        where: t.template_type == ^type and t.text_template == ^text
    )
  end
end
