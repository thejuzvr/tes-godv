defmodule TesIdle.Repo.Migrations.AddHeroPassport do
  @moduledoc """
  Паспорт героя (docs/PLAN_CHARACTER.md): предыстория, текст картотеки,
  искры и купленные пассивы. Идемпотентно: колонки могли появиться вручную.
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE heroes ADD COLUMN IF NOT EXISTS origin VARCHAR(32)")
    execute("ALTER TABLE heroes ADD COLUMN IF NOT EXISTS dossier VARCHAR(500) NOT NULL DEFAULT ''")
    execute("ALTER TABLE heroes ADD COLUMN IF NOT EXISTS soul_sparks INTEGER NOT NULL DEFAULT 0")
    execute("ALTER TABLE heroes ADD COLUMN IF NOT EXISTS passives JSONB NOT NULL DEFAULT '{}'::jsonb")
  end

  def down do
    execute("ALTER TABLE heroes DROP COLUMN IF EXISTS passives")
    execute("ALTER TABLE heroes DROP COLUMN IF EXISTS soul_sparks")
    execute("ALTER TABLE heroes DROP COLUMN IF EXISTS dossier")
    execute("ALTER TABLE heroes DROP COLUMN IF EXISTS origin")
  end
end
