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
GRAY=$'\033[38;2;121;121;122m'  # #79797A for all text except branch
DARK_GRAY=$'\033[38;2;74;74;74m'  # #4A4A4A for pipe characters
GREEN=$'\033[38;2;116;190;51m'  # #74BE33 for branch
RESET=$'\033[0m'

# Git branch info
git_info="${GRAY}${project_name}${RESET}"
if [ -d "$cwd/.git" ]; then
    git_branch=$(cd "$cwd" 2>/dev/null && git -c core.fileMode=false rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        git_info="${GRAY}${project_name} 🌿 ${GREEN}${git_branch}${RESET}"
    fi
fi

# Simplify model name and apply gray color
model_name_raw="$model_display"
if [[ "$model_id" == *"sonnet"* ]]; then
    if [[ "$model_id" == *"4"* ]]; then
        model_name_raw="sonnet 4"
    elif [[ "$model_id" == *"3-7"* ]]; then
        model_name_raw="sonnet 3.7"
    elif [[ "$model_id" == *"3-5"* ]] || [[ "$model_display" == *"3.5"* ]]; then
        model_name_raw="sonnet 3.5"
    else
        model_name_raw="sonnet"
    fi
elif [[ "$model_id" == *"opus"* ]]; then
    if [[ "$model_id" == *"4"* ]]; then
        model_name_raw="opus 4"
    elif [[ "$model_id" == *"3"* ]]; then
        model_name_raw="opus 3"
    else
        model_name_raw="opus"
    fi
elif [[ "$model_id" == *"haiku"* ]]; then
    if [[ "$model_id" == *"3-5"* ]] || [[ "$model_display" == *"3.5"* ]]; then
        model_name_raw="haiku 3.5"
    elif [[ "$model_id" == *"3"* ]]; then
        model_name_raw="haiku 3"
    else
        model_name_raw="haiku"
    fi
fi
model_name="${GRAY}${model_name_raw}${RESET}"

# Context window usage
context_window=$(echo "$input" | jq ".context_window")
window_size=$(echo "$context_window" | jq -r ".context_window_size // 200000")
current_usage=$(echo "$context_window" | jq ".current_usage")

usage_display=""
if [ "$current_usage" != "null" ]; then
    input_tokens=$(echo "$current_usage" | jq -r ".input_tokens // 0")
    output_tokens=$(echo "$current_usage" | jq -r ".output_tokens // 0")
    cache_creation=$(echo "$current_usage" | jq -r ".cache_creation_input_tokens // 0")
    cache_read=$(echo "$current_usage" | jq -r ".cache_read_input_tokens // 0")

    current_total=$((input_tokens + output_tokens + cache_creation + cache_read))

    if [ $window_size -gt 0 ] && [ $current_total -gt 0 ]; then
        pct_used=$((current_total * 100 / window_size))
        pct_remaining=$((100 - pct_used))
        filled=$((pct_used / 10))
        empty=$((10 - filled))

        bar=""
        for ((i=0; i<filled; i++)); do
            bar="${bar}█"
        done
        for ((i=0; i<empty; i++)); do
            bar="${bar}░"
        done

        # Auto-compact threshold (85% of window size)
        compact_threshold=$((window_size * 85 / 100))
        remaining_to_compact=$((compact_threshold - current_total))

        # Convert to k format
        remaining_k=$((remaining_to_compact / 1000))
        compact_threshold_k=$((compact_threshold / 1000))

        usage_display="${GRAY}${remaining_k}k/${compact_threshold_k}k ${DARK_GRAY}|${GRAY} [${bar}] ${pct_remaining}%${RESET}"
    fi
fi

# Reset time calculation
current_hour=$(date +%H)
current_min=$(date +%M)

if [ $current_hour -lt 5 ]; then
    reset_hour=5
elif [ $current_hour -lt 10 ]; then
    reset_hour=10
elif [ $current_hour -lt 15 ]; then
    reset_hour=15
elif [ $current_hour -lt 20 ]; then
    reset_hour=20
else
    reset_hour=5
fi

now_epoch=$(date +%s)

if [ $reset_hour -le $current_hour ] && [ $reset_hour -eq 5 ] && [ $current_hour -ge 20 ]; then
    reset_epoch=$(date -v+1d -v${reset_hour}H -v0M -v0S +%s 2>/dev/null || date -d "tomorrow ${reset_hour}:00" +%s 2>/dev/null)
else
    reset_epoch=$(date -v${reset_hour}H -v0M -v0S +%s 2>/dev/null || date -d "today ${reset_hour}:00" +%s 2>/dev/null)
fi

seconds_until=$((reset_epoch - now_epoch))
if [ $seconds_until -lt 0 ]; then
    seconds_until=$((seconds_until + 86400))
fi

hours=$((seconds_until / 3600))
minutes=$(((seconds_until % 3600) / 60))

if [ $reset_hour -eq 5 ]; then
    reset_time="5am"
elif [ $reset_hour -eq 10 ]; then
    reset_time="10am"
elif [ $reset_hour -eq 15 ]; then
    reset_time="3pm"
elif [ $reset_hour -eq 20 ]; then
    reset_time="8pm"
fi

reset_display="${GRAY}♻️ ${reset_time} ${hours}h${minutes}m${RESET}"

# Output final status line
PIPE="${DARK_GRAY} | ${RESET}"
if [ -n "$usage_display" ]; then
    printf "%s%s%s%s%s %s" "$git_info" "$PIPE" "$model_name" "$PIPE" "$usage_display" "$reset_display"
else
    printf "%s%s%s%s%s" "$git_info" "$PIPE" "$model_name" "$PIPE" "$reset_display"
fi