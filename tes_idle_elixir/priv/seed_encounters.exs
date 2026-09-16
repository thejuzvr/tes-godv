import Ecto.Query

alias TesIdle.Repo
alias TesIdle.Schemas.NarrativeTemplate

# Dedicated safe encounter templates. Idempotent by {template_type, text_template}.
templates = [
  {"hero_encounter_initiator",
   "В {location_name} {hero_name} первым заметил героя по имени {other_hero_name}. Оба сделали вид, что именно так и планировали."},
  {"hero_encounter_initiator",
   "{hero_name} встретил {other_hero_name} в месте под названием {location_name} и вежливо уступил дорогу. В ту же сторону."},
  {"hero_encounter_initiator",
   "У вывески «{location_name}» {hero_name} кивнул герою {other_hero_name}. Вывеска, кажется, кивнула тоже."},
  {"hero_encounter_initiator",
   "{hero_name} начал встречу с {other_hero_name} уверенным приветствием. Эхо в {location_name} повторило его менее уверенно."},
  {"hero_encounter_initiator",
   "В {location_name} {hero_name} спросил у {other_hero_name} дорогу. Оба стояли прямо под указателем."},
  {"hero_encounter_initiator",
   "{hero_name} и {other_hero_name} столкнулись взглядами в {location_name}. Сапоги столкнулись следом."},
  {"hero_encounter_initiator",
   "{hero_name} приветствовал {other_hero_name} так торжественно, будто встреча «{encounter_kind}» входила в королевский протокол."},
  {"hero_encounter_initiator",
   "В {location_name} {hero_name} поделился с {other_hero_name} важной новостью: погода снова находится снаружи."},
  {"hero_encounter_counterpart",
   "В {location_name} к герою {hero_name} подошёл {other_hero_name}. Отступать было поздно: приветствие уже прозвучало."},
  {"hero_encounter_counterpart",
   "{hero_name} встретил {other_hero_name} в месте под названием {location_name} и мудро согласился, что это действительно место."},
  {"hero_encounter_counterpart",
   "У вывески «{location_name}» герой {hero_name} ответил на кивок {other_hero_name}. Вывеска осталась нейтральной."},
  {"hero_encounter_counterpart",
   "{other_hero_name} уверенно поприветствовал героя {hero_name}. Эхо в {location_name} воздержалось от комментариев."},
  {"hero_encounter_counterpart",
   "В {location_name} {other_hero_name} спросил у героя {hero_name} дорогу. Совет указателя победил единогласно."},
  {"hero_encounter_counterpart",
   "{hero_name} и {other_hero_name} разминулись в {location_name}, затем вернулись и разминулись ещё профессиональнее."},
  {"hero_encounter_counterpart",
   "Герой {hero_name} выдержал встречу «{encounter_kind}» с {other_hero_name} с достоинством и почти без жестикуляции."},
  {"hero_encounter_counterpart",
   "В {location_name} герой {hero_name} выслушал новость от {other_hero_name}: погода всё ещё находится снаружи."}
]

Enum.each(templates, fn {template_type, text_template} ->
  exists? =
    Repo.exists?(
      from template in NarrativeTemplate,
        where:
          template.template_type == ^template_type and
            template.text_template == ^text_template
    )

  unless exists? do
    Repo.insert!(%NarrativeTemplate{
      template_type: template_type,
      text_template: text_template,
      source: "system",
      is_active: true
    })
  end
end)

IO.puts("Encounter narratives seeded: #{length(templates)}")
