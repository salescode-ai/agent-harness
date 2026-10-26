#!/usr/bin/env bash
# scripts/harness/lint.sh — structural tests for the agent harness.
# Quiet on success (one line). Loud on failure: every problem with its file and a fix.
# Exit 0 = pass (warnings allowed), 1 = at least one failure.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1

FAILS=(); WARNS=()
fail() { FAILS+=("FAIL  $1"); }
warn() { WARNS+=("warn  $1"); }

# 1. Core files exist
for f in AGENTS.md INVARIANTS.md; do
  [[ -f "$f" ]] || fail "$f missing — run the harness-init skill"
done

# 2. CLAUDE.md is a pure shim (blank lines, '#' headings, HTML comments and @-references only)
if [[ -f CLAUDE.md ]]; then
  bad=$(grep -nvE '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*@[^ ]+[[:space:]]*$|^[[:space:]]*<!--.*-->[[:space:]]*$' CLAUDE.md | head -5)
  [[ -n "$bad" ]] && fail "CLAUDE.md has real content (move it to AGENTS.md or INVARIANTS.md):
$(sed 's/^/        /' <<<"$bad")"
  grep -qE '^[[:space:]]*@AGENTS\.md' CLAUDE.md || fail "CLAUDE.md does not reference @AGENTS.md"
fi

# 3. Size budgets (defaults; INVARIANTS.md "## Context Budget" / "## File Size Budget" override)
# bud <section> <key> <default-warn> <default-fail> -> "warn fail"
bud() {
  local v=""
  [[ -f INVARIANTS.md ]] && v=$(awk -v s="## $1" -v k="- $2:" '{sub(/[ \t\r]+$/,"")} $0==s{on=1;next} /^## /{on=0} on && index($0,k)==1{print;exit}' INVARIANTS.md | sed -nE 's/.*warn ([0-9]+), fail ([0-9]+).*/\1 \2/p')
  echo "${v:-$3 $4}"
}
read -r a_warn a_fail <<<"$(bud 'File Size Budget' 'AGENTS.md' 100 120)"
read -r t_warn t_fail <<<"$(bud 'Context Budget' 'auto-loaded tokens' 3000 5000)"
read -r m_warn m_fail <<<"$(bud 'File Size Budget' 'module AGENTS.md' 80 999999)"
read -r s_warn s_fail <<<"$(bud 'File Size Budget' 'SKILL.md' 120 999999)"
if [[ -f AGENTS.md ]]; then
  n=$(wc -l < AGENTS.md | tr -d ' ')
  (( n > a_fail )) && fail "AGENTS.md is $n lines (max $a_fail) — move detail into docs/ or module AGENTS.md"
  (( n > a_warn && n <= a_fail )) && warn "AGENTS.md is $n lines (target ≤ $a_warn)"
fi
chars=0
for f in CLAUDE.md AGENTS.md INVARIANTS.md; do [[ -f "$f" ]] && chars=$(( chars + $(wc -c < "$f") )); done
tokens=$(( chars / 4 ))
(( tokens > t_fail )) && fail "auto-loaded set ≈ $tokens tokens (max $t_fail): CLAUDE.md + AGENTS.md + INVARIANTS.md"
(( tokens > t_warn && tokens <= t_fail )) && warn "auto-loaded set ≈ $tokens tokens (target ≤ $t_warn)"
while IFS= read -r m; do
  n=$(wc -l < "$m" | tr -d ' ')
  (( n > m_fail )) && fail "$m is $n lines (max $m_fail)"
  (( n > m_warn && n <= m_fail )) && warn "$m is $n lines (module target ≤ $m_warn)"
done < <(find . -name AGENTS.md -not -path './AGENTS.md' -not -path '*/node_modules/*' -not -path './.git/*' -not -path './.worktrees/*' -not -path './.agents/*' -not -path './.claude/*' 2>/dev/null)
while IFS= read -r m; do
  n=$(wc -l < "$m" | tr -d ' ')
  (( n > s_fail )) && fail "$m is $n lines (max $s_fail)"
  (( n > s_warn && n <= s_fail )) && warn "$m is $n lines (SKILL.md target ≤ $s_warn)"
done < <(find .agents/skills -name SKILL.md 2>/dev/null)

