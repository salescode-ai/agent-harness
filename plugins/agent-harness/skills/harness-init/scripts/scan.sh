#!/usr/bin/env bash
# Quick inventory of agent-harness artifacts. Prints TYPE<TAB>PATH. Read-only.
set -uo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"; cd "$ROOT" || exit 1
p() { printf '%s\t%s\n' "$1" "$2"; }
[[ -L AGENTS.md ]] && p "symlink(fix: must be real file)" AGENTS.md
[[ -f AGENTS.md && ! -L AGENTS.md ]] && p "harness" "AGENTS.md ($(wc -l < AGENTS.md | tr -d ' ') lines)"
[[ -f INVARIANTS.md ]] && p harness INVARIANTS.md
if [[ -f CLAUDE.md ]]; then
  if grep -vE '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*@[^ ]+[[:space:]]*$|^[[:space:]]*<!--.*-->[[:space:]]*$' CLAUDE.md | grep -q .; then p "real-content(migrate)" CLAUDE.md; else p shim CLAUDE.md; fi
  grep -q '^## Agent skills' CLAUDE.md && p "pack-block-in-CLAUDE.md(move)" CLAUDE.md
fi
for f in .cursorrules .github/copilot-instructions.md GEMINI.md; do [[ -f "$f" ]] && p "tool-specific(migrate)" "$f"; done
for d in .cursor/rules .github/instructions .claude/commands; do [[ -d "$d" ]] && find "$d" -type f | while read -r f; do p "tool-specific(migrate)" "$f"; done; done
find . -name SKILL.md -not -path './.git/*' -not -path '*/node_modules/*' 2>/dev/null | while read -r f; do
  case "$f" in ./.agents/skills/*) p skill "$f";; ./.claude/skills/*) [[ -L "$(dirname "$f")" ]] && p skill-link "$f" || p "skill-misplaced(move)" "$f";; *) p "skill-misplaced(move)" "$f";; esac
done
find . -name AGENTS.md -not -path './AGENTS.md' -not -path './.git/*' -not -path '*/node_modules/*' 2>/dev/null | while read -r f; do p module-agents "$f"; done
for f in GLOSSARY.md GLOSSARY-MAP.md docs/DECISIONS.md docs/ARCHITECTURE.md docs/TESTING.md .claude/settings.json scripts/harness/lint.sh; do [[ -e "$f" ]] && p harness "$f"; done
for d in docs/adr docs/plans docs/specs docs/agents .scratch .worktrees; do [[ -d "$d" ]] && p dir "$d/"; done
find docs -mindepth 2 -maxdepth 2 -type d \( -name plans -o -name specs \) 2>/dev/null | grep -v '^docs/plans$\|^docs/specs$' | while read -r d; do p "plugin-folder(keep, route in Work Artifacts)" "$d/"; done
[[ -f Makefile ]] && p makefile "Makefile: $(grep -oE '^[a-zA-Z0-9_-]+:' Makefile | tr -d ':' | tr '\n' ' ')"
exit 0
