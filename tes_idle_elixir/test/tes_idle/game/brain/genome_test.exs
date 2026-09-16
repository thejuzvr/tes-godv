defmodule TesIdle.Game.Brain.GenomeTest do
  use ExUnit.Case, async: true

  alias TesIdle.Game.Brain.Genome

  @user_id "11111111-1111-1111-1111-111111111111"

  describe "brain_hash/2" do
    test "стабилен: тот же user + ordinal = тот же hash" do
      assert Genome.brain_hash(@user_id) == Genome.brain_hash(@user_id)
      assert Genome.brain_hash(@user_id, 1) == Genome.brain_hash(@user_id, 1)
    end

    test "разные пользователи → разные мозги" do
      h1 = Genome.brain_hash("user-a")
      h2 = Genome.brain_hash("user-b")
      assert h1 != h2
    end

    test "разные ординалы → разные мозги" do
      assert Genome.brain_hash(@user_id, 1) != Genome.brain_hash(@user_id, 2)
    end

    test "это 64 hex-символа (SHA256)" do
      hash = Genome.brain_hash(@user_id)
      assert byte_size(hash) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, hash)
    end
  end

  describe "derive/1" do
    setup do
      %{hash: Genome.brain_hash(@user_id)}
    end

    test "детерминирован: два вызова дают идентичный геном", %{hash: hash} do
      assert Genome.derive(hash) == Genome.derive(hash)
    end

    test "разные hash → разные геномы" do
      g1 = Genome.derive(Genome.brain_hash("user-a"))
      g2 = Genome.derive(Genome.brain_hash("user-b"))
      assert g1.traits != g2.traits or g1.links != g2.links
    end

    test "9 черт в диапазоне 30..70", %{hash: hash} do
      genome = Genome.derive(hash)
      assert MapSet.new(Map.keys(genome.traits)) == MapSet.new(Genome.traits())
      assert genome.traits |> Map.values() |> Enum.all?(&(&1 in 30..70))
    end

    test "все 15 связей, вес в коридоре -1.0..1.0", %{hash: hash} do
      genome = Genome.derive(hash)
      assert MapSet.new(Map.keys(genome.links)) == MapSet.new(Genome.link_pairs())

      assert genome.links
             |> Map.values()
             |> Enum.all?(&(&1 >= -1.0 and &1 <= 1.0))
    end

    test "причуды: 0..2, уникальные, из известного набора", %{hash: hash} do
      genome = Genome.derive(hash)
      assert length(genome.quirks) in 0..2
      assert Enum.uniq(genome.quirks) == genome.quirks
      assert genome.quirks -- Genome.quirks() == []
    end

    test "архетип из известного списка, generation = 1", %{hash: hash} do
      genome = Genome.derive(hash)
      assert genome.archetype_hint in Genome.archetype_hints()
      assert genome.generation == 1
    end

    test "гено-база покрывает все 9 черт", %{hash: hash} do
      traits = Genome.base_traits(hash)
      assert MapSet.new(Map.keys(traits)) == MapSet.new(Genome.traits())
    end
  end

  test "причуды на всём пространстве hash остаются в коридоре 0..2" do
    # 200 детерминированных пользователей — ни один не выбился из коридора
    results =
      for i <- 1..200 do
        hash = Genome.brain_hash("bulk-user-#{i}")
        length(Genome.derive(hash).quirks)
      end

    assert Enum.all?(results, &(&1 in 0..2))
    # и распределение не вырождено (есть и безпричудные, и с причудами)
    assert 0 in results
    assert Enum.any?(results, &(&1 > 0))
  end
end
