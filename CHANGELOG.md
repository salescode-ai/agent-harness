# Changelog

## 2.0.9

Fixes from running the harness on a Spring Boot/Maven repo.

- **Setup no longer asks for `~/.m2/settings.xml` when deps installed.** The "maven credentials" hint now appears only when `setup-deps` failed or was skipped, so a repo that passes `-s settings.xml` (or uses a registry extension) is not told to copy it.
- **Main checkout ports.** `make setup` kept the `.env.example` ports even when something else held them, so `docker compose up` failed with "port is already allocated". The main checkout now keeps an example port only while it is free or held by this compose project's own container; otherwise it gets a free port, recorded in `.env.local` (which wins on re-runs, as before).
- **Smoke reporting.** With `HARNESS_SMOKE` unset, setup printed `smoke ✓` although nothing ran; it now prints `smoke n/a`. Setup runs smoke only once nothing is listed under "needs you", and `HARNESS_SETUP_SMOKE = 0` keeps it out of setup entirely (for server apps whose smoke boots the app before the database is configured).
- **New: `make dev-check` / `make dev-stop`.** Set `HARNESS_HEALTH` (a URL or a command meaning "the app is up"). `dev-check` starts `make dev` in the background, waits up to `HARNESS_HEALTH_SECS` (120), runs `RUN='<cmd>'` if given, and always stops it (`scripts/harness/dev-check.sh`). Once it exists, the Bash guard refuses an agent's long-lived `make dev`, also when wrapped (`nohup`, `bash -c`, `VAR=`), and any run script listed in `HARNESS_DEV_BLOCK`. A repo that already defines its own `dev-check` keeps it, and the guard honours it.
- **One token count.** `level.py` counted characters and `lint.sh` bytes (≈2963 vs ≈3004 on the same files), so the audit's token check could pass while `harness-lint` warned. Both now use UTF-8 bytes / 4.
- **Less noise.** `harness-lint`'s check-fast warning only counts source files of the stacks whose build files the repo has, never `scripts/harness/` (a Maven repo's Python sensors were cited as untested). `HARNESS_TEST_CHANGED_CONFIRMED = 1` silences the custom-selector warning once you have checked the selector. `level.py --log` no longer appends a row identical to the last one.
- **Learning is offered at close.** `harness-session` Close gains step 5: when the session shows a repeated failure (the stop gate blocked twice on it or gave up, a FAIL or `Red: not proven` entry before the PASS, or a developer correction), it shows `Learn? <what happened> · seen <n>× · likely rung: …` and runs `harness-learn` only after the developer says yes. `harness-verify` now offers `harness-learn` the same way instead of running it unasked. Skill text only: nothing to upgrade in repos.
- **Upgrade:** `/agent-harness:harness-upgrade` refreshes `setup.sh`, `harness.mk` and `lint.sh` (unmodified copies) and installs `dev-check.sh`. Manual migration `dev-health`: a Makefile with `HARNESS_DEV` but no `HARNESS_HEALTH` (and no `dev-check` of its own) is asked to set it.

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
