defmodule TesIdleWeb.Admin.LlmController do
  use TesIdleWeb, :controller

  alias TesIdle.Game.Narrative.LlmFactory

  def status(conn, _params) do
    json(conn, %{
      auto_generate: false,
      tone: "standard",
      sentences: 2,
      backend: "scene_grammar",
      fragments_available: LlmFactory.fragments_available?(),
      pending_count: LlmFactory.pending_count()
    })
  end

  def toggle(conn, %{"enabled" => enabled}) do
    json(conn, %{auto_generate: enabled == "true"})
  end

  # N-4: оффлайн-фабрика кандидатов шаблонов (source="llm", is_active=false).
  def generate(conn, params) do
    template_type = params["template_type"]

    cond do
      not is_binary(template_type) or template_type == "" ->
        conn |> put_status(:bad_request) |> json(%{detail: "template_type required"})

      not LlmFactory.fragments_available?() ->
        conn |> put_status(:conflict) |> json(%{detail: "Фрагменты пулов пусты — seed_fragments не запущен"})

      true ->
        count = count_param(params)
        {:ok, candidates} = LlmFactory.generate(template_type, count)

        json(conn, %{
          message: "Сгенерировано #{length(candidates)} кандидатов для «#{template_type}» (модерация)",
          inserted: length(candidates),
          pending_count: LlmFactory.pending_count(),
          candidates:
            Enum.map(candidates, fn c ->
              %{id: c.id, template_type: c.template_type, text_template: c.text_template,
                source: c.source, is_active: c.is_active}
            end)
        })
    end
  end

  # A-2b: batch-генерация по целям аналитики (тонкие типы + мёртвые шаблоны).
  def generate_batch(conn, params) do
    unless LlmFactory.fragments_available?() do
      conn |> put_status(:conflict) |> json(%{detail: "Фрагменты пулов пусты — seed_fragments не запущен"})
    else
      count_per_type = count_param(params, "count_per_type", 5)
      {:ok, results, total} = LlmFactory.generate_batch(count_per_type)

      json(conn, %{
        message: "Сгенерировано #{total} кандидатов по #{map_size(results)} целям (модерация)",
        inserted: total,
        per_type: results,
        pending_count: LlmFactory.pending_count()
      })
    end
  end

  defp count_param(params, key, default) do
    case params[key] do
      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} when n in 1..20 -> n
          _ -> default
        end

      _ ->
        default
    end
  end

  defp count_param(%{"count" => c}) when is_binary(c) do
    case Integer.parse(c) do
      {n, ""} when n in 1..20 -> n
      _ -> 6
    end
  end

  defp count_param(_), do: 6
end
