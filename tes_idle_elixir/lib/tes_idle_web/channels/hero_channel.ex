defmodule TesIdleWeb.HeroChannel do
  use Phoenix.Channel

  def join("hero:" <> hero_id, _params, socket) do
    if socket.assigns.user_id do
      send(self(), :after_join)
      {:ok, %{hero_id: hero_id}, assign(socket, :hero_id, hero_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_info(:after_join, socket) do
    Phoenix.PubSub.subscribe(TesIdle.PubSub, "hero:#{socket.assigns.hero_id}")
    {:noreply, socket}
  end

  def handle_info({:hero_tick, result}, socket) do
    # Push combat progress (during multi-round combat)
    if result.combat_progress do
      push(socket, "combat_progress", result.combat_progress)
    end

    # Push combat start
    if result.combat_start do
      push(socket, "combat_start", result.combat_start)
    end

    # Push combat result
    if result.combat_result do
      push(socket, "combat_result", result.combat_result)
    end

    # Push journal entry
    if result.journal_entry do
      entry = result.journal_entry
      push(socket, "journal_entry", %{
        id: to_string(entry.id),
        entry_type: entry.entry_type,
        text: entry.text,
        xp_gained: entry.xp_gained,
        gold_gained: entry.gold_gained,
        location_name: entry.location_name,
        chapter: entry.chapter,
        chapter_title: entry.chapter_title,
        motive: entry.motive,
        created_at: if(entry.created_at, do: NaiveDateTime.to_iso8601(entry.created_at)),
      })
    end

    # S-3: «Новости мира» — отдельная запись в журнале
    if result[:world_news_entry] do
      entry = result.world_news_entry
      push(socket, "journal_entry", %{
        id: to_string(entry.id),
        entry_type: entry.entry_type,
        text: entry.text,
        xp_gained: entry.xp_gained,
        gold_gained: entry.gold_gained,
        location_name: entry.location_name,
        chapter: entry.chapter,
        chapter_title: entry.chapter_title,
        motive: entry.motive,
        created_at: if(entry.created_at, do: NaiveDateTime.to_iso8601(entry.created_at)),
      })
    end

    # P-4: сны при долгом отдыхе — отдельная запись в журнале
    if result[:dream_entry] do
      entry = result.dream_entry
      push(socket, "journal_entry", %{
        id: to_string(entry.id),
        entry_type: entry.entry_type,
        text: entry.text,
        xp_gained: entry.xp_gained,
        gold_gained: entry.gold_gained,
        location_name: entry.location_name,
        chapter: entry.chapter,
        chapter_title: entry.chapter_title,
        motive: entry.motive,
        created_at: if(entry.created_at, do: NaiveDateTime.to_iso8601(entry.created_at)),
      })
    end

    # Push equipment update if changed
    if result.equip_events != [] do
      push(socket, "equipment_update", %{})
    end

    # Push hero delta update (only changed fields)
    if result.hero_delta && map_size(result.hero_delta) > 0 do
      push(socket, "hero_update", result.hero_delta)
    end

    {:noreply, socket}
  end

  def handle_in("heartbeat", _payload, socket) do
    # hero_id is a binary_id (UUID string) — pass as-is; Ecto casts it in queries
    TesIdle.Worker.ActivityFlushWorker.mark_activity(socket.assigns.hero_id)
    {:reply, {:ok, %{status: "ok"}}, socket}
  end
end
