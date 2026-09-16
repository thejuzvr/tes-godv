// Общие данные мастерской нарративов: типы шаблонов, словник переменных, примеры.
// Используется страницей NarrativesPage и админкой (AdminPage).

// ─── Типы шаблонов (полный список активных типов, сгруппированы по смыслу) ──
export const TEMPLATE_TYPE_GROUPS: { group: string; types: { id: string; label: string }[] }[] = [
  {
    group: "Бой",
    types: [
      { id: "combat_start", label: "Бой: начало" },
      { id: "combat_result", label: "Бой: итог" },
      { id: "hero_victory", label: "Бой: победа" },
      { id: "hero_defeat", label: "Бой: поражение" },
      { id: "combat_defeat", label: "Бой: сокрушительное поражение" },
      { id: "enemy_ambush", label: "Засада" },
      { id: "spot_bandits", label: "Заметить бандитов" },
    ],
  },
  {
    group: "Дорога",
    types: [
      { id: "travel", label: "Путешествие" },
      { id: "travel_road", label: "Дорога" },
      { id: "travel_shortcut", label: "Короткий путь" },
      { id: "leave_city", label: "Покинуть город" },
      { id: "enter_city", label: "Войти в город" },
      { id: "bad_weather", label: "Непогода" },
      { id: "avoid_danger", label: "Избегание опасности" },
      { id: "search_danger", label: "Поиск опасности" },
    ],
  },
  {
    group: "Исследование и находки",
    types: [
      { id: "explore", label: "Исследование" },
      { id: "discover_ruin", label: "Найти руины" },
      { id: "discover_treasure", label: "Сокровище" },
      { id: "find_loot", label: "Найти добычу" },
      { id: "loot", label: "Добыча" },
      { id: "find_abandoned_cart", label: "Брошенная телега" },
      { id: "find_tracks", label: "Следы" },
      { id: "notice_tracks", label: "Заметить следы" },
      { id: "hear_river", label: "Шум реки" },
      { id: "hear_birds", label: "Пение птиц" },
      { id: "smell_flowers", label: "Цветы" },
      { id: "equip", label: "Экипировка" },
    ],
  },
  {
    group: "Отдых и мысли",
    types: [
      { id: "rest", label: "Отдых" },
      { id: "rest_by_fire", label: "Отдых у костра" },
      { id: "sleep_in_inn", label: "Сон в таверне" },
      { id: "dream", label: "Сон: сновидение" },
      { id: "thought", label: "Мысли" },
      { id: "feel_confident", label: "Уверенность" },
    ],
  },
  {
    group: "Общество и торговля",
    types: [
      { id: "social", label: "Общение" },
      { id: "meet_merchant", label: "Встретить торговца" },
      { id: "learn_rumors", label: "Сплетни" },
      { id: "hear_song", label: "Песня" },
      { id: "shelter_from_storm", label: "Укрыться от грозы" },
      { id: "shop", label: "Магазин" },
    ],
  },
  {
    group: "Смерть и мир",
    types: [
      { id: "death", label: "Смерть" },
      { id: "death_respawn", label: "Возрождение" },
      { id: "remember_defeat", label: "Воспоминание о поражении" },
      { id: "world_news", label: "Новости мира" },
      { id: "construction_donation", label: "Стройка: взнос" },
      { id: "gate_donation", label: "Врата: взнос" },
      { id: "gate_closed", label: "Врата: закрытие" },
    ],
  },
  {
    group: "Гильдии",
    types: [
      { id: "guild_founded", label: "Гильдия: основание" },
      { id: "guild_levelup", label: "Гильдия: уровень" },
      { id: "guild_feast", label: "Гильдия: пир" },
      { id: "guild_shop_purchase", label: "Гильдия: покупка" },
    ],
  },
  {
    group: "Активности",
    types: [
      { id: "fishing", label: "Рыбалка" },
      { id: "gather", label: "Собирательство" },
      { id: "collect_herbs", label: "Сбор трав" },
      { id: "steal", label: "Кража" },
      { id: "break_in", label: "Проникновение" },
      { id: "jail", label: "Тюрьма" },
      { id: "pet_care", label: "Питомец: уход" },
    ],
  },
  {
    group: "Кузня и боги",
    types: [
      { id: "enhance_success", label: "Небесная кузня: заточка" },
      { id: "god_encourage", label: "Бог: Вдохновить" },
      { id: "god_punish", label: "Бог: Наказать" },
      { id: "god_heal", label: "Бог: Исцелить" },
      { id: "god_direct", label: "Бог: Направить" },
      { id: "god_quest", label: "Бог: Задание" },
      { id: "god_weather", label: "Бог: Погода" },
    ],
  },
]

