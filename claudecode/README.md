# Claude Code Usage (Noctalia v5)

A [Noctalia](https://noctalia.dev) v5 plugin that monitors your Claude Code subscription
usage. Ported from the original [Dank Material Shell plugin](https://github.com/titeya/dms-claudecode).

## Features

- **Bar pill** showing 5-hour (or 7-day) rate-limit utilization as `NN%`, colored by
  threshold (>80% error, >50% warning, else accent), with a summary tooltip.
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

Noctalia's plugin API has no bar-click popout, so the rich detail UI is a **desktop
widget** (added from the desktop-widget editor) rather than a popout from the bar pill.
Circular progress rings are rendered as linear bars, and the interactive per-bar hover
tooltips on the daily chart are not available (Noctalia's `ui.*` has no hover events).
The profile tabs/dropdown become a cycle button.

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
