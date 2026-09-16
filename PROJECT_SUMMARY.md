# TES Idle — Project Summary

> Автономная RPG (idle/auto-rpg) в мире **The Elder Scrolls**, вдохновлённая Godville. Герой самостоятельно исследует мир, сражается, торгуется и отдыхает. Игрок наблюдает через нарративный дневник и вмешивается как «бог».

---

## Технологический стек

| Слой | Технология |
|------|-----------|
| **Backend** | Elixir 1.20 + Phoenix 1.7 (JSON API) |
| **Database** | PostgreSQL (Ecto + binary UUID PK) |
| **Auth** | Guardian (JWT) + PBKDF2 |
| **Real-time** | Phoenix Channels (WebSocket) |
| **Frontend** | React 19 + TypeScript 6 + Vite |
| **State management** | Zustand 5 |
| **Styling** | Tailwind CSS 4 + CSS custom properties |
| **Fonts** | Inter (body), Cormorant Garamond (display), Fira Code (mono) |
| **LLM integration** | LlmFactory (оффлайн-комбинатор пулов); внешний LLM — точка расширения |

---

## Архитектура

```
┌──────────────────────────────────────────────────────┐
│                    Frontend (Vite + React)            │
│  React 19 · Zustand · Tailwind · WebSocket hook      │
│  Дашборд · Админ · Пантеон · Wiki · Авторизация      │
└──────────────────┬───────────────────────────────────┘
                   │ HTTP JSON API (port 4000)
                   │ WS /socket/websocket
┌──────────────────▼───────────────────────────────────┐
│              Backend (Phoenix JSON API)                │
│                                                        │
│  ┌──────────────── Game Pipeline ──────────────────┐  │
│  │                                                  │  │
│  │  GameTickWorker (GenServer, 30s)                 │  │
│  │       │                                          │  │
│  │       ▼                                          │  │
│  │  ContextBuilder  →  загрузка героя, локации,     │  │
│  │                     инвентаря, квеста, конфигов   │  │
│  │       │                                          │  │
│  │       ▼                                          │  │
│  │  FSMExecutor     →  Utility AI → GOAP → FSM     │  │
│  │       │                                          │  │
│  │       ▼                                          │  │
│  │  Action Module   →  Fight / Explore / Rest /     │  │
│  │                     Shop / Travel / Loot / ...   │  │
│  │       │                                          │  │
│  │       ▼                                          │  │
│  │  apply_result    →  needs, mood, xp, gold, time  │  │
│  │  auto_consume    →  potions, food, soul stones   │  │
│  │  quest_progress  →  step tracking                │  │
│  │  track_memories  →  hero memory (last 20 events) │  │
│  │  auto_equip      →  every 5-10 ticks             │  │
│  │  NarrativeDirector → TemplateEngine → journal     │  │
│  │       │                                          │  │
│  │       ▼                                          │  │
│  │  PubSub broadcast → WebSocket push               │  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  Guardian JWT · Admin plug · CORS                      │
└──────────────────┬───────────────────────────────────┘
                   │ Ecto
┌──────────────────▼───────────────────────────────────┐
│              PostgreSQL                                │
│  13 таблиц: users, heroes, items, inventory_items,    │
│  equipment, locations, monsters, journal_entries,      │
│  quests, quest_steps, active_quests, reputations,      │
│  narrative_templates, suggestions, game_configs        │
└──────────────────────────────────────────────────────┘
```

---

## Структура проекта

