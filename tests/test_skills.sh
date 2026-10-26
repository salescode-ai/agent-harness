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
    if grep -E '`make (check|check-fast|smoke)`' "$PLUGIN/skills/harness-$s/SKILL.md" | grep -vqE 'cmd\.sh|workspace'; then _fail "harness-$s: hard-coded make check"; fi
  done
}
t_scripts_referenced_exist() {
  local out tmp; tmp="$(mktemp)"
  python3 - "$PLUGIN" $(_doc_files) > "$tmp" <<'PY'
import os, re, sys
plugin, files = sys.argv[1], sys.argv[2:]
tok = re.compile(r"(?<![\w./$-])(\$\{CLAUDE_PLUGIN_ROOT\}/[^\s\x60\x22\x27)]+|(?:scripts|assets|references|agents|skills|\.githooks)/[^\s\x60\x22\x27)]*)")
mapping = [("scripts/harness/cmd.sh", "scripts/harness-cmd.sh"), ("scripts/harness/lint.sh", "skills/harness-init/assets/lint.sh")]
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
  out="$(grep -rn 'eval "$(bash scripts/harness/cmd.sh' "$PLUGIN/skills" "$PLUGIN/agents" || true)"
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
