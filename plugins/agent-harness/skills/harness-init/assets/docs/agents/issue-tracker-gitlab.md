# Issue tracker: GitLab

Work is tracked as GitLab issues in this project. Use the `glab` CLI.

- Create: `glab issue create --title "<title>" --description "<body>" --label <label>`
- Read: `glab issue view <n> --comments`
- List: `glab issue list --label <label>`
- Comment / close: `glab issue note <n> -m "<text>"`, `glab issue close <n>`

When a skill says "publish to the issue tracker", create an issue and reply with its number.

**Status updates (approval-gated).** Agents draft, the developer approves: mid-work a short progress comment (what changed · tests status · next); when a step or the plan is done, the harness-verify evidence block (Verified · Gate with test count · Criteria k/n → proving test/command · Reviewers · Open) plus the plan path, the local evidence path (`.harness/evidence/<plan file name>`, never committed) and the next step, and a proposed transition when the plan is done. Post only after an explicit yes, through the connector or CLI in the session; never store tokens; without one, print the text for copy-paste.
