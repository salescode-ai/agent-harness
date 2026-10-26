---
name: harness-session
description: Start, resume or close a work session so long tasks survive context resets — orient from git, the active plan and the progress log, confirm the repo is healthy, pick one step, and leave a clean hand-off at the end. Use at the start of a session on existing work, after /clear or compaction, and before stopping.
---

# Harness Session

Agents lose memory between sessions; the repo must not. Work state lives in `docs/plans/active/<plan>.md` (goal, acceptance criteria, steps, progress log) and in git history — never only in the conversation.

## Start or resume

1. **Where am I.** `git status --short`, `git branch --show-current`, `git log --oneline -10`.
2. **What was I doing.** Open the plan in `docs/plans/active/` that matches the branch's ticket key (else its slug, else the newest). Read Goal, unchecked Steps, the last 3 Progress log lines and the latest entry of the local evidence file `.harness/evidence/<plan file name>` (the session hook prints it as `last verification:`). No plan and the task needs more than ~3 steps → create one from `docs/plans/TEMPLATE.md` before coding: fill `Ticket:` (`docs/agents/issue-tracker.md`; else `none (<reason>)`), name the branch `<KEY>-<n>-<slug>` and the plan `docs/plans/active/YYYY-MM-DD-<KEY>-<n>-<slug>.md` (no ticket: drop the key).
**Resolver** (`$R` below): `R=scripts/harness/cmd.sh; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT}/scripts/harness-cmd.sh"` — a v1 repo without `scripts/harness/cmd.sh` uses the plugin's copy (same contract).
3. **Is the repo healthy.** Run the check command in two steps: `c="$(bash "$R" . check-fast)" || { echo "check-fast not wired (exit $?)"; exit 1; }; eval "$c"` (default `make check-fast`); `smoke` the same way if it is wired. Not wired is not healthy: report it. If it fails on work you did not start, stop and fix that first, or report it — never build on a broken base.
4. **Pick exactly one step.** The first unchecked step whose dependencies are done. State it and its `verify:` command in one line, then work.

In a multi-repo workspace (a `harness-workspace.json` above you): run `make status` instead of the git commands, read the cross-repo plan in `plans/active/`, check health with the workspace `make check-fast` (it runs each changed repo's resolved gate), and pick one step in one repo.

## During

- One step at a time. When its verify command passes, tick it in the plan.
- Anything surprising (a constraint you discovered, a workaround, a decision) → one line under "Decisions made during the work".
- Context getting long? Write the hand-off below first, then compact or clear.

## Close (before stopping, or before /clear)

1. Leave the tree clean: either commit (if Agent Authorization allows) with a message naming the plan step, or `git stash` with a named message and say so.
2. Append one line to the plan's Progress log: `- YYYY-MM-DD · what changed · tests status · next: <step>`.
3. If the plan is complete: run **harness-verify** first. **Never set Status: done or move the plan to `docs/plans/done/` until `bash scripts/harness/plan-check.sh fresh .harness/evidence/<plan file name>` exits 0** (the latest local entry is PASS, for a commit with the same code as HEAD, and no code is uncommitted; plan edits don't count); otherwise show its one line, run harness-verify and stop there. Then set Status: done, move the file, and promote any decision worth keeping to `docs/adr/` (update `docs/DECISIONS.md`).
4. **Tracker update (approval-gated).** If the plan has a ticket (Jira, GitHub or GitLab): draft one comment. Mid-work: the short progress line (what changed · tests status · next). Plan or step done after harness-verify: the harness-verify **evidence block** (Verified · Gate with test count · Criteria k/n → proving test/command · Reviewers · Open), plus the plan path, the local evidence path (`.harness/evidence/<plan file name>`) and the next step; when the plan is done, also propose the transition (e.g. → Done). Show the draft and **post only after the developer says yes**, through a Jira/GitHub/GitLab connector or CLI in this session (`docs/agents/issue-tracker.md`). Never store or ask for tokens; no connector → print the text for copy-paste.
5. Say in one line what the next session should do.

## Rules

- Never mark a step done without running its verify command in this session.
- Never rewrite earlier Progress log lines; append only.
- The plan file is the contract. If the plan is wrong, change it explicitly (and say why in the log) instead of silently diverging.
