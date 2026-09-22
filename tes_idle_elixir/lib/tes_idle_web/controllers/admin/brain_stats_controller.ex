defmodule TesIdleWeb.Admin.BrainStatsController do
  @moduledoc """
  Long-lived, paginated Brain decision telemetry for administrators.

  S-6: `/brain/stats` отдаёт расширенную аналитику (объёмы, таймлайн, аномалии),
  `/brain/export` — файл с анализом в markdown/json/csv.
  """

  use TesIdleWeb, :controller

  alias TesIdle.Game.Brain.{AuditReportFile, AuditStats}

  def show(conn, params) do
    report = AuditStats.analysis(params)

    json(conn, %{
      range: report.range,
      limit: report.limit,
      offset: report.offset,
      filters: report.filters,
      goals: report.goals,
      event_types: report.event_types,
      # Intent telemetry diagnoses concentration (not state_data's capped decision_log).
      intent_by_goal: report.intent_by_goal,
      action_outcomes: report.action_outcomes,
      heroes: report.heroes,
      recent_events: report.recent_events,
      event_counts: report.event_counts,
      totals: report.totals,
      timeline: Enum.map(report.timeline, &json_timeline/1),
      anomalies: Enum.map(report.anomalies, &json_anomaly/1),
      anomaly_summary: report.anomaly_summary,
      total_decisions: report.total_decisions,
      # Compatibility aliases for consumers of the original admin shape.
      by_goal: report.intent_by_goal,
      by_hero: report.heroes
    })
  end

  # severity — атом (:critical/:warning/:info). Jason не кодирует атомы,
  # поэтому json/2 падал 500 на каждом открытии аудита, как только детектор
  # находил хотя бы одну аномалию. Внутри модуля атом остаётся: тесты и
  # markdown-отчёт сравнивают его напрямую.
  defp json_anomaly(anomaly) do
    Map.update!(anomaly, :severity, &to_string/1)
  end

  # date_trunc возвращает NaiveDateTime. Фронт режет bucket как дату "YYYY-MM-DD".
  defp json_timeline(%{bucket: %NaiveDateTime{} = bucket} = row) do
    %{row | bucket: bucket |> NaiveDateTime.to_date() |> Date.to_iso8601()}
  end

  defp json_timeline(row), do: row

  @doc "Выгрузка файла аналитики: format=markdown|json|csv (по умолчанию markdown)."
  def export(conn, params) do
    analysis = AuditStats.analysis(Map.put(params, "limit", params["limit"] || "200"))
    {content, filename, content_type} = AuditReportFile.render(analysis, params["format"] || "markdown")

    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, content)
  end
end
