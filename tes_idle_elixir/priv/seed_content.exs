# Seed: каталог питомцев (15 видов) + каталог предметов (50 позиций), идемпотентно.
#
# Запуск: mix run priv/seed_content.exs   (входит в seed_all.exs)
#
# Питомцы: Pet.species — данные, не seed (вид живёт в Pets.species_list/0);
# здесь сидируем КАТАЛОГ видов в game_configs["pet_catalog"] для фронта/доки.
# Имена видов и пулы имён — в lib/tes_idle/game/pets.ex (источник правды).
#
# Предметы: 10 зелий (consumable) + 10 предметов (tool/material) + 10 хлама (junk)
# + 10 экипировки (body/head/legs/amulet/ring) + 10 оружия (weapon).
# Грабля сидов items: weight/speed_bonus float, reduce_hunger/reduce_fatigue/
# boost_morale/soul_restore NOT NULL — всегда задавать 0.0 явно.

alias TesIdle.Repo
alias TesIdle.Schemas.{Item, GameConfig}
alias TesIdle.Game.Pets

defmodule ContentSeed do
  import Ecto.Query

  # Поля предмета, синхронизируемые сидом. ВАЖНО: equip_slot/attack_bonus/
  # defense_bonus/hp_bonus/weight/speed_bonus должны быть здесь же — иначе
  # экипировка вставляется «пустышкой» (слот NULL, статы 0): автоэкип её
  # игнорирует, магазин продаёт за золото нулевой предмет (реальный кейс
  # первых 20 предметов каталога). НЕ NULL float'ы — 0.0 явно.
  @item_sync_fields [
    :item_type, :icon, :description, :rarity, :sell_price, :tags,
    :heal_hp, :heal_mp, :heal_sp, :reduce_hunger, :reduce_fatigue, :boost_morale,
    :buff_attack, :buff_duration_ticks, :soul_restore,
    :equip_slot, :attack_bonus, :defense_bonus, :hp_bonus, :weight, :speed_bonus,
  ]

  defp item_attrs(attrs) do
    %{
      name: attrs.name,
      item_type: attrs.item_type,
      icon: attrs.icon,
      description: Map.get(attrs, :description, ""),
      rarity: Map.get(attrs, :rarity, "common"),
      sell_price: Map.get(attrs, :price, 5),
      tags: Map.get(attrs, :tags, []),
      heal_hp: Map.get(attrs, :heal_hp, 0),
      heal_mp: Map.get(attrs, :heal_mp, 0),
      heal_sp: Map.get(attrs, :heal_sp, 0),
      reduce_hunger: Map.get(attrs, :reduce_hunger, 0.0),
      reduce_fatigue: Map.get(attrs, :reduce_fatigue, 0.0),
      boost_morale: Map.get(attrs, :boost_morale, 0.0),
      buff_attack: Map.get(attrs, :buff_attack, 0),
      buff_duration_ticks: Map.get(attrs, :buff_duration_ticks, 0),
      soul_restore: Map.get(attrs, :soul_restore, 0.0),
      equip_slot: Map.get(attrs, :equip_slot),
      attack_bonus: Map.get(attrs, :attack_bonus, 0),
      defense_bonus: Map.get(attrs, :defense_bonus, 0),
      hp_bonus: Map.get(attrs, :hp_bonus, 0),
      weight: Map.get(attrs, :weight, 0.1),
      speed_bonus: Map.get(attrs, :speed_bonus, 0.0),
    }
  end

  def ensure_item(attrs) do
    full = item_attrs(attrs)
    # CD-1: в dev-БД легаси-дубликаты имён («Кожаные сапоги» ×3) — any/nil,
    # не get_by! (MultipleResultsError валит весь сид).
    existing = Repo.one(from i in Item, where: i.name == ^attrs.name, limit: 1)

    if existing do
      existing
      |> Ecto.Changeset.change(Map.take(full, @item_sync_fields))
      |> Repo.update!()
    else
      full
      |> Map.put(:is_active, true)
      |> then(&Repo.insert!(struct(Item, &1)))
    end
  end

  def ensure_item!(%Item{} = item), do: item

  def ensure_config(key, value, description) do
    case Repo.get_by(GameConfig, key: key) do
      nil ->
        Repo.insert!(%GameConfig{
          key: key,
          value: Jason.encode!(value),
          description: description
        })

      cfg ->
        cfg
        |> Ecto.Changeset.change(value: Jason.encode!(value))
        |> Repo.update!()
    end
  end
end

# --- Питомцы: каталог видов -----------------------------------------------------
# Обычные 7: wolf/owl/cat/lizard/goat/fox/raven. Комичные 8: осталь­ные.
# species_icons берётся из Pets.species_icons() — единый источник правды.

pet_catalog =
  Pets.species_list()
  |> Enum.map(fn species ->
    %{
      "species" => species,
      "icon" => Map.get(Pets.species_icons(), species, "?"),
      "comical" => species in ["goose", "hedgehog", "moth", "rock", "turnip", "butter", "skeleton", "cheese"]
    }
  end)

