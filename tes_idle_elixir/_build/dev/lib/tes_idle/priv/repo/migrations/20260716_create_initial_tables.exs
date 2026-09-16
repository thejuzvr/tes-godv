defmodule TesIdle.Repo.Migrations.CreateInitialTables do
  use Ecto.Migration

  def up do
    # Check if tables already exist from Python backend
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_tables WHERE tablename = 'users') THEN
        CREATE TABLE users (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          username VARCHAR(100) NOT NULL UNIQUE,
          email VARCHAR(255) NOT NULL UNIQUE,
          password_hash VARCHAR(255) NOT NULL,
          is_admin BOOLEAN DEFAULT false,
          inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      END IF;
    END
    $$;
    """)

    # Add Ecto's migration tracking table if not exists
    execute("""
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version BIGINT PRIMARY KEY,
      inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    """)
  end

  def down do
    # Don't drop existing tables
  end
end
