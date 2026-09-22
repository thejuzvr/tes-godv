# LOGIC_MAP — карта логики TES Idle

Статус: рабочая карта для постановки задачи ИИ. Не план и не хроника.
Обновлять, когда меняется контракт, писатель или граница блока.
Длинные обоснования живут в `docs/PLAN_*.md` и `AGENTS.md`; сюда — только то,
без чего правка блока делается вслепую.

Фронт сюда не входит. Он потребитель API: смена формы ответа — правка
`frontend/src/lib/api.ts` и типа в сторе, не отдельное направление.

## Как ставить задачу

Называть направление из раздела 2 и границу, которую нельзя перейти.
Пример: «Journal, только чтение ленты. Не трогать Pipeline и state_data».

В направление входят три вещи:

1. единственный писатель состояния;
2. контракт наружу (REST, канал, таблица);
3. что ломается, если писать состояние в обход.

## 1. Как идёт время

Два независимых тика. Герой не ждёт мир, мир не ждёт героя.

```text
GameTickWorker                каждые 30с, онлайн — каждый тик,
  │                           офлайн — раз в ~15 мин (±20% джиттер от hero_id)
  └─ Pipeline.tick(hero_id)   один герой, ошибка гасится логом и не роняет волну
        ContextBuilder        единственный загрузчик контекста тика
        FSMExecutor           решение
        apply_result          единственное сохранение героя в тике
        Journal               текст ПОСЛЕ применения наград
        PubSub "hero:<id>"    {:hero_tick, result}

World.Kernel                  каждые 60с, свой GenServer
  погода → экономика → миграции → фракции → события → стройка → врата
  └─ пишет world_state, кладёт сырой блок в ETS (World.Snapshot)
        наружу (REST и "world:lobby") — public_snapshot:
        стройка и врата уже как summary, не сырой блок
```

Ручной тик админа (`POST /admin/game/tick-all`) шлёт воркеру `:tick`.
`POST /admin/heroes/:id/force-tick` тикает одного героя тем же Pipeline.

## 2. Направления

### Hero — состояние героя

Писатель тика: `Pipeline.apply_result/4`. Поля героя, `state` и `state_data`
сходятся там. Action возвращает `{:ok, map}` с дельтами и `state_data_update`;
сам героя не сохраняет.

Контракт: `GET /hero/me`, `POST /hero/heartbeat|offline`, `GET /hero/brain`,
`GET /hero/pets/history`, `GET /hero/reputations`.

Обходы, которые уже есть и которые нельзя плодить:

- ручные действия игрока пишут героя из своего контроллера
  (`InventoryController`, `EquipmentController`, `GodController`,
  `QuestController`, `LocationController`) — это ответ на клик, не тик;
- `Law`, `Pets`, `Skyforge` пишут свои таблицы и иногда журнал;
- часть Action пишет `skills` и инвентарь напрямую
  (fishing, gathering, mining, stealing, shop, loot, fight).

`state_data` — JSON-строка. Ключи: `combat`, `travel`, `plan`, `jail`,
`fishing`, `law`, `brain`, `memories`, `sleep`, `death`, `journal`.
Писать её может только код, который только что перечитал героя.
`TemplateEngine.track_used` и `NarrativeDirector` делают `Repo.reload!`
перед записью. Прямой `Repo.update` от `ctx.hero` затирает свежие ключи.

`GameContext` — struct. Только `ctx.field`. `ctx[:key]` компилируется
и падает на каждом тике (`GameContext` не реализует Access), воркер
ошибку глотает, хроника молчит.

### Decision — чем герой занят

`FSMExecutor` → `Goal` (utility) → `GOAPPlanner` → Action.
Состояния героя: exploring, fighting, traveling, resting, shopping,
socializing, looting, fishing, jailed, dead и активности из Фазы 2.

Контракт Action: `{:ok, map} | {:error, reason}`. Голая карта роняет тик
(`no case clause`). `Enum.random([])` бросает до `||` и так же гасит тик.

Новая цель = evaluator в `goal.ex` + строка в `goap_planner.ex` +
модуль в `@action_to_module`. Числа — из `game_configs` через `ctx.configs`,
не из литералов.

Аудит решения пишет `Brain.Audit` в `decision_audit_events`. Это отдельный
поток от журнала: подавление текста его не касается.

Чтение: `GET /admin/brain/stats`, `GET /admin/brain/export`.
`Anomalies` внутри держит `severity` атомом; в JSON атом становится строкой.
Без этого `json/2` отвечает 500, как только найдена хоть одна аномалия.

