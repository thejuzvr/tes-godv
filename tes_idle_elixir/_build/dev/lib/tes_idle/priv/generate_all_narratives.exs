# N-5 one-off: генерация кандидатов LlmFactory по ВСЕМ типам шаблонов.
# Запуск: mix run priv/generate_all_narratives.exs
#
# По каждому template_type: до 12 кандидатов (обычные + комичные опенеры/closers
# в пулах дают тональную смесь). Кандидаты идут в модерацию (is_active=false).
# Идемпотентность текстов — uniq_by в фабрике; повторный запуск добавит только
# новые комбинации (дедуп по тексту на уровне insert не делаем — кандидаты
# можно отсеять в модерации).

alias TesIdle.Repo
alias TesIdle.Schemas.NarrativeTemplate
alias TesIdle.Game.Narrative.LlmFactory
import Ecto.Query

unless LlmFactory.fragments_available?() do
  IO.puts("Пулы фрагментов пусты — сначала mix run priv/seed_fragments.exs")
  System.halt(1)
end

types = Repo.all(from t in NarrativeTemplate, distinct: true, select: t.template_type)

per_type = 12
results =
  types
  |> Enum.sort()
  |> Map.new(fn type ->
    {:ok, candidates} = LlmFactory.generate(type, per_type)
    {type, length(candidates)}
  end)

total = results |> Map.values() |> Enum.sum()
empty = results |> Enum.filter(fn {_t, n} -> n == 0 end) |> Enum.map(&elem(&1, 0))

Enum.each(Enum.sort(results), fn {type, n} ->
  IO.puts("#{type}: #{n}")
end)

IO.puts("\nИтого: #{total} кандидатов по #{map_size(results)} типам")
if empty != [], do: IO.puts("Пустые типы (нет system-костяков): #{Enum.join(empty, ", ")}")
IO.puts("Ожидают модерации: #{LlmFactory.pending_count()}")
