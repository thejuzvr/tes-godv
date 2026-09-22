alias TesIdle.Repo
alias TesIdle.Schemas.{Hero, JournalEntry, User}
import Ecto.Query

hero = Repo.one!(from h in Hero, limit: 1)
IO.puts("HERO=#{hero.id}")

try do
  entry = Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: "god", text: "probe"})
  IO.puts("INSERT_OK=#{entry.id}")
  Repo.delete!(entry)
  IO.puts("DELETED")
rescue
  e ->
    IO.puts("INSERT_FAIL")
    IO.puts(Exception.message(e))
end
