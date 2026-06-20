-- Claude Code Usage — launcher provider.
--
-- The launcher is the one rich overlay a plugin can own that appears OVER the
-- current workspace (not on the desktop) — ideal on a tiling WM. Typing the
-- prefix, or clicking the bar pill (which runs `panel-open launcher "<prefix> "`),
-- opens a centered breakdown of the current usage. Reads the same "usage" state
-- the service publishes.
--
-- Usage: type `/cc` in the launcher, or left-click the bar widget.

-- ── formatters (shared shape with widget/desktop; VMs are isolated) ─────────

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

local function shortModelName(name)
  if type(name) ~= "string" or #name == 0 then return tostring(name) end
  return name:sub(1, 1):upper() .. name:sub(2)
end

local function tzOffset()
  local now = os.time()
  return os.difftime(now, os.time(os.date("!*t", now)))
end

local function formatCountdown(iso)
  if type(iso) ~= "string" or iso == "" then return nil end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  local epoch = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
  })
  if not epoch then return nil end
  local secs = (epoch + tzOffset()) - os.time()
  if secs <= 0 then return noctalia.tr("resetting") end
  local dd = secs // 86400
  local hh = (secs % 86400) // 3600
  local mm = (secs % 3600) // 60
  if dd > 0 then return `{dd}d {hh}h {mm}m` end
  if hh > 0 then return `{hh}h {mm}m` end
  return `{mm}m`
end

-- ── pacing (usage vs. time elapsed through the window) ─────────────────────

local FIVE_HOUR_SECS = 5 * 3600
local SEVEN_DAY_SECS = 7 * 86400
local PACE_MARGIN = 5

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

local function paceLabel(p)
  if p.status == "over_quota" then return noctalia.tr("pace.over_quota") end
  if p.status == "over" then return `{math.floor(p.delta + 0.5)}% {noctalia.tr("pace.over")}` end
  if p.status == "under" then return `{math.floor(-p.delta + 0.5)}% {noctalia.tr("pace.under")}` end
  if p.status == "on" then return noctalia.tr("pace.on") end
  return nil
end

local function paceGlyph(status, default)
  if status == "over_quota" then return "alert-octagon" end
  if status == "over" then return "alert-triangle" end
  return default
end

-- ── result rows ─────────────────────────────────────────────────────────────

local function round(x) return math.floor((tonumber(x) or 0) + 0.5) end

local function buildRows(usage)
  local rate = usage.usd_eur_rate

  local t = os.date("*t")
  local todayIdx = (t.wday == 1) and 7 or (t.wday - 1)
  local todayTokens = (type(usage.daily) == "table" and usage.daily[todayIdx]) or 0

  local function ratdetail(util, resetIso, durationSecs)
    local p = pace(util, resetIso, durationSecs)
    local cd = formatCountdown(resetIso)
    local base = `{round(util)}% {noctalia.tr("used")}`
    local pl = paceLabel(p)
    if pl then base = `{base} · {pl}` end
    if cd then base = `{base} · {noctalia.tr("resets_in")} {cd}` end
    return base, p
  end

  local fiveSub, fiveP = ratdetail(usage.five_hour_util, usage.five_hour_reset, FIVE_HOUR_SECS)
  local sevenSub, sevenP = ratdetail(usage.seven_day_util, usage.seven_day_reset, SEVEN_DAY_SECS)

  local rows = {
    {
      id = "five_hour", glyph = paceGlyph(fiveP.status, "gauge"),
      title = noctalia.tr("five_hour"),
      subtitle = fiveSub,
      badge = `{round(usage.five_hour_util)}%`,
    },
    {
      id = "seven_day", glyph = paceGlyph(sevenP.status, "calendar"),
      title = noctalia.tr("seven_day"),
      subtitle = sevenSub,
      badge = `{round(usage.seven_day_util)}%`,
    },
    {
      id = "today", glyph = "coin",
      title = noctalia.tr("today"),
      subtitle = `{formatTokens(todayTokens)} {noctalia.tr("tokens")} · {formatCost(usage.today_cost, rate)}`,
    },
    {
      id = "week", glyph = "coin",
      title = noctalia.tr("week"),
      subtitle = `{formatTokens(usage.week_tokens)} {noctalia.tr("tokens")} · {formatCost(usage.week_cost, rate)}`,
    },
    {
      id = "month", glyph = "coin",
      title = noctalia.tr("month"),
      subtitle = `{formatTokens(usage.month_tokens)} {noctalia.tr("tokens")} · {formatCost(usage.month_cost, rate)}`,
    },
  }

  -- Per-model breakdown (current week), sorted desc.
  if type(usage.week_models) == "table" then
    local list = {}
    for name, tok in usage.week_models do
      table.insert(list, { name = name, tokens = tonumber(tok) or 0 })
    end
    table.sort(list, function(a, b) return a.tokens > b.tokens end)
    local weekTokens = tonumber(usage.week_tokens) or 0
    for _, m in list do
      local share = (weekTokens > 0) and round(m.tokens / weekTokens * 100) or 0
      table.insert(rows, {
        id = `model:{m.name}`, glyph = "robot",
        title = shortModelName(m.name),
        subtitle = `{formatTokens(m.tokens)} {noctalia.tr("tokens")} · {share}%`,
        badge = `{share}%`,
      })
    end
  end

  -- All-time footer.
  local s = tonumber(usage.alltime_sessions) or 0
  local msg = tonumber(usage.alltime_messages) or 0
  if s > 0 or msg > 0 then
    local parts = { `{s} {noctalia.tr("sessions")}`, `{msg} {noctalia.tr("msgs")}` }
    if type(usage.first_session) == "string" and usage.first_session ~= "" and usage.first_session ~= "unknown" then
      table.insert(parts, `{noctalia.tr("since")} {usage.first_session}`)
    end
    table.insert(rows, {
      id = "alltime", glyph = "history",
      title = noctalia.tr("all_time"),
      subtitle = table.concat(parts, " · "),
    })
  end

  return rows
end

-- id → "Title — subtitle", so Enter copies the row.
local rowText = {}

function onQuery(query)
  local usage = noctalia.state.get("usage")
  if type(usage) ~= "table" then
    launcher.setResults(query, {
      { id = "loading", title = noctalia.tr("title"), subtitle = "loading…", glyph = "robot" },
    })
    return
  end

  local rows = buildRows(usage)
  rowText = {}
  for _, r in rows do
    rowText[r.id] = r.subtitle and `{r.title} — {r.subtitle}` or r.title
  end
  launcher.setResults(query, rows)
end

function onActivate(id)
  local text = rowText[id]
  if text then
    noctalia.copyToClipboard(text, "text/plain")
    noctalia.notify(noctalia.tr("title"), text)
  end
end
