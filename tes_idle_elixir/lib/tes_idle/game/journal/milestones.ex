defmodule TesIdle.Game.Journal.Milestones do
  @moduledoc """
  Памятные вехи героя (docs/JOURNAL_RETENTION_ARCHITECTURE.md, 5.2).

  Веха — это то, что остаётся, когда обычные тексты хроники уже удалены:
  смена поколения, порог уровня, завершённый квест, первая победа, избранное
  игроком. Храним **снимок текста**, потому что шаблон могут изменить или
  удалить, и тогда памятная запись превратилась бы в пустышку.

  Cap на количество вех защищает от превращения «памятного» в свалку:
  500 автоматических + 100 избранных. При переполнении вытесняется самая
  старая веха того же типа (однотипные вехи не копятся бесконечно).
  """

  require Logger

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.HeroMilestone

  @default_cap 500
  @default_bookmark_cap 100

  @doc """
  Записывает веху. Идемпотентно по (hero_id, kind, entry_type, day):
  повторная доставка события не создаёт дубликат памятной записи.

  `opts`: `:entry_type`, `:text`, `:title`, `:chapter`, `:game_day`, `:payload`.
  """
  def record(hero, kind, opts \\ %{}) when is_map(opts) do
    hero_id = if is_map(hero), do: hero.id, else: hero
    game_day = opts[:game_day] || (is_map(hero) && hero.game_day) || nil
    entry_type = opts[:entry_type]

    attrs = %{
      hero_id: hero_id,
      kind: to_string(kind),
      # Избранное игрока хранится отдельной категорией со своим cap,
      # поэтому источник приходит из opts, а не жёстко "auto".
      source: opts[:source] || "auto",
      entry_type: entry_type,
      title: opts[:title] || title_for(kind, entry_type),
      text: opts[:text] || "",
      chapter: opts[:chapter],
      game_day: game_day,
      payload: opts[:payload] || %{}
    }

    if duplicate?(hero_id, attrs.kind, entry_type, game_day) do
      :ok
    else
      case %HeroMilestone{} |> HeroMilestone.changeset(attrs) |> Repo.insert() do
        {:ok, milestone} ->
          enforce_cap(hero_id, attrs.source, cap_for(attrs.source))
          {:ok, milestone}

        {:error, changeset} ->
          Logger.warning("milestone insert rejected: #{inspect(changeset.errors)}")
          :ok
      end
    end
  rescue
    error ->
      # Веха — наблюдательная запись: её сбой не должен ронять тик героя.
      Logger.warning("milestone insert raised: #{Exception.message(error)}")
      :ok
  end

  @doc "Избранная игроком запись — отдельный cap."
  def bookmark(hero_id, text, opts \\ %{}) do
    result = record(hero_id, "bookmark", Map.merge(opts, %{source: "bookmark", text: text}))
    enforce_cap(hero_id, "bookmark", @default_bookmark_cap)
    result
  end

  @doc "Вехи героя, новые первыми."
  def list(hero_id, limit \\ 100) do
    Repo.all(
      from m in HeroMilestone,
        where: m.hero_id == ^hero_id,
        order_by: [desc: m.created_at],
        limit: ^limit
    )
  end

  @doc "Количество вех героя — для панели и проверки cap."
  def count(hero_id) do
    Repo.one(from m in HeroMilestone, where: m.hero_id == ^hero_id, select: count(m.id)) || 0
  end

  # ─── Внутреннее ──────────────────────────────────────

  # Проверка дубликата: entry_type и game_day могут быть NULL, а сравнение
  # с NULL в SQL не даёт true. Поэтому для NULL используем is_nil/1 —
  # иначе веха без типа не находилась бы и дубликаты копились бы.
  defp duplicate?(hero_id, kind, entry_type, game_day) do
    query =
      from m in HeroMilestone,
        where: m.hero_id == ^hero_id and m.kind == ^kind,
        where: ^entry_type_filter(entry_type),
        where: ^game_day_filter(game_day)

    Repo.exists?(query)
  end

  defp entry_type_filter(nil), do: dynamic([m], is_nil(m.entry_type))
  defp entry_type_filter(value), do: dynamic([m], m.entry_type == ^value)

  defp game_day_filter(nil), do: dynamic([m], is_nil(m.game_day))
  defp game_day_filter(value), do: dynamic([m], m.game_day == ^value)

  # Вытесняем самые старые вехи этого типа, сохраняя общее число в пределах cap.
  # Избранное исключено: игрок не должен терять закладки из-за автоматических вех.
  defp enforce_cap(hero_id, source, cap) do
    total =
      Repo.one(
        from m in HeroMilestone,
          where: m.hero_id == ^hero_id and m.source == ^source,
          select: count(m.id)
      ) || 0

    if total > cap do
      excess = total - cap

      ids =
        Repo.all(
          from m in HeroMilestone,
            where: m.hero_id == ^hero_id and m.source == ^source,
            order_by: [asc: m.created_at],
            limit: ^excess,
            select: m.id
        )

      Repo.delete_all(from m in HeroMilestone, where: m.id in ^ids)
    end

    :ok
  end

  defp title_for("generation_shift", _), do: "Новое поколение"
  defp title_for("level_threshold", _), do: "Новый порог уровня"
  defp title_for("quest_completed", _), do: "Квест завершён"
  defp title_for("first_kill", _), do: "Первая победа"
  defp title_for("rare_loot", _), do: "Редкая находка"
  defp title_for("guild_joined", _), do: "Знамя поднято"
  defp title_for("guild_lead", _), do: "Во главе гильдии"
  defp title_for("bookmark", _), do: "Избранная запись"
  defp title_for(kind, entry_type), do: "#{kind}#{if entry_type, do: ": #{entry_type}", else: ""}"

  defp cap_for("bookmark"), do: @default_bookmark_cap
  defp cap_for(_), do: @default_cap
end
