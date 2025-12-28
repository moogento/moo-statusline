# Publishing moo-statusline to GitHub

## Step 1: Create the Repository on GitHub

1. Go to https://github.com/new
2. Repository name: `moo-statusline`
3. Description: "Beautiful statusline for Claude Code with git, context tracking, and rate limits"
4. Public repository
5. **Do NOT** initialize with README (we already have one)
6. Click "Create repository"

## Step 2: Initialize and Push

From this directory (`.temp/moo-statusline/`):

```bash
# Navigate to the directory
cd /Users/senor2/repos/m2-moo/.temp/moo-statusline

# Initialize git
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit: Moo statusline for Claude Code

- Custom statusline with git branch, model, and context tracking
- Shows tokens remaining before auto-compact
- Rate limit reset timer
- Custom colors: green branch, dark grey pipes"

# Add your GitHub repository as remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/moo-statusline.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Step 3: Add a Screenshot (Optional but Recommended)

1. Take a screenshot of your statusline in Claude Code
2. Save it as `screenshot.png` in this directory
3. Delete `screenshot-placeholder.txt`
4. Commit and push:
   ```bash
   git add screenshot.png
   git rm screenshot-placeholder.txt
   git commit -m "Add statusline screenshot"
   git push
   ```

## Step 4: Add Topics/Tags on GitHub

On your repository page, click "Add topics" and add:
- `claude-code`
- `statusline`
- `cli`
- `productivity`
- `terminal`
- `git`
- `bash`

## Step 5: Share It!

Once published, share the installation link:

```bash
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/YOUR_USERNAME/moo-statusline/main/statusline.sh
chmod +x ~/.claude/statusline.sh
```

## Optional Enhancements

### Add to Claude Code Marketplace/Community
- Share on Claude Code Discord/community forums
- Submit to any Claude Code statusline collections

### Create a GitHub Release
```bash
git tag v1.0.0
git push origin v1.0.0
```

Then create a release on GitHub with release notes.

### Update README with Your GitHub Username
Replace `YOUR_USERNAME` in README.md with your actual GitHub username.