# 4. ADRs and the index agree
if [[ -d docs/adr ]]; then
  for f in docs/adr/*.md; do
    [[ -e "$f" ]] || continue
    b=$(basename "$f"); [[ "$b" == TEMPLATE.md || "$b" == README.md ]] && continue
    grep -q "adr/$b" docs/DECISIONS.md 2>/dev/null || fail "docs/adr/$b is not listed in docs/DECISIONS.md"
  done
  if [[ -f docs/DECISIONS.md ]]; then
    while IFS= read -r ref; do
      [[ -f "docs/$ref" ]] || fail "docs/DECISIONS.md links to missing docs/$ref"
    done < <(grep -oE 'adr/[0-9]{4}-[A-Za-z0-9._-]+\.md' docs/DECISIONS.md | sort -u)
  fi
fi

# 5. Skills: canonical in .agents/skills, only symlinks in .claude/skills
if [[ -d .claude/skills ]]; then
  for e in .claude/skills/*; do
    [[ -e "$e" || -L "$e" ]] || continue
    if [[ ! -L "$e" ]]; then fail "$e is real content — move it to .agents/skills/ and symlink it"
    elif [[ ! -f "$e/SKILL.md" ]]; then fail "$e is a broken symlink (no SKILL.md behind it)"; fi
  done
fi
while IFS= read -r s; do
  head -5 "$s" | grep -q '^name:' || fail "$s has no 'name:' in its front matter"
  head -8 "$s" | grep -q '^description:' || fail "$s has no 'description:' in its front matter"
done < <(find .agents/skills -name SKILL.md 2>/dev/null)

# 6. Relative links in harness docs resolve
harness_docs=(AGENTS.md INVARIANTS.md GLOSSARY.md CONTRIBUTING.md)
while IFS= read -r f; do harness_docs+=("$f"); done < <(find docs -maxdepth 2 -name '*.md' 2>/dev/null; find . -name AGENTS.md -not -path './AGENTS.md' -not -path '*/node_modules/*' -not -path './.git/*' -not -path './.worktrees/*' -not -path './.agents/*' -not -path './.claude/*' 2>/dev/null)
for f in "${harness_docs[@]}"; do
  [[ -f "$f" ]] || continue
  dir=$(dirname "$f")
  while IFS= read -r link; do
    target="${link%%#*}"
    [[ -z "$target" || "$target" =~ ^(https?:|mailto:|<) || "$target" == *NNNN* ]] && continue
    [[ -e "$dir/$target" ]] || fail "$f links to missing $target"
  done < <(grep -oE '\]\([^)[:space:]]+\)' "$f" | sed -E 's/^\]\((.*)\)$/\1/')
done

# 7. Commands named in AGENTS.md exist: in .agents/harness.json (runner + commands) and/or the Makefile
runner=make; reg_ok=1
if [[ -f AGENTS.md && -f .agents/harness.json ]]; then
  if command -v python3 >/dev/null; then
    reg=$(python3 -c 'import json; c=json.load(open(".agents/harness.json")); print("R"+str(c.get("runner") or "make"))
for k,v in c.get("commands",{}).items(): print("K"+k); print("V"+str(v))' 2>/dev/null) \
      || { fail ".agents/harness.json is not valid JSON — fix it (expected {\"runner\": ..., \"commands\": {...}})"; reg_ok=0; reg=; }
    runner=$(sed -n 's/^R//p' <<<"$reg")
    [[ -z "$runner" ]] && runner=make
    if (( reg_ok )); then
      if [[ "$runner" != make ]]; then
        while IFS= read -r t; do
          fail "AGENTS.md names 'make $t' but this repo's runner is $runner — name '$runner $t' (or register it)"
        done < <(grep -oE '`make [a-z][a-z0-9_-]*' AGENTS.md | awk '{print $2}' | sort -u)
        while IFS= read -r t; do
          grep -qx "K$t" <<<"$reg" && continue
          ok=
          while IFS= read -r v; do [[ "$v" == "$runner $t" || "$v" == "$runner $t "* ]] && ok=1; done < <(sed -n 's/^V//p' <<<"$reg")
          [[ -n "$ok" ]] || fail "AGENTS.md names '$runner $t' but .agents/harness.json has no commands.$t — register it or fix AGENTS.md"
        done < <(grep -oE "\`$runner [a-z][a-z0-9_-]*" AGENTS.md | awk '{print $NF}' | sort -u)
      fi
    fi
  else
    warn ".agents/harness.json check skipped: python3 not found"; reg_ok=0
  fi
fi
if (( reg_ok )) && [[ "$runner" == make ]]; then
  if [[ -f AGENTS.md ]] && command -v make >/dev/null && { [[ -f Makefile ]] || [[ -f makefile ]] || [[ -f GNUmakefile ]]; }; then
    targets=$(make -pRrq : 2>/dev/null | awk -F: '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {print $1}' | sort -u)
    while IFS= read -r t; do
      grep -qx "$t" <<<"$targets" || fail "AGENTS.md names 'make $t' but the Makefile has no '$t' target"
    done < <(grep -oE '`make [a-z][a-z0-9_-]*' AGENTS.md | awk '{print $2}' | sort -u)
  elif [[ -f AGENTS.md ]] && grep -q '`make ' AGENTS.md; then
    fail "AGENTS.md names make targets but there is no Makefile"
  fi
fi

# 9. CLAUDE.md must not carry an Agent skills block
[[ -f CLAUDE.md ]] && grep -qE '^##[[:space:]]+Agent skills' CLAUDE.md && fail "CLAUDE.md has a '## Agent skills' section — move to AGENTS.md"

# 10. INVARIANTS.md bullets carry Severity and Enforced by (Budget sections exempt)
if [[ -f INVARIANTS.md ]]; then
  while IFS= read -r b; do fail "INVARIANTS.md bullet lacks '— Severity: <Critical|Important|Nice-to-have> — Enforced by: <…>': $b"
  done < <(awk '{sub(/[ \t\r]+$/,"")} /^## /{ex=($0=="## Context Budget"||$0=="## File Size Budget"); cat=1; next}
    cat && !ex && /^[-*][[:space:]]/ && !/^[-*][[:space:]]+Harness target:/ &&
    !(/Severity: (Critical|Important|Nice-to-have)([^A-Za-z-]|$)/ && /Enforced by:/) {print}' INVARIANTS.md)
fi

# 11. TODO / [verify] markers in harness files are warnings
todo_files=(INVARIANTS.md GLOSSARY.md)
while IFS= read -r f; do todo_files+=("$f"); done < <(find . \( -name AGENTS.md -o -path './docs/*.md' \) -not -path '*/node_modules/*' -not -path './.git/*' -not -path './.worktrees/*' -not -path './.agents/*' -not -path './.claude/*' 2>/dev/null | sed 's|^\./||')
for f in "${todo_files[@]}"; do
  [[ -f "$f" ]] || continue
  c=$(grep -cE 'TODO|\[verify\]' "$f")
  (( c > 0 )) && warn "$f has $c TODO/[verify] marker(s) — resolve before relying on it"
done

# 12. Sensor fixtures still fire
if [[ -f scripts/harness/sensors/registry.json ]]; then
  if [[ ! -f scripts/harness/sensor-proof.sh ]]; then fail "sensor registry present but scripts/harness/sensor-proof.sh missing"
  else
    if ! out=$(bash scripts/harness/sensor-proof.sh --recheck 2>&1); then
      why="a sensor no longer fires on its fixture"
      grep -q 'FAIL step 3' <<<"$out" && why="a sensor fails on the current code (real violations: fix the code, not the sensor)"
      fail "sensor recheck failed — $why:
$(sed 's/^/        /' <<<"$out")"
    fi
  fi
fi

# 14. Plans carry a ticket; finished plans carry verification evidence
ticket_of() { # the "Ticket:" value of a plan (up to " · " or end of line), or nothing
  grep -m1 -E '(^|[^A-Za-z])Ticket\**:' "$1" | sed -E 's/.*Ticket\**:\**[[:space:]]*//; s/[[:space:]]+·.*$//; s/[[:space:]]+$//'
}
jira_key=$(grep -oE 'Jira project `[A-Z][A-Z0-9]+`' docs/agents/issue-tracker.md 2>/dev/null | head -1 | tr -d '`' | awk '{print $3}')
for f in docs/plans/active/*.md; do
  [[ -f "$f" && "$(basename "$f")" != TEMPLATE.md ]] || continue
  v=$(ticket_of "$f")
  if [[ -z "$v" || "$v" == *"<"* || "$v" =~ ^(TODO|tbd|TBD|\[verify\]|none|none\ *\(\ *\))$ ]]; then
    fail "$f has no ticket — set 'Ticket: <KEY-123 | #123 | .scratch/... | none (<reason>)>' under the title"
  elif [[ "$v" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
    [[ -n "$jira_key" && "${v%-*}" != "$jira_key" ]] && warn "$f Ticket $v is not in Jira project $jira_key (docs/agents/issue-tracker.md)"
  elif ! [[ "$v" =~ ^#[0-9]+$ || "$v" == .scratch/* || "$v" =~ ^none\ \(.+\)$ ]]; then
    fail "$f Ticket '$v' is not a Jira key (ABC-123), #123, a .scratch/ path or 'none (<reason>)'"
  fi
done
for f in docs/plans/done/*.md docs/plans/active/*.md; do
  [[ -f "$f" && "$(basename "$f")" != TEMPLATE.md ]] || continue
  [[ "$f" == docs/plans/done/* ]] || grep -qE 'Status\**:\**[[:space:]]*done([[:space:]]|$)' "$f" || continue
  awk '/^## /{on=($0 ~ /^## Verification/)} on && /^### [0-9]{4}-[0-9]{2}-[0-9]{2}/{found=1} END{exit !found}' "$f" \
    || warn "$f is done but has no ## Verification entry — run harness-verify (it appends the evidence block)"
done

# 13. check-fast tests the changed source files (make runner with harness.mk only; runs no tests)
if (( reg_ok )) && [[ "$runner" == make && -f harness.mk ]] && command -v make >/dev/null \
   && plan=$(make -s --no-print-directory harness-test-plan 2>/dev/null); then
  secs=$(sed -n 's/^secs=//p' <<<"$plan"); mode=$(sed -n 's/^mode=//p' <<<"$plan")
  src_re='\.(java|kt|groovy|scala|py|go|[cm]?[jt]sx?|rb|cs|php|rs|swift)$'
  test_re='(^|/)(src/test[^/]*|tests?|__tests__|spec)/|\.(test|spec)\.|_test\.(go|py)$|(^|/)test_[^/]*\.py$|Tests?\.[a-z]+$|IT\.[a-z]+$'
  srcs=$(sed -n 's/^file=//p' <<<"$plan" | grep -E "$src_re" | grep -vE "$test_re" | sort -u)
  if [[ "$secs" =~ ^[0-9]+$ ]] && (( secs <= 60 )) && [[ "$mode" == none ]]; then srcs=""; fi  # full suite runs
  if [[ -n "$srcs" ]] && git ls-files --cached --others --exclude-standard 2>/dev/null | grep -qE "$test_re"; then
    case "$mode" in
      related) untested=$(sed -n 's/^none: //p' <<<"$plan") ;;
      custom)  untested=""; warn "check-fast: HARNESS_TEST_CHANGED does not use related-tests.sh, so changed source files ($(head -1 <<<"$srcs")…) may select no tests; wire scripts/harness/related-tests.sh (see layout.md)" ;;
      *)       untested="$srcs" ;;
    esac
    n=0
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue; n=$((n+1))
      (( n <= 5 )) && warn "check-fast tests nothing for $f; wire scripts/harness/related-tests.sh (see layout.md)"
    done <<<"$untested"
    (( n > 5 )) && warn "check-fast tests nothing for $((n-5)) more changed source file(s)"
  fi
fi

# 8. Gitignore covers harness scratch
if [[ -f .gitignore ]]; then
  grep -qE '^/?\.harness/?$' .gitignore || warn ".harness/ is not in .gitignore"
  [[ -d .worktrees ]] && ! grep -qE '^/?\.worktrees/?$' .gitignore && fail ".worktrees/ exists but is not gitignored"
fi

# Report
for w in "${WARNS[@]+"${WARNS[@]}"}"; do echo "$w"; done
if (( ${#FAILS[@]} )); then
  for f in "${FAILS[@]}"; do echo "$f"; done
  echo "harness-lint: ${#FAILS[@]} failure(s)"; exit 1
fi
echo "harness-lint: OK (≈${tokens} auto-loaded tokens)"
