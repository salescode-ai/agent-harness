# Cross-repo plan: <feature>

**Status**: draft | active | blocked | done · **Branch**: <KEY-123-slug, same name in every repo below>
**Ticket**: <KEY-123 (harness-workspace.json issueKey) | #123 | none (<reason>)>
**Evidence**: local `.harness/evidence/<this file name>`, one block per repo (never committed; shared via each PR description and the tracker comment)

## Goal
<one sentence: what is true for the user when this ships>

## Contract
<!-- The interface between repos: routes, request/response fields, enums, error codes, events. Provider repo owns it. -->
- `<METHOD /path>` — request `{…}` → response `{…}`; new fields are optional for old clients

## Per repo (in merge order)
### <provider repo, e.g. backend-api>
- [ ] 1. <step> → verify: `make -C backend-api test T=<test>`
- Acceptance: <criterion> — proved by: <test>

### <client repo, e.g. portal>
- [ ] 1. <step> → verify: `make -C portal test T=<path>`
- Acceptance: <criterion> — proved by: <test>

## Progress log
<!-- Append one line per session: date · repo · what changed · next. Never rewrite history. -->
- <YYYY-MM-DD> · <repo> · <done> · next: <step>
