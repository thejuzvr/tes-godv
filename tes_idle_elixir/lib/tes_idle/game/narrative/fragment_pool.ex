defmodule TesIdle.Game.Narrative.FragmentPool do
  @moduledoc """
  N-1: выдача описательных фрагментов из БД (narrative_fragments).

  Заменяет хардкодные пулы TemplateEngine (@terrains, @npc_names, ...) —
  по правилу «Нарративы — только из БД». Пулы: terrains, discoveries,
  landmarks, combat_verbs, npc_names, fish_names, herb_names, witnesses.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeFragment
  import Ecto.Query

  @doc """
  Случайный (взвешенный) активный текст пула.
  nil, если пул пуст — переменная останется видимой в шаблоне ({terrain}),
  что честно сигнализирует о незаполненном пуле.
  """
  def draw(pool_key) do
    fragments =
      Repo.all(
        from f in NarrativeFragment,
          where: f.pool_key == ^pool_key and f.is_active == true and f.weight > 0,
          select: {f.text, f.weight}
      )

    case fragments do
      [] -> nil
      _ -> weighted_random(fragments)
    end
  end

  @doc "Все активные тексты пула (для превью и сидов)."
  def pool_texts(pool_key) do
    Repo.all(
      from f in NarrativeFragment,
        where: f.pool_key == ^pool_key and f.is_active == true,
        order_by: [asc: f.text],
        select: f.text
    )
  end

  defp weighted_random(fragments) do
    total = Enum.reduce(fragments, 0, fn {_text, w}, acc -> acc + w end)
    # roll ∈ 1..total ⇒ цикл гарантированно завершается {:halt, text}
    roll = :rand.uniform(total)

    Enum.reduce_while(fragments, 0, fn {text, w}, acc ->
      new_acc = acc + w
      if roll <= new_acc, do: {:halt, text}, else: {:cont, new_acc}
    end)
  end
end
