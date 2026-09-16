defmodule TesIdle.Repo.Migrations.WidenJournalEntryType do
  @moduledoc """
  Расширение journal_entries.entry_type до varchar(64).

  В dev-БД колонка осталась varchar(20) от легаси-миграции — длинные типы событий
  («construction_donation», будущие guild_* / construction_stage) не влезают
  (value too long). Повторный ALTER безопасен (идемпотентно, правило 2.2).
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE journal_entries ALTER COLUMN entry_type TYPE varchar(64)")
  end

  def down do
    :ok
  end
end
