defmodule TesIdle.Game.Brain.AuditReportFile do
  @moduledoc """
  S-6: рендер файла аналитики решений ИИ.

  Чистый модуль (никаких Repo) — принимает то, что вернул `AuditStats.analysis/1`,
  и выдаёт текст в одном из форматов: `markdown` (для чтения человеком),
  `json` (машинная обработка), `csv` (таблицы аномалий и исходов действий).
  """

  @doc "Возвращает {content, filename, content_type}."
  def render(analysis, format \\ "markdown")

  def render(analysis, "json") do
    # Те же атомы severity, что роняют json/2 в контроллере: файл должен
    # кодироваться, даже когда в сводке есть аномалии.
    payload = Map.update(analysis, :anomalies, [], fn list ->
      Enum.map(list, &Map.update!(&1, :severity, fn s -> to_string(s) end))
    end)

    {Jason.encode!(payload, pretty: true), filename("json"), "application/json"}
  end

  def render(analysis, "csv") do
    {csv(analysis), filename("csv"), "text/csv"}
  end

  def render(analysis, _markdown) do
    {markdown(analysis), filename("md"), "text/markdown"}
  end

  defp filename(ext) do
    stamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:.]/, "-")
    "brain-audit-#{stamp}.#{ext}"
  end

  # ─── Markdown ────────────────────────────────────────

  defp markdown(analysis) do
    totals = analysis.totals || %{}
    summary = analysis.anomaly_summary || %{critical: 0, warning: 0, info: 0, total: 0}
    filters = analysis.filters || %{}

    [
      "# Аналитика решений ИИ — TES Idle",
      "",
      "**Сформировано:** #{DateTime.utc_now() |> DateTime.to_iso8601()}",
      "**Период:** #{analysis.range.days} дн. (с #{analysis.range.from})",
      "**Фильтры:** #{filter_line(filters)}",
      "",
      "## Сводка",
      "",
      "| Показатель | Значение |",
      "| --- | --- |",
      "| Событий аудита | #{totals[:events] || 0} |",
      "| Решений (намерений) | #{totals[:intents] || 0} |",
      "| Действий | #{totals[:actions] || 0} |",
      "| Сбоев действий | #{totals[:failed_actions] || 0} (#{pct(totals[:failure_rate])}) |",
      "| Доля смен намерения | #{pct(totals[:switch_rate])} |",
      "| Доля удержаний | #{pct(totals[:hold_rate])} |",
      "| Целей задействовано | #{totals[:distinct_goals] || 0} |",
      "| Героев в аудите | #{totals[:heroes] || 0} |",
      "",
      "## Аномалии (#{summary.total || 0})",
      "",
      "Критичных: **#{summary.critical || 0}**, предупреждений: **#{summary.warning || 0}**, наблюдений: **#{summary.info || 0}**.",
      "",
      anomaly_section(analysis.anomalies || []),
      "",
      "## Распределение целей",
      "",
      "| Цель | Выбрано | Удержано | Сменено | Всего | Ср. utility |",
      "| --- | --- | --- | --- | --- | --- |",
      goal_rows(analysis.intent_by_goal || []),
      "",
      "## Исходы действий",
      "",
      "| Цель | Действие | Завершено | Сбоев | Доля сбоев |",
      "| --- | --- | --- | --- | --- |",
      action_rows(analysis.action_outcomes || []),
      "",
      "## Профиль героев",
      "",
      "| Герой | Ур. | События | Выбрано | Удержано | Сменено | Завершено | Сбоев |",
      "| --- | --- | --- | --- | --- | --- | --- | --- |",
      hero_rows(analysis.heroes || []),
      "",
      "## Объём по дням",
      "",
      "| День | Намерения | Завершено | Сбоев |",
      "| --- | --- | --- | --- |",
      timeline_rows(analysis.timeline || []),
      "",
      "---",
      "",
      "_Файл собран админ-панелью TES Idle (Brain audit telemetry). Данные append-only;_",
      "_аномалии рассчитаны пороговыми правилами `TesIdle.Game.Brain.Anomalies`._",
      ""
    ]
    |> Enum.join("\n")
  end

  defp filter_line(filters) do
    parts =
      [
        filters[:event_type] && "событие: #{filters[:event_type]}",
        filters[:goal] && "цель: #{filters[:goal]}",
        filters[:hero_id] && "герой: #{filters[:hero_id]}",
        filters[:q] && "поиск: #{filters[:q]}"
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: "без фильтров", else: Enum.join(parts, ", ")
  end

  defp anomaly_section([]), do: "_Аномалий не обнаружено — решения выглядят сбалансированными._"

  defp anomaly_section(anomalies) do
    anomalies
    |> Enum.map(fn a ->
      [
        "### #{severity_mark(a.severity)} #{a.title}",
        "",
        "- **Тип:** `#{a.kind}`",
        "- **Значение:** #{Float.round(a.value * 100, 1)}% (порог #{Float.round(a.threshold * 100, 1)}%)",
        a.goal && "- **Цель:** `#{a.goal}`",
        a.action && "- **Действие:** `#{a.action}`",
        a.hero && "- **Герой:** #{a.hero}",
        "",
        a.detail,
        "",
        "**Что делать:** #{a.hint}",
        ""
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end)
    |> Enum.join("\n")
  end

  defp severity_mark(:critical), do: "[КРИТИЧНО]"
  defp severity_mark(:warning), do: "[ВНИМАНИЕ]"
  defp severity_mark(_), do: "[ИНФО]"

  defp goal_rows([]), do: "| — | — | — | — | — | — |"

  defp goal_rows(rows) do
    rows
    |> Enum.map(fn r ->
      total = r.selected + r.held + r.switched
      "| #{r.goal || "—"} | #{r.selected} | #{r.held} | #{r.switched} | #{total} | #{r.avg_utility} |"
    end)
    |> Enum.join("\n")
  end

  defp action_rows([]), do: "| — | — | — | — | — |"

  defp action_rows(rows) do
    rows
    |> Enum.map(fn r ->
      total = r.completed + r.failed
      rate = if total > 0, do: Float.round(r.failed / total * 100, 1), else: 0.0
      "| #{r.goal || "—"} | #{r.action || "—"} | #{r.completed} | #{r.failed} | #{rate}% |"
    end)
    |> Enum.join("\n")
  end

  defp hero_rows([]), do: "| — | — | — | — | — | — | — | — |"

  defp hero_rows(rows) do
    rows
    |> Enum.map(fn r ->
      "| #{r.hero} | #{r.level} | #{r.events} | #{r.selected} | #{r.held} | #{r.switched} | #{r.completed} | #{r.failed} |"
    end)
    |> Enum.join("\n")
  end

  defp timeline_rows([]), do: "| — | — | — | — |"

  defp timeline_rows(rows) do
    rows
    |> Enum.map(fn r -> "| #{day(r.bucket)} | #{r.intent} | #{r.action} | #{r.failed} |" end)
    |> Enum.join("\n")
  end

  defp day(%NaiveDateTime{} = value), do: NaiveDateTime.to_date(value) |> Date.to_iso8601()
  defp day(%DateTime{} = value), do: DateTime.to_date(value) |> Date.to_iso8601()
  defp day(value), do: to_string(value)

  defp pct(nil), do: "0.0%"
  defp pct(value), do: "#{Float.round(value * 100, 1)}%"

  # ─── CSV ─────────────────────────────────────────────

  @csv_headers ~w(section kind severity goal action hero value threshold title detail hint)

  defp csv(analysis) do
    anomaly_lines =
      (analysis.anomalies || [])
      |> Enum.map(fn a ->
        [
          "anomaly",
          a.kind,
          to_string(a.severity),
          a.goal || "",
          a.action || "",
          a.hero || "",
          to_string(a.value),
          to_string(a.threshold),
          a.title,
          a.detail,
          a.hint
        ]
      end)

    action_lines =
      (analysis.action_outcomes || [])
      |> Enum.map(fn r ->
        total = r.completed + r.failed
        rate = if total > 0, do: Float.round(r.failed / total, 4), else: 0.0

        [
          "action_outcome",
          "",
          "",
          r.goal || "",
          r.action || "",
          "",
          to_string(rate),
          "",
          "#{r.completed} завершено, #{r.failed} сбоев",
          "",
          ""
        ]
      end)

    goal_lines =
      (analysis.intent_by_goal || [])
      |> Enum.map(fn r ->
        [
          "goal_share",
          "",
          "",
          r.goal || "",
          "",
          "",
          to_string(r.avg_utility),
          "",
          "выбрано #{r.selected}, удержано #{r.held}, сменено #{r.switched}",
          "",
          ""
        ]
      end)

    ([@csv_headers] ++ anomaly_lines ++ goal_lines ++ action_lines)
    |> Enum.map(&csv_row/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp csv_row(fields), do: fields |> Enum.map(&csv_escape/1) |> Enum.join(",")

  # Экранирование по RFC 4180: кавычки удваиваются, поле оборачивается при спецсимволах.
  defp csv_escape(value) do
    text = to_string(value)

    if String.contains?(text, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(text, "\"", "\"\"") <> "\""
    else
      text
    end
  end
end
