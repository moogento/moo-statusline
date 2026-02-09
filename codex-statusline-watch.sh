#!/bin/bash

set -euo pipefail

OS_TYPE=$(uname -s)
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SESSIONS_DIR="${SESSIONS_DIR:-$CODEX_HOME/sessions}"
STATUSLINE_SCRIPT="${STATUSLINE_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline-codex.sh}"
BOOTSTRAP_LINES="${BOOTSTRAP_LINES:-2000}"

usage() {
    cat <<'EOF'
Usage: codex-statusline-watch.sh

Watches the latest Codex rollout JSONL and renders a statusline on token_count events.

Options:
  --once           Render the latest token_count once and exit

Env vars:
  CODEX_HOME        Override Codex home directory (default: ~/.codex)
  SESSIONS_DIR      Override sessions dir (default: $CODEX_HOME/sessions)
  STATUSLINE_SCRIPT Path to statusline renderer (default: ./statusline-codex.sh)
  BOOTSTRAP_LINES   Lines to scan for initial context (default: 2000)
EOF
}

MODE_ONCE=0

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "${1:-}" = "--once" ]; then
    MODE_ONCE=1
    shift
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required. Install it and retry." >&2
    exit 1
fi

if [ ! -f "$STATUSLINE_SCRIPT" ]; then
    echo "Statusline script not found: $STATUSLINE_SCRIPT" >&2
    exit 1
fi

if [ ! -d "$SESSIONS_DIR" ]; then
    echo "Sessions directory not found: $SESSIONS_DIR" >&2
    exit 1
fi

find_latest_rollout() {
    local latest=""
    if [ "$OS_TYPE" = "Darwin" ]; then
        latest=$(find "$SESSIONS_DIR" -type f -name 'rollout-*.jsonl' -exec stat -f '%m %N' {} + 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    else
        latest=$(find "$SESSIONS_DIR" -type f -name 'rollout-*.jsonl' -exec stat -c '%Y %n' {} + 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    fi
    printf '%s' "$latest"
}

bootstrap_context() {
    local file="$1"
    local tail_data
    tail_data=$(tail -n "$BOOTSTRAP_LINES" "$file" 2>/dev/null || true)
    if [ -z "$tail_data" ]; then
        return
    fi

    local found_cwd
    local found_model

    found_cwd=$(printf '%s\n' "$tail_data" | jq -r 'select(.type=="turn_context") | .payload.cwd' | tail -1)
    if [ -z "$found_cwd" ] || [ "$found_cwd" = "null" ]; then
        found_cwd=$(printf '%s\n' "$tail_data" | jq -r 'select(.type=="session_meta") | .payload.cwd' | tail -1)
    fi
    if [ -n "$found_cwd" ] && [ "$found_cwd" != "null" ]; then
        current_cwd="$found_cwd"
    fi

    found_model=$(printf '%s\n' "$tail_data" | jq -r 'select(.type=="turn_context") | .payload.model' | tail -1)
    if [ -n "$found_model" ] && [ "$found_model" != "null" ]; then
        current_model="$found_model"
    fi
}

render_line() {
    local json="$1"
    local status
    status=$(printf '%s\n' "$json" | bash "$STATUSLINE_SCRIPT" 2>/dev/null || true)
    if [ -n "$status" ]; then
        printf '\r%s\033[K' "$status"
    fi
}

render_line_once() {
    local json="$1"
    local status
    status=$(printf '%s\n' "$json" | bash "$STATUSLINE_SCRIPT" 2>/dev/null || true)
    if [ -n "$status" ]; then
        printf '%s\n' "$status"
    fi
}

current_cwd=""
current_model=""

rollout_file=$(find_latest_rollout)
while [ -z "$rollout_file" ]; do
    sleep 1
    rollout_file=$(find_latest_rollout)
done

bootstrap_context "$rollout_file"

if [ "$MODE_ONCE" -eq 1 ]; then
    payload=$(jq -c 'select(.type=="event_msg" and .payload.type=="token_count") | .payload' "$rollout_file" | tail -1)
    if [ -z "$payload" ] || [ "$payload" = "null" ]; then
        echo "No token_count events found in: $rollout_file" >&2
        exit 2
    fi

    merged=$(printf '%s\n' "$payload" | jq -c --arg cwd "$current_cwd" --arg model "$current_model" '. + {cwd:$cwd, model:$model}' 2>/dev/null || true)
    if [ -z "$merged" ]; then
        echo "Failed to merge payload with cwd/model." >&2
        exit 3
    fi

    render_line_once "$merged"
    exit 0
fi

# Render a best-effort initial line so the terminal isn't blank until new events arrive.
bootstrap_payload=$(tail -n "$BOOTSTRAP_LINES" "$rollout_file" 2>/dev/null | jq -c 'select(.type=="event_msg" and .payload.type=="token_count") | .payload' 2>/dev/null | tail -1)
if [ -n "$bootstrap_payload" ] && [ "$bootstrap_payload" != "null" ]; then
    bootstrap_merged=$(printf '%s\n' "$bootstrap_payload" | jq -c --arg cwd "$current_cwd" --arg model "$current_model" '. + {cwd:$cwd, model:$model}' 2>/dev/null || true)
    if [ -n "$bootstrap_merged" ]; then
        render_line "$bootstrap_merged"
    fi
fi

if [ -z "${bootstrap_merged:-}" ]; then
    placeholder=$(jq -c -n --arg cwd "$current_cwd" --arg model "$current_model" '{cwd:$cwd, model:$model}')
    render_line "$placeholder"
fi

trap 'printf "\n"; exit 0' INT TERM

tail -n 0 -F "$rollout_file" | while IFS= read -r line; do
    if [ -z "$line" ]; then
        continue
    fi

    event_type=$(printf '%s\n' "$line" | jq -r '.type // empty' 2>/dev/null || true)
    case "$event_type" in
        turn_context)
            new_cwd=$(printf '%s\n' "$line" | jq -r '.payload.cwd // empty' 2>/dev/null || true)
            if [ -n "$new_cwd" ] && [ "$new_cwd" != "null" ]; then
                current_cwd="$new_cwd"
            fi
            new_model=$(printf '%s\n' "$line" | jq -r '.payload.model // empty' 2>/dev/null || true)
            if [ -n "$new_model" ] && [ "$new_model" != "null" ]; then
                current_model="$new_model"
            fi
            ;;
        session_meta)
            new_cwd=$(printf '%s\n' "$line" | jq -r '.payload.cwd // empty' 2>/dev/null || true)
            if [ -n "$new_cwd" ] && [ "$new_cwd" != "null" ]; then
                current_cwd="$new_cwd"
            fi
            ;;
        event_msg)
            payload_type=$(printf '%s\n' "$line" | jq -r '.payload.type // empty' 2>/dev/null || true)
            if [ "$payload_type" = "token_count" ]; then
                payload=$(printf '%s\n' "$line" | jq -c '.payload' 2>/dev/null || true)
                if [ -n "$payload" ]; then
                    merged=$(printf '%s\n' "$payload" | jq -c --arg cwd "$current_cwd" --arg model "$current_model" '. + {cwd:$cwd, model:$model}' 2>/dev/null || true)
                    if [ -n "$merged" ]; then
                        render_line "$merged"
                    fi
                fi
            fi
            ;;
    esac
done
