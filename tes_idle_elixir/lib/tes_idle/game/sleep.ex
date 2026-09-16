defmodule TesIdle.Game.Sleep do
  @moduledoc """
  P-4: сны при долгом отдыхе. Герой отдыхает (state_to == "resting") несколько
  тиков подряд — с шансом dream_chance (и не чаще одного сна за игровой день)
  в журнал пишется запись типа "dream" ИЗ БД (нет шаблона — записи нет).
  Кандидат-функция чистая по духу world_news_candidate: возвращает обновлённый
  merged_sd и выбранный шаблон (или nil); вставку записи делает Pipeline — там
  живёт глава дневника.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate
  import Ecto.Query

  def default_config, do: %{"dream_chance" => 0.35, "min_streak" => 3}

  @doc """
  Обновляет блок sleep в merged_sd и, если пора спать, возвращает {merged_sd, template}.
  result.state_to != "resting" — сброс streak (герой снова на ногах), {merged_sd, nil}.
  """
  def step(merged_sd, hero, result, configs) when is_map(merged_sd) do
    if result && result[:state_to] == "resting" do
      cfg = (configs || %{})["sleep"] || default_config()
      min_streak = cfg["min_streak"] || 3
      dream_chance = cfg["dream_chance"] || 0.35

      streak = get_in(merged_sd, ["sleep", "streak"]) || 0
      streak = streak + 1
      last_day = get_in(merged_sd, ["sleep", "last_dream_day"])

      merged_sd = Map.put(merged_sd, "sleep", %{"streak" => streak, "last_dream_day" => last_day})

      if streak >= min_streak and last_day != hero.game_day and :rand.uniform() < dream_chance do
        case draw_template() do
          nil ->
            {merged_sd, nil}

          template ->
            merged_sd =
              Map.put(merged_sd, "sleep", %{"streak" => streak, "last_dream_day" => hero.game_day})

            {merged_sd, template}
        end
      else
        {merged_sd, nil}
      end
    else
      {Map.delete(merged_sd, "sleep"), nil}
    end
  end

  defp draw_template do
    Repo.one(
      from t in NarrativeTemplate,
        where: t.template_type == "dream" and t.source == "system" and t.is_active == true,
        order_by: fragment("RANDOM()"),
        limit: 1
    )
  end
end
