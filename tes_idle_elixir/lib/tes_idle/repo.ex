defmodule TesIdle.Repo do
  use Ecto.Repo,
    otp_app: :tes_idle,
    adapter: Ecto.Adapters.Postgres
end
