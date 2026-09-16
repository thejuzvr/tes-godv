import Config

config :tes_idle, TesIdle.Repo,
  username: "tes-godv",
  password: "Mo90p4mo!!!",
  hostname: "62.122.99.214",
  port: 54321,
  database: "tes-godv",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 20,
  timeout: 30_000,
  timestamp_type: :utc_datetime

config :tes_idle, TesIdleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_work",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
