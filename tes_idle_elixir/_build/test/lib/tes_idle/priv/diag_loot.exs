alias TesIdle.Repo
import Ecto.Query

IO.puts("monster_loot rows: #{Repo.one(from ml in TesIdle.Schemas.MonsterLoot, select: count(ml.id))}")
IO.puts("quests: #{Repo.one(from q in TesIdle.Schemas.Quest, select: count(q.id))}")
System.halt(0)
