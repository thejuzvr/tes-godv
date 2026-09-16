defmodule TesIdleWeb.Plugs.AdminPlug do
  @moduledoc """
  Plug for admin authorization.
  Must be used after AuthPlug.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.is_admin do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{detail: "Admin access required"}))
      |> halt()
    end
  end
end
