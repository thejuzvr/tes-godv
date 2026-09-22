alias TesIdle.Repo

{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Repo.start_link()

# Реальная интенсивность: записей на героя в день (по дням с 7 героями)
rate = """
SELECT
  date_trunc('day', created_at)::date AS day,
  count(*) AS entries,
  count(DISTINCT hero_id) AS heroes,
  round(count(*)::numeric / GREATEST(count(DISTINCT hero_id),1), 1) AS per_hero
FROM journal_entries
WHERE created_at >= now() - interval '7 days'
GROUP BY 1 ORDER BY 1 DESC
"""

Repo.query!(rate).rows
|> Enum.each(fn r -> IO.puts("RATE " <> Enum.join(Enum.map(r, &to_string/1), " | ")) end)

# Средний размер строки по типам — где именно вес
sizes = """
SELECT
  entry_type,
  count(*) AS n,
  round(avg(pg_column_size(t.*))) AS avg_bytes,
  round(avg(char_length(text))) AS avg_text
FROM journal_entries t
GROUP BY 1 ORDER BY 3 DESC NULLS LAST LIMIT 12
"""

Repo.query!(sizes).rows
|> Enum.each(fn r -> IO.puts("SIZE " <> Enum.join(Enum.map(r, &to_string/1), " | ")) end)

# Доля "шумных" механических типов против значимых
noise = """
SELECT
  CASE
    WHEN entry_type IN ('generic_action','fishing_wait','fishing_catch','smell_flowers',
                        'watch_sunset','hear_birds','hear_river','hear_wolves',
                        'collect_herbs','feel_confident','rest_by_fire','shelter_from_storm',
                        'notice_tracks','find_tracks','avoid_danger','find_loot')
      THEN 'routine'
    ELSE 'significant'
  END AS bucket,
  count(*) AS n,
  round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM journal_entries GROUP BY 1
"""

Repo.query!(noise).rows
|> Enum.each(fn r -> IO.puts("BUCKET " <> Enum.join(Enum.map(r, &to_string/1), " | ")) end)

# Аудит: вес на событие
audit = """
SELECT
  event_type,
  count(*) AS n,
  round(avg(pg_column_size(t.*))) AS avg_bytes
FROM decision_audit_events t
GROUP BY 1 ORDER BY 2 DESC
"""

Repo.query!(audit).rows
|> Enum.each(fn r -> IO.puts("AUDIT " <> Enum.join(Enum.map(r, &to_string/1), " | ")) end)

audit_avg = "SELECT count(*), round(avg(pg_column_size(t.*))) FROM decision_audit_events t"
Repo.query!(audit_avg).rows
|> Enum.each(fn r -> IO.puts("AUDITAVG " <> Enum.join(Enum.map(r, &to_string/1), " | ")) end)
