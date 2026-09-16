defmodule TesIdleWeb.Admin.GameController do
  use TesIdleWeb, :controller

  def loops(conn, _params) do
    json(conn, %{count: 0, loops: []})
  end

  def restart_loops(conn, _params) do
    json(conn, %{message: "Loops restarted"})
  end

  def tick_all(conn, _params) do
    json(conn, %{message: "Tick triggered for all heroes"})
  end
end
