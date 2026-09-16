# TES Idle — Elixir Backend

Idle-игра во вселенной The Elder Scrolls на Elixir/Phoenix.

## Стек

- Elixir 1.20.2 + Erlang/OTP 29
- Phoenix Framework 1.7
- Ecto + PostgreSQL
- Guardian (JWT auth)
- Phoenix Channels (WebSocket)

## Запуск

```bash
# Установка зависимостей
mix deps.get

# Создание БД
mix ecto.create

# Миграции
mix ecto.migrate

# Seed data
mix run priv/reseed.exs

# Запуск сервера
mix phx.server
```

## Структура

```
lib/
├── tes_idle/
│   ├── game/              # Game Pipeline
│   │   ├── game_context.ex
│   │   ├── pipeline.ex
│   │   ├── context_builder.ex
│   │   ├── decision_maker.ex
│   │   ├── behavior_chains.ex
│   │   ├── actions/       # 8 Actions
│   │   └── narrative/     # Template engine
│   ├── schemas/           # Ecto schemas
│   └── worker/            # Game tick workers
├── tes_idle_web/
│   ├── channels/          # WebSocket
│   ├── controllers/       # API endpoints
│   └── plugs/             # Auth + Admin
└── config/
```

## API Endpoints

53 endpoints: Auth, Hero, Inventory, Equipment, Journal, Locations, God, Quests, Pantheon, Suggestions, Admin (28).

## Game Pipeline

```
ContextBuilder → DecisionMaker → Action.execute() → Narrative → WS Push
```

## FastAPI Backend

Python backend работает параллельно и НЕ удаляется.
LLM генерация и симуляция остаются на Python.
