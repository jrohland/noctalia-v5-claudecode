# Claude Code Usage (Noctalia v5)

A [Noctalia](https://noctalia.dev) v5 plugin that monitors your Claude Code subscription
usage. Ported from the original [Dank Material Shell plugin](https://github.com/titeya/dms-claudecode).

## Features

- **Bar pill** showing 5-hour, 7-day, or both rate-limit utilizations as `NN%`, colored by
  threshold (>80% error, >50% warning, else neutral), with a summary tooltip.
  **Left-click** opens the usage breakdown in the launcher overlay; **right-click** refreshes.
- **Launcher breakdown** (`/cc`) — a centered overlay listing rate windows, today/week/month
  tokens + cost, per-model usage, and all-time stats. Appears over the current workspace
  (works on a tiling WM where the desktop is never visible).
- **Desktop widget panel** with:
  - 5-hour and 7-day rate windows with reset countdowns
  - Token consumption (today / week / month) with estimated cost
  - Weekly activity bar chart (Monday–Sunday)
  - Per-model token breakdown for the current calendar week
  - All-time session and message stats
  - CCS profile selector (cycles through `~/.ccs/instances/*`)
- **Automatic subscription / rate-limit detection** via the Anthropic OAuth API.
- **Dynamic model pricing** from [LiteLLM](https://github.com/BerriAI/litellm); USD/EUR
  via the ECB ([Frankfurter](https://www.frankfurter.app/)).
- **Localization** (English, French).

## How it differs from the DMS version

Noctalia's plugin API has no bar-anchored popout (verified against the runtime — bar
widgets only render text/glyph/tooltip, and there is no plugin panel/popout API). So the
rich UI is split across two surfaces:

- a **launcher breakdown** (`/cc`, or left-click the pill) — a centered overlay that
  appears over the current workspace, the closest thing to a click-flyout;
- a **desktop widget** with the full visual panel (charts/bars), added from the
  desktop-widget editor.

Circular progress rings are rendered as linear bars, the daily chart has no per-bar hover
tooltips (Noctalia's `ui.*` has no hover events), and the profile tabs/dropdown become a
cycle button.

## Requirements

- Noctalia ≥ 5.0.0
- `jq`, `curl`
- An authenticated Claude Code install (`~/.claude/.credentials.json`)

## Architecture

- `get-claude-usage` — the data engine (Bash). Run with `--json` by the plugin; the
  default `KEY=value` output and its `tests/` are preserved unchanged.
- `service.luau` — headless service: runs the script on the configured interval and
  publishes the parsed result to the plugin's shared state.
- `widget.luau` — bar pill (thin client of the published state).
- `desktop.luau` — the detail panel (thin client of the published state).

## Installation (manual / local dev)

```bash
git clone <repo> "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/claudecode"
noctalia msg config-reload
```

Then enable it (`noctalia msg plugins enable titeya/claudecode`), add the **Claude Code
Usage** bar widget from the Add-widget picker, and add the desktop widget from the
desktop-widget editor. Configure the refresh interval and currency under
Settings → Plugins.

Force a manual refresh:

```bash
noctalia msg plugin titeya/claudecode:service all refresh
```

## License

[MIT](LICENSE)
