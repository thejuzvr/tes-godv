defmodule TesIdle.Game.Guilds.Shop do
  @moduledoc """
  G-3: лавка гильдии — уникальные предметы за гильдейские очки.

  Каталог — `game_configs["guild_shop"]["catalog"]`: `[%{"name" => ..., "points" => ...}]`
  (fallback-дефолты в ContextBuilder.load_configs). Покупка ищет активный item по имени
  (сид `priv/seed_guild_shop.exs`), списывает очки члена, выдаёт предмет в инвентарь
  (consumable накапливается quantity+1). Журнал — шаблон `guild_shop_purchase` из БД
  (нет шаблона — записи нет, честно). Очки не передаются между игроками.
  """

  import Ecto.Query
  alias Ecto.Multi
  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{GuildMember, InventoryItem, Item}

  @doc "Каталог лавки из конфига (fallback в ContextBuilder)."
  def catalog(configs) do
    configs
    |> Map.get("guild_shop", %{})
    |> Map.get("catalog", [])
  end

  @doc """
  Покупка: очки члена >= цена → списание + предмет в инвентарь.
  Возвращает {:ok, %{item, member, points_left}} | {:error, reason}.
  """
  def buy(user, hero, name, configs) do
    case Guilds.membership(user.id) do
      {_guild, member} ->
        price = find_price(catalog(configs), name)

        cond do
          price == nil ->
            {:error, :unknown_item}

          name == "Искра" ->
            buy_spark(user, hero, price, configs)

          member.points < price ->
            {:error, :not_enough_points}

          true ->
            do_buy(user, hero, name, price)
        end

      nil ->
        {:error, :not_in_guild}
    end
  end

  defp buy_spark(user, hero, price, configs) do
    alias TesIdle.Game.Sparks

    spark_cfg = Sparks.cfg(configs)
    {guild, member} = TesIdle.Game.Guilds.membership(user.id)

    cond do
      guild.level < spark_cfg["guild_min_level"] ->
        {:error, :guild_level}

      not Sparks.allow?(hero, "guild", configs) ->
        {:error, :weekly_cap}

      member.points < price ->
        {:error, :not_enough_points}

      true ->
        member = Repo.one!(from m in GuildMember, where: m.user_id == ^user.id, limit: 1)

        Repo.transaction(fn ->
          updated = member |> Ecto.Changeset.change(points: member.points - price) |> Repo.update!()

          hero
          |> Ecto.Changeset.change(soul_sparks: hero.soul_sparks + 1)
          |> Repo.update!()

          Repo.insert!(%TesIdle.Schemas.JournalEntry{
            hero_id: hero.id,
            entry_type: "spark_guild",
            text: "Искра: guild",
            xp_gained: 0,
            gold_gained: 0
          })

          updated
        end)
        |> case do
          {:ok, updated} -> {:ok, %{item: %{name: "Искра"}, member: updated, points_left: updated.points}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp do_buy(user, hero, name, price) do
    item = Repo.one(from i in Item, where: i.name == ^name and i.is_active == true, limit: 1)

    if item == nil do
      {:error, :unknown_item}
    else
      member = Repo.one!(from m in GuildMember, where: m.user_id == ^user.id, limit: 1)
      existing = Repo.one(from inv in InventoryItem, where: inv.hero_id == ^hero.id and inv.item_id == ^item.id, limit: 1)

      multi =
        Multi.new()
        |> Multi.update(
          :member,
          Ecto.Changeset.change(member, points: member.points - price)
        )
        |> Multi.insert_or_update(:inventory, fn _changes_so_far ->
          if existing do
            Ecto.Changeset.change(existing, quantity: existing.quantity + 1)
          else
            Ecto.Changeset.change(%InventoryItem{hero_id: hero.id, item_id: item.id, quantity: 1})
          end
        end)

      case Repo.transaction(multi) do
        {:ok, %{member: updated}} ->
          journal_purchase(hero, item, updated.points)
          {:ok, %{item: item, member: updated, points_left: updated.points}}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp find_price(catalog, name) do
    case Enum.find(catalog, &(&1["name"] == name)) do
      %{"points" => p} -> p
      _ -> nil
    end
  end

  # Журнал — только из БД: шаблон guild_shop_purchase (нет шаблона — записи нет, честно)
  defp journal_purchase(hero, item, points_left) do
    template =
      Repo.one(
        from t in TesIdle.Schemas.NarrativeTemplate,
          where: t.template_type == "guild_shop_purchase" and t.is_active == true,
          order_by: fragment("random()"),
          limit: 1,
          select: t.text_template
      )

    if template do
      text =
        TesIdle.Game.Narrative.TemplateEngine.render_vars(template, %{
          "hero_name" => hero.name,
          "item" => item.name,
          "points" => Integer.to_string(points_left)
        })

      Repo.insert!(%TesIdle.Schemas.JournalEntry{
        hero_id: hero.id,
        entry_type: "guild_shop_purchase",
        text: text,
        created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
    end

    :ok
  rescue
    _ -> :ok
  end
end
