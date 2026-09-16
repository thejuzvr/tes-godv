defmodule TesIdle.Repo.Migrations.CreateGuildNews do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS guild_news (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      guild_id UUID REFERENCES guilds(id) ON DELETE SET NULL,
      template_type VARCHAR(40) NOT NULL,
      text TEXT NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS guild_news_created_idx ON guild_news (created_at DESC)")
  end

  def down do
    execute("DROP TABLE IF EXISTS guild_news")
  end
end
