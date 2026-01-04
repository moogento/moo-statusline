---
description: Update moo-statusline to the latest version
allowed-tools: Bash(*), Read, Write, Glob
---

# Update Moo Statusline

Update moo-statusline to the latest version from the plugin. Recognizes: `/update`, `self-update`

## Steps

1. Find the plugin's `statusline.sh` using Glob to search for `**/moo-statusline/statusline.sh` or similar patterns.

2. Copy the updated script:
```bash
cp <path-to-plugin-statusline.sh> ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

3. Verify the update:
```bash
ls -la ~/.claude/statusline.sh
head -20 ~/.claude/statusline.sh
```

4. Tell the user:
   - Moo-statusline has been updated
   - Restart Claude Code to use the new version
   - Show any new features if the script header mentions them
