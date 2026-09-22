defmodule TesIdle.Game.Journal.ThrottleTest do
  @moduledoc """
  Этап E: ограничение атмосферных повторов.
  Проверки из docs/JOURNAL_RETENTION_ARCHITECTURE.md, раздел 12:
  важные события проходят, разные типы не обходят общий бюджет,
  режимы shadow/off/enforce ведут себя предсказуемо.
  """
  use ExUnit.Case, async: false

  alias TesIdle.Game.Journal.Throttle

  setup do
    Throttle.init()
    Throttle.reset()
    :ok
  end

  defp enforce(cooldown, per_hour) do
    %{
      "journal_throttle" => %{
        "mode" => "enforce",
        "ambient_type_cooldown_seconds" => cooldown,
        "ambient_per_hour" => per_hour
      }
    }
  end

  test "same ambient type is suppressed inside the cooldown window" do
    configs = enforce(600, 100)
    hero = Ecto.UUID.generate()

    {first, :publish} = Throttle.check(hero, "watch_sunset", nil, configs)
    assert first.allowed?

    # сразу повтор — окно занято
    {second, :suppress} = Throttle.check(hero, "watch_sunset", nil, configs)
    refute second.allowed?
    assert second.reason == :type_cooldown
    assert second.suppressed?
  end

  test "important events never get suppressed" do
    configs = enforce(600, 1)
    hero = Ecto.UUID.generate()

    for _ <- 1..20 do
      {meta, decision} = Throttle.check(hero, "hero_victory", nil, configs)
      assert decision == :publish
      assert meta.reason == :protected
    end

    # смерть и победа в «фоновом» типе тоже защищены
    {meta, :publish} = Throttle.check(hero, "generic_action", %{combat_result: %{victory: true}}, configs)
    assert meta.reason == :protected

    {meta2, :publish} = Throttle.check(hero, "generic_action", %{combat_result: %{hero_defeated: true}}, configs)
    assert meta2.reason == :protected
  end

  test "many different ambient types cannot bypass the hourly budget" do
    # Кулдаун на тип огромный, поэтому типы не мешают друг другу,
    # но бюджет часа должен остановить поток.
    configs = enforce(100_000, 3)
    hero = Ecto.UUID.generate()

    types = ~w(watch_sunset smell_flowers hear_birds hear_river hear_wolves watch_stars count_coins hum_tune)

    decisions =
      Enum.map(types, fn type ->
        {_meta, decision} = Throttle.check(hero, type, nil, configs)
        decision
      end)

    published = Enum.count(decisions, &(&1 == :publish))
    suppressed = Enum.count(decisions, &(&1 == :suppress))

    assert published == 3
    assert suppressed == length(types) - 3
  end

  test "budget is per hero, not shared across heroes" do
    configs = enforce(600, 2)
    hero_a = Ecto.UUID.generate()
    hero_b = Ecto.UUID.generate()

    for _ <- 1..2, do: Throttle.check(hero_a, "watch_sunset", nil, configs)
    {_meta, decision} = Throttle.check(hero_a, "smell_flowers", nil, configs)
    assert decision == :suppress

    # другой герой не страдает от бюджета первого
    {other_meta, :publish} = Throttle.check(hero_b, "smell_flowers", nil, configs)
    assert other_meta.allowed?
    refute other_meta.suppressed?
  end

  test "shadow mode publishes everything but reports what would be suppressed" do
    configs = %{
      "journal_throttle" => %{
        "mode" => "shadow",
        "ambient_type_cooldown_seconds" => 600,
        "ambient_per_hour" => 1
      }
    }

    hero = Ecto.UUID.generate()

    {first, :publish} = Throttle.check(hero, "watch_sunset", nil, configs)
    refute first.would_suppress?

    {second, :publish} = Throttle.check(hero, "watch_sunset", nil, configs)
    # публикуем, но помечаем
    assert second.would_suppress?
    refute second.suppressed?
    assert second.mode == :shadow
  end

  test "off mode disables the limiter entirely" do
    configs = %{"journal_throttle" => %{"mode" => "off", "ambient_per_hour" => 1}}
    hero = Ecto.UUID.generate()

    for _ <- 1..10 do
      {meta, decision} = Throttle.check(hero, "watch_sunset", nil, configs)
      assert decision == :publish
      assert meta.reason == :off
    end
  end

  test "default mode is shadow, so the limiter is safe by default" do
    # Пустой конфиг не должен внезапно начать подавлять записи.
    hero = Ecto.UUID.generate()
    {_meta, decision} = Throttle.check(hero, "watch_sunset", nil, %{})
    assert decision == :publish

    config = Throttle.config(%{})
    assert config.mode == :shadow
    assert config.cooldown_seconds == 600
    assert config.per_hour == 6
  end

  test "invalid config values fall back to defaults instead of crashing" do
    config = Throttle.config(%{"journal_throttle" => %{"mode" => "hax", "ambient_per_hour" => "abc"}})
    assert config.mode == :shadow
    assert config.per_hour == 6

    config2 = Throttle.config(%{"journal_throttle" => %{"ambient_per_hour" => -5, "ambient_type_cooldown_seconds" => 0}})
    assert config2.per_hour == 6
    assert config2.cooldown_seconds == 600
  end

  test "concurrent checks cannot both pass the same type window" do
    configs = enforce(600, 100)
    hero = Ecto.UUID.generate()

    results =
      1..20
      |> Task.async_stream(fn _ -> Throttle.check(hero, "watch_sunset", nil, configs) end)
      |> Enum.map(fn {:ok, {_meta, decision}} -> decision end)

    # окно одно: ровно одна публикация, остальные подавлены
    assert Enum.count(results, &(&1 == :publish)) == 1
    assert Enum.count(results, &(&1 == :suppress)) == 19
  end

  test "snapshot reports state for diagnostics" do
    configs = enforce(600, 2)
    hero = Ecto.UUID.generate()

    Throttle.check(hero, "watch_sunset", nil, configs)
    Throttle.check(hero, "smell_flowers", nil, configs)

    snap = Throttle.snapshot(hero)
    assert snap.hero_id == hero
    assert snap.used_in_hour == 2
    assert Map.has_key?(snap.types, "watch_sunset")
  end
end
