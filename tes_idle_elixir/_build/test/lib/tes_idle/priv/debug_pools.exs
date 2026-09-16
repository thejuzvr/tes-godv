alias TesIdle.Repo
alias TesIdle.Schemas.NarrativeFragment
import Ecto.Query
for pool <- ["openers_rain", "closers_high"] do
  texts = Repo.all(from f in NarrativeFragment, where: f.pool_key == ^pool, select: f.text)
  IO.puts(pool <> ": #{length(texts)} строк")
  Enum.each(texts, &IO.puts("  | " <> &1))
end
