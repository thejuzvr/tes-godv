defmodule TesIdle.Repo.Migrations.CreateNarrativeFragments do
  @moduledoc "N-1: пулы описательных фрагментов Composer (тексты — только из БД)."
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS narrative_fragments (
      id UUID PRIMARY KEY,
      pool_key VARCHAR NOT NULL,
      text TEXT NOT NULL,
      weight INTEGER NOT NULL DEFAULT 1,
      source VARCHAR NOT NULL DEFAULT 'system',
      is_active BOOLEAN NOT NULL DEFAULT true,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS narrative_fragments_pool_idx ON narrative_fragments (pool_key);
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS narrative_fragments;")
  end
end