```
tes-godv/
├── tes_idle_elixir/              # Backend
│   ├── lib/
│   │   ├── tes_idle/
│   │   │   ├── schemas/          # 13 Ecto схем
│   │   │   ├── game/             # Ядро игры
│   │   │   │   ├── pipeline.ex          # Главный оркестратор тика
│   │   │   │   ├── fsm_executor.ex      # FSM: idle→execute→fight→jailed
│   │   │   │   ├── brain/               # Фаза 1: genome (BrainHash), graph, learner, intent
│   │   │   │   ├── goal.ex              # Goal scoring (14 целей, делегирует Brain.Intent)
│   │   │   │   ├── goap_planner.ex      # GOAP планировщик
│   │   │   │   ├── context_builder.ex   # Контекст + world-снапшот + погода + конфиги
│   │   │   │   ├── game_context.ex      # GameContext struct
│   │   │   │   ├── personality.ex       # 6 personality traits
│   │   │   │   ├── memory.ex            # Hero memory (last 20)
│   │   │   │   ├── behavior_chains.ex   # Chain bonuses
│   │   │   │   ├── auto_equip.ex        # Auto-equip logic
│   │   │   │   ├── law.ex               # LawSystem: bounties/arrest/reputation (P-3)
│   │   │   │   ├── pets.ex              # Питомцы: adopt/care/history
│   │   │   │   ├── skills.ex            # Навыки активностей
│   │   │   │   ├── actions/             # 14 action modules (базовые + fish/gather/steal/break_in/jail/pet_care)
│   │   │   │   └── narrative/           # Директор, TemplateEngine (+Composer), FragmentPool, LlmFactory, Analytics
│   │   │   ├── world/             # Фаза 3 «Ядро мира»: kernel (GenServer 60s), snapshot (ETS),
│   │   │   │                      #  weather, events, factions, economy, migration, aggregator
│   │   │   ├── worker/           # GameTickWorker (async_stream пул), ActivityFlushWorker
│   │   │   ├── guardian.ex       # JWT auth
│   │   │   ├── repo.ex           # Ecto Repo
│   │   │   └── application.ex    # OTP Application
│   │   └── tes_idle_web/
│   │       ├── router.ex         # API routes (public, auth, admin)
│   │       ├── channels/         # WebSocket
│   │       │   ├── user_socket.ex
│   │       │   └── hero_channel.ex
│   │       ├── controllers/      # 12 controllers
│   │       │   ├── auth, hero, inventory, equipment
│   │       │   ├── journal, location, god, quest
│   │       │   ├── pantheon, suggestion
│   │       │   └── admin/ (10 admin controllers)
│   │       └── plugs/            # AuthPlug, AdminPlug
│   ├── config/                   # Elixir config files
│   ├── priv/
│   │   ├── repo/migrations/      # Ecto migrations
│   │   ├── reseed.exs            # Seed script
│   │   └── exports/              # Admin exports
│   ├── seed_narratives.exs       # Narrative seed
│   └── mix.exs
│
├── frontend/                     # Frontend (Vite + React)
│   ├── src/
│   │   ├── pages/
│   │   │   ├── DashboardPage.tsx       # Дашборд «Обсерватория» (панели + WS + polling, кнопка «Словник» → /narratives)
│   │   │   ├── AdminPage.tsx           # Админка (10 вкладок; модерация/мир; LLM-фабрики UI убраны)
│   │   │   ├── NarrativesPage.tsx      # Мастерская нарративов /narratives: словник, создание, предложения
│   │   │   ├── AnalyticsPage.tsx       # Личность героя (причуды/связи/история питомцев)
│   │   │   ├── AuthPage.tsx            # Login / Register
│   │   │   ├── CreateHeroPage.tsx      # Hero creation
│   │   │   └── WikiPage.tsx            # In-game wiki
│   │   ├── components/
│   │   │   ├── hero/            # HeroStatus, NeedsPanel, EquipmentPanel, PetCard, ReputationPanel
│   │   │   ├── game/            # QuestPanel, InventoryPanel (+Надеть), MoodGraph, GameTimePanel
│   │   │   ├── god/             # GodPanel (Encourage, Punish, Heal, Weather)
│   │   │   ├── journal/         # JournalPanel (главы S-3, фильтры)
│   │   │   ├── pantheon/        # PantheonPage (kills, gold, time)
│   │   │   ├── ui/              # Panel, StatBar
│   │   │   └── narrativeData.ts # Словник: VAR_GROUPS (падежи/примеры), TEMPLATE_TYPE_GROUPS (64 типа), утилиты
│   │   ├── stores/gameStore.ts  # Zustand store (hero, journal, world, pets, ws, admin)
│   │   ├── hooks/useWebSocket.ts # WS hero:* + world:lobby (stale-close-safe)
│   │   ├── lib/api.ts           # HTTP API client
│   │   └── lib/utils.ts         # Utility functions
│   ├── public/wiki/             # 7 wiki markdown pages
│   ├── index.html
│   └── vite.config.ts
│
├── docs/
│   ├── ROADMAP_BRAIN_WORLD.md    # Мастер-план: Фазы 0–3
│   ├── PLAN_BETA_0.7.md          # Действующий план Beta-0.7 (S-1..S-5)
│   ├── GAME_RULES.md             # Правила игры
│   ├── VISUAL_RULES.md           # UI design system «Обсерватория»
│   ├── NARRATIVES_WIKI.md        # Справочник нарративов
│   └── godville_analysis.md      # Анализ Godville
│
├── AGENTS.md                    # Правила разработки
├── SUMMARY.md                   # Нарративная логика
├── start.bat                    # Запуск обоих серверов
└── PROJECT_SUMMARY.md           # Этот файл
```

---

## Игровые системы

### Hero Personality (6 traits, 0–100)

| Trait | Влияние | Примеры расовых стартовых значений |
|-------|---------|-----------------------------------|
| bravery | → fight (+0.004/pt) | Nord=75, Khajiit=30, Argonian=40 |
| curiosity | → explore (+0.004), travel (+0.003) | Nord=40, Khajiit=60, Imperial=55 |
| greed | → shop (+0.004), loot (+0.003) | Nord=55, Khajiit=70, Argonian=65 |
| sociability | → socialize (+0.005) | Nord=45, Imperial=75 |
| tenacity | → complete_quest (+0.003) | Nord=60 |
| caution | → heal (+0.005), rest (+0.003), fight (-0.002) | Nord=35, Argonian=70 |

### Decision Making: Utility AI → GOAP → FSM

Каждый тик (30 сек):

