defmodule TesIdle.Game.EncountersTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TesIdle.Game.Encounters.{Matcher, Narrative, Resolver}
  alias TesIdle.Repo

  alias TesIdle.Schemas.{
    EncounterClaim,
    EncounterParticipant,
    EventOutbox,
    Hero,
    HeroBlock,
    HeroEncounter,
    HeroRelationship,
    HeroSocialSetting,
    JournalEntry,
    Location,
    NarrativeTemplate,
    User
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    Repo.delete_all(
      from template in NarrativeTemplate,
        where:
          template.template_type in [
            "hero_encounter_initiator",
            "hero_encounter_counterpart"
          ]
    )

    config = %{
      "activity_ttl_seconds" => 120,
      "allowed_states" => ["exploring", "resting", "socializing", "shopping"],
      "daily_cap" => 10,
      "cooldown_seconds" => 300,
      "familiarity_gain" => 1,
      "fallback_label" => "Попутчик",
      "kind" => "meeting"
    }

    %{config: config, location: Repo.one!(from location in Location, limit: 1)}
  end

  test "deterministic adjacent pairing is disjoint and remains inside each location" do
    candidates =
      for {location, id} <- [
            {"a", "00000000-0000-0000-0000-000000000001"},
            {"a", "00000000-0000-0000-0000-000000000002"},
            {"a", "00000000-0000-0000-0000-000000000003"},
            {"a", "00000000-0000-0000-0000-000000000004"},
            {"a", "00000000-0000-0000-0000-000000000005"},
            {"b", "00000000-0000-0000-0000-000000000006"},
            {"b", "00000000-0000-0000-0000-000000000007"}
          ],
          do: %{id: id, location_id: location}

    pairs = Matcher.pairs(candidates, 42)
    assert pairs == Matcher.pairs(Enum.reverse(candidates), 42)

    ids = Enum.flat_map(pairs, fn {left, right} -> [left.id, right.id] end)
    assert length(ids) == length(Enum.uniq(ids))
    assert length(pairs) == 3
    assert Enum.all?(pairs, fn {left, right} -> left.location_id == right.location_id end)
  end

  test "resolver replay creates one encounter, two perspectives and one relationship increment",
       %{
         config: config,
         location: location
       } do
    insert_templates()
    alpha = insert_hero!(location, "Альфа")
    beta = insert_hero!(location, "Бета")

    assert {:ok, %{created?: true, encounter: encounter}} =
             Resolver.resolve(alpha.id, beta.id, 101, config)

    assert encounter.idempotency_key =~ ~r/^encounter:[0-9a-f]{64}$/
    assert encounter.shared_payload["location_name"] == location.name

    assert {:ok, %{created?: false}} = Resolver.resolve(beta.id, alpha.id, 101, config)

    assert Repo.aggregate(
             from(item in HeroEncounter, where: item.id == ^encounter.id),
             :count
           ) == 1

    assert Repo.aggregate(
             from(item in EncounterClaim, where: item.encounter_id == ^encounter.id),
             :count
           ) == 2

    assert Repo.aggregate(
             from(item in EncounterParticipant, where: item.encounter_id == ^encounter.id),
             :count
           ) == 2

    assert Repo.aggregate(
             from(item in JournalEntry, where: item.encounter_id == ^encounter.id),
             :count
           ) == 2

    assert Repo.aggregate(
             from(item in EventOutbox, where: item.encounter_id == ^encounter.id),
             :count
           ) == 2

    relationship =
      Repo.one!(
        from relationship in HeroRelationship,
          where:
            relationship.hero_low_id in ^[alpha.id, beta.id] and
              relationship.hero_high_id in ^[alpha.id, beta.id]
      )

    assert relationship.encounter_count == 1
    assert relationship.familiarity == 1

    entries =
      Repo.all(
        from entry in JournalEntry,
          where: entry.encounter_id == ^encounter.id,
          order_by: entry.perspective_role
      )

    assert Enum.map(entries, & &1.perspective_role) == ["counterpart", "initiator"]
    assert Enum.any?(entries, &(&1.text == "Бета видит Альфа в #{location.name}."))
    assert Enum.any?(entries, &(&1.text == "Альфа встречает Бета в #{location.name}."))
  end

  test "resolver honestly records encounter without journal when templates are absent", %{
    config: config,
    location: location
  } do
    alpha = insert_hero!(location, "Тихий-А")
    beta = insert_hero!(location, "Тихий-Б")

    assert {:ok, %{created?: true, journal_entries: [], encounter: encounter}} =
             Resolver.resolve(alpha.id, beta.id, 102, config)

    assert Repo.get!(HeroEncounter, encounter.id)

    assert Repo.exists?(
             from relationship in HeroRelationship,
               where:
                 relationship.hero_low_id in ^[alpha.id, beta.id] and
                   relationship.hero_high_id in ^[alpha.id, beta.id]
           )

    refute Repo.exists?(from entry in JournalEntry, where: entry.encounter_id == ^encounter.id)
    refute Repo.exists?(from event in EventOutbox, where: event.encounter_id == ^encounter.id)
  end

  test "resolver rechecks same location, social settings and directional blocks", %{
    config: config,
    location: location
  } do
    alpha = insert_hero!(location, "Проверка-А")
    beta = insert_hero!(location, "Проверка-Б")

    other =
      Repo.one(from loc in Location, where: loc.id != ^location.id, limit: 1) ||
        Repo.insert!(%Location{
          name: "QA-встречи-#{System.unique_integer([:positive])}",
          region: "QA",
          location_type: "city"
        })

    Repo.update_all(from(hero in Hero, where: hero.id == ^beta.id), set: [location_id: other.id])
    assert {:error, :different_location} = Resolver.resolve(alpha.id, beta.id, 201, config)

    Repo.update_all(from(hero in Hero, where: hero.id == ^beta.id),
      set: [location_id: location.id]
    )

    Repo.insert!(%HeroSocialSetting{
      hero_id: beta.id,
      encounter_mode: "disabled",
      reveal_name: "encounter"
    })

    assert {:error, :ineligible} = Resolver.resolve(alpha.id, beta.id, 202, config)

    Repo.delete_all(from setting in HeroSocialSetting, where: setting.hero_id == ^beta.id)
    Repo.insert!(%HeroBlock{blocker_id: beta.id, blocked_id: alpha.id})
    assert {:error, :blocked} = Resolver.resolve(alpha.id, beta.id, 203, config)

    refute Repo.exists?(
             from encounter in HeroEncounter,
               where:
                 encounter.hero_low_id in ^[alpha.id, beta.id] and
                   encounter.hero_high_id in ^[alpha.id, beta.id]
           )
  end

  test "matcher and resolver allow async mode without online freshness", %{
    config: config,
    location: location
  } do
    alpha = insert_hero!(location, "Асинхронный-А")
    beta = insert_hero!(location, "Асинхронный-Б")

    Repo.update_all(
      from(hero in Hero, where: hero.id in ^[alpha.id, beta.id]),
      set: [is_online: false, last_activity: DateTime.add(DateTime.utc_now(), -86_400, :second)]
    )

    for hero <- [alpha, beta] do
      Repo.insert!(%HeroSocialSetting{
        hero_id: hero.id,
        encounter_mode: "async",
        reveal_name: "encounter"
      })
    end

    candidate_ids =
      config
      |> Matcher.candidates(DateTime.utc_now())
      |> Enum.map(& &1.id)

    assert alpha.id in candidate_ids
    assert beta.id in candidate_ids

    assert {:ok, %{created?: true}} = Resolver.resolve(alpha.id, beta.id, 204, config)
  end

  test "idempotency identity includes location and canonicalizes the pair" do
    low = "00000000-0000-0000-0000-000000000001"
    high = "00000000-0000-0000-0000-000000000002"
    location_a = "10000000-0000-0000-0000-000000000001"
    location_b = "10000000-0000-0000-0000-000000000002"

    key_a = Resolver.idempotency_key(205, location_a, low, high, "meeting")
    key_reversed = Resolver.idempotency_key(205, location_a, high, low, "meeting")
    key_b = Resolver.idempotency_key(205, location_b, low, high, "meeting")

    assert key_a == key_reversed
    refute key_a == key_b
    assert key_a =~ ~r/^encounter:[0-9a-f]{64}$/
  end

  test "narrative renderer rejects generic or missing variables" do
    safe = %{
      hero_name: "А",
      other_hero_name: "Б",
      location_name: "Город",
      encounter_kind: "meeting"
    }

    assert {:ok, "А встретил Б."} =
             Narrative.render("{hero_name} встретил {other_hero_name}.", safe)

    assert {:error, :unsafe_or_missing_variable} =
             Narrative.render("{hero_name}: {gold}", Map.put(safe, :gold, "999"))
  end

  test "encounter workers are disabled in test application config" do
    refute Application.get_env(:tes_idle, :encounter_worker_enabled, true)
    refute Application.get_env(:tes_idle, :outbox_dispatcher_enabled, true)
    assert Process.whereis(TesIdle.Worker.EncounterWorker) == nil
    assert Process.whereis(TesIdle.Worker.OutboxDispatcher) == nil
  end

  defp insert_templates do
    Repo.insert!(%NarrativeTemplate{
      template_type: "hero_encounter_initiator",
      text_template: "{hero_name} встречает {other_hero_name} в {location_name}.",
      source: "system",
      is_active: true
    })

    Repo.insert!(%NarrativeTemplate{
      template_type: "hero_encounter_counterpart",
      text_template: "{hero_name} видит {other_hero_name} в {location_name}.",
      source: "system",
      is_active: true
    })
  end

  defp insert_hero!(location, name) do
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "encounter_#{suffix}",
        email: "encounter_#{suffix}@test.gg",
        password_hash: "x"
      })

    Repo.insert!(%Hero{
      user_id: user.id,
      location_id: location.id,
      name: name,
      race: "Норд",
      hero_class: "Warrior",
      state: "exploring",
      is_online: true,
      last_activity: DateTime.utc_now() |> DateTime.truncate(:second),
      brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id)
    })
  end
end
