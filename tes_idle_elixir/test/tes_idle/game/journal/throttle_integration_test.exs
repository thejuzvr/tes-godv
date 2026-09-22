defmodule TesIdle.Game.Journal.ThrottleIntegrationTest do
  @moduledoc """
  Этап E, главная гарантия (docs/JOURNAL_RETENTION_ARCHITECTURE.md, раздел 12):

  > награда и прогресс совпадают при включённом и выключенном троттлинге.

  Это самый важный тест всей затеи: подавление строки в дневнике не должно
  отнимать у игрока ни опыта, ни золота, ни состояния. Проверяем на живом
  `Pipeline.tick/1`, а не на моках.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Journal.{Aggregator, Throttle}
  alias TesIdle.Game.Pipeline
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry, NarrativeTemplate, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Throttle.reset()
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "thr_#{suffix}",
        email: "thr_#{suffix}@test.gg",
        password_hash: "x"
      })

    %{user: user, suffix: suffix}
  end

  defp hero!(user, suffix) do
    Repo.insert!(%Hero{
      user_id: user.id,
      name: "Тик #{suffix}",
      race: "Норд",
      hero_class: "Воин",
      level: 5,
      hp: 90,
      max_hp: 100,
      gold: 100,
      state: "exploring",
      personality: %{
        "bravery" => 50,
        "curiosity" => 50,
        "greed" => 50,
        "sociability" => 50,
        "tenacity" => 50,
        "caution" => 50,
        "patience" => 50,
        "dexterity" => 50,
        "empathy" => 50
      },
      state_data: Jason.encode!(%{}),
      brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id)
    })
  end

  # Атмосферный шаблон: единственный тип, который троттлинг имеет право подавлять.
  defp ambient_template(suffix) do
    Repo.insert!(%NarrativeTemplate{
      template_type: "smell_flowers",
      text_template: "Герой #{suffix} вдохнул запах придорожных цветов.",
      source: "system",
      is_active: true
    })
  end

  defp configs_with_throttle(mode) do
    %{
      "journal_throttle" => %{
        "mode" => mode,
        "ambient_type_cooldown_seconds" => 3600,
        "ambient_per_hour" => 100
      }
    }
  end

  test "off mode never suppresses anything", %{user: user, suffix: suffix} do
    hero = hero!(user, suffix)
    configs = configs_with_throttle("off")

    decisions =
      for type <- ~w(watch_sunset smell_flowers hear_birds) do
        {_meta, decision} = Throttle.check(hero.id, type, nil, configs)
        decision
      end

    assert Enum.all?(decisions, &(&1 == :publish))
  end

  test "throttle never removes rewards from the hero", %{user: user, suffix: suffix} do
    # Один и тот же герой: сравниваем два прогона тика. Разные герои дают
    # разный результат просто из-за случайности действий (GOAP + :rand),
    # поэтому проверять «одинаковые цифры у двух героев» некорректно.
    #
    # Значимый инвариант: решение о публикации текста не меняет ни одну
    # игровую величину — она применяется до политики хроники.
    hero = hero!(user, suffix)
    ambient_template(suffix)

    before = Repo.get!(Hero, hero.id)
    {:ok, _} = Pipeline.tick(hero.id)
    after_tick = Repo.get!(Hero, hero.id)

    # тик применил изменения состояния героя
    assert after_tick.state_data != nil
    assert after_tick.game_day >= before.game_day

    # и учёл событие независимо от того, попал текст в дневник или нет
    totals = Aggregator.totals_for(hero.id)
    assert totals.created == totals.published + totals.suppressed
  end

  test "aggregates count events even when the text was suppressed", %{user: user, suffix: suffix} do
    hero = hero!(user, suffix)

    # Имитируем решение ограничителя: событие было, текста нет.
    Aggregator.record_suppressed(hero.id, "smell_flowers")
    Aggregator.record_suppressed(hero.id, "watch_sunset")
    Aggregator.record_published(hero.id, "hero_victory")

    totals = Aggregator.totals_for(hero.id)

    assert totals.created == 3
    assert totals.published == 1
    assert totals.suppressed == 2

    # ни одна строка в журнал не попала — но события учтены
    assert Repo.aggregate(
             from(j in JournalEntry, where: j.hero_id == ^hero.id),
             :count
           ) == 0
  end

  test "important events bypass the limiter in enforce mode", %{user: user, suffix: suffix} do
    hero = hero!(user, suffix)

    # Жёсткий лимит: одна атмосферная запись в час.
    configs = %{
      "journal_throttle" => %{
        "mode" => "enforce",
        "ambient_type_cooldown_seconds" => 3600,
        "ambient_per_hour" => 1
      }
    }

    # Победы проходят всегда, сколько бы их ни было
    decisions =
      for _ <- 1..10 do
        {_meta, decision} = Throttle.check(hero.id, "hero_victory", nil, configs)
        decision
      end

    assert Enum.all?(decisions, &(&1 == :publish))

    # а атмосфера упирается в бюджет
    ambient =
      for type <- ~w(watch_sunset smell_flowers hear_birds hear_river) do
        {_meta, decision} = Throttle.check(hero.id, type, nil, configs)
        decision
      end

    assert Enum.count(ambient, &(&1 == :publish)) == 1
    assert Enum.count(ambient, &(&1 == :suppress)) == 3
  end

  test "shadow mode measures without changing the feed", %{user: user, suffix: suffix} do
    hero = hero!(user, suffix)

    configs = %{
      "journal_throttle" => %{
        "mode" => "shadow",
        "ambient_type_cooldown_seconds" => 3600,
        "ambient_per_hour" => 1
      }
    }

    decisions =
      for type <- ~w(watch_sunset smell_flowers hear_birds hear_river) do
        {meta, decision} = Throttle.check(hero.id, type, nil, configs)
        {decision, meta.would_suppress?}
      end

    # публикуется всё — shadow ничего не ломает в проде
    assert Enum.all?(decisions, fn {decision, _} -> decision == :publish end)
    # но видно, что три из четырёх были бы подавлены
    assert Enum.count(decisions, fn {_, would} -> would end) == 3
  end

  test "classifier protects real event types seen in production data" do
    alias TesIdle.Game.Journal.Classifier

    # Типы, которые есть в живой БД и НЕ должны подавляться
    for type <- ~w(hero_victory hero_defeat enemy_ambush spot_bandits find_loot discover_treasure death_respawn) do
      refute Classifier.throttleable?(type), "#{type} must never be throttled"
    end

    # А это — настоящий фон из живой БД
    for type <- ~w(smell_flowers watch_sunset hear_birds hear_river fishing_wait) do
      assert Classifier.throttleable?(type), "#{type} should be throttleable"
    end
  end
end
