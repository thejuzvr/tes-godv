defmodule TesIdle.World.Construction do
  @moduledoc """
  C-1 «Часовня Девяти»: коммунальная стройка — вечный золотой сток (аналог храма Godville).

  Состояние живёт в снапшоте мира под ключом `"construction"`. Kernel — единственный
  писатель: тик зовёт `step/4` (фон-взнос «паломников»), донат героев — `donate/5`
  через `GenServer.call`. Здесь только чистые функции; параметры — в
  `game_configs["construction"]` (правило «hardcode — только в конфигах»).

  Стадии делят цель поровну: стадия i завершается на `target × (i+1)/n`.
  Проекты идут конвейером (после последнего — снова первый), история завершений копится.
  """

  @default_config %{
    "min_donation" => 10,
    "world_trickle" => 25,
    "top_donors_size" => 10,
    "projects" => [
      %{
        "name" => "Часовня Девяти в Ривервуде",
        "target" => 12_000,
        "stages" => ["фундамент", "стены", "крыша", "освящение"],
      },
      %{
        "name" => "Мост через Белую реку",
        "target" => 18_000,
        "stages" => ["опоры", "пролёты", "настил"],
      },
      %{
        "name" => "Маяк у Солитьюда",
        "target" => 24_000,
        "stages" => ["кладка", "фонарь", "освящение огня"],
      },
    ],
  }

  def default_config, do: @default_config

  @doc "Конфиг стройки: дефолты, поверх — значения из game_configs."
  def config(configs) do
    Map.merge(@default_config, configs["construction"] || %{})
  end

  @doc "Начальный блок стройки для снапшота."
  def init_block do
    %{"project" => 0, "collected" => 0, "stage" => 0, "top_donors" => [], "history" => []}
  end

  @doc "Тик мира: «паломники» понемногу достраивают сами (фон для малого онлайна)."
  def step(block, configs, tick) when is_map(block) do
    cfg = config(configs)
    trickle = cfg["world_trickle"] || 0

    if trickle > 0 do
      donate(block, "Паломники", trickle, configs, tick, track?: false)
    else
      {block, []}
    end
  end

  @doc """
  Пожертвование: collected += amount, топ-донатеров обновляем (кроме системных),
  стадии/проект сдвигаются. Возвращает `{block, events}` — события в формате мировых
  событий снапшота (type/name/desc/ttl/id).
  """
  def donate(block, donor_name, amount, configs, tick, opts \\ [])

  def donate(block, donor_name, amount, configs, tick, opts) when is_integer(amount) and amount > 0 do
    cfg = config(configs)
    block = Map.update!(block, "collected", &(&1 + amount))

    block =
      if Keyword.get(opts, :track?, true) do
        track_donor(block, donor_name, amount, cfg)
      else
        block
      end

    settle(block, cfg, tick, [])
  end

  def donate(block, _donor, _amount, _configs, _tick, _opts) when is_map(block), do: {block, []}

  @doc """
  Офлайн-донат: Kernel выключен (тесты) — применяем через Snapshot и персистим снапшот сами.
  В рабочем режиме персистит только Kernel (правило единственного писателя мира).
  """
  def apply_offline(donor_name, amount) do
    alias TesIdle.Repo
    alias TesIdle.Schemas.WorldState
    alias TesIdle.World.Snapshot

    snap = Snapshot.current()

    {block, _events} =
      donate(
        snap["construction"] || init_block(),
        donor_name,
        amount,
        TesIdle.Game.ContextBuilder.load_configs(),
        snap["tick"] || 0
      )

    snap2 = Map.put(snap, "construction", block)
    Snapshot.put(snap2)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %WorldState{key: "snapshot", value: snap2, updated_at: now},
      on_conflict: [set: [value: snap2, updated_at: now]],
      conflict_target: :key
    )

    {:ok, block}
  end

  @doc "Публичное резюме для API/фронта: имена, пороги, прогресс."
  def summary(block, configs) do
    cfg = config(configs)
    projects = cfg["projects"]
    proj = Enum.at(projects, block["project"]) || Enum.at(projects, 0)
    stages = proj["stages"]
    target = proj["target"]
    stage = min(block["stage"], length(stages) - 1)

    %{
      "project" => proj["name"],
      "stage" => Enum.at(stages, stage),
      "stage_index" => stage,
      "stages_total" => length(stages),
      "collected" => block["collected"],
      "target" => target,
      "progress" => if(target > 0, do: min(1.0, block["collected"] / target), else: 0.0),
      "top_donors" => Enum.map(block["top_donors"], fn d -> %{"name" => d["name"], "gold" => d["gold"]} end),
      "history" => block["history"],
    }
  end

  # --- Внутреннее ---

  # Скачок через несколько стадий/проект при крупном донате — хвостовая рекурсия.
  defp settle(block, cfg, tick, events) do
    projects = cfg["projects"]
    proj = Enum.at(projects, block["project"]) || Enum.at(projects, 0)
    stages = proj["stages"]
    target = proj["target"]
    stage = block["stage"]

    cond do
      # Завершение проекта: последняя стадия и цель закрыта
      stage >= length(stages) - 1 and block["collected"] >= target ->
        history = [%{"name" => proj["name"]} | block["history"]] |> Enum.take(10)

        block2 = %{
          block
          | "project" => rem(block["project"] + 1, length(projects)),
            "collected" => 0,
            "stage" => 0,
            "history" => history
        }

        event = %{
          "id" => Ecto.UUID.generate(),
          "type" => "construction",
          "name" => "Стройка завершена",
          "desc" => "#{proj["name"]} — готово! Стройка переезжает: #{next_project_name(projects, block["project"])}",
          "ttl" => 24
        }

        settle(block2, cfg, tick, events ++ [event])

      # Следующая стадия
      block["collected"] >= stage_target(target, stages, stage) ->
        block2 = Map.update!(block, "stage", &min(length(stages) - 1, &1 + 1))

        event = %{
          "id" => Ecto.UUID.generate(),
          "type" => "construction",
          "name" => "Стройка: #{stage_name(stages, stage)} готово",
          "desc" => "#{proj["name"]}: этап «#{stage_name(stages, stage)}» завершён — начат этап «#{stage_name(stages, min(length(stages) - 1, stage + 1))}»",
          "ttl" => 12
        }

        settle(block2, cfg, tick, events ++ [event])

      true ->
        {block, events}
    end
  end

  defp stage_target(target, stages, stage_idx) do
    n = max(1, length(stages))
    div(target * (stage_idx + 1), n)
  end

  defp stage_name(stages, idx), do: Enum.at(stages, idx) || "—"

  defp next_project_name(projects, current_idx) do
    Enum.at(projects, rem(current_idx + 1, length(projects)))["name"]
  end

  defp track_donor(block, name, amount, cfg) do
    cap = cfg["top_donors_size"] || 10

    donors =
      block["top_donors"]
      |> Enum.map(fn d -> if d["name"] == name, do: Map.update!(d, "gold", &(&1 + amount)), else: d end)

    donors =
      if Enum.any?(donors, &(&1["name"] == name)) do
        donors
      else
        donors ++ [%{"name" => name, "gold" => amount}]
      end

    Map.put(block, "top_donors", donors |> Enum.sort_by(&{-&1["gold"], &1["name"]}) |> Enum.take(cap))
  end
end
