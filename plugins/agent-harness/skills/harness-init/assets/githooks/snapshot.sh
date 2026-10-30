# agent-harness: sourced by pre-commit and pre-push (not a hook). snapshot_check <tree-ish> <target> [merge]: runs the
# repo's <target> in a scratch worktree holding exactly <tree-ish>, so uncommitted edits can't change the verdict.
# merge: also carry over MERGE_HEAD (a merge being committed); nothing else is carried over but dependency folders.
snapshot_check() {
  SNAP_TMP="$(mktemp -d)"; local w="$SNAP_TMP/w"
  trap '(unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE; git worktree remove --force "$SNAP_TMP/w" >/dev/null 2>&1); rm -rf "$SNAP_TMP"' EXIT
  (
    unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE
    git worktree add -q --detach "$w" HEAD >/dev/null 2>&1 && git -C "$w" read-tree -u --reset "$1" \
      || { echo "harness: could not check out $1 in a scratch worktree (no commit yet?)" >&2; exit 1; }
    # a merge being committed stays a merge there: repo logic that reads MERGE_HEAD must not see every merged file as changed
    [ "${3:-}" = merge ] && mh="$(git rev-parse -q --verify MERGE_HEAD)" && (cd "$w" && echo "$mh" > "$(git rev-parse --git-path MERGE_HEAD)")
    # shortcut: shares the usual gitignored dependency/env folders by symlink (as red-proof.sh); build output starts cold
    for d in $(find . -maxdepth 3 \( -name node_modules -o -name .venv -o -name venv \) -type d -prune 2>/dev/null) .env .env.local; do
      [ -e "$d" ] && [ ! -e "$w/$d" ] && { mkdir -p "$w/$(dirname "$d")"; ln -s "$PWD/${d#./}" "$w/${d#./}"; }
    done
    c="$(bash scripts/harness/cmd.sh "$w" "$2")" || exit 1
    cd "$w" && eval "$c"
  )
}
