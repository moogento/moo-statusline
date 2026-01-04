---
description: Uninstall moo-statusline from Claude Code
allowed-tools: Bash(*), Read, Edit
---

# Uninstall Moo Statusline

Remove moo-statusline from Claude Code. Recognizes: `/uninstall`, `self-uninstall`

## Steps

1. Remove the statusline script:
```bash
rm -f ~/.claude/statusline.sh
```

2. Read `~/.claude/settings.json` and remove the `statusLine` key while preserving all other settings. Use jq or careful editing.

3. Confirm removal:
```bash
ls ~/.claude/statusline.sh 2>/dev/null || echo "Script removed"
cat ~/.claude/settings.json | jq 'has("statusLine")'
```

4. Tell the user:
   - Moo-statusline has been uninstalled
   - Restart Claude Code to see the default statusline
   - They can reinstall anytime with `/statusline`
