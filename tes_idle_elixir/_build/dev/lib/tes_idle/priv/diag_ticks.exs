# Временная диагностика: is_online + свежесть последней записи журнала по всем героям
alias TesIdle.Repo
import Ecto.Query

now = NaiveDateTime.utc_now()

heroes = Repo.all(
  from h in TesIdle.Schemas.Hero,
    select: {h.id, h.name, h.is_online, h.state}
)

for {id, name, online, state} <- heroes do
  last = Repo.one(
    from e in TesIdle.Schemas.JournalEntry,
      where: e.hero_id == ^id,
      select: max(e.created_at)
  )

  age_min = if last, do: div(NaiveDateTime.diff(now, last), 60), else: -1
  # интервал между двумя последними записями
  interval = if last do
    case Repo.all(
      from e in TesIdle.Schemas.JournalEntry,
        where: e.hero_id == ^id,
        order_by: [desc: e.created_at],
        limit: 2,
        select: e.created_at
    ) do
      [latest, prev] -> div(NaiveDateTime.diff(latest, prev), 60)
      _ -> -1
    end
  else
    -1
  end

  IO.puts("#{String.slice(name, 0, 12)} | online=#{online} | state=#{state} | last=#{age_min}m ago | gap_prev=#{interval}m")
end

System.halt(0)
