# Claude Code Usage

Watch your Claude Code subscription burn down without leaving the bar: rate-limit
windows, token consumption, estimated cost, daily activity and a per-model breakdown,
refreshed in the background and mirrored into a bar pill, a click panel and a desktop
tile. Ported from the original [Dank Material Shell plugin](https://github.com/titeya/dms-claudecode)
by Nicolas Bellamy.

It reads the usage that Anthropic already reports for your own account, so it covers the
subscription rate windows (5-hour and 7-day) rather than only counting local tokens.

## Plugin

| Field | Value |
| --- | --- |
| ID | `jrohland/claudecode` |
| Entries | Bar widget: `pill`; panel: `popout`; desktop widget: `panel`; service: `service` |

The `service` entry is headless and owns the single fetch loop; `pill`, `popout` and
`panel` are thin clients that watch the state it publishes. Entry ids are unique across
entry types, which is why the click panel is `popout` while the desktop tile keeps the
older id `panel`.

## Requirements

- A Noctalia build at plugin API level 26 or newer.
- An authenticated Claude Code install, i.e. `~/.claude/.credentials.json` exists.
- `jq` and `curl` on `PATH`. The service checks for both and reports a status instead of
  running when either is missing.
- `bash`, plus the usual base userland that `get-claude-usage` calls: `awk`, `grep`,
  `date`, `cut`, `tr`, `wc`, `cat`, `head`, `find`, `basename` and `mktemp`. These ship
  with coreutils, findutils and gawk on every supported distribution.

## Usage

Add the **Claude Code Usage** widget to a bar from the Add-widget picker. The pill shows
the chosen rate window as `NN%`, colored by pacing: neutral when you are on or under
pace, warning when over pace, error when over quota, with an `↑` cue when you are off
track. Hover it for a summary tooltip.

- **Left-click** the pill opens the usage panel.
- **Right-click** forces a refresh.

Both are `[widget.actions]` defaults, so they are re-bindable in the bar's gesture
settings; the script's own `onClick` / `onRightClick` do the same thing if you remove a
binding.

The panel opens attached under the pill and carries the full detail: the 5-hour and
7-day windows with reset countdowns and pacing bars, token consumption for today, this
week and this month with estimated cost, a Monday-to-Sunday activity chart you can hover
for a single day's tokens and cost, a per-model breakdown for the current week, all-time
session and message stats, and a profile selector that cycles the CCS instances found in
`~/.ccs/instances/*`. Refresh, settings and close buttons sit in its header.

Open or close it from a terminal with:

```sh
noctalia msg panel-toggle jrohland/claudecode:popout
```

Force a refresh without touching the bar:

```sh
noctalia msg plugin jrohland/claudecode:service all refresh
```

For an always-visible copy, add the desktop widget from the desktop-widget editor
(`noctalia msg desktop-widgets-edit`). It lays out the same panel; being a desktop
surface it takes no hover, so the daily chart has no per-bar detail and the profile
selector is a cycle button rather than a dropdown.

## Settings

Plugin-wide settings live under Settings → Plugins; the rest are per-entry and appear
with the widget.

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `refresh_interval` | `int` | `2` | Minutes between background fetches (2–15). |
| `currency` | `select` | `auto` | Cost display: `auto` follows the locale, or force `usd` / `eur`. |
| `pill_metric` | `select` | `five_hour` | Which window the pill reports: `five_hour`, `seven_day`, or `both`. |
| `pill_style` | `select` | `glyph_text` | Pill appearance: glyph + percentage, a circular ring, or ring + percentage. |
| `show_glyph` | `bool` | `true` | Show the Claude glyph next to the percentage. |
| `ring_size` | `int` | `16` | Ring diameter in pixels (10–28). Keep it under the bar height or it clips. |
| `ring_thickness` | `int` | `3` | Ring stroke width in pixels (1–6). |
| `ring_color` | `color` | `#89B4FA` | Ring progress color, used only when the active palette cannot be read. |
| `ring_track_color` | `color` | `#585B70` | Ring background color, same fallback. |
| `accent` | `color` | `primary` | Desktop widget accent. |

Under `pill_metric = both` the ring tracks the 5-hour window only — the text still
carries both numbers. Two concentric rings do not read at bar size.

## How it differs from the DMS version

- Noctalia's `ui.*` has no arc primitive, so `ring.luau` generates an SVG and hands it to
  `barWidget.setImage`; the image loader rasterizes it through librsvg.
- An SVG needs literal hex and the plugin API has no palette-role resolver, so
  `ring.luau` resolves the active palette itself: custom and community palettes are read
  from disk, wallpaper palettes are re-derived by running `noctalia theme`. Built-in
  palettes live inside the shell binary and cannot be read, so those fall back to
  `ring_color` / `ring_track_color`.
- Inside the panel and the desktop widget, progress is still linear (`ui.progress`).
- The panel is a fixed 380×640 and scrolls; the DMS popout auto-sizes.

## Architecture

- `get-claude-usage` — the data engine, a Bash script. The plugin runs it with `--json`;
  its default `KEY=value` output and the `tests/` suite are preserved unchanged.
- `service.luau` — headless service: runs the script on the configured interval and
  publishes the parsed result as `usage` and `status`.
- `shared.luau` — formatters, countdown math, pacing model and profile projection,
  required by the three UI entries so they cannot drift on how a number reads.
- `widget.luau` — the bar pill.
- `ring.luau` — the pill's circular-progress SVG and palette resolution.
- `panel.luau` — the click panel.
- `desktop.luau` — the desktop tile.

## Notes

What this plugin touches, so nothing is a surprise:

- **Reads** `~/.claude/.credentials.json` for the OAuth token that authorizes the usage
  query, and enumerates `~/.ccs/instances/*` for the profile selector. The token is sent
  only to Anthropic.
- **Network**: the Anthropic usage API for your account's rate windows; LiteLLM's public
  model-price table to cost the tokens; Frankfurter (ECB rates) for USD to EUR. All over
  HTTPS, on the refresh interval.
- **Spawns** `get-claude-usage` through `bash`, and `noctalia theme` when the ring needs
  a wallpaper-derived palette.
- **Writes** nothing outside the plugin's own data directory.

Localized in English. Translations for other locales are welcome through
[Noctalia Translate](https://i18n.noctalia.dev).

## Development

Point a `path` source at a checkout; Luau edits hot-reload on save, manifest changes need
a config reload.

```sh
git clone https://github.com/jrohland/noctalia-v5-claudecode ~/dev/noctalia-v5-claudecode
noctalia msg plugins source add jrohland-dev path ~/dev/noctalia-v5-claudecode
noctalia msg plugins enable jrohland/claudecode
```

Run the data-engine tests with `bash tests/test-get-claude-usage.sh`. They mock `curl`,
so they need no network and no credentials.

## License

[MIT](LICENSE)
