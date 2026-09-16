defmodule TesIdle.Game.Narrative.LlmFactory do
  @moduledoc """
  N-4: оффлайн-фабрика кандидатов шаблонов.

  Комбинатор сцен: случайный активный шаблон типа × опенер погоды × closer
  настроения — все строки из БД-пулов (`narrative_fragments`), `{var}` остаются
  нетронутыми (рендерит TemplateEngine в рантайме). Кандидаты вставляются с
  `source: "llm"`, `is_active: false` и попадают в модерацию (approve/reject).

  Точка расширения: внешний LLM-бэкенд добавляется здесь же — контракты
  (source="llm", is_active=false, модерация) не меняются. Пока ключей нет,
  работает комбинатор — он не завязан на сеть и даёт тот же продукт.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.{NarrativeTemplate, NarrativeFragment}
  alias TesIdle.Game.Narrative.{Analytics, FragmentPool}
  import Ecto.Query

  @weather_keys ["clear", "cloud", "rain", "storm", "snow"]
  @mood_bands ["high", "mid", "low"]
  @max_batch_types 8

  @doc "Генерирует до `count` кандидатов для типа. Возвращает {:ok, inserted}, {:ok, []} если типа нет."
  def generate(template_type, count \\ 6) when is_binary(template_type) and is_integer(count) do
    count = min(max(count, 1), 20)
    backbones = backbones(template_type, count)

    candidates =
      backbones
      |> Enum.map(&build_candidate(template_type, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.text_template)
      |> Enum.map(&Repo.insert!/1)

    {:ok, candidates}
  end

  @doc """
  A-2b: batch-генерация по целям аналитики (тонкие типы журнала + мёртвые шаблоны).
  Возвращает {:ok, results_map, total}, максимум #{@max_batch_types} типов за прогон.
  """
  def generate_batch(count_per_type) when is_integer(count_per_type) do
    count_per_type = min(max(count_per_type, 1), 10)

    results =
      Analytics.factory_targets(30)
      |> Enum.take(@max_batch_types)
      |> Map.new(fn type ->
        {:ok, candidates} = generate(type, count_per_type)
        {type, length(candidates)}
      end)

    {:ok, results, results |> Map.values() |> Enum.sum()}
  end

  defp backbones(template_type, count) do
    from(t in NarrativeTemplate,
      where: t.template_type == ^template_type and t.is_active == true and t.source == "system"
    )
    |> Repo.all()
    |> case do
      [] -> []
      backbones -> backbones |> Enum.shuffle() |> Stream.cycle() |> Enum.take(count)
    end
  end

  # Один тонкий костяк × разные опенеры/клозеры → разные кандидаты
  defp build_candidate(type, backbone) do
    with opener when is_binary(opener) <- draw_opener(),
         closer when is_binary(closer) <- draw_closer() do
      text = Enum.reject([opener, backbone.text_template, closer], &(&1 in [nil, ""])) |> Enum.join(" ")

      %NarrativeTemplate{
        template_type: type,
        text_template: text,
        source: "llm",
        is_active: false
      }
    end
  end

  defp draw_opener do
    with w when is_binary(w) <- Enum.random(@weather_keys) do
      FragmentPool.draw("openers_" <> w)
    end
  end

  defp draw_closer do
    with b when is_binary(b) <- Enum.random(@mood_bands) do
      FragmentPool.draw("closers_" <> b)
    end
  end

  @doc "Счётчик кандидатов в модерации (для UI)."
  def pending_count do
    Repo.one(
      from t in NarrativeTemplate,
        where: t.source == "llm" and t.is_active == false,
        select: count(t.id)
    )
  end

  @doc "Есть ли вообще фрагменты пулов (иначе фабрика бессмысленна)."
  def fragments_available? do
    Repo.aggregate(from(f in NarrativeFragment, where: f.is_active == true), :count, :id) > 0
  end
end
