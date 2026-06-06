#!/usr/bin/env bash
# Gatesmith installer — copies the .gatesmith/ ledger scaffold and .claude/ commands,
# the vendored loop scripts + Stop hook, into the current repository. Run from the root
# of the project you want to build.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$KIT_DIR/template"
DEST="$PWD"

if [[ ! -d "$SRC/.gatesmith" || ! -d "$SRC/.claude" ]]; then
  echo "error: can't find template/ next to install.sh ($SRC)" >&2
  exit 1
fi

if [[ "$DEST" == "$KIT_DIR" ]]; then
  echo "error: run this from your project's root, not from the gatesmith repo." >&2
  exit 1
fi

if [[ -d "$DEST/.gatesmith" ]]; then
  echo "refusing to overwrite an existing .gatesmith/ in $DEST" >&2
  echo "(remove or back it up first if you really want a fresh ledger)" >&2
  exit 1
fi

echo "Installing Gatesmith into $DEST ..."

# Ledger scaffold (carries the .gatesmith/.gitignore for loops/locks/questions/answers).
cp -R "$SRC/.gatesmith" "$DEST/.gatesmith"
# Runtime orchestration state dirs (gitignored; created lazily otherwise).
mkdir -p "$DEST/.gatesmith/loops" "$DEST/.gatesmith/locks" \
         "$DEST/.gatesmith/questions" "$DEST/.gatesmith/answers"

# Commands: the /gatesmith tick plus the namespaced /gatesmith:loop|cancel|conduct.
mkdir -p "$DEST/.claude/commands/gatesmith"
cp "$SRC/.claude/commands/gatesmith.md" "$DEST/.claude/commands/gatesmith.md"
cp "$SRC/.claude/commands/gatesmith/"*.md "$DEST/.claude/commands/gatesmith/"

# Vendored loop scripts + Stop hook.
mkdir -p "$DEST/.claude/gatesmith"
cp "$SRC/.claude/gatesmith/"*.sh "$DEST/.claude/gatesmith/"
chmod +x "$DEST/.claude/gatesmith/"*.sh

# Bundled skills (snapdir).
mkdir -p "$DEST/.claude/skills/snapdir"
cp "$SRC/.claude/skills/snapdir/SKILL.md" "$DEST/.claude/skills/snapdir/SKILL.md"

# Snapdir-mode runtime scratch dir (gitignored).
mkdir -p "$DEST/.gatesmith/work"

# Settings: copy ours (with the Stop hook) or merge the hook into an existing file.
HOOK_CMD="bash .claude/gatesmith/stop-hook.sh"
if [[ -f "$DEST/.claude/settings.json" ]]; then
  if grep -q 'gatesmith/stop-hook.sh' "$DEST/.claude/settings.json"; then
    echo "note: gatesmith Stop hook already present in .claude/settings.json — leaving it."
  elif command -v jq >/dev/null 2>&1; then
    TMP="$(mktemp)"
    jq --arg cmd "$HOOK_CMD" \
      '.hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":$cmd}]}])' \
      "$DEST/.claude/settings.json" > "$TMP" && mv "$TMP" "$DEST/.claude/settings.json"
    echo "merged the gatesmith Stop hook into your existing .claude/settings.json"
    echo "      Now merge the allow/deny entries from: $SRC/.claude/settings.json"
  else
    echo "ACTION REQUIRED (no jq found): the loop needs a Stop hook. Add this to"
    echo "      $DEST/.claude/settings.json (top-level, sibling of \"permissions\"):"
    echo ''
    echo '        "hooks": { "Stop": [ { "hooks": [ { "type": "command",'
    echo "                   \"command\": \"$HOOK_CMD\" } ] } ] }"
    echo ''
    echo "      and merge the allow/deny entries from: $SRC/.claude/settings.json"
  fi
else
  cp "$SRC/.claude/settings.json" "$DEST/.claude/settings.json"
fi

cat <<'EOF'

Gatesmith installed.

Next steps:
  1. Fill in {{LANES}}, {{PLAN_DOC}}, {{FROZEN}} in .gatesmith/PM_PROMPT.md
  2. Replace the seed gates in .gatesmith/gates.yaml with your real ledger
     (set an optional `owner:` per gate if multiple teams/branches build in parallel)
  3. Copy .gatesmith/templates/_lane.md to .gatesmith/templates/<lane>.md per lane
  4. Add your build/test/run commands to .claude/settings.json (and any --tick-cmd)
  5. Bootstrap-commit .gatesmith/ and .claude/, then run the loop:

       /gatesmith:loop <owner>        # one owner in this session (omit <owner> args for single-stream)
       /gatesmith:conduct             # conductor: drive several owners in one session
       /gatesmith:cancel <owner>      # stop a loop

  (Tip: paste the filled-in SETUP_PROMPT.md to have Claude generate steps 1-4.)

  Optional — git-free "snapdir mode" (state synced via BLAKE3 snapshots instead of
  git): needs the snapdir binary (cargo install snapdir-cli). Then add
  --snapdir-store file:///abs/store to the loop/conduct command. See README.
EOF
