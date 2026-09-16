# Временная разведка: монстры × локации
alias TesIdle.Repo
import Ecto.Query

locs = Repo.all(from l in TesIdle.Schemas.Location, select: {l.id, l.name, l.location_type})
IO.puts("locations: #{length(locs)}")

per_loc =
  Repo.all(from m in TesIdle.Schemas.Monster, select: {m.location_id, m.name})
  |> Enum.group_by(fn {lid, _} -> lid end, fn {_, n} -> n end)

Enum.each(Enum.sort(locs, fn {_, a, _}, {_, b, _} -> a <= b end), fn {id, name, type} ->
  ms = Map.get(per_loc, id, [])
  IO.puts("#{name} (#{type}): #{length(ms)} — #{Enum.join(ms, ", ")}")
end)

System.halt(0)
