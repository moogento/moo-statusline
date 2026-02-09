# Moo Statusline for Codex CLI

This is a Codex-oriented copy of the moo-statusline script. It reads a JSON
payload from stdin and renders a compact statusline with:

- Project name + git branch
- Model name
- Context usage vs model context window
- Rate limit usage + reset timer

## Script

- `statusline-codex.sh`

## Input format

The script expects JSON similar to Codex `token_count` events:

```json
{
  "cwd": "/path/to/repo",
  "model": "gpt-5.2-codex",
  "info": {
    "last_token_usage": {
      "input_tokens": 6437,
      "cached_input_tokens": 0,
      "output_tokens": 35,
      "reasoning_output_tokens": 0,
      "total_tokens": 6472
    },
    "model_context_window": 258400
  },
  "rate_limits": {
    "primary": {
      "used_percent": 24.0,
      "window_minutes": 300,
      "resets_at": 1767958180
    },
    "secondary": {
      "used_percent": 3.0,
      "window_minutes": 10080,
      "resets_at": 1768212356
    }
  }
}
```

The script also accepts Claude-style keys (e.g., `workspace.current_dir`,
`context_window`) as fallbacks.

## Manual test

```bash
echo '{"cwd":"'$PWD'","model":"gpt-5.2-codex","info":{"last_token_usage":{"total_tokens":6472},"model_context_window":258400},"rate_limits":{"primary":{"used_percent":24.0,"window_minutes":300,"resets_at":1767958180},"secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1768212356}}}' | ./statusline-codex.sh
```

## Live watcher (separate terminal)

This helper tails the latest Codex rollout JSONL and renders the statusline in
place as token_count events arrive:

```bash
chmod +x ./statusline-codex.sh ./codex-statusline-watch.sh
./codex-statusline-watch.sh
```

If you start a new Codex session, re-run the watcher so it attaches to the
latest rollout file.

Env overrides:
- `CODEX_HOME` (default `~/.codex`)
- `SESSIONS_DIR` (default `$CODEX_HOME/sessions`)
- `STATUSLINE_SCRIPT` (default `./statusline-codex.sh`)
- `BOOTSTRAP_LINES` (default `2000`)

## Install into `~/.codex/` (optional)

Codex CLI does not currently expose a built-in statusline hook, so the
recommended approach is to run the watcher in a separate terminal.

Install the scripts somewhere stable:

```bash
mkdir -p ~/.codex/moo-statusline
cp ./statusline-codex.sh ./codex-statusline-watch.sh ~/.codex/moo-statusline/
chmod +x ~/.codex/moo-statusline/statusline-codex.sh ~/.codex/moo-statusline/codex-statusline-watch.sh
```

Render the latest token_count once:

```bash
~/.codex/moo-statusline/codex-statusline-watch.sh --once
```

Or watch live updates (separate terminal):

```bash
~/.codex/moo-statusline/codex-statusline-watch.sh
```

## Requirements

- Bash
- jq
- git (for branch display)

## Install notes

If you have a wrapper/custom TUI that can pipe Codex `token_count` JSON into a
command, point it at `statusline-codex.sh`.
