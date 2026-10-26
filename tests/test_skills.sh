_skill_files() { ls "$PLUGIN"/skills/*/SKILL.md; }
_doc_files() { ls "$PLUGIN"/skills/*/SKILL.md "$PLUGIN"/skills/*/references/*.md "$PLUGIN"/agents/*.md; }

t_skill_frontmatter() {
  local f
  for f in $(_skill_files); do
    [ "$(head -1 "$f")" = "---" ] || _fail "$f: no frontmatter"
    sed -n '2,/^---$/p' "$f" | grep -q '^name: ' || _fail "$f: no name"
    sed -n '2,/^---$/p' "$f" | grep -q '^description: ' || _fail "$f: no description"
  done
}
t_skill_budget() {
  local f n
  for f in $(_skill_files) "$PLUGIN"/agents/*.md; do
    n="$(wc -l < "$f" | tr -d ' ')"
    [ "$n" -le 120 ] || _fail "$f: $n lines (max 120)"
  done
}
t_init_mentions_layers_in_order() {
  grep -q 'Guides → Tools → Sensors → Context & State → Observability' "$PLUGIN/skills/harness-init/SKILL.md" \
    || _fail "init SKILL.md: layer order line"
  local got
  got="$(grep -E '^## ' "$PLUGIN/skills/harness-init/references/layers.md" | grep -oE 'Guides|Tools|Sensors|Context & State|Observability' | tr '\n' ',')"
  assert_eq "$got" "Guides,Tools,Sensors,Context & State,Observability," "layers.md sections in order"
}
t_init_markers_and_state() {
  local f="$PLUGIN/skills/harness-init/SKILL.md" m
  for m in 'auto-filled ✓' 'skeleton + TODO' 'needs your answer ?' '~ extend' '→ move' '➡️' 'Assumed — change any time' \
           '.harness/init-state.json' '"layers_done"' '"gate_wired"' 'one-shot'; do
    grep -qF "$m" "$f" || _fail "init SKILL.md missing '$m'"
  done
}
t_audit_readonly_flag() {
  local s
  for s in harness-audit harness-init harness-workspace; do
    grep -q '^disable-model-invocation: true' "$PLUGIN/skills/$s/SKILL.md" || _fail "$s: no disable-model-invocation"
  done
  grep -q 'level.py' "$PLUGIN/skills/harness-audit/SKILL.md"
}
t_everyday_skills_use_resolved_commands() {
  local s
  for s in verify session garden learn; do
    grep -q 'scripts/harness/cmd.sh' "$PLUGIN/skills/harness-$s/SKILL.md" || _fail "harness-$s: no cmd.sh"
    # a literal make check is fine only as the resolver's default or the workspace gate
    if grep -E '`make (check|check-fast|smoke)`' "$PLUGIN/skills/harness-$s/SKILL.md" | grep -vqE 'cmd\.sh|"\$R"|workspace'; then _fail "harness-$s: hard-coded make check"; fi
  done
}
t_scripts_referenced_exist() {
  local out tmp; tmp="$(mktemp)"
  python3 - "$PLUGIN" $(_doc_files) > "$tmp" <<'PY'
import os, re, sys
plugin, files = sys.argv[1], sys.argv[2:]
tok = re.compile(r"(?<![\w./$-])(\$\{CLAUDE_PLUGIN_ROOT\}/[^\s\x60\x22\x27)]+|(?:scripts|assets|references|agents|skills|\.githooks)/[^\s\x60\x22\x27)]*)")
mapping = [("scripts/harness/cmd.sh", "scripts/harness-cmd.sh"), ("scripts/harness/assets.json", "scripts/assets.py"), ("scripts/harness/lint.sh", "skills/harness-init/assets/lint.sh")]
bad = []
for f in files:
    skill = os.path.dirname(f) if f.endswith("SKILL.md") else os.path.dirname(os.path.dirname(f))
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        for t in tok.findall(line):
            t = t.rstrip(".,:;")
            if "<" in t or "*" in t or ("{" in t and not t.startswith("${")):
                continue
            if t.startswith("${CLAUDE_PLUGIN_ROOT}/"):
                cands = [t[len("${CLAUDE_PLUGIN_ROOT}/"):]]
            elif t in dict(mapping):
                cands = [dict(mapping)[t]]
            elif t.startswith("scripts/harness/"):
                cands = ["skills/harness-init/assets/harness/" + t[16:]]
            elif t.startswith(".githooks/"):
                cands = ["skills/harness-init/assets/githooks/" + t[10:]]
            elif t.startswith(("assets/", "references/")):
                cands = [os.path.relpath(os.path.join(skill, t), plugin), "skills/harness-init/" + t]
            else:
                cands = [t]
            if not any(os.path.exists(os.path.join(plugin, c)) for c in cands):
                bad.append(f"{os.path.relpath(f, plugin)}:{n}: {t}")
print("\n".join(bad))
PY
  out="$(cat "$tmp")"; rm -f "$tmp"
  assert_eq "$out" "" "referenced plugin paths exist"
}
t_no_false_green_eval() {
  # eval "$(cmd.sh …)" turns an unresolved target (exit 3/4, empty output) into exit 0
  local out
  out="$(grep -rnE 'eval "\$\(bash (scripts\/harness\/cmd.sh|"\$R")' "$PLUGIN/skills" "$PLUGIN/agents" || true)"
  assert_eq "$out" "" "two-step cmd.sh form only"
}
t_logged_level_uses_run_checks() {
  local out
  out="$(grep -rhn 'level.py[^`]*--log' "$PLUGIN/skills" "$PLUGIN/agents" | grep -v -- '--run-checks' || true)"
  assert_eq "$out" "" "--log always with --run-checks"
}
t_init_base_and_baseline_rules() {
  local f="$PLUGIN/skills/harness-init/SKILL.md" m
  for m in 'git symbolic-ref --short refs/remotes/origin/HEAD' 'HARNESS_BASE' 'CI=true' 'skipped:timeout' 'compose file or seed generation'; do
    grep -qF "$m" "$f" || _fail "init SKILL.md missing '$m'"
  done
}
t_init_state_first_and_declined_tools() {
  local f="$PLUGIN/skills/harness-init/SKILL.md" m
  for m in '**first** save `.harness/init-state.json` with `"gate_wired": false`' 'Do **not** set `core.hooksPath` here' \
           'lint: none (declined <date>)' 'into `HARNESS_TEST_ALL`'; do
    grep -qF "$m" "$f" || _fail "init SKILL.md missing '$m'"
  done
  grep -qF 'lint: none (declined' "$PLUGIN/skills/harness-init/references/layout.md" || _fail "layout: declined form"
  grep -qF 'declined' "$PLUGIN/skills/harness-init/references/layers.md" || _fail "layers: declined option"
  if grep -qF 'run `git config core.hooksPath .githooks` now' "$PLUGIN/skills/harness-init/references/layers.md"; then _fail "hooksPath at install"; fi
}
t_resolver_falls_back_to_plugin_copy() {
  local f
  for f in skills/harness-garden/SKILL.md skills/harness-learn/SKILL.md skills/harness-session/SKILL.md \
           skills/harness-verify/SKILL.md agents/verifier.md agents/harness-auditor.md; do
    grep -qF '[ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT}/scripts/harness-cmd.sh"' "$PLUGIN/$f" || _fail "$f: no resolver fallback"
    if grep -qF 'bash scripts/harness/cmd.sh' "$PLUGIN/$f"; then _fail "$f: hard-wired repo resolver"; fi
  done
  grep -qF 'level.py" . --json --run-checks' "$PLUGIN/agents/harness-auditor.md" || _fail "auditor: --run-checks"
}
t_init_member_argument_and_refresh() {
  local i="$PLUGIN/skills/harness-init/SKILL.md" w="$PLUGIN/skills/harness-workspace/SKILL.md" t="$PLUGIN/skills/harness-workspace/assets/AGENTS.md" m
  for m in 'with a first argument naming a member' 'work **inside that member**' 'Without one, stop: list the members' \
           '/agent-harness:harness-init <member>' 'assets.py" status .' 'assets.py refresh .' 'modified locally, review diff'; do
    grep -qF -- "$m" "$i" || _fail "init SKILL.md missing '$m'"
  done
  grep -qF '/agent-harness:harness-init <member>` (no interview: `/agent-harness:harness-init <member> one-shot`)' "$w" || _fail "workspace skill: opt-in command"
  grep -qF '/agent-harness:harness-init <repo>` (no interview: `/agent-harness:harness-init <repo> one-shot`)' "$t" || _fail "workspace AGENTS.md: opt-in command"
  grep -qF 'assets.py" status .' "$PLUGIN/skills/harness-audit/SKILL.md" || _fail "audit: stale assets"
}
t_init_wires_related_tests_and_skipped_tools() {
  local f="$PLUGIN/skills/harness-init/SKILL.md" l="$PLUGIN/skills/harness-init/references/layout.md" m
  for m in 'baseline_secs' 'HARNESS_TEST_SECS = <baseline_secs>' 'scripts/harness/related-tests.sh' \
           'skipped (<why>, <date>)' '"gate_reason"'; do
    grep -qF -- "$m" "$f" || _fail "init SKILL.md missing '$m'"
  done
  for m in 'related-tests.sh maven' 'related-tests.sh go' 'related-tests.sh pytest' 'related-tests.sh jest' \
           'related-tests.sh gradle' 'lint: skipped ('; do
    grep -qF -- "$m" "$l" || _fail "layout.md missing '$m'"
  done
  if grep -qF '`skipped` tools are not wired' "$f"; then _fail "skipped tools left unwired"; fi
}
t_one_shot_never_runs_make_setup() {
  local s="$PLUGIN/skills/harness-init/SKILL.md" l="$PLUGIN/skills/harness-init/references/layers.md"
  grep -qF 'One-shot **never runs `make setup`**' "$s" || _fail "one-shot make setup rule"
  grep -qF 'Next: make setup' "$s" || _fail "make setup is the first Next step"
  grep -qF 'pending make setup' "$s" && grep -qF 'pending make setup' "$l" || _fail "hooks recorded pending"
}
t_tracker_comment_carries_verification_evidence() {
  local s="$PLUGIN/skills/harness-session/SKILL.md" v="$PLUGIN/skills/harness-verify/SKILL.md" t
  grep -qF 'the harness-verify **evidence block** (Verified · Gate with test count · Criteria k/n → proving test/command · Reviewers · Open)' "$s" || _fail "session Close: evidence in comment"
  grep -qF '**post only after the developer says yes**' "$s" || _fail "approval gate"
  grep -qF 'Never store or ask for tokens; no connector → print the text for copy-paste' "$s" || _fail "no tokens / copy-paste"
  grep -qF 'The PR description and the tracker comment reuse this same block with the plan path' "$v" || _fail "verify: same block"
  for t in jira github gitlab; do
    grep -qF 'the harness-verify evidence block (Verified · Gate with test count' "$PLUGIN/skills/harness-init/assets/docs/agents/issue-tracker-$t.md" || _fail "issue-tracker-$t"
  done
}
t_verify_writes_local_evidence() {
  local s="$PLUGIN/skills/harness-session/SKILL.md" v="$PLUGIN/skills/harness-verify/SKILL.md"
  grep -qF '**appends** this block to the local evidence file `.harness/evidence/<active plan file name>`' "$v" || _fail "append rule"
  grep -qF 'evidence is **never committed**' "$v" || _fail "never committed"
  grep -qF 'never invent a plan' "$v" || _fail "no invented plan"
  grep -qF 'one block per repo' "$v" || _fail "workspace per repo"
  grep -qF '**Never set Status: done or move the plan to `docs/plans/done/` until `bash scripts/harness/plan-check.sh fresh .harness/evidence/<plan file name>` exits 0**' "$s" || _fail "done needs fresh PASS"
  grep -qF 'branch `<KEY>-<n>-<slug>` and the plan `docs/plans/active/YYYY-MM-DD-<KEY>-<n>-<slug>.md`' "$s" || _fail "ticket-keyed naming"
}
