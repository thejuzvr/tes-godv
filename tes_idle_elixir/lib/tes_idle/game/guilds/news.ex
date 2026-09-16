defmodule TesIdle.Game.Guilds.News do
  @moduledoc """
  G-5: вести гильдий — мировой фид событий (основание, уровни, достижения).
  Записи рендерятся из narrative_templates (guild_founded, guild_levelup, …);
  нет шаблона — записи нет (паттерн честных пустых состояний).
  """

  import Ecto.Query
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildNews, NarrativeTemplate}

  @doc "Вестей нет — записи нет. vars значения — только строки (render_vars)."
  def broadcast(template_type, guild_id, vars) when is_map(vars) do
    template =
      Repo.one(
        from t in NarrativeTemplate,
          where: t.template_type == ^template_type and t.source == "system" and t.is_active == true,
          order_by: fragment("RANDOM()"),
          limit: 1,
          select: t.text_template
      )

    case template do
      nil ->
        :skip

      text_template ->
        text =
          TesIdle.Game.Narrative.TemplateEngine.render_vars(text_template, vars)

        Repo.insert!(%GuildNews{guild_id: guild_id, template_type: template_type, text: text})
        {:ok, text}
    end
  rescue
    _ -> :skip
  end

  @doc "Последние вести фида (для Wiki)."
  def feed(limit \\ 50) do
    from(n in GuildNews,
      order_by: [desc: n.created_at],
      limit: ^limit,
      select: %{
        id: n.id,
        template_type: n.template_type,
        text: n.text,
        created_at: n.created_at
      }
    )
    |> Repo.all()
  end
end
