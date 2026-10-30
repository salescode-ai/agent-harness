# Releasing agent-harness

Repos pin the plugin in `.claude/settings.json` with `extraKnownMarketplaces.agent-harness.source.ref: "vX.Y.Z"`. A github marketplace source has no sha field, so the tag is the only pin: moving it changes every pinned repo's hooks with no review.

**Tags are never moved or deleted.** A fix to a release ships as a new patch version (`vX.Y.Z+1`), never as a re-tag. The repo ruleset "protect release tags" (target: tags `refs/tags/v*`; rules: update, deletion, non-fast-forward) enforces this on GitHub; check it with `gh api repos/salescode-ai/agent-harness/rulesets`.

## Steps

1. On a branch, the last commit is the release commit, matching the code exactly:
   - version in `plugins/agent-harness/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (and `tests/test_meta.sh`);
   - a `CHANGELOG.md` entry;
   - `plugins/agent-harness/scripts/asset-history.json`: the new version's hash for every changed installed asset;
   - `docs/manual/agent-harness-manual.pdf` rebuilt when the manual changed.
2. `bash tests/run.sh` passes on a clean checkout of that commit.
3. Open a PR to `main`; merge it.
4. `git fetch`, then tag the merge commit on `origin/main` and push only that tag:
   `git tag vX.Y.Z origin/main && git push origin vX.Y.Z`, then check `git ls-remote --tags origin vX.Y.Z`.
