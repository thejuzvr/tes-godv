TesIdle.Repo.start_link()
alias TesIdle.Schemas.User
import Ecto.Query

u = TesIdle.Repo.one(from u in User, where: u.is_admin == true, limit: 1)

case u do
  nil ->
    IO.puts("NO_ADMIN")

  %User{} ->
    {:ok, t, _} = TesIdle.Guardian.encode_and_sign(u, %{}, ttl: {1, :hour})
    IO.puts("TOKEN=" <> t)
end
