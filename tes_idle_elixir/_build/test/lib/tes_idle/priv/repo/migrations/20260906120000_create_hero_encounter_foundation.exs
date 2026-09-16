defmodule TesIdle.Repo.Migrations.CreateHeroEncounterFoundation do
  @moduledoc "DB foundation for safe, idempotent encounters between co-located heroes."
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS hero_encounters (
      id UUID PRIMARY KEY,
      hero_low_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      hero_high_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      round BIGINT NOT NULL,
      location_id UUID NOT NULL REFERENCES locations (id) ON DELETE RESTRICT,
      kind VARCHAR(32) NOT NULL,
      status VARCHAR(32) NOT NULL DEFAULT 'pending',
      shared_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      idempotency_key VARCHAR(128) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
      CONSTRAINT hero_encounters_ordered_pair_check CHECK (hero_low_id < hero_high_id)
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS hero_encounters_idempotency_uidx ON hero_encounters (idempotency_key)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS hero_encounters_round_location_idx ON hero_encounters (round, location_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS hero_encounters_pair_idx ON hero_encounters (hero_low_id, hero_high_id, round DESC)"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS encounter_claims (
      id UUID PRIMARY KEY,
      round BIGINT NOT NULL,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      encounter_id UUID REFERENCES hero_encounters (id) ON DELETE CASCADE,
      claimed_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS encounter_claims_round_hero_uidx ON encounter_claims (round, hero_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS encounter_claims_encounter_idx ON encounter_claims (encounter_id)"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS encounter_participants (
      id UUID PRIMARY KEY,
      encounter_id UUID NOT NULL REFERENCES hero_encounters (id) ON DELETE CASCADE,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      role VARCHAR(32),
      private_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS encounter_participants_encounter_hero_uidx ON encounter_participants (encounter_id, hero_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS encounter_participants_hero_idx ON encounter_participants (hero_id, created_at DESC)"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS hero_relationships (
      id UUID PRIMARY KEY,
      hero_low_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      hero_high_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      familiarity INTEGER NOT NULL DEFAULT 0,
      encounter_count INTEGER NOT NULL DEFAULT 0,
      cooldown_until TIMESTAMP,
      shared_tags VARCHAR[] NOT NULL DEFAULT ARRAY[]::varchar[],
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
      CONSTRAINT hero_relationships_ordered_pair_check CHECK (hero_low_id < hero_high_id),
      CONSTRAINT hero_relationships_familiarity_check CHECK (familiarity >= 0),
      CONSTRAINT hero_relationships_encounter_count_check CHECK (encounter_count >= 0)
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS hero_relationships_pair_uidx ON hero_relationships (hero_low_id, hero_high_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS hero_relationships_cooldown_idx ON hero_relationships (cooldown_until)"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS hero_relationship_sides (
      id UUID PRIMARY KEY,
      relationship_id UUID NOT NULL REFERENCES hero_relationships (id) ON DELETE CASCADE,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      affinity INTEGER NOT NULL DEFAULT 0,
      tags VARCHAR[] NOT NULL DEFAULT ARRAY[]::varchar[],
      private_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS hero_relationship_sides_relationship_hero_uidx ON hero_relationship_sides (relationship_id, hero_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS hero_relationship_sides_hero_idx ON hero_relationship_sides (hero_id)"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS hero_social_settings (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      encounter_mode VARCHAR(32) NOT NULL DEFAULT 'live_only',
      reveal_name VARCHAR(32) NOT NULL DEFAULT 'encounter',
      daily_cap INTEGER,
      cooldown_seconds INTEGER,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
      CONSTRAINT hero_social_settings_daily_cap_check CHECK (daily_cap IS NULL OR daily_cap >= 0),
      CONSTRAINT hero_social_settings_cooldown_check CHECK (cooldown_seconds IS NULL OR cooldown_seconds >= 0)
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS hero_social_settings_hero_uidx ON hero_social_settings (hero_id)"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS hero_blocks (
      id UUID PRIMARY KEY,
      blocker_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      blocked_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      CONSTRAINT hero_blocks_distinct_heroes_check CHECK (blocker_id <> blocked_id)
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS hero_blocks_blocker_blocked_uidx ON hero_blocks (blocker_id, blocked_id)"
    )

    execute("CREATE INDEX IF NOT EXISTS hero_blocks_blocked_idx ON hero_blocks (blocked_id)")

    execute("""
    CREATE TABLE IF NOT EXISTS event_outbox (
      id UUID PRIMARY KEY,
      encounter_id UUID REFERENCES hero_encounters (id) ON DELETE SET NULL,
      event_type VARCHAR(64) NOT NULL,
      payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      idempotency_key VARCHAR(128) NOT NULL,
      status VARCHAR(32) NOT NULL DEFAULT 'pending',
      attempts INTEGER NOT NULL DEFAULT 0,
      available_at TIMESTAMP NOT NULL DEFAULT NOW(),
      processed_at TIMESTAMP,
      last_error TEXT,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      CONSTRAINT event_outbox_attempts_check CHECK (attempts >= 0)
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS event_outbox_idempotency_uidx ON event_outbox (idempotency_key)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS event_outbox_pending_idx ON event_outbox (available_at, created_at) WHERE status = 'pending'"
    )

    execute(
      "ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS encounter_id UUID REFERENCES hero_encounters (id) ON DELETE SET NULL"
    )

    execute("ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS perspective_role VARCHAR(32)")

    execute(
      "ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS template_id UUID REFERENCES narrative_templates (id) ON DELETE SET NULL"
    )

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS journal_entries_encounter_hero_uidx ON journal_entries (encounter_id, hero_id) WHERE encounter_id IS NOT NULL"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS journal_entries_template_idx ON journal_entries (template_id) WHERE template_id IS NOT NULL"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS heroes_encounter_eligibility_idx ON heroes (location_id, last_activity DESC) WHERE location_id IS NOT NULL"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS heroes_encounter_eligibility_idx")
    execute("DROP INDEX IF EXISTS journal_entries_template_idx")
    execute("DROP INDEX IF EXISTS journal_entries_encounter_hero_uidx")
    execute("ALTER TABLE journal_entries DROP COLUMN IF EXISTS template_id")
    execute("ALTER TABLE journal_entries DROP COLUMN IF EXISTS perspective_role")
    execute("ALTER TABLE journal_entries DROP COLUMN IF EXISTS encounter_id")
    execute("DROP TABLE IF EXISTS event_outbox")
    execute("DROP TABLE IF EXISTS hero_blocks")
    execute("DROP TABLE IF EXISTS hero_social_settings")
    execute("DROP TABLE IF EXISTS hero_relationship_sides")
    execute("DROP TABLE IF EXISTS hero_relationships")
    execute("DROP TABLE IF EXISTS encounter_participants")
    execute("DROP TABLE IF EXISTS encounter_claims")
    execute("DROP TABLE IF EXISTS hero_encounters")
  end
end
