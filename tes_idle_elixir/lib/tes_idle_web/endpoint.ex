defmodule TesIdleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tes_idle

  @session_options [
    store: :cookie,
    key: "_tes_idle_key",
    signing_salt: "random_salt",
    same_site: "Lax"
  ]

  socket "/socket", TesIdleWeb.UserSocket,
    websocket: [connect_info: [:peer_data, :uri]],
    longpoll: [connect_info: [:peer_data, :uri]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TesIdleWeb.Router
end