1. **Utility AI** — Goal.best(ctx) оценивает 9 целей (fight, explore, rest, shop, socialize, travel, loot, complete_quest, idle) по формулам с учётом personality + needs + memory + location
2. **GOAP Planner** — строит план действий для выбранной цели
3. **FSM Executor** — выполняет план пошагово:
   - `:idle` → создать план → выполнить первый шаг
   - `:execute` → выполнить текущий шаг плана
   - `:fight` → обработать раунд боя (multi-tick)

### Game Pipeline (каждый тик для каждого героя)

```
1.  ContextBuilder.build()     — контекст из БД + world-снапшот + погода + конфиги
2.  FSMExecutor.tick()         — Brain.Intent (Utility AI + enrich) → GOAP → Execute action
3.  apply_result()             — needs, mood, xp, gold, time (+ progression S-4)
4.  auto_consume()             — HP potions / food / soul stones
5.  check_quest_progress()     — multi-step tracking + репутация за квест (P-3)
6.  reputation_tick()          — +rep за победу над монстром (P-3)
7.  pet_tick()                 — голод/настроение/лояльность питомца
8.  track_memories()           — last 20 events (victory, defeat, discovery, ...)
9.  check_auto_equip()         — every 5-10 ticks (единый save state_data)
10. NarrativeDirector.select() — choose narrative event
11. TemplateEngine.format()    — template + Composer-сцена → journal text
12. PubSub broadcast()         — WebSocket push (hero:* + world:lobby)
```

### Multi-tick Combat

- 1 тик = 1 раунд боя (до 20 раундов)
- `state_data["combat"]` хранит: hero_hp, monster_hp, rounds_left, monster_name
- Промежуточные раунды → WS `combat_progress` (HP updates)
- Финал → `combat_result` (victory/defeat, xp, gold) + journal entry

### Narrative System

**29 типов шаблонов** (20 базовых + 9 активностей: fishing/gather/steal/break_in/jail/pet_care)

**Сцены (Composer):** текст = [опенер погоды] + костяк-шаблон + [closer]. Closer — иерархия: причуда героя → свежая память → настроение. Одобренные llm-сцены полные (full_scene), Composer их не размножает.

**Описательные фрагменты (FragmentPool):** 124 фрагмента в 30 пулах БД (terrain, discovery, landmark, combat verbs, npc/fish/herb names, witnesses, weather openers, mood closers, quirk/memory pools).

**Источники:**
- `source="system"` — seed narratives
- `source="llm"` — LlmFactory (оффлайн-комбинатор пулов) или внешний LLM (точка расширения), needs approve
- `source="community"` — player suggestions (needs approve)
- `source="manual"` — созданные админом в панели

**Аналитика нарративов:** type_usage / daily_volume / unused («мёртвые» типы) / factory_targets → batch-генерация по целям.

**Выбор:** запрос из БД → фильтрация последних использованных (dedup, ротация) → fallback

**Переменные:** `{hero_name}`, `{location_name}`, `{monster_name}`, `{terrain}`, `{discovery}`, `{npc_name}`, etc. SafeMap — неизвестные переменные остаются как `{var}`

### Reputation System (P-3)

Единая точка `Law.adjust_reputation/5`: clamp ±100, уровни hostile (≤−50) / unfriendly (<0) / neutral (<25) / friendly (<75) / allied (≥75), journal-событие при смене уровня.

| Источник | Дельта |
|----------|--------|
| Завершённый квест | +5 |
| Победа над монстром | +1 |
| Преступление (свидетели) | −(rep_loss × crime множитель) |
| Уплата штрафа | +2 (fine_paid) |

Конфиг: `game_configs["law"]["reputation"]`. UI: ReputationPanel — значение, бар (−100..100), подпись до следующего уровня.

### Manual Actions (P-2)

- **Экипировка:** «Надеть» в инвентаре (`POST /equipment/equip/:id`), «Снять» в панели снаряжения (`POST /equipment/unequip/:slot`)
- **Путешествия:** панель «Дороги Тамриэля» — кнопка «Идти» у каждой локации, недоступна в бою/тюрьме/мульти-тике (409). Запись state_data через свежее чтение (не затирает план/мозг)
- **Предложения нарративов:** вкладка «Мои предложения» в словнике → модерация админа

### Pets (P-1)

4 вида (wolf/owl/cat/lizard) с бонусами. Adopt при социализации (шанс 8%) при пустом слоте. Cooldown при смерти в бою (revive_at 4ч, работает офлайн). Лояльность 0 → gone навсегда: ушедший висит на главной, пока не появится новый питомец, затем уходит в историю (`GET /hero/pets/history`, панель «История питомцев» в Аналитике).

### World Kernel (Фаза 3)

GenServer с тиком 60с: Weather → Events → Factions (+войны) → Economy → Migration → снапшот (ETS + world_state) → broadcast `world:lobby`. Герои читают снапшот (погода влияет на клёв/скрытность/needs), редко влияют обратно (Aggregator: покупки поднимают цены, убийства снижают плотность монстров). События: fair / monster_wave / dragon / eclipse. Админ: `GET /admin/world`, `POST /admin/world/tick`, `POST /admin/world/events`.

### Hero Brain (Фаза 1)

