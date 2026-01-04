# Moo Statusline for Claude Code

A beautiful, informative statusline for Claude Code CLI that shows your project, git branch, model, context usage, and **real-time rate limit tracking** via the Anthropic API.

## Features

- 🌿 **Git Integration** - Shows project name and current branch (highlighted in green)
- 🤖 **Model Display** - Simplified model names (sonnet 4.5, opus 4.5, haiku, etc.)
- 📊 **Context Tracking** - Shows current usage vs auto-compact threshold (e.g., `⛁ 97k/170k`)
- ⚡ **Live Rate Limit Data** - Real 5-hour usage from Anthropic API with visual progress bar
- ⏰ **Smart Reset Timer** - Displays next reset time and countdown (e.g., `↺ 9pm 1h43m`)
- 🎨 **Color-Coded Warnings** - Orange/red alerts when context or rate limits are high
- 📈 **Weekly Usage** - Optional 7-day usage percentage when available

## What It Looks Like

```
repo 🌿 main | sonnet 4.5 | ⛁ 97k/170k | [██░░░░░░░░] 5h:24% used ↺ 9pm 1h43m
```

**Breakdown:**
- `repo 🌿 main` - Project name + git branch (branch in green #74BE33)
- `sonnet 4.5` - Current model (simplified from full model ID)
- `⛁ 97k/170k` - Current context usage / auto-compact threshold (always shown)
  - Turns orange at 70%, red at 85%
  - Shows `left:X%` warning when <10% remaining
- `[██░░░░░░░░] 5h:24% used` - 5-hour rate limit usage from Anthropic API
  - Visual bar + percentage
  - Gray: <50%, Yellow: 50-79%, Red: ≥80%
  - Shows `w:3%` if weekly data is available
- `↺ 9pm 1h43m` - Next reset time + countdown
  - Icon in dark green (#357500)
  - Clean time format: `9pm` not `9:00pm`

## Installation

### Plugin Install (Recommended)

```bash
# 1. Add the plugin to Claude Code
claude plugins add github:moogento/moo-statusline

# 2. Run the setup command
/statusline

# 3. Restart Claude Code
```

### Quick Install

```bash
# 1. Download the statusline script
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/moogento/moo-statusline/main/statusline.sh
chmod +x ~/.claude/statusline.sh

# 2. Add to your Claude Code settings
# Edit ~/.claude/settings.json (global) or .claude/settings.json (project-specific)
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}

# 3. Restart Claude Code
```

### Manual Install

1. **Copy the script:**
   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. **Configure Claude Code:**

   Edit `~/.claude/settings.json` (for global settings) or `.claude/settings.json` (for project-specific settings):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     }
   }
   ```

3. **Restart Claude Code** to see the statusline in action.

## Requirements

- **Claude Code CLI** (version 2.0.76 or later)
- **macOS** (for OAuth token retrieval via Keychain)
- **jq** - JSON processor (install with: `brew install jq`)
- **Git** (for branch display)
- **Bash** shell
- **Active Claude Code session** (must be logged in for API access)

## Customization

### Colors

The statusline uses RGB color codes. You can customize these in the script:

```bash
GRAY=$'\033[38;2;121;121;122m'          # #79797A - Main text
DARK_GRAY=$'\033[38;2;74;74;74m'        # #4A4A4A - Pipe separators
GREEN=$'\033[38;2;116;190;51m'          # #74BE33 - Git branch
DARK_GREEN=$'\033[38;2;53;117;0m'       # #357500 - Reset icon (↺)
YELLOW=$'\033[38;2;255;193;7m'          # #FFC107 - Rate limit warning (50-79%)
DARK_ORANGE=$'\033[38;2;204;122;0m'     # #CC7A00 - Context warning (70-84%)
RED=$'\033[38;2;255;82;82m'             # #FF5252 - Critical (≥80% rate limit, ≥85% context)
```

### Auto-Compact Threshold

Default is 85% of context window. Adjust in the script:

```bash
compact_threshold=$((window_size * 85 / 100))  # Change 85 to your preferred %
```

### API Cache Duration

The script caches Anthropic API responses for 30 seconds to avoid rate limits. Adjust if needed:

```bash
CACHE_MAX_AGE=30  # seconds
```

## How It Works

The statusline script:

1. **Receives JSON input** from Claude Code via stdin (model info, workspace, context usage)
2. **Detects git branch** if in a git repository
3. **Fetches real usage data** from Anthropic OAuth API:
   - Retrieves OAuth token from macOS Keychain (`security find-generic-password`)
   - Calls `https://api.anthropic.com/api/oauth/usage` for live rate limit data
   - Caches results for 30 seconds to avoid API rate limits
