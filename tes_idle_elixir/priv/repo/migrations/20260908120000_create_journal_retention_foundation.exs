defmodule TesIdle.Repo.Migrations.CreateJournalRetentionFoundation do
  @moduledoc """
  Этап B из docs/JOURNAL_RETENTION_ARCHITECTURE.md.

  Три таблицы, которые позволяют сокращать хроники без потери смысла:

  - `hero_milestones` — памятные вехи с длительным хранением (снимок текста,
    а не ссылка на шаблон: шаблон могут изменить или удалить);
  - `hero_daily_stats` — идемпотентный суточный агрегат по герою, который
    переживает удаление текстов;
  - `journal_event_totals` — счётчики «создано/опубликовано/подавлено» по
    герою и типу, чтобы retention не обнулял сквозные показатели.

  Миграция идемпотентна: в тестовой БД живёт старый stub 20260716, поэтому
  всё создаётся через IF NOT EXISTS / ADD COLUMN IF NOT EXISTS.
  """

  use Ecto.Migration

  def up do
    # ─── Памятные вехи ───────────────────────────────────
    execute("""
    CREATE TABLE IF NOT EXISTS hero_milestones (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      kind VARCHAR(48) NOT NULL,
      source VARCHAR(24) NOT NULL DEFAULT 'auto',
      entry_type VARCHAR(64),
      title VARCHAR(160) NOT NULL,
      text TEXT NOT NULL DEFAULT '',
      game_day INTEGER,
      chapter INTEGER,
      payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS hero_milestones_hero_created_idx ON hero_milestones (hero_id, created_at DESC)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS hero_milestones_hero_kind_idx ON hero_milestones (hero_id, kind)"
    )

    # ─── Суточный агрегат ────────────────────────────────
    execute("""
    CREATE TABLE IF NOT EXISTS hero_daily_stats (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      day DATE NOT NULL,
      game_events INTEGER NOT NULL DEFAULT 0,
      published_entries INTEGER NOT NULL DEFAULT 0,
      suppressed_entries INTEGER NOT NULL DEFAULT 0,
      victories INTEGER NOT NULL DEFAULT 0,
      defeats INTEGER NOT NULL DEFAULT 0,
      quests_completed INTEGER NOT NULL DEFAULT 0,
      xp_gained BIGINT NOT NULL DEFAULT 0,
      gold_gained BIGINT NOT NULL DEFAULT 0,
      deaths INTEGER NOT NULL DEFAULT 0,
      level_ups INTEGER NOT NULL DEFAULT 0,
      schema_version INTEGER NOT NULL DEFAULT 1,
      coverage VARCHAR(24) NOT NULL DEFAULT 'live',
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    # Один агрегат на героя в сутки — идемпотентность на уровне БД,
    # а не на честном слове воркера.
    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS hero_daily_stats_hero_day_uidx ON hero_daily_stats (hero_id, day)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS hero_daily_stats_day_idx ON hero_daily_stats (day DESC)"
    )

    # ─── Сквозные счётчики по типу события ───────────────
    execute("""
    CREATE TABLE IF NOT EXISTS journal_event_totals (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      entry_type VARCHAR(64) NOT NULL,
      category VARCHAR(24) NOT NULL DEFAULT 'ambient',
      created_count BIGINT NOT NULL DEFAULT 0,
      published_count BIGINT NOT NULL DEFAULT 0,
      suppressed_count BIGINT NOT NULL DEFAULT 0,
      first_seen_at TIMESTAMP,
      last_seen_at TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS journal_event_totals_hero_type_uidx ON journal_event_totals (hero_id, entry_type)"
    )

    # ─── Лента: курсорная пагинация вместо глубокого OFFSET ───
    execute(
      "CREATE INDEX IF NOT EXISTS journal_entries_hero_created_id_idx ON journal_entries (hero_id, created_at DESC, id DESC)"
    )

    # Индекс под выборку кандидатов на очистку и под «последние N обычных».
    execute(
      "CREATE INDEX IF NOT EXISTS journal_entries_created_at_id_idx ON journal_entries (created_at, id)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS journal_entries_created_at_id_idx")
    execute("DROP INDEX IF EXISTS journal_entries_hero_created_id_idx")
    execute("DROP TABLE IF EXISTS journal_event_totals")
    execute("DROP TABLE IF EXISTS hero_daily_stats")
    execute("DROP TABLE IF EXISTS hero_milestones")
  end
end
