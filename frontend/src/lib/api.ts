const API_BASE = "/api/v1"

import type { Pet } from "@/stores/gameStore"

export type DecisionAuditEventType = "intent_selected" | "intent_held" | "intent_switched" | "action_started" | "action_completed" | "action_failed"

export interface DecisionAuditGoal {
  goal: string | null
  selected: number
  held: number
  switched: number
  avg_utility: number
}

export interface DecisionAuditActionOutcome {
  goal: string | null
  action: string | null
  completed: number
  failed: number
}

export interface DecisionAuditHero {
  hero: string
  level: number
  events: number
  selected: number
  held: number
  switched: number
  completed: number
  failed: number
}

export interface DecisionAuditRecentEvent {
  hero: string
  game_day: number | null
  game_hour: number | null
  event_type: DecisionAuditEventType
  goal: string | null
  action: string | null
  utility: number | null
  created_at: string
}

export interface DecisionAuditReport {
  range: { from: string; days: number }
  limit: number
  intent_by_goal: DecisionAuditGoal[]
  action_outcomes: DecisionAuditActionOutcome[]
  heroes: DecisionAuditHero[]
  recent_events: DecisionAuditRecentEvent[]
  total_decisions: number
}

class ApiClient {
  private token: string | null = null

  setToken(token: string) {
    this.token = token
    localStorage.setItem("token", token)
  }

  getToken(): string | null {
    if (!this.token) {
      this.token = localStorage.getItem("token")
    }
    return this.token
  }

  clearToken() {
    this.token = null
    localStorage.removeItem("token")
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const token = this.getToken()
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      ...((options.headers as Record<string, string>) || {}),
    }
    if (token) {
      headers["Authorization"] = `Bearer ${token}`
    }

