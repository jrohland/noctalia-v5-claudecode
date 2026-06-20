-- Claude Code Usage — bar widget (thin presentation client).
--
-- The fetch logic lives in service.luau; this pill only mirrors the published
-- "usage" / "status" state. It shows the chosen rate-window utilization as
-- "NN%", colored by threshold (cf. the DMS progressColor), with a multi-line
-- summary tooltip standing in for the bar-click popout the runtime doesn't offer.
--
-- Left click forces an immediate refresh (bumps refresh_nonce, watched by the service).

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

-- Pill color: default (neutral, like the other bar widgets) until the window
-- fills up — then warning >50%, error >80%. The DMS pill kept its TEXT neutral
-- and only colored the progress ring; with no ring, the number carries the cue.
local function pillColor(pct)
  if pct > 80 then return "error" end
  if pct > 50 then return "warning" end
  return "on_surface"
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
  local text, util
  if metric == "both" then
    -- 5h · 7d; color follows whichever window is fuller.
    text = `{math.floor(five + 0.5)}% · {math.floor(seven + 0.5)}%`
    util = math.max(five, seven)
  elseif metric == "seven_day" then
    text, util = `{math.floor(seven + 0.5)}%`, seven
  else
    text, util = `{math.floor(five + 0.5)}%`, five
  end
  local color = pillColor(util)

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

  local fivePct = math.floor((tonumber(usage.five_hour_util) or 0) + 0.5)
  local sevenPct = math.floor((tonumber(usage.seven_day_util) or 0) + 0.5)
  barWidget.setTooltip(table.concat({
    sub,
    `5h: {fivePct}%  ·  7d: {sevenPct}%`,
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

function onClick()
  local nonce = noctalia.state.get("refresh_nonce")
  noctalia.state.set("refresh_nonce", (tonumber(nonce) or 0) + 1)
end
