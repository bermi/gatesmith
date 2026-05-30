#!/usr/bin/env bash
# Gatesmith installer — copies the .gatesmith/ ledger scaffold and .claude/ command
# into the current repository. Run from the root of the project you want to build.
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
cp -R "$SRC/.gatesmith" "$DEST/.gatesmith"

mkdir -p "$DEST/.claude/commands"
cp "$SRC/.claude/commands/gatesmith.md" "$DEST/.claude/commands/gatesmith.md"

if [[ -f "$DEST/.claude/settings.json" ]]; then
  echo "note: $DEST/.claude/settings.json already exists — NOT overwriting it."
  echo "      Merge in the allow/deny entries from:"
  echo "      $SRC/.claude/settings.json"
else
  cp "$SRC/.claude/settings.json" "$DEST/.claude/settings.json"
fi

cat <<'EOF'

Gatesmith installed.

Next steps:
  1. Fill in {{LANES}}, {{PLAN_DOC}}, {{FROZEN}} in .gatesmith/PM_PROMPT.md
  2. Replace the seed gates in .gatesmith/gates.yaml with your real ledger
  3. Copy .gatesmith/templates/_lane.md to .gatesmith/templates/<lane>.md per lane
  4. Add your build/test/run commands to .claude/settings.json
  5. Bootstrap-commit .gatesmith/ and .claude/, then run:

       /ralph-loop:ralph-loop /gatesmith

  (Tip: paste the filled-in SETUP_PROMPT.md to have Claude generate steps 1-4.)
EOF
