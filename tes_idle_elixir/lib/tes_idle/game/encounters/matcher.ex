defmodule TesIdle.Game.Encounters.Matcher do
  @moduledoc """
  Loads eligible heroes in one query and forms deterministic, disjoint pairs.
  """

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, HeroSocialSetting}

  @type candidate :: %{id: Ecto.UUID.t(), location_id: Ecto.UUID.t()}

  @spec candidates(map(), DateTime.t()) :: [candidate()]
  def candidates(config, now \\ DateTime.utc_now()) do
    ttl = config["activity_ttl_seconds"]
    allowed_states = config["allowed_states"]
    fresh_after = DateTime.add(now, -ttl, :second)

    Repo.all(
      from hero in Hero,
        left_join: settings in HeroSocialSetting,
        on: settings.hero_id == hero.id,
        where:
          not is_nil(hero.location_id) and hero.state in ^allowed_states and
            (settings.encounter_mode == "async" or
               (coalesce(settings.encounter_mode, "live_only") == "live_only" and
                  hero.is_online == true and hero.last_activity >= ^fresh_after)),
        select: %{id: hero.id, location_id: hero.location_id}
    )
  end

  @spec pairs([candidate()], integer()) :: [{candidate(), candidate()}]
  def pairs(candidates, round) do
    candidates
    |> Enum.group_by(& &1.location_id)
    |> Enum.sort_by(fn {location_id, _} -> location_id end)
    |> Enum.flat_map(fn {location_id, heroes} ->
      heroes
      |> Enum.sort_by(fn hero -> {:erlang.phash2({round, location_id, hero.id}), hero.id} end)
      |> adjacent_pairs()
    end)
  end

  @spec match(integer(), map(), DateTime.t()) :: [{candidate(), candidate()}]
  def match(round, config, now \\ DateTime.utc_now()) do
    config
    |> candidates(now)
    |> pairs(round)
  end

  defp adjacent_pairs([left, right | rest]), do: [{left, right} | adjacent_pairs(rest)]
  defp adjacent_pairs(_), do: []
end
