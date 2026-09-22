defmodule TesIdle.Game.SparksAndOriginsTest do
  use ExUnit.Case, async: false

  alias TesIdle.Game.{Origins, Sparks}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])
    user = Repo.insert!(%User{username: "sp_#{suffix}", email: "sp_#{suffix}@t.gg", password_hash: "x"})

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Искра #{suffix}",
        race: "Норд",
        hero_class: "Воин",
        is_online: true
      })

    %{hero: hero}
  end

  test "daily cap stops a second time spark", %{hero: hero} do
    Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: "spark_time", text: "Искра: time"})
    refute Sparks.allow?(hero, "time", %{})
  end

  test "quest sparks are capped per week, not per day", %{hero: hero} do
    Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: "spark_quest", text: "Искра: quest"})
    assert Sparks.allow?(hero, "quest", %{})
    Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: "spark_quest", text: "Искра: quest"})
    refute Sparks.allow?(hero, "quest", %{})
  end

  test "offline hero never receives the time spark", %{hero: hero} do
    offline = %{hero | is_online: false}
    refute Sparks.time_spark?(offline, %{"soul_sparks" => %{"time_chance" => 1.0}})
  end

  test "origins resolve to their cities and the mage starts with mana" do
    assert Origins.get("mage_student").city == "Солитьюд"
    assert Origins.get("mage_student").mp == 70
    assert Origins.get("acolyte").reputation == 5
    assert Origins.get("gutter").stealth == 8
    assert Origins.resolve(nil) == "beggar"
    assert Origins.resolve("нет такой") == nil
  end
end
