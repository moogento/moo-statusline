#!/bin/bash
# Regression tests for model name + effort dot rendering.
#
# Asserts lit/dim dot counts, never the ANSI-stripped text: lit and dim dots use
# the same ● glyph and differ only by color, so a stripped comparison passes even
# when the scale has silently collapsed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Override to test another copy, e.g. the installed one:
#   MOO_STATUSLINE=~/.claude/statusline.sh bash tests/statusline-test.sh
STATUSLINE="${MOO_STATUSLINE:-$SCRIPT_DIR/statusline.sh}"

LIT=$'\033[38;2;121;121;122m'
DIM=$'\033[38;2;74;74;74m'
LIT_PURPLE=$'\033[38;2;168;85;247m'
DIM_PURPLE=$'\033[38;2;102;52;151m'

pass=0
fail=0

# Isolate from the developer's real settings/env so results are deterministic.
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.claude"
echo '{}' > "$FAKE_HOME/.claude/settings.json"
echo '{}' > "$FAKE_HOME/.claude.json"
trap 'rm -rf "$FAKE_HOME"' EXIT

# render <model_id> [effort_json] -> statusline output
render() {
    local model_id="$1" effort="$2"
    local effort_field=""
    [ -n "$effort" ] && effort_field="\"effort\":{\"level\":\"$effort\"},"
    printf '{"model":{"display_name":"DISPLAY","id":"%s"},%s"workspace":{"current_dir":"%s"}}' \
        "$model_id" "$effort_field" "$SCRIPT_DIR" \
        | HOME="$FAKE_HOME" MOO_HIDE_GIT=1 CLAUDE_CODE_EFFORT_LEVEL= bash "$STATUSLINE" 2>/dev/null
}

# Count ● glyphs attributed to the color in effect when they were emitted.
# A color code applies until the next code or a reset.
count_dots() {
    printf '%s' "$1" | perl -CSD -e '
        local $/; my $s = <STDIN> // "";
        my %n = (lit => 0, dim => 0);
        my $cur = "";
        while ($s =~ /\e\[38;2;(\d+;\d+;\d+)m|(\x{25CF}+)|(\e\[0m)/g) {
            if (defined $2) { $n{$cur} += length($2) if $cur; }
            elsif (defined $1) {
                $cur = ($1 eq "121;121;122" || $1 eq "168;85;247") ? "lit"
                     : ($1 eq "74;74;74"    || $1 eq "102;52;151") ? "dim"
                     : "";
            } else { $cur = ""; }
        }
        print "$n{lit}/$n{dim}";
    '
}

check() {
    local label="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf '  FAIL %-46s expected %-18s got %s\n' "$label" "$expected" "$actual"
    fi
}

# name <model_id> -> the rendered model name token (2nd pipe-delimited segment)
name_of() {
    render "$1" "$2" | sed -E 's/\x1b\[[0-9;]*m//g' | awk -F' \\| ' '{print $2}' | awk '{print $1}'
}

# dots <model_id> <effort> -> "lit/dim"; dim includes the unlit purple ultra slot
dots_of() {
    count_dots "$(render "$1" "$2")"
}

echo "== model name parsing =="
check "claude-opus-5"                 "$(name_of claude-opus-5 high)"                 "opus5"
check "claude-opus-4-8"               "$(name_of claude-opus-4-8 high)"               "opus4.8"
check "claude-sonnet-4-5-20250929"    "$(name_of claude-sonnet-4-5-20250929 high)"    "sonnet4.5"
check "claude-opus-5-20260115 (date)" "$(name_of claude-opus-5-20260115 high)"        "opus5"
check "claude-fable-5"                "$(name_of claude-fable-5 high)"                "fable5"
check "claude-mythos-5"               "$(name_of claude-mythos-5 high)"               "mythos5"
check "claude-haiku-4-5-20251001"     "$(name_of claude-haiku-4-5-20251001)"          "haiku4.5"
check "claude-3-7-sonnet (legacy)"    "$(name_of claude-3-7-sonnet-20250219 high)"    "sonnet3.7"
check "unknown future family"         "$(name_of claude-quartz-7 high)"               "quartz7"

echo "== effort scale (lit/dim) =="
# Modern models: 6-dot scale, level determines lit count.
check "opus5 low"        "$(dots_of claude-opus-5 low)"        "1/5"
check "opus5 medium"     "$(dots_of claude-opus-5 medium)"     "2/4"
check "opus5 high"       "$(dots_of claude-opus-5 high)"       "3/3"
check "opus5 xhigh"      "$(dots_of claude-opus-5 xhigh)"      "4/2"
check "opus5 max"        "$(dots_of claude-opus-5 max)"        "5/1"
check "opus5 ultra"      "$(dots_of claude-opus-5 ultra)"      "6/0"
check "opus4.8 high"     "$(dots_of claude-opus-4-8 high)"     "3/3"
check "sonnet5 high"     "$(dots_of claude-sonnet-5 high)"     "3/3"
check "fable5 high"      "$(dots_of claude-fable-5 high)"      "3/3"
check "mythos5 high"     "$(dots_of claude-mythos-5 high)"     "3/3"

# Legacy models keep the 3-dot scale.
check "opus4.6 high (legacy)"   "$(dots_of claude-opus-4-6 high)"    "3/0"
check "opus4.6 medium (legacy)" "$(dots_of claude-opus-4-6 medium)"  "2/1"
check "sonnet4.6 high (legacy)" "$(dots_of claude-sonnet-4-6 high)"  "3/0"

# An unknown family must get the modern scale, not a collapsed one.
check "unknown family high"  "$(dots_of claude-quartz-7 high)"   "3/3"
check "unknown family xhigh" "$(dots_of claude-quartz-7 xhigh)"  "4/2"

# A level above the assumed ceiling widens the scale instead of clamping.
check "legacy id at ultra"   "$(dots_of claude-opus-4-6 ultra)"  "6/0"
check "legacy id at xhigh"   "$(dots_of claude-opus-4-6 xhigh)"  "4/0"

# Haiku is not thinking-capable: no dots at all.
check "haiku has no dots"    "$(dots_of claude-haiku-4-5-20251001 high)"  "0/0"

echo
if [ "$fail" -eq 0 ]; then
    echo "PASS: $pass checks"
else
    echo "FAIL: $fail failed, $pass passed"
fi
exit $((fail > 0))
