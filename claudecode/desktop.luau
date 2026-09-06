--!nonstrict
-- Claude Code Usage — desktop widget (the detail panel pinned to the desktop).
--
-- The same content as the click panel (panel.luau), built from the declarative
-- ui.* vocabulary as a desktop tile (cf. timer.luau). It mirrors the service's
-- published "usage" state; the bar widget, the panel and this tile show the same
-- data, and it follows the profile chosen in the panel (shared "selected_profile").
--
-- Sections (ported from ClaudeCodeUsageWidget.qml): rate windows, token
-- consumption, daily activity, per-model breakdown, all-time, profile selector.
-- Circular rings become linear bars with a time-tick; per-bar hover tooltips live
-- in the click panel (desktop widgets have no tooltips); profile tabs/dropdown
-- become a cycle button.

local shared = require("./shared.luau")
local formatTokens, formatCost, shortModelName = shared.formatTokens, shared.formatCost, shared.shortModelName
local formatCountdown, pace = shared.formatCountdown, shared.pace
local FIVE_HOUR_SECS, SEVEN_DAY_SECS = shared.FIVE_HOUR_SECS, shared.SEVEN_DAY_SECS

local accent = noctalia.getConfig("accent")
if type(accent) ~= "string" or accent == "" then accent = "primary" end

-- ui.* needs explicit widths (flex children otherwise collapse — progress bars to
-- 0, labels truncate). Size everything off one panel width.
local PANEL_W = 340
local PAD = 14
local CONTENT_W = PANEL_W - PAD * 2 -- inner width of a card

local usage = noctalia.state.get("usage")
local status = noctalia.state.get("status")
local selected = noctalia.state.get("selected_profile") or "all"

local function paceColor(status)
  return shared.paceColor(status, accent) -- on / under: keep the bar reading as "filled"
end

-- A usage bar with an inlined time-tick. ui.* has no overlay, so we build it from
-- segments: fill / track, with a 2px tick sliver at the time-elapsed position.
local TICK_TRACK = "on_surface/0.14"
local TICK_MARK = "on_surface"
local BAR_H = 8

local function seg(w, color)
  if w <= 0 then return nil end
  return ui.box({ width = w, height = BAR_H, fill = color })
end

local function paceBar(util, timeFrac, fill)
  local W = CONTENT_W
  local u = math.max(0, math.min(1, (tonumber(util) or 0) / 100))
  local uW = math.floor(u * W)
  local parts = {}
  local function add(b) if b then table.insert(parts, b) end end

  if timeFrac == nil then
    add(seg(uW, fill))
    add(seg(W - uW, TICK_TRACK))
  else
    local t = math.max(0, math.min(1, timeFrac))
    local tW = math.floor(t * W)
    local TICK = 2
    if t <= u then
      add(seg(tW, fill))
      add(seg(TICK, TICK_MARK))
      add(seg(uW - tW - TICK, fill))
      add(seg(W - uW, TICK_TRACK))
    else
      add(seg(uW, fill))
      add(seg(tW - uW - TICK, TICK_TRACK))
      add(seg(TICK, TICK_MARK))
      add(seg(W - tW, TICK_TRACK))
    end
  end
  return ui.row({ width = W, height = BAR_H, radius = 4 }, parts)
end

-- ── small ui.* helpers ──────────────────────────────────────────────────────

local function muted(text, size)
  return ui.label({ text = text, fontSize = size or 12, color = "on_surface_variant" })
end

local function card(children)
  return ui.column({
    gap = 8, padding = PAD, fill = "surface_variant/0.45", radius = 12,
    width = PANEL_W,
  }, children)
end

-- Rate window card: title, "NN% used" (pace-colored), usage bar with time-tick,
-- and a pace caption ("X% under/over pace · resets in …").
local function rateCard(title, util, resetIso, durationSecs)
  util = tonumber(util) or 0
  local p = pace(util, resetIso, durationSecs)
  local status = p.status
  local fill = paceColor(status)

  local rows = {
    ui.row({ width = CONTENT_W, justify = "space_between" }, {
      ui.label({ text = title, fontSize = 14, fontWeight = "medium" }),
      ui.label({ text = `{math.floor(util + 0.5)}% {noctalia.tr("used")}`, fontSize = 14, color = fill }),
    }),
    paceBar(util, p.timeFrac, fill),
  }

  local cd = formatCountdown(resetIso)
  local caption = shared.paceLabel(p)
  if cd then
    caption = caption and `{caption} · {noctalia.tr("resets_in")} {cd}` or `{noctalia.tr("resets_in")} {cd}`
  end
  if caption then table.insert(rows, muted(caption, 11)) end
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

  local todayIdx = shared.todayIndex()
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
          fill = isToday and accent or "on_surface/0.14",
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
  local list = shared.modelList(weekModels)
  if #list == 0 then return nil end

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
        ui.label({ text = status.message ~= "" and status.message or noctalia.tr("unavailable") }),
      }),
    }))
    return
  end

  local pd = shared.projection(usage, selected)
  if not pd then
    desktopWidget.render(card({
      ui.row({ gap = 8, align = "center" }, {
        ui.glyph({ name = "robot", size = 20, color = "on_surface_variant" }),
        ui.label({ text = noctalia.tr("loading"), color = "on_surface_variant" }),
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

  table.insert(sections, rateCard(noctalia.tr("five_hour"), pd.five_hour_util, pd.five_hour_reset, FIVE_HOUR_SECS))
  table.insert(sections, rateCard(noctalia.tr("seven_day"), pd.seven_day_util, pd.seven_day_reset, SEVEN_DAY_SECS))

  -- Token consumption: Today / Week / Month.
  local todayTokens = (type(pd.daily) == "table" and pd.daily[shared.todayIndex()]) or 0
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
  local order = shared.profileOrder(usage)

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
