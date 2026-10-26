# agent-harness (plugin)

Claude Code plugin; see the repository root README for install, levels and settings.

- **Skills:** user-invoked `harness-init`, `harness-audit`, `harness-workspace`; supporting `harness-verify`, `harness-session`, `harness-learn`, `harness-garden`, `harness-glossary`
- **Agents:** `repo-cartographer`, `verifier`, `invariants-reviewer`, `scope-guard`, `cross-repo-reviewer`, `harness-auditor`, `sensor-smith`, `setup-smith`
- **Hooks** (`hooks/hooks.json`): session context, bash guard, file guard, stop gate
- **Scripts** (`scripts/`): `session-context.sh`, `guard-bash.sh` (+ `guard_bash.py`), `guard-files.sh`, `stop-gate.sh`, `harness-cmd.sh` (command resolution), `scan.py`, `level.py`, `_lib.sh`
- **Templates** (`skills/harness-init/assets/`): AGENTS, INVARIANTS, CLAUDE, GLOSSARY, `docs/`, `harness.mk`, `lint.sh`, `harness/` scripts and sensors, `githooks/`
