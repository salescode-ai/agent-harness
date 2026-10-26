#!/usr/bin/env python3
"""PreToolUse(Bash) guard for agent-harness.

Parses the command into segments and argv tokens (quotes respected), so text inside
commit messages or grep patterns never triggers a rule. Prints a PreToolUse decision
JSON for deny/ask; prints nothing to allow. Fails open on any internal error.
"""
import json
import os
import re
import shlex
import subprocess
import sys

SEPARATORS = {";", "&&", "||", "|", "&", "\n", "(", ")"}
WRAPPERS = {"sudo", "env", "command", "time", "nice", "nohup", "xargs"}


def decide(kind, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": kind,
        "permissionDecisionReason": reason}}))
    sys.exit(0)


def segments(cmd):
    lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    seg = []
    for tok in lex:
        if tok in SEPARATORS or (tok and set(tok) <= set(";&|()")):
            if seg:
                yield seg
            seg = []
        else:
            seg.append(tok)
    if seg:
        yield seg


def strip_prefix(argv):
    """Drop env assignments and wrapper commands; return (env_names, argv)."""
    env = []
    i = 0
    while i < len(argv):
        t = argv[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            env.append(t.split("=", 1)[0])
            i += 1
        elif t in WRAPPERS:
            i += 1
        else:
            break
    return env, argv[i:]


def short_flags(args):
    """All single-letter flags from tokens like -fu, -rf (not --long)."""
    out = set()
    for a in args:
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            out.update(a[1:])
    return out


def default_branch(cwd):
    try:
        ref = subprocess.run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
                             capture_output=True, text=True, timeout=3, cwd=cwd).stdout.strip()
        return ref.split("/", 1)[1] if "/" in ref else "main"
    except Exception:
        return "main"


def current_branch(cwd):
    try:
        return subprocess.run(["git", "branch", "--show-current"], capture_output=True,
                              text=True, timeout=3, cwd=cwd).stdout.strip()
    except Exception:
        return ""


def check_git(argv, env, cwd):
    # skip global options: git -C dir, -c k=v, --git-dir=...
    i = 1
    cfg = []
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] in ("-C", "-c"):
            if argv[i] == "-c" and i + 1 < len(argv):
                cfg.append(argv[i + 1])
            if argv[i] == "-C" and i + 1 < len(argv):
                cwd = os.path.join(cwd, os.path.expanduser(argv[i + 1]))
            i += 2
        else:
            i += 1
    if any(c.lower().startswith("core.hookspath") for c in cfg):
        decide("deny", "Overriding core.hooksPath bypasses git hooks (INVARIANTS.md Harness Integrity). Fix the failing check instead.")
    if i >= len(argv):
        return
    sub, args = argv[i], argv[i + 1:]
    flags = short_flags(args)
    longs = {a.split("=", 1)[0] for a in args if a.startswith("--")}

    if "--no-verify" in longs or (sub == "commit" and "n" in flags):
        decide("deny", "Bypassing git hooks (--no-verify / -n) is blocked by INVARIANTS.md. Fix the failing check instead.")
    if sub == "config" and any(a.lower() == "core.hookspath" for a in args):
        decide("deny", "Changing core.hooksPath bypasses git hooks. Ask a human if hooks need to change.")
    if sub == "push":
        refspecs = [a for a in args if not a.startswith("-")]
        force = "--force" in longs or "f" in flags or any(r.startswith("+") for r in refspecs)
        if force:
            decide("deny", "Force-push is blocked by the harness. Use --force-with-lease on your own branch, or ask a human.")
        target = default_branch(cwd)
        names = [r.split(":")[-1] for r in refspecs[1:]]
        if target in names or f"refs/heads/{target}" in names or (not names and current_branch(cwd) == target):
            decide("ask", f"Pushing to {target}. AGENTS.md Agent Authorization normally requires a human for this.")
        if "--force-with-lease" in longs:
            decide("ask", "Force-with-lease push rewrites remote history. Confirm this is your own branch.")
    if sub == "reset" and "--hard" in longs:
        decide("deny", "git reset --hard is blocked: it destroys uncommitted work. Use git stash, or ask a human.")
    if sub == "clean" and ("f" in flags or "--force" in longs):
        decide("deny", "git clean -f is blocked: it deletes untracked files permanently. List them with git clean -n and ask.")
    if sub in ("checkout", "restore"):
        paths = [a for a in args if not a.startswith("-")]
        staged_only = sub == "restore" and ("--staged" in longs or "S" in flags) and not ("--worktree" in longs or "W" in flags)
        if not staged_only and any(p in (".", "./", ":/", "*") for p in paths):
            decide("deny", "Discarding all working-tree changes is blocked. Restore specific files, or ask a human.")
    if sub == "branch" and ("D" in flags or ("--delete" in longs and ("--force" in longs or "f" in flags))):
        decide("deny", "Force-deleting a branch can drop unmerged work. Use git branch -d, or ask a human.")
    if sub == "stash" and args[:1] == ["clear"]:
        decide("deny", "git stash clear deletes every stash permanently. Drop specific stashes, or ask a human.")


