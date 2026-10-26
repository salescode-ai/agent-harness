# Issue tracker: GitHub

Work is tracked as GitHub issues in this repo. Use the `gh` CLI; it infers the repo from `git remote`.

- Create: `gh issue create --title "<title>" --body-file <file>` (labels with `--label`)
- Read: `gh issue view <n> --comments`
- List: `gh issue list --state open --label <label>`
- Comment / label / close: `gh issue comment`, `gh issue edit --add-label`, `gh issue close <n> --comment "<why>"`
- Sub-tasks: put `Part of #<parent>` on the first line of the child issue.

When a skill says "publish to the issue tracker", create an issue as above and reply with its number.
External pull requests are not treated as requests unless this line says otherwise: **PRs as requests: no**.

**Status updates (approval-gated).** Agents draft, the developer approves: mid-work a short progress comment (what changed · tests status · next); when a step or the plan is done, the harness-verify evidence block (Verified · Gate with test count · Criteria k/n → proving test/command · Reviewers · Open) plus the plan's `## Verification` path and the next step, and a proposed transition when the plan is done. Post only after an explicit yes, through the connector or CLI in the session; never store tokens; without one, print the text for copy-paste.
