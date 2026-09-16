import Ecto.Query

alias TesIdle.Repo
alias TesIdle.Schemas.{GuildNews, NarrativeTemplate}

counts =
  from(t in NarrativeTemplate, where: like(t.template_type, "guild%"), group_by: t.template_type, select: {t.template_type, count(t.id)})
  |> Repo.all()

IO.inspect(counts, label: "COUNTS")

news =
  from(n in GuildNews, select: {n.template_type, n.text})
  |> Repo.all()

IO.inspect(news, label: "NEWS")

:ok
