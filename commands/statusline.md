---
description: Install and configure moo-statusline for Claude Code
allowed-tools: Bash(*), Read, Write, Edit, Glob
---

# Install Moo Statusline

Set up the moo-statusline for Claude Code. Follow these steps:

## 1. Check Dependencies

Verify `jq` is installed:
```bash
which jq
```

If not found, tell the user to install it with `brew install jq` (macOS) or their package manager.

## 2. Find and Copy the Script

Find the `statusline.sh` file in this plugin's directory using Glob to search for `**/moo-statusline/statusline.sh` or similar patterns. Then copy it to `~/.claude/statusline.sh`:

```bash
cp <path-to-statusline.sh> ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

## 3. Configure Settings

Read `~/.claude/settings.json` if it exists. Add or update the `statusLine` configuration:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

If the file doesn't exist, create it with the above content. If it exists, merge the `statusLine` key while preserving other settings.

## 4. Verify Installation

Confirm the setup:
```bash
ls -la ~/.claude/statusline.sh
cat ~/.claude/settings.json | jq .statusLine
```

## 5. Complete

Tell the user:
- Installation complete
- Restart Claude Code to see the statusline
- The statusline shows: project name, git branch, model, context usage, and rate limits
