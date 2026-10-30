#!/usr/bin/env python3
"""PreToolUse(Bash) guard for agent-harness.

Parses the command into segments and argv tokens (quotes respected), so text inside
commit messages or grep patterns never triggers a rule. Prints a PreToolUse decision
JSON for deny/ask; prints nothing to allow. An internal error asks (fails closed).
"""
import json
import os
import re
import shlex
import subprocess
import sys

SEPARATORS = {";", "&&", "||", "|", "&", "\n", "(", ")"}
WRAPPERS = {"sudo", "env", "command", "time", "nice", "nohup", "xargs"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
MAX_DEPTH = 3  # nested `bash -c` / `eval` payloads checked
# guarded git long options -> shortest prefix git could accept for them (git takes unambiguous abbreviations)
LONG_MIN = {"--no-verify": "--no-ve", "--force": "--for", "--force-with-lease": "--force-w",
            "--hard": "--ha", "--delete": "--de"}


def has_long(longs, opt):
    """True if any long option is `opt` or an abbreviation git could expand to it."""
    return any(l == opt or (len(l) >= len(LONG_MIN[opt]) and opt.startswith(l)) for l in longs)


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

    if has_long(longs, "--no-verify") or (sub == "commit" and "n" in flags):
        decide("deny", "Bypassing git hooks (--no-verify / -n) is blocked by INVARIANTS.md. Fix the failing check instead.")
    if sub == "config" and any(a.lower() == "core.hookspath" for a in args):
        # the one allowed write: point this checkout at the repo's own .githooks (what make setup does)
        k = [a.lower() for a in args].index("core.hookspath")
        pre = [a for a in args[:k] if not a.startswith("-")]  # "get"/"set"/"unset" subcommand form
        rest = args[k + 1:]
        opts = {a for a in args if a.startswith("-")}
        reading = not rest and pre in ([], ["get"]) and opts <= {"--get", "--local"}
        if not reading and not (len(rest) == 1 and rest[0].rstrip("/") in (".githooks", "./.githooks")
                                and pre in ([], ["set"]) and opts <= {"--local"}):
            decide("deny", "Changing core.hooksPath bypasses git hooks. Only `git config core.hooksPath .githooks` is allowed; ask a human otherwise.")
    if sub == "push":
        refspecs = [a for a in args if not a.startswith("-")]
        force = has_long(longs, "--force") or "f" in flags or any(r.startswith("+") for r in refspecs)
        if force:
            decide("deny", "Force-push is blocked by the harness. Use --force-with-lease on your own branch, or ask a human.")
        target = default_branch(cwd)
        names = [r.split(":")[-1] for r in refspecs[1:]]
        if target in names or f"refs/heads/{target}" in names or (not names and current_branch(cwd) == target):
            decide("ask", f"Pushing to {target}. AGENTS.md Agent Authorization normally requires a human for this.")
        if has_long(longs, "--force-with-lease"):
            decide("ask", "Force-with-lease push rewrites remote history. Confirm this is your own branch.")
    if sub in ("merge", "cherry-pick") or (sub == "pull" and args[:1] == ["."]):
        red = red_branch(cwd, [r for a in args if not a.startswith("-") for r in a.split("..") if r])
        if red:
            decide("deny", red)
    if sub == "reset" and has_long(longs, "--hard"):
        decide("deny", "git reset --hard is blocked: it destroys uncommitted work. Use git stash, or ask a human.")
    if sub == "clean" and ("f" in flags or has_long(longs, "--force")):
        decide("deny", "git clean -f is blocked: it deletes untracked files permanently. List them with git clean -n and ask.")
    if sub in ("checkout", "restore"):
        paths = [a for a in args if not a.startswith("-")]
        staged_only = sub == "restore" and ("--staged" in longs or "S" in flags) and not ("--worktree" in longs or "W" in flags)
        if not staged_only and any(p in (".", "./", ":/", "*") for p in paths):
            decide("deny", "Discarding all working-tree changes is blocked. Restore specific files, or ask a human.")
    if sub == "branch" and ("D" in flags or (has_long(longs, "--delete") and (has_long(longs, "--force") or "f" in flags))):
        decide("deny", "Force-deleting a branch can drop unmerged work. Use git branch -d, or ask a human.")
    if sub == "stash" and args[:1] == ["clear"]:
        decide("deny", "git stash clear deletes every stash permanently. Drop specific stashes, or ask a human.")


def red_branch(cwd, refs):
    """Deny reason when a ref is a branch whose implementer subagent last stopped with check-fast failing in its worktree."""
    try:
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True, cwd=cwd, timeout=5).stdout.strip()
    except Exception:
        return None
    red = os.path.join(cwd, common, "harness-red")
    for r in refs:
        f = os.path.join(red, re.sub(r"[^A-Za-z0-9_.-]", "_", r[len("refs/heads/"):] if r.startswith("refs/heads/") else r))
        if os.path.isfile(f):
            line = (open(f).read().split("\n") or [""])[0].split("\t")
            wt = line[1] if len(line) > 1 else "its worktree"
            return ("Branch %s is red: its implementer stopped with check-fast failing in %s. Don't merge it yet: send the failures back to "
                    "that implementer (it is re-checked when it stops again) or fix them there, then run check-fast in that worktree; "
                    "once it passes, remove %s." % (r, wt, f))
    return None


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