// Плоский список (для фильтров/select'ов без групп)
export const TEMPLATE_TYPES = TEMPLATE_TYPE_GROUPS.flatMap(g => g.types)

// ─── Словник переменных (зеркало backend simple_context в template_engine.ex) ──
// caseHint — какой падеж/форму ждёт движок, чтобы тексты читались без корявостей.
export const VAR_GROUPS: { title: string; hint: string; vars: { var: string; label: string; caseHint?: string; example: string }[] }[] = [
  {
    title: "Основные",
    hint: "доступны в любом шаблоне",
    vars: [
      { var: "{hero_name}", label: "Имя героя", caseHint: "им. падеж", example: "Дракенфел" },
      { var: "{location_name}", label: "Название локации", caseHint: "им. падеж", example: "Ривервуд" },
      { var: "{location_type}", label: "Тип локации (англ.)", example: "village" },
      { var: "{mood}", label: "Настроение героя", caseHint: "0–100", example: "75" },
      { var: "{god_name}", label: "Имя бога героя", caseHint: "им. падеж", example: "Талос" },
    ],
  },
  {
    title: "Смерть и возрождение",
    hint: "death_respawn",
    vars: [
      { var: "{location}", label: "Город возрождения", caseHint: "им. падеж", example: "Вайтран" },
      { var: "{generation}", label: "Поколение души", caseHint: "число", example: "3" },
    ],
  },
  {
    title: "Бой",
    hint: "combat_start / combat_result / hero_defeat / засады",
    vars: [
      { var: "{monster_name}", label: "Имя монстра", caseHint: "им. падеж", example: "Серый волк" },
      { var: "{xp}", label: "Опыт за бой", caseHint: "число", example: "25" },
      { var: "{gold}", label: "Золото за бой", caseHint: "число", example: "12" },
      { var: "{rounds}", label: "Раундов боя", caseHint: "число", example: "3" },
      { var: "{_combat_verbs}", label: "Глагол начала боя", caseHint: "прош. время", example: "Сразился" },
    ],
  },
  {
    title: "Дорога и местность",
    hint: "explore / travel_* / переходы",
    vars: [
      { var: "{terrain}", label: "Местность", caseHint: "дат. падеж", example: "густому лесу" },
      { var: "{destination}", label: "Пункт назначения", caseHint: "им. падеж", example: "Вайтран" },
      { var: "{landmark}", label: "Ориентир", caseHint: "род. падеж", example: "старого дуба" },
    ],
  },
  {
    title: "Находки и добыча",
    hint: "explore / find_loot / discover_treasure / shop",
    vars: [
      { var: "{discovery}", label: "Находка", caseHint: "вин. падеж", example: "старую карту" },
      { var: "{item_name}", label: "Предмет", caseHint: "им. падеж", example: "Зелье здоровья" },
      { var: "{loot_text}", label: "Описание добычи", caseHint: "вин. падеж", example: "немного золота" },
      { var: "{gold_spent}", label: "Потрачено золота", caseHint: "число", example: "10" },
    ],
  },
  {
    title: "Общество",
    hint: "social / meet_merchant / learn_rumors",
    vars: [
      { var: "{npc_name}", label: "Имя NPC", caseHint: "им. падеж", example: "Олаф" },
      { var: "{gamble_result}", label: "Итог игры в кости", caseHint: "глагольная фраза", example: "выиграл 15 золотых" },
      { var: "{rumor}", label: "Слух (пул CD-1)", caseHint: "предложение целиком", example: "на востоке видели дракона" },
      { var: "{tavern}", label: "Таверна (пул CD-1)", caseHint: "предл. падеж, с кавычками", example: "«Пьяный дракон»" },
    ],
  },
  {
    title: "Мир и лавка",
    hint: "travel / explore / rest / shop — новые пулы CD-1",
    vars: [
      { var: "{beast}", label: "Зверь (пул CD-1)", caseHint: "им. падеж", example: "мудрый краб" },
      { var: "{shop_item}", label: "Товар лавки (пул CD-1)", caseHint: "вин. падеж", example: "стальной наплечник" },
    ],
  },
  {
    title: "Активности",
    hint: "fishing / gather / steal / break_in / jail / pet_care",
    vars: [
      { var: "{fish_name}", label: "Улов", caseHint: "вин. падеж", example: "ловкую форель" },
      { var: "{herb_name}", label: "Собранное", caseHint: "вин. падеж", example: "пучок лаванды" },
      { var: "{stolen_gold}", label: "Украдено золота", caseHint: "число", example: "15" },
      { var: "{witness_name}", label: "Свидетель", caseHint: "им. падеж", example: "Олаф Двужильный" },
      { var: "{bounty_gold}", label: "Награда за голову", caseHint: "число", example: "25" },
      { var: "{fine_gold}", label: "Штраф", caseHint: "число", example: "30" },
      { var: "{trap_hp}", label: "Урон от ловушки", caseHint: "число", example: "10" },
      { var: "{jail_reason}", label: "Причина ареста", caseHint: "род. падеж («за …»)", example: "кражу" },
      { var: "{jail_ticks}", label: "Тиков отсидки", caseHint: "число", example: "5" },
      { var: "{pet_name}", label: "Имя питомца", caseHint: "им. падеж", example: "Мурчелло" },
      { var: "{pet_species}", label: "Вид питомца", caseHint: "им. падеж", example: "кот" },
      { var: "{pet_care_kind}", label: "Действие ухода", caseHint: "прош. время", example: "покормил" },
      { var: "{pet_loyalty}", label: "Лояльность питомца", caseHint: "0–100", example: "70" },
    ],
  },
]

