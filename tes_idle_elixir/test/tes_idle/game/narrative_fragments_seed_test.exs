defmodule TesIdle.Game.NarrativeFragmentsSeedTest do
  @moduledoc """
  N-5: пулы фрагментов — тональная смесь (обычные + комичные ~50/50).

  Проверяем контракт seed_fragments.exs: каждая тонально-чувствительная группа
  (опенеры погоды, closers настроения) содержит и нейтральные, и комичные строки;
  пул не вырождается в один тон. Сам скрипт сид-файла не запускаем — его логика
  идемпотентности (MapSet по {pool_key, text}) тривиальна, а состав пулов — это
  контентный контракт, который фиксируем здесь.
  """

  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeFragment
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  # Маркеры комичных строк из seed (устойчивые подстроки, не встречающиеся в обычных).
  # ВАЖНО: Ecto-запрос из теста возвращает строки как есть, но маркеры сравниваются
  # с lowercase-текстом — маркеры тоже в нижнем регистре.
  @comedic_markers ["стражник", "вороны", "тапки", "кошеля", "каша", "безделье",
                    "пешком", "зонтик", "роскошью", "последняя капля", "оркестра",
                    "птицы", "лужу", "сочинения", "советчик", "вороной", "соловой",
                    "пельменя", "крендель", "сапог", "ремесла", "проснулся", "громко",
                    "трижды", "монету", "шляпу", "медведи"]

  defp pool_texts(pool) do
    Repo.all(from f in NarrativeFragment, where: f.pool_key == ^pool and f.is_active == true, select: f.text)
  end

  defp is_comedic?(t), do: Enum.any?(@comedic_markers, &String.contains?(String.downcase(t), &1))
  defp has_comedic?(texts), do: Enum.any?(texts, &is_comedic?/1)
  defp has_plain?(texts), do: Enum.any?(texts, &(not is_comedic?(&1)))

  test "опенеры всех 5 погод — тональная смесь (обычные + комичные)" do
    for w <- ["clear", "cloud", "rain", "storm", "snow"] do
      texts = pool_texts("openers_" <> w)
      assert length(texts) >= 3, "openers_#{w} слишком мал (#{length(texts)})"
      assert has_comedic?(texts), "openers_#{w}: нет комичных строк"
      assert has_plain?(texts), "openers_#{w}: нет нейтральных строк"
    end
  end

  test "closers трёх настроений — тональная смесь" do
    for b <- ["high", "mid", "low"] do
      texts = pool_texts("closers_" <> b)
      assert length(texts) >= 4, "closers_#{b} слишком мал (#{length(texts)})"
      assert has_comedic?(texts), "closers_#{b}: нет комичных строк"
      assert has_plain?(texts), "closers_#{b}: нет нейтральных строк"
    end
  end

  test "предметные пулы расширены (рыба/травы/свидетели ≥ 8)" do
    for pool <- ["fish_names", "herb_names", "witnesses", "npc_names", "terrains", "discoveries", "landmarks"] do
      n = length(pool_texts(pool))
      assert n >= 8, "#{pool} слишком мал (#{n})"
    end
  end

  test "все фрагменты активны и с валидным весом" do
    bad = Repo.all(from f in NarrativeFragment, where: f.weight <= 0 or f.is_active == false)
    assert bad == [], "найдены неактивные/нулевые фрагменты: #{length(bad)}"
  end
end
