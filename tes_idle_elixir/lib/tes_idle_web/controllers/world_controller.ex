defmodule TesIdleWeb.WorldController do
  @moduledoc "W-7: снапшот мира для дашборда + C-1 пожертвование на стройку (аутентифицированные пользователи)."
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry, NarrativeTemplate}
  alias TesIdle.Game.Narrative.TemplateEngine
  alias TesIdle.World.{Construction, Kernel}
  import Ecto.Query

  def show(conn, _params) do
    json(conn, %{snapshot: Kernel.snapshot()})
  end

  @doc """
  C-1: пожертвовать золото на стройку. Золото списывается с героя и уходит из экономики
  в фонд. Прогресс — в снапшоте мира (виден всем). Запись в журнал — по шаблону из БД.
  """
  def donate(conn, params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    amount = parse_amount(params["amount"])
    cfg = TesIdle.Game.ContextBuilder.load_configs()
    min_donation = get_in(cfg, ["construction", "min_donation"]) || 10

    cond do
      is_nil(hero) ->
        conn |> put_status(404) |> json(%{error: "hero_not_found"})

      is_nil(amount) or amount < min_donation ->
        conn |> put_status(400) |> json(%{error: "min_donation", min_donation: min_donation})

      true ->
        fresh = Repo.reload!(hero)

        if fresh.gold < amount do
          conn |> put_status(409) |> json(%{error: "not_enough_gold", gold: fresh.gold})
        else
          hero2 =
            fresh
            |> Ecto.Changeset.change(%{gold: fresh.gold - amount})
            |> Repo.update!()

          {:ok, block} = Kernel.donate(hero2.name, amount)
          journal_donation(hero2, amount, block, cfg)

          json(conn, %{
            construction: Construction.summary(block, cfg),
            gold: hero2.gold
          })
        end
    end
  end

  # Целое из JSON может прийти и строкой (грабля approve-batch max)
  defp parse_amount(a) when is_integer(a) and a > 0, do: a
  defp parse_amount(a) when is_binary(a) do
    case Integer.parse(a) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end
  defp parse_amount(_), do: nil

  # Нарратив — только из БД: шаблон construction_donation, нет шаблона — нет записи (честно)
  defp journal_donation(hero, amount, block, cfg) do
    template =
      Repo.one(
        from t in NarrativeTemplate,
          where: t.template_type == "construction_donation" and t.is_active == true,
          order_by: fragment("random()"),
          limit: 1,
          select: t.text_template
      )

    summary = Construction.summary(block, cfg)

    if template do
      # render_vars требует СТРОКОВЫЕ значения (не-строка → символ по кодовой точке)
      text =
        TemplateEngine.render_vars(template, %{
          "hero_name" => hero.name,
          "amount" => Integer.to_string(amount),
          "project" => summary["project"],
          "stage" => summary["stage"]
        })

      Repo.insert!(%JournalEntry{
        hero_id: hero.id,
        entry_type: "construction_donation",
        text: text,
        created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
    end

    :ok
  rescue
    _ -> :ok
  end

  # ── C-3: Врата Обливиона — взнос в фонд экспедиции ───────────────────────────

  @doc "Взнос героя в фонд врат (золото сгорает). Награда — слава в вести и событие при закрытии."
  def gate_donate(conn, params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    amount = parse_amount(params["amount"])
    min_donation = 10

    cond do
      is_nil(hero) ->
        conn |> put_status(404) |> json(%{error: "hero_not_found"})

      is_nil(amount) or amount < min_donation ->
        conn |> put_status(400) |> json(%{error: "min_donation", min_donation: min_donation})

      true ->
        fresh = Repo.reload!(hero)

        if fresh.gold < amount do
          conn |> put_status(409) |> json(%{error: "not_enough_gold", gold: fresh.gold})
        else
          hero2 =
            fresh
            |> Ecto.Changeset.change(%{gold: fresh.gold - amount})
            |> Repo.update!()

          case Kernel.gate_donate(hero2.id, hero2.name, amount) do
            {:ok, summary, closed?} ->
              journal_gate_donation(hero2, amount, summary, closed?)
              json(conn, %{gates: summary, closed: closed?, gold: hero2.gold})

            {:error, :not_open} ->
              # возврат золота: врата схлопнулись между списанием и взносом (гонка с тиком)
              fresh2 = Repo.reload!(hero2)
              hero3 = fresh2 |> Ecto.Changeset.change(%{gold: fresh2.gold + amount}) |> Repo.update!()
              conn |> put_status(409) |> json(%{error: "gates_closed", gold: hero3.gold})

            {:error, _other} ->
              conn |> put_status(409) |> json(%{error: "gate_donate_failed"})
          end
        end
    end
  end

  defp journal_gate_donation(hero, amount, summary, closed?) do
    template =
      Repo.one(
        from t in NarrativeTemplate,
          where: t.template_type == "gate_donation" and t.is_active == true,
          order_by: fragment("random()"),
          limit: 1,
          select: t.text_template
      )

    if template do
      text =
        TemplateEngine.render_vars(template, %{
          "hero_name" => hero.name,
          "amount" => Integer.to_string(amount),
          "location" => summary["location_name"] || "далёкий холд",
          "fund" => Integer.to_string(summary["fund"] || 0),
          "status" => if(closed?, do: "врата запечатаны", else: "разлом всё ещё зияет")
        })

      Repo.insert!(%JournalEntry{
        hero_id: hero.id,
        entry_type: "gate_donation",
        text: text,
        created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
    end

    :ok
  rescue
    _ -> :ok
  end
end
