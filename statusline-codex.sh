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

# Extract basic info (try multiple keys to be resilient)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir? // .path // empty')
model_id=$(echo "$input" | jq -r '(.model.id? // .model? // empty) | if type=="string" then . else empty end')
model_display=$(echo "$input" | jq -r '(.model.display_name? // .model_display_name? // empty) | if type=="string" then . else empty end')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir? // .project_dir? // empty')

if [ -z "$cwd" ] || [ "$cwd" = "null" ]; then
    cwd=$(pwd)
fi

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
DARK_GREEN=$'\033[38;2;53;117;0m'
YELLOW=$'\033[38;2;255;193;7m'
DARK_ORANGE=$'\033[38;2;204;122;0m'
RED=$'\033[38;2;255;82;82m'
RESET=$'\033[0m'

# Git branch info
git_info="${GRAY}${project_name}${RESET}"
if [ "$MOO_HIDE_GIT" != "1" ] && [ -n "$cwd" ]; then
    if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$git_branch" ]; then
            git_info="${GRAY}${project_name} 🌿 ${GREEN}${git_branch}${RESET}"
        fi
    fi
fi

# Simplify model name
model_name_raw=""
if [ -n "$model_display" ] && [ "$model_display" != "null" ]; then
    model_name_raw="$model_display"
else
    model_name_raw="$model_id"
fi
if [ -n "$model_name_raw" ]; then
    model_name_raw="${model_name_raw%-codex}"
fi
model_name="${GRAY}${model_name_raw:-model}${RESET}"

# ============================================
# Usage and rate limits (from Codex JSON input)
# ============================================
usage_display=""
reset_display=""
weekly_display=""

# Context usage
context_display=""
current_total=""
window_size=""
if [ "$MOO_HIDE_CONTEXT" != "1" ]; then
    current_total=$(echo "$input" | jq -r ".context_window.current_usage.total_tokens // .info.last_token_usage.total_tokens // empty")
    window_size=$(echo "$input" | jq -r ".info.model_context_window // empty")

    if [ -z "$current_total" ] || [ "$current_total" = "null" ]; then
        input_tokens=$(echo "$input" | jq -r ".info.last_token_usage.input_tokens // .context_window.current_usage.input_tokens // 0")
        cached_tokens=$(echo "$input" | jq -r ".info.last_token_usage.cached_input_tokens // .context_window.current_usage.cache_creation_input_tokens // 0")
        cache_read=$(echo "$input" | jq -r ".context_window.current_usage.cache_read_input_tokens // 0")
        output_tokens=$(echo "$input" | jq -r ".info.last_token_usage.output_tokens // 0")
        reasoning_tokens=$(echo "$input" | jq -r ".info.last_token_usage.reasoning_output_tokens // 0")
        current_total=$((input_tokens + cached_tokens + cache_read + output_tokens + reasoning_tokens))
    fi

    if [ -z "$window_size" ] || [ "$window_size" = "null" ]; then
        window_size=$(echo "$input" | jq -r ".context_window.context_window_size // .context_window.window_size // empty")
    fi
fi

if [ "$MOO_HIDE_CONTEXT" != "1" ] && [ -n "$current_total" ] && [ -n "$window_size" ] && [ "$window_size" -gt 0 ]; then
    current_k=$((current_total / 1000))
    window_k=$((window_size / 1000))
    usage_pct=$((current_total * 100 / window_size))
    remaining_pct=$((100 - usage_pct))

    if [ $usage_pct -ge 85 ]; then
        ctx_color="$RED"
    elif [ $usage_pct -ge 70 ]; then
        ctx_color="$DARK_ORANGE"
    else
        ctx_color="$GRAY"
    fi

    context_display="${GRAY}⛁ ${ctx_color}${current_k}k/${window_k}k${RESET}"
    if [ $remaining_pct -le 10 ] && [ $remaining_pct -gt 0 ]; then
        context_display="${context_display} ${RED}left:${remaining_pct}%${RESET}"
    fi
fi

# Rate limit usage
primary_pct=$(echo "$input" | jq -r ".rate_limits.primary.used_percent // empty")
primary_window_min=$(echo "$input" | jq -r ".rate_limits.primary.window_minutes // empty")
primary_reset=$(echo "$input" | jq -r ".rate_limits.primary.resets_at // empty")
weekly_pct=$(echo "$input" | jq -r ".rate_limits.secondary.used_percent // empty")

