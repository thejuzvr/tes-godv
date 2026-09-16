defmodule TesIdle.Game.Narrative.FragmentPoolTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeFragment
  alias TesIdle.Game.Narrative.FragmentPool
  alias TesIdle.Test.FragmentIsolation
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    # N-5: сид наполнил реальные пулы (terrains/herb_names/...) — тесты пулов
    # работают в собственных sandbox-пулах, чтобы не зависеть от содержимого.
    hidden = FragmentIsolation.hide_seed_fragments(["terrains", "landmarks", "herb_names", "fish_names"])
    on_exit(fn -> FragmentIsolation.restore(hidden) end)
    :ok
  end

  defp fragment(pool, text, attrs \\ %{}) do
    Repo.insert!(Map.merge(%NarrativeFragment{pool_key: pool, text: text}, attrs))
  end

  test "draw/1 возвращает текст из указанного пула" do
    fragment("test_pool_a", "строка один")
    fragment("test_pool_a", "строка два")

    text = FragmentPool.draw("test_pool_a")
    assert text in ["строка один", "строка два"]
  end

  test "draw/1: неактивные фрагменты и чужие пулы не выдаются" do
    fragment("test_pool_b", "скрытая строка", %{is_active: false})
    fragment("test_pool_c", "видимая строка")

    assert FragmentPool.draw("test_pool_b") == nil
    assert FragmentPool.draw("test_pool_c") == "видимая строка"
  end

  test "draw/1: пустой пул → nil (переменная останется видимой в шаблоне)" do
    assert FragmentPool.draw("missing_pool_xyz") == nil
  end

  test "draw/1: weight 0 исключает фрагмент из выдачи" do
    fragment("test_pool_d", "нулевой вес", %{weight: 0})
    fragment("test_pool_d", "обычный вес")

    texts = for _ <- 1..10, into: MapSet.new(), do: FragmentPool.draw("test_pool_d")
    assert MapSet.member?(texts, "обычный вес")
    refute MapSet.member?(texts, "нулевой вес")
  end

  test "pool_texts/1 возвращает все активные тексты пула" do
    fragment("test_pool_e", "первая строка")
    fragment("test_pool_e", "неактивная", %{is_active: false})
    fragment("test_pool_f", "чужой пул")

    assert FragmentPool.pool_texts("test_pool_e") == ["первая строка"]
  end

  test "draw/1: не выдает фрагменты вне пула (изоляция от сид-контента)" do
    # Реальный пул из сида наполнен — draw обязан вернуть строку ИМЕННО из него
    fragment("other_test_pool", "не отсюда")
    text = FragmentPool.draw("openers_clear")
    if text do
      assert text in FragmentPool.pool_texts("openers_clear")
      refute text == "не отсюда"
    end
  end
end