### Journal — что видит игрок

Четыре разных вещи, их нельзя мешать:

| Поток | Где | Срок |
| --- | --- | --- |
| игровой факт | применён в Pipeline до текста | не зависит от журнала |
| строка хроники | `journal_entries` | обычные — 7 суток + хвост 500, политика выключена |
| веха | `hero_milestones` | снимок текста, не ссылка на шаблон |
| суточный факт | `hero_daily_stats`, `journal_event_totals` | переживает удаление строк |

Порядок в тике (`Pipeline.publish_narrative/8`):

```text
награды уже применены
  → Throttle.check        off | shadow | enforce; важный тип не режется
  → suppress:  Aggregator.record_suppressed, строки нет
  → publish:   mark_published + record_published + INSERT + веха по факту
```

`shadow` считает отказ, но строку пишет. `enforce` — единственный режим,
в котором строка не создаётся. Оба не трогают награды.

Класс решает `Journal.Classifier` по результату, не по имени типа:
`ambient | progress | important | milestone`. Неизвестный тип — `progress`,
чтобы новый текст не вычистился как шум.

Чтение:

- `GET /journal` — `{entries, has_more, next_cursor, limit}`. Курсор
  `created_at|id`. `offset` оставлен. Пустой список — `entries: []`, не ошибка.
- `GET /journal/count` — `{count, totals}`. `totals` читает
  `journal_event_totals`: без миграции `20260908120000` ручка 500.
- `GET /journal/summary` — итоги 7 суток против сквозных счётчиков.

Админ: `GET /admin/journal/retention`, `.../preview`, `POST .../run`,
`GET /admin/journal/stats`. Очистка сама не стартует. `run` уважает
`enabled` и `dry_run`. Предпросмотр — один проход с `row_number()` по всей
хронике героя; хвост «последние 500» считается до отсечения по возрасту.

`Throttle` держит счётчики в ETS `:journal_throttle`. Таблица создаётся
в `Application.start` до супервизора. Это лимит одного узла: после рестарта
несколько лишних атмосферных строк допустимы.

### Narrative — из чего собирается текст

Писатель шаблонов: админ-контроллеры и `LlmFactory` (кандидаты
`source=llm, is_active=false`). Рантайм только читает.

`NarrativeDirector` выбирает событие → `TemplateEngine` берёт шаблон типа
→ `Composer` доклеивает опенер погоды и один closer. Нет шаблона — нет строки.
Это честно, а не ошибка. Текст с непокрытым `{var}` не публикуется.

`{var}` заполняет `TemplateEngine.render_vars/2`, и только строками.
Число `60` становится символом `<`.

Фрагменты (`narrative_fragments`) — пулы для `{terrain}`, `{fish_name}` и т.п.
Пустой пул оставляет плейсхолдер видимым.

Тип `combat` мёртвый: бой идёт через `hero_victory | hero_defeat |
combat_result | combat_start`. Запись `god` пишет `GodController` напрямую,
минуя типы `god_*`.

### World — общий мир

Писатель: `World.Kernel`. Читатели берут `Snapshot.current()` и не пишут
`world_state`. Снаружи всегда `Kernel.snapshot/0` / `public_snapshot`:
сырой блок стройки и врат наружу не выходит.

`World.Aggregator` копит давление героев (покупки, убийства) и раз в пять
минут отдаёт его ядру через `apply_pressure`. Сам снапшот не пишет.

Контракт: `GET /world`, `POST /construction/donate`, `POST /gates/donate`.
Админ: `POST /admin/world/tick|events|gates/open`.
Канал: `world:lobby`, событие `world_update`.

Донат героя — `GenServer.call`. Золото списывает контроллер, прогресс
копит ядро. Гонка «врата закрылись, пока списывали» возвращает золото.

### Guild — общее у игроков

Писатель: `Game.Guilds` и его подмодули (`Shop`, `News`, `Prune`).
Один игрок — одна гильдия (`guild_members.user_id` уникален).

Контракт, важен порядок роутов: `/guilds/shop` и `/guilds/news` стоят
выше `/guilds/:id`.

```text
GET|POST /guilds
POST /guilds/:id/join|leave|offerings|treasury|feast
GET|POST /guilds/:id/messages
GET /guilds/:id/applications + decide
POST /guilds/:id/members/:user_id/role|kick
```

