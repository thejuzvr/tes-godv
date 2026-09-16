# AGENTS.md — Правила разработки TES Idle

## Принцип: Bottom-Up

Порядок разработки — **снизу вверх**. После каждого изменения проверяем, что нужно обновить на уровне выше.

```
Frontend (React)     ← обновляем если изменился API
    ↑
API Endpoints        ← обновляем если изменились сервисы
    ↑
Game Pipeline        ← обновляем если изменились модули
    ↑
Schemas / Ecto       ← фундамент
```

---

## Структура проекта

```
tes-godv/
├── tes_idle_elixir/           # Backend (Elixir + Phoenix)
│   ├── lib/
│   │   ├── tes_idle/
│   │   │   ├── schemas/       # Ecto схемы (user, hero, location, item, inventory_item,
│   │   │   │                  #  equipment, monster, quest, journal_entry, reputation,
│   │   │   │                  #  narrative_template, suggestion, game_config, pet,
│   │   │   │                  #  world_state, world_event)
│   │   │   ├── game/          # Pipeline, FSM, Actions, Narrative, Law, Pets, Skills
│   │   │   │   ├── brain/     # Фаза 1: genome.ex (BrainHash), graph.ex (enrich), learner.ex
│   │   │   │   └── actions/   # Контракт Action: базовые 9 + fishing/gathering/
│   │   │   │                  #  stealing/breaking_in/jail/pet_care (Фаза 2)
│   │   │   ├── world/         # Фаза 3 «Ядро мира»: kernel.ex (GenServer), snapshot.ex (ETS),
│   │   │   │                  #  weather.ex, economy.ex, migration.ex, factions.ex,
│   │   │   │                  #  events.ex, aggregator.ex, state.ex
│   │   │   ├── worker/        # GameTickWorker (пул задач per-hero), ActivityFlushWorker
│   │   │   └── guardian.ex    # JWT
│   │   └── tes_idle_web/
│   │       ├── router.ex      # API routes (public, auth, admin/world)
│   │       ├── controllers/   # + world_controller.ex, admin/world_controller.ex
│   │       ├── channels/      # WebSocket: HeroChannel (hero:*), WorldChannel (world:lobby)
│   │       └── plugs/         # AuthPlug, AdminPlug
│   ├── config/
│   ├── priv/
│   │   ├── repo/migrations/   # Идемпотентные (см. правило миграций)
│   │   ├── reseed.exs
│   │   ├── seed_narratives.exs
│   │   └── seed_phase2.exs    # Предметы активностей + нарративы Фазы 2
│   └── mix.exs
├── frontend/                  # React + Vite + Tailwind
│   ├── src/
│   │   ├── pages/             # Dashboard, Admin, Auth, CreateHero, Wiki, Analytics, Narratives (мастерская), Map (Фаза 1)
│   │   ├── components/        # hero/ (+ PetCard, WorldPanel), game/, god/, journal/,
│   │   │                      #  pantheon/, ui/, map/, narrativeData.ts (словник: VAR_GROUPS, TEMPLATE_TYPE_GROUPS)
│   │   ├── stores/            # gameStore.ts (Zustand: hero, journal, world, pets)
│   │   ├── hooks/             # useWebSocket (hero:* + world:lobby)
│   │   └── lib/               # api.ts, utils.ts
│   └── package.json
├── docs/
│   ├── ROADMAP_BRAIN_WORLD.md # Мастер-план: Фазы 0–3 ✅, Часть IV «Сцены» — впереди
│   └── PLAN_BETA_0.7.md       # Действующий план: сшивание мира → Beta-0.7 (1 фаза = 1 тест)
├── AGENTS.md                  # Этот файл
├── PROJECT_SUMMARY.md         # Актуальный статус проекта
├── SUMMARY.md                 # Нарративная логика
└── start.bat
```

---

## Правила

### 1. Backend → Frontend (обязательная проверка)

После любого изменения Backend **проверь**:

- [ ] Добавлен/изменён endpoint? → Добавить метод в `frontend/src/lib/api.ts`
- [ ] Изменилась структура ответа? → Обновить типы в `frontend/src/stores/gameStore.ts`
- [ ] Добавлена новая сущность? → Создать компонент/страницу во Frontend
- [ ] Изменился admin endpoint? → Обновить `frontend/src/pages/AdminPage.tsx`
- [ ] Endpoint удалён? → Удалить вызов из Frontend

### 2. Schemas → Game → API

- [ ] Добавлена Ecto схема? → Добавить файл в `lib/tes_idle/schemas/`
- [ ] Добавлено поле в схему? → Проверить миграцию, контроллеры, API responses
- [ ] Изменён GameConfig? → Проверить `pipeline.ex`, `goal.ex`, `fsm_executor.ex`, `context_builder.ex`
- [ ] Изменён leveling config? → Проверить формулу в `pipeline.ex` (apply_result → level up)

### 2.1 state_data — правило единственного писателя (критично!)

`heroes.state_data` (JSONB: combat/travel/plan/jail/fishing/law/brain) пишется **только** одним путём:

```
Action/FSM возвращает state_data_update
  → FSMExecutor/Pipeline мерджит в merged_sd
  → check_auto_equip делает единственный Repo.save
```

**Запрещено** писать state_data напрямую из Action/модулей (`Repo.update` от `ctx.hero`) — снапшот героя в ctx устаревает, свежие записи (brain/plan/law) затираются. Законные паттерны:

- `Law.add_bounty/clear_bounties` — **чистые** map-функции над `state_data["law"]`, результат протаскивается через `state_data_update`
- `template_engine.track_used` / `memory.ex` — только с `Repo.reload!(hero)` (свежее чтение)
- FSM-ветка `:jailed` в `tick/1` — `Map.delete(state_data, "jail")` при выходе

### 2.2 Миграции — идемпотентные (критично!)

В тестовой БД (`tes-godv-test`) живёт старый stub 20260716, создающий таблицы раньше полной миграции. Поэтому:

- `CREATE TABLE IF NOT EXISTS` + `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` для любой таблицы, которую могли создать старые миграции
- **Один `execute()` = один SQL statement** (multi-statement строка падает с `42601` в Ecto)
- `game_configs.id`/`description` — NOT NULL без дефолтов: при ручных INSERT давать `gen_random_uuid()` и description
- После правки миграций: `$env:MIX_ENV="test"; mix ecto.drop; mix ecto.create; mix ecto.migrate` (не забыть `ecto.create` после drop)

### 3. Seed Data

- [ ] Добавлена схема? → Обновить `priv/reseed.exs`
- [ ] Добавлены дефолтные значения? → В таблицу `game_configs` (сейчас: базовые, `brain`, `activities`, `law`, `world_kernel`, `world_limits`)
- [ ] Изменены нарративные шаблоны? → Обновить seed (29 типов: 20 базовых + 9 активностей)
- [ ] Новые template_type? → Обновить NarrativeDirector + `@state_to_template`/legacy-маппинг в template_engine

**Запуск seed — через mix:**

1. `mix ecto.reset` — drop + create + migrate + reseed + seed_fragments
2. Проверить результат через `mix ecto.migrations`
3. Точечные вставки: `seed_narratives.exs` (базовые), `seed_phase2.exs` (предметы fish/herb/lockpick + 40 шаблонов активностей, идемпотентный), `seed_fragments.exs` (124 описательных фрагмента в 30 пулах narrative_fragments: 8 предметных + 5 погодных опенеров + 3 mood-полосы + 8 quirk-пулов + 6 memory-пулов, идемпотентный; перезапуск добавляет только новые строки, существующие не обновляет)
4. **`mix run priv/seed_all.exs` — единый вход сида (только dev!):** narratives → phase2 → fragments → construction → guild_shop → skyforge → guild_news, идемпотентно. **test-БД сидировать НЕ надо** (кроме reseed+fragments из ecto.reset) — тесты самодостаточны и рассчитаны на чистые пулы; сид в test валит тесты «нет шаблона — честная тишина» и точные counts
5. Флаги локаций (`flags.water`/`gather_nodes`/`locked_buildings`) — часть данных мира, не seed: менять через SQL/админку по мере надобности
6. Грабля сидов: `@attr` вне defmodule в .exs — «cannot invoke @/1 outside module» (сид seed_narratives был мёртв, обёрнут в `defmodule SeedNarratives.run()` с дедупом по {type, text})

### 4. Тесты

- [ ] Добавлен endpoint? → Добавить тест
- [ ] Изменена логика? → Проверить существующие тесты
- [ ] Перед коммитом: `mix test`

---

## Архитектурные решения

### Hardcode — только в конфигах

Все игровые параметры (веса переходов, пороги, формулы) хранятся в:
- Таблица `game_configs` — runtime значения (key → JSON value)
- Используются через `ContextBuilder` → `ctx.configs`

**Не хардкодить** числа в `fsm_executor.ex`, `goal.ex`, `pipeline.ex`.

### Нарративы — только из БД

Шаблоны нарративов хранятся в таблице `narrative_templates` (29 типов: 20 базовых + 9 активностей — fishing/gather/steal/break_in/jail/pet_care):
- `source="system"` — дефолтные шаблоны из seed
- `source="llm"` — сгенерированные LLM (требуют approve)
- `source="community"` — предложения игроков (требуют approve)

**Не хардкодить** тексты в `template_engine.ex` / `narrative_director.ex`.

