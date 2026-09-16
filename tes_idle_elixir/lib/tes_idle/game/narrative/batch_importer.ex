defmodule TesIdle.Game.Narrative.BatchImporter do
  @moduledoc """
  Safe, deterministic validation and transactional import for admin narrative JSON batches.

  This module deliberately does not call the template engine's random/database-backed
  fragment sources. Previews use only the bounded sample values below.
  """

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate

  @max_templates 200
  @max_text_bytes 4_000
  @near_duplicate_min_prefix_chars 80
  @near_duplicate_min_similarity 0.85
  # These are the only provenance values understood by the narrative lifecycle.
  @sources ~w(system community llm)
  @policies ~w(pending active_system)

  @base_vars ~w(hero_name location_name location_type god_name mood)
  @base_samples %{
    "hero_name" => "Хальвар",
    "location_name" => "Ривервуд",
    "location_type" => "village",
    "god_name" => "Талос",
    "mood" => "72"
  }

  @vars_by_type %{
    "explore" => ~w(terrain discovery landmark),
    "combat_start" => ~w(monster_name landmark),
    "combat_result" => ~w(monster_name xp gold rounds _combat_verbs),
    "combat_defeat" => ~w(monster_name),
    "shop" => ~w(item_name gold_spent npc_name shop_item),
    "social" => ~w(gamble_result npc_name rumor tavern),
    "travel" => ~w(destination),
    "loot" => ~w(loot_text),
    "fishing" => ~w(fish_name),
    "gather" => ~w(herb_name),
    "collect_herbs" => ~w(herb_name),
    "steal" => ~w(stolen_gold witness_name bounty_gold fine_gold witness_outcome),
    "break_in" => ~w(trap_hp break_in_ok break_in_trap break_in_noise break_in_fail),
    "jail" => ~w(jail_reason jail_ticks jail_escaped jail_escape_fail jail_free),
    "pet_care" => ~w(pet_name pet_species pet_care_kind pet_loyalty),
    "mining" => ~w(ore_name),
    "death_respawn" => ~w(location generation),
    "dream" => ~w(location_name),
    "world_news" => ~w(event),
    "construction_donation" => ~w(hero_name amount project_name),
    "gate_donation" => ~w(hero_name amount location_name),
    "gate_closed" => ~w(location_name),
    "enhance_success" => ~w(hero_name item_name level price),
    "guild_shop_purchase" => ~w(hero_name item_name price),
    "guild_founded" => ~w(guild_name emblem leader),
    "guild_levelup" => ~w(guild_name emblem level),
    "guild_feast" => ~w(guild_name emblem),
    "hero_encounter_initiator" => ~w(hero_name other_hero_name location_name encounter_kind),
    "hero_encounter_counterpart" => ~w(hero_name other_hero_name location_name encounter_kind)
  }

  @samples Map.merge(@base_samples, %{
             "terrain" => "густому лесу",
             "discovery" => "старую карту",
             "landmark" => "старого дуба",
             "monster_name" => "серый волк",
             "xp" => "25",
             "gold" => "12",
             "rounds" => "3",
             "_combat_verbs" => "сверкнул",
             "item_name" => "стальной меч",
             "gold_spent" => "10",
             "npc_name" => "Олаф",
             "shop_item" => "стальной наплечник",
             "gamble_result" => "выиграл немного золота",
             "rumor" => "на востоке видели дракона",
             "tavern" => "«Пьяный дракон»",
             "destination" => "Вайтран",
             "loot_text" => "немного золота",
             "fish_name" => "ловкую форель",
             "herb_name" => "пучок лаванды",
             "stolen_gold" => "15",
             "witness_name" => "Олаф Двужильный",
             "bounty_gold" => "25",
             "fine_gold" => "30",
             "witness_outcome" => "clean",
             "trap_hp" => "10",
             "break_in_ok" => "false",
             "break_in_trap" => "false",
             "break_in_noise" => "false",
             "break_in_fail" => "false",
             "jail_reason" => "кражу",
             "jail_ticks" => "5",
             "jail_escaped" => "false",
             "jail_escape_fail" => "false",
             "jail_free" => "false",
             "pet_name" => "Мурчелло",
             "pet_species" => "кот",
             "pet_care_kind" => "покормил",
             "pet_loyalty" => "70",
             "ore_name" => "железная жила",
             "location" => "Вайтран",
             "generation" => "3",
             "event" => "ветер переменился",
             "amount" => "50",
             "project_name" => "Часовня Девяти",
             "level" => "2",
             "price" => "50",
             "guild_name" => "Соратники",
             "emblem" => "🛡️",
             "leader" => "Хальвар",
             "other_hero_name" => "Сигрун",
             "encounter_kind" => "дружеская"
           })

  @doc "Returns the explicit allowlist maintained from renderer/action sources."
  def supported_types do
    event_types = TesIdle.Game.Narrative.NarrativeEvent.all() |> Enum.map(& &1.name)

    (Map.keys(@vars_by_type) ++
       event_types ++
       ~w(rest thought death god_encourage god_punish god_heal god_direct god_quest god_weather equip remember_defeat find_loot))
    |> MapSet.new()
  end

  # Admin UI also accepts a bare JSON array for convenient file imports.
  def validate(templates) when is_list(templates), do: validate(%{"templates" => templates})

  def validate(payload) when is_map(payload) do
    with {:ok, templates} <- templates(payload),
         {:ok, policy} <- policy(payload) do
      rows =
        templates
        |> Enum.with_index()
        |> Enum.map(fn {row, index} -> validate_row(row, index, policy) end)

      rows = mark_batch_duplicates(rows)
      rows = mark_batch_near_duplicates(rows)
      rows = mark_existing_duplicates(rows)

      %{
        valid: Enum.all?(rows, & &1.valid),
        activation_policy: policy,
        rows: rows,
        summary: %{
          total: length(rows),
          valid: Enum.count(rows, & &1.valid),
          invalid: Enum.count(rows, &(not &1.valid))
        }
      }
    else
      {:error, error} ->
        %{
          valid: false,
          activation_policy: "pending",
          rows: [],
          errors: [error],
          summary: %{total: 0, valid: 0, invalid: 0}
        }
    end
  end

  def validate(_),
    do: %{
      valid: false,
      activation_policy: "pending",
      rows: [],
      errors: ["JSON object expected"],
      summary: %{total: 0, valid: 0, invalid: 0}
    }

  @doc "Imports only an entirely valid batch; no partial inserts are ever committed."
  def import(payload) do
    result = validate(payload)

    if result.valid do
      attrs =
        Enum.map(result.rows, fn row ->
          %{row.normalized | variables: Jason.encode!(row.normalized.variables)}
        end)

      Repo.transaction(fn ->
        duplicate_keys = existing_keys(Enum.map(attrs, &{&1.template_type, &1.text_template}))

        if MapSet.size(duplicate_keys) > 0 do
          Repo.rollback({:duplicate_in_database, MapSet.to_list(duplicate_keys)})
        end

        templates =
          Enum.map(attrs, fn attr ->
            Repo.insert!(%NarrativeTemplate{} |> NarrativeTemplate.changeset(attr))
          end)

        %{
          imported: length(templates),
          ids: Enum.map(templates, & &1.id),
          activation_policy: result.activation_policy
        }
      end)
      |> case do
        {:ok, response} ->
          {:ok, response}

        {:error, {:duplicate_in_database, keys}} ->
          {:error,
           Map.merge(result, %{
             valid: false,
             errors: ["A template was added concurrently"],
             duplicate_keys: keys
           })}

        {:error, reason} ->
          {:error,
           Map.merge(result, %{
             valid: false,
             errors: ["Import transaction failed: #{inspect(reason)}"]
           })}
      end
    else
      {:error, result}
    end
  end

  defp templates(%{"templates" => templates})
       when is_list(templates) and length(templates) in 1..@max_templates, do: {:ok, templates}

  defp templates(%{"templates" => templates}) when is_list(templates),
    do: {:error, "templates must contain 1..#{@max_templates} rows"}

  defp templates(_), do: {:error, "templates must be an array"}

  defp policy(payload) do
    value = payload["activation_policy"] || payload["mode"] || "pending"

    if value in @policies,
      do: {:ok, value},
      else: {:error, "activation_policy must be pending or active_system"}
  end

  defp validate_row(row, index, policy) when is_map(row) do
    type = row["template_type"]
    text = row["text_template"] |> normalize_text()
    source = row["source"] || "community"
    variables = placeholders(text)
    malformed_placeholders = malformed_placeholders(text)

    allowed = MapSet.new(@base_vars ++ allowed_vars(type))

    errors = []

    errors =
      if is_binary(type) and MapSet.member?(supported_types(), type),
        do: errors,
        else: ["Unsupported template_type" | errors]

    errors = if source in @sources, do: errors, else: ["Unsupported source" | errors]

    errors =
      if is_binary(text) and text != "",
        do: errors,
        else: ["text_template must not be empty" | errors]

    errors =
      if is_binary(text) and byte_size(text) <= @max_text_bytes,
        do: errors,
        else: ["text_template exceeds #{@max_text_bytes} bytes" | errors]

    errors =
      if Enum.all?(variables, &MapSet.member?(allowed, &1)),
        do: errors,
        else: [
          "Unknown or unrenderable variables: #{Enum.join(Enum.reject(variables, &MapSet.member?(allowed, &1)), ", ")}"
          | errors
        ]

    errors =
      if malformed_placeholders == [], do: errors, else: ["Malformed placeholder syntax" | errors]

    {declared, variable_errors} = normalized_declared_variables(row["variables"], variables)
    errors = variable_errors ++ errors
    {mood_min, min_error} = mood(row["mood_min"], "mood_min")
    {mood_max, max_error} = mood(row["mood_max"], "mood_max")
    errors = Enum.reject([min_error, max_error | errors], &is_nil/1)

    errors =
      if is_number(mood_min) and is_number(mood_max) and mood_min > mood_max,
        do: ["mood_min must not exceed mood_max" | errors],
        else: errors

    errors =
      if policy == "active_system" and source != "system",
        do: ["active_system requires source=system" | errors],
        else: errors

    normalized = %{
      template_type: type,
      text_template: text,
      source: source,
      variables: declared,
      mood_min: mood_min,
      mood_max: mood_max,
      is_active: policy == "active_system"
    }

    %{
      index: index,
      valid: errors == [],
      errors: Enum.reverse(errors),
      warnings: [],
      normalized: normalized,
      variables: variables,
      preview: render_preview(text, variables)
    }
  end

  defp validate_row(_, index, _),
    do: %{
      index: index,
      valid: false,
      errors: ["row must be an object"],
      warnings: [],
      normalized: nil,
      variables: [],
      preview: nil
    }

  # Event-only types render through TemplateEngine.simple_context/1. These are
  # conservative source-derived aliases, not a generic "any variable" escape hatch.
  defp allowed_vars(type) when is_binary(type) do
    Map.get(@vars_by_type, type) ||
      cond do
        type in ~w(hero_victory hero_defeat enemy_ambush spot_bandits search_danger hear_wolves) ->
          ~w(monster_name xp gold rounds _combat_verbs landmark)

        type in ~w(leave_city travel_road travel_shortcut cross_bridge enter_city bad_weather) ->
          ~w(destination terrain landmark)

        type in ~w(discover_ruin discover_cave find_shrine find_abandoned_cart notice_tracks find_tracks hear_river hear_birds smell_flowers collect_herbs) ->
          ~w(terrain discovery landmark herb_name)

        type in ~w(meet_merchant learn_rumors hear_song shelter_from_storm) ->
          ~w(npc_name rumor tavern gamble_result)

        type in ~w(rest_by_fire sleep_in_inn watch_sunset feel_confident remember_defeat thought rest death god_encourage god_punish god_heal god_direct god_quest god_weather equip) ->
          ~w(item_name)

        type in ~w(discover_treasure find_loot) ->
          ~w(loot_text discovery)

        true ->
          []
      end
  end

  defp allowed_vars(_), do: []

  defp normalize_text(text) when is_binary(text), do: String.trim(text)
  defp normalize_text(_), do: nil
  defp placeholders(nil), do: []

  defp placeholders(text),
    do:
      Regex.scan(~r/\{([A-Za-z_][A-Za-z0-9_]*)\}/, text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

  defp malformed_placeholders(nil), do: []

  defp malformed_placeholders(text) do
    Regex.scan(~r/\{[^{}]*\}/, text)
    |> List.flatten()
    |> Enum.reject(&Regex.match?(~r/^\{[A-Za-z_][A-Za-z0-9_]*\}$/, &1))
  end

  defp render_preview(nil, _), do: nil

  defp render_preview(text, _),
    do:
      Regex.replace(~r/\{([A-Za-z_][A-Za-z0-9_]*)\}/, text, fn match, key ->
        Map.get(@samples, key, match)
      end)

  defp normalized_declared_variables(nil, variables), do: {variables, []}

  defp normalized_declared_variables(declared, variables) when is_list(declared) do
    names = declared |> Enum.map(&normalize_variable/1)

    errors =
      if Enum.all?(names, &is_binary/1),
        do: [],
        else: ["variables must be an array of variable names"]

    normalized = names |> Enum.filter(&is_binary/1) |> Enum.uniq() |> Enum.sort()

    errors =
      if errors == [] and normalized != variables,
        do: ["variables must exactly match placeholders" | errors],
        else: errors

    {normalized, errors}
  end

  defp normalized_declared_variables(_, _),
    do: {[], ["variables must be an array of variable names"]}

  defp normalize_variable("{" <> rest), do: String.trim_trailing(rest, "}")
  defp normalize_variable(v) when is_binary(v), do: v
  defp normalize_variable(_), do: nil

  defp mood(nil, _), do: {nil, nil}

  defp mood(value, name) when is_integer(value) or is_float(value),
    do: check_mood(value * 1.0, name)

  defp mood(value, name) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> check_mood(number, name)
      _ -> {nil, "#{name} must be a number between 0 and 100"}
    end
  end

  defp mood(_, name), do: {nil, "#{name} must be a number between 0 and 100"}
  defp check_mood(value, _name) when value >= 0 and value <= 100, do: {value, nil}
  defp check_mood(_, name), do: {nil, "#{name} must be between 0 and 100"}

  defp mark_batch_duplicates(rows) do
    duplicate_keys =
      rows
      |> Enum.map(&row_key/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> Map.new()

    Enum.map(rows, fn row ->
      if Map.has_key?(duplicate_keys, row_key(row)),
        do: invalidate(row, "Duplicate template_type + text_template in batch"),
        else: row
    end)
  end

  # Near-duplicate detection deliberately stays batch-local. It compares only rows of
  # the same type and needs a long, highly similar opening, so short/common phrasing
  # and legitimately different narratives are not rejected.
  defp mark_batch_near_duplicates(rows) do
    near_duplicate_indexes =
      rows
      |> Enum.with_index()
      |> Enum.reduce(MapSet.new(), fn {row, index}, indexes ->
        rows
        |> Enum.drop(index + 1)
        |> Enum.with_index(index + 1)
        |> Enum.reduce(indexes, fn {other, other_index}, acc ->
          if near_duplicate?(row, other),
            do: MapSet.union(acc, MapSet.new([index, other_index])),
            else: acc
        end)
      end)

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      if MapSet.member?(near_duplicate_indexes, index),
        do: invalidate(row, "Near-duplicate opening sentence in batch"),
        else: row
    end)
  end

  defp near_duplicate?(left, right) do
    case {row_key(left), row_key(right)} do
      {{type, left_text}, {type, right_text}} when left_text != right_text ->
        left_opening = normalized_opening(left_text)
        right_opening = normalized_opening(right_text)
        shorter_length = min(String.length(left_opening), String.length(right_opening))
        prefix_length = common_prefix_length(left_opening, right_opening)

        shorter_length >= @near_duplicate_min_prefix_chars and
          prefix_length >= @near_duplicate_min_prefix_chars and
          prefix_length / shorter_length >= @near_duplicate_min_similarity

      _ ->
        false
    end
  end

  defp normalized_opening(text) do
    text
    |> String.split(~r/[.!?]+/u, parts: 2)
    |> hd()
    |> String.normalize(:nfc)
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp common_prefix_length(left, right) do
    left
    |> String.graphemes()
    |> Enum.zip(String.graphemes(right))
    |> Enum.take_while(fn {left_char, right_char} -> left_char == right_char end)
    |> length()
  end

  defp mark_existing_duplicates(rows) do
    keys = rows |> Enum.map(&row_key/1) |> Enum.reject(&is_nil/1)
    existing = existing_keys(keys)

    Enum.map(rows, fn row ->
      if MapSet.member?(existing, row_key(row)),
        do: invalidate(row, "Template already exists"),
        else: row
    end)
  end

  defp row_key(%{normalized: %{template_type: type, text_template: text}})
       when is_binary(type) and is_binary(text), do: {type, text}

  defp row_key(_), do: nil
  defp invalidate(row, error), do: %{row | valid: false, errors: Enum.uniq(row.errors ++ [error])}

  defp existing_keys([]), do: MapSet.new()

  defp existing_keys(keys) do
    keys = MapSet.new(keys)

    Repo.all(from t in NarrativeTemplate, select: {t.template_type, t.text_template})
    |> MapSet.new()
    |> MapSet.intersection(keys)
  end
end
