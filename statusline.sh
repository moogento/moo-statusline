#!/bin/bash

# Detect OS
OS_TYPE=$(uname -s)

# Configuration via environment variables
# Set any of these to "1" to hide that segment
# MOO_HIDE_GIT=1      - Hide git branch
# MOO_HIDE_CONTEXT=1  - Hide context usage
# MOO_HIDE_WEEKLY=1   - Hide weekly percentage
# MOO_HIDE_RESET=1    - Hide reset timer

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
GREEN=$'\033[38;2;116;190;51m'  # #74BE33 for branch
DARK_GREEN=$'\033[38;2;53;117;0m'  # #357500 for reset icon
YELLOW=$'\033[38;2;255;193;7m'
DARK_ORANGE=$'\033[38;2;204;122;0m'  # Darker orange for context warning
RED=$'\033[38;2;255;82;82m'
RESET=$'\033[0m'

# Git branch info
git_info="${GRAY}${project_name}${RESET}"
if [ "$MOO_HIDE_GIT" != "1" ]; then
    if [ -d "$cwd/.git" ] || [ -d "$(dirname "$cwd")/.git" ]; then
        git_branch=$(cd "$cwd" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$git_branch" ]; then
            git_info="${GRAY}${project_name} 🌿 ${GREEN}${git_branch}${RESET}"
        fi
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

# Get OAuth token (OS-specific)
get_oauth_token() {
    local creds
    if [ "$OS_TYPE" = "Darwin" ]; then
        # macOS: use Keychain
        creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    else
        # Linux: try secret-tool (GNOME Keyring) or file-based fallback
        if command -v secret-tool >/dev/null 2>&1; then
            creds=$(secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        fi
        # Fallback: check for credentials file
        if [ -z "$creds" ] && [ -f "$HOME/.claude/credentials.json" ]; then
            creds=$(cat "$HOME/.claude/credentials.json" 2>/dev/null)
        fi
    fi
    if [ -n "$creds" ]; then
        echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
    fi
}

# Cache file for usage data (avoid hammering API)
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_MAX_AGE=30  # seconds

get_file_mtime() {
    if [ "$OS_TYPE" = "Darwin" ]; then
        stat -f %m "$1" 2>/dev/null || echo 0
    else
        stat -c %Y "$1" 2>/dev/null || echo 0
    fi
}

should_refresh_cache() {
    if [ ! -f "$CACHE_FILE" ]; then
        return 0
    fi
    local cache_age=$(($(date +%s) - $(get_file_mtime "$CACHE_FILE")))
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
api_error=false
if should_refresh_cache; then
    usage_json=$(fetch_usage)
    if [ -n "$usage_json" ] && echo "$usage_json" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$usage_json" > "$CACHE_FILE"
    else
        api_error=true
        if [ -f "$CACHE_FILE" ]; then
            usage_json=$(cat "$CACHE_FILE")
        fi
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

        # Show daily and weekly (only if weekly data exists and not hidden)
        weekly_display=""
        if [ "$MOO_HIDE_WEEKLY" != "1" ] && [ -n "$weekly_pct" ] && [ "$weekly_pct" != "null" ]; then
            weekly_int=${weekly_pct%.*}
            [ -z "$weekly_int" ] && weekly_int=0
            weekly_display=" w:${weekly_int}%"
        fi

        # Add error indicator if API is failing
        error_indicator=""
        if [ "$api_error" = true ]; then
            error_indicator="${RED}[!]${RESET} "
        fi

        usage_display="${error_indicator}${bar_color}[${bar}]${RESET} ${GRAY}5h:${pct_int}% used${weekly_display}${RESET}"
    fi

    # Calculate reset time
    if [ "$MOO_HIDE_RESET" != "1" ] && [ -n "$five_hour_reset" ]; then
        # Parse ISO timestamp as UTC (API returns UTC time)
        if [ "$OS_TYPE" = "Darwin" ]; then
            reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${five_hour_reset%%.*}" +%s 2>/dev/null)
        else
            reset_epoch=$(date -d "${five_hour_reset}" +%s 2>/dev/null)
        fi
        now_epoch=$(date +%s)

        if [ -n "$reset_epoch" ]; then
            seconds_until=$((reset_epoch - now_epoch))

            # If reset time has passed, clear cache to force refresh
            if [ $seconds_until -le 0 ]; then
                rm -f "$CACHE_FILE" 2>/dev/null
                reset_display="${DARK_GREEN}↺ ${RESET}${GRAY}refreshing...${RESET}"
            else
                hours=$((seconds_until / 3600))
                minutes=$(((seconds_until % 3600) / 60))

                # Extract time components (OS-specific)
                if [ "$OS_TYPE" = "Darwin" ]; then
                    reset_hour=$(LC_TIME=C date -r "$reset_epoch" "+%-I" 2>/dev/null)
                    reset_min=$(LC_TIME=C date -r "$reset_epoch" "+%M" 2>/dev/null)
                    reset_ampm=$(LC_TIME=C date -r "$reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
                else
                    reset_hour=$(LC_TIME=C date -d "@$reset_epoch" "+%-I" 2>/dev/null)
                    reset_min=$(LC_TIME=C date -d "@$reset_epoch" "+%M" 2>/dev/null)
                    reset_ampm=$(LC_TIME=C date -d "@$reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
                fi

                # If minutes are 59, round to next hour for cleaner display
                if [ "$reset_min" = "59" ]; then
                    reset_hour=$((reset_hour + 1))
                    # When going from 11:59 to 12:00, we cross noon or midnight
                    if [ $reset_hour -eq 12 ]; then
                        # Flip AM/PM when crossing noon (11:59 AM → 12:00 PM) or midnight (11:59 PM → 12:00 AM)
                        if [ "$reset_ampm" = "pm" ]; then
                            reset_ampm="am"
                        else
                            reset_ampm="pm"
                        fi
                    elif [ $reset_hour -eq 13 ]; then
                        # This shouldn't happen with 12-hour format, but handle it just in case
                        reset_hour=1
                        if [ "$reset_ampm" = "pm" ]; then
                            reset_ampm="am"
                        else
                            reset_ampm="pm"
                        fi
                    fi
                    # Handle 12:00 special cases
                    if [ $reset_hour -eq 12 ]; then
                        if [ "$reset_ampm" = "am" ]; then
                            reset_time_str="midnight"
                        else
                            reset_time_str="midday"
                        fi
                    else
                        reset_time_str="${reset_hour}${reset_ampm}"
                    fi
                elif [ "$reset_min" = "00" ]; then
                    # Handle 12:00 special cases
                    if [ $reset_hour -eq 12 ]; then
                        if [ "$reset_ampm" = "am" ]; then
                            reset_time_str="midnight"
                        else
                            reset_time_str="midday"
                        fi
                    else
                        reset_time_str="${reset_hour}${reset_ampm}"
                    fi
                else
                    # Show minutes - no special handling needed for non-00 minutes
                    reset_time_str="${reset_hour}:${reset_min}${reset_ampm}"
                fi

                # Color based on time remaining
                total_minutes=$((hours * 60 + minutes))
                if [ $total_minutes -lt 15 ]; then
                    time_color="$GREEN"  # Almost reset!
                else
                    time_color="$GRAY"
                fi

                reset_display="${DARK_GREEN}↺ ${RESET}${time_color}${reset_time_str} ${hours}h${minutes}m${RESET}"
            fi
        fi
    fi
fi

# Fallback if API failed
if [ -z "$usage_display" ]; then
    usage_display="${GRAY}[░░░░░░░░░░] --%${RESET}"
fi
if [ -z "$reset_display" ]; then
    reset_display="${DARK_GREEN}↺ ${RESET}${GRAY}--${RESET}"
fi

# Context window (always show in k format)
context_display=""
if [ "$MOO_HIDE_CONTEXT" != "1" ]; then
    context_window=$(echo "$input" | jq ".context_window")
    window_size=$(echo "$context_window" | jq -r ".context_window_size // 200000")
    current_usage=$(echo "$context_window" | jq ".current_usage")
fi

if [ "$MOO_HIDE_CONTEXT" != "1" ] && [ "$current_usage" != "null" ]; then
    input_tokens=$(echo "$current_usage" | jq -r ".input_tokens // 0")
    cache_creation=$(echo "$current_usage" | jq -r ".cache_creation_input_tokens // 0")
    cache_read=$(echo "$current_usage" | jq -r ".cache_read_input_tokens // 0")
    current_total=$((input_tokens + cache_creation + cache_read))

    # Auto-compact threshold: context_window - 45K buffer
    # All models have 200K context, compact triggers at ~155K
    auto_compact_buffer=45000
    compact_threshold=$((window_size - auto_compact_buffer))

    # Convert to k format (round to nearest k)
    current_k=$((current_total / 1000))
    compact_k=$(( (compact_threshold + 500) / 1000 ))
    window_k=$((window_size / 1000))

    # Color based on proximity to auto-compact threshold
    # Dark red: within 10k of compact threshold
    # Dark orange: within 20k of compact threshold
    remaining_k=$((compact_k - current_k))
    if [ $remaining_k -le 10 ]; then
        ctx_color="$RED"
    elif [ $remaining_k -le 20 ]; then
        ctx_color="$DARK_ORANGE"
    else
        ctx_color="$GRAY"
    fi

    # Format: current/compact(theoretical_max) with max in dark grey
    context_display="${GRAY}⛁ ${ctx_color}${current_k}k/${compact_k}k${DARK_GRAY}(${window_k}k)${RESET}"

    # Add warning when very close to compact threshold
    if [ $remaining_k -le 5 ] && [ $remaining_k -gt 0 ]; then
        context_display="${context_display} ${RED}${remaining_k}k left${RESET}"
    fi
fi

# Output
PIPE="${DARK_GRAY} | ${RESET}"
printf "%s%s%s" "$git_info" "$PIPE" "$model_name"

if [ -n "$context_display" ]; then
    printf "%s%s" "$PIPE" "$context_display"
fi

printf "%s%s %s" "$PIPE" "$usage_display" "$reset_display"
