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
    elif [[ "$model_id" == *"3-7"* ]]; then
        model_name_raw="sonnet 3.7"
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

# Context window (for auto-compact warning)
context_window=$(echo "$input" | jq ".context_window")
window_size=$(echo "$context_window" | jq -r ".context_window_size // 200000")
current_usage=$(echo "$context_window" | jq ".current_usage")

context_display=""
if [ "$current_usage" != "null" ]; then
    input_tokens=$(echo "$current_usage" | jq -r ".input_tokens // 0")
    output_tokens=$(echo "$current_usage" | jq -r ".output_tokens // 0")
    cache_creation=$(echo "$current_usage" | jq -r ".cache_creation_input_tokens // 0")
    cache_read=$(echo "$current_usage" | jq -r ".cache_read_input_tokens // 0")
    current_total=$((input_tokens + output_tokens + cache_creation + cache_read))
    
    compact_threshold=$((window_size * 85 / 100))
    remaining_k=$((( compact_threshold - current_total ) / 1000))
    compact_threshold_k=$((compact_threshold / 1000))
    
    context_display="${GRAY}ctx:${remaining_k}k/${compact_threshold_k}k${RESET}"
fi

# 5-hour block info from ccusage (the accurate source)
block_display=""
if command -v npx &> /dev/null; then
    # Get block info - ccusage reads the actual JSONL logs (get active block)
    block_json=$(npx -y ccusage@latest blocks --json 2>/dev/null | jq -r '.blocks[] | select(.isActive == true)' 2>/dev/null)
    
    if [ -n "$block_json" ]; then
        # Extract block data
        block_start=$(echo "$block_json" | jq -r '.startTime // empty')
        total_cost=$(echo "$block_json" | jq -r '.costUSD // 0')
        
        if [ -n "$block_start" ]; then
            # Calculate time remaining in 5-hour window
            start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${block_start%.*}" +%s 2>/dev/null || \
                          date -d "${block_start}" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            elapsed=$((now_epoch - start_epoch))
            remaining=$((18000 - elapsed))  # 5 hours = 18000 seconds
            
            if [ $remaining -gt 0 ]; then
                hours=$((remaining / 3600))
                minutes=$(((remaining % 3600) / 60))
                
                # Color based on time remaining
                if [ $hours -lt 1 ]; then
                    time_color="$RED"
                elif [ $hours -lt 2 ]; then
                    time_color="$YELLOW"
                else
                    time_color="$GRAY"
                fi
                
                block_display="${time_color}♻️ ${hours}h${minutes}m${RESET}"
            else
                block_display="${GREEN}♻️ reset${RESET}"
            fi
        fi
    fi
fi

# Fallback if ccusage failed
if [ -z "$block_display" ]; then
    block_display="${GRAY}♻️ --${RESET}"
fi

# Output
PIPE="${DARK_GRAY} | ${RESET}"
printf "%s%s%s" "$git_info" "$PIPE" "$model_name"

if [ -n "$context_display" ]; then
    printf "%s%s" "$PIPE" "$context_display"
fi

printf "%s%s" "$PIPE" "$block_display"
