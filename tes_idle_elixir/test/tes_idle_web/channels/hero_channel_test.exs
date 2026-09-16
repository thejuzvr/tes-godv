defmodule TesIdleWeb.Channels.HeroChannelTest do
  use TesIdleWeb.ChannelCase, async: false

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, User}
  alias TesIdleWeb.{HeroChannel, UserSocket}

  setup do
    suffix = System.unique_integer([:positive])

    owner =
      Repo.insert!(%User{
        username: "qa_hero_owner_#{suffix}",
        email: "qa_hero_owner_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    outsider =
      Repo.insert!(%User{
        username: "qa_hero_outsider_#{suffix}",
        email: "qa_hero_outsider_#{suffix}@test.gg",
        password_hash: "x",
        is_admin: false
      })

    hero =
      Repo.insert!(%Hero{
        user_id: owner.id,
        name: "QA Канальный #{suffix}",
        race: "Nord",
        hero_class: "Warrior"
      })

    foreign_hero =
      Repo.insert!(%Hero{
        user_id: outsider.id,
        name: "QA Чужой #{suffix}",
        race: "Nord",
        hero_class: "Warrior"
      })

    %{owner: owner, outsider: outsider, hero: hero, foreign_hero: foreign_hero}
  end

  test "join: владелец героя входит в hero:<id>", %{owner: owner, hero: hero} do
    assert {:ok, %{hero_id: hero_id}, socket} =
             UserSocket
             |> socket("user_socket:#{owner.id}", %{user_id: owner.id})
             |> subscribe_and_join(HeroChannel, "hero:#{hero.id}")

    assert hero_id == hero.id
    assert socket.assigns.hero_id == hero.id
  end

  test "join: чужой герой отклоняется", %{outsider: outsider, hero: hero} do
    assert {:error, %{reason: "unauthorized"}} =
             UserSocket
             |> socket("user_socket:#{outsider.id}", %{user_id: outsider.id})
             |> subscribe_and_join(HeroChannel, "hero:#{hero.id}")
  end

  test "join: отсутствующий user_id отклоняется", %{hero: hero} do
    assert {:error, %{reason: "unauthorized"}} =
             UserSocket
             |> socket("user_socket:anon", %{})
             |> subscribe_and_join(HeroChannel, "hero:#{hero.id}")
  end

  test "heartbeat маркирует только героя из авторизованного join", %{
    owner: owner,
    hero: hero,
    foreign_hero: foreign_hero
  } do
    start_supervised!(TesIdle.Worker.ActivityFlushWorker)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_socket:#{owner.id}", %{user_id: owner.id})
      |> subscribe_and_join(HeroChannel, "hero:#{hero.id}")

    :ets.delete(:hero_activity, hero.id)
    :ets.delete(:hero_activity, foreign_hero.id)

    ref = push(socket, "heartbeat", %{"hero_id" => foreign_hero.id})
    assert_reply(ref, :ok, %{status: "ok"})

    assert [{hero_id, %DateTime{}}] = :ets.lookup(:hero_activity, hero.id)
    assert hero_id == hero.id
    assert [] == :ets.lookup(:hero_activity, foreign_hero.id)
  end
end
