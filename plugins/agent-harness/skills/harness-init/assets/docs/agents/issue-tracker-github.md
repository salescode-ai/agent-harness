# Issue tracker: GitHub

Work is tracked as GitHub issues in this repo. Use the `gh` CLI; it infers the repo from `git remote`.

- Create: `gh issue create --title "<title>" --body-file <file>` (labels with `--label`)
- Read: `gh issue view <n> --comments`
- List: `gh issue list --state open --label <label>`
- Comment / label / close: `gh issue comment`, `gh issue edit --add-label`, `gh issue close <n> --comment "<why>"`
- Sub-tasks: put `Part of #<parent>` on the first line of the child issue.

When a skill says "publish to the issue tracker", create an issue as above and reply with its number.
External pull requests are not treated as requests unless this line says otherwise: **PRs as requests: no**.
