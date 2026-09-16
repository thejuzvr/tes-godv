defmodule TesIdle.Repo.Migrations.CreateGuildApplications do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS guild_applications (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      status VARCHAR(20) NOT NULL DEFAULT 'pending',
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute("CREATE UNIQUE INDEX IF NOT EXISTS guild_applications_pending_user_idx ON guild_applications (user_id) WHERE status = 'pending'")
    execute("CREATE INDEX IF NOT EXISTS guild_applications_guild_idx ON guild_applications (guild_id, status)")
  end

  def down do
    execute("DROP TABLE IF EXISTS guild_applications")
  end
end
