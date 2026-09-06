--!nonstrict
-- Claude Code Usage — bar widget (thin presentation client).
--
-- The fetch logic lives in service.luau; this pill only mirrors the published
-- "usage" / "status" state. It shows the chosen rate-window utilization as
-- "NN%", colored by pacing (neutral on/under pace, warning over pace, error over
-- quota) with a "↑" cue when off-track, plus a summary tooltip.
--
-- Left click opens the click panel; right click forces a refresh. Both are also
-- declared as [widget.actions] defaults in plugin.toml (bindings win over these
-- callbacks; the callbacks cover a user who unbinds a gesture).

local shared = require("./shared.luau")
local formatTokens, formatCost = shared.formatTokens, shared.formatCost
local pace, paceLabel, paceColor = shared.pace, shared.paceLabel, shared.paceColor
local round = shared.round

local PANEL_ID = "jrohland/claudecode:popout"

local metric = noctalia.getConfig("pill_metric") or "five_hour"
local showGlyph = noctalia.getConfig("show_glyph")
if showGlyph == nil then showGlyph = true end

local usage = noctalia.state.get("usage")
local status = noctalia.state.get("status")

-- ── render ─────────────────────────────────────────────────────────────────

local function render()
  -- Dependency / load failures: show a muted error glyph.
  if type(status) == "table" and status.available == false then
    barWidget.setGlyph("robot-off")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("")
    barWidget.setTooltip(status.message ~= "" and status.message or noctalia.tr("unavailable"))
    return
  end

  if type(usage) ~= "table" then
    if showGlyph then barWidget.setGlyph("robot") end
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("…")
    barWidget.setColor("on_surface_variant")
    barWidget.setTooltip(noctalia.tr("loading"))
    return
  end

  local five = tonumber(usage.five_hour_util) or 0
  local seven = tonumber(usage.seven_day_util) or 0
  local pFive = pace(five, usage.five_hour_reset, shared.FIVE_HOUR_SECS)
  local pSeven = pace(seven, usage.seven_day_reset, shared.SEVEN_DAY_SECS)

  local text, shown
  if metric == "both" then
    text = `{round(five)}% · {round(seven)}%`
    shown = { pFive, pSeven }
  elseif metric == "seven_day" then
    text, shown = `{round(seven)}%`, { pSeven }
  else
    text, shown = `{round(five)}%`, { pFive }
  end

  -- Color + caret by the worst pace status among the shown window(s).
  local worst = "unknown"
  for _, p in shown do
    if shared.SEVERITY[p.status] > shared.SEVERITY[worst] then worst = p.status end
  end
  local color = paceColor(worst, "on_surface")
  if worst == "over" or worst == "over_quota" then
    text = `{text} ↑`
  end

  if showGlyph then
    barWidget.setGlyph("robot")
    barWidget.setGlyphColor(color)
  end
  barWidget.setText(text)
  barWidget.setColor(color)

  -- Summary tooltip (the panel has the full picture).
  local rate = usage.usd_eur_rate
  local sub = usage.subscription_type
  if sub == nil or sub == "" or sub == "unknown" then sub = "Claude Code" end
  local todayTokens = (type(usage.daily) == "table" and usage.daily[shared.todayIndex()]) or 0

  local function rateLine(label, pct, p)
    local pl = paceLabel(p)
    if pl then return `{label}: {round(pct)}%  ·  {pl}` end
    return `{label}: {round(pct)}%`
  end
  barWidget.setTooltip(table.concat({
    sub,
    rateLine("5h", five, pFive),
    rateLine("7d", seven, pSeven),
    `{noctalia.tr("today")}: {formatTokens(todayTokens)}  ({formatCost(usage.today_cost, rate)})`,
    `{noctalia.tr("week")}: {formatTokens(usage.week_tokens)}  ({formatCost(usage.week_cost, rate)})`,
  }, "\n"))
end

-- ── wiring ─────────────────────────────────────────────────────────────────

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

-- Left click: open / close the attached usage panel.
function onClick()
  noctalia.togglePanel(PANEL_ID)
end

-- Right click: force an immediate refresh (service watches refresh_nonce).
function onRightClick()
  shared.requestRefresh()
end
