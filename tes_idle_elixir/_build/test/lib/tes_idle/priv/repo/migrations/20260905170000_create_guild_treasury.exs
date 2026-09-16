defmodule TesIdle.Repo.Migrations.CreateGuildTreasury do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE guilds ADD COLUMN IF NOT EXISTS treasury INTEGER NOT NULL DEFAULT 0")

    execute("""
    CREATE TABLE IF NOT EXISTS guild_treasury_log (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
      user_id UUID REFERENCES users(id) ON DELETE SET NULL,
      kind VARCHAR(20) NOT NULL,
      amount INTEGER NOT NULL,
      balance_after INTEGER NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS guild_treasury_log_guild_idx ON guild_treasury_log (guild_id, created_at DESC)"
    )

    execute(
      "ALTER TABLE guilds ADD COLUMN IF NOT EXISTS boost_until TIMESTAMP"
    )
  end

  def down do
    execute("DROP TABLE IF EXISTS guild_treasury_log")
    execute("ALTER TABLE guilds DROP COLUMN IF EXISTS treasury")
    execute("ALTER TABLE guilds DROP COLUMN IF EXISTS boost_until")
  end
end
