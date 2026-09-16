defmodule TesIdle.Game.Personality do
  @moduledoc """
  Hero personality traits that influence decision-making and narrative generation.
  Traits: bravery, curiosity, greed, sociability, tenacity, caution (0-100 each),
  plus patience, dexterity, empathy for activity systems (ROADMAP Часть I/II).
  Modified by race and class at creation. Stored as JSONB in heroes.personality.

  Two generation paths:
  - `generate(race, class, brain_hash: h)` — deterministic from Brain.Genome (new heroes)
  - `generate(race, class)` — legacy random (backward compat)
  """

  @race_modifiers %{
    "Nord" => %{"bravery" => 20, "caution" => -10},
    "Khajiit" => %{"greed" => 20, "curiosity" => 10, "dexterity" => 20},
    "Imperial" => %{"sociability" => 20, "bravery" => -10},
    "Breton" => %{"curiosity" => 15, "sociability" => 10},
    "Redguard" => %{"bravery" => 15, "tenacity" => 10},
    "Altmer" => %{"curiosity" => 20, "sociability" => -10},
    "Dunmer" => %{"tenacity" => 15, "bravery" => 10},
    "Argonian" => %{"caution" => 20, "curiosity" => 15, "patience" => 15},
    "Orc" => %{"bravery" => 25, "caution" => -15, "greed" => 10},
    "WoodElf" => %{"curiosity" => 15, "sociability" => 10, "tenacity" => 10, "patience" => 10},
  }

  @class_modifiers %{
    "Warrior" => %{"bravery" => 15, "tenacity" => 10},
    "Mage" => %{"curiosity" => 20, "caution" => 5},
    "Thief" => %{"greed" => 15, "caution" => 10, "curiosity" => 5, "dexterity" => 20},
    "Priest" => %{"sociability" => 20, "bravery" => -5, "empathy" => 15},
    "Bard" => %{"sociability" => 25, "curiosity" => 10, "empathy" => 10},
    "Berserker" => %{"bravery" => 30, "caution" => -20},
  }

  @traits [:bravery, :curiosity, :greed, :sociability, :tenacity, :caution,
           :patience, :dexterity, :empathy]

  @doc "Generate personality traits for a new hero."
  def generate(race, hero_class, opts \\ [])

  # Детерминированный путь: гено-база из Brain.Genome + модификаторы расы/класса
  def generate(race, hero_class, [{:brain_hash, hash} | _]) when is_binary(hash) do
    genome_traits = TesIdle.Game.Brain.Genome.base_traits(hash)
    base = Map.new(@traits, fn t -> {t, Map.get(genome_traits, t, 50)} end)
    apply_all_modifiers(base, race, hero_class)
  end

  # Легаси-путь: случайные значения (обратная совместимость)
  def generate(race, hero_class, _opts) do
    base = Map.new(@traits, fn t -> {t, Enum.random(30..70)} end)
    apply_all_modifiers(base, race, hero_class)
  end

  @doc "Ensure personality is a proper normalized map."
  def normalize(nil), do: default()

  # Ключи из JSONB приходят строками — принимаем и атомы, и строки.
  # (Баг: раньше строковые ключи молча сбрасывались в дефолт 50.)
  def normalize(%{} = p) do
    Map.new(@traits, fn t ->
      v = Map.get(p, t) || Map.get(p, Atom.to_string(t)) || 50
      {t, clamp_number(v)}
    end)
  end

  def normalize(_), do: default()

  @doc "Get a trait value."
  def trait(personality, name) when is_atom(name) do
    Map.get(personality || %{}, name) || Map.get(personality || %{}, Atom.to_string(name)) || 50
  end

  def trait(personality, name) when is_binary(name) do
    trait(personality, String.to_existing_atom(name))
  end

  @doc "Adjust a trait (for experience/memory effects)."
  def adjust(personality, trait_name, delta) do
    current = trait(personality, trait_name)
    Map.put(personality, trait_name, max(0, min(100, current + delta)))
  end

  defp clamp_number(v) when is_integer(v), do: max(0, min(100, v))
  defp clamp_number(v) when is_float(v), do: v |> max(0.0) |> min(100.0)
  defp clamp_number(_), do: 50

  defp apply_all_modifiers(base, race, hero_class) do
    base
    |> apply_modifiers(Map.get(@race_modifiers, race, %{}))
    |> apply_modifiers(Map.get(@class_modifiers, hero_class, %{}))
    |> Enum.into(%{}, fn {k, v} -> {k, max(0, min(100, v))} end)
  end

  defp apply_modifiers(base, mods) do
    Enum.reduce(mods, base, fn {trait_name, delta}, acc ->
      trait_atom = String.to_existing_atom(trait_name)
      Map.update(acc, trait_atom, 50, &(&1 + delta))
    end)
  end

  defp default do
    %{bravery: 50, curiosity: 50, greed: 50, sociability: 50, tenacity: 50, caution: 50,
      patience: 50, dexterity: 50, empathy: 50}
  end
end
