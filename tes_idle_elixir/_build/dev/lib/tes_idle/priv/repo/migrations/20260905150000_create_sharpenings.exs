defmodule TesIdle.Repo.Migrations.CreateSharpenings do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS sharpenings (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      hero_id UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
      item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      level INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute("CREATE UNIQUE INDEX IF NOT EXISTS sharpenings_hero_item_idx ON sharpenings (hero_id, item_id)")
  end

  def down do
    execute("DROP TABLE IF EXISTS sharpenings")
  end
end
