defmodule TesIdle.Game.DeathRespawnTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Location, NarrativeTemplate, User}
  alias TesIdle.Game.Pipeline
  import Ecto.Query

  # P-2: смерть с таймером — мёртвый герой ждёт respawn_at и возрождается
  # в ближайшем городе с 20% HP, поколение +1, запись из БД (death_respawn).

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_dead_#{suffix}",
        email: "qa_dead_#{suffix}@test.gg", password_hash: "x"})

    # города из сида локаций
    cities = Repo.all(from l in Location, where: l.location_type == "city")
    rift = Enum.find(cities, &(&1.name == "Рифтен")) || List.first(cities)
    wind = Enum.find(cities, &(&1.name == "Виндхельм")) || Enum.at(cities, 1)
    whiterun = Enum.find(cities, &(&1.name == "Вайтран")) || List.first(cities)

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "QA-Мертвяк",
        race: "Имперец",
        hero_class: "Warrior",
        level: 5,
        hp: 0,
        max_hp: 100,
        gold: 1000,
        state: "idle",
        location_id: rift.id,
        personality: %{"bravery" => 50, "curiosity" => 50, "greed" => 50, "sociability" => 50,
          "tenacity" => 50, "caution" => 50, "patience" => 50, "dexterity" => 50, "empathy" => 50},
        state_data: Jason.encode!(%{"brain" => %{"generation" => 2}}),
        brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id),
      })

    %{user: user, hero: hero, rift: rift, wind: wind, whiterun: whiterun}
  end

  test "hp<=0 → state dead + death-блок с ближайшим городом и будущим respawn_at",
       %{hero: hero, rift: rift} do
    {:ok, result} = Pipeline.tick(hero.id)

    reloaded = Repo.reload!(hero)
    assert reloaded.state == "dead"
    assert reloaded.hp == 0
    # золото: −10%
    assert reloaded.gold == 900
    assert result.state_to == "dead"

    sd = Jason.decode!(reloaded.state_data)
    assert death = sd["death"]
    assert death["city_id"]
    # Рифтен (813,410): ближайший город к нему — Виндхельм (744,150), но герой
    # УЖЕ в городе Рифтен (dist 0) → город смерти и есть место возрождения
    assert death["city_id"] == rift.id
    {:ok, respawn_at} = NaiveDateTime.from_iso8601(death["respawn_at"])
    assert NaiveDateTime.compare(NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second), respawn_at) == :lt
  end

  test "мёртвый до срока — тихий тик: state не меняется, записей нет", %{hero: hero} do
    Pipeline.tick(hero.id)
    {:ok, result} = Pipeline.tick(hero.id)

    reloaded = Repo.reload!(hero)
    assert reloaded.state == "dead"
    assert result.state_to == "dead"
    assert result.journal_entry == nil
    assert result.narrative == nil
    # золото не списывается второй раз
    assert reloaded.gold == 900
  end

  test "после respawn_at — возрождение: hp 20%, локация ближайший город, generation +1, запись из БД",
       %{hero: hero, rift: rift} do
    # шаблон возрождения (в test-БД narrative-сид не гоняется — вставляем сами)
    Repo.insert!(%NarrativeTemplate{
      template_type: "death_respawn",
      text_template: "{hero_name} приходит в себя в {location}. Поколение {generation}.",
      source: "system", is_active: true})

    Pipeline.tick(hero.id)

    reloaded = Repo.reload!(hero)
    sd = Jason.decode!(reloaded.state_data)
    past = NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second) |> NaiveDateTime.truncate(:second)
    reloaded
    |> Ecto.Changeset.change(state_data: Jason.encode!(Map.put(sd, "death", Map.put(sd["death"], "respawn_at", NaiveDateTime.to_iso8601(past)))))
    |> Repo.update!()

    {:ok, result} = Pipeline.tick(reloaded.id)

    final = Repo.reload!(hero)
    assert final.state == "resting"
    assert final.hp == 20
    # герой умер в Рифтене — возрождение там же (ближайший город dist 0)
    assert final.location_id == rift.id
    assert result.state_to == "resting"

    # death-блок удалён, brain переродился
    fsd = Jason.decode!(final.state_data)
    assert fsd["death"] == nil
    assert fsd["brain"]["generation"] == 3

    # запись в журнале из БД
    entry = Repo.one(from j in TesIdle.Schemas.JournalEntry,
      where: j.hero_id == ^hero.id and j.entry_type == "death_respawn",
      order_by: [desc: j.created_at], limit: 1)
    assert entry
    assert entry.text =~ "приходит в себя в Рифтен"
    assert entry.text =~ "Поколение 3"
    assert entry.text =~ "QA-Мертвяк"
  end

  test "нет шаблона death_respawn — возрождение без записи (честная тишина)", %{hero: hero} do
    Pipeline.tick(hero.id)
    reloaded = Repo.reload!(hero)
    sd = Jason.decode!(reloaded.state_data)
    past = NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second) |> NaiveDateTime.truncate(:second)
    reloaded
    |> Ecto.Changeset.change(state_data: Jason.encode!(Map.put(sd, "death", Map.put(sd["death"], "respawn_at", NaiveDateTime.to_iso8601(past)))))
    |> Repo.update!()

    {:ok, result} = Pipeline.tick(reloaded.id)

    final = Repo.reload!(hero)
    assert final.state == "resting"
    assert result.journal_entry == nil
    assert Repo.one(from j in TesIdle.Schemas.JournalEntry,
      where: j.hero_id == ^hero.id and j.entry_type == "death_respawn") == nil
  end
end
