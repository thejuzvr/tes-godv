defmodule TesIdle.Game.SleepTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, User}
  alias TesIdle.Schemas.NarrativeTemplate
  alias TesIdle.Game.Sleep
  import Ecto.Query

  # P-4: сны при долгом отдыхе. Sleep.step — кандидат-функция (merged_sd + шаблон),
  # вставку записи делает Pipeline. Тесты: streak, тишина вне отдыха, честная тишина
  # без шаблонов, dream-шаблон из БД + дневной кап.

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp hero(game_day \\ 5) do
    %Hero{
      id: Ecto.UUID.generate(),
      name: "QA-Сновидец",
      game_day: game_day,
      user_id: Ecto.UUID.generate(),
    }
  end

  test "streak растёт на resting-тиках и сбрасывается вне отдыха" do
    h = hero()
    {merged, nil} = Sleep.step(%{}, h, %{state_to: "resting"}, %{})
    assert merged["sleep"]["streak"] == 1
    {merged, nil} = Sleep.step(merged, h, %{state_to: "resting"}, %{})
    assert merged["sleep"]["streak"] == 2

    # герой встал — блок sleep сброшен
    {merged, nil} = Sleep.step(merged, h, %{state_to: "exploring"}, %{})
    assert merged["sleep"] == nil
  end

  test "dream раньше min_streak не пишется даже при chance 1.0" do
    h = hero()
    configs = %{"sleep" => %{"dream_chance" => 1.0, "min_streak" => 3}}

    {merged, nil} = Sleep.step(%{}, h, %{state_to: "resting"}, configs)
    assert merged["sleep"]["streak"] == 1
    {merged, nil} = Sleep.step(merged, h, %{state_to: "resting"}, configs)
    assert merged["sleep"]["streak"] == 2
    assert merged["sleep"]["last_dream_day"] == nil
  end

  test "пул dream пуст → честная тишина (streak растёт, шаблона нет)" do
    Repo.delete_all(NarrativeTemplate)
    h = hero()
    configs = %{"sleep" => %{"dream_chance" => 1.0, "min_streak" => 3}}
    merged = %{"sleep" => %{"streak" => 9, "last_dream_day" => nil}}

    {merged, template} = Sleep.step(merged, h, %{state_to: "resting"}, configs)
    assert merged["sleep"]["streak"] == 10
    assert template == nil
  end

  test "dream при активном шаблоне: кандидат есть, last_dream_day ставится; повтор в тот же день — тишина" do
    suffix = System.unique_integer([:positive])
    user = Repo.insert!(%User{username: "qa_sleep_#{suffix}",
      email: "qa_sleep_#{suffix}@test.gg", password_hash: "x"})

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "QA-Сновидец",
        race: "Имперец",
        hero_class: "Thief",
        level: 3,
        hp: 90,
        max_hp: 100,
        gold: 10,
        state: "resting",
        game_day: 5,
        location_id: Repo.one!(from l in TesIdle.Schemas.Location, limit: 1).id,
        brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id),
      })

    Repo.insert!(%TesIdle.Schemas.NarrativeTemplate{
      template_type: "dream",
      text_template: "Сон QA: {hero_name} спал. Безмятежно.",
      source: "system", is_active: true})

    hero_loaded = Repo.reload!(hero)
    configs = %{"sleep" => %{"dream_chance" => 1.0, "min_streak" => 3}}

    {merged, template} =
      Sleep.step(%{"sleep" => %{"streak" => 2, "last_dream_day" => nil}}, hero_loaded,
        %{state_to: "resting"}, configs)

    assert template != nil
    assert template.text_template =~ "{hero_name}"
    assert merged["sleep"]["streak"] == 3
    assert merged["sleep"]["last_dream_day"] == 5

    # рендер без дырок (как это делает create_dream_entry)
    text = TesIdle.Game.Narrative.TemplateEngine.render_vars(template.text_template, %{
      "hero_name" => hero_loaded.name, "location_name" => "Ривервуд"})
    refute text =~ "{"
    assert text =~ "QA-Сновидец"

    # второй сон в тот же игровой день — не пишется (дневной кап)
    {merged2, nil} =
      Sleep.step(%{"sleep" => %{"streak" => 9, "last_dream_day" => 5}}, hero_loaded,
        %{state_to: "resting"}, configs)
    assert merged2["sleep"]["streak"] == 10
  end
end
