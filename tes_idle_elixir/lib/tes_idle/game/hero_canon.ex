defmodule TesIdle.Game.HeroCanon do
  @moduledoc """
  Канонические ключи расы и класса.

  Форма создания шлёт русские подписи («Воин», «Норд»), а расчёт личности
  исторически ждал английские («Warrior», «Nord»). Из-за этого модификаторы
  у героя из формы молча не срабатывали. Здесь одна таблица на оба написания:
  в БД по-прежнему лежит то, что прислал клиент, а расчёт берёт ключ.
  """

  @races %{
    "nord" => "Норд",
    "imperial" => "Имперец",
    "breton" => "Бретонец",
    "redguard" => "Редгард",
    "altmer" => "Альтмер",
    "bosmer" => "Босмер",
    "dunmer" => "Данмер",
    "orc" => "Орк",
    "khajiit" => "Каджит",
    "argonian" => "Аргонианин"
  }

  @classes %{
    "warrior" => "Воин",
    "mage" => "Маг",
    "thief" => "Вор",
    "rogue" => "Разбойник",
    "hunter" => "Охотник",
    "priest" => "Жрец",
    "paladin" => "Паладин",
    "assassin" => "Ассасин"
  }

  # Старые английские написания, которые уже лежат у части героев.
  @legacy %{
    "nord" => "nord",
    "imperial" => "imperial",
    "breton" => "breton",
    "redguard" => "redguard",
    "altmer" => "altmer",
    "woodelf" => "bosmer",
    "dunmer" => "dunmer",
    "orc" => "orc",
    "khajiit" => "khajiit",
    "argonian" => "argonian",
    "warrior" => "warrior",
    "mage" => "mage",
    "thief" => "thief",
    "priest" => "priest",
    "bard" => "priest",
    "berserker" => "warrior"
  }

  def races, do: @races
  def classes, do: @classes

  def race_key(value), do: lookup(value, @races)
  def class_key(value), do: lookup(value, @classes)

  def race_label(value), do: Map.get(@races, race_key(value), value)
  def class_label(value), do: Map.get(@classes, class_key(value), value)

  defp lookup(nil, _), do: nil

  defp lookup(value, table) do
    needle = value |> to_string() |> String.trim() |> String.downcase()

    cond do
      needle == "" ->
        nil

      key = Enum.find_value(table, fn {k, label} -> if down(label) == needle, do: k end) ->
        key

      Map.has_key?(@legacy, needle) ->
        @legacy[needle]

      true ->
        nil
    end
  end

  defp down(text), do: text |> String.downcase()
end
