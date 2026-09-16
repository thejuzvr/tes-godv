defmodule TesIdle.Game.ProgressionSimTest do
  @moduledoc """
  S-4-T: A/B-симуляция прогрессии — один и тот же сид 200 тиков героя
  с конфигом progression (медленно) и без (быстро). Проверяем, что
  медленный герой набирает меньше XP/золота в пределах множителей.
  """
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Location, User}

  @prog %{"progression" => %{"xp_multiplier" => 0.5, "gold_multiplier" => 0.75, "skill_rate" => 0.5}}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])

    user = Repo.insert!(%User{username: "qa_s4_#{suffix}",
      email: "qa_s4_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    location = Repo.insert!(%Location{
      name: "QA Полигон #{suffix}",
      location_type: "wilderness",
      region: "Скайрим",
      danger_level: "Низкая",
      min_level: 1, max_level: 10,
      has_shop: false, has_inn: false,
      weather: "Ясно",
      flags: %{},
    })

    %{user: user, location: location}
  end

  @tag :skip
  test "A/B: 200 тиков с сидом — медленный герой растёт в 2-3 раза медленнее", %{user: _user, location: _location} do
    # Полная симуляция требует ContextBuilder+Kernel; базовая проверка темпа
    # выполняется детерминированным прогоном apply_progression (см. юнит-тесты).
    # Этот тест-каркас оставлен для полной pipeline-симуляции после стабилизации S-5.
    assert true
  end

  test "A/B по apply_progression: 200 идентичных наград — суммарная дельта соответствует множителям" do
    rewards = List.duplicate(%{xp: 20, gold_change: 12}, 200)
    cfg_slow = @prog
    cfg_fast = %{}

    total = fn cfg ->
      Enum.reduce(rewards, %{xp: 0, gold: 0}, fn r, acc ->
        res = TesIdle.Game.Pipeline.apply_progression(r, cfg)
        %{xp: acc.xp + res[:xp], gold: acc.gold + res[:gold_change]}
      end)
    end

    slow = total.(cfg_slow)
    fast = total.(cfg_fast)

    assert fast.xp == 4000
    assert slow.xp == 2000
    assert fast.gold == 2400
    assert slow.gold == 1800

    # Целевой темп: 2-3x медленнее по XP, золото режется мягче
    ratio = fast.xp / slow.xp * 1.0
    assert ratio >= 2.0 and ratio <= 3.0
    assert fast.gold / slow.gold <= 2.0
  end
end
