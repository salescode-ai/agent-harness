# Issue tracker: Jira

Work is tracked in Jira project `<KEY>` at `<https://<site>.atlassian.net>`. Use the Jira connector or CLI available
in your session. Never write tokens into files.

- Specs → issue type `Story`; tickets → `Task` or `Bug`, linked to the story; dependencies as `blocks / is blocked by`.
- Priority scheme: `<P1–P4>`. Required fields: `<e.g. Sprint, Complexity, Start/End date>`.
- Labels: the triage labels in `docs/agents/triage-labels.md`, if that file exists.
- A bare `#42` in conversation means `<KEY>-42`.

When a skill says "publish to the issue tracker", create the Jira issue and reply with its key.
