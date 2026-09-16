defmodule TesIdleWeb.Admin.UserController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.User
  import Ecto.Query

  def index(conn, params) do
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "20") |> String.to_integer() |> min(100)
    offset = (page - 1) * per_page

    total = Repo.one(from u in User, select: count(u.id))
    users = Repo.all(from u in User, limit: ^per_page, offset: ^offset, order_by: u.username)

    json(conn, %{
      users: Enum.map(users, fn u ->
        %{id: u.id, username: u.username, email: u.email, is_admin: u.is_admin}
      end),
      total: total,
      page: page,
      per_page: per_page,
    })
  end

  def show(conn, %{"id" => id}) do
    user = Repo.get(User, id)
    if !user, do: conn |> put_status(:not_found) |> json(%{detail: "User not found"}) |> halt()
    json(conn, %{id: user.id, username: user.username, email: user.email, is_admin: user.is_admin})
  end

  def set_admin(conn, %{"id" => id} = params) do
    user = Repo.get(User, id)
    if !user, do: conn |> put_status(:not_found) |> json(%{detail: "User not found"}) |> halt()

    is_admin = Map.get(params, "is_admin", "false") == "true"
    Repo.update!(User.changeset(user, %{is_admin: is_admin}))

    json(conn, %{message: "User updated", is_admin: is_admin})
  end
end