ENV_MSG = "Writing to .env is blocked: secrets files are human-managed. Update .env.example instead."
ENV_TEMPLATES = {".env.example", ".env.sample", ".env.template"}


def _is_claude_md(t):
    return os.path.basename(t.rstrip("/")) == "CLAUDE.md"


def _is_env(t):
    b = os.path.basename(t.rstrip("/"))
    return (b == ".env" or b.startswith(".env.")) and b not in ENV_TEMPLATES


def writes_target(cmd, segs, is_target):
    """True if the command writes a file matching is_target (redirect, tee, cp/mv/install, curl -o, sed/perl -i)."""
    # shortcut: redirects are found in text whose quoted strings became placeholders (so a `>` inside a
    # commit message is ignored, but `> ".env"` is not); heredoc bodies / escaped quotes can fool it
    quoted = []

    def hide(m):
        quoted.append(m.group(1) if m.group(1) is not None else m.group(2))
        return "\0%d\0" % (len(quoted) - 1)
    bare = re.sub(r"\"([^\"]*)\"|'([^']*)'", hide, cmd)
    for t in re.findall(r"(?<![0-9&<])>>?\s*([^\s;&|()<>]+)", bare):
        if is_target(re.sub(r"\0(\d+)\0", lambda m: quoted[int(m.group(1))], t)):
            return True
    for seg in segs:
        _, argv = strip_prefix(seg)
        if not argv:
            continue
        prog, args = os.path.basename(argv[0]), argv[1:]
        files = [a for a in args if not a.startswith("-")]
        if prog == "tee" and any(is_target(a) for a in files):
            return True
        if prog == "curl" and any(is_target(a.split("=", 1)[-1]) for a in args if a.startswith("--output")):
            return True
        if prog == "curl" and any(a == "-o" and is_target(n) for a, n in zip(args, args[1:])):
            return True
        if prog in ("cp", "mv", "install") and files and is_target(files[-1]):
            return True
        if prog in ("sed", "perl") and any(re.match(r"-[A-Za-z]*i", a) for a in args) \
                and any(is_target(a) for a in files):
            return True
    return False


HOOKS_OFF = {"HUSKY", "SKIP_HOOKS", "SKIP"}
DECLARERS = {"export", "declare", "typeset", "readonly", "local"}
HOOKS_OFF_MSG = "Disabling git hooks via environment is blocked by INVARIANTS.md. Fix the failing check instead."


def hooks_off_names(env, argv):
    """HOOKS_OFF names a segment sets: a prefix (`X=1 cmd`, `env X=1 cmd`), a bare `X=1`, or export/declare X[=1]."""
    names = set(env)
    if argv and os.path.basename(argv[0]) in DECLARERS:
        names |= {a.split("=", 1)[0] for a in argv[1:] if not a.startswith("-")}
    return names & HOOKS_OFF


INIT_STATE_MSG = ("The harness gate is wired: .harness/init-state.json must keep \"gate_wired\": true (the git hooks skip "
                  "without it). Fix the failing check instead; a human can rerun /agent-harness:harness-upgrade.")


def _is_init_state(t):
    t = t.rstrip("/")
    return os.path.basename(t) == "init-state.json" and os.path.basename(os.path.dirname(t)) == ".harness"


def gate_wired(cwd):
    """True if the repo at cwd has .harness/init-state.json with "gate_wired": true."""
    roots = {cwd}
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                             timeout=3, cwd=cwd).stdout.strip()
        if top:
            roots.add(top)
    except Exception:
        pass
    for r in roots:
        try:
            if json.load(open(os.path.join(r, ".harness", "init-state.json"))).get("gate_wired") is True:
                return True
        except Exception:
            continue
    return False


