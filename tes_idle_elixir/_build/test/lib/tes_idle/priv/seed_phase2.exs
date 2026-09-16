# Seed Phase 2: предметы активностей + нарративные шаблоны (идемпотентно)
#
# Запуск: mix run priv/seed_phase2.exs
#
# A-1: item.tags (fish/herb/component/lockpick)
# A-6: narrative_templates для fishing/gather/steal/break_in/jail/pet_care
#      + переменные {fish_name}, {herb_name}, {pet_name}, {witness_name}, {fine_gold}

alias TesIdle.Repo
alias TesIdle.Schemas.{Item, NarrativeTemplate}

defmodule Phase2Seed do
  import Ecto.Query

  def ensure_item(attrs) do
    existing = Repo.get_by(Item, name: attrs.name)

    if existing do
      existing
      |> Ecto.Changeset.change(%{tags: attrs.tags, item_type: attrs.item_type, icon: attrs.icon})
      |> Repo.update!()
    else
      Repo.insert!(%Item{
        name: attrs.name,
        item_type: attrs.item_type,
        icon: attrs.icon,
        description: attrs.description || "",
        sell_price: attrs.price || 5,
        tags: attrs.tags,
        is_active: true,
      })
    end
  end

  def ensure_template(type, text, source \\ "system") do
    exists =
      Repo.exists?(
        from t in NarrativeTemplate,
          where: t.template_type == ^type and t.text_template == ^text and t.source == ^source
      )

    unless exists do
      Repo.insert!(%NarrativeTemplate{
        template_type: type,
        text_template: text,
        source: source,
        is_active: true,
        location_id: nil,
      })
    end
  end
end

# --- A-1: предметы активностей -----------------------------------------------

items = [
  %{name: "Речная рыба", item_type: "consumable", icon: "🐟", tags: ["fish", "food"], price: 4, description: "Свежая, ещё пахнет рекой."},
  %{name: "Ловкая форель", item_type: "consumable", icon: "🐠", tags: ["fish", "food"], price: 7, description: "Бьётся в руках так, что мало не покажется."},
  %{name: "Серебристая плотва", item_type: "consumable", icon: "🐡", tags: ["fish", "food"], price: 5, description: "Чешуя переливается на солнце."},
  %{name: "Пучок лаванды", item_type: "material", icon: "🌿", tags: ["herb", "component"], price: 3, description: "Пахнет покоем и тихими вечерами."},
  %{name: "Можжевеловые ягоды", item_type: "material", icon: "🫐", tags: ["herb", "component"], price: 3, description: "Горсть синих ягод, хороши в настой."},
  %{name: "Светящийся мох", item_type: "material", icon: "🟢", tags: ["herb", "component"], price: 12, description: "Слабо светится в темноте подземелий."},
  %{name: "Корень женьшеня", item_type: "material", icon: "🥕", tags: ["herb", "component"], price: 15, description: "Редкий корень, целители отрывают с руками."},
  %{name: "Отмычка", item_type: "tool", icon: "🗝️", tags: ["lockpick"], price: 10, description: "Тонкая, гибкая, надёжная. Пока не сломается."},
]

Enum.each(items, &Phase2Seed.ensure_item/1)

# --- A-6: нарративные шаблоны ---------------------------------------------------

fishing = [
  "Поплавок дрогнул — {hero_name} подсёк и вытащил {fish_name}. Улов!",
  "Час тишины у воды, и вот: {fish_name} бьётся в ладонях. {hero_name} доволен.",
  "{hero_name} сменил наживку в третий раз — и наконец {fish_name} на крючке.",
  "Рассветный туман, тихая вода, {fish_name} в корзине. Простые радости.",
  "Клёв был вялый, но {hero_name} дождался: {fish_name} отправляется в котёл.",
  "Мимо проплыло бревно, потом ботинок, потом — {fish_name}. Повезло.",
]

gather = [
  "{hero_name} собрал {herb_name} — аккуратно, сохранив корни.",
  "На опушке нашлось {herb_name}. Алхимики не останутся в обиде.",
  "{hero_name} продирался через заросли и набрал {herb_name}.",
  "Пока другие ищут беды, {hero_name} находит {herb_name}. Тоже прибыль.",
  "{herb_name} прятался под старым пнём, но {hero_name} знал, где искать.",
]

steal = [
  "Ловкий движок — и {stolen_gold} золота перекочевали в карман {hero_name}. Никто не заметил.",
  "{hero_name} слился с толпой. В кармане — {stolen_gold} золота, на душе — лёгкость.",
  "Кошелёк зазевавшегося горожанина сам прыгнул в руку {hero_name}. {stolen_gold} золота!",
  "{witness_name} отвернулся ровно на миг — этого хватило {hero_name}.",
]

