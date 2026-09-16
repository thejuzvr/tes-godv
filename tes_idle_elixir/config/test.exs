import Config

# Тестовая БД на том же сервере (tes-godv — superuser, CREATE DATABASE доступен).
# Песочница: каждый тест в транзакции с откатом.
config :tes_idle, TesIdle.Repo,
  username: "tes-godv",
  password: "Mo90p4mo!!!",
  hostname: "62.122.99.214",
  port: 54321,
  database: "tes-godv-test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  queue_target: 5_000,
  queue_interval: 10_000,
  timeout: 30_000,
  timestamp_type: :utc_datetime

config :tes_idle, TesIdleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  check_origin: false,
  secret_key_base: "test_secret_key_base_at_least_64_bytes_long_for_phoenix_framework_ok"

# Фоновые процессы выключены в тестах (не ломают SQL-песочницу)
config :tes_idle,
  game_tick_enabled: false,
  activity_flush_enabled: false,
  world_kernel_enabled: false,
  world_aggregator_enabled: false,
  encounter_worker_enabled: false,
  outbox_dispatcher_enabled: false

config :logger, level: :warning
