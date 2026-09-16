defmodule SeedGuildNews do
  @moduledoc "G-5: шаблоны вестей гильдий (идемпотентно)."

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate

  @news [
    {"guild_founded", [
      "⚔️ Знамя «{guild_name}» развевается над Скайримом — {leader} собирает соратников!",
      "Слухи из Вайтрана: {leader} основал(а) гильдию «{guild_name}». Кто разделит трапезу?",
      "Рог зовёт: «{guild_name}» ищет героев, чьи имена переживут саги.",
      "На двери таверны гвоздём нацарапано: «{guild_name}» объявляет набор."
    ]},
    {"guild_levelup", [
      "⚔️ «{guild_name}» {emblem} достигает {level} уровня — алтарь пылает, враги трепещут!",
      "Барды слагают: «{guild_name}» {emblem} усиливается до {level} уровня.",
      "«{guild_name}» {emblem}: {level} уровень. Клинки острее, знамя ярче.",
      "Весть из всех девяти холдов: «{guild_name}» {emblem} вступает в {level} уровень."
    ]},
    {"guild_feast", [
      "🍻 «{guild_name}» {emblem} справляет пир — {hours} ч рогов и вдохновения, опыт течёт рекой!",
      "Запах жареного кабана над «{guild_name}» {emblem}: {hours} ч пира, xp_member и певцы в голос.",
      "«{guild_name}» {emblem} открыли погреба: {hours} ч пиршества — мудрость приходит с элём.",
      "Весь холд слышит гул веселья: «{guild_name}» {emblem} пирует {hours} ч и молодеет духом."
    ]}
  ]

  {:ok, _} = Application.ensure_all_started(:tes_idle)

  {inserted, total} =
    Enum.reduce(@news, {0, 0}, fn {type, texts}, {ins, tot} ->
      existing = Repo.all(from t in NarrativeTemplate, where: t.template_type == ^type, select: t.text_template)

      new_count =
        Enum.reduce(texts, 0, fn text, acc ->
          if text in existing do
            acc
          else
            Repo.insert!(%NarrativeTemplate{
              template_type: type,
              text_template: text,
              source: "system",
              is_active: true
            })

            acc + 1
          end
        end)

      type_total = Repo.one(from t in NarrativeTemplate, where: t.template_type == ^type, select: count(t.id))
      {ins + new_count, tot + type_total}
    end)

  IO.puts("seed_guild_news: шаблонов +#{inserted}, всего #{total}")
  :ok
end
