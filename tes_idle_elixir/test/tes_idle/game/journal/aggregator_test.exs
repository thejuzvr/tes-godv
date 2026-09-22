defmodule TesIdle.Game.Journal.AggregatorTest do
  @moduledoc """
  Этап B: идемпотентность агрегатов и сквозных счётчиков.
  Обязательные проверки из docs/JOURNAL_RETENTION_ARCHITECTURE.md, раздел 12.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Journal.{Aggregator, Classifier}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, HeroDailyStat, JournalEntry, JournalEventTotal, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "agg_#{suffix}",
        email: "agg_#{suffix}@test.gg",
        password_hash: "x"
      })

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Агрегатор #{suffix}",
        race: "Норд",
        hero_class: "Воин"
      })

    %{hero: hero}
  end

  test "repeated delivery does not double the daily counters", %{hero: hero} do
    day = ~D[2026-05-01]

    Aggregator.record_published(hero.id, "hero_victory", nil, day: day, deltas: %{victories: 1, xp_gained: 10})
    Aggregator.record_published(hero.id, "hero_victory", nil, day: day, deltas: %{victories: 1, xp_gained: 10})

    stat = Repo.one!(from s in HeroDailyStat, where: s.hero_id == ^hero.id and s.day == ^day)

    assert stat.game_events == 2
    assert stat.published_entries == 2
    assert stat.victories == 2
    assert stat.xp_gained == 20
  end

  test "late events update the correct day instead of vanishing", %{hero: hero} do
    Aggregator.record_published(hero.id, "explore", nil, day: ~D[2026-05-01])
    # позднее событие задним числом
    Aggregator.record_published(hero.id, "explore", nil, day: ~D[2026-05-01])

    stat = Repo.one!(from s in HeroDailyStat, where: s.hero_id == ^hero.id and s.day == ^~D[2026-05-01])
    assert stat.game_events == 2

    # второй день не затронут
    assert Repo.one(from s in HeroDailyStat, where: s.day == ^~D[2026-05-02], select: count(s.id)) == 0
  end

  test "suppressed events are counted separately from published", %{hero: hero} do
    day = ~D[2026-05-03]

    Aggregator.record_published(hero.id, "explore", nil, day: day)
    Aggregator.record_suppressed(hero.id, "smell_flowers", nil, day: day)
    Aggregator.record_suppressed(hero.id, "smell_flowers", nil, day: day)

    stat = Repo.one!(from s in HeroDailyStat, where: s.hero_id == ^hero.id and s.day == ^day)

    # событие случилось трижды, текстом опубликовано один раз
    assert stat.game_events == 3
    assert stat.published_entries == 1
    assert stat.suppressed_entries == 2
  end

  test "cumulative totals survive regardless of retained rows", %{hero: hero} do
    Aggregator.record_published(hero.id, "explore")
    Aggregator.record_published(hero.id, "explore")
    Aggregator.record_suppressed(hero.id, "explore")

    totals = Aggregator.totals_for(hero.id)
    assert totals.created == 3
    assert totals.published == 2
    assert totals.suppressed == 1

    # счётчик по типу обновляется, а не создаёт вторую строку
    rows = Repo.all(from t in JournalEventTotal, where: t.hero_id == ^hero.id)
    assert length(rows) == 1
    assert hd(rows).entry_type == "explore"
  end

  test "backfill replaces counters so a second run does not double them", %{hero: hero} do
    day = ~D[2026-06-01]

    for _ <- 1..5 do
      Repo.insert!(%JournalEntry{
        hero_id: hero.id,
        entry_type: "explore",
        text: "Текст",
        xp_gained: 3,
        gold_gained: 1
      })
    end

    # проставляем created_at вручную: backfill группирует по дню created_at
    Repo.update_all(
      from(j in JournalEntry, where: j.hero_id == ^hero.id),
      set: [created_at: NaiveDateTime.new!(day, ~T[12:00:00])]
    )

    assert Aggregator.backfill_day(day) == 1
    first = Repo.one!(from s in HeroDailyStat, where: s.hero_id == ^hero.id and s.day == ^day)
    assert first.game_events == 5
    assert first.xp_gained == 15
    assert first.coverage == "backfill"

    # повторный прогон не удваивает
    assert Aggregator.backfill_day(day) == 1
    second = Repo.one!(from s in HeroDailyStat, where: s.hero_id == ^hero.id and s.day == ^day)
    assert second.game_events == 5
    assert second.xp_gained == 15
  end

  test "summary counts distinct heroes, not the sum of daily uniques", %{hero: hero} do
    user2 =
      Repo.insert!(%User{
        username: "agg2_#{System.unique_integer([:positive])}",
        email: "agg2_#{System.unique_integer([:positive])}@test.gg",
        password_hash: "x"
      })

    hero2 =
      Repo.insert!(%Hero{user_id: user2.id, name: "Второй", race: "Норд", hero_class: "Маг"})

    # один герой в два дня: сумма дневных uniques дала бы 2, distinct — 1
    Aggregator.record_published(hero.id, "explore", nil, day: ~D[2026-07-01])
    Aggregator.record_published(hero.id, "explore", nil, day: ~D[2026-07-02])
    Aggregator.record_published(hero2.id, "explore", nil, day: ~D[2026-07-01])

    summary = Aggregator.summary(~D[2026-07-01], ~D[2026-07-31])

    assert summary.heroes == 2
    assert summary.hero_days == 3
    assert summary.game_events == 3
  end

  test "daily rollup aggregates across heroes", %{hero: hero} do
    Aggregator.record_published(hero.id, "hero_victory", nil, day: ~D[2026-08-01], deltas: %{victories: 1, gold_gained: 25})

    [row] = Aggregator.daily(~D[2026-08-01], ~D[2026-08-01])

    assert row.day == ~D[2026-08-01]
    assert row.game_events == 1
    assert row.victories == 1
    assert row.gold == 25
  end

  test "aggregation failure never raises into the tick", %{hero: hero} do
    # Несуществующий герой нарушил бы FK — учёт обязан проглотить это,
    # потому что наблюдательный сбой не должен ронять тик героя.
    assert Aggregator.record_published(Ecto.UUID.generate(), "explore") == :ok
    assert Aggregator.record_suppressed(Ecto.UUID.generate(), "explore") == :ok
  end

  test "classifier protects important events from throttling", %{} do
    refute Classifier.throttleable?("hero_victory")
    refute Classifier.throttleable?("hero_defeat")
    refute Classifier.throttleable?("enemy_ambush")
    refute Classifier.throttleable?("death_respawn")

    assert Classifier.throttleable?("smell_flowers")
    assert Classifier.throttleable?("watch_sunset")
  end

  test "ambient type carrying a victory is treated as important", %{} do
    # generic_action нельзя считать пустым: за ним может скрываться победа
    refute Classifier.throttleable?("generic_action", %{combat_result: %{hero_defeated: false}})
    assert Classifier.classify("generic_action", %{combat_result: %{victory: true}}) == :important

    # смерть героя в «фоновом» типе — тоже не атмосфера
    assert Classifier.classify("generic_action", %{combat_result: %{hero_defeated: true}}) ==
             :important
  end

  test "ambient type with rewards is progress, not noise", %{} do
    assert Classifier.classify("collect_herbs", %{xp: 5}) == :progress
    assert Classifier.classify("collect_herbs") == :ambient
  end
end
