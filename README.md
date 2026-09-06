# Noctalia v5 — Claude Code Usage

A [Noctalia](https://noctalia.dev) v5 plugin that monitors your Claude Code subscription
usage (rate limits, token consumption, estimated cost, daily activity, per-model and
per-profile breakdowns). Ported from the
[Dank Material Shell plugin](https://github.com/titeya/dms-claudecode) by Nicolas Bellamy.

This repository is a **Noctalia plugin source**: the root `catalog.toml` indexes the
plugins, and each plugin lives in its own subdirectory (here, `claudecode/`).

## Screenshots

**Bar pill** (left-click opens the usage panel; hover for a summary tooltip):

<img src="assets/bar-pill.png" alt="Bar pill" width="170">

<table>
  <tr>
    <td valign="top" width="50%">
      <b>Usage panel</b> — left-click the pill<br><br>
      <img src="assets/panel.png" alt="Usage panel attached to the bar">
    </td>
    <td valign="top" width="50%">
      <b>Desktop widget</b><br><br>
      <img src="assets/desktop-panel.png" alt="Desktop usage panel">
    </td>
  </tr>
</table>

## Install

Add this repo as a plugin source, then enable the plugin:

```bash
noctalia msg plugins source add jrohland git https://github.com/jrohland/noctalia-v5-claudecode
noctalia msg plugins enable jrohland/claudecode
```

Then add the **Claude Code Usage** bar widget from the Add-widget picker. **Left-click** the
pill to open the usage panel under it (also `noctalia msg panel-toggle jrohland/claudecode:popout`);
**right-click** to refresh. For an always-visible copy, add the desktop widget from the
desktop-widget editor (`noctalia msg desktop-widgets-edit`). Configure the refresh interval and
currency under Settings → Plugins (or the panel's settings button).

Update later with `noctalia msg plugins update jrohland`, or remove the source with
`noctalia msg plugins source remove jrohland`.

## Requirements

- A Noctalia build at plugin API level 26 or newer
- `jq`, `curl`
- An authenticated Claude Code install (`~/.claude/.credentials.json`)

See [`claudecode/README.md`](claudecode/README.md) for plugin details and architecture.

## License

[MIT](LICENSE)
