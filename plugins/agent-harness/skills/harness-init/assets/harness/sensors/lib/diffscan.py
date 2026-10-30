#!/usr/bin/env python3
"""diffscan.py -- the lines new code adds, for sensors that check only new code. Plugin-owned: don't edit; import it.

    sys.path.insert(0, "scripts/harness/sensors/lib"); from diffscan import added_lines
    for path, lines in added_lines().items():          # {path: {lineno: text}}
        for n, text in lines.items(): ...

Shell sensors: `python3 scripts/harness/sensors/lib/diffscan.py [base]` prints `path:lineno:text` per added line.
New code = everything since the merge-base with the repo's base (make harness-base, else HARNESS_BASE, else origin/HEAD): commits, staged and unstaged edits, untracked files;
planted violations under scripts/harness/sensors/fixtures/ are not new code.
An unresolvable base or merge-base (shallow or single-branch clone, never-fetched remote) exits 2 with a message,
never "no changes": a sensor that silently checks nothing is worse than none.
"""
import codecs, os, re, subprocess, sys

FIXTURES = "scripts/harness/sensors/fixtures/"
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def _git(*args):
    return subprocess.run(["git", *args], capture_output=True)


def _die(msg):
    print("sensor: " + msg, file=sys.stderr)
    sys.exit(2)


def default_base():  # the repo's base (cmd.sh --base: harness-base target, HARNESS_BASE, origin/HEAD), as the stop gate
    top = _git("rev-parse", "--show-toplevel").stdout.decode().strip()
    cmd = os.path.join(top, "scripts", "harness", "cmd.sh")
    if top and os.path.isfile(cmd):
        r = subprocess.run(["bash", cmd, top, "--base"], capture_output=True)
        lines = r.stdout.decode().split()
        if lines:  # exit 1 = a fallback base, still the right order
            return lines[-1]
    if os.environ.get("HARNESS_BASE"):
        return os.environ["HARNESS_BASE"]
    r = _git("symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.decode().strip()
    return "origin/main" if _git("rev-parse", "-q", "--verify", "origin/main").returncode == 0 else "origin/master"


def _path(s):  # "b/x" or "\"b/x\\tab\"" (core.quotePath); None for /dev/null
    if s.startswith('"'):
        s = codecs.escape_decode(s[1:-1].encode())[0].decode("utf-8", "replace")
    return None if s == "/dev/null" else s[2:]


def parse(diff):
    """{path: {lineno: text}} from `git diff -U0` output. "+++ "/"--- " are headers only between "diff --git" and the
    first "@@": an added line "++ x" shows as "+++ x" and a removed "-- x" as "--- x", and both are content."""
    out, path, head, n = {}, None, False, 0
    for line in diff.split("\n"):
        if line.startswith("diff --git "):
            path, head = None, True
        elif line.startswith("@@"):
            head = False
            m = HUNK.match(line)
            n = int(m.group(1)) if m else 0
        elif head:
            if line.startswith("+++ "):
                path = _path(line[4:])
        elif line.startswith("+"):
            if path is not None:
                out.setdefault(path, {})[n] = line[1:]
            n += 1
        elif line.startswith(" "):
            n += 1
    return out


def added_lines(base=None):
    base = base or default_base()
    if _git("rev-parse", "-q", "--verify", base + "^{commit}").returncode != 0:
        _die(f"cannot resolve HARNESS_BASE {base}; fetch it or set HARNESS_BASE")
    mb = _git("merge-base", base, "HEAD")
    if mb.returncode != 0:
        _die(f"cannot resolve HARNESS_BASE {base}: no merge-base with HEAD (shallow clone?); fetch it or set HARNESS_BASE")
    d = _git("-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-ext-diff", "--no-renames", mb.stdout.decode().strip(), "--")
    if d.returncode != 0:
        _die(f"git diff against {base} failed: {d.stderr.decode(errors='replace').strip()}")
    out = parse(d.stdout.decode("utf-8", "replace"))
    u = _git("ls-files", "-z", "--others", "--exclude-standard")
    if u.returncode != 0:
        _die("git ls-files failed: " + u.stderr.decode(errors="replace").strip())
    for p in filter(None, u.stdout.decode("utf-8", "replace").split("\0")):
        try:
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\0" not in data:  # binary files add no lines
            out[p] = {i: t for i, t in enumerate(data.decode("utf-8", "replace").split("\n"), 1)}
            if data.endswith(b"\n"):
                out[p].pop(max(out[p]))
    return {p: v for p, v in out.items() if not p.startswith(FIXTURES)}


if __name__ == "__main__":
    for p, lines in sorted(added_lines(sys.argv[1] if len(sys.argv) > 1 else None).items()):
        for n, t in sorted(lines.items()):
            print(f"{p}:{n}:{t}")
