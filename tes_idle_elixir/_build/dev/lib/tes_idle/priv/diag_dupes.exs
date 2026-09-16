# CD-1 разовый: дубликаты предметов в dev БД
alias TesIdle.Repo
import Ecto.Query

dupes =
  Repo.all(from i in TesIdle.Schemas.Item, group_by: i.name, select: {i.name, count(i.id)})
  |> Enum.filter(fn {_n, c} -> c > 1 end)

IO.puts("DUPES=#{length(dupes)}")
Enum.each(dupes, fn {n, c} -> IO.puts("#{n}: #{c}") end)
System.halt(0)
