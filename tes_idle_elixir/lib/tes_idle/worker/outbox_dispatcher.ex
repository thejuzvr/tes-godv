defmodule TesIdle.Worker.OutboxDispatcher do
  @moduledoc """
  Delivers due outbox events to hero channels.

  Rows are selected with `FOR UPDATE SKIP LOCKED`; delivery and the resulting
  processed/retry update happen in the same transaction so multiple dispatcher
  instances cannot concurrently publish the same pending row.
  """

  use GenServer

  import Ecto.Query
  require Logger

  alias TesIdle.Repo
  alias TesIdle.Schemas.EventOutbox
  alias TesIdleWeb.Endpoint

  @default_config %{
    "interval_seconds" => 1,
    "batch_size" => 50,
    "retry_seconds" => 5,
    "max_attempts" => 10
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Claims and delivers one due batch."
  @spec dispatch_once() :: {:ok, non_neg_integer()} | {:error, term()}
  def dispatch_once do
    config = config()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.transaction(fn ->
      events =
        Repo.all(
          from event in EventOutbox,
            where: event.status == "pending" and event.available_at <= ^now,
            order_by: [asc: event.available_at, asc: event.created_at],
            limit: ^config["batch_size"],
            lock: "FOR UPDATE SKIP LOCKED"
        )

      Enum.each(events, &deliver(&1, now, config))
      length(events)
    end)
  end

  @impl true
  def init(_opts) do
    send(self(), :dispatch)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:dispatch, state) do
    interval = interval_ms()

    try do
      case dispatch_once() do
        {:ok, _count} -> :ok
        {:error, reason} -> Logger.error("outbox dispatch transaction failed: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.error(
          "outbox dispatcher failed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    catch
      kind, reason ->
        Logger.error("outbox dispatcher failed: #{kind}: #{inspect(reason)}")
    after
      Process.send_after(self(), :dispatch, interval)
    end

    {:noreply, state}
  end

  defp deliver(event, now, config) do
    case broadcast(event) do
      :ok ->
        event
        |> EventOutbox.changeset(%{
          status: "processed",
          processed_at: now,
          last_error: nil
        })
        |> Repo.update!()

      {:error, reason} ->
        retry(event, reason, now, config)
    end
  rescue
    error -> retry(event, Exception.message(error), now, config)
  catch
    kind, reason -> retry(event, "#{kind}: #{inspect(reason)}", now, config)
  end

  defp broadcast(%EventOutbox{
         event_type: "journal_entry",
         payload: %{"hero_id" => hero_id, "journal_entry" => journal_entry}
       })
       when is_binary(hero_id) and is_map(journal_entry) do
    case Endpoint.broadcast("hero:#{hero_id}", "journal_entry", journal_entry) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_broadcast_result, other}}
    end
  end

  defp broadcast(%EventOutbox{event_type: type}), do: {:error, {:unsupported_event, type}}

  defp retry(event, reason, now, config) do
    attempts = event.attempts + 1
    status = if attempts >= config["max_attempts"], do: "failed", else: "pending"

    event
    |> EventOutbox.changeset(%{
      status: status,
      attempts: attempts,
      available_at: NaiveDateTime.add(now, config["retry_seconds"], :second),
      processed_at: nil,
      last_error: reason |> inspect_reason() |> String.slice(0, 4_000)
    })
    |> Repo.update!()
  end

  defp inspect_reason(reason) when is_binary(reason), do: reason
  defp inspect_reason(reason), do: inspect(reason)

  defp config do
    @default_config
    |> Map.merge(normalize_map(Application.get_env(:tes_idle, :outbox_dispatcher, %{})))
  end

  defp interval_ms do
    config()
    |> Map.fetch!("interval_seconds")
    |> :timer.seconds()
  rescue
    _ -> :timer.seconds(@default_config["interval_seconds"])
  end

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), item} end)
  end

  defp normalize_map(_), do: %{}
end