// Плоский список переменных (для превью и чипов)
export const ALL_VARIABLES = VAR_GROUPS.flatMap(g => g.vars)

// ─── Примеры для импорта JSON ──────────────────────────────────────────────
export const EXAMPLE_JSON: { title: string; desc: string; json: object[] }[] = [
  {
    title: "Исследование",
    desc: "Находка на природе с переменными",
    json: [
      { template_type: "explore", text_template: "В тени {landmark} герой {hero_name} обнаружил {discovery}. Кто оставил — история умалчивает." },
    ],
  },
  {
    title: "Бой",
    desc: "Итог сражения с наградами",
    json: [
      { template_type: "combat_result", text_template: "{_combat_verbs} с {monster_name} за {rounds} раундов. Трофеи: {xp} опыта и {gold} золота." },
    ],
  },
  {
    title: "Сон",
    desc: "Сновидение после долгого отдыха",
    json: [
      { template_type: "dream", text_template: "Старый сон про бездонный суп. {hero_name} проснулся голодным вдвойне." },
    ],
  },
  {
    title: "Возрождение",
    desc: "Смерть — не конец",
    json: [
      { template_type: "death_respawn", text_template: "{hero_name} приходит в себя в храме — {location}. Поколение {generation} будет осторожнее." },
    ],
  },
  {
    title: "Воля бога",
    desc: "Вмешательство божества",
    json: [
      { template_type: "god_encourage", text_template: "{god_name} обратил взор на {hero_name}. В {location_name} стало светлее — впервые за много дней." },
    ],
  },
  {
    title: "Набор шаблонов",
    desc: "Пачка из трёх разных типов",
    json: [
      { template_type: "smell_flowers", text_template: "Полевые цветы пахли духами. {hero_name} задумался о карьере алхимика." },
      { template_type: "hear_river", text_template: "Где-то за деревьями шумела вода. К реке! {hero_name} взбодрился." },
      { template_type: "watch_sunset", text_template: "Солнце село за {landmark}, окрасив небо в цвет крови дракона." },
    ],
  },
]

// ─── Утилиты ───────────────────────────────────────────────────────────────

// Живое превью: подставляем примеры вместо переменных
export function previewTemplate(text: string, vars: { var: string; example: string }[]): string {
  let result = text
  for (const v of vars) {
    result = result.replaceAll(v.var, v.example)
  }
  return result
}

// Вставка переменной в позицию курсора textarea
export function insertVariable(textarea: HTMLTextAreaElement, variable: string, setText: (v: string) => void) {
  const start = textarea.selectionStart ?? textarea.value.length
  const end = textarea.selectionEnd ?? start
  const before = textarea.value.substring(0, start)
  const after = textarea.value.substring(end)
  const newText = before + variable + after
  setText(newText)
  setTimeout(() => {
    textarea.selectionStart = textarea.selectionEnd = start + variable.length
    textarea.focus()
  }, 0)
}