4. **Parses API response** for:
   - `five_hour.utilization` - Current 5-hour usage percentage
   - `five_hour.resets_at` - UTC timestamp of next reset
   - `seven_day.utilization` - Weekly usage (if available)
5. **Calculates context usage**:
   - Shows current tokens vs auto-compact threshold (85% of window)
   - Converts to k format (e.g., `97k/170k`)
   - Color-codes based on usage level
6. **Formats reset time**:
   - Parses UTC timestamp and converts to local time
   - Shows clean format: `9pm` instead of `9:00pm`
   - Rounds `:59` minutes up to next hour for clarity
7. **Outputs colored statusline** with ANSI RGB codes

Claude Code refreshes the statusline automatically every ~300ms.

## Troubleshooting

### Statusline not showing?

1. **Check script exists and is executable:**
   ```bash
   ls -la ~/.claude/statusline.sh
   ```
   Should show: `-rwxr-xr-x`

2. **Test the script manually:**
   ```bash
   echo '{"model":{"display_name":"Sonnet","id":"claude-sonnet-4-5"},"workspace":{"current_dir":"'$PWD'"}}' | ~/.claude/statusline.sh
   ```

3. **Verify settings.json syntax:**
   ```bash
   cat ~/.claude/settings.json | jq .
   ```

4. **Check jq is installed:**
   ```bash
   which jq
   ```

5. **Restart Claude Code completely**

### Rate limit showing as `[░░░░░░░░░░] --%`?

This means the API call is failing. Check:

1. **Verify you're logged in to Claude Code:**
   ```bash
   claude status
   ```

2. **Check OAuth token is accessible:**
   ```bash
   security find-generic-password -s "Claude Code-credentials" -w
   ```
   Should return JSON with OAuth credentials.

3. **Test API access manually:**
   ```bash
   # Get token
   TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | jq -r '.claudeAiOauth.accessToken')

   # Test API
   curl -s "https://api.anthropic.com/api/oauth/usage" \
     -H "Authorization: Bearer $TOKEN" \
     -H "anthropic-beta: oauth-2025-04-20"
   ```

4. **Check cache file:**
   ```bash
   cat /tmp/claude-usage-cache.json
   ```
   If corrupted, delete it: `rm /tmp/claude-usage-cache.json`

### Reset time showing wrong timezone?

The script uses `TZ=UTC` for parsing and `LC_TIME=C` for formatting. If times are still wrong, verify your system timezone:
```bash
date +%Z
```

### Escape codes showing as literal text?

Your terminal or Claude Code version may not support ANSI escape sequences. Try removing the color codes or updating to the latest Claude Code version.

## Contributing

Contributions welcome! Feel free to:

- Report bugs via issues
- Submit pull requests for improvements
- Share your customizations
- Suggest new features

## License

MIT License - Feel free to use, modify, and distribute.

## Credits

Created for the Claude Code community. Inspired by the need for better context awareness and rate limit tracking.

---

**Tips:**
- The statusline updates automatically as you work (~300ms refresh)
- Watch `⛁` values turn orange/red to know when auto-compact is approaching
- Monitor the 5-hour rate limit bar to pace your usage
- Dark green `↺` icon marks the reset timer
- Weekly usage (`w:X%`) helps track longer-term patterns
- Cache refreshes every 30 seconds to keep data current without hammering the API
- Times are shown cleanly: `9pm` instead of `9:00pm`, `:59` rounds to next hour
