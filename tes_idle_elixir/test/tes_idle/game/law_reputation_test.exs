defmodule TesIdle.Game.LawReputationTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Game.Law
  alias TesIdle.Schemas.{User, Hero, Location, Reputation, JournalEntry}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_rep_#{suffix}",
        email: "qa_rep_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    location =
      Repo.insert!(%Location{name: "QA Репутация #{suffix}", location_type: "village",
        region: "Скайрим", danger_level: "Низкая", min_level: 1, max_level: 10,
        has_shop: false, has_inn: false, weather: "Ясно", flags: %{}})

    hero =
      Repo.insert!(%Hero{user_id: user.id, name: "QA Дипломат", race: "Nord", hero_class: "Warrior",
        level: 1, location_id: location.id, brain_hash: "x", personality: %{}, skills: %{},
        state_data: "{}"})

    %{hero: hero, user: user}
  end

  @configs %{"law" => %{"reputation" => %{"quest_complete" => 5, "monster_kill" => 1, "crime" => 10}}}

  test "rep_level: пороги уровней", %{hero: _hero} do
    cfg = Law.rep_cfg(%{})
    assert Law.rep_level(-60, cfg) == "hostile"
    assert Law.rep_level(-10, cfg) == "unfriendly"
    assert Law.rep_level(0, cfg) == "neutral"
    assert Law.rep_level(30, cfg) == "friendly"
    assert Law.rep_level(80, cfg) == "allied"
  end

  test "adjust_reputation: создаёт строку с нуля, журнал при смене уровня", %{hero: hero} do
    res = Law.adjust_reputation(hero.id, "Империя", 30, @configs, hero.name)
    assert res.value == 30
    assert res.level == "friendly"
    assert res.changed? == true

    entry = Repo.one!(from j in JournalEntry, where: j.hero_id == ^hero.id and j.entry_type == "reputation_change")
    assert entry.text =~ "Империя"
    assert entry.text =~ "дружелюбно"

    # Рост внутри уровня — без журнала
    res2 = Law.adjust_reputation(hero.id, "Империя", 5, @configs, hero.name)
    assert res2.value == 35
    assert res2.changed? == false
    assert Repo.aggregate(from(j in JournalEntry, where: j.hero_id == ^hero.id and j.entry_type == "reputation_change"), :count) == 1
  end

  test "adjust_reputation: clamp на границах ±100", %{hero: hero} do
    Law.adjust_reputation(hero.id, "Братья Бури", -150, @configs, hero.name)
    rep = Repo.one!(from r in Reputation, where: r.hero_id == ^hero.id and r.faction == "Братья Бури")
    assert rep.value == -100
    assert rep.level == "hostile"

    Law.adjust_reputation(hero.id, "Братья Бури", 250, @configs, hero.name)
    rep2 = Repo.reload!(rep)
    assert rep2.value == 100
    assert rep2.level == "allied"
  end

  test "reputation_hit: штраф с учётом множителя crime → падение уровня", %{hero: hero} do
    ctx = %{
      hero: hero,
      configs: @configs,
      location: Repo.reload!(hero).location && Repo.one!(from l in Location, limit: 1),
      location_type: "village",
      hour: 12.0,
      weather: "clear",
      world: %{},
      personality: %{},
    }

    # Сперва поднимем до friendly, потом преступление должно уронить
    Law.adjust_reputation(hero.id, "Империя", 30, @configs, hero.name)

    # witness_roll не нужен — reputation_hit вызывается напрямую, как из on_crime
    Law.reputation_hit(ctx, %{"rep_loss" => [60, 60]})

    rep = Repo.one!(from r in Reputation, where: r.hero_id == ^hero.id and r.faction == "Империя")
    assert rep.value < 30
  end
end
