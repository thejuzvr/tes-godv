defmodule TesIdle.HeroSocial do
  @moduledoc "Privacy-safe read/update boundary for hero social data."

  import Ecto.Query
  import Ecto.Changeset

  alias TesIdle.Repo

  alias TesIdle.Schemas.{
    EncounterParticipant,
    GameConfig,
    Hero,
    HeroBlock,
    HeroEncounter,
    HeroRelationship,
    HeroRelationshipSide,
    HeroSocialSetting
  }

  @default_config %{
    "default_daily_cap" => 3,
    "max_daily_cap" => 20,
    "default_cooldown_seconds" => 3600
  }
  @encounter_modes ~w(disabled live_only async)
  @reveal_names ~w(nobody encounter guild public)
  @default_label "Незнакомец"

  def hero_for_user(user_id), do: Repo.get_by(Hero, user_id: user_id)

  def list_encounters(hero_id, params \\ %{}) do
    limit = bounded_limit(params["limit"])
    page_number = bounded_page(params["page"])
    offset = (page_number - 1) * limit
    before = parse_before(params["before"])

    query =
      from e in HeroEncounter,
        join: p in EncounterParticipant,
        on: p.encounter_id == e.id and p.hero_id == ^hero_id,
        where: e.hero_low_id == ^hero_id or e.hero_high_id == ^hero_id,
        order_by: [desc: e.created_at, desc: e.id],
        offset: ^offset,
        limit: ^(limit + 1),
        select: %{
          id: e.id,
          round: e.round,
          kind: e.kind,
          status: e.status,
          location_id: e.location_id,
          created_at: e.created_at,
          role: p.role,
          participant_payload: p.private_payload
        }

    query =
      if before do
        from [e, _p] in query, where: e.created_at < ^before
      else
        query
      end

    rows = Repo.all(query)
    {page, rest} = Enum.split(rows, limit)

    %{
      encounters: Enum.map(page, &public_encounter/1),
      page: page_number,
      limit: limit,
      has_more: rest != [],
      next_before: if(rest == [], do: nil, else: page |> List.last() |> Map.fetch!(:created_at))
    }
  end

  def list_relationships(hero_id) do
    Repo.all(
      from r in HeroRelationship,
        join: side in HeroRelationshipSide,
        on: side.relationship_id == r.id and side.hero_id == ^hero_id,
        where: r.hero_low_id == ^hero_id or r.hero_high_id == ^hero_id,
        order_by: [desc: r.updated_at, desc: r.id],
        select: %{
          id: r.id,
          hero_low_id: r.hero_low_id,
          hero_high_id: r.hero_high_id,
          familiarity: r.familiarity,
          encounter_count: r.encounter_count,
          cooldown_until: r.cooldown_until,
          shared_tags: r.shared_tags,
          affinity: side.affinity,
          tags: side.tags,
          created_at: r.created_at,
          updated_at: r.updated_at
        }
    )
    |> Enum.map(&public_relationship(&1, hero_id))
  end

  def get_settings(hero_id) do
    config = config()

    case Repo.get_by(HeroSocialSetting, hero_id: hero_id) do
      nil -> default_settings(config)
      settings -> public_settings(settings, config)
    end
  end

  def update_settings(hero_id, attrs) do
    config = config()

    settings =
      Repo.get_by(HeroSocialSetting, hero_id: hero_id) || %HeroSocialSetting{hero_id: hero_id}

    allowed = Map.take(attrs, ["encounter_mode", "reveal_name", "daily_cap"])

    changeset =
      settings
      |> HeroSocialSetting.changeset(Map.put(allowed, "hero_id", hero_id))
      |> validate_inclusion(:encounter_mode, @encounter_modes)
      |> validate_inclusion(:reveal_name, @reveal_names)
      |> validate_number(:daily_cap,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: config["max_daily_cap"]
      )

    case Repo.insert_or_update(changeset) do
      {:ok, saved} -> {:ok, public_settings(saved, config)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def block(hero_id, blocked_id) do
    with :ok <- valid_target(hero_id, blocked_id) do
      %HeroBlock{}
      |> HeroBlock.changeset(%{blocker_id: hero_id, blocked_id: blocked_id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:blocker_id, :blocked_id])
      |> case do
        {:ok, _} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def unblock(hero_id, blocked_id) do
    case Ecto.UUID.cast(blocked_id) do
      {:ok, id} ->
        {_, _} =
          Repo.delete_all(
            from b in HeroBlock,
              where: b.blocker_id == ^hero_id and b.blocked_id == ^id
          )

        :ok

      :error ->
        {:error, :not_found}
    end
  end

  defp valid_target(hero_id, hero_id), do: {:error, :invalid_target}

  defp valid_target(_hero_id, blocked_id) do
    case Ecto.UUID.cast(blocked_id) do
      {:ok, id} ->
        if Repo.exists?(from h in Hero, where: h.id == ^id),
          do: :ok,
          else: {:error, :not_found}

      :error ->
        {:error, :not_found}
    end
  end

  defp public_relationship(row, hero_id) do
    row
    |> Map.put(
      :counterpart_id,
      if(row.hero_low_id == hero_id, do: row.hero_high_id, else: row.hero_low_id)
    )
    |> Map.drop([:hero_low_id, :hero_high_id])
  end

  defp public_encounter(row) do
    %{
      id: row.id,
      round: row.round,
      kind: row.kind,
      status: row.status,
      location_id: row.location_id,
      created_at: row.created_at,
      role: row.role,
      counterpart_label: safe_label(row.participant_payload)
    }
  end

  defp safe_label(payload) when is_map(payload) do
    label = Map.get(payload, "counterpart_label") || Map.get(payload, "label")

    if is_binary(label) do
      label
      |> String.trim()
      |> String.slice(0, 80)
      |> case do
        "" -> @default_label
        value -> value
      end
    else
      @default_label
    end
  end

  defp safe_label(_), do: @default_label

  defp public_settings(settings, config) do
    %{
      encounter_mode: settings.encounter_mode || "live_only",
      reveal_name: settings.reveal_name || "encounter",
      daily_cap: settings.daily_cap || config["default_daily_cap"],
      cooldown_seconds: settings.cooldown_seconds || config["default_cooldown_seconds"],
      limits: %{daily_cap_max: config["max_daily_cap"]}
    }
  end

  defp default_settings(config) do
    %{
      encounter_mode: "live_only",
      reveal_name: "encounter",
      daily_cap: config["default_daily_cap"],
      cooldown_seconds: config["default_cooldown_seconds"],
      limits: %{daily_cap_max: config["max_daily_cap"]}
    }
  end

  defp config do
    case Repo.get_by(GameConfig, key: "hero_social") do
      nil -> @default_config
      %{value: value} -> merge_config(value)
    end
  end

  defp merge_config(value) do
    with {:ok, decoded} when is_map(decoded) <- Jason.decode(value) do
      @default_config
      |> Map.merge(Map.take(decoded, Map.keys(@default_config)))
      |> normalize_config()
    else
      _ -> @default_config
    end
  end

  defp normalize_config(config) do
    max_cap = positive_integer(config["max_daily_cap"], @default_config["max_daily_cap"])

    %{
      "max_daily_cap" => max_cap,
      "default_daily_cap" =>
        config["default_daily_cap"]
        |> non_negative_integer(@default_config["default_daily_cap"])
        |> min(max_cap),
      "default_cooldown_seconds" =>
        non_negative_integer(
          config["default_cooldown_seconds"],
          @default_config["default_cooldown_seconds"]
        )
    }
  end

  defp bounded_limit(value) do
    value
    |> parse_integer(20)
    |> max(1)
    |> min(100)
  end

  defp bounded_page(value) do
    value
    |> parse_integer(1)
    |> max(1)
  end

  defp parse_before(nil), do: nil

  defp parse_before(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp parse_before(_), do: nil

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> default
    end
  end

  defp parse_integer(_, default), do: default
  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_, default), do: default
  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_, default), do: default
end
