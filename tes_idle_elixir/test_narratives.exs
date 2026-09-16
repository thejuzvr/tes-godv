# Тест: 200 тиков героя — проверка стабильности нарративов и логики
# Запуск: mix run test_narratives.exs

alias TesIdle.{Repo, Schemas.Hero}
alias TesIdle.Game.Pipeline
alias TesIdle.Schemas.{InventoryItem, ActiveQuest}
import Ecto.Query

hero_name = System.get_env("HERO") || "Нарвал"

hero = Repo.one(from h in Hero, where: h.name == ^hero_name, limit: 1, preload: [:location])
if !hero do
  IO.puts("Герой #{hero_name} не найден!")
  System.halt(1)
end

# Reset hero state for clean test
heal_hp = max(hero.hp, hero.max_hp)
hero = hero |> Ecto.Changeset.change(%{
  hp: heal_hp,
  state: "exploring",
  state_data: "{}",
}) |> Repo.update!()

IO.puts("=== Тест героя #{hero.name} (Lv.#{hero.level}) ===\n")
IO.puts("#{hero.name} HP:#{hero.hp}/#{hero.max_hp} Gold:#{hero.gold}\n")

total = 80
errors = 0
entries = []
last_types = []
death_count = 0
duplicate_ticks = 0

for tick <- 1..total do
  case Pipeline.tick(hero.id) do
    {:ok, result} ->
      hero = Repo.get!(Hero, hero.id)

      entry_type = get_in(result, [:narrative, :type])
      entry_text = (get_in(result, [:narrative, :text]) || "") |> String.slice(0, 60)

      if entry_type do
        entries = entries ++ [entry_type]
        last_types = (last_types ++ [entry_type]) |> Enum.take(5)

        # Check for repeats (>5 same in a row)
        if length(last_types) == 5 and Enum.uniq(last_types) == [hd(last_types)] do
          IO.puts("  ⚠️  ПОВТОР x5: #{entry_type}")
        end
      end

      # Check death
      if hero.hp <= 0 do
        death_count = death_count + 1
        IO.puts("  💀 СМЕРТЬ на тике #{tick}")
      end

      # Progress every 20 ticks
      if rem(tick, 20) == 0 do
        item_count = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id, select: count())
        quest = Repo.one(from aq in ActiveQuest, where: aq.hero_id == ^hero.id, limit: 1)
        quest_info = if quest, do: " Quest:step#{quest.current_step}/#{quest.current_progress}", else: ""
        IO.puts("[#{tick}/#{total}] HP:#{hero.hp}/#{hero.max_hp} Gold:#{hero.gold} Items:#{item_count}#{quest_info} | #{entry_type}: #{entry_text}")
      end

    {:error, reason} ->
      errors = errors + 1
      IO.puts("  ❌ ОШИБКА на тике #{tick}: #{inspect(reason)}")
  end
end

# Final stats
hero = Repo.get!(Hero, hero.id)
item_count = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id, select: count())

IO.puts("\n=== Итоги после #{total} тиков ===")
IO.puts("HP: #{hero.hp}/#{hero.max_hp}  Gold: #{hero.gold}  XP: #{hero.xp}/#{hero.xp_to_next}  Level: #{hero.level}")
IO.puts("Items: #{item_count}  Deaths: #{death_count}  Errors: #{errors}")

# Entry type distribution
type_counts = entries |> Enum.frequencies() |> Enum.sort_by(fn {_, c} -> -c end)
IO.puts("\nТипы записей (всего #{length(entries)}):")
Enum.each(Enum.take(type_counts, 10), fn {type, count} ->
  IO.puts("  #{type}: #{count}")
end)

# Check for problems
if errors > 0, do: IO.puts("\n⚠️  Есть ошибки: #{errors}")
if death_count > 5, do: IO.puts("\n⚠️  Слишком много смертей: #{death_count}")

IO.puts("\n✅ Тест завершён")
