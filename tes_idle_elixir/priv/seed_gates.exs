# C-3 «Врата Обливиона»: шаблоны журнала взноса + весть о запечатанных вратах + конфиг gates
# Запуск: mix run priv/seed_gates.exs (идемпотентно: {type, text} не дублируются)

alias TesIdle.Repo
alias TesIdle.Schemas.{GameConfig, NarrativeTemplate}
import Ecto.Query

defmodule SeedGates do
  @donation_templates [
    {"gate_donation", "{hero_name} бросает {amount} золота в багровую дыру: фонд экспедиции — {fund} 🪙. {status}."},
    {"gate_donation", "Клинок не берёт Врата — берёт кошель. {hero_name} добавляет {amount} золота ({fund} 🪙 в фонде). {status}."},
    {"gate_donation", "{hero_name} щедро кладёт {amount} золота на алтарь экспедиции. Итого фонд: {fund} 🪙. {status}."},
    {"gate_donation", "«На врата!» — {hero_name} скидывается {amount} золота. Собрано {fund} 🪙. {status}."},
    {"gate_donation", "{hero_name} тратит {amount} золота на снаряжение героев, идущих к Вратам. Фонд: {fund} 🪙. {status}."},
    {"gate_donation", "{amount} золота уходит в багровое свечение над {location}. Фонд экспедиции: {fund} 🪙. {status}."}
  ]

  @closed_news [
    {"gate_closed", "🌀 Фонд экспедиции собран ({fund} 🪙) — над «{location}» врата запечатаны! Слава {hero}!"},
    {"gate_closed", "🌀 Врата Обливиона над «{location}» захлопнулись: {fund} золота ушло в поход. Отличная работа, {hero}!"},
    {"gate_closed", "🌀 Экспедиция вернулась: «{location}» снова тихо. Врата запечатаны фондом {fund} 🪙. Во главе — {hero}."}
  ]

  def run do
    existing =
      Repo.all(from t in NarrativeTemplate, where: t.source == "system", select: {t.template_type, t.text_template})
      |> MapSet.new()

    inserted =
      Enum.reduce(@donation_templates ++ @closed_news, 0, fn {type, text}, acc ->
        if MapSet.member?(existing, {type, text}) do
          acc
        else
          Repo.insert!(%NarrativeTemplate{
            template_type: type,
            text_template: text,
            source: "system",
            is_active: true
          })

          acc + 1
        end
      end)

    cfg_state = if Repo.exists?(from c in GameConfig, where: c.key == "gates"), do: "есть", else: "создан"
    insert_config()
    IO.puts("seed_gates: шаблонов +#{inserted} (donation 6, closed 3), конфиг gates: #{cfg_state}")
  end

  defp insert_config do
    unless Repo.exists?(from c in GameConfig, where: c.key == "gates") do
      Repo.insert!(%GameConfig{
        key: "gates",
        value: Jason.encode!(%{
          "open_chance" => 0.02,
          "fund_target" => 2000,
          "deadline_ticks" => 72,
          "cooldown_ticks" => 48
        }),
        description: "C-3 Врата Обливиона: шанс открытия за тик, цель фонда, срок (тики), cooldown"
      })
    end
  end
end

SeedGates.run()
