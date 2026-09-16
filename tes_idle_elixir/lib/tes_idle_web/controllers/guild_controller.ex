defmodule TesIdleWeb.GuildController do
  @moduledoc "G-0: REST каркаса гильдий (лендинг/создание/детали/вступление/выход)."

  use TesIdleWeb, :controller

  alias TesIdle.Game.{ContextBuilder, Guilds}
  alias TesIdle.Repo
  alias TesIdle.Schemas.Hero

  import Ecto.Query, only: [from: 2]

  def index(conn, _params) do
    user = conn.assigns.current_user

    my =
      case Guilds.membership(user.id) do
        {guild, member} -> %{guild_id: guild.id, name: guild.name, emblem: guild.emblem, role: member.role, user_id: user.id}
        nil -> nil
      end

    json(conn, %{guilds: Guilds.list(), my: my})
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if hero == nil do
      conn |> put_status(404) |> json(%{error: "hero_not_found"})
    else
      attrs = %{
        name: params["name"],
        motto: params["motto"],
        emblem: params["emblem"] || "🛡️",
        description: params["description"],
        policy: params["policy"] || "open"
      }

      case Guilds.create(user, hero, attrs, ContextBuilder.load_configs()) do
        {:ok, guild} ->
          json(conn, %{guild: %{id: guild.id, name: guild.name, emblem: guild.emblem, motto: guild.motto, policy: guild.policy, level: guild.level}})

        {:error, :already_in_guild} ->
          conn |> put_status(409) |> json(%{error: "already_in_guild"})

        {:error, :not_enough_gold} ->
          conn |> put_status(409) |> json(%{error: "not_enough_gold"})

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> json(%{
            error: "validation",
            details:
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          })
      end
    end
  end

  def show(conn, %{"id" => id}) do
    case Guilds.show(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      %{guild: guild, members: members} ->
        user = conn.assigns.current_user
        guild_cfg = Guilds.cfg(%{})

        # G-1: алтарь — хроника подношений + мои очки/кап
        offerings = Guilds.offerings_recent(guild.id)

        my_altar =
          case Guilds.membership(user.id) do
            {g, m} when g.id == guild.id ->
              cap = Map.get(Guilds.cfg(%{}), "daily_points_cap", 150)
              %{points: m.points, contributed: m.contributed, points_today: Guilds.points_today(user.id, g.id), daily_cap: cap}

            _ ->
              nil
          end

        # G-6: казна + активный пир + мой доступ к пиршеству
        my_feast_access =
          case Guilds.membership(user.id) do
            {g, m} when g.id == guild.id -> m.role in ["leader", "officer"]
            _ -> false
          end

        json(conn, %{
          guild: %{
            id: guild.id,
            name: guild.name,
            motto: guild.motto,
            emblem: guild.emblem,
            description: guild.description,
            level: guild.level,
            exp: guild.exp,
            exp_to_next: Guilds.threshold_for(guild.level, guild_cfg),
            max_level: Map.get(guild_cfg, "max_level", 20),
            policy: guild.policy,
            buff: Guilds.buff_for(guild.level, guild_cfg)
          },
          members: members,
          offerings: offerings,
          my_altar: my_altar,
          treasury: %{
            amount: guild.treasury,
            log: Enum.map(Guilds.treasury_log(guild.id, 10), &%{kind: &1.kind, amount: &1.amount, balance_after: &1.balance_after}),
            feast_cost: Map.get(guild_cfg, "feast_cost", 300),
            feast_active: Guilds.feast_active?(guild.boost_until),
            boost_until: guild.boost_until,
            my_can_feast: my_feast_access
          }
        })
    end
  end

  # G-1: подношение золота на алтарь (сток золота №3)
  def offer(conn, %{"id" => id, "amount" => amount}) do    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    cond do
      hero == nil ->
        conn |> put_status(404) |> json(%{error: "hero_not_found"})

      true ->
        case parse_amount(amount) do
          nil ->
            conn |> put_status(400) |> json(%{error: "bad_amount"})

          amt when amt <= 0 ->
            conn |> put_status(400) |> json(%{error: "bad_amount"})

          amt ->
            # verify: пользователь в ЭТОЙ гильдии
            mine? =
              case Guilds.membership(user.id) do
                {g, _m} -> g.id == id
                _ -> false
              end

            if mine? do
              case Guilds.offer_gold(user, hero, amt, ContextBuilder.load_configs()) do
                {:ok, result} ->
                  json(conn, %{
                    guild: result.guild,
                    member: result.member,
                    points_awarded: result.points_awarded,
                    level_ups: result.level_ups,
                    gold: Repo.reload!(hero).gold
                  })

                {:error, :not_in_guild} ->
                  conn |> put_status(409) |> json(%{error: "not_in_guild"})

                {:error, :not_enough_gold} ->
                  conn |> put_status(409) |> json(%{error: "not_enough_gold"})

                {:error, reason} ->
                  conn |> put_status(400) |> json(%{error: inspect(reason)})
              end
            else
              conn |> put_status(409) |> json(%{error: "not_in_guild"})
            end
        end
    end
  end

  defp parse_amount(a) when is_integer(a), do: a
  defp parse_amount(a) when is_binary(a) do
    case Integer.parse(a) do
      {n, ""} -> n
      _ -> nil
    end
  end
  defp parse_amount(_), do: nil

  # ── G-2: чат — REST-фоллбеки (WS — GuildChannel) ─────────────────────────────

  @doc "Последние 50 сообщений чата (системные+игроковые)."
  def messages(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    if member_of?(user.id, id) do
      import Ecto.Query

      msgs =
        from(m in TesIdle.Schemas.GuildMessage,
          where: m.guild_id == ^id,
          left_join: u in assoc(m, :user),
          order_by: [asc: m.inserted_at],
          limit: 50,
          select: %{
            id: m.id,
            user_id: m.user_id,
            username: coalesce(u.username, "Системное"),
            body: m.body,
            kind: m.kind,
            inserted_at: m.inserted_at
          }
        )
        |> Repo.all()

      json(conn, %{messages: msgs})
    else
      conn |> put_status(409) |> json(%{error: "not_in_guild"})
    end
  end

  @doc "Отправка сообщения (rate limit из конфига, 200 симв) + broadcast в канал."
  def send_message(conn, %{"id" => id, "body" => body}) do
    user = conn.assigns.current_user

    if member_of?(user.id, id) do
      text = (body || "") |> to_string() |> String.trim()
      max_len = Map.get(Guilds.cfg(%{}), "chat_max_len", 200)
      rate = Map.get(Guilds.cfg(%{}), "chat_rate_limit_sec", 2)

      cond do
        text == "" ->
          conn |> put_status(400) |> json(%{error: "empty"})

        String.length(text) > max_len ->
          conn |> put_status(400) |> json(%{error: "too_long"})

        rate_limited?(user.id, rate) ->
          conn |> put_status(429) |> json(%{error: "rate_limited"})

        true ->
          msg =
            Repo.insert!(%TesIdle.Schemas.GuildMessage{
              guild_id: id,
              user_id: user.id,
              body: text,
              kind: "chat"
            })

          payload = %{
            id: msg.id,
            user_id: user.id,
            username: user.username,
            body: msg.body,
            kind: msg.kind,
            inserted_at: msg.inserted_at
          }

          Phoenix.PubSub.broadcast(TesIdle.PubSub, "guild:#{id}", {:chat_message, payload})
          Guilds.Prune.prune(id)
          json(conn, %{message: payload})
      end
    else
      conn |> put_status(409) |> json(%{error: "not_in_guild"})
    end
  end

  defp member_of?(user_id, guild_id) do
    case Guilds.membership(user_id) do
      {g, _m} -> g.id == guild_id
      _ -> false
    end
  end

  defp rate_limited?(user_id, rate_sec) do
    import Ecto.Query

    last =
      from(m in TesIdle.Schemas.GuildMessage,
        where: m.user_id == ^user_id and m.kind == "chat",
        order_by: [desc: m.inserted_at],
        limit: 1,
        select: m.inserted_at
      )
      |> Repo.one()

    case last do
      nil -> false
      dt -> NaiveDateTime.diff(NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second), dt) < rate_sec
    end
  end

  # ── G-6: казна и пир ─────────────────────────────────────────────────────────

  def treasury(conn, %{"id" => id, "amount" => amount}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    cond do
      hero == nil ->
        conn |> put_status(404) |> json(%{error: "hero_not_found"})

      true ->
        case parse_amount(amount) do
          nil ->
            conn |> put_status(400) |> json(%{error: "bad_amount"})

          amt when amt <= 0 ->
            conn |> put_status(400) |> json(%{error: "bad_amount"})

          amt ->
            case Guilds.treasury_deposit(user, hero, id, amt) do
              {:ok, %{treasury: treasury, gold: gold}} ->
                json(conn, %{treasury: treasury, hero_gold: gold})

              {:error, :not_in_guild} ->
                conn |> put_status(409) |> json(%{error: "not_in_guild"})

              {:error, :not_enough_gold} ->
                conn |> put_status(409) |> json(%{error: "not_enough_gold"})

              {:error, _other} ->
                conn |> put_status(409) |> json(%{error: "deposit_failed"})
            end
        end
    end
  end

  def feast(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Guilds.feast(user, id, ContextBuilder.load_configs()) do
      {:ok, %{treasury: treasury, boost_until: until}} ->
        json(conn, %{treasury: treasury, boost_until: until})

      {:error, :not_in_guild} ->
        conn |> put_status(409) |> json(%{error: "not_in_guild"})

      {:error, :forbidden} ->
        conn |> put_status(403) |> json(%{error: "forbidden"})

      {:error, :not_enough_treasury} ->
        conn |> put_status(409) |> json(%{error: "not_enough_treasury"})

      {:error, _other} ->
        conn |> put_status(409) |> json(%{error: "feast_failed"})
    end
  end

  # ── G-5: вести гильдий (мировой фид) ─────────────────────────────────────────

  @doc "Последние вести: основания, уровни, достижения (Wiki «Вести гильдий»)."
  def news(conn, _params) do
    json(conn, %{news: Guilds.News.feed(50)})
  end

  # ── G-3: лавка гильдии (покупка за очки) ─────────────────────────────────────

  @doc "Каталог лавки: предметы + цены в очках + мой баланс."
  def shop(conn, _params) do
    user = conn.assigns.current_user
    configs = ContextBuilder.load_configs()
    catalog = Guilds.Shop.catalog(configs)

    my_points =
      case Guilds.membership(user.id) do
        {_g, m} -> m.points
        nil -> nil
      end

    # существующие имена предметов (dev/test БД могли не иметь сида — честный признак)
    available =
      catalog
      |> Enum.map(fn entry ->
        item =
          Repo.one(
            from i in TesIdle.Schemas.Item,
              where: i.name == ^entry["name"] and i.is_active == true,
              limit: 1
          )

        entry
        |> Map.take(["name", "points"])
        |> Map.put("item", item && item_summary(item))
      end)

    json(conn, %{catalog: available, my_points: my_points})
  end

  @doc "Покупка предмета за гильдейские очки."
  def shop_buy(conn, %{"name" => name}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    configs = ContextBuilder.load_configs()

    cond do
      hero == nil ->
        conn |> put_status(404) |> json(%{error: "hero_not_found"})

      true ->
        case Guilds.Shop.buy(user, hero, name, configs) do
          {:ok, result} ->
            json(conn, %{item: item_summary(result.item), points_left: result.points_left})

          {:error, :not_in_guild} ->
            conn |> put_status(409) |> json(%{error: "not_in_guild"})

          {:error, :not_enough_points} ->
            conn |> put_status(409) |> json(%{error: "not_enough_points"})

          {:error, :unknown_item} ->
            conn |> put_status(404) |> json(%{error: "unknown_item"})

          {:error, reason} ->
            conn |> put_status(400) |> json(%{error: inspect(reason)})
        end
    end
  end

  defp item_summary(item) do
    %{
      id: item.id,
      name: item.name,
      description: item.description,
      item_type: item.item_type,
      rarity: item.rarity,
      icon: item.icon,
      equip_slot: item.equip_slot,
      attack_bonus: item.attack_bonus,
      defense_bonus: item.defense_bonus,
      hp_bonus: item.hp_bonus,
      heal_hp: item.heal_hp,
      heal_sp: item.heal_sp,
      buff_attack: item.buff_attack
    }
  end

  def join(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Guilds.join(user, id) do
      {:ok, {guild, member}} ->
        json(conn, %{guild: %{id: guild.id, name: guild.name, emblem: guild.emblem, level: guild.level}, role: member.role})

      {:error, :policy_closed} ->
        # G-4: policy=request → заявка вместо отказа
        case Guilds.apply_to_join(user, id) do
          {:ok, _app} ->
            json(conn, %{status: "application_pending"})

          {:error, :already_applied} ->
            conn |> put_status(409) |> json(%{error: "already_applied"})

          {:error, :already_in_guild} ->
            conn |> put_status(409) |> json(%{error: "already_in_guild"})

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "not_found"})

          {:error, reason} ->
            conn |> put_status(409) |> json(%{error: to_string(reason)})
        end

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      {:error, :already_in_guild} ->
        conn |> put_status(409) |> json(%{error: "already_in_guild"})
    end
  end

  # ── G-4: заявки (officer+) ───────────────────────────────────────────────────

  @doc "Pending-заявки гильдии (officer+)."
  def applications(conn, %{"id" => id}) do
    case Guilds.list_applications(conn.assigns.current_user, id) do
      {:ok, list} -> json(conn, %{applications: list})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  @doc "Одобрить/отклонить заявку {decision: approved|rejected} (officer+)."
  def decide_application(conn, %{"id" => _guild_id, "app_id" => app_id, "decision" => decision}) do
    case Guilds.decide_application(conn.assigns.current_user, app_id, decision) do
      {:ok, status} -> json(conn, %{status: status})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not_found"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: inspect(reason)})
    end
  end

  # ── G-4: роли и кик ──────────────────────────────────────────────────────────

  @doc "Назначение роли {role: officer|member} — только лидер, максимум 3 офицера."
  def set_role(conn, %{"id" => guild_id, "user_id" => target_user_id, "role" => role}) do
    case Guilds.set_role(conn.assigns.current_user, guild_id, target_user_id, role) do
      {:ok, _updated} -> json(conn, %{role: role})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
      {:error, :officers_cap} -> conn |> put_status(409) |> json(%{error: "officers_cap"})
      {:error, :cannot_change_leader} -> conn |> put_status(409) |> json(%{error: "cannot_change_leader"})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not_found"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: inspect(reason)})
    end
  end

  @doc "Кик member (officer+). Офицеров и лидера кикать нельзя."
  def kick(conn, %{"id" => guild_id, "user_id" => target_user_id}) do
    case Guilds.kick(conn.assigns.current_user, guild_id, target_user_id) do
      {:ok, :kicked} -> json(conn, %{status: "kicked"})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
      {:error, :cannot_kick_officer} -> conn |> put_status(409) |> json(%{error: "cannot_kick_officer"})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not_found"})
      {:error, reason} -> conn |> put_status(400) |> json(%{error: inspect(reason)})
    end
  end

  def leave(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Guilds.leave(user, id) do
      {:ok, result} ->
        json(conn, %{result: Atom.to_string(result)})

      {:error, :not_in_guild} ->
        conn |> put_status(409) |> json(%{error: "not_in_guild"})

      {:error, reason} ->
        conn |> put_status(400) |> json(%{error: inspect(reason)})
    end
  end
end