DANGEROUS_RM_TARGETS = {"/", "/*", "~", "~/", "~/*", "$HOME", "$HOME/", "${HOME}", ".", "./", "./*", "..", "../", "*", ".*"}


def check_rm(argv):
    args = argv[1:]
    flags = short_flags(args)
    recursive = "r" in flags or "R" in flags or "--recursive" in args
    targets = [a for a in args if not a.startswith("-")]
    if recursive and any(t in DANGEROUS_RM_TARGETS for t in targets):
        decide("deny", "Recursive delete of /, ~, $HOME, ., .. or * is blocked. Delete specific paths.")


CLAUDE_MD_MSG = ('CLAUDE.md files are shims (@-references only). Put instructions in AGENTS.md — '
                 'skill/pack setup blocks go under "## Agent skills", working guidelines under "Working Principles".')


def _is_claude_md(t):
    return os.path.basename(t.rstrip("/")) == "CLAUDE.md"


def writes_claude_md(cmd, segs):
    # shortcut: redirect regex runs on quote-stripped text; heredoc bodies / escaped quotes can fool it
    bare = re.sub(r"\"[^\"]*\"|'[^']*'", " ", cmd)
    if re.search(r"(?<![0-9&<])>>?\s*[^\s;&|()<>]*CLAUDE\.md(?=[\s;&|()]|$)", bare):
        return True
    for seg in segs:
        _, argv = strip_prefix(seg)
        if not argv:
            continue
        prog, args = os.path.basename(argv[0]), argv[1:]
        files = [a for a in args if not a.startswith("-")]
        if prog == "tee" and any(_is_claude_md(a) for a in files):
            return True
        if prog == "curl" and any(_is_claude_md(a.split("=", 1)[-1]) for a in args if a.startswith("--output")):
            return True
        if prog == "curl" and any(a == "-o" and _is_claude_md(n) for a, n in zip(args, args[1:])):
            return True
        if prog in ("cp", "mv", "install") and files and _is_claude_md(files[-1]):
            return True
        if prog in ("sed", "perl") and any(re.match(r"-[A-Za-z]*i", a) for a in args) \
                and any(_is_claude_md(a) for a in files):
            return True
    return False


def main():
    if os.environ.get("HARNESS_GUARD", "1") == "0":
        return
    try:
        data = json.load(sys.stdin)
        cmd = data.get("tool_input", {}).get("command", "") or ""
    except Exception:
        return
    if not cmd.strip():
        return
    try:
        segs = list(segments(cmd))
    except ValueError:  # unbalanced quotes: let the shell report it
        return
    cwd = data.get("cwd") or os.getcwd()
    if not os.path.isdir(cwd):
        cwd = os.getcwd()
    for seg in segs:
        env, argv = strip_prefix(seg)
        if argv[:1] == ["cd"] and len(argv) > 1:
            nxt = os.path.join(cwd, os.path.expanduser(argv[1]))
            if os.path.isdir(nxt):
                cwd = nxt
            continue
        if any(e in ("HUSKY", "SKIP_HOOKS", "SKIP") for e in env) and argv[:1] == ["git"]:
            decide("deny", "Disabling git hooks via environment is blocked by INVARIANTS.md. Fix the failing check instead.")
        if not argv:
            continue
        prog = os.path.basename(argv[0])
        if prog == "git":
            check_git(argv, env, cwd)
        elif prog == "rm":
            check_rm(argv)
    if writes_claude_md(cmd, segs):
        decide("deny", CLAUDE_MD_MSG)
    # SQL lives inside quoted strings, so check the raw text here
    if re.search(r"(?i)(^|[^A-Za-z_])(drop|truncate)\s+(table|database|schema)\b", cmd):
        decide("ask", "Destructive SQL detected. Confirm this targets a local or dev database.")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        pass
