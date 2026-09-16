# TES Idle · Классификатор нарративов

Этот каталог — автономная памятка для создания **валидных** narrative JSON-пакетов. Откройте `index.html` в браузере для поиска переменных, выбора типа и генерации prompt.

> Источник правил: `TesIdle.Game.Narrative.BatchImporter`. При расхождении кода и документации верен код importer.

## Быстрый путь

1. В `index.html` выберите `template_type`.
2. Выберите тон и число сцен.
3. Скопируйте сгенерированный prompt в модель.
4. Сохраните ответ модели в UTF-8 JSON-файл.
5. В админке: **Нарративы → Импорт JSON-пакета → Выбрать файл… → Проверить пакет → Импортировать**.
6. По умолчанию используйте `pending`, затем просматривайте и одобряйте шаблоны в модерации.

## Допустимый JSON

Импортер принимает оба формата.

### Рекомендуемый: пакет-объект

```json
{
  "activation_policy": "pending",
  "templates": [
    {
      "template_type": "mining",
      "text_template": "{hero_name} нашёл {ore_name} в трещине жилы.",
      "source": "community",
      "variables": ["hero_name", "ore_name"],
      "mood_min": 0,
      "mood_max": 100
    }
  ]
}
```

### Допустимый: голый массив

```json
[
  {
    "template_type": "rest",
    "text_template": "У костра {hero_name} позволил дороге немного подождать.",
    "source": "community"
  }
]
```

- Максимум: **200 шаблонов в одном файле**.
- `text_template`: непустой, до **4 000 UTF-8 байт**.
- `source`: `community`, `system` или `llm`. Для ручной генерации используйте `community`.
- `activation_policy`: `pending` или `active_system`. `active_system` допустим только если **каждая** строка имеет `source: "system"`.
- `variables`, если указано, обязано в точности совпадать с переменными из текста.
- `mood_min` / `mood_max`: от 0 до 100, минимум не больше максимума.
- Импорт атомарный: одна ошибка отменяет весь пакет.

## Базовые переменные: допустимы у всех типов

| Переменная | Значение | Пример | Падеж / замечание |
|---|---|---|---|
| `{hero_name}` | Имя текущего героя | Хальвар | Ставьте в синтаксис, где имя уместно в именительном падеже. |
| `{location_name}` | Имя текущей локации | Ривервуд | Как правило, именительный падеж. |
| `{location_type}` | Технический тип места | village | Лучше не выводить в художественном тексте. |
| `{god_name}` | Имя божества | Талос | Используйте только в подходящих божественных событиях. |
| `{mood}` | Настроение героя | 72 | Число; не склоняется. |

## Предметные и событийные переменные

| Переменная | Значение | Пример | Обычно разрешена в |
|---|---|---|---|
| `{terrain}` | Описание местности | густому лесу | explore / discovery / road |
| `{discovery}` | Находка | старую карту | explore / discovery / loot |
| `{landmark}` | Ориентир | старого дуба | explore / combat / road |
| `{monster_name}` | Имя противника | серый волк | combat |
| `{xp}` | Опыт | 25 | combat_result |
| `{gold}` | Золото | 12 | combat_result |
| `{rounds}` | Число раундов | 3 | combat_result |
| `{_combat_verbs}` | Боевой глагол | сверкнул | combat_result |
| `{destination}` | Пункт назначения | Вайтран | travel |
| `{loot_text}` | Описание добычи | немного золота | loot |
| `{fish_name}` | Рыба | ловкую форель | fishing |
| `{herb_name}` | Трава / ингредиент | пучок лаванды | gather / collect_herbs |
| `{ore_name}` | Руда | железная жила | mining |
| `{item_name}` | Предмет | стальной меч | shop / equip / enhance |
| `{shop_item}` | Товар лавки | стальной наплечник | shop |
| `{gold_spent}` | Потрачено золота | 10 | shop |
| `{npc_name}` | Имя NPC | Олаф | shop / social |
| `{rumor}` | Слух | на востоке видели дракона | social |
| `{tavern}` | Название таверны | «Пьяный дракон» | social |
| `{gamble_result}` | Итог игры | выиграл немного золота | social |
| `{stolen_gold}` | Украдено золота | 15 | steal |
| `{witness_name}` | Свидетель | Олаф Двужильный | steal |
| `{bounty_gold}` | Награда за голову | 25 | steal |
| `{fine_gold}` | Штраф | 30 | steal |
| `{witness_outcome}` | Исход для свидетеля | clean | steal; техническая строка, не выводить без необходимости. |
| `{trap_hp}` | Урон ловушки | 10 | break_in |
| `{break_in_ok}` | Успех взлома | false | break_in; техническое значение. |
| `{break_in_trap}` | Сработала ловушка | false | break_in; техническое значение. |
| `{break_in_noise}` | Поднят шум | false | break_in; техническое значение. |
| `{break_in_fail}` | Провал | false | break_in; техническое значение. |
| `{jail_reason}` | Причина ареста | кражу | jail |
| `{jail_ticks}` | Осталось тиков | 5 | jail |
| `{jail_escaped}` | Побег | false | jail; техническое значение. |
| `{jail_escape_fail}` | Неудачный побег | false | jail; техническое значение. |
| `{jail_free}` | Свобода | false | jail; техническое значение. |
| `{pet_name}` | Имя питомца | Мурчелло | pet_care |
| `{pet_species}` | Вид питомца | кот | pet_care |
| `{pet_care_kind}` | Действие ухода | покормил | pet_care |
| `{pet_loyalty}` | Лояльность | 70 | pet_care |
| `{location}` | Место возрождения | Вайтран | death_respawn |
| `{generation}` | Поколение души | 3 | death_respawn |
| `{event}` | Мировое событие | ветер переменился | world_news |
| `{amount}` | Сумма вклада | 50 | construction / gates |
| `{project_name}` | Название стройки | Часовня Девяти | construction_donation |
| `{level}` | Уровень улучшения/гильдии | 2 | enhance / guild_levelup |
| `{price}` | Цена | 50 | enhance / guild shop |
| `{guild_name}` | Имя гильдии | Соратники | guild events |
| `{emblem}` | Эмблема гильдии | 🛡️ | guild events |
| `{leader}` | Лидер гильдии | Хальвар | guild_founded |
| `{other_hero_name}` | Имя встреченного героя | Сигрун | hero_encounter_* |
| `{encounter_kind}` | Характер встречи | дружеская | hero_encounter_* |

