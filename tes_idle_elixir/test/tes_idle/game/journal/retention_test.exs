defmodule TesIdle.Game.Journal.RetentionTest do
  @moduledoc """
  Этап C/D: очистка обычной хроники.
  Проверки из docs/JOURNAL_RETENTION_ARCHITECTURE.md, раздел 12:
  минимальный хвост и важные типы переживают очистку, dry-run ничего не удаляет.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Journal.Retention
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "ret_#{suffix}",
        email: "ret_#{suffix}@test.gg",
        password_hash: "x"
      })

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Хроникёр #{suffix}",
        race: "Норд",
        hero_class: "Воин"
      })

    %{hero: hero}
  end

  defp entry(hero, type, days_ago) do
    at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-days_ago * 86_400, :second)
      |> NaiveDateTime.truncate(:second)

    Repo.insert!(%JournalEntry{
      hero_id: hero.id,
      entry_type: type,
      text: "Текст #{type}",
      created_at: at
    })
  end

  defp enabled(days, keep) do
    %{
      "journal_retention" => %{
        "enabled" => true,
        "dry_run" => false,
        "routine_days" => days,
        "keep_last_routine" => keep,
        "batch_size" => 100
      }
    }
  end

  test "disabled by default and does nothing", %{hero: hero} do
    entry(hero, "explore", 30)

    report = Retention.run(%{})

    assert report.skipped
    assert report.reason == :disabled
    assert Repo.aggregate(JournalEntry, :count) == 1
  end

  test "dry run reports candidates without deleting anything", %{hero: hero} do
    for _ <- 1..20, do: entry(hero, "explore", 30)

    configs = %{"journal_retention" => %{"enabled" => true, "dry_run" => true, "routine_days" => 7, "keep_last_routine" => 5}}
    report = Retention.run(configs)

    assert report.dry_run
    assert report.deleted == 0
    # 20 старых обычных записей минус сохранённый хвост из 5
    assert report.candidates == 15
    assert Repo.aggregate(JournalEntry, :count) == 20
  end

  test "keeps the last N routine entries regardless of age", %{hero: hero} do
    # Все записи старше окна: без хвоста удалились бы все.
    for _ <- 1..10, do: entry(hero, "explore", 30)

    report = Retention.run(enabled(7, 4))

    assert report.deleted == 6
    assert Repo.aggregate(JournalEntry, :count) == 4
  end

  test "protected types survive cleanup entirely", %{hero: hero} do
    entry(hero, "hero_victory", 30)
    entry(hero, "hero_defeat", 30)
    entry(hero, "enemy_ambush", 30)
    entry(hero, "death_respawn", 30)
    entry(hero, "dream", 30)
    entry(hero, "world_news", 30)
    for _ <- 1..10, do: entry(hero, "explore", 30)

    Retention.run(enabled(7, 2))

    remaining = Repo.all(from j in JournalEntry, select: j.entry_type) |> Enum.frequencies()

    # важное и вехи не тронуты
    assert remaining["hero_victory"] == 1
    assert remaining["hero_defeat"] == 1
    assert remaining["enemy_ambush"] == 1
    assert remaining["death_respawn"] == 1
    assert remaining["dream"] == 1
    assert remaining["world_news"] == 1
    # обычных осталось ровно 2 (хвост)
    assert remaining["explore"] == 2
  end

  test "recent entries inside the window are never touched", %{hero: hero} do
    entry(hero, "explore", 0)
    entry(hero, "explore", 1)
    entry(hero, "explore", 3)
    entry(hero, "explore", 30)

    # Свежие записи защищены окном в любом случае: хвост держит самую
    # новую запись, старая уходит.
    Retention.run(enabled(7, 1))

    remaining = Repo.all(from j in JournalEntry, select: j.created_at)
    assert length(remaining) == 3
    # ни одна из свежих записей не удалена
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-7 * 86_400, :second)
    assert Enum.all?(remaining, &(NaiveDateTime.compare(&1, cutoff) == :gt))
  end

  test "preview shows what would be removed, grouped by type", %{hero: hero} do
    for _ <- 1..6, do: entry(hero, "explore", 30)
    for _ <- 1..4, do: entry(hero, "smell_flowers", 30)

    preview = Retention.preview(enabled(7, 5))

    assert preview.dry_run
    assert preview.candidates == 5
    assert preview.keep_last_routine == 5
    types = Map.new(preview.by_type, fn t -> {t.entry_type, t["count"] || t.count} end)
    assert map_size(types) >= 1
    # предпросмотр не удаляет
    assert Repo.aggregate(JournalEntry, :count) == 10
  end

  test "oversized heroes are reported for investigation", %{hero: hero} do
    for _ <- 1..12, do: entry(hero, "explore", 1)

    heroes = Retention.oversized_heroes(%{"journal_retention" => %{"warning_rows_per_hero" => 10}})

    assert Enum.any?(heroes, &(&1.hero_id == hero.id and &1.rows == 12))
  end

  test "cleanup is batched and reports batch count", %{hero: hero} do
    for _ <- 1..25, do: entry(hero, "explore", 30)

    report = Retention.run(enabled(7, 5))

    assert report.deleted == 20
    assert report.batches >= 1
    assert report.heroes == 1
  end

  test "runs again cleanly when there is nothing left to delete", %{hero: hero} do
    for _ <- 1..5, do: entry(hero, "explore", 30)

    first = Retention.run(enabled(7, 2))
    assert first.deleted == 3

    second = Retention.run(enabled(7, 2))
    assert second.deleted == 0
    assert second.candidates == 0
  end

  test "config defaults are conservative and bounded", %{} do
    cfg = Retention.config(%{})

    # по умолчанию выключено и в dry-run — включение требует осознанного действия
    refute cfg.enabled
    assert cfg.dry_run
    assert cfg.routine_days == 7
    assert cfg.keep_last_routine == 500

    # мусор в конфиге не ломает и не расширяет границы
    weird = Retention.config(%{"journal_retention" => %{"routine_days" => "abc", "batch_size" => 999_999}})
    assert weird.routine_days == 7
    assert weird.batch_size == 10_000
  end
end
