# C-1 «Часовня Девяти»: шаблоны журнала пожертвований (идемпотентно по {template_type, text}).
# Запуск: mix run priv/seed_construction.exs

alias TesIdle.Repo
alias TesIdle.Schemas.NarrativeTemplate
import Ecto.Query

templates = [
  # обычный тон
  "{hero_name} кладёт {amount} золота в фонд стройки: «{project}». Камень за камнем растёт дело Девяти.",
  "Ещё {amount} золота уходит в казну стройки «{project}». Каменщики кивают: дела идут.",
  "{hero_name} жертвует {amount} золота на «{project}» — вклад в общее дело.",
  # комичный тон
  "{hero_name} трясёт кошель над ящиком для пожертвований: {amount} золота звякнули о дно. Молитва принята.",
  "«{amount} золота на {project}!» — сказал {hero_name} так громко, что мимо проходивший жрец уронил кадило.",
  "{hero_name} жертвует {amount} золота на «{project}» и шёпотом просит Девяти списать это со счетов добрых дел."
]

inserted =
  Enum.reduce(templates, 0, fn text, acc ->
    exists =
      Repo.exists?(
        from t in NarrativeTemplate,
          where: t.template_type == "construction_donation" and t.text_template == ^text
      )

    if exists do
      acc
    else
      Repo.insert!(%NarrativeTemplate{
        template_type: "construction_donation",
        text_template: text,
        source: "system",
        is_active: true
      })

      acc + 1
    end
  end)

total =
  Repo.one(
    from t in NarrativeTemplate,
      select: count(t.id),
      where: t.template_type == "construction_donation"
  )

IO.puts("seed_construction: добавлено #{inserted}, всего шаблонов construction_donation: #{total}")
