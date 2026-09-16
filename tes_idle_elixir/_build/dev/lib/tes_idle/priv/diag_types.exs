alias TesIdle.Repo
import Ecto.Query

q = from t in TesIdle.Schemas.NarrativeTemplate, where: t.is_active and t.source == "system",
  group_by: t.template_type, select: {t.template_type, count(t.id)}
rows = Repo.all(q) |> Enum.sort()
IO.puts("TYPES: " <> Enum.map_join(rows, " ", fn {tp, n} -> "#{tp}:#{n}" end))
total = Enum.reduce(rows, 0, fn {_, n}, acc -> acc + n end)
IO.puts("TOTAL=#{total}")
System.halt(0)
