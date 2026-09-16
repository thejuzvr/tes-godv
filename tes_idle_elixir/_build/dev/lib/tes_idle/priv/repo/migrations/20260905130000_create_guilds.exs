defmodule TesIdle.Repo.Migrations.CreateGuilds do
  @moduledoc "G-0: каркас гильдий — guilds + guild_members; заодно G-1/G-2 таблицы offering/messages."
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS guilds (
      id UUID PRIMARY KEY,
      name VARCHAR(24) NOT NULL,
      motto VARCHAR(80),
      emblem VARCHAR(8) NOT NULL DEFAULT '🛡️',
      description TEXT,
      leader_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      level INTEGER NOT NULL DEFAULT 1,
      exp INTEGER NOT NULL DEFAULT 0,
      policy VARCHAR(10) NOT NULL DEFAULT 'open',
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS guilds_name_unique_idx ON guilds (name);
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS guild_members (
      id UUID PRIMARY KEY,
      guild_id UUID NOT NULL REFERENCES guilds (id) ON DELETE CASCADE,
      user_id UUID NOT NULL UNIQUE REFERENCES users (id) ON DELETE CASCADE,
      role VARCHAR(10) NOT NULL DEFAULT 'member',
      points INTEGER NOT NULL DEFAULT 0,
      contributed INTEGER NOT NULL DEFAULT 0,
      joined_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS guild_members_guild_points_idx ON guild_members (guild_id, points DESC);
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS guild_offerings (
      id UUID PRIMARY KEY,
      guild_id UUID NOT NULL REFERENCES guilds (id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      hero_id UUID REFERENCES heroes (id) ON DELETE SET NULL,
      kind VARCHAR(10) NOT NULL DEFAULT 'gold',
      ref_id UUID,
      amount INTEGER NOT NULL DEFAULT 0,
      points INTEGER NOT NULL DEFAULT 0,
      inserted_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS guild_offerings_guild_idx ON guild_offerings (guild_id, inserted_at DESC);
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS guild_messages (
      id UUID PRIMARY KEY,
      guild_id UUID NOT NULL REFERENCES guilds (id) ON DELETE CASCADE,
      user_id UUID REFERENCES users (id) ON DELETE SET NULL,
      body VARCHAR(200) NOT NULL,
      kind VARCHAR(10) NOT NULL DEFAULT 'chat',
      inserted_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS guild_messages_guild_idx ON guild_messages (guild_id, inserted_at DESC);
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS guild_messages;")
    execute("DROP TABLE IF EXISTS guild_offerings;")
    execute("DROP TABLE IF EXISTS guild_members;")
    execute("DROP TABLE IF EXISTS guilds;")
  end
end