    const response = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers,
    })

    if (!response.ok) {
      let detail = "Request failed"
      const contentType = response.headers.get("content-type") || ""
      if (contentType.includes("application/json")) {
        const data = await response.json().catch(() => ({}))
        detail = data.detail || detail
      } else {
        // Phoenix renders HTML error pages (e.g. NoRouteError) — surface status instead
        detail = `HTTP ${response.status}: ${response.statusText || "Request failed"}`
      }
      throw new Error(detail)
    }

    return response.json()
  }

  // Auth
  async register(username: string, email: string, password: string) {
    return this.request<any>("/auth/register", {
      method: "POST",
      body: JSON.stringify({ username, email, password }),
    })
  }

  async login(username: string, password: string) {
    const data = await this.request<{ access_token: string }>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    })
    this.setToken(data.access_token)
    return data
  }

  // Hero
  async getHero() {
    return this.request<any>("/hero/me")
  }

  async getHeroEncounters(limit = 20) {
    return this.request<{ encounters: any[]; has_more: boolean }>(`/hero/encounters?limit=${limit}`)
  }

  async getHeroRelationships() {
    return this.request<{ relationships: any[] }>("/hero/relationships")
  }

  async getHeroSocialSettings() {
    return this.request<{ encounter_mode: "disabled" | "live_only" | "async"; reveal_name: "nobody" | "encounter" | "guild" | "public"; daily_cap: number; cooldown_seconds: number; limits: { daily_cap_max: number } }>("/hero/social-settings")
  }

  async updateHeroSocialSettings(body: { encounter_mode?: "disabled" | "live_only" | "async"; reveal_name?: "nobody" | "encounter" | "guild" | "public"; daily_cap?: number }) {
    return this.request<any>("/hero/social-settings", { method: "PATCH", body: JSON.stringify(body) })
  }

  async blockHero(heroId: string) {
    return this.request<any>(`/hero/blocks/${heroId}`, { method: "PUT" })
  }

  async unblockHero(heroId: string) {
    return this.request<any>(`/hero/blocks/${heroId}`, { method: "DELETE" })
  }

  // Текущий пользователь (тихая проверка роли, 200 для всех авторизованных)
  async getMe() {
    return this.request<{ id: string; username: string; email: string; is_admin: boolean }>("/me")
  }

  // Репутация героя по фракциям (LawSystem)
  async getReputations() {
    return this.request<{ reputations: { faction: string; value: number; level: string }[] }>("/hero/reputations")
  }

  // World (W-7)
  async getWorld() {
    return this.request<any>("/world")
  }

  // C-1 «Часовня Девяти»: пожертвовать золото на стройку
  async donateConstruction(amount: number) {
    return this.request<{ construction: any; gold: number }>("/construction/donate", {
      method: "POST",
      body: JSON.stringify({ amount }),
    })
  }

  // C-3 «Врата Обливиона»: взнос в фонд экспедиции
  async donateGates(amount: number) {
    return this.request<{ gates: any; closed: boolean; gold: number }>("/gates/donate", {
      method: "POST",
      body: JSON.stringify({ amount }),
    })
  }

  // Гильдии (G-0): каркас — список/создание/детали/вступление/выход
  async getGuilds() {
    return this.request<{ guilds: any[]; my: { guild_id: string; name: string; emblem: string; role: string; user_id?: string } | null }>("/guilds")
  }

  async createGuild(body: { name: string; motto?: string; emblem?: string; policy?: string }) {
    return this.request<any>("/guilds", { method: "POST", body: JSON.stringify(body) })
  }

  async getGuild(id: string) {
    return this.request<any>(`/guilds/${id}`)
  }

  async joinGuild(id: string) {
    return this.request<any>(`/guilds/${id}/join`, { method: "POST" })
  }

  async leaveGuild(id: string) {
    return this.request<{ result: string }>(`/guilds/${id}/leave`, { method: "POST" })
  }

  // Гильдии (G-1): подношение золота на алтарь
  async offerGold(id: string, amount: number) {
    return this.request<any>(`/guilds/${id}/offerings`, { method: "POST", body: JSON.stringify({ amount }) })
  }

  // Гильдии (G-2): чат — REST-фоллбеки (WS — канал guild:<id>)
  async getGuildMessages(id: string) {
    return this.request<{ messages: any[] }>(`/guilds/${id}/messages`)
  }

  async sendGuildMessage(id: string, body: string) {
    return this.request<{ message: any }>(`/guilds/${id}/messages`, { method: "POST", body: JSON.stringify({ body }) })
  }

  // Гильдии (G-3): лавка — покупка за гильдейские очки
  async getGuildShop() {
    return this.request<{ catalog: any[]; my_points: number | null }>("/guilds/shop")
  }

  async buyGuildItem(name: string) {
    return this.request<{ item: any; points_left: number }>("/guilds/shop/buy", { method: "POST", body: JSON.stringify({ name }) })
  }

  // Гильдии (G-4): заявки и роли
  async getGuildApplications(id: string) {
    return this.request<{ applications: any[] }>(`/guilds/${id}/applications`)
  }

  async decideGuildApplication(id: string, appId: string, decision: "approved" | "rejected") {
    return this.request<{ status: string }>(`/guilds/${id}/applications/${appId}`, { method: "POST", body: JSON.stringify({ decision }) })
  }

  async setGuildRole(id: string, userId: string, role: "officer" | "member") {
    return this.request<{ role: string }>(`/guilds/${id}/members/${userId}/role`, { method: "POST", body: JSON.stringify({ role }) })
  }

  async kickGuildMember(id: string, userId: string) {
    return this.request<{ status: string }>(`/guilds/${id}/members/${userId}/kick`, { method: "POST" })
  }

  // Гильдии (G-5): вести — мировой фид событий
  async getGuildNews() {
    return this.request<{ news: any[] }>("/guilds/news")
  }

  // Гильдии (G-6): казна и пир
  async depositTreasury(id: string, amount: number) {
    return this.request<{ treasury: number; hero_gold: number }>(`/guilds/${id}/treasury`, {
      method: "POST",
      body: JSON.stringify({ amount }),
    })
  }

  async holdFeast(id: string) {
    return this.request<{ treasury: number; boost_until: string }>(`/guilds/${id}/feast`, { method: "POST" })
  }

  async createHero(name: string, race: string, hero_class: string) {
    return this.request<any>("/hero/create", {
      method: "POST",
      body: JSON.stringify({ name, race, hero_class }),
    })
  }

  async heartbeat() {
    return this.request<any>("/hero/heartbeat", { method: "POST" })
  }

  async goOffline() {
    return this.request<any>("/hero/offline", { method: "POST" })
  }

  async getBrain() {
    return this.request<any>("/hero/brain")
  }

  // История питомцев (P-1): все ушедшие навсегда
  async getPetHistory() {
    return this.request<{ pets: (Pet & { created_at: string | null })[] }>("/hero/pets/history")
  }

  // Journal
  async getJournal(limit = 50, offset = 0, entry_type?: string) {
    const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
    if (entry_type) params.set("entry_type", entry_type)
    return this.request<any[]>(`/journal/?${params}`)
  }

  async getJournalCount() {
    return this.request<{ count: number }>("/journal/count")
  }

  // Locations
  async getLocations() {
    return this.request<any[]>("/locations/")
  }

  async travel(locationId: string) {
    return this.request<any>(`/locations/${locationId}/travel`, { method: "POST" })
  }

  // Inventory
  async getInventory() {
    return this.request<any>("/inventory/")
  }

  async getInventoryStatus() {
    return this.request<any>("/inventory/status")
  }

  async useItem(itemId: string) {
    return this.request<any>(`/inventory/use/${itemId}`, { method: "POST" })
  }

  async dropItem(itemId: string, quantity = 1) {
    return this.request<any>(`/inventory/drop/${itemId}?quantity=${quantity}`, { method: "POST" })
  }

  // Equipment
  async getEquipment() {
    return this.request<{ slots: Record<string, any>; hero_gold: number }>("/equipment/")
  }

  async equipItem(itemId: string) {
    return this.request<any>(`/equipment/equip/${itemId}`, { method: "POST" })
  }

  // C-2 Небесная кузня: заточка слота за золото
  async enhanceEquipment(slot: string) {
    return this.request<{ slot: string; item: { name: string }; level: number; price: number; gold_left: number }>(`/equipment/enhance/${slot}`, { method: "POST" })
  }

  async unequipItem(slot: string) {
    return this.request<any>(`/equipment/unequip/${slot}`, { method: "POST" })
  }

  // Quests
  async getActiveQuest() {
    return this.request<any>("/quests/active")
  }

  async generateQuest() {
    return this.request<any>("/quests/generate", { method: "POST" })
  }

  async acceptQuest(questId: string) {
    return this.request<any>(`/quests/${questId}/accept`, { method: "POST" })
  }

  async completeQuest() {
    return this.request<any>("/quests/complete", { method: "POST" })
  }

  // God actions
  async godAction(actionType: string, message?: string) {
    return this.request<any>("/god/action", {
      method: "POST",
      body: JSON.stringify({ action_type: actionType, message }),
    })
  }

  // Pantheon
  async getPantheonKills(limit = 50) {
    return this.request<any[]>(`/pantheon/kills?limit=${limit}`)
  }

  async getPantheonGold(limit = 50) {
    return this.request<any[]>(`/pantheon/gold?limit=${limit}`)
  }

  async getPantheonTime(limit = 50) {
    return this.request<any[]>(`/pantheon/time?limit=${limit}`)
  }

  // Suggestions
  async createSuggestion(type: string, title: string, content: string) {
    return this.request<any>("/suggestions/", {
      method: "POST",
      body: JSON.stringify({ suggestion_type: type, title, content }),
    })
  }

  async getMySuggestions() {
    return this.request<any[]>("/suggestions/")
  }

  // ─── Admin ─────────────────────────────────────────

  async adminStats() {
    return this.request<any>("/admin/stats")
  }

  async adminUsers(page = 1, perPage = 20) {
    return this.request<any>(`/admin/users?page=${page}&per_page=${perPage}`)
  }

  async adminUser(userId: string) {
    return this.request<any>(`/admin/users/${userId}`)
  }

  async adminSetAdmin(userId: string, isAdmin: boolean) {
    return this.request<any>(`/admin/users/${userId}/set-admin?is_admin=${isAdmin}`, { method: "PATCH" })
  }

  async adminHeroes(page = 1, perPage = 20) {
    return this.request<any>(`/admin/heroes?page=${page}&per_page=${perPage}`)
  }

  async adminHero(heroId: string) {
    return this.request<any>(`/admin/heroes/${heroId}`)
  }

  async adminResetHero(heroId: string) {
    return this.request<any>(`/admin/heroes/${heroId}/reset`, { method: "PATCH" })
  }

  async adminAddGold(heroId: string, amount: number) {
    return this.request<any>(`/admin/heroes/${heroId}/add-gold?amount=${amount}`, { method: "POST" })
  }

  async adminAddXp(heroId: string, amount: number) {
    return this.request<any>(`/admin/heroes/${heroId}/add-xp?amount=${amount}`, { method: "POST" })
  }

  async adminDeleteHero(heroId: string) {
    return this.request<any>(`/admin/heroes/${heroId}`, { method: "DELETE" })
  }

  async adminForceTick(heroId: string) {
    return this.request<any>(`/admin/heroes/${heroId}/force-tick`, { method: "POST" })
  }

  async adminTickAll() {
    return this.request<any>("/admin/game/tick-all", { method: "POST" })
  }

  async adminLoops() {
    return this.request<any>("/admin/game/loops")
  }

  async adminRestartLoops() {
    return this.request<any>("/admin/game/restart-loops", { method: "POST" })
  }

  async adminValidateNarrativeBatch(payload: { templates: Array<Record<string, unknown>>; activation_policy?: "pending" | "active_system" }) {
    return this.request<any>("/admin/narrative-batches/validate", { method: "POST", body: JSON.stringify(payload) })
  }

  async adminImportNarrativeBatch(payload: { templates: Array<Record<string, unknown>>; activation_policy?: "pending" | "active_system" }) {
    return this.request<any>("/admin/narrative-batches/import", { method: "POST", body: JSON.stringify(payload) })
  }

  async adminDeletePendingTemplates(scope: { template_type?: string; source?: string; all?: true }) {
    return this.request<{ deleted: number }>("/admin/narrative-templates/delete-pending", {
      method: "POST",
      body: JSON.stringify(scope),
    })
  }

  async adminNarrativeTemplates(page = 1, perPage = 50, type?: string, source?: string, isActive?: boolean, q?: string) {
    const params = new URLSearchParams({ page: String(page), per_page: String(perPage) })
    if (type) params.set("template_type", type)
    if (source) params.set("source", source)
    if (isActive !== undefined) params.set("is_active", String(isActive))
    if (q) params.set("q", q)
    return this.request<any>(`/admin/narrative-templates?${params}`)
  }

  async adminNarrativeStats() {
    return this.request<any>("/admin/narrative-templates/stats")
  }

  async adminBulkTemplates(ids: string[], action: "activate" | "deactivate" | "delete") {
    return this.request<any>("/admin/narrative-templates/bulk", {
      method: "POST",
      body: JSON.stringify({ ids, action }),
    })
  }

  async adminNarrativeUsage(days = 30) {
    return this.request<any>(`/admin/narrative-stats?days=${days}`)
  }

  async adminBrainStats(days = 30, limit = 50) {
    return this.request<DecisionAuditReport>(`/admin/brain/stats?days=${days}&limit=${limit}`)
  }

  // ─── Каталог контента: предметы и монстры ────────────

  async adminContentOptions() {
    return this.request<{
      item_types: string[]
      rarities: string[]
      equip_slots: string[]
      locations: Array<{ id: string; name: string }>
    }>("/admin/content/options")
  }

  async adminItems(page = 1, type?: string, q?: string) {
    const params = new URLSearchParams({ page: String(page) })
    if (type) params.set("type", type)
    if (q) params.set("q", q)
    return this.request<{ items: any[]; total: number; page: number; per_page: number; counts: Record<string, number> }>(
      `/admin/items?${params}`,
    )
  }

  async adminCreateItem(payload: Record<string, unknown>) {
    return this.request<any>("/admin/items", { method: "POST", body: JSON.stringify(payload) })
  }

  async adminUpdateItem(id: string, payload: Record<string, unknown>) {
    return this.request<any>(`/admin/items/${id}`, { method: "PATCH", body: JSON.stringify(payload) })
  }

  async adminDeleteItem(id: string) {
    return this.request<{ status: string; id: string }>(`/admin/items/${id}`, { method: "DELETE" })
  }

  async adminMonsters(page = 1, locationId?: string) {
    const params = new URLSearchParams({ page: String(page) })
    if (locationId) params.set("location_id", locationId)
    return this.request<{ monsters: any[]; total: number; page: number; per_page: number }>(
      `/admin/monsters?${params}`,
    )
  }

  async adminCreateMonster(payload: Record<string, unknown>) {
    return this.request<any>("/admin/monsters", { method: "POST", body: JSON.stringify(payload) })
  }

  async adminUpdateMonster(id: string, payload: Record<string, unknown>) {
    return this.request<any>(`/admin/monsters/${id}`, { method: "PATCH", body: JSON.stringify(payload) })
  }

  async adminDeleteMonster(id: string) {
    return this.request<{ status: string; id: string }>(`/admin/monsters/${id}`, { method: "DELETE" })
  }

  async adminApproveBatch(body: Record<string, string>) {    return this.request<any>("/admin/narrative-templates/approve-batch", {
      method: "POST",
      body: JSON.stringify(body),
    })
  }

  async adminApproveTemplate(id: string) {
    return this.request<any>(`/admin/narrative-templates/${id}/approve`, { method: "PATCH" })
  }

  // P-0: предложения игроков — модерация с превращением в шаблон
  async adminSuggestions(status?: string) {
    const q = status ? `?status=${encodeURIComponent(status)}` : ""
    return this.request<{ total: number; suggestions: any[] }>(`/admin/suggestions${q}`)
  }

  async adminApproveSuggestion(id: string, templateType?: string) {
    return this.request<{ message: string; template_id: string | null; template_type?: string }>(`/admin/suggestions/${id}/approve`, {
      method: "PATCH",
      body: JSON.stringify(templateType ? { template_type: templateType } : {}),
    })
  }

  async adminRejectSuggestion(id: string, comment = "") {
    return this.request<{ message: string }>(`/admin/suggestions/${id}/reject`, {
      method: "PATCH",
      body: JSON.stringify({ admin_comment: comment }),
    })
  }

  async adminUpdateTemplate(
    id: string,
    textTemplate: string,
    templateType: string,
    moodMin?: string,
    moodMax?: string,
  ) {
    const body: Record<string, unknown> = {
      text_template: textTemplate,
      template_type: templateType,
    }
    if (moodMin !== undefined) body.mood_min = moodMin
    if (moodMax !== undefined) body.mood_max = moodMax
    return this.request<any>(`/admin/narrative-templates/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    })
  }

  async adminCreateTemplate(templateType: string, textTemplate: string, moodMin?: string, moodMax?: string) {
    const body: Record<string, unknown> = {
      template_type: templateType,
      text_template: textTemplate,
      source: "manual",
      is_active: true,
    }
    if (moodMin !== undefined && moodMin !== "") body.mood_min = moodMin
    if (moodMax !== undefined && moodMax !== "") body.mood_max = moodMax
    return this.request<any>("/admin/narrative-templates", {
      method: "POST",
      body: JSON.stringify(body),
    })
  }

  async adminRejectTemplate(id: string) {
    return this.request<any>(`/admin/narrative-templates/${id}/reject`, { method: "PATCH" })
  }

  async adminDeleteTemplate(id: string) {
    return this.request<any>(`/admin/narrative-templates/${id}`, { method: "DELETE" })
  }

  async adminGenerateMonsters(count = 5) {
    return this.request<any>(`/admin/simulation/generate-monsters?count=${count}`, { method: "POST" })
  }

  async adminGenerateItems(count = 10) {
    return this.request<any>(`/admin/simulation/generate-items?count=${count}`, { method: "POST" })
  }

  async adminRunTests() {
    return this.request<any>("/admin/tests/run", { method: "POST" })
  }

  async adminLastTests() {
    return this.request<any>("/admin/tests/last")
  }

  async adminConfigs() {
    return this.request<any>("/admin/config")
  }

  async adminUpdateConfig(key: string, value: any, description = "") {
    return this.request<any>(`/admin/config/${key}?description=${encodeURIComponent(description)}`, {
      method: "PUT",
      body: JSON.stringify(value),
    })
  }

  // ─── LLM Auto-Generation ─────────────────────────

  async adminLlmStatus() {
    return this.request<any>("/admin/llm-status")
  }

  async adminLlmToggle(enabled: boolean) {
    return this.request<any>(`/admin/llm-toggle?enabled=${enabled}`, { method: "POST" })
  }

  async adminGenerateAll() {
    return this.request<any>("/admin/simulation/generate-all", { method: "POST" })
  }

  async adminGenerateNarrativesModerated(type: string, location: string, count: number, sentences = 2, tone = "atmospheric") {
    const params = new URLSearchParams({
      template_type: type,
      location_name: location,
      count: String(count),
      sentences: String(sentences),
      tone,
    })
    return this.request<any>(
      `/admin/simulation/generate-narratives-moderated?${params}`,
      { method: "POST" }
    )
  }

  async adminExport() {
    return this.request<any>("/admin/export", { method: "POST" })
  }

  async adminExportFile() {
    return this.request<any>("/admin/export/file", { method: "POST" })
  }

  async adminImport(data: any) {
    return this.request<any>("/admin/import", {
      method: "POST",
      body: JSON.stringify(data),
    })
  }

  async adminImportFile(filename: string) {
    return this.request<any>(`/admin/import/file?filename=${encodeURIComponent(filename)}`, { method: "POST" })
  }

  // ─── Narrative Import ─────────────────────────────

  async adminNarrativesImport(templates: any[]) {
    return this.request<any>("/admin/import", {
      method: "POST",
      body: JSON.stringify({ narrative_templates: templates }),
    })
  }

  // ─── Hero Simulation ───────────────────────────────

  async adminSimulationRun(ticks: number = 300) {
    return this.request<any>(`/admin/simulation/run?ticks=${ticks}`, { method: "POST" })
  }
}

export const api = new ApiClient()
