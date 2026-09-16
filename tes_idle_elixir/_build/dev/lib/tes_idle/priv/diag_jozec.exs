# Временная диагностика: почему хроника Джозеца молчит
alias TesIdle.Repo
import Ecto.Query

hero = Repo.one!(from h in TesIdle.Schemas.Hero, where: h.name == "Джозец")
IO.puts("id=#{hero.id}")
IO.puts("state=#{hero.state} loc=#{hero.location_id} gold=#{hero.gold} hp=#{hero.hp}/#{hero.max_hp}")

sd = if is_binary(hero.state_data), do: Jason.decode!(hero.state_data), else: (hero.state_data || %{})
IO.puts("plan: #{inspect(sd["plan"], limit: 5)}")
IO.puts("brain.goal: #{inspect(get_in(sd, ["brain", "goal"]), limit: 3)}")

loc = Repo.get!(TesIdle.Schemas.Location, hero.location_id)
IO.puts("location: #{loc.name} flags=#{inspect(loc.flags, limit: 4)}")

IO.puts("--- manual tick ---")
result = TesIdle.Game.Pipeline.tick(hero.id)

if is_map(result) do
  IO.puts("keys: #{inspect(Map.keys(result))}")
  IO.puts("state_to: #{inspect(result[:state_to])}")
  je = result[:journal_entry] || Map.get(result, :journal_entry)
  IO.puts("journal_entry: #{if je, do: inspect(%{type: je.entry_type, text: String.slice(je.text || "", 0, 80)}), else: "NIL — записи нет"}")
  hd = Map.get(result, :hero_delta)
  IO.puts("hero_delta: #{inspect(hd, limit: 4)}")
else
  IO.puts("result: #{inspect(result)}")
end

# Каденция последних 6 записей Джозеца
recent = Repo.all(
  from e in TesIdle.Schemas.JournalEntry,
    where: e.hero_id == ^hero.id,
    order_by: [desc: e.created_at],
    limit: 6,
    select: {e.entry_type, e.created_at}
)
now = NaiveDateTime.utc_now()
IO.puts("--- last 6 entries ---")
Enum.each(recent, fn {t, at} ->
  IO.puts("#{t} | #{div(NaiveDateTime.diff(now, at), 60)}m ago")
end)

social_active = Repo.one(
  from(t in TesIdle.Schemas.NarrativeTemplate,
    where: t.template_type == "social" and t.is_active,
    select: count(t.id)
  )
)
IO.puts("active social templates: #{social_active}")

System.halt(0)
