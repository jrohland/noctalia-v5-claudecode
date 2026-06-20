-- Claude Code Usage — bar widget (thin presentation client).
--
-- The fetch logic lives in service.luau; this pill only mirrors the published
-- "usage" / "status" state. It shows the chosen rate-window utilization as
-- "NN%", colored by pacing (neutral on/under pace, warning over pace, error over
-- quota) with a "↑" cue when off-track, plus a summary tooltip.
--
-- Left click opens the launcher breakdown; right click forces a refresh.

local metric = barWidget.getConfig("pill_metric") or "five_hour"
local showGlyph = barWidget.getConfig("show_glyph")
if showGlyph == nil then showGlyph = true end

local usage = noctalia.state.get("usage")
local status = noctalia.state.get("status")

-- ── formatters (ported from ClaudeCodeUsageWidget.qml) ─────────────────────

local function formatTokens(n)
  n = tonumber(n) or 0
  if n >= 1000000000 then return string.format("%.1fB", n / 1000000000) end
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.1fK", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

-- "auto" currency follows the active UI language via a translation-resolved hint.
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

-- ── pacing (usage vs. time elapsed through the window) ─────────────────────
-- Pill stays neutral (like the other bar widgets) while you're on/under pace,
-- turns warning when over pace (burning faster than the clock), and error when
-- over quota. Windows treated as fixed-length; elapsed time derived from reset.
local FIVE_HOUR_SECS = 5 * 3600
local SEVEN_DAY_SECS = 7 * 86400
local PACE_MARGIN = 5

local function tzOffset()
  local now = os.time()
  return os.difftime(now, os.time(os.date("!*t", now)))
end

local function resetEpoch(iso)
  if type(iso) ~= "string" or iso == "" then return nil end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  local e = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
  })
  if not e then return nil end
  return e + tzOffset()
end

-- → { delta, status } ; status: over_quota | over | under | on | unknown
local function pace(util, resetIso, durationSecs)
  util = tonumber(util) or 0
  local epoch = resetEpoch(resetIso)
  if not epoch then
    if util >= 100 then return { delta = util, status = "over_quota" } end
    return { status = "unknown" }
  end
  local remaining = epoch - os.time()
  local timeFrac = (durationSecs - remaining) / durationSecs
  if timeFrac < 0 then timeFrac = 0 elseif timeFrac > 1 then timeFrac = 1 end
  local delta = util - timeFrac * 100
  if util >= 100 then return { delta = delta, status = "over_quota" } end
  if delta >= PACE_MARGIN then return { delta = delta, status = "over" } end
  if delta <= -PACE_MARGIN then return { delta = delta, status = "under" } end
  return { delta = delta, status = "on" }
end

local SEVERITY = { unknown = 0, under = 0, on = 0, over = 1, over_quota = 2 }

local function pillPaceColor(status)
  if status == "over_quota" then return "error" end
  if status == "over" then return "warning" end
  return "on_surface"
end

-- Human pace phrase for the tooltip, or nil when unknown.
local function paceLabel(p)
  if p.status == "over_quota" then return noctalia.tr("pace.over_quota") end
  if p.status == "over" then return `{math.floor(p.delta + 0.5)}% {noctalia.tr("pace.over")}` end
  if p.status == "under" then return `{math.floor(-p.delta + 0.5)}% {noctalia.tr("pace.under")}` end
  if p.status == "on" then return noctalia.tr("pace.on") end
  return nil
end

-- ── render ─────────────────────────────────────────────────────────────────

local function render()
  -- Dependency / load failures: show a muted error glyph.
  if type(status) == "table" and status.available == false then
    barWidget.setGlyph("robot-off")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("")
    barWidget.setTooltip(status.message ~= "" and status.message or "Claude Code Usage unavailable")
    return
  end

  if type(usage) ~= "table" then
    if showGlyph then barWidget.setGlyph("robot") else barWidget.clearTooltip() end
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("…")
    barWidget.setColor("on_surface_variant")
    barWidget.setTooltip("Claude Code Usage — loading…")
    return
  end

  local five = tonumber(usage.five_hour_util) or 0
  local seven = tonumber(usage.seven_day_util) or 0
  local pFive = pace(five, usage.five_hour_reset, FIVE_HOUR_SECS)
  local pSeven = pace(seven, usage.seven_day_reset, SEVEN_DAY_SECS)

  local text, shown
  if metric == "both" then
    text = `{math.floor(five + 0.5)}% · {math.floor(seven + 0.5)}%`
    shown = { pFive, pSeven }
  elseif metric == "seven_day" then
    text, shown = `{math.floor(seven + 0.5)}%`, { pSeven }
  else
    text, shown = `{math.floor(five + 0.5)}%`, { pFive }
  end

  -- Color + caret by the worst pace status among the shown window(s).
  local worst = "unknown"
  for _, p in shown do
    if SEVERITY[p.status] > SEVERITY[worst] then worst = p.status end
  end
  local color = pillPaceColor(worst)
  if worst == "over" or worst == "over_quota" then
    text = `{text} ↑`
  end

  if showGlyph then
    barWidget.setGlyph("robot")
    barWidget.setGlyphColor(color)
  end
  barWidget.setText(text)
  barWidget.setColor(color)

  -- Summary tooltip — the lightweight stand-in for the lost popout.
  local rate = usage.usd_eur_rate
  local sub = usage.subscription_type
  if sub == nil or sub == "" or sub == "unknown" then sub = "Claude Code" end

  -- Today's tokens come from the daily array at today's index (Mon=1 in Lua's 1-based array).
  local t = os.date("*t")
  local todayIdx = (t.wday == 1) and 7 or (t.wday - 1)
  local todayTokens = (type(usage.daily) == "table" and usage.daily[todayIdx]) or 0

  local function rateLine(label, pct, p)
    local pl = paceLabel(p)
    if pl then return `{label}: {math.floor(pct + 0.5)}%  ·  {pl}` end
    return `{label}: {math.floor(pct + 0.5)}%`
  end
  barWidget.setTooltip(table.concat({
    sub,
    rateLine("5h", five, pFive),
    rateLine("7d", seven, pSeven),
    `Today: {formatTokens(todayTokens)}  ({formatCost(usage.today_cost, rate)})`,
    `Week:  {formatTokens(usage.week_tokens)}  ({formatCost(usage.week_cost, rate)})`,
  }, "\n"))
end

noctalia.state.watch("usage", function(value)
  usage = value
  render()
end)

noctalia.state.watch("status", function(value)
  status = value
  render()
end)

function update()
  noctalia.setUpdateInterval(5000)
  render()
end

-- Left click: open the usage breakdown in the launcher overlay (appears over the
-- current workspace — the closest thing to a click-flyout the plugin API allows).
function onClick()
  noctalia.runAsync([[noctalia msg panel-open launcher "/cc "]])
end

-- Right click: force an immediate refresh (service watches refresh_nonce).
function onRightClick()
  local nonce = noctalia.state.get("refresh_nonce")
  noctalia.state.set("refresh_nonce", (tonumber(nonce) or 0) + 1)
end
