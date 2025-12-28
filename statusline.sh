#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract basic info
cwd=$(echo "$input" | jq -r ".workspace.current_dir // .cwd")
model_id=$(echo "$input" | jq -r ".model.id")
model_display=$(echo "$input" | jq -r ".model.display_name")
project_dir=$(echo "$input" | jq -r ".workspace.project_dir // \"\"")

# Determine project name
if [ -n "$project_dir" ] && [ "$project_dir" != "null" ]; then
    project_name=$(basename "$project_dir")
else
    project_name=$(basename "$cwd")
fi

# Color codes
GRAY=$'\033[38;2;121;121;122m'
DARK_GRAY=$'\033[38;2;74;74;74m'
GREEN=$'\033[38;2;116;190;51m'
YELLOW=$'\033[38;2;255;193;7m'
RED=$'\033[38;2;255;82;82m'
RESET=$'\033[0m'

# Git branch info
git_info="${GRAY}${project_name}${RESET}"
if [ -d "$cwd/.git" ] || [ -d "$(dirname "$cwd")/.git" ]; then
    git_branch=$(cd "$cwd" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        git_info="${GRAY}${project_name} 🌿 ${GREEN}${git_branch}${RESET}"
    fi
fi

# Simplify model name
model_name_raw="$model_display"
if [[ "$model_id" == *"sonnet"* ]]; then
    if [[ "$model_id" == *"4-5"* ]]; then
        model_name_raw="sonnet 4.5"
    elif [[ "$model_id" == *"4"* ]]; then
        model_name_raw="sonnet 4"
    else
        model_name_raw="sonnet"
    fi
elif [[ "$model_id" == *"opus"* ]]; then
    if [[ "$model_id" == *"4-5"* ]]; then
        model_name_raw="opus 4.5"
    elif [[ "$model_id" == *"4"* ]]; then
        model_name_raw="opus 4"
    else
        model_name_raw="opus"
    fi
elif [[ "$model_id" == *"haiku"* ]]; then
    model_name_raw="haiku"
fi
model_name="${GRAY}${model_name_raw}${RESET}"

# ============================================
# Get REAL usage from Anthropic API
# ============================================
usage_display=""
reset_display=""

# Try to get OAuth token from Keychain (macOS)
get_oauth_token() {
    local creds
    creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -n "$creds" ]; then
        echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
    fi
}

# Cache file for usage data (avoid hammering API)
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_MAX_AGE=30  # seconds

should_refresh_cache() {
    if [ ! -f "$CACHE_FILE" ]; then
        return 0
    fi
    local cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
    [ $cache_age -gt $CACHE_MAX_AGE ]
}

fetch_usage() {
    local token
    token=$(get_oauth_token)
    if [ -z "$token" ]; then
        return 1
    fi

    curl -s --max-time 2 "https://api.anthropic.com/api/oauth/usage" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        2>/dev/null
}

# Get usage data (from cache or API)
usage_json=""
if should_refresh_cache; then
    usage_json=$(fetch_usage)
    if [ -n "$usage_json" ] && echo "$usage_json" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$usage_json" > "$CACHE_FILE"
    elif [ -f "$CACHE_FILE" ]; then
        usage_json=$(cat "$CACHE_FILE")
    fi
else
    usage_json=$(cat "$CACHE_FILE" 2>/dev/null)
fi

# Parse usage data
if [ -n "$usage_json" ]; then
    five_hour_pct=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    five_hour_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    weekly_pct=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)

    if [ -n "$five_hour_pct" ]; then
        # Round to integer
        pct_int=${five_hour_pct%.*}
        [ -z "$pct_int" ] && pct_int=0

        # Build progress bar
        filled=$((pct_int / 10))
        empty=$((10 - filled))
        [ $filled -gt 10 ] && filled=10 && empty=0
        [ $filled -lt 0 ] && filled=0 && empty=10

        bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done

        # Color based on usage
        if [ $pct_int -ge 80 ]; then
            bar_color="$RED"
        elif [ $pct_int -ge 50 ]; then
            bar_color="$YELLOW"
        else
            bar_color="$GRAY"
        fi

        # Always show daily and weekly percentages
        weekly_int=0
        if [ -n "$weekly_pct" ]; then
            weekly_int=${weekly_pct%.*}
            [ -z "$weekly_int" ] && weekly_int=0
        fi

        usage_display="${bar_color}[${bar}]${RESET} ${GRAY}d:${pct_int}% w:${weekly_int}%${RESET}"
    fi

    # Calculate reset time
    if [ -n "$five_hour_reset" ]; then
        # Parse ISO timestamp
        reset_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${five_hour_reset%%.*}" +%s 2>/dev/null || \
                      date -d "${five_hour_reset}" +%s 2>/dev/null)
        now_epoch=$(date +%s)

        if [ -n "$reset_epoch" ]; then
            seconds_until=$((reset_epoch - now_epoch))
            if [ $seconds_until -gt 0 ]; then
                hours=$((seconds_until / 3600))
                minutes=$(((seconds_until % 3600) / 60))

                # Extract hour from reset time for display
                reset_hour=$(date -j -f "%s" "$reset_epoch" "+%-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')

                # Color based on time remaining
                if [ $hours -lt 1 ]; then
                    time_color="$GREEN"  # Almost reset!
                elif [ $hours -lt 2 ]; then
                    time_color="$YELLOW"
                else
                    time_color="$GRAY"
                fi

                reset_display="${time_color}♻️ ${reset_hour} ${hours}h${minutes}m${RESET}"
            else
                reset_display="${GREEN}♻️ now${RESET}"
            fi
        fi
    fi
fi

# Fallback if API failed
if [ -z "$usage_display" ]; then
    usage_display="${GRAY}[░░░░░░░░░░] --%${RESET}"
fi
if [ -z "$reset_display" ]; then
    reset_display="${GRAY}♻️ --${RESET}"
fi

# Context window (always show in k format)
context_display=""
context_window=$(echo "$input" | jq ".context_window")
window_size=$(echo "$context_window" | jq -r ".context_window_size // 200000")
current_usage=$(echo "$context_window" | jq ".current_usage")

if [ "$current_usage" != "null" ]; then
    input_tokens=$(echo "$current_usage" | jq -r ".input_tokens // 0")
    cache_creation=$(echo "$current_usage" | jq -r ".cache_creation_input_tokens // 0")
    cache_read=$(echo "$current_usage" | jq -r ".cache_read_input_tokens // 0")
    current_total=$((input_tokens + cache_creation + cache_read))

    # Auto-compact threshold (85% of window size)
    compact_threshold=$((window_size * 85 / 100))

    # Convert to k format
    current_k=$((current_total / 1000))
    compact_k=$((compact_threshold / 1000))

    # Color based on usage percentage
    ctx_pct=$((current_total * 100 / window_size))
    if [ $ctx_pct -ge 85 ]; then
        ctx_color="$RED"
    elif [ $ctx_pct -ge 70 ]; then
        ctx_color="$YELLOW"
    else
        ctx_color="$GRAY"
    fi

    context_display="${ctx_color}ctx:${current_k}k/${compact_k}k${RESET}"
fi

# Output
PIPE="${DARK_GRAY} | ${RESET}"
printf "%s%s%s%s%s %s" "$git_info" "$PIPE" "$model_name" "$PIPE" "$usage_display" "$reset_display"

if [ -n "$context_display" ]; then
    printf "%s%s" "$PIPE" "$context_display"
fi