steal_spotted = [
  "«Вор!» — крикнул {witness_name}. {hero_name} исчез в переулке, но лицо запомнили.",
  "{witness_name} заметил слишком много. Придётся уходить быстро: +{bounty_gold} золота к награде.",
  "Собака залаяла, {witness_name} обернулся. {hero_name} ретировался без добычи.",
  "Неудачный момент: {witness_name} оказался зорче, чем выглядел. Награда за голову выросла на {bounty_gold}.",
]

steal_caught = [
  "{witness_name} поймал {hero_name} за руку. Штраф: {fine_gold} золота.",
  "Стража оказалась ближе, чем думал {hero_name}. {fine_gold} золота ушли в казну.",
  "«Ну-ну, кошельки не ваши» — {witness_name} ткнул пальцем. {fine_gold} золота штрафа.",
]

break_in_ok = [
  "Замок щёлкнул — {hero_name} внутри. Добыча: {stolen_gold} золота.",
  "Отмычка справилась, {hero_name} справился. {stolen_gold} золота нашли нового хозяина.",
  "Подвал, сундук, {stolen_gold} золота — и ни одной души вокруг. Работка мечты.",
  "Дверь поддалась с третьей попытки. {hero_name} вынес оттуда {stolen_gold} золота и хорошее настроение.",
]

break_in_trap = [
  "Щелчок, свист — ловушка! {hero_name} качнулся от раны в {trap_hp} HP.",
  "Иглы из стены задели {hero_name}: −{trap_hp} HP. Но дверь он всё-таки вскрыл... нет, не вскрыл.",
  "Старая растяжка сработала как часы. {hero_name} отшатнулся, потеряв {trap_hp} HP.",
]

break_in_noise = [
  "Грохот на весь квартал. {witness_name} уже бежит за стражей.",
  "Отмычка сломалась с таким звоном, что проснулся весь дом. {witness_name} выходит на крыльцо.",
  "Слишком громко. {witness_name} поднял тревогу — награда за голову подросла на {bounty_gold}.",
]

jail = [
  "День {jail_ticks}: {hero_name} отсиживает за {jail_reason}. Баланда, лавка, мысли о воле.",
  "Решётка, солома, {jail_reason}. {hero_name} считает трещины в потолке.",
  "Стражник принёс баланду. {hero_name} думает о своём и о {jail_reason}.",
  "«Ещё пару дней» — говорит стража. {hero_name} кивает и ложится спать.",
  "Тюремный повар назвал своё варево «утешением». {hero_name} просит утешения поменьше.",
  "{hero_name} выцарапал на стене счёт побед над мухами. Табло: 47:39, победа за мухами.",
  "Сосед по камере торгует соломой по спекулятивной цене. {hero_name} ведёт переговоры за {jail_reason}.",
  "Стража дважды перепутала камеру и дважды извинилась. {hero_name} почти чувствует себя дома.",
  "В камере нет ни окна, ни стула, ни надежды — зато есть мышь по имени Хват. {hero_name} счёл это справедливым обменом за {jail_reason}.",
  "{hero_name} нацарапал жалобу на решётке. Решётка оставила жалобу без ответа.",
  "«За хорошее поведение дадим метлу» — сказал стражник. {hero_name} взял метлу и стал главным по чистоте камеры.",
  "Паук в углу молчит уже третий час. {hero_name} и паук уважают молчание друг друга.",
]

pet_care = [
  "{hero_name} {pet_care_kind} своего питомца — {pet_name} доволен.",
  "{pet_name} мурчит/ворчит от удовольствия: {hero_name} {pet_care_kind}.",
  "Уход за {pet_name}: лояльность {pet_loyalty}%. Хороший хозяин.",
  "{hero_name} {pet_care_kind} — и {pet_name} виляет хвостом так, что едва не свалил ведро.",
]

# S-3: «Новости мира» (ambient-записи о событиях ядра мира)
world_news = [
  "Слухи по дорогам: {event}. Стража говорит, {event} — не к добру.",
  "Караванщики принесли весть: {event}. Хорошие люди советуют не совать нос.",
  "В тавернах только об одном и говорят: {event}. Меняется земля — меняются и судьбы.",
]

Enum.each(fishing, &Phase2Seed.ensure_template("fishing", &1))
Enum.each(gather, &Phase2Seed.ensure_template("gather", &1))
Enum.each(steal, &Phase2Seed.ensure_template("steal", &1))
Enum.each(steal_spotted, &Phase2Seed.ensure_template("steal", &1))
Enum.each(steal_caught, &Phase2Seed.ensure_template("steal", &1))
Enum.each(break_in_ok, &Phase2Seed.ensure_template("break_in", &1))
Enum.each(break_in_trap, &Phase2Seed.ensure_template("break_in", &1))
Enum.each(break_in_noise, &Phase2Seed.ensure_template("break_in", &1))
Enum.each(jail, &Phase2Seed.ensure_template("jail", &1))
Enum.each(pet_care, &Phase2Seed.ensure_template("pet_care", &1))
Enum.each(world_news, &Phase2Seed.ensure_template("world_news", &1))

IO.puts("Phase 2 seed: #{length(items)} items + templates ok (incl. world_news)")
