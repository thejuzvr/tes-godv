defmodule TesIdle.Repo.Migrations.AddJournalChapters do
  @moduledoc "S-3: главы дневника (chapter/chapter_title) и мотивы решений (motive)."
  use Ecto.Migration

  def up do
    execute("ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS chapter integer")
    execute("ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS chapter_title varchar(120)")
    execute("ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS motive text")
  end

  def down do
    execute("ALTER TABLE journal_entries DROP COLUMN IF EXISTS motive")
    execute("ALTER TABLE journal_entries DROP COLUMN IF EXISTS chapter_title")
    execute("ALTER TABLE journal_entries DROP COLUMN IF EXISTS chapter")
  end
end