**Грабля `template_type = "combat"`:** это НЕ валидный тип — NarrativeDirector отдаёт combat-события только через `hero_victory`/`hero_defeat`/`combat_result`/`combat_start` (legacy-маппинг в template_engine). Шаблоны `combat` в БД — мёртвый груз (community-импорт, 0 использований за всё время): при обнаружении — удалить, в промптах генерации тип не упоминать. Аналогично тип `god` (записи журнала с entry_type "god" пишутся напрямую GodController'ом, минуя шаблоны-типы `god_*`).

**Грабля моджибейки имени героя:** имя из cp1251-источника (ручные INSERT, кривые скрипты) доходит до Postgres как «???????» — каждый непечатаемый байт замещён `?`. Такое имя через `{hero_name}` расползается по ВСЕЙ хронике (реальный кейс: 94 записи «???????» героя Хальвар до переименования). Защита: `Hero.changeset` валидирует `name` на отсутствие `?` (validate_format `^[^?]+$`) — легитимные имена вопроса не содержат. Старые битые записи журнала не чистятся (история), но новые герои с моджибейкой создаться не могут.

**Описательные фрагменты — Narrative.FragmentPool (N-1):** бывшие хардкодные пулы `@terrains`/`@discoveries`/`@landmarks`/`@combat_verbs`/`@npc_names`/`@fish_names`/`@herb_names`/`@witnesses` перенесены в таблицу `narrative_fragments` (pool_key, text, weight, source, is_active). `TemplateEngine` берёт их через `FragmentPool.draw/1` — пустой пул оставляет `{terrain}` видимым в тексте (честный сигнал). Новые пулы: строка в `priv/seed_fragments.exs` + `mix run priv/seed_fragments.exs`.

**Сцены — Narrative.Composer (N-2/N-3):** сцена = `[опенер погоды] + костяк-шаблон + [closer]`. Опенеры — пулы `openers_<weather>` (clear/cloud/rain/storm/snow — ключи World.Weather). Closer — иерархия, ровно один на сцену: (1) `quirk_<имя>` — персонажная реакция по причуде BrainHash (0..2 у героя, `NarrativeContext.quirks`); (2) `memory_<type>` — реакция на свежую память героя (victory/defeat/discovery/social/shop/travel из `state_data["memories"]`, давность ≤ `memory_days`); (3) `closers_<band>` — fallback по настроению (high ≥60 / mid / low ≤40, `{hero_name}` через `TemplateEngine.render_vars/2`). Рендер входит в выбор: фрагмент с непокрытыми `{var}` отбрасывается, иерархия идёт дальше (никогда не возвращает текст с дырками). Конкретика памяти доступна closer-текстам как `{monster}`/`{item}`/`{npc}` (именительный падеж!). Управление — `game_configs["composer"]`: `{"enabled", "types" — полные сцены, "closer_only_types" — боевые (только closer, без опенера), "opener_chance", "closer_chance", "quirk_chance", "memory_chance", "memory_days"}`; пустой конфиг или enabled=false → костяк без изменений. Composer вшит в `TemplateEngine.format/2` (рабочий путь Pipeline); event-имена смаппятся через `legacy_type/1`. `NarrativeContext` несёт `configs`, погоду ядра (`ctx.weather || "clear"`, легаси `location.weather` не читается), `quirks` (Genome.derive(brain_hash)) и `memories`. Важно: `weighted_random/1` в NarrativeDirector/Composer округляет float-веса (множители памяти 1.5/2.0) — `:rand.uniform/1` роняет тик на float.

Путь шаблона: `NarrativeDirector.select` → event.name → `@state_to_template`/legacy-маппинг в `TemplateEngine` → load_templates(event.name) → simple_context. Переменные действия (result[:context]) пробрасываются через `NarrativeContext.action_context` и мерджатся **поверх** пулов simple_context — так `{fish_name}`, `{witness_name}` из действий попадают в тексты. Pet-события (`pet_adopted`/`pet_left`/`pet_revived`) пишутся в журнал напрямую (entry_type = имя события), без шаблонов.

**Аналитика нарративов (A-2):** `TesIdle.Game.Narrative.Analytics` — read-only запросы из `journal_entries` + `narrative_templates`: `type_usage/1` (типы за N дней: count, ср. длина текста, последний раз — тонкие первыми), `daily_volume/1` (по дням), `unused_template_types/1` (активные template_type без записей журнала — «мёртвые»), `totals/1`. Endpoint `GET /api/v1/admin/narrative-stats?days=N` (NarrativeController `usage`, days 1..365, иначе 30). Frontend: вкладка «Аналитика нарративов» в админке (`NarrativeAnalyticsPanel`) — карточки-итоги, дневной volume-бар-граф, таблица типов (⚠ типы < 5 записей), чипы мёртвых шаблонов.

**Фабрика кандидатов (N-4):** `TesIdle.Game.Narrative.LlmFactory` — оффлайн-генерация кандидатов шаблонов: сцена из пулов (опенер погоды × активный system-шаблон типа × closer настроения), `{var}` нетронуты (рендер в рантайме), дедуп по тексту, cap 20. Кандидаты вставляются `source="llm", is_active=false` → вкладка «Модерация» → approve/reject (одобренные сразу в ротации). Endpoint `POST /api/v1/admin/llm-generate` `{template_type, count}` (409 если пулы пусты). UI — блок «Фабрика кандидатов» в ModerationPanel. Внешний LLM-бэкенд — точка расширения внутри LlmFactory (контракты не меняются).

**Фабрика × аналитика (A-2b):** `Analytics.factory_targets/1` — цели пополнения: тонкие типы журнала (count < 5) + мёртвые шаблоны, uniq+sort; приходит в ответе `narrative-stats`. Batch: `POST /api/v1/admin/llm-generate-batch` `{count_per_type}` — генерация по целям (до 8 типов × до 10 на тип за прогон), ответ `per_type`. UI — панель «Фабрика · цели пополнения» в NarrativeAnalyticsPanel (чипы целей warn-цвета, кнопка batch). Нюанс тестов: фабрика тянет погоду случайно из 5 ключей — сиды теста обязаны вставлять опенеры ВСЕХ погод, иначе нулевые вставки из-за пустого пула.

**Массовое одобрение (A-1b) + full_scene:** `POST /api/v1/admin/narrative-templates/approve-batch` — одобряет pending-шаблоны по `template_type`/`source`; без фильтров только с явным `all=true` (защита от слепого «одобрить всё»), `max` cap 200. UI — кнопка «Одобрить всё отобранное (N)» в ModerationPanel (confirm при отсутствии фильтра). **Контракт full_scene:** одобренная llm-сцена — уже полный текст (опенер+костяк+closer); `TemplateEngine.format/2` передаёт в Composer `full_scene: true` по `chosen.source == "llm"` (в обеих ветках, включая legacy-fallback), Composer не размножает её второй сценой. `load_templates/2` теперь отдаёт `%{text, source}` — `choose_template/track_used` работают по `.text`. Известный класс багов весов NarrativeDirector: после chain ×3 / memory-множителей weight бывает float — в dedup `div/2` падал (`ArithmeticError`); правило: все арифметики весов через `round/1` и `/`.

**Питомцы — видимость и история (P-1):** `hero_response` (GET /hero/me) отдаёт не всех питомцев, а `visible_pets/1`: активный/лечащийся (active/cooldown) всегда; ушедший (gone) — только пока у героя нет живого питомца (появился новый → gone исчезает с главной). Полный список ушедших — `Pets.history/1` → `GET /hero/pets/history` (новые первыми), UI — панель «История питомцев» в AnalyticsPage. Контракт протестирован в `test/tes_idle_web/controllers/hero_pets_test.exs` (7 тестов).

**Ручные действия (P-2):** мёртвые API оживлены UI. (1) Экипировка: «Снять» в EquipmentPanel (`POST /equipment/unequip/:slot`), «Надеть» в InventoryPanel для `type="equipment"` (`POST /equipment/equip/:id`); после действия InventoryPanel диспатчит `window`-событие `tes:hero-refresh`, DashboardPage по нему делает fetchData + refresh панелей. (2) Путешествия: **с M-3 переехали на страницу «Карта мира»** (ранее TravelPanel в правой колонке дашборда, компонент удалён) — кнопка «Идти» в инфопанели карты (`POST /locations/:id/travel`), disabled при занятом герое (fighting/traveling/jailed/fishing/...); backend travel переписан на cond + `Repo.reload!` перед записью state_data (правило единственного писателя, busy → 409), тесты `test/tes_idle_web/controllers/travel_test.exs` (4). (3) Предложения: вкладка «📨 Предложить» в мастерской нарративов (`pages/NarrativesPage.tsx`, маршрут `/narratives` — заменила модалку-словник) — форма через `POST /suggestions` (type="narrative", title="Шаблон: <label>", content=текст; **ключ тела — `suggestion_type`**, не `type`!) + список своих предложений со статусами; админ видит их через вкладку «Предложения» в админке (P-0): `PATCH /admin/suggestions/:id/approve {template_type?}` — для narrative с валидным template_type (2..40) текст **сразу становится активным community-шаблоном** (дедуп по {type, text}; без template_type — только статус), reject с admin_comment; ТЕСТЫ `suggestion_approve_test.exs` (4).

**Мастерская нарративов (S-UI):** модалка-словник (`NarrativeImportModal`) удалена — вместо неё полноэкранная страница `/narratives` (nav-кнопка «Словник» на дашборде ведёт туда же). Вкладки: «📖 Словник» (все группы переменных с падежными подсказками, поиск по словнику, клик-копирование), «✍️ Создать шаблон» (админ: сайдбар-чипы вставляют `{var}` в textarea, live-превью с примерами, `adminNarrativesImport` source="community"), «📨 Предложить» (авторы: та же форма через suggestions + «Мои предложения»), «🗄️ Шаблоны в базе» + «📥 Импорт JSON» (админ: примеры-пресеты `EXAMPLE_JSON` доклеиваются к текущему JSON). Данные — общий модуль `components/narrativeData.ts`: `TEMPLATE_TYPE_GROUPS` (полные 64 активных типа из БД, сгруппированы 9 смысловыми группами + flat `TEMPLATE_TYPES`), `VAR_GROUPS` (зеркало `simple_context` в template_engine.ex: `{location}`/`{generation}` — death_respawn-only, пулы FragmentPool с падежами: terrain дат./landmark род./discovery вин.), `previewTemplate`/`insertVariable`. AdminPage импортирует константы оттуда же; select формы создания в админке — optgroup по группам + хвост «Legacy». UI-фабрики LLM удалены из админки («Фабрика кандидатов» в ModerationPanel, «Фабрика · цели пополнения» + batch-кнопка в NarrativeAnalyticsPanel и api-методы `adminGenerateLlm*`) — backend endpoints и их тесты сохранены; пополнение шаблонов — через предложения авторов в мастерской. Полировка дашборда: `.main-grid` боковые 300/320 → 390/416px (+30%), `--container-max` 1440 → 1640px (центральная колонка не ужата), 2-колоночный брейкпоинт 1200 → 1400px.

**Репутация героя (P-3):** единая точка `Law.adjust_reputation/5` (hero_id, faction, delta, configs, hero_name): clamp ±100, пересчёт уровня по порогам из `rep_cfg(configs)["thresholds"]` (hostile ≤ −50 / unfriendly < 0 / neutral < 25 / friendly < 75 / allied ≥ 75), journal-событие `reputation_change` только при смене уровня (рост внутри уровня — без записи). Конфиг — `game_configs["law"]["reputation"]`: `quest_complete` (+5), `monster_kill` (+1), `crime` (множитель штрафа), `fine_paid`; дефолты в `ContextBuilder.load_configs`. Позитивные источники в Pipeline: победа в бою → `reputation_tick`, завершение квеста → `reputation_reward` (внутри check_quest_progress, без ctx — минимальный аналог через `ContextBuilder.load_configs`). `reputation_hit` теперь дельта-минус через adjust_reputation. GET /hero/reputations отдаёт `{reputations, thresholds}`. UI: ReputationPanel — числовое значение, бар по шкале −100..100, подпись «+N до следующего уровня». Тесты: `test/tes_idle/game/law_reputation_test.exs` (4).

**Контракт Action (критично!):** каждый Action обязан возвращать `{:ok, map} | {:error, reason}` — FSMExecutor/Pipeline матчатся на `{:ok, _}`. Голая карта от execute (`%{state_to: ...}`) валит тик героя с `no case clause matching` КАЖДЫЙ раз, когда выбрано действие — герой молчит в хронике неделями (реальный кейс: SocialAction, «умершая» хроника Джозеца). Проверка: `grep -L "{:ok," lib/tes_idle/game/actions/*.ex`.

**Грабля Enum.random на отфильтрованном списке (тихий убийца тиков, 2026-09):** паттерн `list |> Enum.filter(...) |> Enum.random() || fallback` НЕ работает — `Enum.random([])` кидает `Enum.EmptyError` ДО `||`; исключение абортит ВЕСЬ тик, GameTickWorker глотает его (`[warning] tick of hero … failed`), хроника молчит часами, герой «застревает» (реальный кейс: Джозец, дыры 125+ мин — TravelAction с квестом, чей step_type не дал ни одного подходящего назначения). Правило: `case Enum.filter(...) do [] -> fallback; xs -> Enum.random(xs) end`. Диагностика «тихого» героя: ручной `Pipeline.tick(hero.id)` из временного priv-скрипта воспроизводит краш мгновенно; герой виден по разрыву cadence (`max(created_at)` + gap между двумя последними записями) при живом `is_online=true`.

**CSS-хроники:** записи журнала обёрнуты в group-div главы (S-3) — flex-gap `.panel-body` действует только между группами; отступы внутри группы даёт `.journal-panel .panel-body > div > .journal-entry { margin-top: var(--space-3) }` в index.css.

**Тональная смесь пулов и наращивание нарративов (N-5):** сид-пулы расширены 124 → 201 строка (опенеры 5 погод, closers 3 полос, предметные пулы fish/herb/witness/npc/terrain/discovery/landmark/combat_verbs, квирки, memory) — тональная смесь ~50/50 «обычные + комичные» строки в каждом пуле: комбинатор LlmFactory сам даёт микс тонов без изменений кода. Новые строки добавляются только в `priv/seed_fragments.exs` + `mix run priv/seed_fragments.exs` (идемпотентно по {pool_key, text}); в dev и test БД сид гоняется отдельно. Массовая генерация по всем типам — `mix run priv/generate_all_narratives.exs` (12 кандидатов × 54 типа, дедуп по тексту), кандидаты идут в модерацию → approve-batch по 200 (cap). Нюансы: (1) тесты Composer/FragmentPool/фабрики изолируются от сида через `TesIdle.Test.FragmentIsolation` (`hide_seed_fragments/1`, `:all` для тестов «пулы пусты» — `fragments_available?/0` считает ЛЮБЫЕ активные фрагменты; restore в on_exit открывает свой sandbox-owner) — иначе draw() возвращает сид-строки и ассерты «точное совпадение» падают; (2) `approve-batch` `max` может прийти ЦЕЛЫМ из JSON — `Integer.parse/1` принимает только строки (FunctionClauseError → 500), поэтому `parse_int/1` с коэрцией. Тесты: `narrative_fragments_seed_test.exs` (4 — тональная смесь/размеры пулов), регрессионный на числовой max в `admin_llm_factory_test.exs`.

**Карта мира (M-1–M-3b):** интерактивная SVG-карта Скайрима — **полноэкранная страница** `/map` (nav «Карта»): канвас занимает всю рабочую область между топ-баром и статус-баром (`.map-shell` на контейнере в App при `pathname === "/map"` снимает max-width/padding, `.map-stage` — flex:1 без прокрутки), досье локации/войны/события — плавающие оверлеи с backdrop-blur справа (сворачиваемые), чип «Карта мира · сезон · день · погода» сверху слева, пилюля пути снизу. Backend: миграция 20260904120000 добавила `locations.map_x/map_y` (идемпотентно); координаты узлов — данные, не хардкод: расставлены в `priv/reseed.exs` по географии Скайрима (viewBox 1000×700) + UPDATE dev-БД; `GET /locations` отдаёт `map_x`, `map_y`, `flags` (тесты `locations_index_test.exs`). UI: `pages/MapPage.tsx` + `components/map/WorldMap.tsx` — узлы-станции по типу (город=двойное кольцо, деревня=круг, дичь=треугольник, подземелье=ромб), цвет кольца = danger_level (Низкая→success / Средняя→gold / Высокая→warn / Экстремальная→danger), бейджи 🏪/🍺, пульсирующая звезда героя, пунктирный «кометный» маршрут к `state_data.travel.destination_id` при hero.state="traveling". **Вид карты (M-3c):** зум колесом к курсору (×1..×4, непассивный wheel-listener — React onWheel пассивен, preventDefault через addEventListener), пан перетаскиванием (pointer events, порог 5px отделяет drag от клика — иначе выбор локации срабатывает при перетаскивании), кнопки ＋/－/⌖-центр на герое/⟲-сброс + индикатор ×N; clamp сдвига `x ∈ [1000(1−k), 0]` — края не оголяются. Легенда (геометрия типов + цвета опасностей) — чип снизу слева. Каскадное появление узлов — CSS-анимация nodeIn с animationDelay по индексу. В досье: описание, удобства, активности из flags, погода региона (`world.weather`), плотность (`world.density`), цены города (`world.prices`) + кнопка «Идти» (контракт P-2b: disabled при busy, role="status" notice). Дашборд разгружен: TravelPanel удалена, в «Здесь и сейчас» ссылка «Карта мира →». Доступность: узлы role="button" tabIndex=0, Enter/Space — выбор; aria-expanded на toggle досье. Нюансы: (1) SVG-хит-тест: формы узла НЕ имеют cx/cy — позиционирование только translate-обёрткой, иначе все контуры сваливаются в origin (0,0); (2) `fill="transparent"` ловит pointer-events, `fill="none"` — НЕТ; кликабельная прозрачная зона r24 обязательна, центр bbox группы попадает в зазор между контуром и подписью; (3) Vite-через-watch иногда пропускает правки тулзой — `touch` файла триггерит пересборку модуля (грабля: «правка не применилась» = stale module); (4) **selection через pointer-события, не onClick**: setPointerCapture на svg уводит click-событие на корень (клик по узлу «пропадает») — выбор локации делается на pointerup по узлу из `data-loc-id`, запомненному на pointerdown, порог 5px отделяет drag; (5) **letterboxing preserveAspectRatio**: svg-элемент 1280×621 с viewBox 1000×700 леттербоксится (scale = min(w/W,h/H) + центрирующий сдвиг) — screenToView обязан это учитывать, иначе зум-якорь и пан-дельты врут на ~44%; при этом узлы под оверлеем досье некликабельны (легитимно, как у карт с панелями). Декор карты (Море Призраков, Белая река, горы, компас) — только хроматика, игровые данные — только из API.

**Коммунальная стройка — «Часовня Девяти» (C-1):** вечный золотой сток в духе храма Godville. `World.Construction` — чистые функции (`step/4` — тик мира: «паломники» добавляют trickle; `donate/6` — взнос героя; `settle` — стадии/проекты хвостовой рекурсией: кит-донат может закрыть проект целиком; конвейер проектов зациклен, история последних 10). Состояние — ключ `"construction"` в снапшоте мира: **внутри снапшота и в персисте — сырой блок** (числовые индексы), наружу (REST `Kernel.snapshot/0` + все WS-broadcast'ы) — `Construction.summary` через `Kernel.public_snapshot/1` (имена/цель/прогресс/топ-донатеров). Kernel — единственный писатель; донат героя — `GenServer.call {:donate, ...}` (синхронный), офлайн-фоллбек `Construction.apply_offline/2` для тестов (Kernel выключен в test). Endpoint `POST /construction/donate` (min_donation из конфига, нехватка золота → 409, целое может прийти строкой); золото списывается и уходит из экономики. Журнал: `journal_donation` — шаблон `construction_donation` из БД (seed `priv/seed_construction.exs`, 6 вариантов тональной смеси), нет шаблона → записи нет (честно); **грабля: `TemplateEngine.render_vars/2` принимает ТОЛЬКО строковые значения** — целое 60 превращается в символ `<` (кодовая точка); конфиг — `game_configs["construction"]` (проекты/target/stages/trickle), дефолты — `Construction.default_config()` в `ContextBuilder.load_configs`. UI: секция «🏗️ Стройка» в WorldPanel (прогресс-бар, этап N/M, пресеты 10/50/200, disabled при нехватке золота, role=status notice). Тесты: `test/tes_idle/world/construction_test.exs` (10) + `construction_donate_test.exs` (4). Грабли: (1) `%{snap | "construction" => ...}` падает KeyError на старых персистах без ключа — использовать `Map.put`; (2) `journal_entries.entry_type` в dev-БД был varchar(20) — миграция 20260905120000 расширила до 64 (в test-БД уже была шире — легаси-расхождение схем).

**Карта: артвор-подложка + фикс выделения (P-1):** `Skyrim.svg` (3.5 МБ, 31000×31000, тексты в кривых — меток городов НЕТ текстом) скопирован в `frontend/public/skyrim.svg`; в `WorldMap.tsx` — `<image>`-подложка внутри вид-группы (до узлов), тумблер «🗺️» в кластере зума (persist `localStorage "tes:map-substrate"`), CSS `.map-substrate` (opacity 0.28 + grayscale через `data-muted`). **Калибровка — точная проекция, не «на глаз»:** границы провинции = общий bbox путей `Brdr_*` (X 1782..29098, Y 8911..29185); города — центры групп `City_x0020_S_x0020_<City>` (иконки 218×218; `Bldg_*`/`Wall_*` — хуже: здания включают фермы/башни); проекция провинции → 943×700 на канвасе (поля 28.5) даёт константу `SUBSTRATE = {x: -33, y: -308, w: 1070, h: 1070}`. Узлы синхронизированы с артворком: координаты в `priv/reseed.exs` пересчитаны той же проекцией + UPDATE dev-БД (Вайтран 552,226; Солитьюд 406,47; Виндхельм 744,150; Рифтен 813,410). **Выделение текста при пан-драге:** `.map-canvas, .map-canvas * { user-select: none }` + `e.preventDefault()` в onPointerDown; `image { pointer-events: none }` — подложка не ловит клики. `setPointerCapture/releasePointerCapture` обёрнуты в try/catch (синтетические PointerEvent без активного указателя кидают NotFoundError и роняли обработчики). Грабли: (1) пан при k=1 невозможен по дизайну (clamp) — проверять пан при зуме ≥1.3; (2) после правки тулзой — touch файла (stale Vite).

**Смерть с таймером (P-2b):** переход от мгновенного возрождения к двухфазному: (1) тик с `hp <= 0` (state != "dead") → `Pipeline.handle_death`: state="dead", `state_data["death"] = {respawn_at (naive ISO, now + respawn_ticks*60с), city_id/city_name (ближайший город по map_x/map_y — сам город при dist 0)}`, −10% золота сразу; журнал смерти НЕ пишется (его пишет тик поражения через state_to "dead" → тип death; внебоевая смерть — честная тишина). (2) Тики в state "dead" → `handle_dead_tick`: до respawn_at — тихий тик (delta без изменений), после — `respawn/4`: `Brain.Learner.reborn` (поколение +1, mutation черт), телепорт `location_id = city_id`, hp = `trunc(max_hp * respawn_hp_ratio)` (0.2), death-блок удалён, глава S-3 ["world"], запись в журнал ТОЛЬКО из БД — тип `death_respawn` (seed: 8 строк, {location} им. падеж + {generation}), нет шаблона — записи нет. Легаси-dead без блока → handle_death ставит блок. Конфиг `game_configs["death"]`: {gold_loss_percent 10, respawn_hp_ratio 0.2, respawn_ticks 3} (дефолты в `ContextBuilder.load_configs`). UI: `DeathOverlay` в DashboardPage — danger-панель с таймером mm:ss (парс `new Date(x + "Z")` — грабля TZ), city_name из блока. Тесты: `test/tes_idle/game/death_respawn_test.exs` (4). Грабля: `journal_entries` — колонка `created_at` (не inserted_at). Грабля сида: seed-файлы insert-only по {type, text} — после переписывания текстов старые строки остаются: удалить старые `DELETE FROM narrative_templates WHERE template_type='death_respawn'` и перегнать сид.

**Тюрьма: решётка + комичные нарративы (P-3):** пул `jail` в `priv/seed_phase2.exs` расширен 4 → 12 строк (тональная смесь, комичные «Паук в углу молчит уже третий час…», «Тюремный повар назвал своё варево „утешением“…»); сид идемпотентный, в dev 24 активных. Инвариант: jail-шаблоны используют ТОЛЬКО {hero_name}/{jail_reason}/{jail_ticks} — они есть в simple_context всех jail-событий (serve/escape-fail/release) → ни одной {var}-дырки; проверяется файловым тестом (пул ≥ 12 строк, vars ⊆ whitelist) в `jail_narrative_test.exs` (+ интеграционный: serve-тики продвигают отсидку, release → exploring + jail null). UI: `.jail-bars-overlay` (DashboardPage при state="jailed") — fixed-оверлей решётки поверх всего дашборда: repeating-linear-gradient вертикальных баров + верх/низ-виньетка, opacity 0.22, z-30, pointer-events none (клики проходят), анимация jailIn. **Грабля PowerShell 5.1:** даже `.Replace()` через конвейер даёт BOM (U+FEFF) — Elixir-компилятор падает «unexpected token U+FEFF»; правка кириллицы только edit/write-тулзами, снятие BOM: `[IO.File]::WriteAllBytes($p, $bytes[3..($bytes.Length-1)])`.

**Сны при долгом отдыхе (P-4):** `Game.Sleep` — кандидат-функция (дух world_news_candidate, без Repo-вставки): при `result.state_to == "resting"` streak+1 в `state_data["sleep"] = {streak, last_dream_day}`; при streak ≥ min_streak И last_dream_day != game_day И :rand < dream_chance — `draw_template()` (тип `dream`, source system, активный, RANDOM) → `{merged_sd, template}`, иначе {merged_sd, nil}; **вне отдыха блок sleep удаляется** (streak обнуляется). Вставку записи делает Pipeline (`create_dream_entry`: render_vars {hero_name}/{location_name} + JournalEntry entry_type "dream" с главой) — до единственного сохранения state_data (правило 2.1); нет шаблона — записи нет. WS: `dream_entry` пушится в HeroChannel как отдельная journal_entry (копия блока world_news). Конфиг `game_configs["sleep"]` {dream_chance 0.35, min_streak 3} + дефолт в `ContextBuilder.load_configs`; seed `priv/seed_narratives.exs` — 8 строк dream (тональная смесь, {location_name} — именительный: «Проснулся — всё по-прежнему: {location_name}, солома»). Тесты: `sleep_test.exs` (4: streak/сброс, min_streak барьер, честная тишина пустого пула, кандидат+дневной кап+рендер без дырок). QA-грабля: live-проверка через временный game_configs["sleep"] {dream_chance 1.0, min_streak 1} + SQL state="resting" — после проверки вернуть 0.35/3.

### Гильдии — каркас (G-0)

Гильдии (план: `docs/PLAN_RETENTION_GUILDS.md`, фазы G-0..G-6) — второе направление удержания. **G-0 готов:** миграция `20260905130000` (4 таблицы: guilds, guild_members, guild_offerings, guild_messages — последние две пока пустые, придут в G-1/G-2), схемы `Schemas.Guild/GuildMember/GuildOffering/GuildMessage`, модуль `Game.Guilds` (create/join/leave/list/show + `cfg/1` — блок `game_configs["guild"]` с fallback-дефолтами), контроллер `GuildController` + роуты `/guilds*`. Инварианты: **одна гильдия на игрока** (guild_members.user_id UNIQUE), создание платит `guild.create_cost` (500) золотом героя — сток золота №2, policy != "open" → честный 409 `policy_closed` (заявки — G-4), выход лидера → старший офицер/макс-вкладчик (`successor_member`), последний участник распускает гильдию (`:disbanded`). Эмблемы — whitelist 8 (Guild.emblems), имя 3–24 unique. API: `GET /guilds` → `{guilds (с member_count), my}`; `POST /guilds` (400 validation / 409 already_in_guild|not_enough_gold); `GET /guilds/:id` (детали+состав); `POST /guilds/:id/join|leave`. **Грабля timestamps:** в raw-SQL миграциях колонка `created_at`, а `timestamps()` ждёт `inserted_at` → всегда `timestamps(inserted_at: :created_at, updated_at: false)` (или joined_at), типы naive_datetime (`:utc_datetime` падает на микросекундах `DateTime.utc_now/0`). Frontend: `pages/GuildPage.tsx` (лендинг: список-карточки + форма создания с picker'ом эмблем/политики; в гильдии: шапка + состав с ролями/вкладом + «Оставить знамя»/«Покинуть»), nav «Гильдия», типы в `stores/guildStore.ts` (отдельный файл: GUILD_EMBLEMS/GUILD_POLICY_RU/GUILD_ROLE_RU). Тесты: `test/tes_idle_web/controllers/guilds_test.exs` (11: create/join/leave/лидерство/распад/index/show).

### Гильдии — Алтарь (G-1)

Подношения золота: `POST /guilds/:id/offerings {amount}` → `Game.Guilds.offer_gold/4` (транзакция: золото **сгорает** — сток №3; exp гильдии `+= amount × exp_per_gold`; очки жертвователю `round(amount × points_per_gold)` **с дневным капом** `daily_points_cap` — остаток считается по `guild_offerings` за сегодня UTC; запись в хронику). Level-up: `threshold_for/2` = `level_exp_base × level_exp_growth^(level−1)` (1000, 1400, 1960…), хвостовой `level_up_loop` может перескочить несколько уровней, при росте — системное сообщение в `guild_messages` (`kind="system"`, user_id null). Бафы: `Guilds.buff_for/2` = `buffs_per_level × (level − 1)` — на 1 уровне нули, на 20-м +38% XP / +19 атаки / +190 HP (по духу кэпа Brain.Graph). **Точки применения (Bottom-Up):** (1) `GameContext.guild_buff` заполняется в `ContextBuilder.build` (`Guilds.buff_for_user/2` — 1 query/тик); (2) `Pipeline.apply_progression/3` — третий аргумент guild_buff, xp × (1 + xp_mult) **поверх** прогрессии S-4; (3) `fight_action` — атака `+ attack_flat`, стартовый HP боя `hero.hp + hp_flat` (баф «свежих сил», в БД не пишется). `hero_response` → блок `guild: {id, name, emblem, level, role, points, contributed, buff}`. `GET /guilds/:id` отдаёт `offerings` (хроника) + `my_altar` (points/points_today/daily_cap) + `exp_to_next`/`buff` гильдии. UI: панель «🔥 Алтарь» в GuildPage (exp-бар, бафы, пресеты 10/100/500 + своя сумма, мой вклад, хроника последних 5). Тесты: `guild_altar_test.exs` (8: подношение/кап/level-up/ошибки/баф/threshold/apply_progression) + 4 в `guilds_test.exs` (API offer/hero_response). Нюанс: `Ecto.Multi.insert` с fn → nil падает — условные шаги добавляй в multi через `if`, а не через nil из fn.

### Гильдии — Чат (G-2)

`GuildChannel` — topic `guild:<id>`: джойн требует членство (`Guilds.membership/1` в join-клозе, посторонний → `not_a_member`); клиентский `new_msg {body}` → валидация (не пусто, ≤ `guild.chat_max_len` 200, rate-limit `guild.chat_rate_limit_sec` 2с по времени последнего chat-сообщения юзера в БД — источник правды, без ETS) → insert + `broadcast!("chat_message", …)` + `Guilds.Prune.prune/1`. REST-фоллбеки: `GET /guilds/:id/messages` (последние 50, left_join user, системные → username «Системное»), `POST /guilds/:id/messages` (та же валидация; 429 `rate_limited`; успешный send делает `PubSub.broadcast` в topic `guild:<id>` — WS-подписчики GuildChannel получают событие тоже). Prune (`Game.Guilds.Prune.prune/2`) держит последние 500 на гильдию (`NOT IN subquery` по desc inserted_at) — вызывается после каждого insert. `GET /guilds` my-блок теперь несёт `user_id` (фронт подсвечивает свои сообщения). UI: панель «💬 Чат» в GuildPage — polling REST 4с, input 200 симв, Enter-отправка, кулдаун-кнопка 2с, автоскролл, системные строки золотым курсивом. Тесты: `guild_channel_test.exs` (6: join-членство/без user_id/broadcast/валидация/rate-limit/prune) + 2 в `guilds_test.exs` (REST send/read/409 + 429/400). **Нюансы:** (1) ChannelCase нет в проекте — `test/support/channel_case.ex` с `start_owner!`-паттерном (`checkout` в тесте поверх → `{:already, :owner}`); (2) PowerShell 5.1 `Get-Content | Set-Content` МОДЖИБАЧИТ UTF-8-файлы без BOM (см. S-заметку) — восстанавливается инверсией `utf8_read → cp1251_encode`, но лучше не трогать файлы с кириллицей через конвейер; (3) `Repo.insert_all(schema, list_of_structs)` падал `Enumerable` — в тестах простые `Repo.insert!`.

### GameContext — только `.field`, никогда `ctx[:key]` (критично!)

`GameContext` — struct; синтаксис `ctx[:guild_buff]` компилируется, но падает в рантайме (`GameContext does not implement Access behaviour`) — и GameTickWorker глотает ошибку (`[warning] tick of hero … failed`) **у всех героев каждой волны**: хроника молчит, герой не двигается, а компиляция зелёная. Реальный простой 40+ минут в проде после G-1. Правило: доступ к ctx — только `ctx.field`; перед коммитом `grep "ctx\[" lib/` — должно быть пусто.

### Гильдии — Лавка (G-3)

Каталог — `game_configs["guild_shop"]["catalog"]` (fallback в ContextBuilder): `[%{"name", "points"}]` — предметы ищутся **по имени** (UUID между БД разный; seed `priv/seed_guild_shop.exs`: «Плащ Соратников» body +3/+10, «Знак гильдии» amulet +2, «Эликсир Соборности» consumable +40HP/+30SP/баф +2 — грабли сидов items: weight/speed_bonus **float**, reduce_hunger/reduce_fatigue/boost_morale/soul_restore NOT NULL — давать 0.0; подсчёт по tags-ARRAY — `@> ARRAY[?]::varchar[]`, не like). `Game.Guilds.Shop.buy/4`: membership → цена → очки члена ≥ цена → Multi (member points−, inventory insert_or_update: consumable накапливается quantity+1) → журнал через шаблон `guild_shop_purchase` из narrative_templates (render_vars только строки; нет шаблона — записи нет). **Очки не передаются между игроками.** API: `GET /guilds/shop` (каталог + item-сводки + my_points; item:null если сида нет — честный disabled), `POST /guilds/shop/buy {name}` (200 / 404 unknown_item / 409 not_enough_points|not_in_guild). Роуты `/guilds/shop*` стоят **до** `/guilds/:id`. UI: панель «🛒 Лавка» в GuildPage (баланс очков в шапке, statLine статов, кнопка цены disabled при нехватке). Тесты: `guild_shop_test.exs` (5: покупка/накопление consumable/нехватка/неизвестный+чужой/catalog) + 3 в `guilds_test.exs` (API каталог/покупка/404+409).

### Гильдии — Роли и заявки (G-4)

Миграция `20260905140000` — `guild_applications` (status pending/approved/rejected, частичный UNIQUE по user_id при pending; **timestamps колонка TIMESTAMP без TZ** — G-0-конвенция, timestamptz ломает naive-schema). `Game.Guilds`: `apply_to_join/2` (policy request → заявка; open → `:policy_open`, invite → `:policy_closed`), `list_applications/2`+`decide_application/3` (officer+ через `officer_of/2`; approved → member + системное «вступает в знамя» + прочие pending юзера отклоняются), `set_role/4` (только лидер, роль officer|member, **кап 3 офицера**, лидера менять нельзя), `kick/3` (officer+, кикаются только member, системное «кикнут»). **Join-контракт изменился:** policy=request теперь 200 `{status: "application_pending"}` вместо 409 policy_closed. API: `GET /guilds/:id/applications`, `POST /guilds/:id/applications/:app_id {decision}`, `POST /guilds/:id/members/:user_id/role`, `.../kick` (403 forbidden / 409 officers_cap|cannot_kick_officer|cannot_change_leader). UI: панель «📋 Заявки» (только officer+, скрыта без заявок), кнопки «↑ Офицер / ↓ Рядовой / Кикнуть» в составе (только лидер), лендинг при request показывает «Заявка подана». **Грабля `system_message/1` ждёт guild_id, не структуру.** Тесты: `guild_roles_test.exs` (5) + 2 в `guilds_test.exs` (join-заявка/approve + роли/кик через API).

### Небесная кузня (C-2)

Личный сток золота: заточка предмета экипировки. Таблица `sharpenings` (hero_id+item_id UNIQUE, level; миграция `20260905150000`) — заточка **личная** (каталоговые items общие). `Game.Skyforge`: `price/2` = `round(base_cost × level^growth)` (level = следующий, 1→50 … 10→3155), `enhance/4` — слот экипирован → level<cap → золото ≥ цена → списание (золото в никуда — чистейший сток) + level+1, журнал `enhance_success` (шаблон из БД, `priv/seed_skyforge.exs` — 6 тонов + game_configs[skyforge]). Прибавка плоская: weapon/amulet — +1 **attack** за уровень, остальные слоты — +1 **defense** (`bonus_for_slot`); применяется в `fight_action.get_equipment_bonuses` через `Skyforge.equipment_bonus/1`. Конфиг `game_configs["skyforge"]` (base_cost 50, growth 1.8, cap 10, fail_chance 0 — без провала по плану). API: `POST /equipment/enhance/:slot` (200 / 404 empty_slot / 409 cap_reached|not_enough_gold); **`GET /equipment` сменил контракт**: `{slots: {...}, hero_gold}` (было голым slots-объектом). UI: в EquipmentPanel кнопка «⚒ N🪙» рядом с «Снять» (disabled при нехватке золота/кэпе → «⚒ предел»), бейдж «⚒+N» у заточенного, после покупки — `tes:hero-refresh`. **Грабли:** GameConfig схема — поле `value` (не value_json); PowerShell-пайп с кириллицей в .exs → моджибайка (восстановление utf8→cp1251→utf8, но лучше edit-tool); `Repo.one!(...) |> Repo.get!(Schema)` — пайп подставляет в schema-позицию.

### Гильдии — Вести (G-5)

Мировой фид событий: таблица `guild_news` (guild_id nullable — гильдия может распуститься, template_type, text; миграция `20260905160000`). `Game.Guilds.News.broadcast/3` — рендер из narrative_templates (source system, активные; **нет шаблона — записи нет**), `feed/1` — последние 50, новыми первыми. Триггеры в `Guilds.create/4` (весть `guild_founded`: {guild_name} {emblem} {leader}) и `offer_gold/4` после транзакции при `g.level > guild.level` (`guild_levelup`: {guild_name} {emblem} {level}; **обновлённый guild-struct из Multi, не старый**). Шаблоны — `priv/seed_guild_news.exs` (4+4 тональной смеси, идемпотентно). API: `GET /guilds/news` (роут **до** `/guilds/:id`). UI: Wiki-вкладка «📯 Вести гильдий» (`WikiPage` — кастомный `GuildNewsContent` вне md-файлов, как ai-prompts; пустое состояние честное). Достижения-триггеры (гильдия недели/врата C-3) — на будущее: просто новые template_type + broadcast в точке детекта.

### Гильдии — Казна и пир (G-6)

Общий ресурс гильдии: `guilds.treasury` (integer) + `guilds.boost_until` (naive) + журнал `guild_treasury_log` (kind deposit/withdraw, balance_after; миграция `20260905170000`). Вклад — `Guilds.treasury_deposit/4` (золото героя **замораживается** в казне: не очки, не exp; вывод героям запрещён, тратится только на проекты — паттерн «piranha tank» без утечки). **Пир** — `Guilds.feast/3` (офицер+ через `officer_of/2` — возвращает `{guild, member}|nil`, а НЕ bool): списывает `feast_cost` (300) из казны, ставит `boost_until = now + feast_hours` (4 ч), системное сообщение «🍻 Пир! До HH:MM…» + весть `guild_feast` в мировой фид. Баф пира: +`feast_xp_mult` (0.05) к xp_mult **поверх бафа уровня** — вшит в `buff_for_user/2` (ContextBuilder 1 query: select уровня + boost_until; `feast_active?/1` — naive-сравнение). Пир повторным запуском продлевается. Конфиг — `game_configs["guild"]`: feast_cost/feast_hours/feast_xp_mult (fallback в `cfg/1`). API: `POST /guilds/:id/treasury {amount}` (200 / 400 bad_amount / 409 not_in_guild|not_enough_gold), `POST /guilds/:id/feast` (200 / 403 forbidden / 409 not_in_guild|not_enough_treasury); `GET /guilds/:id` → блок `treasury: {amount, log, feast_cost, feast_active, boost_until, my_can_feast}`. UI: панель «💰 Казна» в GuildPage (вклад 50/200/500+своё, книга казны, кнопка «🍻 Пир · 300🪙» для офицер+, активный пир → статус «+5% опыта ещё N мин»). **Грабля TZ:** `boost_until` — naive UTC; фронт обязан парсить `new Date(x + "Z")`, иначе таймер врёт на часовой пояс (60 мин вместо 240). **Грабля officer_of:** return-тип `{guild, member}|nil` — case на `nil`, не на `false/true`. **Грабля seed:** добавил шаблон в сид-файл → перезапусти сид в dev (весть молча не пишется — «нет шаблона — записи нет»). Тесты: `guild_treasury_test.exs` (6: вклад/лог, нехватки, пир+весть+сообщение, роли, buff_for_user с пиром, feast_active?) + 3 в `guilds_test.exs` (API вклад/show/пир).

### Врата Обливиона (C-3)

Событийный коммунальный сток — финал плана удержания. `World.Gates` (чистые функции по духу Construction): ключ `"gates"` в снапшоте мира — сырой блок `{status, location_id/name, fund, target, opened_tick, deadline_tick, donors (hero_id→сумма), donor_names, cooldown_until_tick}`, наружу — `Gates.summary(block, tick)` через `Kernel.public_snapshot/1`. Цикл: closed → редкий шанс открытия (`open_chance` 0.02/тик, только над `city`, cooldown 48 тика блокирует; `step/5` принимает `roll` — инъекция случайности для тестов) → open (событие `oblivion_gate` ttl = срок) → игроки наполняют «фонд экспедиции» (`Gates.donate/6` — золото героя **сгорает** в фонд; топ-донатеры в summary) → фонд ≥ target → закрытие + событие `gate_closed` + **весть `gate_closed` на Wiki** (Kernel.handle_call вызывает News.broadcast, template_type из seed_gates) ЛИБО срок истёк → collapse (`gate_fallen`, фонд сгорает, cooldown «врата позже»). Пока открыты — регион в опасности: `Economy.apply_gate` — цены города ×1.3. Конфиг `game_configs["gates"]` {open_chance, fund_target 2000, deadline_ticks 72, cooldown_ticks 48} (fallback `default_config/0`; **value в GameConfig — Jason.encode! строка**). Kernel — единственный писатель; взнос героя `Kernel.gate_donate/3` (GenServer.call, синхронный, `News.broadcast` после транзакции), офлайн-фоллбек `Gates.apply_offline/3` для тестов (Kernel выключен в test). Endpoint `POST /gates/donate` (min 10, нехватка → 409, **гонка с тиком: `:not_open` после списания → золото возвращается**), админ-форс `POST /admin/world/gates/open` (`Gates.open/4` публичный). Журнал: `gate_donation` — шаблон из БД (seed `priv/seed_gates.exs`: 6 donation + 3 closed вести), render_vars только строки. UI: секция «🌀 Врата Обливиона» в WorldPanel (прогресс-бар danger-цвета, срок в тиках, топ-донатеры, пресеты 50/200, open→закрыт: «запечатаны — тихо»), иконки событий 🌀/✅/☠️, Wiki-бейдж «🌀 Врата» в GUILD_NEWS_TYPE_RU. Тесты: `test/tes_idle/world/gates_test.exs` (11: step открытие/cooldown/roll/collapse, donate копит+закрывает/not_open/bad_amount, summary, cfg, **Economy surcharge ×1.3**) + `gates_donate_test.exs` (4: взнос+журнал, кит закрывает+событие, gates_closed возврат золота, минимум/строка). Грабли: (1) локации в test-БД уже сидированы (`locations.name` UNIQUE) — в тестах искать существующий город, не вставлять «Вайтран»; (2) полный тест-прогон и существующие economy-тесты не сломаны — fair-скидка и gate-сурчард независимы.

### Переменные в шаблонах — SafeMap

`TemplateEngine.format()` заменяет переменные `{var}` regex-ом. Отсутствующие переменные остаются как есть (не крашат). Каждый тип шаблона имеет свой набор переменных — проверять при добавлении нового типа. Словник переменных для авторов — `components/narrativeData.ts` (VAR_GROUPS) на странице «Мастерская нарративов» (`/narratives`); при добавлении переменной в `simple_context` — обновить словник.

### Страницы ошибок — TES-флейвор (E-1)

404/500 в духе мира. Frontend: `pages/ErrorPages.tsx` — 404 «Донесение имперского курьера» (плакат гильдии: двойная золотая рамка, гигантская цифра Cormorant, случайная шутка из пула, кнопки «Назад»/«На панель героя») и 500 «Сервер пал в бою» (danger-виньетка в духе DeathOverlay) + заготовки 400/429. ErrorBoundary в `App.tsx` рендерит 500 при крэше рендера. **Грабля auth-гейта:** AppLayout раньше возвращал AuthPage ДО `<Routes>` — 404 не был виден гостям; теперь список `KNOWN_PATHS` проверяется первым: неизвестный путь → NotFoundPage ВСЕМ (гостям тоже), известные пути — по правилам авторизации. Новую страницу добавлять и в `<Routes>`, и в `KNOWN_PATHS`. CSS — `.err-*` блок в index.css (токены системы, `prefers-reduced-motion` уважается глобально). Backend: `error_json.ex` — `@flavor` карта статус → пул шуток (404/500/401/403/429/400); поле `detail` автоматически попадает в error-тосты фронта (api.ts читает `data.detail`), `message` — стандартный статус для логов; нестандартные статусы — честный дефолт без флейвора. Нюанс dev: Phoenix в dev-режиме показывает debug-страницу для NoRouteError вместо ErrorJSON (прод-поведение — JSON); api.ts уже умеет оба случая (fallback `HTTP {status}`).

### Ленивые офлайн-тики + WS-стабильность (O-1, 2026-09)

**Офлайн-герои тикаются медленно:** `GameTickWorker` (30с волна) делит героев по `is_online` — онлайн-герои тикаются каждую волну, офлайн — раз в `offline_tick_minutes` (config.exs, дефолт 15) с детерминированным джиттером ±20% от UUID героя (первый байт hex / 255 — переживает рестарт воркера, расписание не сбрасывается). Метки офлайн-тиков (`offline_marks`) в state GenServer — рестарт сервера сбрасывает их (первый офлайн-тик после рестарта наступает через интервал от старта воркера, это ок). Флаг `is_online` живёт: WS-heartbeat → `HeroChannel.handle_in("heartbeat")` → `ActivityFlushWorker.mark_activity` (ETS `:hero_activity`) → flush каждые 30с в БД; REST `POST /hero/heartbeat` (фронт пульсирует раз в 60с из `useWebSocket` как резерв при лежащем WS); `sendBeacon` на beforeunload → `is_online: false`. **Грабля диагностики:** «тишина в журнале офлайн-героя» ≠ «тики не идут» — боевые раунды НЕ пишут записи (только финал `hero_victory`/`combat_defeat`); проверять ручным `Pipeline.tick/1` или по интервалам между записями (15-20 мин = норма), не по плотности.

**WS-стабильность (`useWebSocket.ts`):** три бага починены. (1) Серверный close с кодом 1000 (рестарт Phoenix, idle-timeout) раньше НЕ планировал реконнект — статус «Переподключение…» висел до F5; теперь close 1000 реконнектится по бэкоффу (5s→30s). (2) Мгновенный реконнект при возврате на вкладку: `visibilitychange` (visible) + `online` события сбрасывают бэкофф и коннектятся сразу — фоновая вкладка больше не ждёт троттленного таймера до 30с. (3) REST-пульс `api.heartbeat()` раз в 60с из хука — герой не «умирает» для воркера при лежащем WS. **Грабля проверки:** убить сервер при открытой странице → статус «Переподключение…»; поднять → через ≤30с (бэкофф-цикл) статус сам вернётся к «Герой действует» — без F5. **Грабля VPN/портов:** если dev-порт слушает только `[::1]` (IPv6), а переадресации портов VPN закрыты — браузер на 127.0.0.1 получит ECONNREFUSED; это сеть, не код.

### Авто-экипировка — мотивация

Герой периодически (5-10 тиков) проверяет инвентарь:
- **70%** — лучшая по статам (attack + defense + hp)
- **30%** — случайный выбор (настроение, характер)
- Экипировка обновляется через WebSocket

### WebSocket — delta updates

Отправляются только изменённые поля hero_update через `GameTickWorker.compute_delta()`. state_data отправляется всегда.

Каналы:
- `hero:<hero_id>` (HeroChannel) — hero_update, journal_entry, combat_progress, world_update (мир дублируется в hero-канал, см. Фазу 3)
- `world:lobby` (WorldChannel) — push `world_update` с `%{"snapshot" => snap}` каждый тик ядра

Заметка: `useWebSocket` при смене hero?.id пересоздаёт сокет — cleanup старого срабатывает `onclose` асинхронно, поэтому `onclose` обязан игнорировать устаревший сокет (`wsRef.current !== ws`), иначе stale-close перетирает `connected` после onopen нового.

### Мозг героя — BrainHash (Фаза 1)

- **BrainHash** = SHA256(`user_id || ordinal`): у одного пользователя все герои разделяют одну «личность» (quirks + связи), перерождение сдвигает ordinal → новый мозг. Герой = сессия, мозг = аккаунт.
- `Brain.Genome` — детерминированная генерация quirks/связей из hash (seed через :rand). `Brain.Learner` — обучаемость: plasticity 10 пунктов/неделю, дрейф связей ±0.3, при перерождении generation +1, связи сохраняются.
- `Brain.Graph.enrich/2` — модификатор utility целей от причуд/связей, **жёсткий кэп ±0.15** — мозг раскрашивает, но не решает за героя. **Аудит 2026-09 (Фаза 1):** (1) связи взвешиваются **по цели** — `@link_goals` в graph.ex маппит пару черт на поддерживаемые цели (`greed~dexterity` → steal/break_in, `empathy~patience` → pet_care/fish…), нормировка на число поддерживающих связей, а не на все 15 (раньше был один агрегат — константа для всех целей); (2) причуды погоды (`superstitious`/`afraid_of_water`) читают `ctx.weather` — **ключи ядра мира** (`rain`/`storm`/`snow`), НЕ легаси `location.weather` (заморожен в БД) и НЕ русские названия; (3) гомеостаз `return_to_base` срабатывает **раз в игровой день** (`brain.last_return_day`), а не каждый тик — иначе 0.02/тик съедает недельный бюджет пластичности (10 п.) и личность застывает у гено-базы. Грабля тестов: детерминированный геном с причудой — `Genome.brain_hash("quirk-user-7")` → `[:superstitious]`, `"quirk-user-1"` → `[:afraid_of_water]`.
- **Аудит поведения 2026-09, Фаза 2/3 (приоритеты):** (1) критические нужды бьют квест — `Goal.urgent_needs?/1` по `game_configs["needs_urgent"]` (fatigue > 75 / hp < 50%): rest/heal +0.35, quest −0.3; (2) квест base 0.45 (не автопобедитель), travel-тяга квеста только при невыполнимом на месте шаге (`quest_step_needs_move?/1`), `TravelAction` выбирает локацию по типу шага (collect → city/village, kill → wilderness/dungeon) — иначе герой метается между случайными локациями; (3) окно активностей: после завершения квеста `state_data["activity_break_until_tick"]` (3–5 тиков), `maybe_auto_accept_quest/1` молчит в окне, маркер — через merged_sd (правило 2.1); (4) `check_quest_progress` — kill-шаг прогрессирует только при `combat_result` (victory), раунды `combat_progress` без результата не считаются; (5) **`apply_result` обязан применять `result[:fatigue_change]`** (RestAction/TravelAction возвращают его) — до фикса fatigue только рос и застывал на 100 (rest не работал физически); (6) NarrativeEvent события `shop`/`loot` (requires ["shopping"]/["looting"]) — без них покупки/добыча падали в generic_action; погодные теги NarrativeContext — только ключи ядра. Грабля: в test-БД Kernel выключен → `current_tick/0` = 0, окно активностей в тестах ставится руками (большой break_until). Грабля тестов: ассерты «после X герой делает именно Y» (jail → exploring) вали только против старого поведения — герой теперь свободен выбирать (loot/fish/...), проверяйте инвариант (не jailed), не конкретное состояние.
- Живёт в `state_data["brain"]` (запись только через merged_sd — см. 2.1), лог решений — `state_data["brain"]["decision_log"]` (последние 50).
- Frontend: `AnalyticsPage` (граф причуд/связей), слово «Личность» в UI вместо «Мозг».

### Активности, Law, питомцы (Фаза 2)

- **Контракт Action**: все действия возвращают `{state_data_update, hero_updates, narrative_event, action_result}`; new activities: FishingAction, GatheringAction, StealingAction, BreakingInAction, JailAction (mode serve/bribe/escape), PetCareAction.
- **LawSystem** (`game/law.ex`) — чистые map-функции над `state_data["law"]`: bounties (истекают 48 ч), witness_chance по типу локации, arrest при сумме ≥ 50, reputations по фракциям региона (lore map в `law.factions_by_region`). Тюрьма — FSM-состояние `:jailed` (mode выбирается один раз), план в `state_data["plan"]` переживает отсидку.
- **Скиллы** — `heroes.skills` JSONB: fishing/gathering/stealth/lockpicking (0–100, растут медленнее к 100). Влияют на успех/доход активностей; `Skills.bump` округляет.
- **Питомцы** — таблица `pets` (species/name/mood/hunger/loyalty/status: active|cooldown|gone, revive_at). `Pets.maybe_adopt` — вероятность при пустом слоте; уход офлайн/смерть хозяина → cooldown. Пет-тик в Pipeline (голод/настроение), события в журнал напрямую.
- **Состояние мира у героя**: hero видит активности только там, где есть флаги локации (water/gather_nodes/locked_buildings) — проверка через `ContextBuilder`.
- Frontend: PetCard (настроение/голод/верность), оверлей тюрьмы с таймером, бейдж «Разыскивается» (bounty), журнал-категория «Активности».

### Ядро мира — WorldKernel (Фаза 3)

Мир — отдельный GenServer `TesIdle.World.Kernel` (тик 60с, `game_configs.world_kernel.tick_ms`), **единственный писатель** мира; герои только читают. Супервизор: `maybe_child(Kernel, :world_kernel_enabled)`, `maybe_child(World.Aggregator, :world_aggregator_enabled)` (в test выключены).

```
Kernel.tick → Weather → Events → Factions (+войны/дефекция) → Economy → Migration
  → persist world_state (key="snapshot") → Snapshot.put (ETS :world_snapshot)
  → PubSub broadcast {:world_update, snap} на "world:lobby"
```

- **Снапшот** (`Snapshot.current/0`) — атомарное чтение из ETS с ленивой инициализацией. ContextBuilder кладёт в ctx `world` (весь снапшот) и `weather` (погода региона героя; legacy `location.weather` не читается).
- **Лимиты** (`game_configs.world_limits`): fight utility ±0.15, цены 0.6–1.8, encounter ±30%. Системы — чистые функции (`step/2`), протестированы отдельно (15 тестов в `test/tes_idle/world/`).
- **Обратное влияние** (`World.Aggregator`): герои cast'ят `purchase(city, category)` / `kill(location_id)`; раз в 5 мин Kernel забирает: цены +0.5%·√(n/10), плотность ×(1−0.002n). Один герой мир не двигает.
- **Точки интеграции с героем**: ShopAction — множитель цены `Economy.price_for(world["prices"], city, to_category(item))`; Goal.eval_fight — `world_density_mod` от `world["density"]`; ContextBuilder — эффекты погоды (дождь +fatigue −morale, снег +hunger) и fishing_bonus.
- **Войны**: relation ≤ −60 → объявление, мир при ≥ −30 (гистерезис); цены городов воюющих ×1.4. События (fair/monster_wave/dragon/eclipse) — TTL-тики, пул в `world_kernel.event_pool`; admin: `GET /admin/world`, `POST /admin/world/tick`, `POST /admin/world/events`, геройский `GET /api/v1/world`.
- **Тик героев** (W-0): `GameTickWorker` — `Task.Supervisor.async_stream` (max_concurrency из `:tes_idle, :tick_concurrency`), ошибка одного героя логируется и не роняет волну; delta считается от снапшота предыдущей волны.
- Frontend: WorldPanel на дашборде (погода региона/сезон/день/войны/события) — WS `world:lobby` + polling `api.getWorld()` как резерв.

### Game Pipeline — многоуровневая система решений

1. **Utility AI** (`Goal.best`) — оценка **14 целей** (quest, heal, rest, explore, fight, shop, socialize, travel, loot + Фаза 2: fish, gather, steal, break_in, pet_care) по personality + needs + memory
2. **Brain enrich** (`Brain.Graph.enrich`) — модификатор целей причудами и связями, **кэп ±0.15** (Фаза 1)
3. **GOAP Planner** (`GOAPPlanner.plan`) — пошаговый план для цели
4. **FSM Executor** (`FSMExecutor.tick`) — выполнение. Состояния по state_data: `combat`→:fight, `jail`→:jailed (тюрьма — НЕ цель, план переживает отсидку), `plan`→:execute, иначе :idle

Полный тик (`Pipeline.tick`): ContextBuilder.build (включая world-снапшот и weather) → FSMExecutor.tick → apply_result → auto_consume → check_quest_progress → pet_tick → track_memories → check_auto_equip (единый save state_data) → NarrativeDirector → TemplateEngine → journal → WS push.

### Multi-tиковые состояния

- Бой: 1 тик = 1 раунд, `state_data["combat"]`, WS `combat_progress` каждый раунд
- Путешествие: `state_data["travel"]`
- Рыбалка: `state_data["fishing"]` (ticks_left 1–5; улов возвращает `nil` по ключу — завершение multi-tick)
- Тюрьма: `state_data["jail"]` (mode serve/bribe/escape выбирается один раз по характеру)
- `multi_tick?/1` читает **truthy** ключи `state_data_update` — `nil` по ключу завершает multi-tick
- Журнал только при начале/результате события

### Визуальный стиль

Все UI компоненты следуют правилам из:
→ **`docs/VISUAL_RULES.md`** (система «Обсерватория» после редизайна F-0–F-5)

Ключевые моменты:
- Две темы: тёмная «Ночной уголь» (по умолчанию) и светлая «Пергамент» — `data-theme` на `<html>`, выбор в localStorage
- Панели: `.panel` → `.panel-header` + `.panel-body`, `border: 1px solid`, `border-radius: 12px`
- Шрифты: Inter (body), Cormorant Garamond (display), Fira Code (mono). ❌ Geist Sans — нет кириллицы
- Цвета: через CSS-переменные `--bg`, `--fg`, `--muted`, `--accent`, etc.; HUD: HP красный, MP синий, **SP зелёный**, XP фиолетовый
- **Запрещены фейковые данные в UI** — честные пустые состояния, реальные значения, данные только из API
- Компоненты живут в `components/` — инлайн-копии в DashboardPage запрещены (правило «двух JournalPanel» устарело после редизайна)
- Доступность: `:focus-visible`, `aria-label` на иконочных кнопках, `role="status"` на асинхронных баннерах, явные `transition`-свойства

### Админ-доступ

- Frontend: `isAdmin` в gameStore, вкладка "Админ" видна только админам
- Backend: `AdminPlug` на всех `/admin/*` endpoints (Guardian + is_admin check)

### Beta-0.7: сшивание мира (S-1–S-5, см. docs/PLAN_BETA_0.7.md)

- **S-1 Мир → Действия**: клёв/засады/воровство читают `ctx.weather` и `ctx.world` (легаси `location.weather` не используется). Schemaless-запросы к UUID-колонкам возвращают **raw binary** — в снапшот мира отдавать только типизированные schema-запросы (иначе Jason-крэш на персисте).
- **S-2 Brain.Intent** (`game/brain/intent.ex`): единое ядро решений — base_goals → Graph.enrich → world_stage (мир влияет по характеру, кэп `world_limits.utility_cap`; отброшенные цели не воскрешаются). `Goal.best` делегирует в Intent. `decision_log` содержит блок `world` (weather/events/wars).
- **S-2 FSM-инварианты** (критично, три бага Фазы 0):
  1. state_data_update от действий — **дельта** (`%{"combat" => nil}` для завершения боя), никогда весь старый state_data (иначе merge затирает advance_plan/decision_log);
  2. после завершения multi-tick-шага план шагает (advance_plan) — иначе бесконечный цикл на одном шаге;
  3. pipeline сохраняет state_data даже при nil-результате FSM (мгновенный шаг плана) — иначе план и решение теряются.
- **S-3 Дневник** (`game/journal/chapters.ex`): главы «День N. <фраза>» — граница = смена дня или перелом (мир-событие из `break_seen`/арест/уровень); фразы в `game_configs["journal"].titles`. Мотив решения — в `motive` записи только при создании плана (цель изменилась). «Новости мира» (`world_news`) — шаблоны в narrative_templates, шанс `news_chance`, ротация `news_seen` 20. Фронт: группировка по главам и семантические фильтры в едином `components/journal/JournalPanel.tsx`.
- **S-4 Прогрессия**: `Pipeline.apply_progression/2` — множители `game_configs["progression"]` (xp ×0.5, gold ×0.75 — только награды, траты не режутся), `Skills.gain/4` + `Skills.rate/1` — навыки ×0.5. Пустой конфиг = старый темп. Порог уровня — существующий `leveling.xp_multiplier` (×1.5), не дублировать.
- **Телеметрия**: `GET /api/v1/admin/brain/stats` — aggregate decision_log всех героев (цели, средний utility, мир-контекст).
- **Кодировка (PowerShell 5.1)**: `Invoke-RestMethod` шлёт body в Windows-1251 — кириллица в JSON превращается в `?`. Для запросов с кириллицей использовать браузер (fetch/Playwright) или PowerShell с UTF-8 body; игра (Phoenix/Jason) обрабатывает UTF-8 корректно.

---

## Быстрые команды

```bash
# Backend
cd tes_idle_elixir && mix phx.server
cd tes_idle_elixir && mix ecto.migrate
cd tes_idle_elixir && mix ecto.reset
cd tes_idle_elixir && mix test
cd tes_idle_elixir && mix run priv/seed_phase2.exs          # предметы+шаблоны активностей (идемпотентно)
cd tes_idle_elixir && mix compile --warnings-as-errors      # строгая проверка

# Frontend
cd frontend && npm run dev
cd frontend && npm run build

# Оба
start.bat
```

Админ-точки мира: `GET /api/v1/admin/world` (снапшот+события), `POST /api/v1/admin/world/tick` (форс-тик ядра), `POST /api/v1/admin/world/events` (форс-событие `{"type": "fair"|"monster_wave"|"dragon"|"eclipse"}`).

---

## Harness Skills

Проект подготовил 4 кастомных skills для DSH harness. Загружай нужный skill перед работой с соответствующей областью:

| Skill | Когда использовать | Ключевые файлы |
|-------|-------------------|-----------------|
| `tes-game-engine` | Game pipeline, FSM, GOAP, Utility AI, actions, combat | `pipeline.ex`, `fsm_executor.ex`, `goal.ex`, `goap_planner.ex`, `actions/*.ex` |
| `tes-narrative` | TemplateEngine, NarrativeDirector, narrative events, journal templates | `template_engine.ex`, `narrative_director.ex`, `narrative_event.ex`, `narrative_context.ex` |
| `tes-frontend` | React pages, components, Zustand store, WebSocket, Tailwind | `DashboardPage.tsx`, `gameStore.ts`, `useWebSocket.ts`, `api.ts` |
| `tes-ecto-schemas` | Ecto schemas, migrations, seed data, queries | `schemas/*.ex`, `priv/reseed.exs`, `priv/repo/migrations/` |
| `tes-qa-tester` | QA-тестирование: регистрация, герой, тики, god actions, проверка API | HTTP API через `Invoke-RestMethod`, smoke test скрипт |

Глобальные skills (поставляются с harness):
- `elixir-expert` — общие знания Elixir, OTP, concurrency
- `phoenix` — Phoenix framework best practices, Ecto, LiveView

## MCP-инструменты (подключены через `~/.dsh/profiles/web/cordis.patch.yml`)

Появляются в новых сессиях как `mcp__<server>__<tool>`:

| Сервер | Префикс | Назначение |
|--------|---------|------------|
| `postgres` | `mcp__postgres__*` | Прямой доступ к игровой БД (`tes-godv@62.122.99.214:54321`): SELECT, EXPLAIN, схемы, seed-данные. Использовать для отладки данных вместо временных `mix run`-скриптов. Осторожно с мутациями — dev-БД живая. |
| `playwright` | `mcp__playwright__*` | Реальный браузер (headless Chromium, 1280x720): UI-QA — логин, дашборд, god actions, админка, скриншоты для проверки VISUAL_RULES.md. Frontend на `http://localhost:5173`, backend на `http://localhost:4000`. |
| `context7` | `mcp__context7__*` | Актуальные доки библиотек: Phoenix 1.7, Ecto, React 19, Tailwind 4. Сначала `resolve-library-id`, затем `query-docs`. |

Конфиг: `C:\Users\juztm\.dsh\profiles\web\cordis.patch.yml` (изменение перезагружает соединение; в новой сессии инструменты доступны автоматически).

## Чек-лист перед коммитом

1. Backend: `mix test` проходит
2. Frontend: `npm run build` без ошибок
3. Если менялся API: frontend обновлён
4. Если менялись схемы: миграция создана (**идемпотентная** — см. 2.2)
5. Если менялись game_configs: дефолты в ContextBuilder + актуальные значения в dev-БД
6. Hardcode проверен — всё в конфигах/БД
7. Если менялся state_data: запись только через merged_sd (см. 2.1), ничего не пишет в `ctx.hero`
8. Если менялись world-системы: чистые `step/2`-функции протестированы в `test/tes_idle/world/`, Kernel не держит ничего кроме ETS/таймера