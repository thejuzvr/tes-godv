defmodule TesIdleWeb.Admin.TestController do
  use TesIdleWeb, :controller

  def last(conn, _params) do
    json(conn, %{passed: 0, failed: 0, errors: 0, output: nil, run_at: nil})
  end

  def run(conn, _params) do
    json(conn, %{passed: 0, failed: 0, errors: 0, output: "Tests not implemented yet", run_at: DateTime.utc_now()})
  end
end
