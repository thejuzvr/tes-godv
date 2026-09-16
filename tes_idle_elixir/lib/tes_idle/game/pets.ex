defmodule TesIdle.Game.Pets do
  @moduledoc """
  PetSystem (ROADMAP Часть II): питомцы волк/сова/кот/ящерица.

  Решения пользователя (binding):
  - гибель в бою → **cooldown**, возрождение по таймеру `revive_at`
    (по умолчанию 4 реальных часа, game_configs → работает офлайн);
  - лояльность 0 → питомец уходит навсегда (status "gone");
  - уход (кормить/играть/дрессировать) — экшен `pet_care`, лояльность падает
    без ухода.

  Бонусы: волк — помощь в бою (шанс по loyalty), сова — +к discovery,
  кот — +к настроению.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.Pet
  import Ecto.Query

  @species ["wolf", "owl", "cat", "lizard", "goat", "fox", "raven", "goose", "hedgehog", "moth", "rock", "turnip", "butter", "skeleton", "cheese"]

  # Обычные: wolf/owl/cat/lizard/goat/fox/raven. Комичные: остальные.
  @species_names %{
    "wolf" => ["Клык", "Сумрак", "Лютый", "Рекс"],
    "owl" => ["Сипуха", "Умник", "Ночная", "Борода"],
    "cat" => ["Мурчелло", "Лапка", "Наглый", "Соня"],
    "lizard" => ["Шипокожий", "Бес", "Зелёный", "Проныра"],
    "goat" => ["Бодун", "Рогатый", "Козьма", "Пастух"],
    "fox" => ["Хвост", "Рыжик", "Плутовка", "Огнёвка"],
    "raven" => ["Каркун", "Чёрный", "Шептун", "Глаз"],
    "goose" => ["Гусь", "Хонк", "Клюв", "Гром гусиный"],
    "hedgehog" => ["Колючка", "Игла", "Пыхтелка", "Клубок"],
    "moth" => ["Мотыль", "Пылинка", "Ламповый", "Ночной гость"],
    "rock" => ["Камень", "Валун", "Скала", "Тихоня"],
    "turnip" => ["Репка", "Ботва", "Грядка", "Тяпка"],
    "butter" => ["Маслёнок", "Сливочный", "Паз", "Комок"],
    "skeleton" => ["Костяк", "Роберт", "Хрясть", "Гость из склепа"],
    "cheese" => ["Сырок", "Головка", "Плесень", "Дорогой сыр"],
  }

  @species_icons %{
    "wolf" => "🐺", "owl" => "🦉", "cat" => "🐈", "lizard" => "🦎",
    "goat" => "🐐", "fox" => "🦊", "raven" => "🐦‍⬛",
    "goose" => "🪿", "hedgehog" => "🦔", "moth" => "🦋",
    "rock" => "🪨", "turnip" => "🥬", "butter" => "🧈",
    "skeleton" => "💀", "cheese" => "🧀",
  }

  def species_icons, do: @species_icons

  def species_list, do: @species

  @doc "Активный питомец героя (nil, если нет или ждёт возрождения)."
  def active(hero_id) do
    Repo.one(
      from p in Pet,
        where: p.hero_id == ^hero_id and p.status == "active",
        order_by: [desc: p.created_at],
        limit: 1
    )
  end

  def any_pets(hero_id) do
    Repo.all(from p in Pet, where: p.hero_id == ^hero_id, order_by: [desc: p.created_at])
  end

  @doc "История питомцев (P-1): все ушедшие навсегда (gone), новые первыми."
  def history(hero_id) do
    Repo.all(
      from p in Pet,
        where: p.hero_id == ^hero_id and p.status == "gone",
        order_by: [desc: p.created_at]
    )
  end

  # --- Пассивный тик: голод, лояльность, уход, возрождение -------------------

  @doc "Каждый тик героя: голод растёт, лояльность падает при голоде; revive по таймеру. Возвращает {pet | nil, events}."
  def passive_tick(hero, cfg) do
    cfg = cfg["pets"] || %{}
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. Возрождение по таймеру (работает офлайн: сравнение с серверным временем)
    revive_events =
      Repo.all(from p in Pet, where: p.hero_id == ^hero.id and p.status == "cooldown")
      |> Enum.filter(&(revive_at(&1, cfg) <= now))
      |> Enum.map(fn p ->
        p
        |> Pet.changeset(%{status: "active", mood: 40.0, hunger: 40.0, loyalty: 40.0})
        |> Repo.update!()

        %{type: "pet_revived", pet_name: p.name}
      end)

    pet = active(hero.id)

    cond do
      is_nil(pet) ->
        {nil, revive_events}

      true ->
        # Комичные питомцы: камень не голодает, сыр «скисает» быстрее.
        hunger_step = (cfg["hunger_per_tick"] || 0.6) * cheese_hunger_mult(pet)
        hunger = if rock_ignores_needs?(pet), do: pet.hunger, else: min(100.0, pet.hunger + hunger_step)
        loyalty =
          cond do
            rock_ignores_needs?(pet) -> pet.loyalty
            hunger > 80.0 -> max(0.0, pet.loyalty - (cfg["loyalty_decay"] || 0.4))
            true -> pet.loyalty
          end

        cond do
          loyalty <= 0.0 and cfg["loyalty_zero_leave"] != false ->
            pet |> Pet.changeset(%{status: "gone", loyalty: 0.0}) |> Repo.update!()
            {nil, [%{type: "pet_left", pet_name: pet.name} | revive_events]}

          true ->
            pet
            |> Pet.changeset(%{hunger: hunger, loyalty: loyalty})
            |> Repo.update!()

            {Repo.get!(Pet, pet.id), revive_events}
        end
    end
  end

  defp revive_at(%Pet{revive_at: at}, _cfg) when not is_nil(at), do: at
  defp revive_at(_pet, cfg), do: fallback_revive_time(cfg)

  defp fallback_revive_time(_cfg), do: DateTime.utc_now() |> DateTime.truncate(:second)

  # --- Уход -------------------------------------------------------------------

  @doc "Кормление: стоит золота, снижает голод, повышает лояльность."
  def feed(pet, cfg) do
    pet
    |> Pet.changeset(%{
      hunger: max(0.0, pet.hunger - 40.0),
      loyalty: min(100.0, pet.loyalty + (cfg["feed_loyalty"] || 6)),
      mood: min(100.0, pet.mood + 5.0),
    })
    |> Repo.update!()
  end

  @doc "Игра: настроение питомцу и немного хозяину."
  def play(pet, cfg) do
    pet
    |> Pet.changeset(%{
      mood: min(100.0, pet.mood + (cfg["play_mood"] || 12)),
      hunger: min(100.0, pet.hunger + 3.0),
      loyalty: min(100.0, pet.loyalty + 2.0),
    })
    |> Repo.update!()
  end

  @doc "Дрессировка: лояльность +. Навык empathy хозяина ускоряет."
  def train(pet, cfg) do
    pet
    |> Pet.changeset(%{
      loyalty: min(100.0, pet.loyalty + (cfg["train_loyalty"] || 4)),
      mood: max(0.0, pet.mood - 3.0),
    })
    |> Repo.update!()
  end

  # --- Усыновление -------------------------------------------------------------

  @doc "Шанс завести питомца (на социализации). Возвращает pet | nil."
  def maybe_adopt(hero, cfg) do
    cfg = cfg["pets"] || %{}

    if :rand.uniform() < (cfg["adopt_chance"] || 0.08) and is_nil(active(hero.id)) do
      species = Enum.random(@species)
      name = Enum.random(Map.get(@species_names, species, ["Безымянный"]))

      Repo.insert!(%Pet{
        hero_id: hero.id,
        species: species,
        name: name,
        mood: 60.0,
        hunger: 30.0,
        loyalty: 70.0,
        status: "active",
        created_at: DateTime.utc_now() |> DateTime.truncate(:second),
      })
    else
      nil
    end
  end

  # --- Бонусы -------------------------------------------------------------------

  @doc "Гибель питомца в бою: cooldown + revive_at (реальное время)."
  def on_combat_death(pet, cfg) do
    hours = cfg["revive_hours"] || 4
    revive_at = DateTime.utc_now() |> DateTime.add(hours * 3600, :second) |> DateTime.truncate(:second)

    pet
    |> Pet.changeset(%{status: "cooldown", revive_at: revive_at})
    |> Repo.update!()

    revive_at
  end

  @doc "Волк помогает в бою: шанс по лояльности (config wolf_help × loyalty/100)."
  def wolf_fight_help?(pet, cfg) when pet != nil do
    pet.species == "wolf" and pet.status == "active" and
      :rand.uniform() < (cfg["wolf_help"] || 0.3) * (pet.loyalty / 100.0)
  end

  def wolf_fight_help?(_pet, _cfg), do: false

  @doc "Сова помогает находить (discovery шанс)."
  def owl_discovery?(pet, cfg) when pet != nil do
    pet.species == "owl" and pet.status == "active" and
      :rand.uniform() < (cfg["owl_discovery"] || 0.25)
  end

  def owl_discovery?(_pet, _cfg), do: false

  @doc "Кот поднимает настроение хозяину."
  def cat_mood_bonus(pet, cfg) when pet != nil do
    if pet.species == "cat" and pet.status == "active", do: cfg["cat_mood"] || 2, else: 0
  end

  def cat_mood_bonus(_pet, _cfg), do: 0

  # --- Комичные питомцы: маленькие пасхалки (бонус-поведение) ------------------

  @doc "Гусь агрессивен: редкий шанс, что сам вступит в бой вместо героя (как волк, но смешнее)."
  def goose_fight_help?(pet, cfg) when pet != nil do
    pet.species == "goose" and pet.status == "active" and
      :rand.uniform() < (cfg["goose_help"] || 0.15) * (pet.loyalty / 100.0)
  end

  def goose_fight_help?(_pet, _cfg), do: false

  @doc "Камень надёжен: не голодает (голод не растёт) и не уходит — лояльность не падает."
  def rock_ignores_needs?(pet) when pet != nil, do: pet.species == "rock"
  def rock_ignores_needs?(_pet), do: false

  @doc "Сыр притягивает крыс… то есть просто поднимает аппетит: голод растёт чуть быстрее."
  def cheese_hunger_mult(pet) when pet != nil, do: if(pet.species == "cheese", do: 1.5, else: 1.0)
  def cheese_hunger_mult(_pet), do: 1.0
end
