defmodule TesIdleWeb.Admin.JournalRetentionController do
  @moduledoc """
  Админ-управление политикой хроники (docs/JOURNAL_RETENTION_ARCHITECTURE.md).

  Этап C требует, чтобы администратор **видел**, что будет удалено, до
  включения очистки. Поэтому здесь есть `preview` (dry-run отчёт) и `run`
  (фактический прогон), плюс снимок настроек и «разросшиеся герои».
  """

  use TesIdleWeb, :controller

  alias TesIdle.Game.ContextBuilder
  alias TesIdle.Game.Journal.{Aggregator, Retention, Throttle}

  @doc "Настройки + предпросмотр: что уйдёт при текущей политике."
  def show(conn, _params) do
    configs = ContextBuilder.load_configs()
    cfg = Retention.config(configs)

    json(conn, %{
      config: %{
        enabled: cfg.enabled,
        dry_run: cfg.dry_run,
        routine_days: cfg.routine_days,
        keep_last_routine: cfg.keep_last_routine,
        warning_rows_per_hero: cfg.warning_rows_per_hero,
        batch_size: cfg.batch_size
      },
      throttle: json_throttle(Throttle.config(configs)),
      preview: Retention.preview(configs),
      oversized_heroes: Retention.oversized_heroes(configs)
    })
  end

  @doc "Предпросмотр без изменений — безопасно вызывать всегда."
  def preview(conn, _params) do
    json(conn, Retention.preview(ContextBuilder.load_configs()))
  end

  @doc """
  Прогон очистки. Уважает `dry_run` из конфига: пока он включён,
  эндпоинт только считает кандидатов.
  """
  def run(conn, _params) do
    report = Retention.run(ContextBuilder.load_configs())
    json(conn, report)
  end

  @doc "Сводка агрегатов за период: то, что переживает очистку."
  def stats(conn, params) do
    days = parse_days(params["days"])
    to_day = Date.utc_today()
    from_day = Date.add(to_day, -(days - 1))

    json(conn, %{
      range: %{from: Date.to_iso8601(from_day), to: Date.to_iso8601(to_day), days: days},
      summary: Aggregator.summary(from_day, to_day),
      daily: Aggregator.daily(from_day, to_day)
    })
  end

  defp parse_days(nil), do: 30

  defp parse_days(value) do
    case Integer.parse(to_string(value)) do
      {n, _} when n in 1..365 -> n
      _ -> 30
    end
  end

  # mode — атом (:off/:shadow/:enforce). Jason не кодирует атомы, и вся
  # вкладка «Хроника» отвечала 500 ещё до отрисовки.
  defp json_throttle(cfg) do
    Map.update!(cfg, :mode, &to_string/1)
  end
end