if [ -n "$primary_pct" ] && [ "$primary_pct" != "null" ]; then
    pct_int=${primary_pct%.*}
    [ -z "$pct_int" ] && pct_int=0

    filled=$((pct_int / 10))
    empty=$((10 - filled))
    [ $filled -gt 10 ] && filled=10 && empty=0
    [ $filled -lt 0 ] && filled=0 && empty=10

    bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    if [ $pct_int -ge 80 ]; then
        bar_color="$RED"
    elif [ $pct_int -ge 50 ]; then
        bar_color="$YELLOW"
    else
        bar_color="$GRAY"
    fi

    window_label="rl"
    if [ -n "$primary_window_min" ] && [ "$primary_window_min" != "null" ] && [ "$primary_window_min" -gt 0 ]; then
        if [ $((primary_window_min % 60)) -eq 0 ]; then
            window_label="$((primary_window_min / 60))h"
        elif [ "$primary_window_min" -ge 60 ]; then
            window_label="$((primary_window_min / 60))h$((primary_window_min % 60))m"
        else
            window_label="${primary_window_min}m"
        fi
    fi

    if [ "$MOO_HIDE_WEEKLY" != "1" ] && [ -n "$weekly_pct" ] && [ "$weekly_pct" != "null" ]; then
        weekly_int=${weekly_pct%.*}
        [ -z "$weekly_int" ] && weekly_int=0
        weekly_display=" ${GRAY}w:${weekly_int}%${RESET}"
    fi

    usage_display="${bar_color}[${bar}]${RESET} ${GRAY}${window_label}:${pct_int}% used${RESET}"
fi

# Reset display
if [ "$MOO_HIDE_RESET" != "1" ] && [ -n "$primary_reset" ] && [ "$primary_reset" != "null" ]; then
    reset_epoch="$primary_reset"
    now_epoch=$(date +%s)
    seconds_until=$((reset_epoch - now_epoch))

    if [ $seconds_until -le 0 ]; then
        reset_display="${DARK_GREEN}↺${RESET} ${GRAY}refreshing...${RESET}"
    else
        hours=$((seconds_until / 3600))
        minutes=$(((seconds_until % 3600) / 60))

        if [ "$OS_TYPE" = "Darwin" ]; then
            reset_hour=$(LC_TIME=C date -r "$reset_epoch" "+%-I" 2>/dev/null)
            reset_min=$(LC_TIME=C date -r "$reset_epoch" "+%M" 2>/dev/null)
            reset_ampm=$(LC_TIME=C date -r "$reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
        else
            reset_hour=$(LC_TIME=C date -d "@$reset_epoch" "+%-I" 2>/dev/null)
            reset_min=$(LC_TIME=C date -d "@$reset_epoch" "+%M" 2>/dev/null)
            reset_ampm=$(LC_TIME=C date -d "@$reset_epoch" "+%p" 2>/dev/null | tr 'A-Z' 'a-z')
        fi

        if [ "$reset_min" = "59" ]; then
            reset_hour=$((reset_hour + 1))
            if [ $reset_hour -eq 12 ]; then
                if [ "$reset_ampm" = "pm" ]; then
                    reset_ampm="am"
                else
                    reset_ampm="pm"
                fi
            elif [ $reset_hour -eq 13 ]; then
                reset_hour=1
                if [ "$reset_ampm" = "pm" ]; then
                    reset_ampm="am"
                else
                    reset_ampm="pm"
                fi
            fi
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
            reset_time_str="${reset_hour}:${reset_min}${reset_ampm}"
        fi

        total_minutes=$((hours * 60 + minutes))
        if [ $total_minutes -lt 15 ]; then
            time_color="$GREEN"
        else
            time_color="$GRAY"
        fi

        reset_display="${DARK_GREEN}↺${RESET}${time_color}${reset_time_str} ${hours}h${minutes}m${RESET}"
    fi
fi

# Fallbacks if data is missing
if [ -z "$usage_display" ]; then
    usage_display="${GRAY}[░░░░░░░░░░] --%${RESET}"
fi
if [ -z "$reset_display" ]; then
    reset_display="${DARK_GREEN}↺${RESET} ${GRAY}--${RESET}"
fi

# Output
PIPE="${DARK_GRAY} | ${RESET}"
printf "%s%s%s" "$git_info" "$PIPE" "$model_name"

if [ -n "$context_display" ]; then
    printf "%s%s" "$PIPE" "$context_display"
fi

printf "%s%s %s%s" "$PIPE" "$usage_display" "$reset_display" "$weekly_display"
