-- Claude Code Usage — desktop widget (the rich detail panel).
--
-- Noctalia bar widgets can't open a popout, so the DMS plugin's detail popout
-- lives here as a desktop tile built from the declarative ui.* vocabulary
-- (cf. timer.luau). It mirrors the service's published "usage" state; the bar
-- widget and this panel show the same data.
--
-- Sections (ported from ClaudeCodeUsageWidget.qml): rate windows, token
-- consumption, daily activity, per-model breakdown, all-time, profile selector.
-- Circular rings become linear ui.progress bars; per-bar hover tooltips are
-- dropped (ui.* has no hover); profile tabs/dropdown become a cycle button.

local accent = desktopWidget.getConfig("accent")
if type(accent) ~= "string" or accent == "" then accent = "primary" end

-- ui.* needs explicit widths (flex children otherwise collapse — progress bars to
-- 0, labels truncate). Size everything off one panel width.
local PANEL_W = 340
local PAD = 14
local CONTENT_W = PANEL_W - PAD * 2 -- inner width of a card

local usage = noctalia.state.get("usage")
local status = noctalia.state.get("status")
local selected = noctalia.state.get("selected_profile") or "all"

-- ── formatters (ported from the QML) ───────────────────────────────────────

local function formatTokens(n)
  n = tonumber(n) or 0
  if n >= 1000000000 then return string.format("%.1fB", n / 1000000000) end
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.1fK", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

local function currencyMode()
  local c = noctalia.getConfig("currency")
  if c == "usd" or c == "eur" then return c end
  return noctalia.tr("currency.auto_default")
end

local function formatCost(usd, rate)
  usd = tonumber(usd) or 0
  rate = tonumber(rate) or 0
  local useEur = currencyMode() == "eur" and rate > 0
  local n = useEur and usd * rate or usd
  local sym = useEur and "" or "$"
  local suffix = useEur and " €" or ""
  if n >= 1000 then return `{sym}{string.format("%.1f", n / 1000)}K{suffix}` end
  if n >= 100 then return `{sym}{math.floor(n + 0.5)}{suffix}` end
  if n >= 10 then return `{sym}{string.format("%.1f", n)}{suffix}` end
  return `{sym}{string.format("%.2f", n)}{suffix}`
end

local function progressColor(pct)
  if pct > 80 then return "error" end
  if pct > 50 then return "warning" end
  return "primary"
end

local function shortModelName(name)
  if type(name) ~= "string" or #name == 0 then return tostring(name) end
  return name:sub(1, 1):upper() .. name:sub(2)
end

-- ── countdown (reset timestamps are ISO-8601 UTC) ──────────────────────────

-- Seconds the local clock is ahead of UTC (DST-aware for the current instant).
local function tzOffset()
  local now = os.time()
  return os.difftime(now, os.time(os.date("!*t", now)))
end

-- Parse an ISO-8601 UTC string to a real epoch, or nil.
local function resetEpoch(iso)
  if type(iso) ~= "string" or iso == "" then return nil end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  local asLocal = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
  })
  if not asLocal then return nil end
  return asLocal + tzOffset()
end

local function formatCountdown(iso)
  local epoch = resetEpoch(iso)
  if not epoch then return nil end
  local secs = epoch - os.time()
  if secs <= 0 then return noctalia.tr("resetting") end
  local d = secs // 86400
  local h = (secs % 86400) // 3600
  local m = (secs % 3600) // 60
  if d > 0 then return `{d}d {h}h {m}m` end
  if h > 0 then return `{h}h {m}m` end
  return `{m}m`
end

-- ── selected-profile projection ────────────────────────────────────────────

local function findProfile(name)
  if type(usage) ~= "table" or type(usage.profile_data) ~= "table" then return nil end
  for _, p in usage.profile_data do
    if type(p) == "table" and p.name == name then return p end
  end
  return nil
end

-- Unify the "all" aggregate (top-level fields) and a single profile object into
-- one shape the renderer can read.
local function projection()
  if type(usage) ~= "table" then return nil end
  if selected == "all" then
    return {
      subscription = usage.subscription_type, tier = usage.rate_limit_tier,
      five_hour_util = usage.five_hour_util, seven_day_util = usage.seven_day_util,
      five_hour_reset = usage.five_hour_reset, seven_day_reset = usage.seven_day_reset,
      week_tokens = usage.week_tokens, month_tokens = usage.month_tokens,
      week_messages = usage.week_messages, week_sessions = usage.week_sessions,
      today_cost = usage.today_cost, week_cost = usage.week_cost, month_cost = usage.month_cost,
      daily = usage.daily, daily_costs = usage.daily_costs, week_models = usage.week_models,
      is_all = true,
    }
  end
  local p = findProfile(selected)
  if not p then return nil end
  return {
    subscription = p.subscription, tier = p.tier,
    five_hour_util = p.five_hour_util, seven_day_util = p.seven_day_util,
    five_hour_reset = p.five_hour_reset, seven_day_reset = p.seven_day_reset,
    week_tokens = p.week_tokens, month_tokens = p.month_tokens,
    week_messages = p.week_messages, week_sessions = p.week_sessions,
    today_cost = p.today_cost, week_cost = p.week_cost, month_cost = p.month_cost,
    daily = p.daily, daily_costs = p.daily_costs, week_models = p.week_models,
    is_all = false,
  }
