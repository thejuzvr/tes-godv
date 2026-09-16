defmodule TesIdleWeb.Plugs.AuthPlug do
  @moduledoc """
  Plug for JWT authentication.
  Extracts token from Authorization header and verifies it.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case TesIdle.Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            case TesIdle.Guardian.resource_from_claims(claims) do
              {:ok, user} ->
                assign(conn, :current_user, user)
              _ ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(401, Jason.encode!(%{detail: "User not found"}))
                |> halt()
            end
          _ ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{detail: "Invalid token"}))
            |> halt()
        end
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{detail: "Not authenticated"}))
        |> halt()
    end
  end
end
