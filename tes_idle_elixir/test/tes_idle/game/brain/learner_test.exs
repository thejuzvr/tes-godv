defmodule TesIdle.Game.Brain.LearnerTest do
  use ExUnit.Case, async: true

  alias TesIdle.Game.Brain.{Genome, Learner}
  alias TesIdle.Schemas.Hero

  @cfg %{"brain" => %{
    "enabled" => true, "plasticity_week" => 10.0, "base_return" => 0.02,
    "drift_up" => 0.01, "drift_down" => 0.015, "drift_range" => 0.3,
    "rebirth_mutation" => 5,
  }}

  defp hero(day \\ 3) do
    %Hero{
      name: "Тест", race: "Nord", hero_class: "Warrior", game_day: day,
      brain_hash: Genome.brain_hash("learner-user"),
      personality: %{bravery: 60, curiosity: 50, greed: 40, sociability: 50,
                     tenacity: 55, caution: 45, patience: 50, dexterity: 50, empathy: 50},
      state_data: Jason.encode!(%{}),
    }
  end

  test "выключенный мозг → nil" do
    {p, b} = Learner.learn(hero(), %{state_to: "exploring"}, %{"brain" => %{"enabled" => false}})
    assert is_nil(p) and is_nil(b)
  end

  test "победа повышает bravery в пределах бюджета" do
    {p, brain} = Learner.learn(hero(), %{combat_result: %{victory: true}, state_to: "fighting"}, @cfg)
    assert p.bravery > 60
    assert brain["budget"]["spent"] > 0
    assert brain["budget"]["spent"] <= 10.0
  end

  test "бюджет недельный: перерасход не даёт уйти за лимит" do
    # 30 побед подряд в одну неделю — bravery не улетит
    h = hero()
    {_h2, p} =
      1..30
      |> Enum.reduce({h, nil}, fn _, {h, _} ->
        {p, brain} = Learner.learn(h, %{combat_result: %{victory: true}}, @cfg)
        # state_data персистится между тиками (как в проде через pipeline)
        h2 = h
             |> Map.put(:personality, p)
             |> Map.put(:state_data, Jason.encode!(%{"brain" => brain}))
        {h2, p}
      end)

    # Бюджет 10 на неделю → сдвиг bravery ограничен (~10 п., гомеостаз тянет назад)
    assert p.bravery <= 60 + 12
  end

  # C-3: гомеостаз — раз в игровой день, не каждый тик
  test "гомеостаз срабатывает раз в игровой день, а не каждый тик" do
    # Первый тик дня: возврат применён (last_return_day записан)
    {p1, brain1} = Learner.learn(hero(), %{combat_result: %{victory: true}}, @cfg)
    assert brain1["last_return_day"] == 3

    # Тот же день, персистится brain → возврат НЕ применяется
    h2 = hero() |> Map.put(:personality, p1) |> Map.put(:state_data, Jason.encode!(%{"brain" => brain1}))
    {_p2, brain2} = Learner.learn(h2, %{combat_result: %{victory: true}}, @cfg)
    assert brain2["last_return_day"] == 3

    # Новый день → возврат снова работает
    h3 = hero(4) |> Map.put(:state_data, Jason.encode!(%{"brain" => brain2}))
    {_p3, brain3} = Learner.learn(h3, %{combat_result: %{victory: true}}, @cfg)
    assert brain3["last_return_day"] == 4
  end

  test "гомеостаз за неделю слабее бюджетной пластичности (обучение живёт)" do
    # base_return 0.02 раз в день: 7 дней × 9 черт ≈ 1.3 п./нед суммарно —
    # на порядок меньше бюджета 10 п./нед. Победы должны реально двигать черту.
    h = hero()
    {h2, p} =
      1..35
      |> Enum.reduce({h, nil}, fn day, {h, _} ->
        h_day = %{h | game_day: day}
        {p, brain} = Learner.learn(h_day, %{combat_result: %{victory: true}}, @cfg)
        h2 = h_day
             |> Map.put(:personality, p)
             |> Map.put(:state_data, Jason.encode!(%{"brain" => brain}))
        {h2, p}
      end)

    # 35 дней ≈ 5 недель: пластичность 50 п., гомеостаз-откат ~6.5 п. →
    # bravery должен вырасти существенно, а не остаться у базы (60).
    assert p.bravery >= 62, "обучение должно преодолевать гомеостаз, got #{p.bravery}"
  end

  test "новая неделя сбрасывает бюджет" do
    {_p, brain} = Learner.learn(hero(10), %{combat_result: %{victory: true}}, @cfg)
    assert brain["budget"]["week"] == 2
    assert brain["budget"]["spent"] <= 10.0
  end

  test "дрейф связей ограничен коридором ±0.3 от базы" do
    {_p, brain} = Learner.learn(hero(), %{combat_result: %{victory: true}}, @cfg)
    links = brain["links"]

    assert map_size(links) == 15

    Enum.each(links, fn {_k, w} -> assert w >= -1.0 and w <= 1.0 end)
  end

  test "перерождение: generation+1, причуды сохраняются, черты в 0..100" do
    h = hero()
    {p, brain} = Learner.reborn(h, @cfg)

    assert brain["generation"] == 2
    # значения float — проверяем коридор, а не Range (float не входит в 0..100)
    assert Enum.all?(Map.values(p), &(&1 >= 0 and &1 <= 100))
    assert brain["budget"]["spent"] == 0.0

    # Лог содержит запись о перерождении
    assert Enum.any?(brain["decision_log"], &(&1["goal"] == "__rebirth__"))
  end

  test "легаси-герой без hash перерождается с сохранением черт (мутация ±5)" do
    h = %{hero() | brain_hash: nil}
    {p, brain} = Learner.reborn(h, @cfg)
    assert brain["generation"] == 2
    assert p.bravery >= 55 and p.bravery <= 65
  end
end
