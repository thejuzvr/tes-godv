import Config

config :tes_idle,
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  ecto_repos: [TesIdle.Repo],
  # Тики героя: онлайн-герои — каждые 30с; офлайн-герои — раз в offline_tick_minutes
  # минут (ленивый тик: пока за героем не наблюдают, мир движется медленнее).
  offline_tick_minutes: 15

config :tes_idle, TesIdle.Repo,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

config :tes_idle, TesIdle.Guardian,
  issuer: "tes_idle",
  secret_key: "tes-idle-secret-key-change-in-production-2024"

config :tes_idle, TesIdleWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: TesIdleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TesIdle.PubSub,
  live_view: [signing_salt: "random_salt_here"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
