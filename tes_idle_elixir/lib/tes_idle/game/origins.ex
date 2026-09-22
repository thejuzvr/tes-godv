defmodule TesIdle.Game.Origins do
  @moduledoc """
  Пять предысторий (docs/PLAN_CHARACTER.md, раздел 5).

  Предыстория задаёт первый день: город и скромный скарб. Потолка героя
  она не задаёт и после создания не меняется. Вещь ищется по имени; если
  сид её не положил, слот остаётся пустым — это честнее, чем фиктивный предмет.
  """

  @origins %{
    "beggar" => %{
      label: "Нищий",
      city: "Ривервуд",
      gold: 0,
      hunger: 55.0,
      note: "С самых низов, без монеты и без крыши.",
      items: []
    },
    "mage_student" => %{
      label: "Ученик магов",
      city: "Солитьюд",
      gold: 15,
      hunger: 30.0,
      note: "Ближе всего к Коллегии, в чужой робе.",
      mp: 70,
      items: ["Ученическая роба"]
    },
    "levy" => %{
      label: "Ополченец",
      city: "Вайтран",
      gold: 25,
      hunger: 30.0,
      note: "Городское ополчение выдало простое железо.",
      items: ["Клинок ополчения"]
    },
    "gutter" => %{
      label: "Тень обочины",
      city: "Рифтен",
      gold: 5,
      hunger: 40.0,
      note: "Канавы Рифтена учат раньше, чем гильдии.",
      stealth: 8,
      items: ["Отмычка"]
    },
    "acolyte" => %{
      label: "Послушник",
      city: "Виндхельм",
      gold: 10,
      hunger: 25.0,
      note: "Храмовая скамья и чужая ряса.",
      reputation: 5,
      items: ["Ряса послушника"]
    }
  }

  @default "beggar"

  def all, do: @origins
  def keys, do: Map.keys(@origins)

  def get(key), do: Map.get(@origins, key)

  @doc "Ключ предыстории. Пустое и неизвестное значение становится нищим."
  def resolve(nil), do: @default
  def resolve(""), do: @default

  def resolve(value) do
    needle = value |> to_string() |> String.trim()
    if Map.has_key?(@origins, needle), do: needle, else: nil
  end
end
