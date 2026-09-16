defmodule TesIdleWeb.HeroSocialController do
  use TesIdleWeb, :controller

  alias TesIdle.HeroSocial

  def encounters(conn, params) do
    with {:ok, hero} <- current_hero(conn) do
      json(conn, HeroSocial.list_encounters(hero.id, params))
    else
      {:error, :no_hero} -> no_hero(conn)
    end
  end

  def relationships(conn, _params) do
    with {:ok, hero} <- current_hero(conn) do
      json(conn, %{relationships: HeroSocial.list_relationships(hero.id)})
    else
      {:error, :no_hero} -> no_hero(conn)
    end
  end

  def settings(conn, _params) do
    with {:ok, hero} <- current_hero(conn) do
      json(conn, HeroSocial.get_settings(hero.id))
    else
      {:error, :no_hero} -> no_hero(conn)
    end
  end

  def update_settings(conn, params) do
    with {:ok, hero} <- current_hero(conn),
         {:ok, settings} <- HeroSocial.update_settings(hero.id, params) do
      json(conn, settings)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors(changeset)})

      {:error, :no_hero} ->
        no_hero(conn)
    end
  end

  def block(conn, %{"id" => blocked_id}) do
    with {:ok, hero} <- current_hero(conn),
         :ok <- HeroSocial.block(hero.id, blocked_id) do
      json(conn, %{blocked: true, hero_id: blocked_id})
    else
      {:error, :invalid_target} ->
        conn |> put_status(:unprocessable_entity) |> json(%{detail: "invalid target"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{detail: "hero not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors(changeset)})

      {:error, :no_hero} ->
        no_hero(conn)
    end
  end

  def unblock(conn, %{"id" => blocked_id}) do
    with {:ok, hero} <- current_hero(conn),
         :ok <- HeroSocial.unblock(hero.id, blocked_id) do
      json(conn, %{blocked: false, hero_id: blocked_id})
    else
      {:error, :no_hero} -> no_hero(conn)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{detail: "hero not found"})
    end
  end

  defp current_hero(conn) do
    case HeroSocial.hero_for_user(conn.assigns.current_user.id) do
      nil -> {:error, :no_hero}
      hero -> {:ok, hero}
    end
  end

  defp no_hero(conn), do: conn |> put_status(:not_found) |> json(%{detail: "No hero"})

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
