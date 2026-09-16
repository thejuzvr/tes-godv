defmodule TesIdle.Game.Actions.BreakInAction do
  @moduledoc """
  Проникновение (ROADMAP Часть II): закрытые дома/подвалы (flags.locked_buildings).
  Требует отмычку (item tag "lockpick") или навык lockpicking.
  Успех → жирная добыча; провал → ловушка (HP) или шум → стража (Law.on_crime).
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.{GameContext, Law, Skills}
  alias TesIdle.Repo
  alias TesIdle.Schemas.InventoryItem

  @impl true
  def score(%GameContext{} = _ctx), do: 50

  @impl true
  def execute(%GameContext{} = ctx) do
    cfg = ((ctx.configs || %{})["activities"] || %{})["breaking_in"] || %{}

    cond do
      locked?(ctx) -> do_break_in(ctx, cfg)
      true -> TesIdle.Game.Actions.LootAction.execute(ctx)
    end
  end

  defp do_break_in(ctx, cfg) do
    has_lockpick = has_lockpick?(ctx)
    skill = Skills.get(ctx.hero, :lockpicking)

    if not has_lockpick and skill < (cfg["lockpick_skill"] || 40) do
      # Нечем вскрыть — гулять дальше
      {:ok, %{
        state_to: "exploring",
        context: %{"break_in_fail" => "lockpick"},
      }}
    else
      # Расход отмычки
      if has_lockpick, do: consume_lockpick(ctx)

      # Навык + отмычка против сложности
      open_power = skill + if(has_lockpick, do: 25, else: 0)
      success? = :rand.uniform() * 100 < open_power + 35

      {skills, _} = Skills.gain(ctx.hero, :lockpicking, cfg["skill_xp"] || 1, Skills.rate(ctx.configs))
      ctx.hero |> Ecto.Changeset.change(%{skills: skills}) |> Repo.update!()

      if success? do
        loot_gold = Enum.random(range(cfg["loot_gold"] || [20, 80]))

        {:ok, %{
          state_to: "breaking_in",
          gold_change: loot_gold,
          xp: Enum.random(range(cfg["xp"] || [5, 12])),
          context: %{"stolen_gold" => loot_gold, "break_in_ok" => "true"},
        }}
      else
        # Провал: ловушка или шум
        if :rand.uniform() < (cfg["trap_chance"] || 0.35) do
          hp = Enum.random(range(cfg["trap_hp"] || [5, 15]))

          {:ok, %{
            state_to: "breaking_in",
            hp_change: -hp,
            context: %{"trap_hp" => hp, "break_in_trap" => "true"},
          }}
        else
          # Шум → свидетели: «ценность кражи» 0 — только награда/арест
          law0 = (ctx.state_data || %{})["law"] || %{"bounties" => %{}}

          case Law.on_crime(ctx, 0, law0) do
            %{outcome: :caught, bounty_added: bounty, arrested: true, law: law} ->
              jail = Law.start_jail(ctx, "break_in")

              {:ok, %{
                state_to: "jailed",
                state_data_update: %{"jail" => jail, "law" => law},
                context: %{"witness_name" => "ночной сторож", "bounty_gold" => bounty, "break_in_noise" => "true"},
              }}

            %{outcome: outcome, bounty_added: bounty, law: law} ->
              {:ok, %{
                state_to: "breaking_in",
                state_data_update: %{"law" => law},
                context: %{
                  "witness_name" => "ночной сторож",
                  "bounty_gold" => bounty,
                  "witness_outcome" => to_string(outcome),
                  "break_in_noise" => "true",
                },
              }}
          end
        end
      end
    end
  end

  defp locked?(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}
    flags["locked_buildings"] == true
  end

  defp has_lockpick?(ctx) do
    Enum.any?(ctx.inventory || [], fn {inv, item} ->
      "lockpick" in (item.tags || []) and inv.quantity > 0
    end)
  end

  defp consume_lockpick(ctx) do
    {inv_entry, _item} =
      Enum.find(ctx.inventory || [], fn {inv, item} ->
        "lockpick" in (item.tags || []) and inv.quantity > 0
      end)

    inv = Repo.get!(InventoryItem, inv_entry.id)

    if inv.quantity <= 1 do
      Repo.delete!(inv)
    else
      inv |> Ecto.Changeset.change(%{quantity: inv.quantity - 1}) |> Repo.update!()
    end
  end

  defp range([lo, hi]) when is_number(lo) and is_number(hi), do: round(lo)..round(hi)
  defp range(_), do: 20..40
end
