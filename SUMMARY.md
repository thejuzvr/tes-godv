# TES Idle — Нарративная логика

## Герой

### Характер (Personality)

При создании героя генерируются 6 черт (0-100), модифицированных расой и классом:

| Trait | Nord/Warrior | Khajiit/Mage | Imperial/Bard | Argonian/Thief |
|-------|-------------|-------------|--------------|---------------|
| bravery | 75 | 30 | 25 | 40 |
| curiosity | 40 | 60 | 55 | 60 |
| greed | 55 | 70 | 50 | 65 |
| sociability | 45 | 50 | 75 | 50 |
| tenacity | 60 | 50 | 50 | 50 |
| caution | 35 | 55 | 50 | 70 |

Черты влияют на выбор целей через Utility AI:
- `bravery` +0.004/point к цели **fight**
- `curiosity` +0.004/point к **explore**, +0.003 к **travel**
- `greed` +0.004/point к **shop**, +0.003 к **loot**
- `sociability` +0.005/point к **socialize**
- `tenacity` +0.003/point к **complete_quest**
- `caution` +0.005/point к **heal**, +0.003 к **rest**, -0.002 к **fight**

### Память (Memory)

Герой запоминает 7 типов событий (последние 20):

| Тип | Пример | Влияние на mood |
|-----|--------|----------------|
| victory | "Серый волк" | +10 |
| defeat | "Молодой дракон" | -20 |
| discovery | "забытый алтарь" | +15 |
| quest_complete | "Исследовать окрестности" | +20 |
| social | "Олаф" | +8 |
| shop | "Зелье здоровья" | +5 |
| travel | "Ривервуд" | +3 |

Память влияет на Utility AI: победы повышают желание fight (+2/победа), открытия повышают explore (+3/открытие).

### Принятие решений (Utility AI → GOAP → FSM)

Каждый тик (30 сек реального времени):

1. **Brain.Intent** (единое ядро решений, S-2): **Utility AI** оценивает все 14 целей по формулам с personality + needs + memory, затем **Brain.Graph.enrich** красит цели причудами/связями BrainHash (жёсткий кэп ±0.15) и **world_stage** учитывает мир (события/войны/погоду — кэп `world_limits.utility_cap`). Выбирается цель с максимальной полезностью; `decision_log` хранит мотив и мир-контекст (50 последних решений).

2. **GOAP Planner** строит план действий для цели:
   - `complete_quest` → [travel, explore, fight] (зависит от типа шага квеста)
   - `rest` → [rest]
   - `explore` → [explore]
   - `fight` → [explore, fight]

3. **FSM Executor** выполняет план пошагово:
   - `:idle` — нет плана → создаёт план → выполняет первое действие
   - `:execute` — план есть → выполняет текущий шаг
   - `:fight` — активный бой → обрабатывает раунд боя
   - `:jailed` — арест → отсидка/bribe/escape (план переживает тюрьму)

Multi-tick действия (combat, travel, fishing, jail) хранят состояние в `state_data` JSON и продолжаются в следующих тиках.

---

## Дневник (Journal)

### Последовательность записей

Дневник формируется из двух источников:
1. **HTTP** `GET /hero/me` + `GET /journal` — начальная загрузка и поллинг каждые 60 сек
2. **WebSocket** `journal_entry` — real-time push при каждом тике

Записи идут в порядке `created_at DESC` (новые сверху).

### Типы записей — базовые 18 + активности + мир

| entry_type | Когда появляется | Что содержит |
|-----------|-----------------|-------------|
| **explore** | Герой исследует локацию | `{terrain}`, `{discovery}`, `{landmark}` |
| **combat_start** | Начало боя | `{monster_name}`, `{landmark}` |
| **combat_result** | Победа в бою | `{monster_name}`, `{xp}`, `{gold}`, `{rounds}` |
| **combat_defeat** | Поражение в бою | `{monster_name}`, `{hero_name}` |
| **rest** | Отдых (inn или outdoor) | `{hero_name}`, `{location_name}` |
| **shop** | Покупка в магазине | `{npc_name}`, `{item_name}`, `{gold_spent}` |
| **social** | Общение в таверне | `{npc_name}`, `{gamble_result}` |
| **travel** | Путешествие | `{hero_name}`, `{destination}` |
| **loot** | Поиск добычи | `{loot_text}` |
| **death** | Смерть героя | `{hero_name}`, `{location_name}` |
| **equip** | Экипировка предмета | `{item_name}`, `{hero_name}` |
| **thought** | Мысль героя (15% шанс) | `{hero_name}`, `{god_name}`, `{location_name}` |
| **god_*** | Действия бога (encourage/punish/heal/direct/quest/weather) | `{god_name}`, `{hero_name}` |
| **pet_adopted / pet_left / pet_revived** | События питомца (в журнал напрямую, без шаблонов) | Имя/вид питомца |
| **fishing / gather / steal / break_in / jail** | Активности Фазы 2 | `{fish_name}`, `{herb_name}`, `{witness_name}`, ... |
| **reputation_change** | Смена уровня репутации фракции (P-3) | `{hero_name}`, фракция, новый уровень, дельта |
| **world_news** | Новость мира (шанс `news_chance`) | Событие ядра мира |

### Жизненный цикл боевой записи

```
combat_start → combat_start → ... → combat_result
    (тик 1)      (тик 2-19)           (тик N)
```

Промежуточные тики (`combat_progress`) НЕ создают journal-записи — только WS-push для обновления HP-полосок в combat-баннере.

### Божественные действия

Герой тратит soul_energy (5-15) на действие бога. Нарратив генерируется через TemplateEngine с template_type `god_{action}`. При отсутствии шаблонов — fallback на хардкод-текст.

---

## Нарративы

