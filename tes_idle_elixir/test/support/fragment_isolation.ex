defmodule TesIdle.Test.FragmentIsolation do
  @moduledoc """
  N-5: изоляция тестов пулов фрагментов от сида.

  Сид `priv/seed_fragments.exs` наполняет реальные пулы (openers_*,
  closers_*, quirk_*, memory_*) десятками строк. Тесты Composer/FragmentPool
  создают свои строки в тех же пулах — без изоляции draw() может вернуть
  сид-строку и ассерты «точное совпадение» падают.

  Хелпер на время теста скрывает сид-фрагменты (is_active=false) и в cleanup
  возвращает как было. Тестовые фрагменты вставляются ПОСЛЕ изоляции — они
  остаются видимыми.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeFragment
  import Ecto.Query

  @doc """
  Прячет активные сид-фрагменты затронутых пулов. Возвращает id скрытых строк.
  Вызывать после checkout, ДО вставки тестовых фрагментов.

  `:all` — скрыть весь сид-контент (нужно для тестов «пулы пусты»: счётчик
  `fragments_available?/0` смотрит на ЛЮБЫЕ активные фрагменты, а не только
  на openers/closers).
  """
  def hide_seed_fragments(:all) do
    ids = Repo.all(from f in NarrativeFragment, where: f.is_active == true, select: f.id)

    if ids != [] do
      Repo.update_all(from(f in NarrativeFragment, where: f.id in ^ids), set: [is_active: false])
    end

    ids
  end

  def hide_seed_fragments(pool_prefixes) when is_list(pool_prefixes) do
    rows =
      Repo.all(
        from f in NarrativeFragment,
          where: f.is_active == true,
          select: {f.id, f.pool_key}
      )

    hidden =
      Enum.filter(rows, fn {_id, pool} ->
        Enum.any?(pool_prefixes, &String.starts_with?(pool, &1))
      end)

    ids = Enum.map(hidden, &elem(&1, 0))

    if ids != [] do
      Repo.update_all(from(f in NarrativeFragment, where: f.id in ^ids), set: [is_active: false])
    end

    ids
  end

  @doc """
  Возвращает видимость скрытых фрагментов (cleanup из on_exit).

  on_exit выполняется в отдельном процессе (ExUnit.OnExitHandler) —
  тестовый sandbox-коннект уже закрыт, поэтому открываем свой owner
  на время апдейта.
  """
  def restore(ids)

  def restore([]), do: :ok

  def restore(ids) when is_list(ids) do
    # on_exit выполняется в отдельном процессе (ExUnit.OnExitHandler):
    # тестовый sandbox-коннект уже закрыт, поэтому открываем свой owner
    # на время апдейта. Возвращаемое значение start_owner!/2 не фиксируем —
    # разные версии Ecto отдают {:ok, pid, ref} или {:ok, pid}.
    owner_pid =
      with {:ok, pid, _ref} <-
             Ecto.Adapters.SQL.Sandbox.start_owner!(TesIdle.Repo,
               shared: false,
               ownership_timeout: 60_000
             ) do
        pid
      else
        {:ok, pid} -> pid
        pid when is_pid(pid) -> pid
      end

    Ecto.Adapters.SQL.Sandbox.allow(TesIdle.Repo, owner_pid, self())

    Repo.update_all(from(f in NarrativeFragment, where: f.id in ^ids), set: [is_active: true])

    Ecto.Adapters.SQL.Sandbox.stop_owner(owner_pid)
    :ok
  end
end
