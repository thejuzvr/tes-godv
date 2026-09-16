defmodule TesIdle.Game.Narrative.ComposerTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeFragment
  alias TesIdle.Game.Narrative.Composer
  alias TesIdle.Test.FragmentIsolation

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    # N-5: сид наполнил реальные пулы (openers_*/closers_*/quirk_*/memory_*) —
    # прячем их на время теста, чтобы draw() брал только тестовые строки.
    hidden = FragmentIsolation.hide_seed_fragments(["openers_", "closers_", "quirk_", "memory_"])
    on_exit(fn -> FragmentIsolation.restore(hidden) end)
    :ok
  end

  defp fragment(pool, text) do
    Repo.insert!(%NarrativeFragment{pool_key: pool, text: text, source: "system", is_active: true})
  end

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %{
        configs: %{"composer" => composer_cfg()},
        weather: "rain",
        mood: 70.0,
        hero: %{game_day: 10},
        memories: [],
        quirks: [],
      },
      overrides
    )
  end

  defp composer_cfg(overrides \\ %{}) do
    Map.merge(
      %{
        "enabled" => true,
        "types" => ["explore", "rest", "travel"],
        "opener_chance" => 1.0,
        "closer_chance" => 1.0,
      },
      overrides
    )
  end

  defp full_cfg(overrides \\ %{}) do
    Map.merge(
      %{
        "enabled" => true,
        "types" => ["explore", "rest", "travel"],
        "closer_only_types" => ["combat_result"],
        "opener_chance" => 1.0,
        "closer_chance" => 1.0,
        "quirk_chance" => 1.0,
        "memory_chance" => 1.0,
        "memory_days" => 2,
      },
      overrides
    )
  end

  test "выключенный конфиг → костяк без изменений" do
    text = Composer.compose("explore", "Костяк.", ctx(%{configs: %{"composer" => %{"enabled" => false}}}), %{})
    assert text == "Костяк."
  end

  test "пустой конфиг → костяк без изменений (безопасный дефолт)" do
    text = Composer.compose("explore", "Костяк.", %{configs: %{}}, %{})
    assert text == "Костяк."
  end

  test "тип не в списке types → костяк без изменений" do
    text = Composer.compose("combat_result", "Костяк.", ctx(), %{})
    assert text == "Костяк."
  end

  test "сцена = опенер погоды + костяк + closer с подстановкой {hero_name}" do
    fragment("openers_rain", "Моросил частый дождь.")
    fragment("closers_high", "{hero_name} шагал легко.")

    vars = %{"hero_name" => "Квеннар"}
    text = Composer.compose("explore", "Герой осмотрелся по сторонам.", ctx(), vars)

    assert String.starts_with?(text, "Моросил частый дождь. ")
    assert text =~ "Герой осмотрелся по сторонам."
    assert String.ends_with?(text, "Квеннар шагал легко.")
  end

  test "погода без пула и пустые closers → просто костяк" do
    text = Composer.compose("rest", "Костяк.", ctx(%{weather: "storm"}), %{})
    assert text == "Костяк."
  end

  test "mood-полосы: ≤40 → closers_low, 40–60 → closers_mid" do
    fragment("closers_low", "Ноги несли, но сердце отставало.")
    fragment("closers_mid", "Дорога стелилась вперёд.")

    low = Composer.compose("rest", "Костяк.", ctx(%{mood: 30.0}), %{})
    assert low =~ "Ноги несли, но сердце отставало."

    mid = Composer.compose("rest", "Костяк.", ctx(%{mood: 50.0}), %{})
    assert mid =~ "Дорога стелилась вперёд."
  end

  test "шанс 0 → без опенера и closer'а" do
    fragment("openers_rain", "Моросил частый дождь.")
    fragment("closers_high", "Closer.")

    cfg = composer_cfg(%{"opener_chance" => 0.0, "closer_chance" => 0.0})
    text = Composer.compose("explore", "Костяк.", ctx(%{configs: cfg}), %{})
    assert text == "Костяк."
  end

  # --- N-3: closer_only_types — боевые типы без опенера погоды ---

  test "closer_only тип: опенер-пул заполнен, но сцена без опенера и с closer" do
    fragment("openers_rain", "Моросил частый дождь.")
    fragment("closers_high", "{hero_name} переводил дыхание.")

    cfg = %{"composer" => full_cfg()}
    text = Composer.compose("combat_result", "Герой поверг врага.", ctx(%{configs: cfg, quirks: [], memories: []}), %{"hero_name" => "Квеннар"})

    refute text =~ "Моросил"
    assert String.starts_with?(text, "Герой поверг врага. ")
    assert String.ends_with?(text, "Квеннар переводил дыхание.")
  end

  # --- N-3: quirk-closers (BrainHash причуды) ---

  test "quirk-closer: причуда braggart → текст из quirk-пула" do
    fragment("quirk_braggart", "{hero_name} уже репетировал рассказ.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [:braggart]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{"hero_name" => "Квеннар"})

    assert String.ends_with?(text, "Квеннар уже репетировал рассказ.")
  end

  test "quirk-пул пуст → fallback к mood-полосе" do
    fragment("closers_high", "Closer по настроению.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [:braggart]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    assert text =~ "Closer по настроению."
  end

  # --- N-3: memory-closers (свежая память) ---

  test "memory-closer: свежая память победы → текст из memory_victory" do
    fragment("memory_victory", "Жар схватки ещё не остыл.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [], memories: [%{"type" => "victory", "day" => 9}]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    assert text =~ "Жар схватки ещё не остыл."
  end

  test "память старше memory_days → mood-полоса вместо memory-пула" do
    fragment("memory_victory", "Жар схватки ещё не остыл.")
    fragment("closers_high", "Closer по настроению.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [], memories: [%{"type" => "victory", "day" => 5}]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    refute text =~ "Жар схватки"
    assert text =~ "Closer по настроению."
  end

  test "приоритет: quirk-closer выигрывает у memory-closer" do
    fragment("quirk_braggart", "Quirk-closer.")
    fragment("memory_victory", "Memory-closer.")
    fragment("closers_high", "Mood-closer.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [:braggart], memories: [%{"type" => "victory", "day" => 9}]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    assert text =~ "Quirk-closer."
    refute text =~ "Memory-closer."
    refute text =~ "Mood-closer."
  end

  # --- N-3b: конкретика памяти в memory-closers ---

  test "memory-closer подставляет {monster} из свежей памяти победы" do
    fragment("memory_victory", "В памяти свежа победа — {monster} пал от руки героя.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [], memories: [%{"type" => "victory", "monster" => "тролль", "day" => 9}]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    assert text =~ "тролль пал от руки героя"
    refute text =~ "{monster}"
  end

  test "память без данных для {var} → closer отбрасывается, mood-fallback" do
    fragment("memory_victory", "Победа над {monster} грела сильнее солнца.")
    fragment("closers_high", "Closer по настроению.")

    cfg = %{"composer" => full_cfg()}
    # monster нет в памяти → {monster} не подставится → closer отброшен
    ctx_ = ctx(%{configs: cfg, quirks: [], memories: [%{"type" => "victory", "day" => 9}]})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    refute text =~ "{monster}"
    assert text =~ "Closer по настроению."
  end

  # --- N-5: страховка рендера опенера ---

  test "опенер с {var} рендерится, а не остаётся дыркой" do
    fragment("openers_rain", "День выдался ясный, и {hero_name} проснулся рано.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [], memories: []})
    text = Composer.compose("explore", "Костяк.", ctx_, %{"hero_name" => "Квеннар"})

    refute text =~ "{hero_name}"
    assert text =~ "Квеннар проснулся рано"
  end

  test "опенер с непокрываемой {var} отбрасывается — сцена без опенера" do
    fragment("openers_rain", "Небо хранило тайну {ancient_word}.")

    cfg = %{"composer" => full_cfg()}
    ctx_ = ctx(%{configs: cfg, quirks: [], memories: []})
    text = Composer.compose("explore", "Костяк.", ctx_, %{})

    refute text =~ "{ancient_word}"
    assert text == "Костяк."
  end

  # ─── N-4/A-1b: full_scene — одобренная llm-сцена не размножается ─────────

  test "full_scene: true возвращает костяк как есть — без опенера и closer" do
    scene = "Тучи висели низко. {hero_name} шёл молча. Дорога стелилась вперёд."
    out = Composer.compose("explore", scene, ctx(), %{hero_name: "Квеннар"}, full_scene: true)
    assert out == scene
  end

  test "full_scene: false — сцена собирается как раньше" do
    fragment("openers_clear", "Небо было чистым.")
    fragment("closers_high", "Closer по настроению.")
    out = Composer.compose("explore", "Костяк.", ctx(), %{}, full_scene: false)
    assert out != "Костяк."
    assert out =~ "Костяк."
    assert out =~ "Closer по настроению."
  end
end
