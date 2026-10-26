# Issue tracker: Jira

Work is tracked in Jira project `<KEY>` at `<https://<site>.atlassian.net>`. Use the Jira connector or CLI available
in your session. Never write tokens into files.

- Specs → issue type `Story`; tickets → `Task` or `Bug`, linked to the story; dependencies as `blocks / is blocked by`.
- Priority scheme: `<P1–P4>`. Required fields: `<e.g. Sprint, Complexity, Start/End date>`.
- Labels: the triage labels in `docs/agents/triage-labels.md`, if that file exists.
- A bare `#42` in conversation means `<KEY>-42`.

When a skill says "publish to the issue tracker", create the Jira issue and reply with its key.

**Status updates (approval-gated).** Agents draft, the developer approves: mid-work a short progress comment (what changed · tests status · next); when a step or the plan is done, the harness-verify evidence block (Verified · Gate with test count · Criteria k/n → proving test/command · Reviewers · Open) plus the plan's `## Verification` path and the next step, and a proposed transition when the plan is done. Post only after an explicit yes, through the connector or CLI in the session; never store tokens; without one, print the text for copy-paste.
