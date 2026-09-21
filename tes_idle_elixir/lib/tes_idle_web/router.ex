defmodule TesIdleWeb.Router do
  use TesIdleWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug TesIdleWeb.Plugs.AuthPlug
  end

  pipeline :admin do
    plug TesIdleWeb.Plugs.AuthPlug
    plug TesIdleWeb.Plugs.AdminPlug
  end

  # ─── Public ──────────────────────────────────────────
  scope "/api/v1", TesIdleWeb do
    pipe_through :api

    # Auth
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
  end

  # ─── Authenticated ───────────────────────────────────
  scope "/api/v1", TesIdleWeb do
    pipe_through [:api, :auth]

    # Пользователь (тихая проверка роли/админа без 403-шума)
    get "/me", AuthController, :me

    # Hero
    post "/hero/create", HeroController, :create
    get "/hero/me", HeroController, :me
    get "/hero/reputations", HeroController, :reputations
    get "/hero/pets/history", HeroController, :pets_history
    get "/hero/brain", HeroController, :brain
    post "/hero/heartbeat", HeroController, :heartbeat
    post "/hero/offline", HeroController, :offline
    get "/hero/encounters", HeroSocialController, :encounters
    get "/hero/relationships", HeroSocialController, :relationships
    get "/hero/social-settings", HeroSocialController, :settings
    patch "/hero/social-settings", HeroSocialController, :update_settings
    put "/hero/blocks/:id", HeroSocialController, :block
    delete "/hero/blocks/:id", HeroSocialController, :unblock

    # World (W-7): снапшот мира для мировой плашки + C-1 стройка
    get "/world", WorldController, :show
    post "/construction/donate", WorldController, :donate
    post "/gates/donate", WorldController, :gate_donate

    # Гильдии (G-0): каркас — лендинг/создание/детали/вступление/выход; G-1: алтарь; G-3: лавка
    get "/guilds", GuildController, :index
    post "/guilds", GuildController, :create
    get "/guilds/shop", GuildController, :shop
    post "/guilds/shop/buy", GuildController, :shop_buy
    get "/guilds/news", GuildController, :news
    post "/guilds/:id/treasury", GuildController, :treasury
    post "/guilds/:id/feast", GuildController, :feast
    get "/guilds/:id", GuildController, :show
    post "/guilds/:id/join", GuildController, :join
    post "/guilds/:id/leave", GuildController, :leave
    post "/guilds/:id/offerings", GuildController, :offer
    get "/guilds/:id/messages", GuildController, :messages
    post "/guilds/:id/messages", GuildController, :send_message
    get "/guilds/:id/applications", GuildController, :applications
    post "/guilds/:id/applications/:app_id", GuildController, :decide_application
    post "/guilds/:id/members/:user_id/role", GuildController, :set_role
    post "/guilds/:id/members/:user_id/kick", GuildController, :kick

    # Inventory
    get "/inventory", InventoryController, :index
    get "/inventory/status", InventoryController, :status
    post "/inventory/use/:id", InventoryController, :use_item
    post "/inventory/drop/:id", InventoryController, :drop_item

    # Equipment
    get "/equipment", EquipmentController, :index
    post "/equipment/equip/:id", EquipmentController, :equip
    post "/equipment/unequip/:slot", EquipmentController, :unequip
    post "/equipment/enhance/:slot", EquipmentController, :enhance

    # Journal
    get "/journal", JournalController, :index
    get "/journal/count", JournalController, :count

    # Locations
    get "/locations", LocationController, :index
    post "/locations/:id/travel", LocationController, :travel

    # God
    post "/god/action", GodController, :handle_action

    # Quests
    get "/quests/active", QuestController, :active
    post "/quests/generate", QuestController, :generate
    post "/quests/:id/accept", QuestController, :accept
    post "/quests/complete", QuestController, :complete

    # Pantheon
    get "/pantheon/kills", PantheonController, :kills
    get "/pantheon/gold", PantheonController, :gold
    get "/pantheon/time", PantheonController, :time

    # Suggestions
    post "/suggestions", SuggestionController, :create
    get "/suggestions", SuggestionController, :index
  end

  # ─── Admin ───────────────────────────────────────────
  scope "/api/v1/admin", TesIdleWeb.Admin do
    pipe_through [:api, :admin]

    get "/stats", StatsController, :index

    get "/users", UserController, :index
    get "/users/:id", UserController, :show
    patch "/users/:id/set-admin", UserController, :set_admin

    get "/heroes", HeroController, :index
    get "/heroes/:id", HeroController, :show
    patch "/heroes/:id/reset", HeroController, :reset
    delete "/heroes/:id", HeroController, :delete
    post "/heroes/:id/add-gold", HeroController, :add_gold
    post "/heroes/:id/add-xp", HeroController, :add_xp
    post "/heroes/:id/force-tick", HeroController, :force_tick

    get "/game/loops", GameController, :loops
    post "/game/restart-loops", GameController, :restart_loops
    post "/game/tick-all", GameController, :tick_all

    get "/narrative-templates", NarrativeController, :index
    get "/narrative-templates/stats", NarrativeController, :stats
    get "/narrative-stats", NarrativeController, :usage
    post "/narrative-batches/validate", NarrativeBatchController, :validate
    post "/narrative-batches/import", NarrativeBatchController, :import
    post "/narrative-templates/bulk", NarrativeController, :bulk
    post "/narrative-templates/delete-pending", NarrativeController, :delete_pending
    post "/narrative-templates", NarrativeController, :create
    patch "/narrative-templates/:id", NarrativeController, :update
    patch "/narrative-templates/:id/approve", NarrativeController, :approve
    patch "/narrative-templates/:id/reject", NarrativeController, :reject
    delete "/narrative-templates/:id", NarrativeController, :delete

    get "/config", ConfigController, :index
    put "/config/:key", ConfigController, :update

    get "/llm-status", LlmController, :status
    post "/llm-toggle", LlmController, :toggle
    post "/llm-generate", LlmController, :generate
    post "/llm-generate-batch", LlmController, :generate_batch
    post "/narrative-templates/approve-batch", NarrativeController, :approve_batch

    post "/simulation/run", SimulationController, :run
    post "/simulation/generate-monsters", SimulationController, :generate_monsters
    post "/simulation/generate-items", SimulationController, :generate_items
    post "/simulation/generate-all", SimulationController, :generate_all

    post "/simulation/generate-narratives-moderated",
         SimulationController,
         :generate_narratives_moderated

    # Ручное управление каталогом контента (предметы/монстры)
    get "/content/options", ContentController, :options

    get "/items", ContentController, :items_index
    get "/items/:id", ContentController, :item_show
    post "/items", ContentController, :item_create
    patch "/items/:id", ContentController, :item_update
    delete "/items/:id", ContentController, :item_delete

    get "/monsters", ContentController, :monsters_index
    post "/monsters", ContentController, :monster_create
    patch "/monsters/:id", ContentController, :monster_update
    delete "/monsters/:id", ContentController, :monster_delete

    get "/tests/last", TestController, :last
    post "/tests/run", TestController, :run

    post "/export", ExportController, :export
    post "/export/file", ExportController, :export_file
    post "/import", ImportController, :import

    # Suggestions
    get "/suggestions", SuggestionController, :index
    patch "/suggestions/:id/approve", SuggestionController, :approve
    patch "/suggestions/:id/reject", SuggestionController, :reject

    # World Kernel (W-6)
    get "/world", WorldController, :show
    post "/world/tick", WorldController, :tick
    post "/world/events", WorldController, :force_event
    post "/world/gates/open", WorldController, :open_gates

    # S-5: телеметрия решений (Utility AI)
    get "/brain/stats", BrainStatsController, :show
  end
end
