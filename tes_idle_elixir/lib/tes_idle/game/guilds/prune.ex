defmodule TesIdle.Game.Guilds.Prune do
  @moduledoc "G-2: чистка хвоста чата — держим последние 500 сообщений на гильдию."

  import Ecto.Query
  alias TesIdle.Repo
  alias TesIdle.Schemas.GuildMessage

  @keep 500

  @doc "Удаляет сообщения гильдии сверх последних #{@keep}. Возвращает число удалённых."
  def prune(guild_id, keep \\ @keep) do
    {count, _} =
      from(m in GuildMessage,
        where:
          m.guild_id == ^guild_id and
            m.id not in subquery(
              from(k in GuildMessage,
                where: k.guild_id == ^guild_id,
                order_by: [desc: k.inserted_at],
                limit: ^keep,
                select: k.id
              )
            )
      )
      |> Repo.delete_all()

    count
  end
end
