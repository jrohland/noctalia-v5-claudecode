# Claude Code Usage (Noctalia v5)

A [Noctalia](https://noctalia.dev) v5 plugin that monitors your Claude Code subscription
usage. Ported from the original [Dank Material Shell plugin](https://github.com/titeya/dms-claudecode).

## Features

- **Bar pill** showing 5-hour, 7-day, or both rate-limit utilizations as `NN%`, colored by
  pacing (neutral on/under pace, warning over pace, error over quota, `↑` when off-track),
  with a summary tooltip. **Left-click** opens the usage panel; **right-click** refreshes.
- **Usage panel** (attached under the pill, like the DMS popout) with:
  - 5-hour and 7-day rate windows with reset countdowns and pacing (usage bar over a thin
    time-elapsed bar)
  - Token consumption (today / week / month) with estimated cost
  - Weekly activity bar chart (Monday–Sunday) — hover a bar for that day's tokens and cost
  - Per-model token breakdown for the current calendar week
  - All-time session and message stats
  - CCS profile selector (tabs for up to 4 profiles, dropdown beyond; cycles through
    `~/.ccs/instances/*`)
  - Refresh / settings / close buttons
- **Desktop widget** with the same content as an always-visible tile (profile cycle button).
- **Automatic subscription / rate-limit detection** via the Anthropic OAuth API.
- **Dynamic model pricing** from [LiteLLM](https://github.com/BerriAI/litellm); USD/EUR
  via the ECB ([Frankfurter](https://www.frankfurter.app/)).
- **Localization** (English, French).

## How it differs from the DMS version

- Circular progress rings are rendered as linear bars (Noctalia's `ui.*` has no ring).
- The panel has a fixed size declared in the manifest (380×640) and scrolls; the DMS popout
  auto-sizes.
- The desktop widget's daily chart has no hover tooltips (desktop widgets take no hover);
  the panel's does.

## Requirements

- Noctalia ≥ 5.0.1 (`plugin_api = 22`)
- `jq`, `curl`
- An authenticated Claude Code install (`~/.claude/.credentials.json`)

## Architecture

- `get-claude-usage` — the data engine (Bash). Run with `--json` by the plugin; the
  default `KEY=value` output and its `tests/` are preserved unchanged.
- `service.luau` — headless service: runs the script on the configured interval and
  publishes the parsed result to the plugin's shared state (`usage`, `status`).
- `shared.luau` — formatters, countdown math, pacing model, profile projection, shared by
  the three UI entries via `require`.
- `widget.luau` — bar pill (thin client of the published state).
- `panel.luau` — the click panel (`[[panel]]`, id `popout`).
- `desktop.luau` — the desktop tile (`[[desktop_widget]]`, id `panel`).

Entry ids are unique across entry types, hence `popout` for the panel and `panel` for the
long-standing desktop tile.

## Installation (manual / local dev)

Point a `path` source at a checkout (read-only, no copy; scripts hot-reload on save):

```bash
git clone https://github.com/jrohland/noctalia-v5-claudecode ~/dev/noctalia-v5-claudecode
noctalia msg plugins source add jrohland-dev path ~/dev/noctalia-v5-claudecode
noctalia msg plugins enable jrohland/claudecode
```

Then add the **Claude Code Usage** bar widget from the Add-widget picker, and optionally the
desktop widget from the desktop-widget editor. Configure the refresh interval and currency
under Settings → Plugins.

Useful commands:

```bash
noctalia msg panel-toggle jrohland/claudecode:popout          # open / close the panel
noctalia msg plugin jrohland/claudecode:service all refresh   # force a refresh
noctalia msg plugins disable jrohland/claudecode && noctalia msg plugins enable jrohland/claudecode
```

## License

[MIT](LICENSE)
