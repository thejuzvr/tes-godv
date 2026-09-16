defmodule TesIdleWeb.ChannelCase do
  @moduledoc "G-2: база для тестов каналов (sandbox + реальный UserSocket-пайплайн)."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Phoenix.ChannelTest
      import TesIdleWeb.ChannelCase

      @endpoint TesIdleWeb.Endpoint
    end
  end

  setup tags do
    # start_owner! вместо checkout: чат-тесты гоняют broadcast'ы/каналы с Shared-mode
    # (REST-фоллбеки и события приходят из других процессов), и это исключает {:already, :owner}
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TesIdle.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    :ok
  end
end
