defmodule TesIdle.Game.Skills do
  @moduledoc """
  Навыки героя (heroes.skills JSONB): fishing, gathering, mining, stealth, lockpicking.
  Растут от повторения (0..100), замедляясь к верху. Читаются экшенами как
  шанс успеха / бонус, пишутся после соответствующих активностей.
  """

  @known [:fishing, :gathering, :mining, :stealth, :lockpicking]

  @doc "Карта навыков героя (атомные ключи, 0..100)."
  def all(hero) do
    raw = hero.skills || %{}

    Map.new(@known, fn k ->
      v = Map.get(raw, k) || Map.get(raw, Atom.to_string(k)) || 0
      {k, clamp100(v)}
    end)
  end

  def get(hero, skill) when skill in @known do
    all(hero)[skill]
  end

  @doc "Прирост навыка (дельта > 0). Рост замедляется: чем выше навык, тем реже +1."
  def gain(hero, skill, delta) when skill in @known and is_number(delta) and delta > 0 do
    gain(hero, skill, delta, 1.0)
  end

  @doc "S-4: прирост с темпом прогрессии (rate из configs[\"progression\"][\"skill_rate\"])."
  def gain(hero, skill, delta, rate) when skill in @known and is_number(delta) and delta > 0 and is_number(rate) do
    current = get(hero, skill)
    # Замедление: при 0 растёт на delta, при 100 не растёт
    speed = 1.0 - current / 110.0
    add = delta * rate * max(0.15, speed)
    bump(hero, skill, add)
  end

  @doc "S-4: множитель темпа навыков из configs[\"progression\"] (пустой конфиг → 1.0)."
  def rate(configs) do
    ((configs || %{})["progression"] || %{})["skill_rate"] || 1.0
  end

  @doc "Темп ремесла с пассивом «Тропа». Доля маленькая и не заменяет rate."
  def rate(configs, hero) do
    rate(configs) * (1 + TesIdle.Game.Passives.bonus(hero).skill)
  end

  @doc "Прямое изменение навыка (может уменьшать)."
  def bump(hero, skill, delta) when skill in @known do
    new = clamp100(get(hero, skill) + delta) |> round2()
    skills = Map.put(all(hero), skill, new)
    {skills, new}
  end

  defp clamp100(v), do: v |> max(0) |> min(100)
  defp round2(v), do: round(v * 100) / 100
end
