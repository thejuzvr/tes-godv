defmodule TesIdle.Game.Encounters.Resolver do
  @moduledoc """
  Transactional, idempotent resolution of one proposed hero pair.

  Both hero rows are locked in UUID order. Every mutable eligibility condition is
  then checked again before encounter, relationship, journal and outbox rows are
  committed together.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias TesIdle.Game.Encounters.{Narrative, PublicParticipant}
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
    Location
  }

  @spec resolve(Ecto.UUID.t(), Ecto.UUID.t(), integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def resolve(hero_a_id, hero_b_id, round, config) when hero_a_id != hero_b_id do
    {low_id, high_id} = ordered(hero_a_id, hero_b_id)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Multi.new()
    |> Multi.run(:heroes, fn repo, _ -> lock_heroes(repo, low_id, high_id) end)
    |> Multi.run(:resolved, fn repo, %{heroes: heroes} ->
      # Replay lookup intentionally precedes mutable eligibility checks. A retry of
      # an already committed round remains successful even if a hero moved or its
      # settings changed after that encounter.
      existing = existing_encounter(repo, low_id, high_id, round, config["kind"])

      if existing do
        {:ok, %{encounter: existing, created?: false, journal_entries: []}}
      else
        with {:ok, context} <-
               validate_context(repo, heroes, low_id, high_id, hero_a_id, config, now) do
          idempotency_key =
            idempotency_key(round, context.location.id, low_id, high_id, config["kind"])

          create_all(repo, context, round, config, now, idempotency_key)
        end
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{resolved: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def resolve(id, id, _round, _config), do: {:error, :same_hero}

  defp existing_encounter(repo, low_id, high_id, round, kind) do
    repo.one(
      from encounter in HeroEncounter,
        where:
          encounter.hero_low_id == ^low_id and encounter.hero_high_id == ^high_id and
            encounter.round == ^round and encounter.kind == ^kind,
        order_by: [asc: encounter.created_at],
        limit: 1
    )
  end

  defp lock_heroes(repo, low_id, high_id) do
    case repo.all(
           from hero in Hero,
             where: hero.id in ^[low_id, high_id],
             order_by: [asc: hero.id],
             lock: "FOR UPDATE"
         ) do
      [low, high] -> {:ok, [low, high]}
      _ -> {:error, :not_found}
    end
  end

  defp validate_context(repo, [low, high], low_id, high_id, initiator_id, config, now) do
    settings =
      repo.all(from setting in HeroSocialSetting, where: setting.hero_id in ^[low_id, high_id])
      |> Map.new(&{&1.hero_id, &1})

    with true <-
           (low.location_id == high.location_id and not is_nil(low.location_id)) ||
             :different_location,
         :ok <- eligible(low, Map.get(settings, low.id), config, now),
         :ok <- eligible(high, Map.get(settings, high.id), config, now),
         :ok <- if(blocked?(repo, low_id, high_id), do: :blocked, else: :ok),
         :ok <- under_daily_cap(repo, low, Map.get(settings, low.id), config, now),
         :ok <- under_daily_cap(repo, high, Map.get(settings, high.id), config, now),
         :ok <- outside_cooldown(repo, low_id, high_id, now),
         %Location{} = location <- repo.get(Location, low.location_id) do
      {initiator, counterpart} =
        if low.id == initiator_id, do: {low, high}, else: {high, low}

      {:ok,
       %{
         low: low,
         high: high,
         initiator: initiator,
         counterpart: counterpart,
         settings: settings,
         location: location
       }}
    else
      reason when is_atom(reason) -> {:error, reason}
      _ -> {:error, :ineligible}
    end
  end

  defp eligible(hero, settings, config, now) do
    mode = if settings, do: settings.encounter_mode, else: "live_only"

    fresh_after =
      now
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-config["activity_ttl_seconds"], :second)

    state_allowed? = hero.state in config["allowed_states"]

    live? =
      hero.is_online == true and not is_nil(hero.last_activity) and
        DateTime.compare(hero.last_activity, fresh_after) != :lt

    cond do
      mode == "disabled" -> :ineligible
      not state_allowed? -> :ineligible
      mode == "async" -> :ok
      mode == "live_only" and live? -> :ok
      true -> :ineligible
    end
  end

  defp blocked?(repo, low_id, high_id) do
    repo.exists?(
      from block in HeroBlock,
        where:
          (block.blocker_id == ^low_id and block.blocked_id == ^high_id) or
            (block.blocker_id == ^high_id and block.blocked_id == ^low_id)
    )
  end

  defp under_daily_cap(repo, hero, settings, config, now) do
    cap =
      if settings && not is_nil(settings.daily_cap),
        do: settings.daily_cap,
        else: config["daily_cap"]

    day_start = now |> NaiveDateTime.to_date() |> NaiveDateTime.new!(~T[00:00:00])

    count =
      repo.one(
        from claim in EncounterClaim,
          where: claim.hero_id == ^hero.id and claim.claimed_at >= ^day_start,
          select: count(claim.id)
      )

    if count < cap, do: :ok, else: :daily_cap
  end

  defp outside_cooldown(repo, low_id, high_id, now) do
    relationship =
      repo.one(
        from relationship in HeroRelationship,
          where: relationship.hero_low_id == ^low_id and relationship.hero_high_id == ^high_id,
          lock: "FOR UPDATE"
      )

    case relationship do
      %{cooldown_until: until} when not is_nil(until) ->
        if NaiveDateTime.compare(until, now) == :gt, do: :cooldown, else: :ok

      _ ->
        :ok
    end
  end

  defp create_all(repo, context, round, config, now, idempotency_key) do
    %{low: low, high: high, location: location} = context
    kind = config["kind"]

    encounter_changeset =
      HeroEncounter.changeset(%HeroEncounter{}, %{
        hero_low_id: low.id,
        hero_high_id: high.id,
        round: round,
        location_id: location.id,
        kind: kind,
        status: "resolved",
        shared_payload: %{"location_name" => location.name, "kind" => kind},
        idempotency_key: idempotency_key
      })

    with {:ok, encounter} <- repo.insert(encounter_changeset),
         :ok <- insert_claims(repo, [low, high], encounter.id, round, now) do
      finish_creation(repo, context, encounter, config, now, idempotency_key)
    end
  end

  defp finish_creation(repo, context, encounter, config, now, idempotency_key) do
    %{
      low: low,
      high: high,
      initiator: initiator,
      counterpart: counterpart,
      settings: settings,
      location: location
    } = context

    kind = config["kind"]

    initiator_public =
      PublicParticipant.from_hero(
        initiator,
        Map.get(settings, initiator.id),
        config["fallback_label"]
      )

    counterpart_public =
      PublicParticipant.from_hero(
        counterpart,
        Map.get(settings, counterpart.id),
        config["fallback_label"]
      )

    participants = [
      {initiator, "initiator", initiator_public, counterpart_public},
      {counterpart, "counterpart", counterpart_public, initiator_public}
    ]

    for {hero, role, _self, counterpart} <- participants do
      %EncounterParticipant{}
      |> EncounterParticipant.changeset(%{
        encounter_id: encounter.id,
        hero_id: hero.id,
        role: role,
        private_payload: %{"counterpart_label" => counterpart.label}
      })
      |> repo.insert!()
    end

    relationship = upsert_relationship(repo, low.id, high.id, settings, config, now)

    journal_entries =
      participants
      |> Enum.map(fn {hero, role, self, counterpart} ->
        context = %{
          hero_name: self.label,
          other_hero_name: counterpart.label,
          location_name: location.name,
          encounter_kind: kind
        }

        case Narrative.build(role, context, idempotency_key <> ":" <> role) do
          nil -> nil
          narrative -> insert_journal_and_outbox(repo, hero, encounter, role, location, narrative)
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok,
     %{
       encounter: encounter,
       relationship: relationship,
       created?: true,
       journal_entries: journal_entries
     }}
  end

  defp insert_claims(repo, heroes, encounter_id, round, now) do
    rows =
      Enum.map(heroes, fn hero ->
        %{
          id: Ecto.UUID.generate(),
          round: round,
          hero_id: hero.id,
          encounter_id: encounter_id,
          claimed_at: now
        }
      end)

    case repo.insert_all(EncounterClaim, rows, on_conflict: :nothing) do
      {2, _} -> :ok
      _ -> {:error, :already_claimed}
    end
  end

  defp upsert_relationship(repo, low_id, high_id, settings, config, now) do
    cooldown_seconds =
      [low_id, high_id]
      |> Enum.map(fn hero_id ->
        case Map.get(settings, hero_id) do
          %{cooldown_seconds: seconds} when is_integer(seconds) -> seconds
          _ -> config["cooldown_seconds"]
        end
      end)
      |> Enum.max()

    cooldown = NaiveDateTime.add(now, cooldown_seconds, :second)

    case repo.one(
           from relationship in HeroRelationship,
             where: relationship.hero_low_id == ^low_id and relationship.hero_high_id == ^high_id,
             lock: "FOR UPDATE"
         ) do
      nil ->
        %HeroRelationship{}
        |> HeroRelationship.changeset(%{
          hero_low_id: low_id,
          hero_high_id: high_id,
          familiarity: config["familiarity_gain"],
          encounter_count: 1,
          cooldown_until: cooldown
        })
        |> repo.insert!()

      relationship ->
        relationship
        |> HeroRelationship.changeset(%{
          familiarity: relationship.familiarity + config["familiarity_gain"],
          encounter_count: relationship.encounter_count + 1,
          cooldown_until: cooldown
        })
        |> repo.update!()
    end
  end

  defp insert_journal_and_outbox(repo, hero, encounter, role, location, narrative) do
    entry =
      %JournalEntry{}
      |> JournalEntry.changeset(%{
        hero_id: hero.id,
        encounter_id: encounter.id,
        template_id: narrative.template_id,
        perspective_role: role,
        entry_type: "hero_encounter_#{role}",
        text: narrative.text,
        location_name: location.name
      })
      |> repo.insert!()

    payload = %{
      "hero_id" => hero.id,
      "journal_entry" => %{
        "id" => entry.id,
        "entry_type" => entry.entry_type,
        "text" => entry.text,
        "xp_gained" => entry.xp_gained,
        "gold_gained" => entry.gold_gained,
        "location_name" => entry.location_name,
        "chapter" => entry.chapter,
        "chapter_title" => entry.chapter_title,
        "motive" => entry.motive,
        "created_at" => NaiveDateTime.to_iso8601(entry.created_at)
      }
    }

    %EventOutbox{}
    |> EventOutbox.changeset(%{
      encounter_id: encounter.id,
      event_type: "journal_entry",
      payload: payload,
      idempotency_key: "#{encounter.id}:#{hero.id}:journal_entry",
      available_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    })
    |> repo.insert!()

    entry
  end

  @doc "Builds the stable bounded key for a round, location, kind and canonical pair."
  def idempotency_key(round, location_id, hero_a_id, hero_b_id, kind) do
    {low_id, high_id} = ordered(hero_a_id, hero_b_id)

    # The digest keeps the full composite identity below VARCHAR(128) without
    # exposing raw identifiers in operational logs.
    digest =
      :crypto.hash(:sha256, Enum.join([round, location_id, kind, low_id, high_id], ":"))
      |> Base.encode16(case: :lower)

    "encounter:#{digest}"
  end

  defp ordered(a, b) when a < b, do: {a, b}
  defp ordered(a, b), do: {b, a}
end
