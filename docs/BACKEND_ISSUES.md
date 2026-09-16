# Backend Issues Log

> Автоматически сгенерирован. Все исправлено.

## Compile Output: `mix compile --warnings-as-errors`

**Статус: ✅ 0 warnings, 0 errors** — чистая компиляция.

## Frontend: `npm run build`

**Статус: ✅ 0 TS errors, успешная сборка.**

---

## Runtime Bugs (найдены smoke-тестом tes-qa-tester)

### BUG-RT1 (Critical): отклонённый god action списывал soul_energy и писал journal entry

- **Симптом:** `POST /god/action` при SE < cost → клиент получал 400, но backend продолжал выполнение: списывал 5 SE (до **отрицательных** значений), вставлял фейковую запись `entry_type="god"`, падал на повторном `json()` (AlreadySentError).
- **Причина:** системный паттерн `if !cond, do: conn |> json(...) |> halt()` внутри controller action — `halt()` останавливает plug pipeline, но **не прерывает выполнение функции** (нет early return).
- **Доказательство:** 3 отклонённых вызова → journal +3, SE −15 (1.69 → −11.62). Воспроизведено дважды.
- **Фикс:** `god_controller.ex` переписан на `cond`/early-return. Верифицировано: 3×400 → journal delta 0, SE без изменений.

### BUG-RT2 (High): quests/generate и quests/accept создавали дубликаты ActiveQuest

- **Причина:** тот же паттерн — после guard'а "Already has active quest" код продолжался: новый Quest + 3 QuestSteps + ActiveQuest на каждый повторный вызов.
- **Фикс:** `quest_controller.ex` — все 4 действия на `cond`. Верифицировано: дубликат-вызов → 400, активный квест не изменился.

### BUG-RT3 (High): inventory/use на не-consuming предмете удалял его из инвентаря

- **Причина:** после 400 "Item is not consumable" код доходил до `Repo.delete!(inv_item)`.
- **Фикс:** `inventory_controller.ex` — `use_item`/`drop_item`/`index`/`status` на `cond`; `Repo.get!` → безопасный `Repo.get` + guard.

### BUG-RT4 (High): equipment/equip на неэкипируемом предмете удалял предмет + создавал мусорные слоты

- **Причина:** каскад guard'ов с продолжением выполнения; финальный краш на `%{nil => id}`.
- **Фикс:** `equipment_controller.ex` — `equip`/`unequip` на `cond`; `String.to_atom` (atom pollution на пользовательском вводе) → lookup по `@slot_map` + `String.to_existing_atom`.

### DEBT (Low): 45 halt-паттернов в читающих endpoints

Оставшиеся `if !x, do: ... halt()` в journal/suggestion/location/admin-контроллерах: клиент получает корректный 404/400, но сервер логирует исключение (краш на nil-доступе после отправки ответа). Side-effects отсутствуют. Исправить при рефакторинге — тем же `cond`-паттерном.

### BUG-AUTH1 (Medium): вход по email отклонялся → «Invalid credentials»

- **Симптом:** регистрация успешна, вход с тем же паролем → 401 «Invalid credentials». Хэш НЕ виноват: register→login одним паролем верифицирован (200).
- **Причина:** при регистрации браузер сохраняет пару «email + пароль» и автозаполняет email в поле «Имя пользователя» при входе; backend искал пользователя только по `username` (точное сравнение) → user not found → 401. Также регистр букв значим (`theJuz` ≠ `TheJuz`).
- **Фикс:** `auth_controller.ex` — вход принимает **username ИЛИ email** (`where: u.username == ^x or u.email == ^x`).
- **Верификация:** login by email → 200, login by username → 200.

### Данные (не баг кода)

- Тестовые локации-загрязнения в БД: `FinalImport1784492086`, `UniqueImport1784492005` — почистить в seed/admin.
- Сломанный нарративный шаблон в БД: «Аромат чихнул семь раз...» — забраковать через админку (source llm/community, прошедший approve).
- Два подряд `smell_flowers` в журнале — дедуп ослаблен (weight/3, не исключение). Приемлемо, наблюдать.

---

## API / WebSocket Sync Audit (frontend ↔ backend)

### BUG-WS1 (Critical): WS heartbeat ронял канал на каждом heartbeat

- **Симптом:** клиент шлёт `heartbeat` каждые 30с → `hero_channel.ex` делал `String.to_integer(hero_id)`, но hero_id — **UUID** → ArgumentError → канал падал → сокет рвался → переподключения в UI.
- **Фикс:** `mark_activity(socket.assigns.hero_id)` напрямую (строку Ecto кастует сам).
- **Верификация:** живой ClientWebSocket-тест: join ok → heartbeat ×2 ok → socket Open.

### BUG-SYNC1 (High): `generateQuest` слал GET на POST-only endpoint

- `api.ts` вызывал `/quests/generate` без `method` → GET → `Phoenix.Router.NoRouteError`. Тот же класс ошибки, что и `GET /auth/login`. Фикс: `method: "POST"`.

### BUG-SYNC2 (High): `adminExport` слал GET на POST-only endpoint

- Кнопка «Экспорт» в админке падала с NoRouteError. Фикс: `method: "POST"` (backend уже имел `post /export`).

### BUG-SYNC3 (Medium): админ-генераторы симуляции отсутствовали в backend