end

-- ── small ui.* helpers ──────────────────────────────────────────────────────

local function muted(text, size)
  return ui.label({ text = text, fontSize = size or 12, color = "on_surface_variant" })
end

local function card(children)
  return ui.column({
    gap = 8, padding = PAD, fill = "surface_container_high", radius = 12,
    width = PANEL_W,
  }, children)
end

-- Rate window card: title, "NN% used" (threshold color), progress bar, reset countdown.
local function rateCard(title, util, resetIso)
  util = tonumber(util) or 0
  local color = progressColor(util)
  local rows = {
    ui.row({ width = CONTENT_W, justify = "space_between" }, {
      ui.label({ text = title, fontSize = 14, fontWeight = "medium" }),
      ui.label({ text = `{math.floor(util + 0.5)}% {noctalia.tr("used")}`, fontSize = 14, color = color }),
    }),
    ui.progress({ progress = math.min(1, util / 100), fill = color, width = CONTENT_W, height = 8, radius = 4 }),
  }
  local cd = formatCountdown(resetIso)
  if cd then
    table.insert(rows, muted(`{noctalia.tr("resets_in")} {cd}`, 11))
  end
  return card(rows)
end

-- One Today/Week/Month metric column (fixed width so token values don't truncate).
local function metricCol(label, tokens, cost, rate)
  local colW = math.floor((CONTENT_W - 16) / 3) -- two 8px gaps between three columns
  return ui.column({ gap = 2, align = "center", width = colW }, {
    muted(label, 12),
    ui.label({ text = formatTokens(tokens), fontSize = 16, fontWeight = "bold", color = accent }),
    ui.label({ text = formatCost(cost, rate), fontSize = 11, color = "on_surface_variant" }),
  })
end

-- Daily activity: 7 vertical bars + day labels (Mon→Sun), today's bar accented.
local function dailyChart(daily)
  if type(daily) ~= "table" then daily = {} end
  local maxVal = 1
  for _, v in daily do maxVal = math.max(maxVal, tonumber(v) or 0) end

  local labels = {}
  for w in (noctalia.tr("days")):gmatch("[^,]+") do table.insert(labels, w) end

  local t = os.date("*t")
  local todayIdx = (t.wday == 1) and 7 or (t.wday - 1) -- 1-based, Mon=1
  local colW = math.floor((CONTENT_W - 6 * 6) / 7) -- six 6px gaps
  local barH = 64

  local cols = {}
  for i = 1, 7 do
    local v = tonumber(daily[i]) or 0
    local h = (v > 0) and math.max(3, math.floor(v / maxVal * barH)) or 0
    local isToday = (i == todayIdx)
    table.insert(cols, ui.column({ width = colW, gap = 4, align = "center" }, {
      ui.column({ width = colW, height = barH, justify = "end", align = "center" }, {
        ui.box({
          width = math.min(20, colW), height = h, radius = 3,
          fill = isToday and accent or "surface_container_highest",
        }),
      }),
      ui.label({
        text = labels[i] or tostring(i),
        fontSize = 10,
        color = isToday and accent or "on_surface_variant",
      }),
    }))
  end
  return card({
    ui.label({ text = noctalia.tr("daily_activity"), fontSize = 14, fontWeight = "medium" }),
    ui.row({ width = CONTENT_W, gap = 6 }, cols),
  })
end

-- Per-model breakdown: name + tokens over a share bar, sorted desc.
local function modelsCard(weekModels, weekTokens)
  if type(weekModels) ~= "table" then return nil end
  local list = {}
  for name, tok in weekModels do
    table.insert(list, { name = name, tokens = tonumber(tok) or 0 })
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a.tokens > b.tokens end)

  weekTokens = tonumber(weekTokens) or 0
  local rows = { ui.label({ text = noctalia.tr("models_this_week"), fontSize = 14, fontWeight = "medium" }) }
  for _, m in list do
    local share = (weekTokens > 0) and math.min(1, m.tokens / weekTokens) or 0
    table.insert(rows, ui.column({ width = CONTENT_W, gap = 2 }, {
      ui.row({ width = CONTENT_W, justify = "space_between" }, {
        ui.label({ text = shortModelName(m.name), fontSize = 12 }),
        muted(formatTokens(m.tokens), 12),
      }),
      ui.progress({ progress = share, fill = accent, width = CONTENT_W, height = 5, radius = 2 }),
    }))
  end
  return card(rows)
end

-- ── render ──────────────────────────────────────────────────────────────────

