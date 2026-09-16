defmodule TesIdle.Game.JailNarrativeTest do
  use ExUnit.Case, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, User}
  alias TesIdle.Game.Pipeline

  # P-3: тюрьма — комичные модерируемые нарративы из БД.
  # 1) интеграция: serve-тики продвигают отсидку и не роняют пайплайн; jail-запись
  #    (когда событие jail_time выпало) идёт из БД без {var}-дырок.
  # 2) сид-пул jail: только whitelisted переменные (нет дырок ни в одном контексте).

  @jail_seed_path Path.expand("../../../priv/seed_phase2.exs", __DIR__)
  @jail_vars_whitelist ["hero_name", "jail_reason", "jail_ticks"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_jail_#{suffix}",
        email: "qa_jail_#{suffix}@test.gg", password_hash: "x"})

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "QA-Узник",
        race: "Имперец",
        hero_class: "Thief",
        level: 4,
        hp: 80,
        max_hp: 100,
        gold: 50,
        state: "jailed",
        personality: %{"bravery" => 40, "curiosity" => 60, "greed" => 70, "sociability" => 50,
          "tenacity" => 50, "caution" => 30, "patience" => 40, "dexterity" => 65, "empathy" => 50},
        state_data: Jason.encode!(%{
          "jail" => %{"mode" => "serve", "ticks_left" => 2, "total_ticks" => 3,
            "reason" => "кража", "location_id" => nil, "location_name" => "Подвал Рифтена"},
        }),
        brain_hash: TesIdle.Game.Brain.Genome.brain_hash(user.id),
      })

    %{hero: hero}
  end

  defp template(text) do
    Repo.insert!(%TesIdle.Schemas.NarrativeTemplate{
      template_type: "jail", text_template: text, source: "system", is_active: true})
  end

  test "serve-тики: отсидка продвигается, jail-записи из БД без {var}-дырок", %{hero: hero} do
    template("Сосед по камере торгует соломой по спекулятивной цене. {hero_name} ведёт переговоры за {jail_reason}.")
    template("День {jail_ticks}: {hero_name} отсиживает за {jail_reason}. Баланда, лавка, мысли о воле.")

    {:ok, result1} = Pipeline.tick(hero.id)
    reloaded = Repo.reload!(hero)
    assert reloaded.state == "jailed"
    assert Jason.decode!(reloaded.state_data)["jail"]["ticks_left"] == 1

    if entry = result1.journal_entry do
      if entry.entry_type in ["jail", "jail_time"], do: refute(entry.text =~ "{")
    end

    {:ok, _} = Pipeline.tick(hero.id)
    {:ok, result3} = Pipeline.tick(hero.id)

    reloaded = Repo.reload!(hero)
    # Фаза 2 (аудит): после ослабления квеста герой сам выбирает дело —
    # после выхода может начать loot/explore/fish…, важен выход из тюрьмы.
    assert reloaded.state != "jailed"
    assert Jason.decode!(reloaded.state_data)["jail"] == nil
    assert result3.state_to != "jailed"
  end

  test "сид-пул jail: >= 12 строк тональной смеси, vars только из whitelist" do
    assert File.exists?(@jail_seed_path)
    source = File.read!(@jail_seed_path)

    block =
      case String.split(source, "jail = [") do
        [_head, tail] ->
          case String.split(tail, "\n]", parts: 2) do
            [inner, _rest] -> inner
            _ -> flunk("в seed_phase2.exs не найден конец пула jail")
          end

        _ ->
          flunk("в seed_phase2.exs не найден пул jail")
      end

    lines =
      block
      |> String.split("\n")
      |> Enum.filter(&(String.trim(&1) =~ ~r/^"/))
      |> Enum.map(fn line ->
        case Regex.run(~r/^"(.+)",?\s*$/, String.trim(line)) do
          [_, text] -> text
          _ -> ""
        end
      end)

    assert length(lines) >= 12, "пул jail должен быть расширен (>= 12 строк)"

    for text <- lines, text != "" do
      vars =
        Regex.scan(~r/\{([a-z_]+)\}/, text)
        |> Enum.map(&List.last(&1))
        |> Enum.uniq()

      bad = Enum.reject(vars, &(&1 in @jail_vars_whitelist))
      assert bad == [], "шаблон «#{text}» использует переменные вне whitelist: #{inspect(bad)}"
    end
  end
end