### Переменные шаблонов

**Общие (доступны всем типам):**
`{hero_name}`, `{location_name}`, `{location_type}`, `{mood}`, `{god_name}` ("Талос")

**По типам:**

| Тип | Переменные |
|-----|-----------|
| explore | `{terrain}` (7 вариантов), `{discovery}` (7), `{landmark}` (8) |
| combat_start | `{monster_name}`, `{landmark}` |
| combat_result | `{monster_name}`, `{xp}`, `{gold}`, `{rounds}`, `{_combat_verbs}` (4) |
| combat_defeat | `{monster_name}`, `{hero_name}` |
| rest | `{hero_name}`, `{has_inn}` |
| shop | `{npc_name}` (15 имён), `{item_name}`, `{gold_spent}` |
| social | `{npc_name}` (15 имён), `{gamble_result}` |
| travel | `{destination}` |
| loot | `{loot_text}` |
| death | `{hero_name}`, `{location_name}` |
| thought | `{hero_name}`, `{god_name}`, `{location_name}` |
| equip | `{item_name}`, `{hero_name}` |
| god_* | `{god_name}`, `{hero_name}`, `{location_name}` |

### Выбор шаблона

1. Запрос из БД `narrative_templates` по `template_type` + `is_active=true` + опционально `location_id`
2. Фильтрация: исключение последних использованных (dedup через `state_data["used_templates"]`)
3. Если доступных шаблонов нет — случайный из неподходящих
4. Если шаблонов нет вообще — fallback `"Продолжает свой путь."`

### Сцены (Composer, N-2/N-3)

Полный текст сцены = `[опенер погоды]` + костяк-шаблон + `[closer]`. Closer выбирается по иерархии: причуда героя (`quirk_*`) → свежая память (`memory_<type>`) → настроение (`closers_high/mid/low`). Рендер входит в выбор: фрагмент с непокрытыми `{var}` отбрасывается (N-5: это касается и опенера — сцена уходит без него). Одобренные llm-шаблоны — полные сцены (full_scene), Composer их не размножает. Управление — `game_configs["composer"]`.

**Тональная смесь (N-5):** пулы фрагментов содержат ~50/50 обычных и комичных строк — комбинатор и Composer дают живой микс тонов без изменения кода. Контракт опенеров: без переменных (если {var} всё же попал в пул, defensive-рендер подставит или отбросит).

### Форматирование

Regex `\{(\w+)\}` — переменные заменяются на значения из контекста (переменные действия пробрасываются поверх пулов). Отсутствующие переменные остаются как `{var}` вместо краша.

---

## Игровой цикл (GameTickWorker)

Каждые 30 секунд для каждого героя (полная цепочка — см. PROJECT_SUMMARY):

1. `ContextBuilder.build(hero_id)` — герой, локация, инвентарь, квест, конфиги + world-снапшот + погода региона
2. `FSMExecutor.tick(ctx)` — Brain.Intent → GOAP → Execute
3. `apply_result(hero, result)` — hunger/fatigue/morale, soul_energy, game_hour (+ progression S-4)
4. `auto_consume(hero)` — авто-зелья, еда, камни душ
5. `check_quest_progress(hero, action, result)` — прогресс квеста + репутация за квест (P-3)
6. `reputation_tick(ctx, action, result)` — репутация за победу над монстром (P-3)
7. `pet_tick(hero)` — голод/настроение питомца
8. `track_memories(hero, action, result)` — запись в память героя
9. `check_auto_equip(hero)` — авто-экипировка (каждые 5-10 тиков), единый save state_data
10. `TemplateEngine.generate(result, ctx)` — нарратив (+ Composer-сцена)
11. `create_journal_entry(hero, narrative, result)` — запись в дневник
12. `push_updates(hero_id, result)` — WebSocket-push клиенту

---

## WebSocket-события

| Событие | Когда | Содержимое |
|---------|-------|-----------|
| `hero_update` | Каждый тик (delta) | Изменённые поля героя + state_data всегда |
| `journal_entry` | Каждый тик | Новая запись дневника |
| `combat_start` | Начало боя | Данные монстра, HP-полоски |
| `combat_progress` | Каждый раунд боя | Текущие HP героя и монстра |
| `combat_result` | Конец боя | XP, gold, победитель |
| `equipment_update` | Авто-экипировка | Сигнал обновления |
| `world_update` | Тик ядра мира (60с) | Снапшот мира (в `world:lobby` и дублем в `hero:*`) |

---

## Репутация (P-3)

Единая точка `Law.adjust_reputation/5`. Фракция определяется регионом героя (`law.factions_by_region`, дефолт «Империя»).

| Уровень | Значение |
|---------|----------|
| hostile (враг фракции) | ≤ −50 |
| unfriendly (нелюбим) | < 0 |
| neutral (нейтрален) | < 25 |
| friendly (дружелюбно принят) | < 75 |
| allied (союзник) | ≥ 75 |

Дельты (конфиг `law.reputation`): квест +5, победа над монстром +1, преступление −(rep_loss × множитель), штраф +2. Journal `reputation_change` пишется только при смене уровня.

---

## Баннеры (Combat + Travel)

### Combat Banner
Показывается когда `state_data.combat` существует и `rounds_left > 0`.

Отображает HP-полоски героя и монстра, раунд `(20 - rounds_left)/20`.

Обновляется через WS `combat_progress` каждый раунд.

### Travel Banner
Показывается когда `state_data.travel` существует и `ticks_left > 0`.

Отображает progress-bar `(total_ticks - ticks_left)/total_ticks` и время прибытия.

Обновляется через WS `hero_update` (state_data).

### Combined Banner
Когда оба условия выполняются — показывается комбинированный баннер "🚶 В пути к {destination} — Встречен враг!".
