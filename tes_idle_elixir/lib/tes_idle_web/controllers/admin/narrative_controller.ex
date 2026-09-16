defmodule TesIdleWeb.Admin.NarrativeController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate
  alias TesIdle.Game.Narrative.Analytics
  import Ecto.Query

  # A-2: нарративная аналитика из journal_entries + narrative_templates.
  def usage(conn, params) do
    days = days_param(params)

    json(conn, %{
      totals: Analytics.totals(days),
      type_usage: Analytics.type_usage(days),
      daily_volume: Analytics.daily_volume(min(days, 14)),
      unused_template_types: Analytics.unused_template_types(days),
      factory_targets: Analytics.factory_targets(days)
    })
  end

  defp days_param(%{"days" => d}) when is_binary(d) do
    case Integer.parse(d) do
      {n, ""} when n in 1..365 -> n
      _ -> 30
    end
  end

  defp days_param(_), do: 30

  def index(conn, params) do
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "50") |> String.to_integer() |> min(200)
    template_type = Map.get(params, "template_type")
    source = Map.get(params, "source")
    is_active = Map.get(params, "is_active")
    q = blank_to_nil(Map.get(params, "q"))

    query = from t in NarrativeTemplate

    query = if template_type, do: from(t in query, where: t.template_type == ^template_type), else: query
    query = if source, do: from(t in query, where: t.source == ^source), else: query
    query = if is_active do
      active = is_active == "true"
      from(t in query, where: t.is_active == ^active)
    else
      query
    end
    query = if q, do: from(t in query, where: ilike(t.text_template, ^"%#{escape_like(q)}%")), else: query

    total = Repo.one(from t in query, select: count(t.id))
    offset = (page - 1) * per_page

    templates = query
    |> order_by([t], desc: t.created_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()

    json(conn, %{
      templates: Enum.map(templates, fn t ->
        %{id: t.id, template_type: t.template_type, text_template: t.text_template,
          source: t.source, is_active: t.is_active, mood_min: t.mood_min, mood_max: t.mood_max,
          created_at: t.created_at}
      end),
      total: total, page: page, per_page: per_page,
    })
  end

  def stats(conn, _params) do
    types =
      Repo.all(
        from t in NarrativeTemplate,
          group_by: t.template_type,
          order_by: [asc: count(t.id)],
          select: %{
            template_type: t.template_type,
            total: count(t.id),
            active: count(fragment("CASE WHEN ? THEN 1 END", t.is_active))
          }
      )

    sources =
      Repo.all(
        from t in NarrativeTemplate,
          group_by: t.source,
          order_by: [desc: count(t.id)],
          select: %{source: t.source, count: count(t.id)}
      )

    json(conn, %{
      types: types,
      sources: sources,
      total: Enum.reduce(types, 0, &(&1.total + &2)),
      active: Enum.reduce(types, 0, &(&1.active + &2)),
    })
  end

  def bulk(conn, %{"ids" => ids, "action" => action}) when is_list(ids) do
    cond do
      ids == [] ->
        conn |> put_status(:bad_request) |> json(%{detail: "ids must not be empty"})
      action == "activate" ->
        {n, _} = Repo.update_all(from(t in NarrativeTemplate, where: t.id in ^ids), set: [is_active: true])
        json(conn, %{updated: n})
      action == "deactivate" ->
        {n, _} = Repo.update_all(from(t in NarrativeTemplate, where: t.id in ^ids), set: [is_active: false])
        json(conn, %{updated: n})
      action == "delete" ->
        {n, _} = Repo.delete_all(from(t in NarrativeTemplate, where: t.id in ^ids))
        json(conn, %{deleted: n})
      true ->
        conn |> put_status(:bad_request) |> json(%{detail: "Unknown action"})
    end
  end

  def bulk(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{detail: "ids (list) and action are required"})
  end

  # Explicitly destructive moderation cleanup. The optional type/source scope
  # mirrors the visible filter; absent filters require `all=true`.
  def delete_pending(conn, params) do
    template_type = blank_to_nil(params["template_type"])
    source = blank_to_nil(params["source"])
    all = truthy(params["all"])

    if not all and is_nil(template_type) and is_nil(source) do
      conn
      |> put_status(:bad_request)
      |> json(%{detail: "Уточните template_type, source или передайте all=true"})
    else
      query = from t in NarrativeTemplate, where: t.is_active == false
      query = if template_type, do: from(t in query, where: t.template_type == ^template_type), else: query
      query = if source, do: from(t in query, where: t.source == ^source), else: query
      {deleted, _} = Repo.delete_all(query)
      json(conn, %{deleted: deleted})
    end
  end

  def create(conn, params) do
    template = Repo.insert!(%NarrativeTemplate{
      template_type: params["template_type"],
      text_template: params["text_template"],
      source: Map.get(params, "source", "manual"),
      is_active: truthy(Map.get(params, "is_active", "true")),
      mood_min: parse_mood(params["mood_min"]),
      mood_max: parse_mood(params["mood_max"]),
    })

    json(conn, %{message: "Template created", id: template.id})
  end

  def update(conn, %{"id" => id} = params) do
    template = Repo.get(NarrativeTemplate, id)
    if !template, do: conn |> put_status(:not_found) |> json(%{detail: "Template not found"}) |> halt()

    updates = %{}
    updates = if params["text_template"], do: Map.put(updates, :text_template, params["text_template"]), else: updates
    updates = if params["template_type"], do: Map.put(updates, :template_type, params["template_type"]), else: updates
    updates = if Map.has_key?(params, "is_active"), do: Map.put(updates, :is_active, truthy(params["is_active"])), else: updates

    # Ключи mood_* есть → устанавливаем ("" / nil = очистить)
    updates = if Map.has_key?(params, "mood_min"), do: Map.put(updates, :mood_min, parse_mood(params["mood_min"])), else: updates
    updates = if Map.has_key?(params, "mood_max"), do: Map.put(updates, :mood_max, parse_mood(params["mood_max"])), else: updates

    if map_size(updates) > 0 do
      Repo.update!(NarrativeTemplate.changeset(template, updates))
    end

    json(conn, %{message: "Template updated"})
  end

  def approve(conn, %{"id" => id}) do
    template = Repo.get(NarrativeTemplate, id)
    if !template, do: conn |> put_status(:not_found) |> json(%{detail: "Template not found"}) |> halt()

    Repo.update!(NarrativeTemplate.changeset(template, %{is_active: true}))
    json(conn, %{message: "Template approved"})
  end

  # A-1b: массовое одобрение pending-шаблонов. Фильтры template_type/source;
  # без фильтров — только с явным all=true (осознанное «одобрить всё»).
  def approve_batch(conn, params) do
    template_type = blank_to_nil(params["template_type"])
    source = blank_to_nil(params["source"])
    all = truthy(params["all"])

    if not all and !template_type and !source do
      conn |> put_status(:bad_request)
      |> json(%{detail: "Уточните template_type, source или передайте all=true"})
    else
      max =
        case parse_int(Map.get(params, "max", "200")) do
          n when is_integer(n) and n in 1..200 -> n
          _ -> 200
        end

      base =
        from(t in NarrativeTemplate,
          where: t.is_active == false,
          order_by: [asc: t.created_at],
          select: t.id
        )
      base = if template_type, do: from(t in base, where: t.template_type == ^template_type), else: base
      base = if source, do: from(t in base, where: t.source == ^source), else: base

      ids = base |> limit(^max) |> Repo.all()

      {approved, _} =
        Repo.update_all(
          from(t in NarrativeTemplate, where: t.id in ^ids),
          set: [is_active: true]
        )

      remaining =
        Repo.one(
          from t in NarrativeTemplate,
            where: t.is_active == false,
            select: count(t.id)
        )

      json(conn, %{approved: approved, remaining: remaining})
    end
  end

  def reject(conn, %{"id" => id}) do
    template = Repo.get(NarrativeTemplate, id)
    if !template, do: conn |> put_status(:not_found) |> json(%{detail: "Template not found"}) |> halt()

    Repo.update!(NarrativeTemplate.changeset(template, %{is_active: false}))
    json(conn, %{message: "Template rejected"})
  end

  def delete(conn, %{"id" => id}) do
    template = Repo.get(NarrativeTemplate, id)
    if !template, do: conn |> put_status(:not_found) |> json(%{detail: "Template not found"}) |> halt()

    Repo.delete!(template)
    json(conn, %{message: "Template deleted"})
  end

  # --- Private helpers ---

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  # N-5: max может прийти числом из JSON-боди — Integer.parse/1 принимает только
  # строки, поэтому коэрсим типы явно (иначе FunctionClauseError на 500).
  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> :error
    end
  end
  defp parse_int(_), do: :error

  # Экранируем LIKE-спецсимволы в пользовательском поиске
  defp escape_like(s) do
    s |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
  end

  defp parse_mood(nil), do: nil
  defp parse_mood(""), do: nil
  defp parse_mood(v) when is_number(v), do: v * 1.0
  defp parse_mood(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end
  defp parse_mood(_), do: nil

  # JSON-тело присылает true/false, query-string — "true"/"false"
  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false
end
