defmodule SeedSkyforge do
  @moduledoc "C-2: шаблоны журнала заточки (идемпотентно)."

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.{GameConfig, NarrativeTemplate}
  alias TesIdle.Game.Skyforge

  @templates [
    "«{item}» снова поёт от огня небесной кузни — ступень заточки {level}.",
    "{hero_name} выкладывает золото на наковальню Skyforge: «{item}» крепчает, ступень {level}.",
    "Дым и искры: «{item}» проходит закалку №{level} — небесная кузня довольна.",
    "«{item}» впитывает жар звёздной стали — заточка {level} держится намертво.",
    "Молот бьёт трижды: «{item}» достигает ступени {level}. Кузнец кивает.",
    "Деньги уходят в горн без звука, но «{item}» выходит из него острее — ступень {level}."
  ]

  {:ok, _} = Application.ensure_all_started(:tes_idle)

  existing =
    Repo.all(from t in NarrativeTemplate, where: t.template_type == "enhance_success", select: t.text_template)

  inserted =
    Enum.reduce(@templates, 0, fn text, acc ->
      if text in existing do
        acc
      else
        Repo.insert!(%NarrativeTemplate{
          template_type: "enhance_success",
          text_template: text,
          source: "system",
          is_active: true
        })

        acc + 1
      end
    end)

  total =
    Repo.one(from t in NarrativeTemplate, where: t.template_type == "enhance_success", select: count(t.id))

  IO.puts("seed_skyforge: шаблонов +#{inserted} (всего #{total})")

  case Repo.one(from g in GameConfig, where: g.key == "skyforge", select: g.id) do
    nil ->
      Repo.insert!(%GameConfig{
        key: "skyforge",
        value: Jason.encode!(Skyforge.default_config()),
        description: "Небесная кузня: заточка экипировки (C-2)"
      })

      IO.puts("seed_skyforge: game_configs[skyforge] вставлен")

    _ ->
      IO.puts("seed_skyforge: game_configs[skyforge] уже есть")
  end

  :ok
end
