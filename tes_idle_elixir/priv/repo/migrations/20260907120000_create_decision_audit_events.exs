defmodule TesIdle.Repo.Migrations.CreateDecisionAuditEvents do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS decision_audit_events (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes (id) ON DELETE CASCADE,
      game_day INTEGER,
      game_hour DOUBLE PRECISION,
      event_type VARCHAR(32) NOT NULL,
      goal VARCHAR(64),
      action VARCHAR(128),
      utility DOUBLE PRECISION,
      reasons JSONB NOT NULL DEFAULT '{}'::jsonb,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS decision_audit_events_created_at_idx ON decision_audit_events (created_at DESC)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS decision_audit_events_hero_created_at_idx ON decision_audit_events (hero_id, created_at DESC)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS decision_audit_events_event_created_at_idx ON decision_audit_events (event_type, created_at DESC)"
    )
  end

  def down do
    execute("DROP TABLE IF EXISTS decision_audit_events")
  end
end