def writes_init_state(cmd, segs):
    """"deny" for a shell write to .harness/init-state.json (redirect/tee/cp/sed -i), "ask" for an inline
    interpreter that may write it, else None. Redirects are judged by their target, so reads piped elsewhere pass."""
    if writes_target(cmd, segs, _is_init_state):
        return "deny"
    # shortcut: an inline script naming the file plus a write call only asks; a script file it runs is not inspected
    progs = {os.path.basename(strip_prefix(s)[1][0]) for s in segs if strip_prefix(s)[1]}
    interp = any(re.match(r"^(python[0-9.]*|node|perl|ruby)$", p) for p in progs)
    if interp and "init-state.json" in cmd and re.search(r"""open\([^)]*['"][wax+]|\.write\(|writeFile|-i\b""", cmd):
        return "ask"
    return None


def _is_invariants(t):
    return os.path.basename(t.rstrip("/")) == "INVARIANTS.md"


def infra_ask(prog, args):
    """Reason to ask before a command that destroys cluster or cloud resources, else None."""
    pos = [a for a in args if not a.startswith("-")]
    if prog in ("kubectl", "helm"):  # subcommand = first word not taken by a global flag's value (-n ns, --context x)
        pos, skip = [], False
        for a in args:
            if skip:
                skip = False
            elif a in ("-n", "--namespace", "--context", "--kube-context", "--kubeconfig", "--cluster", "--user", "-s", "--server"):
                skip = True
            elif not a.startswith("-"):
                pos.append(a)
    if prog == "kubectl" and pos[:1] == ["delete"]:
        return "kubectl delete removes cluster resources. Confirm the context and namespace are local or dev."
    if prog in ("terraform", "tofu"):
        sub = pos[:1]
        if sub == ["destroy"] or (sub == ["apply"] and any(a.lstrip("-") in ("auto-approve", "auto-approve=true") for a in args)):
            return "terraform %s changes real infrastructure without a review step. Confirm the workspace/state is local or dev." % sub[0]
    if prog == "helm" and pos[:1] and pos[0] in ("uninstall", "delete", "del", "un"):
        return "helm uninstall removes a release from the cluster. Confirm the kube context is local or dev."
    return None


MAKE_ARG_FLAGS = set("CfIjloWE")  # short make flags that take a value


def make_ask(env, prog, args):
    """Reason to ask before `make` runs code from the command line, else None. A pre-approved `Bash(make test:*)` also
    approves `make test HARNESS_TEST_ONE='<cmd>'`, --eval, -f <file> or MAKEFLAGS=-e. Only the harness's own parameters pass:
    T= (harness.mk checks it is plain data) and dev-check's RUN= (a command by design)."""
    if prog not in ("make", "gmake"):
        return None
    why = "make with %s runs whatever command it carries, outside the targets the harness defines. Confirm it was intended."
    bad = [e for e in env if e in ("MAKEFLAGS", "MFLAGS", "GNUMAKEFLAGS", "MAKEFILES") or e.startswith("HARNESS_")]
    if bad:
        return why % ("%s set in its environment" % bad[0])
    skip = False
    for a in args:
        if skip:
            skip = False
        elif a.startswith("--"):
            if a.split("=", 1)[0] in ("--eval", "--file", "--makefile", "--environment-overrides"):
                return why % a.split("=", 1)[0]
        elif a.startswith("-") and len(a) > 1:
            for k, c in enumerate(a[1:]):
                if c in "fEe":
                    return why % ("-" + c)
                if c in MAKE_ARG_FLAGS:
                    skip = k == len(a) - 2  # the value is the next token
                    break
        else:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_.-]*?)[:+?!]?=", a)
            if m and m.group(1) not in ("T", "RUN"):
                return why % ("the variable override %s" % m.group(1))
    return None


READERS = {"grep", "rg", "cat", "less", "head", "tail", "sed", "awk", "echo", "printf", "git", "ls", "find", "diff", "wc"}
DEV_MSG = ("Agents don't leave the dev server running. Use `make dev-check` (starts it, waits for HARNESS_HEALTH, "
           "runs RUN='<cmd>' if given, then stops it); `make dev-stop` stops a leftover one. "
           "Ask the developer to run `make dev` themselves if they want it up.")


