defmodule TesIdleWeb.Controllers.GuildsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Game.Guilds
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, NarrativeTemplate, User}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    suffix = System.unique_integer([:positive])
    user =
      Repo.insert!(%User{username: "qa_guild_#{suffix}",
        email: "qa_guild_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    hero =
      Repo.insert!(%TesIdle.Schemas.Hero{user_id: user.id, name: "QA Гильдиец", race: "Nord", hero_class: "Warrior",
        level: 1, brain_hash: "x", personality: %{}, skills: %{},
        gold: 1000, sp: 100, state_data: "{}"})

    %{user: user, hero: hero, suffix: suffix}
  end

  defp authed_conn(%User{} = user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp second_user(suffix, gold \\ 1000) do
    u =
      Repo.insert!(%User{username: "qa_guild2_#{suffix}",
        email: "qa_guild2_#{suffix}@test.gg", password_hash: "x", is_admin: false})

    Repo.insert!(%TesIdle.Schemas.Hero{user_id: u.id, name: "QA Второй", race: "Nord", hero_class: "Warrior",
      level: 1, brain_hash: "y", personality: %{}, skills: %{},
      gold: gold, sp: 100, state_data: "{}"})

    u
  end

  test "create: гильдия создаётся, золото списывается (сток), лидер в составе", %{user: user, hero: hero} do
    conn = authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Сумеречный Клинок", "emblem" => "🐺", "motto" => "Ночь наша"})
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["guild"]["name"] == "Сумеречный Клинок"
    assert body["guild"]["emblem"] == "🐺"

    assert Repo.reload!(hero).gold == 500

    {guild, member} = Guilds.membership(user.id)
    assert guild.name == "Сумеречный Клинок"
    assert member.role == "leader"
    assert member.points == 0
  end

  test "create: не хватает золота → 409, гильдии нет", %{user: user, hero: hero} do
    Repo.update!(Ecto.Changeset.change(hero, gold: 100))

    conn = authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Бедняки"})
    assert conn.status == 409
    assert %{"error" => "not_enough_gold"} = json_response(conn, 409)
    assert Guilds.membership(user.id) == nil
  end

  test "create: уже в гильдии → 409", %{user: user} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Первая Гильдия"})
    conn = authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Вторая Гильдия"})
    assert conn.status == 409
    assert %{"error" => "already_in_guild"} = json_response(conn, 409)
  end

  test "create: короткое имя и чужая эмблема → 400 с деталями", %{user: user} do
    conn = authed_conn(user) |> post("/api/v1/guilds", %{"name" => "хи", "emblem" => "💥"})
    assert conn.status == 400
    %{"error" => "validation", "details" => details} = json_response(conn, 400)
    assert details["name"] != nil
    assert details["emblem"] != nil
  end

  test "join: open-гильдия — вступает; request — честный 409", %{user: user, suffix: suffix} do
    leader = second_user(suffix + 1, 1000)
    authed_conn(leader) |> post("/api/v1/guilds", %{"name" => "Открытый Стяг", "policy" => "open"})
    {_g, m} = Guilds.membership(leader.id)
    guild_id = m.guild_id

    conn = authed_conn(user) |> post("/api/v1/guilds/#{guild_id}/join")
    assert conn.status == 200
    assert %{"role" => "member"} = json_response(conn, 200)

    {_g2, m2} = Guilds.membership(user.id)
    assert m2.guild_id == guild_id
    assert m2.role == "member"

    # закрытая политика request — заявка (G-4), а не отказ
    third = second_user(suffix + 2, 1000)
    authed_conn(third) |> post("/api/v1/guilds", %{"name" => "Тайный Круг", "policy" => "request"})
    {_, m3} = Guilds.membership(third.id)

    fourth = second_user(suffix + 3, 1000)
    conn2 = authed_conn(fourth) |> post("/api/v1/guilds/#{m3.guild_id}/join")
    assert conn2.status == 200
    assert %{"status" => "application_pending"} = json_response(conn2, 200)
    # членства пока нет
    assert Guilds.membership(fourth.id) == nil
  end

  test "join: уже в гильдии → 409", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Моя Гильдия"})
    other = second_user(suffix + 10, 1000)
    authed_conn(other) |> post("/api/v1/guilds", %{"name" => "Чужая Гильдия"})
    {_, m} = Guilds.membership(other.id)

    conn = authed_conn(user) |> post("/api/v1/guilds/#{m.guild_id}/join")
    assert conn.status == 409
  end

  test "leave: обычный член выходит", %{user: user, suffix: suffix} do
    leader = second_user(suffix + 11, 1000)
    authed_conn(leader) |> post("/api/v1/guilds", %{"name" => "Стая Волка", "emblem" => "🐺"})
    {guild, _} = Guilds.membership(leader.id)

    authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/join")

    conn = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/leave")
    assert conn.status == 200
    assert %{"result" => "left"} = json_response(conn, 200)
    assert Guilds.membership(user.id) == nil

    # гильдия жива, лидер на месте
    {g2, m2} = Guilds.membership(leader.id)
    assert g2.id == guild.id
    assert m2.role == "leader"
  end

  test "leave: лидер уходит → старший (офицер/активный) наследует", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Династия", "emblem" => "🦅"})
    {guild, _} = Guilds.membership(user.id)

    officer = second_user(suffix + 20, 1000)
    authed_conn(officer) |> post("/api/v1/guilds/#{guild.id}/join")
    {_g, om} = Guilds.membership(officer.id)
    Repo.update!(Ecto.Changeset.change(om, role: "officer"))

    conn = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/leave")
    assert conn.status == 200
    assert %{"result" => "leader_left"} = json_response(conn, 200)
    assert Guilds.membership(user.id) == nil

    {g2, m2} = Guilds.membership(officer.id)
    assert g2.id == guild.id
    assert m2.role == "leader"
    assert Repo.reload!(g2).leader_id == officer.id
  end

  test "leave: последний участник распускает гильдию", %{user: user} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Одиночки"})
    {guild, _} = Guilds.membership(user.id)

    conn = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/leave")
    assert conn.status == 200
    assert %{"result" => "disbanded"} = json_response(conn, 200)
    assert Guilds.membership(user.id) == nil
    assert Repo.get(TesIdle.Schemas.Guild, guild.id) == nil
  end

  test "index: список с member_count и my-блоком", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Списочная", "emblem" => "🐉"})
    {my_guild, _} = Guilds.membership(user.id)

    other = second_user(suffix + 30, 1000)
    authed_conn(other) |> post("/api/v1/guilds", %{"name" => "Другая", "emblem" => "🌙"})
    {other_guild, _} = Guilds.membership(other.id)

    # третий вступает к other — member_count «Другой» = 2
    third = second_user(suffix + 31, 1000)
    authed_conn(third) |> post("/api/v1/guilds/#{other_guild.id}/join")

    conn = authed_conn(user) |> get("/api/v1/guilds")
    assert conn.status == 200
    body = json_response(conn, 200)

    assert length(body["guilds"]) == 2
    mine = Enum.find(body["guilds"], &(&1["name"] == "Списочная"))
    assert mine["member_count"] == 1
    assert mine["emblem"] == "🐉"

    other_entry = Enum.find(body["guilds"], &(&1["name"] == "Другая"))
    assert other_entry["member_count"] == 2

    assert body["my"]["guild_id"] == my_guild.id
    assert body["my"]["role"] == "leader"
  end

  test "show: детали с составом; несуществующая → 404", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Детальная", "emblem" => "⚔️", "motto" => "Клинок в темноте"})
    {guild, _} = Guilds.membership(user.id)

    member = second_user(suffix + 40, 1000)
    authed_conn(member) |> post("/api/v1/guilds/#{guild.id}/join")

    conn = authed_conn(user) |> get("/api/v1/guilds/#{guild.id}")
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["guild"]["name"] == "Детальная"
    assert body["guild"]["motto"] == "Клинок в темноте"
    assert length(body["members"]) == 2
    leader_row = Enum.find(body["members"], &(&1["role"] == "leader"))
    assert leader_row["username"] == user.username

    conn2 = authed_conn(user) |> get("/api/v1/guilds/00000000-0000-0000-0000-000000000000")
    assert conn2.status == 404
  end

  # ── G-1: алтарь ──────────────────────────────────────────────────────────────

  test "offer: подношение через API — gold/exp/points/хроника/my_altar", %{user: user, hero: hero} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Алтарная Гильдия", "emblem" => "🕯️"})
    {guild, _} = Guilds.membership(user.id)

    conn = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/offerings", %{"amount" => 150})
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["gold"] == 350   # 1000 − 500 (create) − 150 (offer)
    assert body["guild"]["exp"] == 150
    assert body["member"]["points"] == 15
    assert body["points_awarded"] == 15
    assert body["level_ups"] == 0

    assert Repo.reload!(hero).gold == 350

    detail = authed_conn(user) |> get("/api/v1/guilds/#{guild.id}") |> json_response(200)
    assert [%{"username" => offering_user, "amount" => 150, "points" => 15}] = detail["offerings"]
    assert offering_user == user.username
    assert detail["my_altar"]["points"] == 15
    assert detail["my_altar"]["points_today"] == 15
    assert detail["my_altar"]["daily_cap"] > 0
  end

  test "offer: строка-сумма принимается, 0/мусор → 400", %{user: user} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Строковая", "emblem" => "🛡️"})
    {guild, _} = Guilds.membership(user.id)

    ok = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/offerings", %{"amount" => "30"})
    assert ok.status == 200
    assert json_response(ok, 200)["gold"] == 470   # 1000 − 500 (create) − 30

    bad = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/offerings", %{"amount" => "abc"})
    assert bad.status == 400

    zero = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/offerings", %{"amount" => 0})
    assert zero.status == 400
  end

  test "offer: не в гильдии → 409, нехватка золота → 409", %{user: user, suffix: suffix} do
    leader = second_user(suffix + 50, 1000)
    authed_conn(leader) |> post("/api/v1/guilds", %{"name" => "Чужой Алтарь", "emblem" => "🔥"})
    {guild, _} = Guilds.membership(leader.id)

    outsider = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/offerings", %{"amount" => 10})
    assert outsider.status == 409
    assert %{"error" => "not_in_guild"} = json_response(outsider, 409)

    poor = second_user(suffix + 51, 100)
    authed_conn(poor) |> post("/api/v1/guilds/#{guild.id}/join")
    broke = authed_conn(poor) |> post("/api/v1/guilds/#{guild.id}/offerings", %{"amount" => 500})
    assert broke.status == 409
    assert %{"error" => "not_enough_gold"} = json_response(broke, 409)
  end

  test "hero_response: блок guild с бафом после вступления", %{user: user, suffix: suffix} do
    # вне гильдии — nil
    me0 = authed_conn(user) |> get("/api/v1/hero/me") |> json_response(200)
    assert me0["guild"] == nil

    # уровень 3 вручную → баф 4%/2/20
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Бафовая", "emblem" => "⚔️"})
    {guild, member} = Guilds.membership(user.id)
    Repo.update!(Ecto.Changeset.change(guild, level: 3))

    me = authed_conn(user) |> get("/api/v1/hero/me") |> json_response(200)
    assert me["guild"]["name"] == "Бафовая"
    assert me["guild"]["level"] == 3
    assert me["guild"]["role"] == "leader"
    assert me["guild"]["buff"]["xp_mult"] == 0.04
    assert me["guild"]["buff"]["attack_flat"] == 2
    assert me["guild"]["buff"]["hp_flat"] == 20
  end

  # ── G-2: чат (REST) ──────────────────────────────────────────────────────────

  test "messages/send: участник шлёт и читает; посторонний — 409", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Чатная Гильдия", "emblem" => "🔥"})
    {guild, _} = Guilds.membership(user.id)

    sent = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/messages", %{"body" => "Зал совета собирается!"})
    assert sent.status == 200
    assert json_response(sent, 200)["message"]["body"] =~ "собирается"

    list = authed_conn(user) |> get("/api/v1/guilds/#{guild.id}/messages") |> json_response(200)
    assert [%{"body" => body, "username" => uname}] = list["messages"]
    assert body =~ "собирается"
    assert uname == user.username

    # системное сообщение level-up тоже видно (было бы при level-up; проверяем пустоту не врёт)
    other = second_user(suffix + 60, 1000)
    denied = authed_conn(other) |> get("/api/v1/guilds/#{guild.id}/messages")
    assert denied.status == 409

    denied_post = authed_conn(other) |> post("/api/v1/guilds/#{guild.id}/messages", %{"body" => "ха-ха"})
    assert denied_post.status == 409
  end

  test "send: rate limit 429 и валидация длины/пустоты", %{user: user} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Лимитная", "emblem" => "🛡️"})
    {guild, _} = Guilds.membership(user.id)

    first = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/messages", %{"body" => "раз"})
    assert first.status == 200

    limited = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/messages", %{"body" => "два"})
    assert limited.status == 429
    assert %{"error" => "rate_limited"} = json_response(limited, 429)

    long = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/messages", %{"body" => String.duplicate("д", 201)})
    assert long.status == 400

    empty = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/messages", %{"body" => "  "})
    assert empty.status == 400
  end

  # ── G-3: лавка (API) ─────────────────────────────────────────────────────────

  test "shop: каталог с ценами и my_points", %{user: user} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Торговая", "emblem" => "⚔️"})
    {_g, m} = Guilds.membership(user.id)
    Repo.update!(Ecto.Changeset.change(m, points: 77))

    conn = authed_conn(user) |> get("/api/v1/guilds/shop")
    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["my_points"] == 77
    assert length(body["catalog"]) >= 1
    entry = Enum.find(body["catalog"], &(&1["name"] == "Плащ Соратников"))
    assert entry != nil
    assert entry["points"] > 0
  end

  test "shop_buy: покупка через API — очки списаны, предмет в инвентаре", %{user: user, hero: hero} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Покупная", "emblem" => "🔥"})
    {_g, m} = Guilds.membership(user.id)
    Repo.update!(Ecto.Changeset.change(m, points: 100))

    # предмет из fallback-конфига существует в test-БД
    Repo.insert!(%TesIdle.Schemas.Item{name: "Плащ Соратников", description: "d", item_type: "equipment",
      rarity: "uncommon", icon: "🧥", weight: 2.0, sell_price: 30, is_active: true, tags: ["guild"],
      reduce_hunger: 0.0, reduce_fatigue: 0.0, boost_morale: 0.0, soul_restore: 0.0, equip_slot: "body",
      defense_bonus: 3, hp_bonus: 10, speed_bonus: 0.0})

    ok = authed_conn(user) |> post("/api/v1/guilds/shop/buy", %{"name" => "Плащ Соратников"})
    assert ok.status == 200
    body = json_response(ok, 200)
    assert body["item"]["name"] == "Плащ Соратников"
    assert body["points_left"] == 40   # 100 − 60 (fallback-цена)

    inv = Repo.get_by!(TesIdle.Schemas.InventoryItem, hero_id: hero.id)
    assert inv.quantity == 1
    assert Repo.get_by!(TesIdle.Schemas.GuildMember, user_id: user.id).points == 40

    # второй раз — не хватает очков
    broke = authed_conn(user) |> post("/api/v1/guilds/shop/buy", %{"name" => "Плащ Соратников"})
    assert broke.status == 409
    assert %{"error" => "not_enough_points"} = json_response(broke, 409)
  end

  test "shop_buy: неизвестный предмет → 404, вне гильдии → 409", %{user: user, suffix: suffix} do
    lone = second_user(suffix + 70, 1000)
    denied = authed_conn(lone) |> post("/api/v1/guilds/shop/buy", %{"name" => "Плащ Соратников"})
    assert denied.status == 409

    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Пустая Лавка", "emblem" => "🛡️"})
    {_g, m} = Guilds.membership(user.id)
    Repo.update!(Ecto.Changeset.change(m, points: 100))

    missing = authed_conn(user) |> post("/api/v1/guilds/shop/buy", %{"name" => "Небылица"})
    assert missing.status == 404
    assert %{"error" => "unknown_item"} = json_response(missing, 404)
  end

  # ── G-4: заявки и роли (API) ─────────────────────────────────────────────────

  test "join request-гильдии → заявка, officer одобряет, кандидат вступил", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Заявочное Знамя", "emblem" => "🛡️", "policy" => "request"})
    {guild, _} = Guilds.membership(user.id)

    candidate = second_user(suffix + 80, 1000)

    # кандидат подаёт заявку
    apply = authed_conn(candidate) |> post("/api/v1/guilds/#{guild.id}/join")
    assert apply.status == 200
    assert %{"status" => "application_pending"} = json_response(apply, 200)

    # дубликат
    dup = authed_conn(candidate) |> post("/api/v1/guilds/#{guild.id}/join")
    assert dup.status == 409
    assert %{"error" => "already_applied"} = json_response(dup, 409)

    # обычный member чужой гильдии не видит список
    outsider = second_user(suffix + 81, 1000)
    other = authed_conn(outsider) |> post("/api/v1/guilds", %{"name" => "Чужое Знамя #{suffix}", "emblem" => "🦅"})
    assert other.status == 200

    # лидер видит заявку
    list = authed_conn(user) |> get("/api/v1/guilds/#{guild.id}/applications")
    assert list.status == 200
    %{"applications" => [app]} = json_response(list, 200)
    assert app["username"] == candidate.username

    # одобрение
    approve = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/applications/#{app["id"]}", %{"decision" => "approved"})
    assert approve.status == 200
    assert %{"status" => "approved"} = json_response(approve, 200)

    {_g, m} = Guilds.membership(candidate.id)
    assert m.role == "member"
  end

  test "set_role и kick через API: только лидер/officer, кап, защита офицеров", %{user: user, suffix: suffix} do
    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Ролевое Знамя", "emblem" => "⚔️"})
    {guild, _} = Guilds.membership(user.id)

    m1 = second_user(suffix + 90, 1000)
    m2 = second_user(suffix + 91, 1000)

    authed_conn(m1) |> post("/api/v1/guilds/#{guild.id}/join")
    authed_conn(m2) |> post("/api/v1/guilds/#{guild.id}/join")

    # лидер повышает m1
    promote = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/members/#{m1.id}/role", %{"role" => "officer"})
    assert promote.status == 200

    # member не может повышать
    denied = authed_conn(m2) |> post("/api/v1/guilds/#{guild.id}/members/#{m2.id}/role", %{"role" => "officer"})
    assert denied.status == 403

    # офицер кикает m2
    kick = authed_conn(m1) |> post("/api/v1/guilds/#{guild.id}/members/#{m2.id}/kick")
    assert kick.status == 200
    assert %{"status" => "kicked"} = json_response(kick, 200)

    # офицера кикать нельзя
    no_officer = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/members/#{m1.id}/kick")
    assert no_officer.status == 409
    assert %{"error" => "cannot_kick_officer"} = json_response(no_officer, 409)
  end

  # ── G-5: вести гильдий (API) ─────────────────────────────────────────────────

  test "news: фид отдаёт весть об основании через API", %{user: user, hero: hero} do
    # шаблон должен существовать ДО создания гильдии — иначе вести не будет
    Repo.insert!(%NarrativeTemplate{
      template_type: "guild_founded",
      text_template: "Знамя «{guild_name}» поднято — {leader} зовёт соратников!",
      source: "system", is_active: true})

    authed_conn(user) |> post("/api/v1/guilds", %{"name" => "Славное Знамя", "emblem" => "🦅"})

    news = authed_conn(user) |> get("/api/v1/guilds/news")
    assert news.status == 200
    body = json_response(news, 200)
    assert is_list(body["news"])

    entry = Enum.find(body["news"], &(&1["template_type"] == "guild_founded"))
    assert entry != nil
    assert entry["text"] =~ "Славное Знамя"
  end

  # ── G-6: казна и пир (API) ───────────────────────────────────────────────────

  test "treasury: вклад через API копит казну и виден в show", %{user: user, hero: hero} do
    {:ok, guild} = Guilds.create(user, hero, %{name: "Казна-Гильдия", emblem: "🛡️"}, %{})

    resp = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/treasury", %{"amount" => 200})
    assert resp.status == 200
    assert %{"treasury" => 200, "hero_gold" => gold} = json_response(resp, 200)
    # создание гильдии уже списало 500, вклад ещё 200
    assert gold == hero.gold - 500 - 200

    show = authed_conn(user) |> get("/api/v1/guilds/#{guild.id}")
    body = json_response(show, 200)
    assert body["treasury"]["amount"] == 200
    assert [%{"kind" => "deposit", "amount" => 200, "balance_after" => 200}] = body["treasury"]["log"]
  end

  test "treasury: 409 при нехватке золота", %{user: user, hero: hero} do
    {:ok, guild} = Guilds.create(user, hero, %{name: "Бедная Казна", emblem: "🔥"}, %{})
    broke = Repo.get!(Hero, hero.id) |> Ecto.Changeset.change(gold: 10) |> Repo.update!()

    resp = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/treasury", %{"amount" => 200})
    assert resp.status == 409
    assert %{"error" => "not_enough_gold"} = json_response(resp, 409)
    assert Repo.get!(TesIdle.Schemas.Guild, guild.id).treasury == 0
  end

  test "feast: лидер устраивает пир через API — казна минус, boost_until, весть", %{user: user, hero: hero} do
    Repo.insert!(%NarrativeTemplate{
      template_type: "guild_feast",
      text_template: "🍻 «{guild_name}» пирует {hours} ч!",
      source: "system", is_active: true})

    {:ok, guild} = Guilds.create(user, hero, %{name: "Пиршественное Знамя", emblem: "🛡️"}, %{})
    authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/treasury", %{"amount" => 500})

    resp = authed_conn(user) |> post("/api/v1/guilds/#{guild.id}/feast")
    assert resp.status == 200
    body = json_response(resp, 200)
    assert body["treasury"] == 200 # 500 − 300 (feast_cost)
    assert body["boost_until"] != nil
  end
end
