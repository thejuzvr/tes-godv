defmodule TesIdle.Game.Actions.StealingAction do
  @moduledoc """
  Воровство (ROADMAP Часть II): только city/village.
  Roll свидетелей (Law.witness_roll): dexterity + навык stealth + ночь/дождь vs стража.
  Успех → золото в карман; заметили → награда за голову + репутация фракции −;
  схватили → штраф, при большой сумме награды — арест (state jailed).
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.{GameContext, Law, Skills}
  alias TesIdle.Repo

  @impl true
  def score(%GameContext{} = _ctx), do: 50

  @impl true
  def execute(%GameContext{} = ctx) do
    cfg = ((ctx.configs || %{})["activities"] || %{})["stealing"] || %{}

    if city?(ctx) do
      do_steal(ctx, cfg)
    else
      TesIdle.Game.Actions.ExploreAction.execute(ctx)
    end
  end

  defp do_steal(ctx, cfg) do
    # Ценность кражи: скромное золото в карманах горожан
    crime_gold = Enum.random(5..25)
    law0 = (ctx.state_data || %{})["law"] || %{"bounties" => %{}}

    case Law.on_crime(ctx, crime_gold, law0) do
      %{outcome: :clean} ->
        bump_stealth(ctx, cfg)

        {:ok, %{
          state_to: "sneaking",
          gold_change: crime_gold,
          context: %{"stolen_gold" => crime_gold, "witness_outcome" => "clean"},
        }}

      %{outcome: :spotted, bounty_added: bounty, law: law} ->
        bump_stealth(ctx, cfg)

        {:ok, %{
          state_to: "sneaking",
          state_data_update: %{"law" => law},
          context: %{
            "witness_name" => witness_name(),
            "bounty_gold" => bounty,
            "witness_outcome" => "spotted",
          },
        }}

      %{outcome: :caught, bounty_added: bounty, fine: fine, arrested: arrest?, law: law} ->
        bump_stealth(ctx, cfg)
        fine_paid = -min(ctx.hero.gold, fine)
        ctx_common = %{"witness_name" => witness_name(), "bounty_gold" => bounty, "fine_gold" => fine}

        if arrest? do
          jail = Law.start_jail(ctx, "steal")

          {:ok, %{
            state_to: "jailed",
            gold_change: fine_paid,
            state_data_update: %{"jail" => jail, "law" => law},
            context: Map.put(ctx_common, "witness_outcome", "arrested"),
          }}
        else
          {:ok, %{
            state_to: "sneaking",
            gold_change: fine_paid,
            state_data_update: %{"law" => law},
            context: Map.put(ctx_common, "witness_outcome", "caught"),
          }}
        end
    end
  end

  defp bump_stealth(ctx, cfg) do
    {skills, _} = Skills.gain(ctx.hero, :stealth, cfg["skill_xp"] || 1, Skills.rate(ctx.configs))
    ctx.hero |> Ecto.Changeset.change(%{skills: skills}) |> Repo.update!()
  end

  defp city?(ctx), do: ctx.location_type in ["city", "village"]

  defp witness_name do
    Enum.random(["Олаф Двужильный", "Хельга Пивная", "Торстен Седой", "стражник Фенрир",
      "купчиха Ингрид", "мальчишка-гонец"])
  end
end
