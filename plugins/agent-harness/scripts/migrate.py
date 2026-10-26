#!/usr/bin/env python3
"""migrate.py -- structural migrations for a harness written by an older plugin version.

Usage: python3 migrate.py <status|apply|diff|accept> [dir] [--skip id,id]
  status  version line, then one line per migration still needed (id, since, layer, kind, what)
  apply   apply the needed `auto` migrations: new files, unedited plugin templates, local .harness state
  diff    print ONE unified diff of every needed `propose` migration (repo-owned files); writes nothing
  accept  write exactly what `diff` shows (run it only after the developer's yes); --skip leaves ids out
Kinds: auto (safe, applied by `apply`), propose (repo-owned edit, needs one yes), manual (needs a
decision or a run: the line says what to do). Every migration detects first, so a second run is a no-op.
Human content is never overwritten: repo-owned files change only through diff + accept.
In a workspace (harness-workspace.json, not a git repo) only workspace files are handled, and each
member whose harness is behind is listed with the command that upgrades it; members are never written.
The recorded plugin version is "plugin" in scripts/harness/assets.json (written by assets.py refresh).
"""
import difflib, hashlib, json, os, re, subprocess, sys

PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True  # never leave __pycache__ in the plugin folder
sys.path.insert(0, os.path.join(PLUGIN, "scripts"))
import assets  # noqa: E402

A = "skills/harness-init/assets"
WA = "skills/harness-workspace/assets"
KEY = r"[A-Z][A-Z0-9]+-[0-9]+"
TEST_RE = re.compile(r"(^|/)(src/test[^/]*|tests?|__tests__|spec)/|\.(test|spec)\.|_test\.(go|py)$|(^|/)test_[^/]*\.py$|Tests?\.[a-z]+$|IT\.[a-z]+$")
OLD_VERIFY = [  # the AGENTS.md Verification bullets written by 2.0.0-2.0.3
    "- Done means `make check` passes. Before claiming done, committing or opening a PR, run the **harness-verify** skill.",
    "- While iterating: `make test T=<path>` (one file or test), `make check-fast` (changed files).",
    "- Runnable surface: `make smoke`. Everything else: `make help`. Run these targets, not raw tool commands.",
    "- If this repo uses another runner, it is registered in `.agents/harness.json`; replace `make` above with that runner.",
]
NEW_VERIFY = [
    "- Done = `{check}` passes (**harness-verify** before claiming done). Fast loop: `{check-fast}`, `{test}`. All commands: `{help}`.",
    "- Run these targets, not raw tool commands.",
]
OLD_WS_VERIFY = [  # workspace AGENTS.md, 2.0.0-2.0.3
    "- Done means `make check` passes here: it runs `make check` inside every repo that changed, with that repo's own gate. Then run the **harness-verify** skill (workspace mode).",
    "- While iterating: `make test R=<repo> T=<path>`, or `make -C <repo> check-fast`. Run make targets, not raw tool commands.",
    "- Overview at any time: `make status` (branch, uncommitted files, commits ahead, harness present per repo).",
]
NEW_WS_VERIFY = [
    "- Done = `make check` passes here (each changed repo's own gate; **harness-verify** in workspace mode before claiming done). Fast loop: `make check-fast`, `make test R=<repo> T=<path>`. All commands: `make help`.",
    "- Run these targets, not raw tool commands.",
]
EVIDENCE = "**Evidence**: local `.harness/evidence/<this file name>` (never committed; shared via the PR description and the tracker comment)"
DEV_VERIFY = re.compile(r"(?s)\n*## Verification\n<!-- harness-verify appends one evidence block per run.*?-->[ \t]*\n*$")  # 2.0.4-dev, empty
ENV_DENY = ["Read(./**/.env)", "Read(./**/.env.local)", "Read(./**/.env.*.local)", "Read(./**/.env.prod*)", "Read(./**/.env.staging*)"]
RUNNER_HELP = {"just": "just --list", "task": "task --list", "npm": "npm run", "pnpm": "pnpm run", "yarn": "yarn run"}


