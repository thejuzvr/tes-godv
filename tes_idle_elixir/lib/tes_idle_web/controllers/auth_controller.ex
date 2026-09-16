defmodule TesIdleWeb.AuthController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.User
  import Ecto.Query

  def register(conn, %{"username" => username, "email" => email, "password" => password}) do
    # Check if user exists
    existing = Repo.one(from u in User, where: u.username == ^username or u.email == ^email)
    if existing do
      conn
      |> put_status(:bad_request)
      |> json(%{detail: "Username or email already exists"})
    else
      # Hash password using pbkdf2
      hashed = Pbkdf2.hash_pwd_salt(password)

      user = %User{
        username: username,
        email: email,
        password_hash: hashed,
        is_admin: false,
      }

      case Repo.insert(user) do
        {:ok, user} ->
          {:ok, token, _claims} = TesIdle.Guardian.encode_and_sign(user)
          json(conn, %{access_token: token})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{detail: "Registration failed", errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)})
      end
    end
  end

  def login(conn, %{"username" => username, "password" => password}) do
    # Accept username OR email — browsers often autofill the email saved at registration
    user =
      Repo.one(
        from u in User,
          where: u.username == ^username or u.email == ^username
      )

    case user do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{detail: "Invalid credentials"})

      user ->
        if Pbkdf2.verify_pass(password, user.password_hash) do
          {:ok, token, _claims} = TesIdle.Guardian.encode_and_sign(user)
          json(conn, %{access_token: token})
        else
          conn
          |> put_status(:unauthorized)
          |> json(%{detail: "Invalid credentials"})
        end
    end
  end

  @doc "Тихая проверка текущего пользователя (is_admin без 403-шума админ-эндпоинтов)."
  def me(conn, _params) do
    user = conn.assigns.current_user
    json(conn, %{id: user.id, username: user.username, email: user.email, is_admin: user.is_admin})
  end
end