local function render()
  if type(status) == "table" and status.available == false then
    desktopWidget.render(card({
      ui.row({ gap = 8, align = "center" }, {
        ui.glyph({ name = "robot-off", size = 20, color = "on_surface_variant" }),
        ui.label({ text = status.message ~= "" and status.message or "Claude Code Usage unavailable" }),
      }),
    }))
    return
  end

  local pd = projection()
  if not pd then
    desktopWidget.render(card({
      ui.row({ gap = 8, align = "center" }, {
        ui.glyph({ name = "robot", size = 20, color = "on_surface_variant" }),
        ui.label({ text = "Claude Code Usage — loading…", color = "on_surface_variant" }),
      }),
    }))
    return
  end

  local rate = usage.usd_eur_rate
  local sub = pd.subscription
  if sub == nil or sub == "" then sub = "unknown" end
  local tier = (pd.tier ~= nil and pd.tier ~= "" and pd.tier ~= "unknown") and ` · {pd.tier}` or ""

  local sections = {
    ui.row({ width = PANEL_W, gap = 10, align = "center", paddingH = 2 }, {
      ui.glyph({ name = "robot", size = 22, color = accent }),
      ui.column({ gap = 0 }, {
        ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold" }),
        muted(`{sub}{tier}`, 11),
      }),
    }),
  }

  -- Profile selector (cycle) — only when there's more than the default profile.
  local profiles = (type(usage) == "table" and type(usage.profiles) == "table") and usage.profiles or {}
  if #profiles > 1 then
    local label = (selected == "all") and noctalia.tr("all") or selected
    table.insert(sections, ui.button({
      text = `{noctalia.tr("profile")}: {label}`,
      variant = "outline",
      width = PANEL_W,
      onClick = "cycleProfile",
    }))
  end

  table.insert(sections, rateCard(noctalia.tr("five_hour"), pd.five_hour_util, pd.five_hour_reset))
  table.insert(sections, rateCard(noctalia.tr("seven_day"), pd.seven_day_util, pd.seven_day_reset))

  -- Token consumption: Today / Week / Month.
  local t = os.date("*t")
  local todayIdx = (t.wday == 1) and 7 or (t.wday - 1)
  local todayTokens = (type(pd.daily) == "table" and pd.daily[todayIdx]) or 0
  table.insert(sections, card({
    ui.label({ text = noctalia.tr("token_consumption"), fontSize = 14, fontWeight = "medium" }),
    ui.row({ width = CONTENT_W, gap = 8, justify = "space_between" }, {
      metricCol(noctalia.tr("today"), todayTokens, pd.today_cost, rate),
      metricCol(noctalia.tr("week"), pd.week_tokens, pd.week_cost, rate),
      metricCol(noctalia.tr("month"), pd.month_tokens, pd.month_cost, rate),
    }),
  }))

  table.insert(sections, dailyChart(pd.daily))

  local models = modelsCard(pd.week_models, pd.week_tokens)
  if models then table.insert(sections, models) end

  -- All-time footer — only for the aggregate view.
  if pd.is_all and type(usage) == "table" then
    local first = usage.first_session
    local parts = {}
    if type(first) == "string" and first ~= "" and first ~= "unknown" then
      table.insert(parts, `{noctalia.tr("since")} {first}`)
    end
    local s = tonumber(usage.alltime_sessions) or 0
    local m = tonumber(usage.alltime_messages) or 0
    if s > 0 then table.insert(parts, `{s} {noctalia.tr("sessions")}`) end
    if m > 0 then table.insert(parts, `{m} {noctalia.tr("msgs")}`) end
    if #parts > 0 then
      table.insert(sections, ui.row({ width = PANEL_W, gap = 6, align = "center", paddingH = 2 }, {
        ui.glyph({ name = "calendar", size = 14, color = "on_surface_variant" }),
        muted(table.concat(parts, " · "), 11),
      }))
    end
  end

  desktopWidget.render(ui.column({ width = PANEL_W, gap = 10 }, sections))
end

-- ── callbacks ────────────────────────────────────────────────────────────────

noctalia.state.watch("usage", function(value)
  usage = value
  render()
end)

noctalia.state.watch("status", function(value)
  status = value
  render()
end)

noctalia.state.watch("selected_profile", function(value)
  selected = value or "all"
  render()
end)

-- Advance through ["all", <profiles…>] and republish so other instances follow.
function cycleProfile()
  local profiles = (type(usage) == "table" and type(usage.profiles) == "table") and usage.profiles or {}
  local order = { "all" }
  for _, name in profiles do table.insert(order, name) end

  local idx = 1
  for i, name in order do
    if name == selected then idx = i break end
  end
  selected = order[(idx % #order) + 1]
  noctalia.state.set("selected_profile", selected)
  render()
end

function update()
  -- Tick on second boundaries so the reset countdowns stay live.
  desktopWidget.setWantsSecondTicks(true)
  render()
end