ContentSeed.ensure_config(
  "pet_catalog",
  pet_catalog,
  "Каталог видов питомцев (обычные + комичные); источник правды — Pets.species_list/0"
)

IO.puts("pet_catalog: #{length(pet_catalog)} видов (комичных: #{Enum.count(pet_catalog, & &1["comical"])})")

# --- Зелья (consumable), 10 ------------------------------------------------------
# Эффекты: heal_hp/heal_mp/heal_sp/reduce_hunger/reduce_fatigue/boost_morale/
# buff_attack/buff_duration_ticks/soul_restore. NOT NULL поля — 0.0 явно.

potions = [
  %{name: "Зелье здоровья (большое)", item_type: "consumable", icon: "🧪", price: 45, description: "Красное, тёплое, пахнет летним сбором.", rarity: "uncommon", heal_hp: 80, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Зелье бодрости", item_type: "consumable", icon: "⚡", price: 35, description: "Снимает усталость одним глотком. Сердце колотится.", rarity: "common", heal_hp: 0, heal_sp: 40, reduce_fatigue: 35.0, reduce_hunger: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Зелье ярости", item_type: "consumable", icon: "🔥", price: 60, description: "Руки сами сжимают оружие крепче.", rarity: "uncommon", heal_hp: 0, buff_attack: 5, buff_duration_ticks: 5, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Настой валерьяны", item_type: "consumable", icon: "🫗", price: 20, description: "Для нервов. Работает и на героях, и на питомцах.", rarity: "common", heal_hp: 0, boost_morale: 15.0, reduce_hunger: 0.0, reduce_fatigue: 0.0, soul_restore: 0.0},
  %{name: "Противоядие", item_type: "consumable", icon: "🧴", price: 30, description: "Горькое. Яд выводит, настроение тоже.", rarity: "common", heal_hp: 15, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Эликсир души", item_type: "consumable", icon: "🔮", price: 70, description: "Сиреневая дымка внутри. Душа теплеет.", rarity: "rare", heal_hp: 0, soul_restore: 25.0, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0},
  %{name: "Малиновый морс", item_type: "consumable", icon: "🥤", price: 8, description: "Бабушкин рецепт. Голод утоляет, споры гасит.", rarity: "common", heal_hp: 5, reduce_hunger: 20.0, reduce_fatigue: 0.0, boost_morale: 5.0, soul_restore: 0.0},
  %{name: "Грибной отвар", item_type: "consumable", icon: "🍄", price: 12, description: "Пахнет лесом. Эффект — как повезёт.", rarity: "common", heal_hp: 10, heal_mp: 10, reduce_hunger: 15.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Медовуха старого Ноки", item_type: "consumable", icon: "🍯", price: 25, description: "Хмелит, лечит, разговоряет. Иногда всё сразу.", rarity: "uncommon", heal_hp: 20, boost_morale: 20.0, reduce_hunger: 0.0, reduce_fatigue: 0.0, soul_restore: 0.0},
  %{name: "Мороженое из Виндхельма", item_type: "consumable", icon: "🍦", price: 15, description: "Везли через всю провинцию. Почти не растаяло.", rarity: "uncommon", heal_hp: 0, boost_morale: 25.0, reduce_hunger: 10.0, reduce_fatigue: 0.0, soul_restore: 0.0},
]

Enum.each(potions, &ContentSeed.ensure_item/1)

# --- Предметы (tool/material), 10 -------------------------------------------------

tools = [
  %{name: "Точильный камень", item_type: "tool", icon: "🪨", price: 18, description: "Оружие любит заботу.", tags: ["tool"], rarity: "common"},
  %{name: "Верёвка", item_type: "tool", icon: "🪢", price: 14, description: "Десять метров спасения. И завязывания.", tags: ["tool"], rarity: "common"},
  %{name: "Факел", item_type: "tool", icon: "🕯️", price: 6, description: "Смолой пропитан, горит ровно.", tags: ["tool"], rarity: "common"},
  %{name: "Лопата", item_type: "tool", icon: "🪏", price: 22, description: "Копает клады. Чаще — ямы.", tags: ["tool"], rarity: "common"},
  %{name: "Картографический набор", item_type: "tool", icon: "🗺️", price: 40, description: "Пергамент, уголь, линейка. Путь станет короче.", tags: ["tool"], rarity: "uncommon"},
  %{name: "Ловушка для крабов", item_type: "tool", icon: "🦀", price: 16, description: "Плетёная, пахнет морем. Иногда работает.", tags: ["tool"], rarity: "common"},
  %{name: "Кузнечный молот", item_type: "tool", icon: "🔨", price: 35, description: "Тяжёлый, надёжный, звенит на весь квартал.", tags: ["tool"], rarity: "uncommon"},
  %{name: "Пустая бутыль", item_type: "material", icon: "🍾", price: 5, description: "Для зелий, росы или честного слова.", tags: ["component"], rarity: "common"},
  %{name: "Драконья чешуйка", item_type: "material", icon: "🐉", price: 120, description: "Тёплая на ощупь. Алхимики в conjure-пудре не признаются.", tags: ["component"], rarity: "epic"},
  %{name: "Эбонитовая пыль", item_type: "material", icon: "🌑", price: 55, description: "Чёрная, невесомая, слегка гудит.", tags: ["component"], rarity: "rare"},
]

Enum.each(tools, &ContentSeed.ensure_item/1)

# --- Хлам (junk), 10 ---------------------------------------------------------------

junk = [
  %{name: "Ложка без ручки", item_type: "junk", icon: "🥄", price: 1, description: "Ручка ушла своей жизнью.", rarity: "common"},
  %{name: "Носок (один)", item_type: "junk", icon: "🧦", price: 1, description: "Второй ищите в другом квесте.", rarity: "common"},
  %{name: "Пробка от бутылки", item_type: "junk", icon: "🍾", price: 1, description: "От бутылки, которую уже не найти.", rarity: "common"},
  %{name: "Смятое письмо", item_type: "junk", icon: "💌", price: 2, description: "«...дорогая, я остаюсь в Скайриме ещё на...»", rarity: "common"},
  %{name: "Куринная кость", item_type: "junk", icon: "🦴", price: 1, description: "Обглодана аккуратно, почти с уважением.", rarity: "common"},
  %{name: "Сломанный гребень", item_type: "junk", icon: "🪮", price: 1, description: "Зубьев четыре, судьбы — ноль.", rarity: "common"},
  %{name: "Камень, похожий на хлеб", item_type: "junk", icon: "🪨", price: 2, description: "Кусали двое. Оба жалеют.", rarity: "common"},
  %{name: "Мухобойка", item_type: "junk", icon: "🪰", price: 2, description: "Герой войны против мух. Отставлен по ранению.", rarity: "common"},
  %{name: "Сапог-утопленник", item_type: "junk", icon: "🥾", price: 2, description: "Выловлен из реки. Истории не подтвердил.", rarity: "common"},
  %{name: "Сундук (пустой)", item_type: "junk", icon: "📦", price: 3, description: "Сундук-обманщик: внутри ничего, зато сколько надежды.", rarity: "common"},
]

Enum.each(junk, &ContentSeed.ensure_item/1)

# --- Экипировка (body/head/legs/amulet/ring), 10 ------------------------------------
# weapon-слот отдельно ниже. NOT NULL float: weight/speed_bonus задавать явно.

armor = [
  %{name: "Стальная броня", item_type: "equipment", icon: "🛡️", price: 90, rarity: "uncommon", equip_slot: "body", attack_bonus: 0, defense_bonus: 18, hp_bonus: 0, weight: 9.0, speed_bonus: 0.0, description: "Звонкая, тяжёлая, надёжная."},
  %{name: "Доспех из костей дракона", item_type: "equipment", icon: "🐉", price: 400, rarity: "epic", equip_slot: "body", attack_bonus: 2, defense_bonus: 35, hp_bonus: 20, weight: 11.0, speed_bonus: 0.0, description: "Чешуя ещё помнит полёт."},
  %{name: "Стальной шлем", item_type: "equipment", icon: "⛑️", price: 30, rarity: "common", equip_slot: "head", attack_bonus: 0, defense_bonus: 8, hp_bonus: 0, weight: 3.0, speed_bonus: 0.0, description: "Держит удар и осанку."},
  %{name: "Шлем стражи Вайтрана", item_type: "equipment", icon: "🏰", price: 55, rarity: "uncommon", equip_slot: "head", attack_bonus: 0, defense_bonus: 11, hp_bonus: 5, weight: 3.5, speed_bonus: 0.0, description: "С изменённым гербом — стража не заметит."},
  %{name: "Стальные сапоги", item_type: "equipment", icon: "🥾", price: 28, rarity: "common", equip_slot: "legs", attack_bonus: 0, defense_bonus: 6, hp_bonus: 0, weight: 3.0, speed_bonus: 0.5, description: "Ступают громко, думают редко."},
  %{name: "Сапоги скорости", item_type: "equipment", icon: "👟", price: 85, rarity: "rare", equip_slot: "legs", attack_bonus: 0, defense_bonus: 5, hp_bonus: 0, weight: 1.5, speed_bonus: 3.0, description: "Ноги сами несут — проверено трижды."},
  %{name: "Амулет Стендарра", item_type: "equipment", icon: "📿", price: 75, rarity: "uncommon", equip_slot: "amulet", attack_bonus: 0, defense_bonus: 4, hp_bonus: 15, weight: 0.2, speed_bonus: 0.0, description: "Милосердие в холодном серебре."},
  %{name: "Амулет Талоса", item_type: "equipment", icon: "⚡", price: 110, rarity: "rare", equip_slot: "amulet", attack_bonus: 2, defense_bonus: 2, hp_bonus: 10, weight: 0.2, speed_bonus: 0.0, description: "«Ты теперь Талос», — шепчет он."},
  %{name: "Кольцо силы", item_type: "equipment", icon: "💪", price: 95, rarity: "rare", equip_slot: "ring", attack_bonus: 3, defense_bonus: 0, hp_bonus: 0, weight: 0.1, speed_bonus: 0.0, description: "Пальцы в хватке, враги — в страхе."},
  %{name: "Кольцо мудрости", item_type: "equipment", icon: "🎓", price: 90, rarity: "rare", equip_slot: "ring", attack_bonus: 0, defense_bonus: 3, hp_bonus: 8, weight: 0.1, speed_bonus: 0.0, description: "Знает больше, чем показывает."},
]

Enum.each(armor, &ContentSeed.ensure_item/1)

# --- Оружие (weapon), 10 --------------------------------------------------------------

weapons = [
  %{name: "Серебряный меч", item_type: "equipment", icon: "⚔️", price: 120, rarity: "rare", equip_slot: "weapon", attack_bonus: 14, defense_bonus: 0, hp_bonus: 0, weight: 4.0, speed_bonus: 0.0, description: "Против нежити — первое, второе и заключительное слово."},
  %{name: "Топор берсерка", item_type: "equipment", icon: "🪓", price: 135, rarity: "rare", equip_slot: "weapon", attack_bonus: 17, defense_bonus: 0, hp_bonus: 0, weight: 6.5, speed_bonus: 0.0, description: "Замах широкий — своих тоже задевает."},
  %{name: "Молот небес", item_type: "equipment", icon: "🔨", price: 210, rarity: "epic", equip_slot: "weapon", attack_bonus: 22, defense_bonus: 0, hp_bonus: 5, weight: 9.0, speed_bonus: 0.0, description: "После удара гномья кузня аплодирует."},
  %{name: "Лук длинной зимой", item_type: "equipment", icon: "🏹", price: 95, rarity: "uncommon", equip_slot: "weapon", attack_bonus: 12, defense_bonus: 0, hp_bonus: 0, weight: 2.0, speed_bonus: 1.0, description: "Тетива поёт — враги подпевают."},
  %{name: "Эльфийский лук", item_type: "equipment", icon: "🍃", price: 150, rarity: "rare", equip_slot: "weapon", attack_bonus: 15, defense_bonus: 0, hp_bonus: 0, weight: 1.5, speed_bonus: 2.0, description: "Лёгкий, как утренний туман в Глэмориин."},
  %{name: "Кинжал тени", item_type: "equipment", icon: "🗡️", price: 80, rarity: "uncommon", equip_slot: "weapon", attack_bonus: 9, defense_bonus: 0, hp_bonus: 0, weight: 0.8, speed_bonus: 2.5, description: "Скользит из рукава быстрее, чем мысль."},
  %{name: "Посох ученика", item_type: "equipment", icon: "🪄", price: 65, rarity: "common", equip_slot: "weapon", attack_bonus: 7, defense_bonus: 2, hp_bonus: 0, weight: 2.5, speed_bonus: 0.0, description: "Огненная стрела иногда получается с первого раза."},
  %{name: "Посох архимага", item_type: "equipment", icon: "✨", price: 260, rarity: "epic", equip_slot: "weapon", attack_bonus: 18, defense_bonus: 4, hp_bonus: 10, weight: 2.8, speed_bonus: 0.0, description: "Кристалл на конце — гнев древних."},
  %{name: "Секира стражника", item_type: "equipment", icon: "🪓", price: 45, rarity: "common", equip_slot: "weapon", attack_bonus: 10, defense_bonus: 0, hp_bonus: 0, weight: 5.5, speed_bonus: 0.0, description: "Уставная, казённая, честная."},
  %{name: "Меч из Небесной стали", item_type: "equipment", icon: "🌟", price: 320, rarity: "legendary", equip_slot: "weapon", attack_bonus: 25, defense_bonus: 3, hp_bonus: 10, weight: 3.8, speed_bonus: 1.0, description: "Кован в небесной кузнице. Один на поколение."},
]

Enum.each(weapons, &ContentSeed.ensure_item/1)

# --- CD-1: ШЛЕМЫ (head), 18 — по мотивам Skyrim: от тряпки до драконьей кости ----
# Слоты head раньше были только 2 из 50 предметов — теперь полноценная линейка.

helmets = [
  %{name: "Капюшон скитальца", item_type: "equipment", icon: "🧢", price: 8, rarity: "common", equip_slot: "head", attack_bonus: 0, defense_bonus: 2, hp_bonus: 0, weight: 0.4, speed_bonus: 0.0, description: "От дождя, солнца и лишних вопросов."},
  %{name: "Кожаная шапка", item_type: "equipment", icon: "🧢", price: 12, rarity: "common", equip_slot: "head", attack_bonus: 0, defense_bonus: 3, hp_bonus: 0, weight: 0.6, speed_bonus: 0.0, description: "Простая, тёплая, честная."},
  %{name: "Меховая шапка", item_type: "equipment", icon: "🎩", price: 18, rarity: "common", equip_slot: "head", attack_bonus: 0, defense_bonus: 3, hp_bonus: 2, weight: 0.9, speed_bonus: 0.0, description: "Мороз бранится, но не проходит."},
  %{name: "Железный шлем", item_type: "equipment", icon: "⛑️", price: 22, rarity: "common", equip_slot: "head", attack_bonus: 0, defense_bonus: 6, hp_bonus: 0, weight: 2.5, speed_bonus: 0.0, description: "Казённого образца. Как у всех — зато живых."},
  %{name: "Скрытый капюшон", item_type: "equipment", icon: "🕵️", price: 40, rarity: "uncommon", equip_slot: "head", attack_bonus: 1, defense_bonus: 3, hp_bonus: 0, weight: 0.5, speed_bonus: 1.0, description: "Тени любят тех, кто их носит."},
  %{name: "Шлем стражи Рифтена", item_type: "equipment", icon: "🪖", price: 48, rarity: "uncommon", equip_slot: "head", attack_bonus: 0, defense_bonus: 9, hp_bonus: 3, weight: 3.2, speed_bonus: 0.0, description: "Запах мёда и правосудия."},
  %{name: "Имперский шлем", item_type: "equipment", icon: "🪖", price: 52, rarity: "uncommon", equip_slot: "head", attack_bonus: 0, defense_bonus: 10, hp_bonus: 2, weight: 3.4, speed_bonus: 0.0, description: "Дисциплина в каждом клёпане."},
  %{name: "Шлем стражи Солитьюда", item_type: "equipment", icon: "🏰", price: 58, rarity: "uncommon", equip_slot: "head", attack_bonus: 0, defense_bonus: 10, hp_bonus: 4, weight: 3.4, speed_bonus: 0.0, description: "С орденской эмблемой — для парадов и понедельников."},
  %{name: "Стальной рогатый шлем", item_type: "equipment", icon: "🪖", price: 65, rarity: "uncommon", equip_slot: "head", attack_bonus: 1, defense_bonus: 11, hp_bonus: 0, weight: 3.8, speed_bonus: 0.0, description: "Рога для красоты. И чтобы вешать вещи."},
  %{name: "Шлем Клинков", item_type: "equipment", icon: "⚔️", price: 85, rarity: "rare", equip_slot: "head", attack_bonus: 2, defense_bonus: 12, hp_bonus: 3, weight: 3.6, speed_bonus: 0.0, description: "Орденская сталь с драконьим гребнем."},
  %{name: "Эльфийский шлем", item_type: "equipment", icon: "🍃", price: 95, rarity: "rare", equip_slot: "head", attack_bonus: 1, defense_bonus: 12, hp_bonus: 4, weight: 1.8, speed_bonus: 0.5, description: "Лёгок, как презрение эльфа к железу."},
  %{name: "Шлем Стражи Рассвета", item_type: "equipment", icon: "🌅", price: 105, rarity: "rare", equip_slot: "head", attack_bonus: 2, defense_bonus: 13, hp_bonus: 5, weight: 3.6, speed_bonus: 0.0, description: "Свет в гравировке не тускнеет."},
  %{name: "Шлем из костяного пласта", item_type: "equipment", icon: "🦴", price: 120, rarity: "rare", equip_slot: "head", attack_bonus: 2, defense_bonus: 14, hp_bonus: 6, weight: 4.2, speed_bonus: 0.0, description: "Солстхейм помнит каждого, кто носил такое."},
  %{name: "Оркский шлем", item_type: "equipment", icon: "🛠️", price: 130, rarity: "rare", equip_slot: "head", attack_bonus: 3, defense_bonus: 15, hp_bonus: 3, weight: 4.5, speed_bonus: 0.0, description: "Кован орк-кузнецом в Малахате. Орки не жалуются."},
  %{name: "Стеклянный шлем", item_type: "equipment", icon: "💚", price: 170, rarity: "epic", equip_slot: "head", attack_bonus: 2, defense_bonus: 16, hp_bonus: 5, weight: 2.2, speed_bonus: 1.0, description: "Малахит размера головы. Хрупок на вид — веками крепок."},
  %{name: "Эбонитовый шлем", item_type: "equipment", icon: "🖤", price: 220, rarity: "epic", equip_slot: "head", attack_bonus: 3, defense_bonus: 19, hp_bonus: 8, weight: 4.8, speed_bonus: 0.0, description: "Вулканическая тьма в форме шлема."},
  %{name: "Драконий шлем", item_type: "equipment", icon: "🐉", price: 290, rarity: "epic", equip_slot: "head", attack_bonus: 3, defense_bonus: 22, hp_bonus: 12, weight: 5.0, speed_bonus: 0.0, description: "Чешуя ещё тёплая. Дракон против."},
  %{name: "Даэдрический шлем", item_type: "equipment", icon: "👹", price: 380, rarity: "legendary", equip_slot: "head", attack_bonus: 4, defense_bonus: 26, hp_bonus: 15, weight: 5.5, speed_bonus: 0.0, description: "Сердце даэдра внутри. Слышно, как бьётся."},
]

Enum.each(helmets, &ContentSeed.ensure_item/1)

# --- CD-1: броня и аксессуары (body/legs/amulet/ring), 14 --------------------------

armor2 = [
  %{name: "Стёганый дублет", item_type: "equipment", icon: "🧥", price: 25, rarity: "common", equip_slot: "body", attack_bonus: 0, defense_bonus: 8, hp_bonus: 2, weight: 2.5, speed_bonus: 0.5, description: "Ткань против стали — неравный бой, но живучий."},
  %{name: "Охотничья куртка", item_type: "equipment", icon: "🧥", price: 35, rarity: "common", equip_slot: "body", attack_bonus: 1, defense_bonus: 9, hp_bonus: 0, weight: 2.2, speed_bonus: 1.0, description: "Пахнет хвоей и удачей."},
  %{name: "Кожаный доспех", item_type: "equipment", icon: "🥋", price: 60, rarity: "uncommon", equip_slot: "body", attack_bonus: 0, defense_bonus: 14, hp_bonus: 4, weight: 4.0, speed_bonus: 0.5, description: "Скрипит, но прикрывает."},
  %{name: "Шкурка снежного медведя", item_type: "equipment", icon: "🐻", price: 110, rarity: "uncommon", equip_slot: "body", attack_bonus: 0, defense_bonus: 16, hp_bonus: 10, weight: 7.0, speed_bonus: 0.0, description: "Медведь изменил мнение о героях. Поздно."},
  %{name: "Эльфийская кольчуга", item_type: "equipment", icon: "🍃", price: 180, rarity: "rare", equip_slot: "body", attack_bonus: 1, defense_bonus: 20, hp_bonus: 8, weight: 5.5, speed_bonus: 1.0, description: "Кольца сплетены тоньше интриг."},
  %{name: "Драконья чешуя (жилет)", item_type: "equipment", icon: "🐉", price: 340, rarity: "epic", equip_slot: "body", attack_bonus: 2, defense_bonus: 28, hp_bonus: 16, weight: 8.0, speed_bonus: 0.0, description: "Легче, чем выглядит. Серьёзнее, чем нужно."},
  %{name: "Меховые штаны", item_type: "equipment", icon: "👖", price: 20, rarity: "common", equip_slot: "legs", attack_bonus: 0, defense_bonus: 4, hp_bonus: 3, weight: 1.8, speed_bonus: 0.0, description: "Зима отменяется."},
  %{name: "Кожаные сапоги", item_type: "equipment", icon: "🥾", price: 30, rarity: "common", equip_slot: "legs", attack_bonus: 0, defense_bonus: 5, hp_bonus: 0, weight: 1.6, speed_bonus: 0.5, description: "Тысяча вёрст — средний ресурс."},
  %{name: "Сапоги странника", item_type: "equipment", icon: "🥾", price: 55, rarity: "uncommon", equip_slot: "legs", attack_bonus: 0, defense_bonus: 6, hp_bonus: 2, weight: 1.4, speed_bonus: 1.5, description: "Дорога становится короче. Проверено."},
  %{name: "Амулет Дибеллы", item_type: "equipment", icon: "📿", price: 70, rarity: "uncommon", equip_slot: "amulet", attack_bonus: 0, defense_bonus: 2, hp_bonus: 8, weight: 0.2, speed_bonus: 0.0, description: "Красота спасёт мир. И владельца."},
  %{name: "Амулет Мары", item_type: "equipment", icon: "💍", price: 80, rarity: "uncommon", equip_slot: "amulet", attack_bonus: 0, defense_bonus: 3, hp_bonus: 12, weight: 0.2, speed_bonus: 0.0, description: "Любовь и милосердие в маленькой оправе."},
  %{name: "Амулет Кинарет", item_type: "equipment", icon: "🌤️", price: 130, rarity: "rare", equip_slot: "amulet", attack_bonus: 1, defense_bonus: 5, hp_bonus: 14, weight: 0.2, speed_bonus: 0.0, description: "Небо покровительствует носителю."},
  %{name: "Кольцо ветра", item_type: "equipment", icon: "💫", price: 100, rarity: "rare", equip_slot: "ring", attack_bonus: 1, defense_bonus: 1, hp_bonus: 0, weight: 0.1, speed_bonus: 2.0, description: "Ноги почти не касаются земли."},
  %{name: "Кольцо крови", item_type: "equipment", icon: "🩸", price: 150, rarity: "epic", equip_slot: "ring", attack_bonus: 5, defense_bonus: 0, hp_bonus: -5, weight: 0.1, speed_bonus: 0.0, description: "Сила за счёт жизни. Вампиры одобряют."},
]

Enum.each(armor2, &ContentSeed.ensure_item/1)

# --- CD-1: оружие (weapon), 16 ------------------------------------------------------

weapons2 = [
  %{name: "Железный меч", item_type: "equipment", icon: "⚔️", price: 25, rarity: "common", equip_slot: "weapon", attack_bonus: 8, defense_bonus: 0, hp_bonus: 0, weight: 3.5, speed_bonus: 0.0, description: "Простой, как утро ополченца."},
  %{name: "Дубина", item_type: "equipment", icon: "🏏", price: 15, rarity: "common", equip_slot: "weapon", attack_bonus: 7, defense_bonus: 0, hp_bonus: 0, weight: 4.0, speed_bonus: 0.0, description: "Философия гиганта в карманном формате."},
  %{name: "Кинжал писца", item_type: "equipment", icon: "🖋️", price: 20, rarity: "common", equip_slot: "weapon", attack_bonus: 5, defense_bonus: 0, hp_bonus: 0, weight: 0.5, speed_bonus: 1.5, description: "Им подписывают. Режут — по необходимости."},
  %{name: "Охотничий лук", item_type: "equipment", icon: "🏹", price: 40, rarity: "common", equip_slot: "weapon", attack_bonus: 9, defense_bonus: 0, hp_bonus: 0, weight: 1.8, speed_bonus: 0.5, description: "Каждая стрела — ужин."},
  %{name: "Морозный клинок", item_type: "equipment", icon: "❄️", price: 140, rarity: "rare", equip_slot: "weapon", attack_bonus: 16, defense_bonus: 0, hp_bonus: 0, weight: 3.6, speed_bonus: 0.0, description: "Раны холодные, обиды ещё холоднее."},
  %{name: "Меч стражи", item_type: "equipment", icon: "⚔️", price: 70, rarity: "uncommon", equip_slot: "weapon", attack_bonus: 12, defense_bonus: 1, hp_bonus: 0, weight: 3.8, speed_bonus: 0.0, description: "Выдан со склада. Возвращён с боя."},
  %{name: "Боевой молот", item_type: "equipment", icon: "🔨", price: 100, rarity: "uncommon", equip_slot: "weapon", attack_bonus: 15, defense_bonus: 0, hp_bonus: 0, weight: 8.0, speed_bonus: 0.0, description: "Аргумент весом в восемь фунтов."},
  %{name: "Двемерский кинжал", item_type: "equipment", icon: "⚙️", price: 160, rarity: "rare", equip_slot: "weapon", attack_bonus: 14, defense_bonus: 2, hp_bonus: 0, weight: 1.0, speed_bonus: 2.0, description: "Механизм древних всё ещё работает."},
  %{name: "Топор Ульфберта", item_type: "equipment", icon: "🪓", price: 175, rarity: "rare", equip_slot: "weapon", attack_bonus: 19, defense_bonus: 0, hp_bonus: 3, weight: 6.0, speed_bonus: 0.0, description: "Клеймо мастера на обухе. И пара зарубок на памяти."},
  %{name: "Посох бури", item_type: "equipment", icon: "🌩️", price: 190, rarity: "rare", equip_slot: "weapon", attack_bonus: 17, defense_bonus: 3, hp_bonus: 5, weight: 2.8, speed_bonus: 0.0, description: "Молния по расписанию. Почти."},
  %{name: "Эбонитовый клинок", item_type: "equipment", icon: "🖤", price: 250, rarity: "epic", equip_slot: "weapon", attack_bonus: 21, defense_bonus: 2, hp_bonus: 4, weight: 4.2, speed_bonus: 0.5, description: "Тьма, которой придали форму."},
  %{name: "Стеклянная сабля", item_type: "equipment", icon: "💚", price: 210, rarity: "epic", equip_slot: "weapon", attack_bonus: 20, defense_bonus: 0, hp_bonus: 0, weight: 2.0, speed_bonus: 1.5, description: "Режет воздух с хрустальным звоном."},
  %{name: "Драконий костяной молот", item_type: "equipment", icon: "🐉", price: 300, rarity: "epic", equip_slot: "weapon", attack_bonus: 24, defense_bonus: 0, hp_bonus: 8, weight: 9.5, speed_bonus: 0.0, description: "Кости дракона служат делу героя."},
  %{name: "Клинок Рассвета", item_type: "equipment", icon: "🌅", price: 340, rarity: "legendary", equip_slot: "weapon", attack_bonus: 26, defense_bonus: 3, hp_bonus: 8, weight: 3.9, speed_bonus: 0.5, description: "Нежить узнаёт его издалека. И уходит."},
  %{name: "Разрушитель Черепов", item_type: "equipment", icon: "💀", price: 360, rarity: "legendary", equip_slot: "weapon", attack_bonus: 28, defense_bonus: 0, hp_bonus: 5, weight: 10.0, speed_bonus: 0.0, description: "Имя говорит само. Черепа подтверждают."},
  %{name: "Найтингейл", item_type: "equipment", icon: "🌑", price: 400, rarity: "legendary", equip_slot: "weapon", attack_bonus: 27, defense_bonus: 4, hp_bonus: 6, weight: 1.2, speed_bonus: 2.0, description: "Клинок ночи: неслышен, неизбежен."},
]

Enum.each(weapons2, &ContentSeed.ensure_item/1)

# --- CD-1: расходники (consumable), 10 ----------------------------------------------

potions2 = [
  %{name: "Зелье здоровья (малое)", item_type: "consumable", icon: "🧪", price: 18, description: "Розовое, скромное, работает.", rarity: "common", heal_hp: 35, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Зелье маны", item_type: "consumable", icon: "🧿", price: 30, description: "Синее сияние в горле. Мысли проясняются.", rarity: "common", heal_hp: 0, heal_mp: 45, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Отвар от голода", item_type: "consumable", icon: "🍲", price: 10, description: "Густой, как обещание трактирщика.", rarity: "common", heal_hp: 5, reduce_hunger: 35.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Бальзам от усталости", item_type: "consumable", icon: "🧴", price: 28, description: "Втирать в ноги. Ноги скажут спасибо.", rarity: "common", heal_hp: 0, reduce_fatigue: 45.0, reduce_hunger: 0.0, boost_morale: 5.0, soul_restore: 0.0},
  %{name: "Эль из Рорикстеда", item_type: "consumable", icon: "🍺", price: 12, description: "Местная гордость. Пьётся быстрее, чем заканчивается.", rarity: "common", heal_hp: 5, boost_morale: 18.0, reduce_hunger: 8.0, reduce_fatigue: 0.0, soul_restore: 0.0},
  %{name: "Ягодный настой", item_type: "consumable", icon: "🍹", price: 15, description: "Можжевельник и терпение.", rarity: "common", heal_hp: 8, heal_mp: 8, reduce_hunger: 12.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Зелье ярости (двойное)", item_type: "consumable", icon: "🔥", price: 95, description: "Дозировка для очень плохого дня.", rarity: "rare", heal_hp: 0, buff_attack: 8, buff_duration_ticks: 5, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0},
  %{name: "Плод праздника", item_type: "consumable", icon: "🍎", price: 22, description: "Золотое яблоко с ярмарки. Не спрашивай, почему золотое.", rarity: "uncommon", heal_hp: 25, boost_morale: 15.0, reduce_hunger: 15.0, reduce_fatigue: 0.0, soul_restore: 0.0},
  %{name: "Дымная эссенция", item_type: "consumable", icon: "💜", price: 85, description: "Душа теплеет и слегка дымится.", rarity: "rare", heal_hp: 0, soul_restore: 40.0, reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0},
  %{name: "Суп стражника", item_type: "consumable", icon: "🥣", price: 6, description: "Казённый рецепт: вода, репа, дисциплина.", rarity: "common", heal_hp: 8, reduce_hunger: 25.0, reduce_fatigue: 5.0, boost_morale: 0.0, soul_restore: 0.0},
]

Enum.each(potions2, &ContentSeed.ensure_item/1)

# --- CD-1: материалы и инструменты (tool/material), 8 -------------------------------

tools2 = [
  %{name: "Шкура волка", item_type: "material", icon: "🐺", price: 20, description: "Тёплая, дырявая — со следами работы.", tags: ["material"], rarity: "common"},
  %{name: "Кость мамонта", item_type: "material", icon: "🦴", price: 45, description: "Тяжёлая, древняя, заслуженная.", tags: ["material"], rarity: "uncommon"},
  %{name: "Двемерский шестерень", item_type: "material", icon: "⚙️", price: 60, description: "Машина умерла — деталь жива.", tags: ["material"], rarity: "uncommon"},
  %{name: "Золотой слиток", item_type: "material", icon: "🪙", price: 120, description: "Тяжелеет в руке и в мыслях.", tags: ["material"], rarity: "rare"},
  %{name: "Свеча отворота", item_type: "tool", icon: "🕯️", price: 35, description: "Горит синим. Отводит взгляд. Или наоборот.", tags: ["tool"], rarity: "uncommon"},
  %{name: "Полевая аптечка", item_type: "tool", icon: "🧰", price: 50, description: "Бинты, нитки, шило. Всё для полевой медицины.", tags: ["tool"], rarity: "uncommon"},
  %{name: "Отмычки (набор)", item_type: "tool", icon: "🗝️", price: 30, description: "Пять штук. Меньше пяти — не набор.", tags: ["tool"], rarity: "common"},
  %{name: "Тигель алхимика", item_type: "tool", icon: "⚗️", price: 70, description: "Для отваров, настоек и подозрительных экспериментов.", tags: ["tool"], rarity: "uncommon"},
]

Enum.each(tools2, &ContentSeed.ensure_item/1)

IO.puts("seed_content: #{length(potions) + length(potions2)} зелий + #{length(tools) + length(tools2)} предметов + #{length(junk)} хлама + #{length(armor) + length(armor2) + length(helmets)} экипировки + #{length(weapons) + length(weapons2)} оружия")
