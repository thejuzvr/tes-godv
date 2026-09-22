defmodule TesIdle.Game.Sparks do
  @moduledoc """
  Искры — редкая валюта игрока (docs/PLAN_CHARACTER.md, раздел 3).

  Не путать с `soul_energy`: та копится сама и тратится на волю бога.
  Искра не восстанавливается сама и не имеет потолка в 100.

  Потолки считаются по записям журнала `spark_<источник>` за сегодня UTC,
  поэтому повтор тика не выдаёт вторую искру. Функции только решают;
  запись журнала и прибавку делает Pipeline.
  """

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.JournalEntry

  @fallback %{
    "time_daily" => 1,
    "victory_daily" => 2,
    "quest_weekly" => 2,
    "guild_weekly" => 1,
    "victory_chance" => 0.12,
    "time_chance" => 0.02,
    "guild_min_level" => 2,
    "guild_points" => 50,
    "dossier_cost" => 1,
    "rank_costs" => [1, 2, 4]
  }

  def cfg(configs) do
    Map.merge(@fallback, (configs || %{})["soul_sparks"] || %{})
  end

  def sources, do: ~w(time victory quest guild)

  @doc "Можно ли выдать искру этого источника прямо сейчас."
  def allow?(hero, source, configs \\ %{}) do
    limits = cfg(configs)

    case source do
      "time" -> granted_since(hero.id, source, day_start()) < limits["time_daily"]
      "victory" -> granted_since(hero.id, source, day_start()) < limits["victory_daily"]
      "quest" -> granted_since(hero.id, source, week_start()) < limits["quest_weekly"]
      "guild" -> granted_since(hero.id, source, week_start()) < limits["guild_weekly"]
      _ -> false
    end
  end

  @doc "Победа над сильным противником: низкий шанс, не каждый крыс."
  def victory_spark?(hero, result, configs \\ %{}) do
    combat = result[:combat_result] || %{}

    combat[:victory] == true and strong?(hero, combat) and
      :rand.uniform() < cfg(configs)["victory_chance"] and allow?(hero, "victory", configs)
  end

  @doc "Суточная искра за время. Только онлайн: офлайн-тик её не получает."
  def time_spark?(hero, configs \\ %{}) do
    hero.is_online == true and allow?(hero, "time", configs) and
      :rand.uniform() < cfg(configs)["time_chance"]
  end

  def quest_spark?(hero, configs \\ %{}), do: allow?(hero, "quest", configs)

  defp strong?(hero, combat) do
    level = combat[:monster_level] || combat[:level] || 1
    level >= max(1, (hero.level || 1) - 1)
  end

  defp granted_since(hero_id, source, since) do
    Repo.one(
      from j in JournalEntry,
        where: j.hero_id == ^hero_id and j.entry_type == ^"spark_#{source}" and j.created_at >= ^since,
        select: count(j.id)
    ) || 0
  end

  defp day_start do
    Date.utc_today() |> NaiveDateTime.new!(~T[00:00:00])
  end

  defp week_start do
    today = Date.utc_today()
    Date.add(today, -(Date.day_of_week(today) - 1)) |> NaiveDateTime.new!(~T[00:00:00])
  end
end
