# Moo Statusline for Claude Code

A beautiful, informative statusline for Claude Code CLI that shows your project, git branch, model, context usage, and rate limit resets.

![Statusline Preview](screenshot.png)

## Features

- 🌿 **Git Integration** - Shows project name and current branch (highlighted in green)
- 🤖 **Model Display** - Simplified model names (sonnet 4, opus 4, haiku 3.5, etc.)
- 📊 **Context Tracking** - Visual progress bar showing context window usage
- ⏰ **Rate Limit Timer** - Countdown to next rate limit reset (5am/10am/3pm/8pm)
- 🎨 **Custom Colors** - Green branch highlight, dark grey pipes, grey text
- 📈 **Smart Metrics** - Shows tokens remaining before auto-compact

## What It Looks Like

```
m2-moo 🌿 main | sonnet 4 | 97k/170k | [███░░░░░░░] 64% ♻️ 8pm 2h37m
```

**Breakdown:**
- `m2-moo 🌿 main` - Project name + git branch (branch in green #74BE33)
- `sonnet 4` - Current model
- `97k/170k` - Tokens remaining / auto-compact threshold
- `[███░░░░░░░] 64%` - Context usage bar + percentage remaining
- `♻️ 8pm 2h37m` - Next rate limit reset time + countdown

## Installation

### Quick Install

```bash
# 1. Download the statusline script
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/moojet/moo-statusline/main/statusline.sh
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

- Claude Code CLI (version 2.0.76 or later)
- `jq` - JSON processor (install with: `brew install jq` on macOS)
- Git (for branch display)
- Bash shell

## Customization

### Colors

The statusline uses RGB color codes. You can customize these in the script:

```bash
GRAY=$'\033[38;2;121;121;122m'     # #79797A - Main text
DARK_GRAY=$'\033[38;2;74;74;74m'   # #4A4A4A - Pipe separators
GREEN=$'\033[38;2;116;190;51m'     # #74BE33 - Git branch
```

### Auto-Compact Threshold

Default is 85% of context window. Adjust in the script:

```bash
compact_threshold=$((window_size * 85 / 100))  # Change 85 to your preferred %
```

### Rate Limit Reset Times

The script calculates next reset based on Anthropic's schedule (5am, 10am, 3pm, 8pm). These are configured around line 96-103.

## How It Works

The statusline script:

1. Receives JSON input from Claude Code via stdin
2. Extracts model info, workspace directory, and context usage
3. Detects git branch if in a git repository
4. Calculates context remaining before auto-compact (default: 85% of window)
5. Shows percentage remaining (not used) for easier mental math
6. Calculates time until next rate limit reset
7. Formats everything with ANSI color codes
8. Outputs a single line to stdout

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
- The statusline updates automatically as you work
- Watch the context percentage to know when auto-compact will happen
- Use the rate limit timer to plan long conversations
- Customize colors to match your terminal theme
