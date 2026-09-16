defmodule TesIdle.Game.Guilds do
  @moduledoc """
  G-0: каркас гильдий — создание (сток золота!), вступление (open), выход, список, состав.

  Правила:
  - одна гильдия на игрока (guild_members.user_id unique);
  - создание платит `guild.create_cost` золотом героя — золото уходит из экономики;
  - выход лидера → старший офицер/самый активный; последний участник распускает гильдию;
  - policy != "open" → заявки в G-4 (сейчас честный отказ).
  """

  alias TesIdle.Repo
  alias TesIdle.Game.Guilds.News
  alias TesIdle.Schemas.{Guild, GuildApplication, GuildMember, GuildMessage, GuildOffering, GuildTreasuryLog}
  import Ecto.Query

  @fallback_cfg %{
    "create_cost" => 500,
    "exp_per_gold" => 1,
    "points_per_gold" => 0.1,
    "daily_points_cap" => 150,
    "level_exp_base" => 1000,
    "level_exp_growth" => 1.4,
    "max_level" => 20,
    "buffs_per_level" => %{"xp_mult" => 0.02, "attack_flat" => 1, "hp_flat" => 10},
    "feast_cost" => 300, "feast_hours" => 4, "feast_xp_mult" => 0.05
  }

  @doc "Блок конфига guild из полного configs (жёсткий fallback — тестам не нужен ContextBuilder)."
  def cfg(configs) when is_map(configs) do
    Map.merge(@fallback_cfg, configs["guild"] || %{})
  end

  # ── G-1: Алтарь — подношения, уровни, бафы ──────────────────────────────────

  @doc "Порог exp для перехода с level на level+1 (геометрический рост)."
  def threshold_for(level, cfg) do
    base = Map.get(cfg, "level_exp_base", 1000)
    growth = Map.get(cfg, "level_exp_growth", 1.4)
    round(base * :math.pow(growth, max(level - 1, 0)))
  end

  @doc """
  Баф гильдии уровня level: buffs_per_level × (level − 1) — на 1 уровне бафов нет,
  на 20-м: +38% XP, +19 атаки, +190 HP (скромно, по духу кэпа Brain.Graph).
  """
  def buff_for(level, cfg) when is_integer(level) do
    per = Map.get(cfg, "buffs_per_level", %{})
    steps = max(level - 1, 0)

    %{
      "xp_mult" => Map.get(per, "xp_mult", 0.02) * steps,
      "attack_flat" => Map.get(per, "attack_flat", 1) * steps,
      "hp_flat" => Map.get(per, "hp_flat", 10) * steps,
      "level" => level
    }
  end

  @doc "Баф героя по его user_id (ContextBuilder): nil, если герой не в гильдии. Учитывает активный пир (G-6)."
  def buff_for_user(user_id, configs) do
    from(m in GuildMember,
      join: g in Guild, on: g.id == m.guild_id,
      where: m.user_id == ^user_id,
      select: %{level: g.level, boost_until: g.boost_until}
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      %{level: level, boost_until: boost_until} ->
        cfg = cfg(configs)
        buff = buff_for(level, cfg)

        if feast_active?(boost_until) do
          Map.update!(buff, "xp_mult", &(&1 + Map.get(cfg, "feast_xp_mult", 0.05)))
        else
          buff
        end
    end
  end

  @doc "Пир активен, если boost_until в будущем (naive-время, G-0-конвенция)."
  def feast_active?(nil), do: false

  def feast_active?(boost_until) do
    NaiveDateTime.compare(boost_until, NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)) == :gt
  end

  @doc "Очки, заработанные пользователем с подношений за сегодня (UTC) — дневной кап."
  def points_today(user_id, guild_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    start_of_day = now |> DateTime.add(-now.hour * 3600, :second) |> DateTime.add(-now.minute * 60, :second) |> DateTime.add(-now.second, :second)

    from(o in GuildOffering,
      where: o.user_id == ^user_id and o.guild_id == ^guild_id and o.inserted_at >= ^start_of_day,
      select: coalesce(sum(o.points), 0)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc "Хроника: последние подношения гильдии (имя пользователя, сумма, очки)."
  def offerings_recent(guild_id, limit \\ 10) do
    from(o in GuildOffering,
      where: o.guild_id == ^guild_id and o.kind == "gold",
      join: u in assoc(o, :user),
      order_by: [desc: o.inserted_at],
      limit: ^limit,
      select: %{
        username: u.username,
        amount: o.amount,
        points: o.points,
        inserted_at: o.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Подношение золота на алтарь: золото сгорает (сток), гильдия получает exp,
  жертвователь — очки (с дневным капом) и запись в хронику. Level-up цикл
  пишет системное сообщение в чат гильдии (вести G-5 подхватят позже).
  """
  def offer_gold(user, hero, amount, configs) when is_integer(amount) and amount > 0 do
    guild_cfg = cfg(configs)
    exp_per_gold = Map.get(guild_cfg, "exp_per_gold", 1)
    points_per_gold = Map.get(guild_cfg, "points_per_gold", 0.1)
    daily_cap = Map.get(guild_cfg, "daily_points_cap", 150)
    max_level = Map.get(guild_cfg, "max_level", 20)

    case membership(user.id) do
      {guild, member} ->
        if hero.gold < amount do
          {:error, :not_enough_gold}
        else
          earned = round(amount * points_per_gold)
          today = points_today(user.id, guild.id)
          awarded = max(0, min(earned, daily_cap - today))

          {new_level, new_exp} = level_up_loop(guild.level, guild.exp + amount * exp_per_gold, guild_cfg, max_level)
          leveled? = new_level > guild.level

          multi =
            Ecto.Multi.new()
            |> Ecto.Multi.update(:hero, fn _ -> Ecto.Changeset.change(hero, gold: hero.gold - amount) end)
            |> Ecto.Multi.update(:member, fn _ ->
              Ecto.Changeset.change(member,
                points: member.points + awarded,
                contributed: member.contributed + amount
              )
            end)
            |> Ecto.Multi.update(:guild, fn _ ->
              Ecto.Changeset.change(guild, exp: new_exp, level: new_level)
            end)
            |> Ecto.Multi.insert(:offering, fn _ ->
              %GuildOffering{guild_id: guild.id, user_id: user.id, hero_id: hero.id,
                kind: "gold", amount: amount, points: awarded}
            end)

          multi =
            if leveled? do
              Ecto.Multi.insert(multi, :system_message, fn %{guild: g} ->
                %GuildMessage{guild_id: g.id, user_id: nil,
                  body: "⚔️ Гильдия достигает #{g.level} уровня! Алтарь пылает от щедрости.",
                  kind: "system"}
              end)
            else
              multi
            end

          multi
          |> Repo.transaction()
          |> case do
            {:ok, %{guild: g, member: m}} ->
              # G-5: весть о новом уровне в мировой фид
              if g.level > guild.level do
                News.broadcast("guild_levelup", g.id, %{
                  "guild_name" => g.name,
                  "emblem" => g.emblem,
                  "level" => Integer.to_string(g.level)
                })
              end

              {:ok, %{
                guild: %{id: g.id, level: g.level, exp: g.exp},
                member: %{points: m.points, contributed: m.contributed},
                points_awarded: awarded,
                level_ups: g.level - guild.level
              }}

            {:error, _step, reason, _} ->
              {:error, reason}
          end
        end

      nil ->
        {:error, :not_in_guild}
    end
  end

  def offer_gold(_user, _hero, _amount, _configs), do: {:error, :bad_amount}

  # ── G-6: Казна и пир ─────────────────────────────────────────────────────────

  @doc """
  Вклад героя в казну: золото уходит с героя и замораживается в общем ресурсе
  (не очки, не exp — чистая социальная инвестиция; тратится только на проекты).
  """
  def treasury_deposit(user, hero, guild_id, amount)

  def treasury_deposit(user, hero, guild_id, amount) when is_integer(amount) and amount > 0 do
    membership(user.id)
    |> case do
      {g, _member} when g.id == guild_id ->
        if hero.gold < amount do
          {:error, :not_enough_gold}
        else
          treasury_multi(user, hero, guild_id, amount)
        end

      _ ->
        {:error, :not_in_guild}
    end
  end

  def treasury_deposit(_user, _hero, _guild_id, _amount), do: {:error, :bad_amount}

  defp treasury_multi(user, hero, guild_id, amount) do
    guild = Repo.get!(Guild, guild_id)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:hero, fn _ -> Ecto.Changeset.change(hero, gold: hero.gold - amount) end)
    |> Ecto.Multi.update(:guild, fn _ ->
      Ecto.Changeset.change(guild, treasury: guild.treasury + amount)
    end)
    |> Ecto.Multi.insert(:log, fn %{guild: g} ->
      %GuildTreasuryLog{guild_id: guild_id, user_id: user.id, kind: "deposit",
        amount: amount, balance_after: g.treasury}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{guild: g}} -> {:ok, %{treasury: g.treasury, gold: hero.gold - amount}}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Пир (офицер+): списывает feast_cost из казны, ставит boost_until — вся гильдия
  получает +feast_xp_mult к XP на feast_hours часов. Системное сообщение + весть.
  """
  def feast(user, guild_id, configs) do
    membership(user.id)
    |> case do
      {g, _member} when g.id == guild_id ->
        cfg = cfg(configs)
        cost = Map.get(cfg, "feast_cost", 300)
        hours = Map.get(cfg, "feast_hours", 4)
        xp = Map.get(cfg, "feast_xp_mult", 0.05)

        officer_of(user.id, guild_id)
        |> case do
          nil ->
            {:error, :forbidden}

          _officer ->
            guild = Repo.get!(Guild, guild_id)

            if guild.treasury < cost do
              {:error, :not_enough_treasury}
            else
              until =
                NaiveDateTime.utc_now()
                |> NaiveDateTime.truncate(:second)
                |> NaiveDateTime.add(hours * 3600, :second)

              Ecto.Multi.new()
              |> Ecto.Multi.update(:guild, fn _ ->
                Ecto.Changeset.change(guild, treasury: guild.treasury - cost, boost_until: until)
              end)
              |> Ecto.Multi.insert(:log, fn %{guild: g} ->
                %GuildTreasuryLog{guild_id: guild_id, user_id: user.id, kind: "withdraw",
                  amount: cost, balance_after: g.treasury}
              end)
              |> Ecto.Multi.insert(:system_message, fn _ ->
                %GuildMessage{guild_id: guild_id, user_id: nil,
                  body: "🍻 Пир! До #{NaiveDateTime.to_time(until) |> Time.to_string()} вся гильдия получает +#{trunc(xp * 100)}% к опыту.",
                  kind: "system"}
              end)
              |> Repo.transaction()
              |> case do
                {:ok, %{guild: g}} ->
                  News.broadcast("guild_feast", g.id, %{
                    "guild_name" => g.name,
                    "emblem" => g.emblem,
                    "hours" => Integer.to_string(hours)
                  })

                  {:ok, %{treasury: g.treasury, boost_until: until}}

                {:error, _step, reason, _} ->
                  {:error, reason}
              end
            end
        end
    end
  end

  @doc "Журнал казны (последние N записей)."
  def treasury_log(guild_id, limit \\ 10) do
    from(l in GuildTreasuryLog,
      where: l.guild_id == ^guild_id,
      order_by: [desc: l.created_at],
      limit: ^limit,
      select: %{kind: l.kind, amount: l.amount, balance_after: l.balance_after, created_at: l.created_at}
    )
    |> Repo.all()
  end

  # Хвостовой level-up цикл: exp съедает пороги, пока хватает
  defp level_up_loop(level, exp, cfg, max_level) do
    cond do
      level >= max_level ->
        {level, exp}

      exp >= threshold_for(level, cfg) ->
        level_up_loop(level + 1, exp - threshold_for(level, cfg), cfg, max_level)

      true ->
        {level, exp}
    end
  end

  @doc "Системное сообщение в чат гильдии (G-1: level-up; позже — и другие события)."
  def system_message(guild_id, body) do
    Repo.insert!(%GuildMessage{guild_id: guild_id, user_id: nil, body: body, kind: "system"})
  end

  @doc "Лендинг: список гильдий с числом участников, новые уровни выше."
  def list do
    from(g in Guild,
      select: %{
        id: g.id,
        name: g.name,
        motto: g.motto,
        emblem: g.emblem,
        level: g.level,
        policy: g.policy,
        member_count:
          fragment("SELECT COUNT(*) FROM guild_members gm WHERE gm.guild_id = ?", g.id)
      },
      order_by: [desc: g.level, asc: g.name]
    )
    |> Repo.all()
  end

  @doc "Гильдия и роль пользователя; nil, если не в гильдии."
  def membership(user_id) do
    from(m in GuildMember, where: m.user_id == ^user_id, limit: 1)
    |> Repo.one()
    |> case do
      nil ->
        nil

      member ->
        {Repo.get(Guild, member.guild_id), member}
    end
  end

  @doc "Детали гильдии + состав (роль/вклад/имя пользователя)."
  def show(guild_id) do
    case Repo.get(Guild, guild_id) do
      nil ->
        nil

      guild ->
        members =
          from(m in GuildMember,
            where: m.guild_id == ^guild_id,
            join: u in assoc(m, :user),
            order_by: [desc: m.points, desc: m.contributed],
            select: %{
              user_id: m.user_id,
              username: u.username,
              role: m.role,
              points: m.points,
              contributed: m.contributed,
              joined_at: m.joined_at
            }
          )
          |> Repo.all()

        %{
          guild: guild,
          members: members,
          treasury: guild.treasury,
          treasury_log: treasury_log(guild_id, 10),
          active_feast: feast_active?(guild.boost_until),
          boost_until: guild.boost_until
        }
    end
  end

  @doc "Создание гильдии: сток золота героя + лидер в составе."
  def create(user, hero, attrs, configs) do
    guild_cfg = cfg(configs)
    cost = Map.get(guild_cfg, "create_cost", 500)

    cond do
      membership(user.id) != nil ->
        {:error, :already_in_guild}

      hero.gold < cost ->
        {:error, :not_enough_gold}

      true ->
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:guild, Guild.changeset(%Guild{}, Map.put(attrs, :leader_id, user.id)))
        |> Ecto.Multi.insert(:member, fn %{guild: guild} ->
          GuildMember.changeset(%GuildMember{}, %{
            guild_id: guild.id,
            user_id: user.id,
            role: "leader"
          })
        end)
        |> Ecto.Multi.update(:hero, fn _ ->
          hero
          |> Ecto.Changeset.change(gold: hero.gold - cost)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{guild: guild}} ->
            # G-5: весть об основании — мировой фид
            News.broadcast("guild_founded", guild.id, %{
              "guild_name" => guild.name,
              "emblem" => guild.emblem,
              "leader" => user.username
            })

            {:ok, guild}

          {:error, _step, reason, _} ->
            {:error, reason}
        end
    end
  end

  @doc "Вступление: policy open — сразу; иначе отказ (заявки — G-4)."
  def join(user, guild_id) do
    cond do
      membership(user.id) != nil ->
        {:error, :already_in_guild}

      true ->
        case Repo.get(Guild, guild_id) do
          nil ->
            {:error, :not_found}

          %Guild{policy: "open"} = guild ->
            GuildMember.changeset(%GuildMember{}, %{guild_id: guild.id, user_id: user.id, role: "member"})
            |> Repo.insert()
            |> case do
              {:ok, member} -> {:ok, {guild, member}}
              {:error, reason} -> {:error, reason}
            end

          %Guild{} ->
            {:error, :policy_closed}
        end
    end
  end

  @doc "Выход. Лидер → старший офицер (макс. points/contributed); последний участник распускает гильдию."
  def leave(user, guild_id) do
    case membership(user.id) do
      {guild, member} ->
        if guild.id != guild_id, do: {:error, :not_in_guild}, else: do_leave(guild, member)

      nil ->
        {:error, :not_in_guild}
    end
  end

  defp do_leave(guild, member) do
    member_count =
      Repo.one(from(m in GuildMember, where: m.guild_id == ^guild.id, select: count(m.id)))

    cond do
      member_count <= 1 ->
        # последний участник — гильдия распадается
        Ecto.Multi.new()
        |> Ecto.Multi.delete(:member, member)
        |> Ecto.Multi.delete(:guild, guild)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> {:ok, :disbanded}
          {:error, _step, reason, _} -> {:error, reason}
        end

      member.role == "leader" ->
        successor = successor_member(guild.id)

        Ecto.Multi.new()
        |> Ecto.Multi.update(:successor, fn _ ->
          successor
          |> Ecto.Changeset.change(role: "leader")
        end)
        |> Ecto.Multi.update(:guild, fn _ ->
          guild
          |> Ecto.Changeset.change(leader_id: successor.user_id)
        end)
        |> Ecto.Multi.delete(:member, member)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> {:ok, :leader_left}
          {:error, _step, reason, _} -> {:error, reason}
        end

      true ->
        Repo.delete(member)
        |> case do
          {:ok, _} -> {:ok, :left}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp successor_member(guild_id) do
    from(m in GuildMember,
      where: m.guild_id == ^guild_id and m.role != "leader",
      order_by: [desc: fragment("CASE WHEN ? = 'officer' THEN 1 ELSE 0 END", m.role),
                 desc: m.points, desc: m.contributed],
      limit: 1
    )
    |> Repo.one!()
  end

  # ── G-4: заявки и роли ───────────────────────────────────────────────────────

  @doc "Заявка на вступление (policy=request). Одна pending на юзера."
  def apply_to_join(user, guild_id) do
    cond do
      membership(user.id) != nil ->
        {:error, :already_in_guild}

      true ->
        case Repo.get(Guild, guild_id) do
          nil ->
            {:error, :not_found}

          %Guild{policy: "open"} ->
            {:error, :policy_open}

          %Guild{policy: "invite"} ->
            {:error, :policy_closed}

          %Guild{policy: "request"} = guild ->
            pending? =
              Repo.exists?(
                from(a in GuildApplication,
                  where: a.user_id == ^user.id and a.status == "pending"
                )
              )

            if pending? do
              {:error, :already_applied}
            else
              %GuildApplication{guild_id: guild.id, user_id: user.id}
              |> Ecto.Changeset.change()
              |> Repo.insert()
              |> case do
                {:ok, app} -> {:ok, app}
                {:error, reason} -> {:error, reason}
              end
            end
        end
    end
  end

  @doc "Мои заявки (для лендинга: статус последней)."
  def my_application(user_id) do
    from(a in GuildApplication,
      where: a.user_id == ^user_id and a.status == "pending",
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Officer+: {guild, member} с ролью officer/leader."
  def officer_of(user_id, guild_id) do
    case membership(user_id) do
      {guild, member} ->
        if guild.id == guild_id and member.role in ["leader", "officer"] do
          {guild, member}
        else
          nil
        end

      nil ->
        nil
    end
  end

  @doc "Список pending-заявок гильдии (officer+)."
  def list_applications(user, guild_id) do
    if officer_of(user.id, guild_id) do
      from(a in GuildApplication,
        join: u in assoc(a, :user),
        where: a.guild_id == ^guild_id and a.status == "pending",
        order_by: [asc: a.created_at],
        select: %{id: a.id, user_id: a.user_id, username: u.username, created_at: a.created_at}
      )
      |> Repo.all()
      |> then(&{:ok, &1})
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Одобрить/отклонить заявку (officer+ своей гильдии).
  Approved: юзер ещё без гильдии → member + системное сообщение; прочие его pending отклоняются.
  """
  def decide_application(user, app_id, decision) when decision in ["approved", "rejected"] do
    case Repo.one(from(a in GuildApplication, where: a.id == ^app_id, limit: 1)) do
      nil ->
        {:error, :not_found}

      app ->
        case officer_of(user.id, app.guild_id) do
          nil ->
            {:error, :forbidden}

          {guild, _officer} ->
            Ecto.Changeset.change(app, status: decision)
            |> Repo.update()
            |> case do
              {:ok, _} ->
                if decision == "approved", do: admit_application(guild, app)
                {:ok, decision}

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  defp admit_application(guild, app) do
    import Ecto.Query

    if membership(app.user_id) == nil do
      GuildMember.changeset(%GuildMember{}, %{guild_id: guild.id, user_id: app.user_id, role: "member"})
      |> Repo.insert!()

      joiner = Repo.get!(TesIdle.Schemas.User, app.user_id)
      system_message(guild.id, "⚔️ #{joiner.username} вступает в знамя по заявке!")
    end

    # прочие pending заявки юзера отклоняем (вступил)
    from(a in GuildApplication, where: a.user_id == ^app.user_id and a.status == "pending")
    |> Repo.update_all(set: [status: "rejected"])

    :ok
  end

  @doc "Назначение роли (только лидер): officer|member, максимум 3 офицера. Лидера менять нельзя."
  def set_role(user, guild_id, target_user_id, role) when role in ["officer", "member"] do
    case membership(user.id) do
      {guild, member} ->
        cond do
          guild.id != guild_id ->
            {:error, :not_in_guild}

          member.role != "leader" ->
            {:error, :forbidden}

          target_user_id == user.id ->
            {:error, :cannot_change_leader}

          true ->
            case Repo.one(from(m in GuildMember, where: m.user_id == ^target_user_id and m.guild_id == ^guild.id, limit: 1)) do
              nil ->
                {:error, :not_found}

              target ->
                if target.role == "leader" do
                  {:error, :cannot_change_leader}
                else
                  if role == "officer" and officer_count(guild.id) >= 3 do
                    {:error, :officers_cap}
                  else
                    Ecto.Changeset.change(target, role: role) |> Repo.update()
                  end
                end
            end
        end

      nil ->
        {:error, :not_in_guild}
    end
  end

  def set_role(_user, _guild_id, _target, _role), do: {:error, :bad_role}

  @doc "Кик (officer+): кикаются только member. Системное сообщение."
  def kick(user, guild_id, target_user_id) do
    case officer_of(user.id, guild_id) do
      nil ->
        {:error, :forbidden}

      {guild, _officer} ->
        case Repo.one(from(m in GuildMember, where: m.user_id == ^target_user_id and m.guild_id == ^guild.id, limit: 1)) do
          nil ->
            {:error, :not_found}

          target ->
            if target.role != "member" do
              {:error, :cannot_kick_officer}
            else
              kicked = Repo.get!(TesIdle.Schemas.User, target_user_id)

              Repo.delete(target)
              |> case do
                {:ok, _} ->
                  system_message(guild.id, "🚪 #{kicked.username} кикнут из знамени.")
                  {:ok, :kicked}

                {:error, reason} ->
                  {:error, reason}
              end
            end
        end
    end
  end

  defp officer_count(guild_id) do
    from(m in GuildMember, where: m.guild_id == ^guild_id and m.role == "officer", select: count(m.id))
    |> Repo.one!()
  end
end
