# Changelog

## 2.0.8

- **Test-first, proven.** New `scripts/harness/red-proof.sh`: in a scratch worktree with the current code, each changed test file must pass (green control), then fail once the changed production files are put back to the base (red). harness-verify's verifier runs it and records a `Red:` line in the evidence: `proven`, `n/a (<reason>)` (no production code changed, or a pure refactor/config change the verifier accepts), `not proven` (FAIL: write a test that fails first) or `inconclusive` (the tests can't run in a scratch worktree; the verifier tries by hand, else NEEDS-HUMAN).
- **Plans close only with a red proof.** `plan-check.sh fresh` (pre-commit, when a plan moves to `done/`) now also needs `Red: proven (…)` or `Red: n/a (<reason>)` in the latest PASS entry. Evidence written before 2.0.8 has no `Red:` line: run harness-verify again before closing an in-flight plan.
- **Templates and upgrade:** `INVARIANTS.md` → Testing gains "New or changed behaviour has a test that fails without the change" (migration `invariants-red-proof`, proposed for your yes); `AGENTS.md` Working Principle 4 now says test first. `/agent-harness:harness-upgrade` installs `red-proof.sh` and refreshes `plan-check.sh` (unmodified copies).

## 2.0.7

- **Fix: `harness-lint` failed on IDE/build copies of module `AGENTS.md`.** `lint.sh` found module `AGENTS.md` files with `find`, which did not skip build output. In a Maven repo an IDE build copied `src/main/java/.../AGENTS.md` into `target/classes/`, its relative links broke there, lint failed, and `level.py` measured the level as `none` after every build. `lint.sh` now lists candidates with `git ls-files -co --exclude-standard` (anything gitignored is skipped) and always drops `target/`, `build/`, `dist/`, `out/`, `.gradle/`, `node_modules/` and the tool folders; outside git it uses a pruned `find`. `scan.py` also skips `out/` and `.gradle/`.
- **Upgrade:** `/agent-harness:harness-upgrade` refreshes `scripts/harness/lint.sh` in repos with an unmodified copy. A repo that hand-patched its `lint.sh` for this bug (channelkart-api added `-not -path './target/*'`) shows it as `modified` and is not overwritten: take the upstream copy with `cp "<plugin>/skills/harness-init/assets/lint.sh" scripts/harness/lint.sh` (the upgrade report prints the `diff` command with the plugin path), then run the upgrade again so the manifest records it as current.

## 2.0.6

- Worktree subagents: when an implementer subagent stops with `check-fast` failing in its own git worktree, its branch is recorded in `.git/harness-red/`, and the Bash guard refuses to merge, cherry-pick or `pull .` it until a later stop there passes.
- `AGENTS.md` → Agent skills rule 8 for parallel and spec-driven flows (migration `agents-parallel`).
