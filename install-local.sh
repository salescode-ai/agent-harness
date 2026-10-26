#!/usr/bin/env bash
# Install agent-harness skills and agent checklists into a repo for tools without Claude Code plugins
# (Codex, Cursor, Copilot, Gemini). Claude Code users should install the plugin instead.
# Usage: bash install-local.sh /path/to/repo
set -euo pipefail
SRC="$(cd "$(dirname "$0")/plugins/agent-harness" && pwd)"
DEST="${1:?usage: install-local.sh /path/to/repo}"
mkdir -p "$DEST/.agents/skills" "$DEST/.agents/agents"
for s in "$SRC"/skills/*/; do
  name="$(basename "$s")"
  if [[ -e "$DEST/.agents/skills/$name" ]]; then echo "skip  .agents/skills/$name (exists)"; continue; fi
  cp -R "$s" "$DEST/.agents/skills/$name"; echo "added .agents/skills/$name"
done
for a in "$SRC"/agents/*.md; do
  name="$(basename "$a")"
  if [[ -e "$DEST/.agents/agents/$name" ]]; then echo "skip  .agents/agents/$name (exists)"; continue; fi
  cp "$a" "$DEST/.agents/agents/$name"; echo "added .agents/agents/$name"
done
A="$SRC/skills/harness-init/assets"
put() { # put <src> <dest-relative-to-repo>
  if [[ -e "$DEST/$2" ]]; then echo "skip  $2 (exists)"; return; fi
  mkdir -p "$(dirname "$DEST/$2")"; cp "$1" "$DEST/$2"; echo "added $2"
}
while IFS= read -r f; do put "$f" "scripts/harness/${f#"$A"/harness/}"; done < <(find "$A/harness" -type f)
put "$SRC/scripts/harness-cmd.sh" scripts/harness/cmd.sh
put "$A/lint.sh" scripts/harness/lint.sh
for h in "$A"/githooks/*; do put "$h" ".githooks/$(basename "$h")"; chmod +x "$DEST/.githooks/$(basename "$h")"; done
chmod +x "$DEST"/scripts/harness/*.sh "$DEST"/scripts/harness/sensors/*.sh 2>/dev/null || true
echo "Done. Hooks are Claude Code only; for other tools rely on make check in CI and pre-commit."