def dev_rules(cwd):
    """(repo offers dev-check, HARNESS_DEV_BLOCK words) from the nearest directory up holding harness.mk.
    dev-check is offered once the Makefile sets HARNESS_HEALTH or defines its own dev-check target."""
    d = os.path.abspath(cwd)
    while not os.path.isfile(os.path.join(d, "harness.mk")):
        if os.path.dirname(d) == d:
            return False, []
        d = os.path.dirname(d)
    words, offered = [], False
    for f in ("Makefile", "makefile", "GNUmakefile"):
        try:
            with open(os.path.join(d, f), errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        words += [w for m in re.finditer(r"^HARNESS_DEV_BLOCK\s*[:?]?=(.*)$", text, re.M) for w in m.group(1).split()]
        offered = offered or bool(re.search(r"^(HARNESS_HEALTH\s*[:?]?=\s*\S|dev-check:)", text, re.M))
    return offered, words


def long_lived_dev(prog, argv, cwd):
    """`make dev` (once harness.mk offers dev-check) or a HARNESS_DEV_BLOCK word run as the program or its argument."""
    has_check, words = dev_rules(cwd)
    if has_check and prog in ("make", "gmake") and "dev" in argv[1:]:
        return True
    return prog not in READERS and any(w == prog or w in argv[1:] for w in words)


def payloads(argv):
    """Command strings a segment runs indirectly: `bash|sh|zsh -c '<cmd>'` and `eval <cmd>`."""
    prog = os.path.basename(argv[0])
    if prog == "eval":
        return [" ".join(argv[1:])]
    if prog in SHELLS:
        for k, a in enumerate(argv[1:-1], 1):
            if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
                return [argv[k + 1]]
    return []


def check(cmd, cwd, depth=0):
    if not cmd.strip():
        return
    try:
        segs = list(segments(cmd))
    except ValueError:  # unbalanced quotes: let the shell report it
        return
    asks = []
    off = set()
    for seg in segs:
        off |= hooks_off_names(*strip_prefix(seg))
    runs_git = any(strip_prefix(s)[1][:1] == ["git"] for s in segs)
    # SKIP_HOOKS is the harness's own switch: refused however it is set; HUSKY/SKIP when this line runs git
    if "SKIP_HOOKS" in off or (off and runs_git):
        decide("deny", HOOKS_OFF_MSG)
    for seg in segs:
        env, argv = strip_prefix(seg)
        if argv[:1] == ["cd"] and len(argv) > 1:
            nxt = os.path.join(cwd, os.path.expanduser(argv[1]))
            if os.path.isdir(nxt):
                cwd = nxt
            continue
        if not argv:
            continue
        prog = os.path.basename(argv[0])
        a = infra_ask(prog, argv[1:]) or make_ask(env, prog, argv[1:])
        if a:
            asks.append(a)
        if long_lived_dev(prog, argv, cwd):
            decide("deny", DEV_MSG)
        if prog == "git":
            check_git(argv, env, cwd)
        elif prog == "rm":
            check_rm(argv)
        elif depth < MAX_DEPTH:
            for p in payloads(argv):
                check(p, cwd, depth + 1)
    if writes_target(cmd, segs, _is_claude_md):
        decide("deny", CLAUDE_MD_MSG)
    if writes_target(cmd, segs, _is_env):
        decide("deny", ENV_MSG)
    how = "init-state.json" in cmd and writes_init_state(cmd, segs)
    if how and gate_wired(cwd):
        decide(how, INIT_STATE_MSG)
    if writes_target(cmd, segs, _is_invariants):
        decide("ask", "INVARIANTS.md changes need human sign-off (Harness Integrity). Confirm this edit was requested.")
    if asks:
        decide("ask", asks[0])
    # SQL lives inside quoted strings, so check the raw text here
    if re.search(r"(?i)(^|[^A-Za-z_])(drop|truncate)\s+(table|database|schema)\b", cmd):
        decide("ask", "Destructive SQL detected. Confirm this targets a local or dev database.")


def main():
    if os.environ.get("HARNESS_GUARD", "1") == "0":
        return
    data = json.load(sys.stdin)
    cmd = data.get("tool_input", {}).get("command", "") or ""
    cwd = data.get("cwd") or os.getcwd()
    if not os.path.isdir(cwd):
        cwd = os.getcwd()
    check(cmd, cwd)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # fail closed: an unparsed command could be anything
        decide("ask", "agent-harness Bash guard error (%s: %s); review this command yourself." % (type(e).__name__, e))
