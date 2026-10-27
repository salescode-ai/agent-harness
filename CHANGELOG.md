# Changelog

## 2.0.7

- **Fix: `harness-lint` failed on IDE/build copies of module `AGENTS.md`.** `lint.sh` found module `AGENTS.md` files with `find`, which did not skip build output. In a Maven repo an IDE build copied `src/main/java/.../AGENTS.md` into `target/classes/`, its relative links broke there, lint failed, and `level.py` measured the level as `none` after every build. `lint.sh` now lists candidates with `git ls-files -co --exclude-standard` (anything gitignored is skipped) and always drops `target/`, `build/`, `dist/`, `out/`, `.gradle/`, `node_modules/` and the tool folders; outside git it uses a pruned `find`. `scan.py` also skips `out/` and `.gradle/`.
- **Upgrade:** `/agent-harness:harness-upgrade` refreshes `scripts/harness/lint.sh` in repos with an unmodified copy. A repo that hand-patched its `lint.sh` for this bug (channelkart-api added `-not -path './target/*'`) shows it as `modified` and is not overwritten: take the upstream copy with `cp "<plugin>/skills/harness-init/assets/lint.sh" scripts/harness/lint.sh` (the upgrade report prints the `diff` command with the plugin path), then run the upgrade again so the manifest records it as current.

## 2.0.6

- Worktree subagents: when an implementer subagent stops with `check-fast` failing in its own git worktree, its branch is recorded in `.git/harness-red/`, and the Bash guard refuses to merge, cherry-pick or `pull .` it until a later stop there passes.
- `AGENTS.md` → Agent skills rule 8 for parallel and spec-driven flows (migration `agents-parallel`).