Канал `guild:<id>`: чужой не входит (`not_a_member`). Чат ещё и REST,
успешный POST шлёт тот же `chat_message` в PubSub.

Золото в гильдии не гуляет между игроками. Подношение алтаря сгорает
и даёт опыт гильдии и очки. Очки тратятся в лавке. Казна — вклад героя,
тратится только на пир, назад не выводится.

`officer_of/2` возвращает `{guild, member} | nil`, не bool.

### Social — герой с героем

`EncounterWorker` подбирает пару (`Encounters.Matcher`) → `Resolver`
→ запись в outbox → `OutboxDispatcher`. Идемпотентность встречи живёт
в outbox и в уникальном индексе журнала `(encounter_id, hero_id)`.
Удаление строки журнала не должно позволять опубликовать ту же встречу снова.

Контракт: `GET /hero/encounters|relationships|social-settings`,
`PATCH /hero/social-settings`, `PUT|DELETE /hero/blocks/:id`.

### Economy — вещи, закон, ремесло

Не один модуль. Граница такая: предмет и его количество принадлежат
инвентарю, золото — герою, заточка — `sharpenings` (пара hero+item,
не сам предмет каталога).

- экипировка и инвентарь: контроллеры игрока + `AutoEquip` внутри тика;
- заточка: `Skyforge`, бонус читает `FightAction`;
- закон и репутация: `Law.adjust_reputation/5`, пороги из `game_configs["law"]`;
- квест: шаги в `Pipeline.check_quest_progress`, награда там же.

`GET /equipment` — `{slots, hero_gold}`, не голый объект слотов.
`POST /equipment/enhance/:slot` — 404 `empty_slot`, 409 `cap_reached | not_enough_gold`.

### Admin — наблюдение и правка каталога

Только то, чего нет у игрока: пользователи, герои, каталог предметов
и монстров, шаблоны, конфиг, импорт/экспорт, пульс мира, аудит, хроника.

`game_configs.value` — строка JSON. Числа и вложенные карты кодируются
`Jason.encode!` на записи и декодируются в `ContextBuilder.load_configs`.
Новый ключ без дефолта в `load_configs` для рантайма не существует.

Удалённые ручки, фронт их больше не зовёт: `/admin/narrative-stats`,
`/admin/simulation/*`, `/admin/tests/*`.

## 3. Контракты, которые уже ломались

| Обещание | Где проверять |
| --- | --- |
| Action возвращает `{:ok, _}` | `lib/tes_idle/game/actions/*.ex` |
| `state_data` не пишется из устаревшего `ctx.hero` | запись только после reload или из `apply_result` |
| `ctx.field`, никогда `ctx[:key]` | `grep "ctx\\[" lib/` |
| текст журнала не создаётся без шаблона и не содержит `{var}` | TemplateEngine / Composer |
| `render_vars` получает строки | вызовы журнала гильдий, стройки, врат, снов |
| миграция идемпотентна, один `execute` — один SQL | `priv/repo/migrations` |
| атом не попадает в `json/2` | severity, mode, reason |
| `if cond, do: conn |> halt()` не прерывает функцию | контроллеры: нужен обычный `if` |
| роут-литерал объявлен раньше `/:id` | guilds, journal |
| колонка называется `created_at`, не `inserted_at` | схемы с `timestamps(inserted_at: :created_at)` |
| наивное время с бэкенда — UTC | клиент парсит с суффиксом `Z` |

## 4. Что где лежит

```text
lib/tes_idle/game/pipeline.ex            оркестратор тика
lib/tes_idle/game/context_builder.ex     загрузка и дефолты конфигов
lib/tes_idle/game/fsm_executor.ex        решение тика
lib/tes_idle/game/goal.ex                utility
lib/tes_idle/game/actions/               один файл — одно действие
lib/tes_idle/game/journal/               classifier, throttle, aggregator,
                                         milestones, retention
lib/tes_idle/game/narrative/             выбор и сборка текста
lib/tes_idle/game/brain/                 геном, граф, аудит, аномалии
lib/tes_idle/game/guilds/                лавка, вести, обрезка чата
lib/tes_idle/world/                      kernel и чистые системы мира
lib/tes_idle/worker/                     тик, встречи, outbox, flush онлайна
lib/tes_idle_web/router.ex               контракт HTTP
lib/tes_idle_web/channels/               hero, world, guild
```

Схемы — `lib/tes_idle/schemas/`. Контроллер не толще контракта:
проверка входа, вызов модуля направления, JSON без атомов.
)