BrainHash = SHA256(user_id || ordinal): причуды и связи детерминированы, у одного пользователя все герои разделяют «личность». Learner: пластичность (бюджет 10 пунктов/нед), дрейф связей, возврат к гено-базе. Graph.enrich красит utility целей (жёсткий кэп ±0.15). decision_log (50 последних решений) — вкладка «Аналитика» на фронте.

### God Actions

Игрок (бог) может влиять на героя через soul_energy (5-15 per action):

| Действие | Эффект | Кулдаун |
|----------|--------|---------|
| Encourage | +15 morale, +10 mood | 5 min |
| Punish | -10 morale, -10 mood | 5 min |
| Heal | +30 HP | 5 min |
| Weather | Visual effect | 5 min |

### Quest System

- Multi-step quests (explore, kill, collect, travel)
- Auto-accept if no active quest
- XP + gold + bonus item rewards
- Difficulty 1-5, scaled rewards

### Pantheon (Leaderboard)

3 категории: kills, gold_earned, play_time — real-time обновление.

---

## WebSocket Events

| Event | Trigger | Payload |
|-------|---------|---------|
| `hero_update` | Every tick | Delta-обновление полей героя |
| `journal_entry` | Every tick | Новая запись дневника |
| `combat_start` | Start of combat | Monster data, HP bars |
| `combat_progress` | Each combat round | Hero HP, Monster HP |
| `combat_result` | End of combat | XP, gold, winner |
| `equipment_update` | Auto-equip | Update signal |

---

## API Endpoints Summary

### Public
- `POST /api/v1/auth/register` — регистрация
- `POST /api/v1/auth/login` — вход (JWT)

### Authenticated
- Hero: `POST create`, `GET me`, `GET brain`, `GET pets/history`, `GET reputations`, `POST heartbeat/offline`
- Inventory: `GET index/status`, `POST use/:id/drop/:id`
- Equipment: `GET index`, `POST equip/:id/unequip/:slot`
- Journal: `GET index/count` (+ `entry_type` фильтр)
- Locations: `GET index`, `POST :id/travel` (409 если герой занят мульти-тиком)
- World: `GET world` (снапшот)
- God: `POST action`
- Quests: `GET active`, `POST generate/accept/complete`
- Pantheon: `GET kills/gold/time`
- Suggestions: `POST create`, `GET index`

### Admin (`/api/v1/admin/*`)
- Stats, Users, Heroes (CRUD + force-tick)
- Game loops, Narrative templates (CRUD + approve/reject + approve-batch)
- Narrative stats (`narrative-stats`), LLM factory (`llm-generate`, `llm-generate-batch`)
- World (`GET world`, `POST world/tick`, `POST world/events`)
- Brain telemetry (`brain/stats`)
- Config management, LLM status/toggle
- Simulation, Tests, Export/Import
- Suggestions moderation

---

## База данных — 18 схем

| Schema | Таблица | Описание |
|--------|---------|----------|
| User | users | Аккаунты (email, password_hash, is_admin) |
| Hero | heroes | Герои (stats, state, personality, state_data JSON) |
| Item | items | Шаблоны предметов (type, rarity, stats) |
| InventoryItem | inventory_items | Инвентарь героя (item_id, quantity) |
| Equipment | equipment | Экипировка (hero_id, item_id, slot) |
| Location | locations | Локации (name, type, danger_level, level_range) |
| Monster | monsters | Монстры (name, hp, attack, defense, xp_reward) |
| JournalEntry | journal_entries | Дневник (type, text, gold/xp gained) |
| Quest | quests | Квесты (name, difficulty, rewards) |
| QuestStep | quest_steps | Шаги квеста (type, target_count) |
| ActiveQuest | active_quests | Активные квесты героев |
| Reputation | reputations | Репутация героя во фракциях (value −100..100, level, пороги) |
| NarrativeTemplate | narrative_templates | Шаблоны нарративов (type, source, text, mood range) |
| NarrativeFragment | narrative_fragments | Пулы описательных фрагментов (pool_key, text, weight) |
| Pet | pets | Питомцы (species, mood/hunger/loyalty, status active/cooldown/gone) |
| WorldState | world_state | Снапшот ядра мира (key="snapshot") |
| Suggestion | suggestions | Предложения игроков (type, data, status) |
| GameConfig | game_configs | Runtime конфигурация (key→JSON value) |

---

## Быстрые команды

```bash
# Backend
cd tes_idle_elixir && mix phx.server
cd tes_idle_elixir && mix ecto.migrate
cd tes_idle_elixir && mix ecto.reset          # drop + create + migrate + seed
cd tes_idle_elixir && mix test
cd tes_idle_elixir && mix compile --warnings-as-errors
cd tes_idle_elixir && mix run priv/seed_fragments.exs   # пулы фрагментов (идемпотентно)

# Frontend  
cd frontend && npm run dev
cd frontend && npm run build

# Оба
start.bat
```

## Тестирование

- Backend: Phoenix.ConnTest + SQL Sandbox (`MIX_ENV=test mix test`, 157+ тестов)
- Frontend: `npm run build` (строгий TS)
- Живая проверка: Playwright MCP (логин → дашборд → force-tick админом → журналы/репутация/панель) + SQL-проверки через postgres MCP
- Полный QA-прогон (сентябрь 2026): новый герой → 6 уровней за 90 тиков, бои/лут/шоп/квесты/путешествия/мировые события/репутация +100 «Союзник» — критических ошибок нет