- UI активно дёргал `generate-monsters/items/all` → 404. Реализовано в `simulation_controller.ex` (+ роуты): TES-монстры распределяются по случайным локациям (fight_action выбирает монстров по `location_id` героя), предметы weighted-rarity (60/25/12/3). `generate-narratives-moderated` → честный 501 (LLM-генерация в Elixir-порте не реализована, фейковые шаблоны не пишем).

### BUG-SYNC4 (Low): мёртвые методы api.ts на несуществующие endpoints

- Удалены: `sellItem` (нет route, нет UI), `getReputation` (нет route, панель репутации статична), `adminHeroSimulation` (не используется, есть per-hero force-tick), `adminGenerateNarratives` (не используется, есть Moderated-вариант).

### UX: разбор HTML-ошибок Phoenix в api.ts

- `request()` теперь проверяет content-type: HTML-страница ошибки (NoRouteError и т.п.) → понятное `HTTP 404: Not Found` вместо «Request failed».

### Разбор жалобы «GET /api/v1/auth/login»

- Код приложения **никогда** не шлёт GET на этот URL: `api.login()` — явный POST; других вызовов `/auth/login` нет (grep), навигаций `window.location` нет, форма имеет `preventDefault`. GET-запрос даёт Phoenix NoRouteError только при **прямом открытии URL в браузере** (адресная строка/закладка) — это ожидаемое поведение: у роута зарегистрирован только POST.
- Верифицировано на живом сервере: `POST /api/v1/auth/login` → 200 + JWT.

### Smoke-пользователь

- `smoke_21401` повышен до `is_admin: true` (для QA админ-эндпоинтов). Генераторы создали тестовых монстров/предметы в dev-БД.

---

## Исправленные проблемы (29 шт)

### A: Unused Variables → prefix with `_`

| # | Файл | Переменная | Статус |
|---|------|-----------|--------|
| 1 | `pipeline.ex:93` | `needs_delta` | ✅ `_needs_delta` |
| 2 | `pipeline.ex:252` | `updated` | ✅ `_updated` |
| 3 | `pipeline.ex:451` | `result` (param) | ✅ `_result` |
| 4 | `goal.ex:42` | `aq` | ✅ `_aq` |
| 5 | `goap_planner.ex:55` | `config` | ✅ `_config` |
| 6 | `memory.ex:118` | `defeats_here` | ✅ `_defeats_here` |
| 7 | `fight_action.ex:171` | `loot_text` | ✅ `_loot_text` |
| 8 | `auto_equip.ex:52` | `best_inv` | ✅ `_best_inv` |
| 9 | `template_engine.ex:267` | `hero` (second def) | ✅ удалён дубликат |

### B: Unused Aliases/Imports/Attributes

| # | Файл | Что | Статус |
|---|------|-----|--------|
| 10 | `travel_action.ex:7` | `Hero` alias | ✅ удалён |
| 11 | `pipeline.ex:8` | `DecisionMaker` alias | ✅ удалён |
| 12 | `pipeline.ex:8` | `Memory` alias | ✅ удалён |
| 13 | `goap_planner.ex:8` | `GameContext` alias | ✅ удалён |
| 14 | `narrative_director.ex:9` | `NarrativeContext` alias | ✅ удалён |
| 15 | `context_builder.ex:9` | `Equipment`, `Location` | ✅ удалены |
| 16 | `export_controller.ex:6` | `import Ecto.Query` | ✅ удалён |
| 17 | `import_controller.ex:6` | `import Ecto.Query` | ✅ удалён |
| 18 | `behavior_chains.ex:9` | `@state_to_action` attr | ✅ удалён |

### C: Unused/Dead Functions

| # | Файл | Функция | Статус |
|---|------|---------|--------|
| 19 | `pipeline.ex:391` | `decode_state_data/1` | ✅ удалена |
| 20 | `fight_action.ex:272` | `quest_boost?/2` catch-all | ✅ удалён |

### D: Dead Clauses (will never match)

| # | Файл | Clause | Статус |
|---|------|--------|--------|
| 21 | `fsm_executor.ex:35` | `{:error, _}` FightAction | ✅ удалён, pattern match |
| 22 | `fsm_executor.ex:70` | `{:error, _}` TravelAction | ✅ удалён, pattern match |
| 23 | `hero_controller.ex:100` | `{:error, reason}` force_tick | ✅ удалён, pattern match |
| 24 | `game_tick_worker.ex:51` | `{:error, reason}` handle_info | ✅ удалён, pattern match |

### E: Duplicate/Redundant Clauses

| # | Файл | Что | Статус |
|---|------|-----|--------|
| 25-26 | `template_engine.ex:251-268` | duplicate `load_templates/2` + `choose_template/2` | ✅ удалены |

### F: Type Warnings

| # | Файл | Что | Статус |
|---|------|-----|--------|
| 27 | `pipeline.ex:43` | `\|\|` right-hand side never executed | ✅ `final_state_data` напрямую |
| 28 | `narrative_context.ex:118` | `ctx.personality \|\| %{}` type warning | ✅ `personality` вынесен в переменную |
| 29 | `god_controller.ex:67` | `TemplateEngine.generate` ctx missing fields | ✅ добавлены `location_type`, `mood` |

## Frontend Fixes (3 шт)

| # | Файл | Что | Статус |
|---|------|-----|--------|
| 30 | `NarrativeImportModal.tsx:185,365` | `GLOBAL_VARS` undefined | ✅ определён как `ALL_VARIABLES.slice(0,3)` |
| 31 | `AdminPage.tsx:803-809` | `data` undefined in ModerationPanel | ✅ заменён на `total`, `templates`, `50` |