## Карта типов → дополнительные переменные

| Тип | Дополнительные переменные |
|---|---|
| `explore` | terrain, discovery, landmark |
| `combat_start` | monster_name, landmark |
| `combat_result` | monster_name, xp, gold, rounds, _combat_verbs |
| `combat_defeat` | monster_name |
| `shop` | item_name, gold_spent, npc_name, shop_item |
| `social` | gamble_result, npc_name, rumor, tavern |
| `travel` | destination |
| `loot` | loot_text |
| `fishing` | fish_name |
| `gather`, `collect_herbs` | herb_name |
| `mining` | ore_name |
| `steal` | stolen_gold, witness_name, bounty_gold, fine_gold, witness_outcome |
| `break_in` | trap_hp, break_in_ok, break_in_trap, break_in_noise, break_in_fail |
| `jail` | jail_reason, jail_ticks, jail_escaped, jail_escape_fail, jail_free |
| `pet_care` | pet_name, pet_species, pet_care_kind, pet_loyalty |
| `death_respawn` | location, generation |
| `dream` | location_name |
| `world_news` | event |
| `construction_donation` | amount, project_name |
| `gate_donation` | amount, location_name |
| `gate_closed` | location_name |
| `enhance_success` | item_name, level, price |
| `guild_shop_purchase` | item_name, price |
| `guild_founded` | guild_name, emblem, leader |
| `guild_levelup` | guild_name, emblem, level |
| `guild_feast` | guild_name, emblem |
| `hero_encounter_initiator`, `hero_encounter_counterpart` | other_hero_name, location_name, encounter_kind |

Остальные event-типы используют только базовые переменные или подмножества, описанные в `index.html`.

## Правила хорошего корпуса

### Делайте

- Одна строка = самостоятельная сцена с новым наблюдением, действием или образом.
- Меняйте **глагол, точку зрения, ритм, место в сцене и итог**, а не один эпитет.
- В обычной линии выбирайте ясную сцену мира TES: тракт, холод, таверна, руины, служба, магия.
- В комичной линии шутка должна расти из ситуации, а не быть случайным мемом.
- Поддерживайте примерно 50/50 обычного и комичного тона **внутри каждого типа**.
- Генерируйте 20–60 строк на один type за prompt, не смешивайте несовместимые переменные.

### Не делайте

- Не пишите «базовая фраза + новый хвост».
- Не меняйте только один объект: «ручей», «ветер», «звёзды» после одинакового начала.
- Не используйте порядковые номера, метки `вариант 17`, «знак номер 4».
- Не вставляйте технические boolean-переменные в красивый текст без отдельной ветки логики.
- Не используйте `{hero}`, `{Location}`, `{alt_hero_name}`, `{monster}` или произвольные переменные: importer их отклонит.
- Не используйте тип `god`: он мёртвый и не участвует в runtime-пути.
- Не копируйте тексты из другого файла без проверки на дубль.

## Prompt-шаблон

Используйте генератор в `index.html`. Его обязательная часть:

```text
Каждая строка обязана быть самостоятельной сценой. Запрещено строить
вариации по формуле «одинаковое начало + другой хвост», менять только
предмет, добавлять нумерацию или искусственные маркеры уникальности.
```

## Проверка перед импортом

- [ ] JSON в UTF-8, без моджибейки `РќР°...`.
- [ ] Не более 200 строк в файле.
- [ ] В каждой строке есть `template_type` и `text_template`.
- [ ] Используются только переменные выбранного типа.
- [ ] Нет повторяющихся или почти одинаковых открывающих предложений.
- [ ] `source` — `community`, если пакет должен пойти в модерацию.
- [ ] В админке нажата «Проверить пакет» до импорта.
