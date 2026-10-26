#!/usr/bin/env python3
"""level.py <repo-dir> [--json] [--log] [--run-checks] [--health N] -- measured harness level, layer scores, blockers."""
import datetime, json, os, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LEVELS = ["none", "Experimental", "Functional", "Robust", "Enterprise"]
LAYERS = ["guides", "sensors", "context", "tools", "observability"]
CI_FILES = [".github/workflows/*.yml", ".github/workflows/*.yaml", ".gitlab-ci.yml", ".circleci/config.yml", "Jenkinsfile"]
LOG_HEADER = "# Harness audit log\n\n| date | level | layers | health | tokens |\n|---|---|---|---|---|\n"


def read(p):
    try:
        return Path(p).read_text(errors="replace")
    except OSError:
        return ""


def run(cmd, cwd, timeout, shell=False):
    try:
        r = subprocess.run(cmd, cwd=cwd, shell=shell, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout + r.stderr
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def invariants(repo):
    """[(section, line)] for '- ' bullets that carry 'Enforced by:'."""
    out, sec = [], ""
    for ln in read(repo / "INVARIANTS.md").splitlines():
        if ln.startswith("## "):
            sec = ln[3:].strip()
        elif re.match(r"[-*]\s", ln) and "Enforced by:" in ln and not re.match(r"[-*]\s+[`<]*<", ln):
            out.append((sec, ln))
    return out


def unenforced(ln):
    v = ln.split("Enforced by:", 1)[1].strip().lower()
    return v.startswith("not yet enforced") or v.startswith("<")


def machine_enforced(ln):
    v = ln.split("Enforced by:", 1)[1].strip().lower()
    return not unenforced(ln) and not re.match(r"(human|verifier|reviewer|manual)", v)


def lint(repo):
    p = repo / "scripts/harness/lint.sh"
    if not p.is_file():
        p = HERE.parent / "skills/harness-init/assets/lint.sh"
    return run(["bash", str(p)], repo, 60) if p.is_file() else (1, "lint.sh not found")


def ci_text(repo):
    return "\n".join(read(f) for g in CI_FILES for f in repo.glob(g))


def tokens(repo):
    return sum(len(read(repo / f)) for f in ("CLAUDE.md", "AGENTS.md", "INVARIANTS.md")) // 4


def check_passes(repo, run_checks, extra=None):
    if run_checks:
        rc, cmd = run(["bash", str(HERE / "harness-cmd.sh"), str(repo), "check"], repo, 30)
        return rc == 0 and run(cmd.strip(), repo, 600, shell=True)[0] == 0
    return any(" pass " in read(f) for f in [repo / ".harness/last-check", extra] if f)


def audit_rows(repo):
    rows = re.findall(r"^\|\s*\d{4}-\d\d-\d\d\s*\|\s*(\w+)\s*\|", read(repo / "docs/harness/AUDIT-LOG.md"), re.M)
    return [LEVELS.index(r) for r in rows if r in LEVELS]


def members(repo, run_checks, seen):
    """({name: level}, [notes]) or None when the manifest is unreadable."""
    try:
        reps = json.loads(read(repo / "harness-workspace.json"))["repos"]
        assert isinstance(reps, list)
    except (ValueError, KeyError, AssertionError, TypeError):
        return None
    res, notes = {}, []
    for m in reps:
        if not isinstance(m, dict) or not m.get("name") or not m.get("path"):
            notes.append(f"workspace entry missing name/path: {m!r}")
            continue
        lab = re.sub(r"[^A-Za-z0-9_-]", "_", str(m["name"]))
        res[m["name"]] = measure(repo / m["path"], run_checks, repo / f".harness/last-check-{lab}", seen)["level"]
    return res, notes


def measure(repo, run_checks=False, ws_check=None, seen=frozenset()):
    repo = Path(repo).resolve()
    if repo in seen:  # member path loops back to an ancestor workspace
        return {"level": "none"}
    seen = seen | {repo}
    inv = invariants(repo)
    settings = {}
    try:
        settings = json.loads(read(repo / ".claude/settings.json"))
    except ValueError:
        pass
    lrc, lout = lint(repo)
    agents = read(repo / "AGENTS.md")
    claude = repo / "CLAUDE.md"
    ci = ci_text(repo)

    # --- criteria: (layer, bool, reason shown when failing) ---
    def crit_files():
        ok = (repo / "AGENTS.md").is_file() and (repo / "INVARIANTS.md").is_file()
        return ok, "AGENTS.md and INVARIANTS.md must both exist"

    def crit_shim():
        return (not claude.exists() or "@AGENTS.md" in read(claude)), "CLAUDE.md is not a shim"

    def crit_lint():
        return lrc == 0, "lint fails (run scripts/harness/lint.sh)"

    def crit_check():
        return check_passes(repo, run_checks, ws_check), "check not passing (no .harness/last-check pass; run with --run-checks)"

    def crit_auto():
        hp = run(["git", "config", "core.hooksPath"], repo, 10)[1].strip()
        mgr = "".join(read(repo / f) for f in ("lefthook.yml", ".pre-commit-config.yaml")) + "".join(
            read(f) for f in (repo / ".husky").glob("*") if f.is_file())
        ok = ((repo / ".githooks/pre-commit").is_file() and hp == ".githooks") or "check-fast" in mgr or re.search(r"\bcheck\b(?!-)", ci)
        return bool(ok), "no automatic enforcement (git hook, hook manager running check-fast, or CI running check)"

    def crit_enforced():
        return any(machine_enforced(l) for _, l in inv), "no invariant is machine-enforced (make target, sensor, hook, lint, test or CI job); human review does not count"

    def crit_plans():
        return (repo / "docs/plans").is_dir(), "docs/plans/ missing"

    def crit_deny():
        return bool(settings.get("permissions", {}).get("deny")), "no permission rules in .claude/settings.json"

    def crit_sensors():
        try:
            n = len(json.loads(read(repo / "scripts/harness/sensors/registry.json")).get("sensors", []))
        except ValueError:
            n = 0
        proof = repo / "scripts/harness/sensor-proof.sh"
        ok = n >= 1 and proof.is_file() and run(["bash", str(proof), "--recheck"], repo, 60)[0] == 0
        return ok, "no sensors in registry, or sensor recheck not passing"

    def crit_budget():
        bad = [l for l in lout.splitlines() if l.startswith("FAIL") and "(max" in l]
        return not bad, "lint budget failure: " + "; ".join(b[6:] for b in bad[:2])

    def crit_cadence():
        return "Cadence" in agents, "AGENTS.md has no Cadence section"

    def crit_security():
        n = sum(1 for s, l in inv if s in ("Security", "Data Integrity") and unenforced(l))
        return n == 0, f"{n} security/data invariants not yet enforced"

    def crit_ci():
        return bool(re.search(r"\bcheck\b(?!-)", ci)), "no CI file runs check"

    def crit_plugins():
        return any("agent-harness" in k for k in settings.get("enabledPlugins", {})), "enabledPlugins does not pin the harness"

    def crit_codeowners():
        t = "".join(read(repo / f) for f in ("CODEOWNERS", ".github/CODEOWNERS", "docs/CODEOWNERS"))
        return all(f in t for f in ("AGENTS.md", "INVARIANTS.md")), "CODEOWNERS does not cover AGENTS.md and INVARIANTS.md"

    def crit_auditlog():
        r = audit_rows(repo)
        return len(r) >= 2 and r[-1] >= r[-2], "AUDIT-LOG.md needs 2+ rows with a non-regressing last level"

    def crit_workspace():
        if not (repo / "harness-workspace.json").is_file():
            return True, ""
        r = members(repo, run_checks, seen)
        if r is None:
            return False, "harness-workspace.json unreadable"
        low = [n for n, v in r[0].items() if LEVELS.index(v) < 2]
        return not low and not r[1], "; ".join(r[1] + (["workspace members below Functional: " + ", ".join(low)] if low else []))

    tiers = [
        ("Experimental", [("guides", crit_files), ("guides", crit_shim), ("context", crit_lint)]),
        ("Functional", [("sensors", crit_check), ("sensors", crit_auto), ("guides", crit_enforced)]),
        ("Robust", [("context", crit_plans), ("tools", crit_deny), ("sensors", crit_sensors), ("context", crit_budget),
                    ("observability", crit_cadence), ("guides", crit_security)]),
        ("Enterprise", [("sensors", crit_ci), ("tools", crit_plugins), ("guides", crit_codeowners),
                        ("observability", crit_auditlog), ("observability", crit_workspace)]),
    ]
    level, blockers, per = "none", None, {k: [0, 0, []] for k in LAYERS}
    for name, crits in tiers:
        fails = []
        for layer, fn in crits:
            ok, why = fn()
            per[layer][1] += 1
            per[layer][0] += ok
            if not ok:
                per[layer][2].append(why)
                fails.append(why)
        if blockers is None:
            if fails:
                blockers = fails
            else:
                level = name
    target = next((m.group(1) for m in re.finditer(r"Harness target:\s*(Experimental|Functional|Robust|Enterprise)", read(repo / "INVARIANTS.md"))), "Robust")
    return {"level": level, "target": target,
            "layers": {k: {"score": round(v[0] / v[1], 2), "missing": v[2]} for k, v in per.items()},
            "next_level_blockers": blockers or [], "tokens": tokens(repo)}


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    health = argv[argv.index("--health") + 1] if "--health" in argv else None
    if health:
        args.remove(health)
    if not args:
        print("usage: level.py <repo-dir> [--json] [--log] [--run-checks] [--health N]", file=sys.stderr)
        return 2
    repo = Path(args[0])
    res = measure(repo, "--run-checks" in argv)
    if "--log" in argv:
        log = repo / "docs/harness/AUDIT-LOG.md"
        log.parent.mkdir(parents=True, exist_ok=True)
        if not log.is_file():
            log.write_text(LOG_HEADER)
        ls = res["layers"]
        sc = " ".join(f"{k[0]}={ls[k]['score']:.2f}" for k in LAYERS)
        with log.open("a") as f:
            f.write(f"| {datetime.date.today()} | {res['level']} | {sc} | health={health or '-'} | tokens={res['tokens']} |\n")
    if "--json" in argv:
        print(json.dumps(res, indent=2))
    else:
        print(f"{res['level']} (target {res['target']})" + "".join(f"\n  - {b}" for b in res["next_level_blockers"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
