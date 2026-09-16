defmodule TesIdle.Game.ProgressionTest do
  @moduledoc "S-4-T: средний темп прогрессии — множители наград и A/B-симуляция тиков."
  use ExUnit.Case, async: true

  alias TesIdle.Game.Pipeline

  describe "apply_progression/2 (чистая функция)" do
    test "xp уменьшается по xp_multiplier" do
      result = Pipeline.apply_progression(%{xp: 100}, %{"progression" => %{"xp_multiplier" => 0.5}})
      assert result[:xp] == 50
    end

    test "положительное золото уменьшается по gold_multiplier" do
      result = Pipeline.apply_progression(%{gold_change: 100}, %{"progression" => %{"gold_multiplier" => 0.75}})
      assert result[:gold_change] == 75
    end

    test "траты (отрицательное золото) НЕ масштабируются" do
      result = Pipeline.apply_progression(%{gold_change: -100}, %{"progression" => %{"gold_multiplier" => 0.75}})
      assert result[:gold_change] == -100
    end

    test "пустой конфиг — старый темп (множители 1.0)" do
      result = Pipeline.apply_progression(%{xp: 100, gold_change: 40}, %{})
      assert result[:xp] == 100
      assert result[:gold_change] == 40
    end

    test "нулевые награды остаются нулями" do
      result = Pipeline.apply_progression(%{xp: 0, gold_change: 0}, %{"progression" => %{"xp_multiplier" => 0.5}})
      assert result[:xp] == 0
      assert result[:gold_change] == 0
    end
  end

  describe "Skills.rate/1" do
    test "rate из конфига, пустой конфиг → 1.0" do
      assert TesIdle.Game.Skills.rate(%{"progression" => %{"skill_rate" => 0.5}}) == 0.5
      assert TesIdle.Game.Skills.rate(%{}) == 1.0
      assert TesIdle.Game.Skills.rate(nil) == 1.0
    end

    test "gain с rate 0.5 растёт вдвое медленнее при прочих равных" do
      alias TesIdle.Game.Skills
      hero1 = %TesIdle.Schemas.Hero{skills: %{}}
      hero2 = %TesIdle.Schemas.Hero{skills: %{}}

      {skills_fast, fast} = Skills.gain(hero1, :fishing, 10, 1.0)
      {skills_slow, slow} = Skills.gain(hero2, :fishing, 10, 0.5)

      assert fast == 10.0
      assert_in_delta slow, 5.0, 0.01
      assert slow < fast
      assert skills_slow[:fishing] == slow
    end
  end
end
