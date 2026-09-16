defmodule TesIdle.Worker.EncounterWorker do
  @moduledoc """
  Periodically matches eligible co-located heroes and resolves their encounters.

  Application defaults are merged with the runtime `game_configs["encounters"]`
  block on every round, so database changes take effect without restarting the
  application.
  """

  use GenServer

  require Logger

  alias TesIdle.Game.ContextBuilder
  alias TesIdle.Game.Encounters.{Matcher, Resolver}

  @default_config %{
    "round_seconds" => 60,
    "activity_ttl_seconds" => 120,
    "allowed_states" => ~w(exploring resting socializing shopping),
    "daily_cap" => 10,
    "cooldown_seconds" => 300,
    "familiarity_gain" => 1,
    "fallback_label" => "Попутчик",
    "kind" => "meeting"
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Runs matching and resolution once for the current wall-clock round."
  @spec run_once() :: :ok
  def run_once do
    config = config()
    now = DateTime.utc_now()
    round = div(System.system_time(:second), config["round_seconds"])

    round
    |> Matcher.match(config, now)
    |> Enum.each(fn {left, right} ->
      case Resolver.resolve(left.id, right.id, round, config) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.debug(
            "encounter resolution skipped for #{left.id}/#{right.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  @impl true
  def init(_opts) do
    send(self(), :match)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:match, state) do
    interval = interval_ms()

    try do
      run_once()
    rescue
      error ->
        Logger.error(
          "encounter worker failed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    catch
      kind, reason ->
        Logger.error("encounter worker failed: #{kind}: #{inspect(reason)}")
    after
      Process.send_after(self(), :match, interval)
    end

    {:noreply, state}
  end

  defp config do
    application =
      @default_config
      |> Map.merge(normalize_map(Application.get_env(:tes_idle, :encounters, %{})))

    runtime =
      ContextBuilder.load_configs()
      |> Map.get("encounters", %{})
      |> normalize_map()

    Map.merge(application, runtime)
  end

  defp interval_ms do
    config()
    |> Map.fetch!("round_seconds")
    |> :timer.seconds()
  rescue
    _ -> :timer.seconds(@default_config["round_seconds"])
  end

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), item} end)
  end

  defp normalize_map(_), do: %{}
end
