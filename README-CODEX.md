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
    "total_token_usage": {
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
echo '{"cwd":"'$PWD'","model":"gpt-5.2-codex","info":{"total_token_usage":{"total_tokens":6472},"model_context_window":258400},"rate_limits":{"primary":{"used_percent":24.0,"window_minutes":300,"resets_at":1767958180},"secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1768212356}}}' | ./statusline-codex.sh
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

## Requirements

- Bash
- jq
- git (for branch display)

## Install notes

Codex CLI does not currently expose a documented statusline command hook. If you
have a local wrapper or custom TUI that can pipe the JSON above into a command,
point it at `statusline-codex.sh` (for example, copy it to `~/.codex/` and mark
it executable).
