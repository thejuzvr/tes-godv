defmodule TesIdle.Game.Brain.Genome do
  @moduledoc """
  Детерминированный «паспорт мозга» героя (ROADMAP_BRAIN_WORLD.md, Часть I).

      brain_hash = SHA256(user_id <> ":hero:" <> ordinal)

  Черты, микросвязи (нейронный слой), причуды и архетип выводятся
  **чисто из байт hash** — без глобального состояния PRNG:

  тот же пользователь + тот же номер героя = тот же мозг, навсегда.
  Разные герои = разные мозги; пересечения минимальны.

  Правило жизни: герой не умирает — он перерождается (generation += 1,
  hash неизменен). См. `TesIdle.Game.Brain.Learner` (Фаза 1).
  """

  # 9 черт: 6 базовых + patience/dexterity/empathy под новые активности
  @traits [:bravery, :curiosity, :greed, :sociability, :tenacity, :caution,
           :patience, :dexterity, :empathy]

  # Микросвязи: пары черт, вес -1.0..+1.0 из hash (15 связей, байты 9..23)
  @link_pairs [
    {:bravery, :greed},        # риск-аппетит
    {:bravery, :caution},      # дерзость vs самосохранение
    {:curiosity, :caution},    # осторожное исследование
    {:curiosity, :patience},   # дотошный исследователь
    {:greed, :dexterity},      # воровская жилка
    {:greed, :patience},       # методичный добытчик
    {:sociability, :empathy},  # привязанность к людям/питомцам
    {:sociability, :bravery},  # вожак / одиночка
    {:tenacity, :patience},    # долгая рутина
    {:caution, :dexterity},    # точность замков
    {:empathy, :patience},     # забота о питомце
    {:bravery, :curiosity},    # первопроходец
    {:greed, :sociability},    # торговая жилка
    {:tenacity, :bravery},     # стойкость до конца
    {:empathy, :caution},      # оберегающий инстинкт
  ]

  # Причуды v1 (решено 2026-09-02): ровно этот набор
  @quirks [:afraid_of_water, :dawn_fisher, :cup_collector, :night_thief,
           :spider_panic, :braggart, :superstitious, :sweet_tooth]

  @archetype_hints [:wanderer, :warrior, :schemer, :socialite, :hermit, :grinder]

  @hash_bytes 32

  @doc "Паспорт мозга: SHA256(user_id:hero:ordinal) → 64 hex-символа."
  def brain_hash(user_id, hero_ordinal \\ 1)

  def brain_hash(user_id, hero_ordinal) when is_binary(user_id) and is_integer(hero_ordinal) do
    :sha256
    |> :crypto.hash("#{user_id}:hero:#{hero_ordinal}")
    |> Base.encode16(case: :lower)
  end

  def brain_hash(user_id, hero_ordinal), do: brain_hash(to_string(user_id), hero_ordinal)

  @doc """
  Выводит геном из hash. Возвращает:

      %{
        traits: %{bravery: 30..70, ... 9 шт},
        links: %{{trait_a, trait_b} => -1.0..1.0, ... 15 связей},
        quirks: [0..2 атомов из @quirks],
        archetype_hint: :wanderer | :warrior | :schemer | :socialite | :hermit | :grinder,
        generation: 1,
      }
  """
  def derive(hash) when is_binary(hash) do
    bytes = Base.decode16!(hash, case: :mixed)

    %{
      traits: derive_traits(bytes),
      links: derive_links(bytes),
      quirks: derive_quirks(bytes),
      archetype_hint: pick(@archetype_hints, at(bytes, 27)),
      generation: 1,
    }
  end

  @doc "Черты гено-базы (30..70) — точка входа для Personality.generate."
  def base_traits(hash), do: derive(hash).traits

  def traits, do: @traits
  def link_pairs, do: @link_pairs
  def quirks, do: @quirks
  def archetype_hints, do: @archetype_hints

  # --- Вывод из байт ---------------------------------------------------------

  # Байты 0..8 → черты 30..70 (равномерно, 41 значение)
  defp derive_traits(bytes) do
    @traits
    |> Enum.with_index()
    |> Map.new(fn {trait, i} -> {trait, 30 + rem(at(bytes, i), 41)} end)
  end

  # Байты 9..23 → веса связей -1.0..1.0 (шаг ~0.008)
  defp derive_links(bytes) do
    @link_pairs
    |> Enum.with_index(9)
    |> Map.new(fn {{a, b}, i} ->
      weight = (at(bytes, i) - 127.5) / 127.5
      {{a, b}, Float.round(weight, 3)}
    end)
  end

  # Байт 24 → количество причуд (≈31% ноль, ≈55% одна, ≈14% две);
  # байты 25..26 → индексы (uniq — дубликаты схлопываются)
  defp derive_quirks(bytes) do
    roll = at(bytes, 24)

    count =
      cond do
        roll < 80 -> 0
        roll < 220 -> 1
        true -> 2
      end

    [at(bytes, 25), at(bytes, 26)]
    |> Enum.map(&(rem(&1, length(@quirks))))
    |> Enum.uniq()
    |> Enum.take(count)
    |> Enum.map(&Enum.at(@quirks, &1))
  end

  defp at(bytes, i) when i < @hash_bytes, do: :binary.at(bytes, i)

  defp pick(list, byte), do: Enum.at(list, rem(byte, length(list)))
end