OVERLAY = {}  # path -> text proposed by an earlier migration in this run, so later ones build on it


def read(root, rel):
    if (root, rel) in OVERLAY:
        return OVERLAY[(root, rel)]
    return _read(root, rel)


def _read(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return None


def src(rel):
    with open(os.path.join(PLUGIN, rel), encoding="utf-8") as f:
        return f.read()


def git(root, *args):
    try:
        return subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def act(kind, path=None, new=None, note=""):
    return {"kind": kind, "path": path, "new": new, "note": note}


def plan_dir(root, ws):
    return "plans/active" if ws else "docs/plans/active"


def active_plans(root, ws):
    d = os.path.join(root, plan_dir(root, ws))
    if not os.path.isdir(d):
        return []
    return sorted(plan_dir(root, ws) + "/" + f for f in os.listdir(d) if f.endswith(".md") and f != "TEMPLATE.md")


# ---- migrations: each takes (root, ws) and returns the actions still needed (empty = done) ----

def m_templates(root, ws):
    """Plan / ADR templates carry the Ticket line; plan templates the local Evidence line (no ## Verification section)."""
    pairs = [(WA + "/plans/TEMPLATE.md", "plans/TEMPLATE.md")] if ws else \
        [(A + "/docs/plans/TEMPLATE.md", "docs/plans/TEMPLATE.md"), (A + "/docs/adr/TEMPLATE.md", "docs/adr/TEMPLATE.md")]
    hist, out = assets.load(assets.HISTORY), []
    for s, dest in pairs:
        have, want = read(root, dest), src(s)
        if have == want:
            continue
        if have is None or hashlib.sha256(have.encode("utf-8")).hexdigest() in hist.get(s, {}):
            out.append(act("auto", dest, want, "unedited plugin template → current"))
            continue
        new = have
        if "adr/" in dest:
            if "Ticket" not in new:
                new = re.sub(r"^(\*\*Status\*\*:.*)$", r"\1 · **Ticket**: <KEY-123 | #123 | none>", new, count=1, flags=re.M)
        else:
            if "Ticket" not in new:
                new = add_ticket_line(new, "<KEY-123 | #123 | none (<reason>)>")
            if "**Evidence**" not in new:
                new = add_after_ticket(new, EVIDENCE)
            new = DEV_VERIFY.sub("\n", new)
        if new != have:
            out.append(act("propose", dest, new, "edited template: add the Ticket / Evidence line"))
    return out


def add_after_ticket(text, line):
    lines = text.split("\n")
    at = next((i + 1 for i, l in enumerate(lines) if re.search(r"Ticket\**:", l)), None)
    if at is None:
        return text
    lines.insert(at, line)
    return "\n".join(lines)


def ticket_of(text):  # same reading as lint.sh check 14
    m = re.search(r"(^|[^A-Za-z])Ticket\**:\**[ \t]*(.*)$", text, re.M)
    return re.sub(r"\s+·.*$", "", m.group(2)).strip() if m else None


def ticket_ok(v):
    if not v or "<" in v or re.match(r"^(TODO|tbd|TBD|\[verify\]|none|none *\( *\))$", v):
        return False
    return bool(re.match("^(%s|#[0-9]+|\\.scratch/.*|none \\(.+\\))$" % KEY, v))


def add_ticket_line(text, value):
    lines = text.split("\n")
    at = next((i + 1 for i, l in enumerate(lines) if l.startswith("**Status**")), 1 if lines and lines[0].startswith("#") else 0)
    if at == 1 and len(lines) > 1 and lines[1] == "":
        lines.insert(1, "")
        at = 2
    lines.insert(at, "**Ticket**: " + value)
    return "\n".join(lines)


def branch_key(root):
    slug = git(root, "branch", "--show-current").split("/")[-1]
    m = re.match(r"^([A-Za-z][A-Za-z0-9]+-[0-9]+)", slug)
    return (m.group(1).upper(), slug) if m else (None, slug)


def m_plan_ticket(root, ws):
    """Active plans need a valid Ticket (lint fails without one)."""
    plans, out = active_plans(root, ws), []
    key, slug = (None, "") if ws else branch_key(root)
    for p in plans:
        text = read(root, p) or ""
        v = ticket_of(text)
        if ticket_ok(v):
            continue
        m = re.search(r"\d{4}-\d\d-\d\d-(%s)" % KEY, os.path.basename(p))
        if m:
            val, why = m.group(1), "key from the file name"
        elif key and (len(plans) == 1 or slug.lower()[len(key):].strip("-") in os.path.basename(p).lower()):
            val, why = key, "key from the branch name"
        else:
            val, why = "none (no ticket recorded before 2.0.4)", "no key found: replace with the real key, or keep with a true reason"
        if v is not None:  # an old inline placeholder such as "· **Ticket**: <key>"
            new = re.sub(r"((^|[^A-Za-z])Ticket\**:\**[ \t]*)[^\n]*?(?=\s+·|[ \t]*$)", lambda mm: mm.group(1) + val, text, count=1, flags=re.M)
        else:
            new = add_ticket_line(text, val)
        out.append(act("propose", p, new, "Ticket: %s (%s)" % (val, why)))
    return out


def m_plan_verification(root, ws):
    """Evidence is local now: drop the EMPTY ## Verification section 2.0.4-dev templates put in active plans (never one with entries)."""
    out = []
    for p in active_plans(root, ws):
        text = read(root, p) or ""
        if DEV_VERIFY.search(text):
            out.append(act("propose", p, DEV_VERIFY.sub("\n", text), "remove the empty ## Verification section (evidence lives in .harness/evidence/)"))
    return out


def m_decisions_ticket(root, ws):
    """docs/DECISIONS.md index gains a Ticket column."""
    text = read(root, "docs/DECISIONS.md")
    if text is None:
        return []
    lines, out, table = text.split("\n"), [], False
    for l in lines:
        s = l.rstrip()
        if s.startswith("| ADR ") and s.endswith("|") and "Ticket" not in s:
            table = True
            out.append(s + " Ticket |")
        elif table and s.startswith("|") and s.endswith("|"):
            out.append(s + ("---|" if re.match(r"^\|[-:| ]+\|$", s) else " none |"))
        else:
            table = False
            out.append(l)
    new = "\n".join(out)
    return [act("propose", "docs/DECISIONS.md", new, "add the Ticket column (existing rows: none)")] if new != text else []


def runner_cmds(root):
    """check / check-fast / test / help as AGENTS.md should name them, or None when a registered runner lacks one."""
    try:
        d = json.loads(read(root, ".agents/harness.json") or "{}")
    except ValueError:
        d = {}
    c = d.get("commands") if isinstance(d, dict) else None
    if not isinstance(c, dict) or not c:
        return {"check": "make check", "check-fast": "make check-fast", "test": "make test T=<path>", "help": "make help"}
    word = (str(next(iter(c.values()))).split() or [""])[0]
    out = {"check": c.get("check"), "check-fast": c.get("check-fast"), "test": c.get("test"),
           "help": c.get("help") or d.get("help") or RUNNER_HELP.get(word)}
    if not all(isinstance(v, str) and v for v in out.values()):
        return None
    out["test"] = out["test"].replace("{T}", "<path>") if "{T}" in out["test"] else out["test"] + " <path>"
    return out


def m_agents_verification(root, ws):
    """AGENTS.md Verification in the short form (Done = … · fast loop · all commands)."""
    text = read(root, "AGENTS.md")
    if text is None or "Done = `" in text or "Done means `" not in text:
        return []
    lines = text.split("\n")
    old, new = (OLD_WS_VERIFY, NEW_WS_VERIFY) if ws else (OLD_VERIFY, NEW_VERIFY)
    cmds = {} if ws else runner_cmds(root)
    if not all(b in lines for b in old[:3]) or cmds is None:
        return [act("manual", "AGENTS.md", None, "Verification is the long form (edited by hand, or a runner without check/check-fast/test/help): shorten it to the template's two bullets")]
    first = lines.index(old[0])
    lines = [l for l in lines if l not in old]
    for k, v in cmds.items():
        new = [n.replace("{%s}" % k, v) for n in new]
    lines[first:first] = new
    return [act("propose", "AGENTS.md", "\n".join(lines), "short Verification section")]


def m_harness_json_help(root, ws):
    """.agents/harness.json records the runner's help/list command as "help"."""
    text = read(root, ".agents/harness.json")
    try:
        d = json.loads(text) if text else None
    except ValueError:
        return []
    cmds = d.get("commands") if isinstance(d, dict) else None
    if not isinstance(cmds, dict) or not cmds or "help" in d or "help" in cmds:
        return []
    word = str(next(iter(cmds.values()))).split()[0] if str(next(iter(cmds.values()))).split() else ""
    if word not in RUNNER_HELP:
        return [act("manual", ".agents/harness.json", None, 'add "help": "<runner list command>" (runner %s)' % (word or "?"))]
    new = text.replace("{", '{\n  "help": %s,' % json.dumps(RUNNER_HELP[word]), 1)
    return [act("propose", ".agents/harness.json", new, 'add "help": "%s"' % RUNNER_HELP[word])]


def m_env_deny(root, ws):
    """.claude/settings.json: the broad Read(./.env.*) deny also hid .env.example; deny the real env files instead."""
    p = ".claude/settings.json"
    text = read(root, p)
    if not text or '"Read(./.env.*)"' not in text:
        return []
    add = [e for e in ENV_DENY if '"%s"' % e not in text]
    new = text.replace('"Read(./.env.*)"', ", ".join('"%s"' % e for e in add) if add else "", 1)
    new = re.sub(r",\s*,", ",", re.sub(r"\[\s*,\s*", "[", re.sub(r",\s*\]", "]", new)))
    return [act("propose", p, new, "narrow the .env deny list (.env.example stays readable)")]


def derived_base(root):
    b = git(root, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
    for ref in ([b] if b else []) + ["origin/main", "origin/master"]:
        if git(root, "rev-parse", "-q", "--verify", ref):
            return ref
    return git(root, "rev-parse", "--abbrev-ref", "@{u}") or None


def m_harness_base(root, ws):
    """A HARNESS_BASE pinned to a ref that does not exist: derive it (origin/HEAD, origin/main, origin/master, upstream)."""
    text = read(root, "Makefile")
    m = re.search(r"^HARNESS_BASE[ \t]*[:?]?=[ \t]*(\S+)[ \t]*$", text or "", re.M)
    if ws or not m or "$" in m.group(1) or git(root, "rev-parse", "-q", "--verify", m.group(1)):
        return []
    ref = derived_base(root)
    if not ref:
        return [act("manual", "Makefile", None, "HARNESS_BASE = %s does not exist and no base branch was found: set it" % m.group(1))]
    new = text[:m.start(1)] + ref + text[m.end(1):]
    return [act("propose", "Makefile", new, "HARNESS_BASE %s → %s" % (m.group(1), ref))]


def make_vars(root):  # HARNESS_* variables the repo assigns (Makefile and its own *.mk files)
    text = ""
    for f in ["Makefile", "makefile", "GNUmakefile"] + sorted(x for x in os.listdir(root) if x.endswith(".mk") and x != "harness.mk"):
        text += read(root, f) or ""
    return set(re.findall(r"^[ \t]*(HARNESS_[A-Z_]+)[ \t]*[:?+]?=", text, re.M)), text


def make_runner(root):
    try:
        d = json.loads(read(root, ".agents/harness.json") or "{}")
        return not (isinstance(d, dict) and d.get("commands"))
    except ValueError:
        return True


def m_check_fast_tests(root, ws):
    """check-fast runs tests: HARNESS_TEST_CHANGED via related-tests.sh, or HARNESS_TEST_SECS for a suite <= 60 s."""
    if ws or not os.path.isfile(os.path.join(root, "harness.mk")) or not make_runner(root):
        return []
    have, _ = make_vars(root)
    if "HARNESS_TEST_CHANGED" in have or "HARNESS_TEST_SECS" in have:
        return []
    if not any(TEST_RE.search(f) for f in git(root, "ls-files").split("\n")):
        return []
    return [act("manual", "Makefile", None, "check-fast runs no tests: time the full suite; <= 60 s → HARNESS_TEST_SECS = <secs>, else HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh <stack> \"<runner>\" (layout.md)")]


def m_tool_wiring(root, ws):
    """No tool left on harness.mk's failing default: wire it, or mark it skipped / declined with a not-yet-enforced invariant."""
    if ws or not os.path.isfile(os.path.join(root, "harness.mk")) or not make_runner(root):
        return []
    have, text = make_vars(root)
    out = []
    for var, tgt in (("HARNESS_LINT", "LINT"), ("HARNESS_TEST_ALL", "TEST")):
        if var not in have and not re.search(r"^HARNESS_DEFINE_%s[ \t]*[:?]?=[ \t]*0" % tgt, text, re.M):
            out.append(act("manual", "Makefile", None, '%s is unset (fails "not configured"): wire it, or %s = @echo "%s: skipped (<why>, <date>)" / "none (declined <date>)" plus a not-yet-enforced invariant' % (var, var, tgt.lower())))
    return out


def m_harness_mk_test_plan(root, ws):
    """harness.mk carries harness-test-plan (lint check 13 reads it); a locally modified copy is not refreshed."""
    text = read(root, "harness.mk")
    if ws or text is None or "harness-test-plan:" in text:
        return []
    return [act("manual", "harness.mk", None, "no harness-test-plan target: run assets.py refresh; if modified locally, merge: diff harness.mk \"%s\"" % os.path.join(PLUGIN, A, "harness.mk"))]


def state(root):
    try:
        d = json.loads(read(root, ".harness/init-state.json") or "")
        return d if isinstance(d, dict) else None
    except ValueError:
        return None


def m_init_state_target(root, ws):
    """init-state.json carries the target, so progress is judged by the target's layers (2.0.2)."""
    d = state(root)
    m = re.search(r"Harness target:\**\s*\**(Experimental|Functional|Robust|Enterprise)", read(root, "INVARIANTS.md") or "")
    if ws or d is None or d.get("target") or not m:
        return []
    d["target"] = m.group(1)
    return [act("auto", ".harness/init-state.json", json.dumps(d, indent=2) + "\n", "target %s from INVARIANTS.md" % m.group(1))]


def m_gate_wired(root, ws):
    """gate_wired: true once check-fast resolved and passed; until then the stop gate and git hooks stay off."""
    d = state(root)
    if ws or d is None or d.get("gate_wired") is True:
        return []
    return [act("manual", ".harness/init-state.json", None, "gate not wired: step 4 runs check-fast; on pass set \"gate_wired\": true, else record \"gate_reason\"")]


MIGRATIONS = [  # id, since, layer, function
    ("templates", "2.0.4", "context", m_templates),
    ("plan-ticket", "2.0.4", "context", m_plan_ticket),
    ("plan-verification-empty", "2.0.4", "context", m_plan_verification),
    ("decisions-ticket", "2.0.4", "context", m_decisions_ticket),
    ("agents-verification", "2.0.4", "guides", m_agents_verification),
    ("harness-json-help", "2.0.4", "tools", m_harness_json_help),
    ("env-deny", "2.0.0", "tools", m_env_deny),
    ("harness-base", "2.0.1", "tools", m_harness_base),
    ("init-state-target", "2.0.2", "context", m_init_state_target),
    ("check-fast-tests", "2.0.3", "sensors", m_check_fast_tests),
    ("tool-wiring", "2.0.3", "tools", m_tool_wiring),
    ("gate-wired", "2.0.3", "sensors", m_gate_wired),
    ("harness-mk-test-plan", "2.0.4", "sensors", m_harness_mk_test_plan),
]


def is_workspace(root):
    return os.path.isfile(os.path.join(root, "harness-workspace.json")) and not os.path.exists(os.path.join(root, ".git"))


def needed(root, skip=()):
    ws, out = is_workspace(root), []
    for k in [k for k in OVERLAY if k[0] == root]:
        del OVERLAY[k]
    for mid, since, layer, fn in MIGRATIONS:
        if mid in skip:
            continue
        for a in fn(root, ws):
            out.append((mid, since, layer, a))
            if a["new"] is not None:
                OVERLAY[(root, a["path"])] = a["new"]
    return out


def recorded(root):
    return assets.load(os.path.join(root, assets.MANIFEST)).get("plugin") or "unknown (before 2.0.2)"


def members(root):
    try:
        with open(os.path.join(root, "harness-workspace.json")) as f:
            repos = json.load(f).get("repos", [])
    except (OSError, ValueError, AttributeError):
        return []
    out = []
    for r in repos:
        if not isinstance(r, dict) or not r.get("name"):
            continue
        p = os.path.join(root, r.get("path", r["name"]))
        if not os.path.isfile(os.path.join(p, "AGENTS.md")):
            continue
        stale = sum(1 for x in assets.states(p) if x[2] == "stale")
        n = len(needed(p))
        if stale or n or recorded(p) != assets.version():
            out.append("member    %s: plugin %s, %d stale asset(s), %d migration(s) — run /agent-harness:harness-upgrade %s"
                       % (r["name"], recorded(p), stale, n, r["name"]))
    return out


def write(root, rel, new):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(new)


def main(argv):
    argv, skip = list(argv[1:]), set()
    for i, a in enumerate(argv):
        if a.startswith("--skip"):
            skip |= set((a.split("=", 1)[1] if "=" in a else (argv[i + 1] if i + 1 < len(argv) else "")).split(","))
            argv[i:i + (1 if "=" in a else 2)] = []
            break
    cmd = argv[0] if argv else "status"
    root = os.path.abspath(argv[1] if len(argv) > 1 else ".")
    if cmd not in ("status", "apply", "diff", "accept"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    rows = needed(root, skip)
    if cmd == "status":
        print("plugin: recorded %s · running %s" % (recorded(root), assets.version()))
        for mid, since, layer, a in rows:
            print("%-8s %s (%s, %s)%s — %s" % (a["kind"], mid, since, layer, " " + a["path"] if a["path"] else "", a["note"]))
        if is_workspace(root):
            for line in members(root):
                print(line)
        k = [a["kind"] for _, _, _, a in rows]
        print("migrations: %d needed (%d auto, %d propose, %d manual)" % (len(k), k.count("auto"), k.count("propose"), k.count("manual")))
        return 0
    kind = "auto" if cmd == "apply" else "propose"
    paths = sorted(set(a["path"] for _, _, _, a in rows if a["kind"] == kind))
    final = dict((a["path"], a["new"]) for _, _, _, a in rows if a["kind"] == kind)  # last edit holds every earlier one
    for path in paths:
        if cmd == "diff":
            old = _read(root, path) or ""
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), final[path].splitlines(True), "a/" + path, "b/" + path))
        else:
            write(root, path, final[path])
            print("%s %s" % ("applied " if kind == "auto" else "accepted", path))
    if cmd != "diff":
        print("migrations: %d file(s) %s" % (len(paths), "applied" if kind == "auto" else "accepted"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
