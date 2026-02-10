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
LIGHT_ORANGE=$'\033[38;2;255;179;71m'  # Light orange for extra usage
LIGHT_BROWN=$'\033[38;2;181;137;80m'  # Light brown for worktree
RED=$'\033[38;2;255;82;82m'
RESET=$'\033[0m'

# Git branch info
git_info="${GRAY}${project_name}${RESET}"
if [ "$MOO_HIDE_GIT" != "1" ]; then
    if [ -d "$cwd/.git" ] || [ -d "$(dirname "$cwd")/.git" ] || [ -f "$cwd/.git" ]; then
        git_branch=$(cd "$cwd" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$git_branch" ]; then
            git_info="${GRAY}${project_name} 🌿 ${GREEN}${git_branch}${RESET}"
            # Detect worktree: git-common-dir differs from git-dir in a worktree
            git_dir=$(cd "$cwd" 2>/dev/null && git rev-parse --git-dir 2>/dev/null)
            git_common_dir=$(cd "$cwd" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)
            if [ -n "$git_dir" ] && [ -n "$git_common_dir" ] && [ "$git_dir" != "$git_common_dir" ]; then
                worktree_name=$(basename "$cwd")
                git_info="${git_info} ${LIGHT_BROWN}🪾 ${worktree_name}${RESET}"
            fi
        fi
    fi
fi

# Simplify model name: extract family and version from model_id
# e.g. "claude-opus-4-6" → "opus 4.6", "claude-sonnet-4-5-20250929" → "sonnet 4.5"
model_name_raw="$model_display"
for family in sonnet opus haiku; do
    if [[ "$model_id" == *"$family"* ]]; then
        if [[ "$model_id" =~ $family-([0-9]+)-([0-9]+) ]]; then
            model_name_raw="$family ${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
        elif [[ "$model_id" =~ $family-([0-9]+) ]]; then
            model_name_raw="$family ${BASH_REMATCH[1]}"
        else
            model_name_raw="$family"
        fi
        break
    fi
done
model_name="${GRAY}${model_name_raw}${RESET}"

# ============================================
# Get REAL usage from Anthropic API
# ============================================
usage_display=""

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
    weekly_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
    extra_enabled=$(echo "$usage_json" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
    extra_utilization=$(echo "$usage_json" | jq -r '.extra_usage.utilization // empty' 2>/dev/null)
    extra_used=$(echo "$usage_json" | jq -r '.extra_usage.used_credits // empty' 2>/dev/null)
    extra_limit=$(echo "$usage_json" | jq -r '.extra_usage.monthly_limit // empty' 2>/dev/null)

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

        # Add error indicator if API is failing
        error_indicator=""
        if [ "$api_error" = true ]; then
            error_indicator="${RED}[!]${RESET} "
        fi

        # Calculate daily reset time and build daily display
        daily_reset_str=""
        if [ "$MOO_HIDE_RESET" != "1" ] && [ -n "$five_hour_reset" ]; then
            if [ "$OS_TYPE" = "Darwin" ]; then
                daily_reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${five_hour_reset%%.*}" +%s 2>/dev/null)
            else
                daily_reset_epoch=$(date -d "${five_hour_reset}" +%s 2>/dev/null)
            fi
            now_epoch=$(date +%s)

            if [ -n "$daily_reset_epoch" ]; then
                seconds_until=$((daily_reset_epoch - now_epoch))

                if [ $seconds_until -le 0 ]; then
                    rm -f "$CACHE_FILE" 2>/dev/null
                    daily_reset_str=" ${DARK_GREEN}↺${RESET} ${GRAY}refreshing...${RESET}"
                else
                    hours=$((seconds_until / 3600))
                    minutes=$(((seconds_until % 3600) / 60))

                    # Extract time components
                    if [ "$OS_TYPE" = "Darwin" ]; then
                        reset_hour=$(LC_TIME=C date -r "$daily_reset_epoch" "+%-I" 2>/dev/null)
                        reset_min=$(LC_TIME=C date -r "$daily_reset_epoch" "+%M" 2>/dev/null)
                        reset_ampm=$(LC_TIME=C date -r "$daily_reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
                    else
                        reset_hour=$(LC_TIME=C date -d "@$daily_reset_epoch" "+%-I" 2>/dev/null)
                        reset_min=$(LC_TIME=C date -d "@$daily_reset_epoch" "+%M" 2>/dev/null)
                        reset_ampm=$(LC_TIME=C date -d "@$daily_reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
                    fi

                    # Round :59 to next hour
                    if [ "$reset_min" = "59" ]; then
                        reset_hour=$((reset_hour + 1))
                        if [ $reset_hour -eq 12 ]; then
                            if [ "$reset_ampm" = "pm" ]; then reset_ampm="am"; else reset_ampm="pm"; fi
                        elif [ $reset_hour -eq 13 ]; then
                            reset_hour=1
                            if [ "$reset_ampm" = "pm" ]; then reset_ampm="am"; else reset_ampm="pm"; fi
                        fi
                        if [ $reset_hour -eq 12 ]; then
                            if [ "$reset_ampm" = "am" ]; then reset_time_str="midnight"; else reset_time_str="midday"; fi
                        else
                            reset_time_str="${reset_hour}${reset_ampm}"
                        fi
                    elif [ "$reset_min" = "00" ]; then
                        if [ $reset_hour -eq 12 ]; then
                            if [ "$reset_ampm" = "am" ]; then reset_time_str="midnight"; else reset_time_str="midday"; fi
                        else
                            reset_time_str="${reset_hour}${reset_ampm}"
                        fi
                    else
                        reset_time_str="${reset_hour}:${reset_min}${reset_ampm}"
                    fi

                    # Color based on time remaining
                    total_minutes=$((hours * 60 + minutes))
                    if [ $total_minutes -lt 15 ]; then
                        time_color="$GREEN"
                    else
                        time_color="$GRAY"
                    fi

                    daily_reset_str=" ${DARK_GREEN}↺${RESET}${time_color}${reset_time_str}.${hours}h${minutes}m${RESET}"
                fi
            fi
        fi

        # Build weekly display (percentage always, reset info only when >=85%)
        weekly_display=""
        if [ "$MOO_HIDE_WEEKLY" != "1" ] && [ -n "$weekly_pct" ] && [ "$weekly_pct" != "null" ]; then
            weekly_int=${weekly_pct%.*}
            [ -z "$weekly_int" ] && weekly_int=0

            weekly_reset_str=""
            # Show weekly reset info only when usage >= 85%
            if [ $weekly_int -ge 85 ] && [ -n "$weekly_reset" ] && [ "$weekly_reset" != "null" ]; then
                if [ "$OS_TYPE" = "Darwin" ]; then
                    weekly_reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${weekly_reset%%.*}" +%s 2>/dev/null)
                else
                    weekly_reset_epoch=$(date -d "${weekly_reset}" +%s 2>/dev/null)
                fi

                if [ -n "$weekly_reset_epoch" ]; then
                    now_epoch=$(date +%s)
                    seconds_until=$((weekly_reset_epoch - now_epoch))

                    if [ $seconds_until -gt 0 ]; then
                        days=$((seconds_until / 86400))
                        hours=$(((seconds_until % 86400) / 3600))
                        minutes=$(((seconds_until % 3600) / 60))

                        # Get date and time for weekly reset
                        if [ "$OS_TYPE" = "Darwin" ]; then
                            weekly_date=$(LC_TIME=C date -r "$weekly_reset_epoch" "+%-d%b" 2>/dev/null)
                            weekly_hour=$(LC_TIME=C date -r "$weekly_reset_epoch" "+%-I" 2>/dev/null)
                            weekly_min=$(LC_TIME=C date -r "$weekly_reset_epoch" "+%M" 2>/dev/null)
                            weekly_ampm=$(LC_TIME=C date -r "$weekly_reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
                        else
                            weekly_date=$(LC_TIME=C date -d "@$weekly_reset_epoch" "+%-d%b" 2>/dev/null)
                            weekly_hour=$(LC_TIME=C date -d "@$weekly_reset_epoch" "+%-I" 2>/dev/null)
                            weekly_min=$(LC_TIME=C date -d "@$weekly_reset_epoch" "+%M" 2>/dev/null)
                            weekly_ampm=$(LC_TIME=C date -d "@$weekly_reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
                        fi

                        # Round :59 to next hour for weekly time
                        if [ "$weekly_min" = "59" ]; then
                            weekly_hour=$((weekly_hour + 1))
                            if [ $weekly_hour -eq 12 ]; then
                                if [ "$weekly_ampm" = "pm" ]; then weekly_ampm="am"; else weekly_ampm="pm"; fi
                            elif [ $weekly_hour -eq 13 ]; then
                                weekly_hour=1
                                if [ "$weekly_ampm" = "pm" ]; then weekly_ampm="am"; else weekly_ampm="pm"; fi
                            fi
                            if [ $weekly_hour -eq 12 ]; then
                                if [ "$weekly_ampm" = "am" ]; then weekly_time_str="midnight"; else weekly_time_str="midday"; fi
                            else
                                weekly_time_str="${weekly_hour}${weekly_ampm}"
                            fi
                        elif [ "$weekly_min" = "00" ]; then
                            if [ $weekly_hour -eq 12 ]; then
                                if [ "$weekly_ampm" = "am" ]; then weekly_time_str="midnight"; else weekly_time_str="midday"; fi
                            else
                                weekly_time_str="${weekly_hour}${weekly_ampm}"
                            fi
                        else
                            weekly_time_str="${weekly_hour}:${weekly_min}${weekly_ampm}"
                        fi

                        # Build countdown string with days
                        if [ $days -gt 0 ]; then
                            countdown_str="${days}d${hours}h${minutes}m"
                        else
                            countdown_str="${hours}h${minutes}m"
                        fi

                        weekly_reset_str=" ${DARK_GREEN}↺${RESET} ${GRAY}${weekly_date}${weekly_time_str}.${countdown_str}${RESET}"
                    fi
                fi
            fi

            weekly_display="  ${GRAY}w:${weekly_int}%${weekly_reset_str}${RESET}"
        fi

        # Build extra usage display when 5h is at 100% and extra usage is enabled
        extra_display=""
        if [ $pct_int -ge 100 ] && [ "$extra_enabled" = "true" ] && [ -n "$extra_utilization" ]; then
            extra_int=${extra_utilization%.*}
            [ -z "$extra_int" ] && extra_int=0

            # Build extra usage progress bar
            extra_filled=$((extra_int / 10))
            extra_empty=$((10 - extra_filled))
            [ $extra_filled -gt 10 ] && extra_filled=10 && extra_empty=0
            [ $extra_filled -lt 0 ] && extra_filled=0 && extra_empty=10

            extra_bar=""
            for ((i=0; i<extra_filled; i++)); do extra_bar+="█"; done
            for ((i=0; i<extra_empty; i++)); do extra_bar+="░"; done

            # Format dollar amounts using awk to avoid locale issues
            extra_used_fmt=$(LC_ALL=C awk "BEGIN{printf \"\$%.2f\", $extra_used/100}")
            extra_limit_fmt=$(LC_ALL=C awk "BEGIN{printf \"\$%.2f\", $extra_limit/100}")

            extra_display="${LIGHT_ORANGE}[${extra_bar}]${RESET} ${GRAY}extra:${extra_int}% used ${extra_used_fmt}/${extra_limit_fmt}${RESET}${DARK_GRAY} | ${RESET}"
        fi

        if [ -n "$extra_display" ]; then
            # Extra usage mode: show extra bar first, then 5h without bar
            usage_display="${error_indicator}${extra_display}${GRAY}5h:${pct_int}% used${RESET}${daily_reset_str}${weekly_display}"
        else
            usage_display="${error_indicator}${bar_color}[${bar}]${RESET} ${GRAY}5h:${pct_int}% used${RESET}${daily_reset_str}${weekly_display}"
        fi
    fi
fi

# Fallback if API failed
if [ -z "$usage_display" ]; then
    usage_display="${GRAY}[░░░░░░░░░░] --% ${DARK_GREEN}↺${RESET} ${GRAY}--${RESET}"
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

    # Detect if auto-compact is disabled via project or global settings
    auto_compact_disabled=false
    if [ -n "$project_dir" ] && [ "$project_dir" != "null" ]; then
        project_compact=$(jq -r 'if has("autoCompact") then .autoCompact | tostring else "unset" end' "$project_dir/.claude/settings.json" 2>/dev/null)
        [ "$project_compact" = "false" ] && auto_compact_disabled=true
    fi
    if [ "$auto_compact_disabled" = false ]; then
        global_compact=$(jq -r 'if has("autoCompact") then .autoCompact | tostring else "unset" end' "$HOME/.claude/settings.json" 2>/dev/null)
        [ "$global_compact" = "false" ] && auto_compact_disabled=true
    fi

    # Convert to k format
    current_k=$((current_total / 1000))
    window_k=$((window_size / 1000))

    if [ "$auto_compact_disabled" = true ]; then
        # No auto-compact: show current/max
        remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // 50')
        remaining_pct_int=${remaining_pct%.*}
        [ -z "$remaining_pct_int" ] && remaining_pct_int=50

        if [ $remaining_pct_int -le 5 ]; then
            ctx_color="$RED"
        elif [ $remaining_pct_int -le 15 ]; then
            ctx_color="$DARK_ORANGE"
        else
            ctx_color="$GRAY"
        fi

        context_display="${GRAY}⛁ ${ctx_color}${current_k}k/${window_k}k${RESET}"

        if [ $remaining_pct_int -le 5 ] && [ $remaining_pct_int -gt 0 ]; then
            remaining_k=$((window_k - current_k))
            context_display="${context_display} ${RED}${remaining_k}k left${RESET}"
        fi
    else
        # Auto-compact enabled: show current/compact(max)
        # Claude Code triggers auto-compact at window_size - 45K
        compact_threshold=$((window_size - 45000))
        compact_k=$(( (compact_threshold + 500) / 1000 ))

        remaining_k=$((compact_k - current_k))
        if [ $remaining_k -le 10 ]; then
            ctx_color="$RED"
        elif [ $remaining_k -le 20 ]; then
            ctx_color="$DARK_ORANGE"
        else
            ctx_color="$GRAY"
        fi

        context_display="${GRAY}⛁ ${ctx_color}${current_k}k/${compact_k}k${DARK_GRAY}(${window_k}k)${RESET}"

        if [ $remaining_k -le 5 ] && [ $remaining_k -gt 0 ]; then
            context_display="${context_display} ${RED}${remaining_k}k left${RESET}"
        fi
    fi
fi

# Output
PIPE="${DARK_GRAY} | ${RESET}"
printf "%s%s%s" "$git_info" "$PIPE" "$model_name"

if [ -n "$context_display" ]; then
    printf "%s%s" "$PIPE" "$context_display"
fi

printf "%s%s" "$PIPE" "$usage_display"
