defmodule TesIdle.Schemas.HeroEncounterFoundationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias TesIdle.Repo

  alias TesIdle.Schemas.{
    EncounterClaim,
    EncounterParticipant,
    EventOutbox,
    HeroBlock,
    HeroEncounter,
    HeroRelationship,
    HeroRelationshipSide,
    HeroSocialSetting,
    JournalEntry
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "migration created encounter tables, journal columns, constraints and eligibility index" do
    tables = ~w(
      hero_encounters encounter_claims encounter_participants hero_relationships
      hero_relationship_sides hero_social_settings hero_blocks event_outbox
    )

    for table <- tables do
      assert %{rows: [[^table]]} =
               SQL.query!(Repo, "SELECT to_regclass('public.' || $1)::text", [table])
    end

    assert %{rows: [["encounter_id"], ["perspective_role"], ["template_id"]]} =
             SQL.query!(
               Repo,
               """
               SELECT column_name
               FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'journal_entries'
                 AND column_name = ANY($1)
               ORDER BY column_name
               """,
               [["encounter_id", "perspective_role", "template_id"]]
             )

    indexes = ~w(
      encounter_claims_round_hero_uidx
      encounter_participants_encounter_hero_uidx
      event_outbox_idempotency_uidx
      hero_encounters_idempotency_uidx
      hero_relationships_pair_uidx
      hero_relationship_sides_relationship_hero_uidx
      hero_social_settings_hero_uidx
      journal_entries_encounter_hero_uidx
      heroes_encounter_eligibility_idx
    )

    for index <- indexes do
      assert %{rows: [[^index]]} =
               SQL.query!(Repo, "SELECT to_regclass('public.' || $1)::text", [index])
    end
  end

  test "schemas expose DB-compatible types, timestamp sources and associations" do
    assert HeroEncounter.__schema__(:type, :round) == :integer
    assert HeroEncounter.__schema__(:type, :shared_payload) == :map
    assert HeroEncounter.__schema__(:association, :hero_low).related == TesIdle.Schemas.Hero
    assert HeroEncounter.__schema__(:association, :participants).related == EncounterParticipant

    assert EncounterClaim.__schema__(:type, :claimed_at) == :naive_datetime
    assert HeroRelationship.__schema__(:type, :cooldown_until) == :naive_datetime
    assert HeroRelationship.__schema__(:type, :shared_tags) == {:array, :string}
    assert HeroRelationshipSide.__schema__(:type, :tags) == {:array, :string}
    assert EventOutbox.__schema__(:type, :available_at) == :naive_datetime

    assert JournalEntry.__schema__(:association, :encounter).related == HeroEncounter

    assert JournalEntry.__schema__(:association, :template).related ==
             TesIdle.Schemas.NarrativeTemplate
  end

  test "privacy defaults are conservative and caps remain nullable" do
    settings = %HeroSocialSetting{}

    assert settings.encounter_mode == "live_only"
    assert settings.reveal_name == "encounter"
    assert settings.daily_cap == nil
    assert settings.cooldown_seconds == nil
  end

  test "changesets reject unsafe pair and self-block invariants before DB access" do
    [low, high] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])

    refute HeroEncounter.changeset(%HeroEncounter{}, %{
             hero_low_id: high,
             hero_high_id: low,
             round: 1,
             location_id: Ecto.UUID.generate(),
             kind: "meeting",
             idempotency_key: "encounter:1"
           }).valid?

    refute HeroRelationship.changeset(%HeroRelationship{}, %{
             hero_low_id: low,
             hero_high_id: low
           }).valid?

    refute HeroBlock.changeset(%HeroBlock{}, %{blocker_id: low, blocked_id: low}).valid?
  end
end
