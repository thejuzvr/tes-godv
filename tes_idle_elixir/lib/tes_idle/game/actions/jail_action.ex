defmodule TesIdle.Game.Actions.JailAction do
  @moduledoc """
  Тюрьма (ROADMAP Часть II): состояние `jailed`, мульти-тик 3–10.
  На первом тике герой выбирает режим по характеру:
  - **отсидеть** (serve) — просто ждёт, голод растёт медленнее;
  - **взятка** (bribe) — если золота хватает, стоимостью из конфига;
  - **побег** (escape) — шанс escape_chance + dexterity/50; провал → увечья
    (HP −) и +2 тика.
  После отсидки/взятки/побега награда за голову в этом городе списана.
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.{GameContext, Law}

  @impl true
  def score(%GameContext{} = _ctx), do: 50

  @impl true
  def execute(%GameContext{} = ctx) do
    cfg = ((ctx.configs || %{})["activities"] || %{})["jail"] || %{}
    jail = jail_state(ctx)

    if is_nil(jail) do
      # Защита: тюрьмы нет, а состояние jailed — выходим
      {:ok, %{state_to: "exploring", context: %{"jail_free" => "true"}}}
    else
      jail = choose_mode(ctx, jail, cfg)

      case jail["mode"] do
        "bribe" -> do_bribe(ctx, jail, cfg)
        "escape" -> do_escape(ctx, jail, cfg)
        _ -> do_serve(ctx, jail, cfg)
      end
    end
  end

  # --- Режимы -----------------------------------------------------------------

  defp choose_mode(ctx, jail, _cfg) do
    if jail["mode"] do
      jail
    else
      p = ctx.personality || %{}
      cfg = ((ctx.configs || %{})["activities"] || %{})["jail"] || %{}
      bribe_cost = Enum.random(range(cfg["bribe_cost"] || [30, 60]))

      cond do
        # Жадный и богатый купит свободу
        Map.get(p, :greed, 50) > 55 and ctx.hero.gold >= bribe_cost ->
          Map.merge(jail, %{"mode" => "bribe", "bribe_cost" => bribe_cost})

        # Ловкий и храбрый рискнёт побегом
        Map.get(p, :dexterity, 50) + Map.get(p, :bravery, 50) > 120 ->
          Map.merge(jail, %{"mode" => "escape"})

        # Остальные сидят
        true ->
          Map.put(jail, "mode", "serve")
      end
    end
  end

  defp do_serve(ctx, jail, cfg) do
    ticks_left = jail["ticks_left"] - 1
    # В тюрьме кормят баландой: голод снижается (hunger_change < 0)
    feed = rand_in(cfg["jail_feed"] || [2, 6]) * -1

    if ticks_left <= 0 do
      release(ctx, jail, feed)
    else
      {:ok, %{
        state_to: "jailed",
        hunger_change: feed,
        state_data_update: %{"jail" => Map.put(jail, "ticks_left", ticks_left)},
        context: %{"jail_reason" => jail["reason"], "jail_ticks" => ticks_left},
      }}
    end
  end

  defp do_bribe(ctx, jail, _cfg) do
    cost = jail["bribe_cost"] || 40
    paid = min(ctx.hero.gold, cost)
    release(ctx, jail, 0, gold_change: -paid)
  end

  defp do_escape(ctx, jail, cfg) do
    chance = (cfg["escape_chance"] || 0.25) + Map.get(ctx.personality || %{}, :dexterity, 50) / 250.0

    if :rand.uniform() < chance do
      hp_loss = rand_in(cfg["escape_hp_loss"] || [10, 25])
      release(ctx, jail, 0, hp_change: -hp_loss, escaped: true)
    else
      # Провал: увечья и +2 тика
      hp_loss = rand_in(cfg["escape_hp_loss"] || [10, 25])
      ticks_left = jail["ticks_left"] + 2

      {:ok, %{
        state_to: "jailed",
        hp_change: -hp_loss,
        state_data_update: %{"jail" => Map.merge(jail, %{"ticks_left" => ticks_left})},
        context: %{"jail_escape_fail" => "true", "trap_hp" => hp_loss},
      }}
    end
  end

  defp release(ctx, jail, hunger_delta, extra \\ []) do
    # Награда в этом городе списана — отсижено/заплачено/сбежал.
    # law-блок — чистый merge через state_data_update (без прямых записей).
    law0 = (ctx.state_data || %{})["law"] || TesIdle.Game.Law.law_of(ctx.hero)
    law = Law.clear_bounties(law0, jail["location_id"])

    base = %{
      state_to: "exploring",
      state_data_update: %{"jail" => nil, "law" => law},
      context: %{
        "jail_reason" => jail["reason"],
        "jail_escaped" => to_string(extra[:escaped] == true),
      },
    }

    base
    |> put_opt(:gold_change, extra[:gold_change])
    |> put_opt(:hp_change, extra[:hp_change])
    |> put_opt(:hunger_change, if(hunger_delta == 0, do: nil, else: hunger_delta))
    |> then(&{:ok, &1})
  end

  defp put_opt(result, _key, nil), do: result
  defp put_opt(result, key, value), do: Map.put(result, key, value)

  defp jail_state(ctx) do
    case Jason.decode(ctx.hero.state_data || "{}") do
      {:ok, %{"jail" => j}} when is_map(j) -> j
      _ -> nil
    end
  end

  defp rand_in([lo, hi]) when is_number(lo) and is_number(hi), do: Enum.random(round(lo)..round(hi))
  defp rand_in(v) when is_number(v), do: v
  defp rand_in(_), do: 5

  defp range([lo, hi]) when is_number(lo) and is_number(hi), do: round(lo)..round(hi)
  defp range(_), do: 30..60
end