---

## Текущий статус

### ✅ Реализовано
- Полная backend архитектура на Elixir/Phoenix
- 13+ Ecto схем с миграциями
- Game pipeline: ContextBuilder → FSMExecutor → Actions → Narrative → WS push
- Utility AI + GOAP + FSM (3-уровневая система принятия решений)
- BrainHash-мозг (Фаза 1): причуды/связи из SHA256(user_id || ordinal), Learner (пластичность/дрейф), Graph.enrich (кэп ±0.15)
- 14 action modules (базовые 9 + fishing, gathering, stealing, break_in, jail, pet_care)
- Multi-tick combat (до 20 раундов), путешествия, рыбалка, тюрьма (serve/bribe/escape)
- LawSystem: награды per-city, свидетели, арест, репутация per-faction (P-3)
- Питомцы (Фаза 2 + P-1): adopt/care/cooldown/gone + история
- Narrative system: 29 типов шаблонов + сцены Composer (опенер×костяк×closer, опенеры с защитным рендером {var}) + FragmentPool (203 фрагмента, тональная смесь ~50/50 «обычные + комичные») + LlmFactory (оффлайн-генерация) + аналитика нарративов
- N-5 наращивание нарративов: 1191 активный шаблон (694 сгенерированы фабрикой, дедуп) во всех 54 типах; массовая генерация `mix run priv/generate_all_narratives.exs`
- Ядро мира WorldKernel (Фаза 3): погода/сезоны/события/войны/экономика, снапшот ETS, обратное влияние героев (Aggregator)
- S-1..S-5 Beta-0.7: мир→действия, Brain.Intent, FSM-инварианты, дневник с главами, прогрессия ×0.5
- Репутация героя (P-3): рост/падение per-faction, уровни hostile→allied, journal-события, прогресс-бары
- Ручные действия (P-2): экипировка (надеть/снять), путешествия (на карте мира, M-3), предложения нарративов
- План удержания (R-план): `docs/PLAN_RETENTION_GUILDS.md` — 3 золотых стока (C-1 Часовня, C-2 Кузня, C-3 Врата Обливиона) + гильдии (G-0..G-6: чат, подношения, очки, лавка, вести)
- Гильдии — каркас (G-0): миграция 4 таблиц, схемы Guild/GuildMember (+Offering/Message под будущие фазы), Game.Guilds (create/join/leave/list/show), роуты /guilds*, страница /guild (лендинг со списком + форма создания, шапка + состав), nav «Гильдия»; одна гильдия на игрока, создание = сток 500 золота, наследование знамени, авто-распад; 11 тестов
- Гильдии — Алтарь (G-1): подношения золота (сток №3) — exp гильдии, очки с дневным капом (150), хроника подношений, level-up с системными сообщениями; бафы уровня (xp_mult/attack_flat/hp_flat) применяются в ContextBuilder+Pipeline (XP) и fight_action (атака/HP); hero_response несёт блок guild; UI «🔥 Алтарь» с exp-баром и пресетами; 12 тестов
- Гильдии — Чат (G-2): GuildChannel (guild:<id>, джойн по членству) + REST-фоллбеки (GET/POST /guilds/:id/messages), rate-limit 2с (429), чистка хвоста до 500 (Prune), системные сообщения в ленте; UI «💬 Чат» с polling 4с и кулдауном; 8 тестов
- Гильдии — Лавка (G-3): каталог в конфиге (3 уникальных предмета из seed_guild_shop), покупка за гильдейские очки (Multi-транзакция, consumable копится), журнал покупок через шаблон guild_shop_purchase; API /guilds/shop + /guilds/shop/buy; UI «🛒 Лавка» с балансом очков; 8 тестов
- Гильдии — Роли и заявки (G-4): policy=request → заявка на вступление (guild_applications, pending-дедуп), офицеры одобряют/отклоняют (системные сообщения), лидер назначает офицеров (кап 3) и кикает рядовых; join-контракт: заявка вместо 409; UI «📋 Заявки» + кнопки ролей в составе; 7 тестов
- Небесная кузня (C-2): личный сток золота — заточка экипировки (sharpenings per hero+item, цена 50×L^1.8, кэп +10, без провала), +1 атака/защита за уровень в бою, журнал enhance_success; API /equipment/enhance/:slot; UI «⚒ N🪙» в EquipmentPanel; 9 тестов
- Гильдии — Вести (G-5): мировой фид гильдейских событий (guild_news), шаблоны guild_founded/guild_levelup (8 тонов), API /guilds/news, вкладка «📯 Вести гильдий» на Wiki; 5 тестов
- Гильдии — Казна и пир (G-6): treasury (вклад замораживает золото), пир за 300🪙 = +5% XP всей гильдии на 4 ч + весть guild_feast + системное сообщение; панель «💰 Казна»; 9 тестов
- Стабилизация: test-БД с нуля через ecto.reset → 250 passed; сид-конвейер priv/seed_all.exs (только dev); починен мёртвый seed_narratives.exs (@ вне defmodule, теперь идемпотентный)
- Врата Обливиона (C-3): World.Gates — событийный сток (врата над городом 3 дня, фонд экспедиции закрывает, цены ×1.3, collapse при просрочке); весть gate_closed + журнал gate_donation; секция в WorldPanel; 15 тестов → план удержания закрыт полностью
- Стройка «Часовня Девяти» (C-1): коммунальный золотой сток — World.Construction (чистые step/donate, стадии/проекты-конвейер), донат героя `POST /construction/donate` (золото уходит из экономики), снапшот мира несёт summary стройки (REST+WS), секция «🏗️ Стройка» в WorldPanel с прогресс-баром и пресетами, журнал по шаблону construction_donation (seed 6 вариантов), миграция varchar(64) для entry_type
- Карта мира (M-1–M-3c): полноэкранная интерактивная SVG-карта Скайрима на `/map` — канвас на всю рабочую область, узлы-станции по типу локации, цвет = опасность, звезда героя + маршрут в пути, плавающее досье (описание/флаги активностей/погода/плотность/цены города) + кнопка «Идти»; зум/пан/центр на герое, легенда, каскадное появление узлов; координаты в БД (`locations.map_x/map_y`), дашборд разгружен (TravelPanel удалена)
- Auto-equip, auto-consume, quest tracking, memory (20 событий)
- WebSocket real-time updates (delta) + world:lobby
- JWT auth + admin system
- React frontend: дашборд «Обсерватория», админка (10 вкладок), Пантеон, Wiki, Аналитика (личность героя), дневник с главами и фильтрами
- God actions (encourage, punish, heal, weather, direct, quest)
- Полное QA-прогон: новый герой → 6 уровней, бои/лут/шоп/квесты/путешествия/мировые события/репутация — без критических ошибок
- Стресс-QA (N-5): 300/300 force-tick'ов без ошибок лога; питомец прожил полный цикл adopted→голод→pet_left (P-1 «ушёл навсегда» подтверждён); репутация в границах clamp; найден и исправлен баг {var}-дырок в опенерах (Composer теперь рендерит опенеры с отбраковкой непокрываемых)
- Полировка персонажа и мира (полировка 2026-09): (1) P-0 канал предложений — PATCH approve создаёт активный community-шаблон (дедуп, тесты 4); (2) P-1 карта: артвор-подложка Skyrim.svg с точной проекцией провинции (Brdr_*/City_* bbox), тумблер 🗺️, фикс выделения текста и pointer-capture; (3) P-2b смерть: двухфазный цикл — тик смерти (−10% золота, блок death с respawn_at + ближайший город), таймер в UI (DeathOverlay), возрождение через respawn_ticks в городе с 20% HP и поколением +1, журнал death_respawn (8 сид-строк); (4) P-3 тюрьма: решётка-оверлей поверх дашборда (jail-bars-overlay, pointer-events none) + комичный сид-пул jail 4→12 строк с инвариантом vars-whitelist (тесты 2); (5) P-4 сны: Game.Sleep (streak при resting, не чаще 1 сна/игровой день, dream_chance 0.35), журнал dream (8 сид-строк), WS-push; конфиг game_configs["sleep"]; тесты 4. Смерть/сон проверены живьём на QA-герое; полный прогон 279 passed, 1 skipped
- Полировка UI-2 (2026-09): (1) «Мастерская нарративов» — модалка-словник заменена полноэкранной страницей `/narratives` (кнопка «Словник» на дашборде ведёт туда): словник переменных с падежными подсказками/поиском/клик-копированием, создание и предложение шаблонов со сайдбаром-чипами и live-превью, «Мои предложения»; общий модуль `components/narrativeData.ts` (полные 64 типа в 9 группах, VAR_GROUPS — зеркало simple_context, примеры-пресеты для импорта); (2) админка: UI-фабрики LLM удалены (backend endpoints сохранены), select формы создания — optgroup по группам типов + Legacy; (3) дашборд: боковые колонки +30% (300→390, 320→416px) без ужатия центральной (контейнер 1440→1640px, брейкпоинт 2 колонок 1200→1400px)
- Аудит поведения героя (`docs/HERO_BEHAVIOR_AUDIT.md`) — все 3 фазы (2026-09): **Фаза 1 «мозг»:** (C-1) причуды погоды читают `ctx.weather` по ключам ядра (легаси location.weather = мёртвый код); (C-2) слой связей `@link_goals` в graph.ex — пара черт поддерживает конкретные цели, нормировка на число поддерживающих связей (была константа всем целям); (C-3) гомеостаз return_to_base раз в игровой день (`brain.last_return_day`) — 0.02/тик съедал недельный бюджет пластичности. **Фаза 2 «приоритеты/квест»:** критические нужды бьют квест (`needs_urgent`: fatigue > 75 / hp < 50% → rest/heal +0.35, quest −0.3); квест base 0.7 → 0.45 + бонус за совпадение шага; travel-тяга только при невыполнимом на месте шаге; TravelAction выбирает локацию по типу шага (collect → город с лавкой) — герой больше не метается случайно; окно активностей 3–5 тиков без auto_accept после квеста (`activity_break_until_tick`); порог боя 0.3 → 0.45; GOAP collect вне лавки → [:travel, :shop]; kill-прогресс квеста только за победу в бою; **бонус-баг: `result[:fatigue_change]` никогда не применялся в apply_result** — fatigue только рос и застывал на 100 (rest не работал физически), теперь снижается. **Фаза 3 «нарратив»:** теги shopping/looting/sleep + события shop/loot (шаблоны были в БД, но не доставались); погодные теги NarrativeContext на ключах ядра. Тесты +10, полный прогон 291 passed, 1 skipped. Live на Джозеце: rest побеждает при fatigue 100 → sp 0 → 100, fatigue 100 → 84.7, герой вышел из цикла в exploring, defeats 0 за час (было 223 за 14 дней), в хронике появились сны/rest_by_fire/find_loot/collect_herbs
- Контент: питомцы (15 видов: 5 обычных + 10 комичных — гусь/камень/слизень-пылесос и др.) + предметы (50 в 6 категориях: зелья/еда/пруфы-сокровища/материалы/книги/хлам) — сид `priv/seed_pets_items.exs`; наследие `legacy_type/1` дополнено типами shop/loot/rest/social/travel/explore
- Промпт-документация: `docs/PROMPT_NARRATIVE_JSON.md` — единый гайд по генерации нарративов LLM (структура шаблона, переменные, тональные полосы, примеры промптов)
- Полировка 2026-09 (сессия «почини»): (1) защита от моджибейки имени героя — `Hero.changeset` валидирует отсутствие `?` (validate_format `^[^?]+$`); (2) flaky `jail_narrative_test` — nil-`location_id` гварды в loot_action/fight_action (10/10 стабильных прогонов); (3) мёртвый `template_type="combat"` вычищен из промптов-документации (тип `god` пишется напрямую GodController'ом)
- Приоритет 1–2 полировки (2026-09): (1) `remember_defeat` стал достижимым — новый тег `aftermath` (мирный тик сразу после поражения: `aftermath_defeat?/2` по свежей defeat-памяти в last 2 memories без combat_result), вес 25, цепочка → rest_by_fire; (2) контекстные переменные покупок — ShopAction передаёт `{item_name}`, `{gold_spent}` через `result[:context]` (мердж поверх simple_context) — журнал стал предметным вместо «купил что-то»; `ensure_item` в seed_content.exs синхронизирует ВСЕ поля предметов (39/39 слотовых с бонусами)
- Страницы ошибок — TES-флейвор (E-1, 2026-09): 404 «Разыскивается страница» (донесение имперского курьера: двойная золотая рамка, случайная шутка из пула, кнопки «Назад»/«На панель героя») + 500 «Сервер пал в бою» (danger-виньетка в духе DeathOverlay) + заготовки 400/429 — `frontend/src/pages/ErrorPages.tsx` + `.err-*` в index.css (обе темы); ErrorBoundary в App.tsx рендерит 500 при крэше рендера; **грабля auth-гейта починена:** список KNOWN_PATHS проверяется до auth — 404 виден гостям; backend `error_json.ex`: карта @flavor 404/500/401/403/429/400 → пулы шуток, поле detail автоматически в error-тостах фронта (api.ts читает data.detail)
- Редизайн UI (Этап 1: The Imperial Chronicler, 2026-09): (1) Презентационный Лендинг `LandingPage.tsx` для неавторизованных пользователей — Hero-блок с драконом над руинами, слоган, 3 столпа игры (автономность, божественная воля, манускрипт), интерактивный свиток-хроника, CTA к созданию героя; (2) Редизайн `AuthPage.tsx` в стиле «Имперские Архивы» — каменная текстура, фоновый скрипторий при свечах, поля с золотой каймой, переключение вход/регистрация, возврат к обзору; (3) Интеграция в `App.tsx` и дизайн-токены в `index.css`.
- Редизайн UI (Этап 2: Dashboard & Wiki, 2026-09): (1) Витрина героя `HeroPanel.tsx` — благородный медальон с золотым ободом, бейдж уровня, поколения и розыска, кошель с анимацией золотого сияния (`shimmer-gold`), радар текущего действия героя (`beacon-pulse`); (2) Небесный Алтарь `GodPanel.tsx` — аметистово-золотой сосуд праны с пульсирующей аурой (`celestial-pulse`), 6 стихийных карт вмешательств (Вдохновить, Наказать, Исцелить, Погода, Направить, Квест) с тактильным подъемом, кулдауном и руническим журналом чудес; (3) Хроника и Арена `DashboardPage.tsx` — глубокая переработка окон (`.fantasy-window` с латунными уголками и золотой патиной); карточка дуэли с анимированными полосами HP и пульсирующим гербом `VS` (`anim-duel-vs`); каскадное появление записей хроники (`anim-entry`); реконфигурация левой колонки: объединенный модуль «Арсенал героя» с переключением вкладок «Снаряжение» / «Сумка» (headless-режим `EquipmentPanel` и `InventoryPanel`), устранивший 5-этажный вертикальный скролл; (4) Имперская Библиотека Тамриэля `WikiPage.tsx` — устранение дефектов макета (wiki-shell, убраны дублирующиеся заголовки и двойной скролл), адаптивное интерактивное «Оглавление свитка» на широких экранах, навигация-фолиант, стилизованный Markdown-манускрипт, генератор промптов и Имперские Депеши гильдий.
- Редизайн UI (Этап 3: Оплот Гильдий / Guild Bastion, 2026-09): глубокая модернизация страницы `GuildPage.tsx` и стилевой слой `guild-skin.css` — (1) Геральдическое знамя Оплота с медальоном герба, девизом на ленте, прогресс-баром опыта, бейджами активного пира и благословений, безопасным подтверждением сложения полномочий (`LeaveConfirmModal`); (2) Разделение на 4 тематических зала вместо вертикальной стопки: «🔥 Алтарь и Казна» (подношения с пресетами, казна и великий пир), «🛒 Лавка соратников» (витрина реликвий за очки верности с тегами характеристик), «👥 Зал соратников» (табель о рангах, управление офицерами/изгнанием и прошения о вступлении), «💬 Ратуша и Вести» (пергаментный чат соратников + мировой фид вестей Тамриэля); (3) Зал поиска гильдий (`GuildLanding`): фильтры «Все / Открытые / По заявке», поиск по девизу/имени, интерактивная «Имперская Хартия» основания знамени за 500 🪙 с живым предпросмотром.
- Редизайн UI (Этап 4: Адаптация под 1080p+ десктопы и двухтемный паритет Свет/Тьма, 2026-09): (1) Устранение пустот и зажимов: увеличен базовый контейнер десктопа `--container-max: 1840px` (было 1640), ликвидированы искусственные зажимы `max-w-7xl` и инлайновые `maxWidth: 1200 / 640`; (2) Полное преображение `WikiPage.tsx`: ликвидация эффекта «коробка в коробке» («жуткие границы» с 8 пересекающимися уголками заменены лаконичной манускриптной панелью `.wiki-manuscript-panel`), ликвидация «слипшегося текста» в `.wiki-markdown` (комфортный размер 15.5px, line-height 1.85, отступы 18px, просторные таблицы 12×18px, оформленные цитаты, списки и код), адаптивное правое оглавление на мониторах от 1280px+; (3) Полноширинный десктоп Оплота Гильдий (`GuildPage.tsx`): просторные двухколоночные залы Алтаря/Казны и Ратуши/Вестей, 4–5 колоночные сетки витрины лавки и гербовых щитов; (4) Бесшовный паритет Светлой («Пергамент») и Тёмной («Ночной уголь») тем: глубокие оверрайды `[data-theme="light"]` для всех гильдейских компонентов, фреймов `.fantasy-window`, манускриптных блоков Вики и шеллов `.wiki-shell` / `.map-shell` (устранён грязно-серый подмес black 25% в пользу чистых светлых пергаментных токенов `var(--surface)` и `var(--border)`).
- Тихий убийца тиков — TravelAction + вики-колонки (фиксы 2026-09): (1) backend: `destinations |> Enum.filter(...) |> Enum.random() || fallback` в TravelAction падал `Enum.EmptyError` ДО фоллбека, когда шаг активного квеста не давал подходящих назначений; исключение абортит весь тик, воркер глотает — хроника героя молчит часами (Джозец: дыры 125+ мин при живом is_online; фронтенд ни при чём — WS/поллинг проверены инструментированием). Фикс: `case Enum.filter(...) do [] -> Enum.random(destinations); xs -> Enum.random(xs) end`, тест `travel_quest_destination_test.exs` (2); (2) frontend: правое оглавление вики (aside w-72 + gap = 312px) отъедало треть манускрипта на 1440px — брейкпоинт xl → 2xl и w-72 → w-64: на 1440px манускрипт снова 1086px.

### 🔄 В разработке / точки расширения
- Внешний LLM narrative generation (LlmFactory готов как точка расширения, оффлайн-комбинатор работает)
- Rebirth (перерождение) — каркас в Brain.Learner, gameplay-цикл не завершён
- Community suggestions → auto-import в модерацию (ручной путь работает)
- Заготовки страниц ошибок 400/429 в `ErrorPages.tsx` (компоненты готовы, точек показа пока нет)

### 📊 Метрики на текущий этап (2026-09)
- Тесты: **293 passed, 1 skipped** (стабильно)
- Тики: онлайн-герои 30с, офлайн-герои 15 мин ±20% (offline_tick_minutes в config.exs)
- Шаблоны нарративов: 1191 активный в 54 типах; фрагменты: 201 строка в 30 пулах (тональная смесь ~50/50)
- Контент: 15 видов питомцев, 50 предметов, 39 предметов экипировки с синхронизированными бонусами
- Фронтенд: 11 страниц (Landing, Dashboard, Map, Guild, Admin, Pantheon, Analytics, Narratives, Wiki, Auth, CreateHero) + страницы ошибок 404/500
- Скриншоты всех фаз — папка `Screenshots/` (31 файл)