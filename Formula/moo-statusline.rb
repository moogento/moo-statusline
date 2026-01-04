class MooStatusline < Formula
  desc "Beautiful statusline for Claude Code showing git, model, context, and rate limits"
  homepage "https://github.com/moogento/moo-statusline"
  url "https://github.com/moogento/moo-statusline/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"

  depends_on "jq"

  def install
    bin.install "statusline.sh" => "moo-statusline"
  end

  def post_install
    claude_dir = Pathname.new(Dir.home) / ".claude"
    claude_dir.mkpath

    target = claude_dir / "statusline.sh"
    source = bin / "moo-statusline"

    if target.exist?
      ohai "Updating existing #{target}"
    else
      ohai "Installing to #{target}"
    end

    FileUtils.cp(source, target)
    FileUtils.chmod(0755, target)
  end

  def caveats
    <<~EOS
      Moo Statusline has been installed to ~/.claude/statusline.sh

      To activate, add to your ~/.claude/settings.json:

        {
          "statusLine": {
            "type": "command",
            "command": "bash ~/.claude/statusline.sh"
          }
        }

      Then restart Claude Code.

      Requirements:
        - jq (installed as dependency)
        - git (for branch display)
        - Active Claude Code login (for API access)
    EOS
  end

  test do
    assert_match "jq", shell_output("#{bin}/moo-statusline 2>&1", 1)
  end
end
