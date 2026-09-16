defmodule TesIdle.Game.ContentDatasetTest do
  @moduledoc """
  CD-1 «Дата-сет»: файловые контракт-тесты (test-БД не сидируется контентом,
  кроме reseed+fragments из ecto.reset). Читаем seed-файлы как текст.
  """

  use ExUnit.Case, async: true

  @elixir_root Path.expand("../../..", __DIR__)

  defp read_priv(name), do: File.read!(Path.join([@elixir_root, "priv", name]))

  test "seed_fragments: новые пулы CD-1 присутствуют и достаточно велики" do
    text = read_priv("seed_fragments.exs")

    for {pool, min} <- [{"monsters", 30}, {"shop_items", 20}, {"rumors", 20}, {"taverns", 10}] do
      case Regex.run(~r/"#{pool}" => \[(.*?)\n\s*\]/s, text) do
        [_, body] ->
          n = Enum.count(Regex.scan(~r/"[^"]+",?\s*\n/, body))
          assert n >= min, "пул #{pool}: #{n} строк, ожидалось >= #{min}"

        nil ->
          flunk("пул #{pool} не найден в seed_fragments.exs")
      end
    end
  end

  test "seed_narratives: дата-сет шаблонов не утерян" do
    text = read_priv("seed_narratives.exs")
    tuples = Regex.scan(~r/\{ "[a-z_]+", "/, text)
    assert length(tuples) >= 700
  end

  test "seed_content: шлемы (head) — полноценная линейка >= 15" do
    text = read_priv("seed_content.exs")
    heads = Regex.scan(~r/equip_slot: "head"/, text)
    assert length(heads) >= 15
  end

  test "seed_guild_shop: лавка 12 позиций + каталог-конфиг" do
    text = read_priv("seed_guild_shop.exs")
    assert text =~ "GameConfig"
    assert text =~ "\"catalog\" => catalog"
    guild_items = Regex.scan(~r/tags: \["guild"/, text)
    assert length(guild_items) >= 10
  end

  test "seed_monsters: бестиарий >= 30 монстров, все 6 боевых локаций, города пусты" do
    text = read_priv("seed_monsters.exs")
    monsters = Regex.scan(~r/\{"[^"]+", "[^"]+", \d+, \d+\}/, text)
    assert length(monsters) >= 30

    for loc <- ["Долина Буревестников", "Леса Глэмориин", "Ривервуд", "Фолкрит", "Драконья Падь", "Хребет Мира"] do
      assert text =~ "\"#{loc}\"", "локация #{loc} отсутствует в бестиарии"
    end

    for city <- ["Вайтран", "Солитьюд", "Виндхельм"] do
      refute text =~ "\"#{city}\"", "город #{city} не должен быть в бестиарии"
    end
  end

  test "ContextBuilder: fallback-каталог лавки = 12 позиций" do
    text = File.read!(Path.join([@elixir_root, "lib", "tes_idle", "game", "context_builder.ex"]))
    [catalog] = Regex.run(~r/"guild_shop" => %\{.*?\n      \}/s, text)
    entries = Regex.scan(~r/%\{"name" =>/, catalog)
    assert length(entries) == 12
  end

  test "seed_all: бестиарий в цепочке после content" do
    text = read_priv("seed_all.exs")
    content_pos = String.split(text, "seed_content.exs")
    monsters_pos = String.split(text, "seed_monsters.exs")
    assert length(monsters_pos) == 2, "seed_monsters не подключён к seed_all"
    assert length(content_pos) > length(monsters_pos) - 1
  end
end
