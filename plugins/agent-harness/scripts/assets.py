#!/usr/bin/env python3
"""assets.py -- keep a repo's copies of plugin-owned harness scripts in step with the plugin.

Usage: python3 assets.py <status|refresh|install|count> [dir]
  status   one line per asset that is stale (an older plugin copy, unmodified), modified (edited here) or missing
  refresh  update stale copies; never overwrite modified ones; record hashes in scripts/harness/assets.json
  install  refresh, plus copy missing assets and missing repo-owned starters (sensors/registry.json, fixtures)
  count    print the number of stale assets (for the session hook)
Only plugin-owned files are handled. Repo-owned files (Makefile, AGENTS.md, INVARIANTS.md,
sensors/registry.json, sensor fixtures, project sensors) are never listed or touched.
A copy counts as unmodified when its sha256 matches the manifest or a released plugin copy (asset-history.json).
"""
import hashlib, json, os, shutil, sys

PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HISTORY = os.path.join(PLUGIN, "scripts", "asset-history.json")
MANIFEST = "scripts/harness/assets.json"
A = "skills/harness-init/assets"


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def version():
    return load(os.path.join(PLUGIN, ".claude-plugin", "plugin.json")).get("version", "?")


def assets(root):
    """(plugin source, repo destination) pairs; a folder with harness-workspace.json is a workspace."""
    pairs = [("scripts/harness-cmd.sh", "scripts/harness/cmd.sh")]
    if root is None or os.path.isfile(os.path.join(root, "harness-workspace.json")):
        pairs.append(("skills/harness-workspace/assets/ws.sh", "ws.sh"))
        pairs.append((A + "/harness/plan-check.sh", "scripts/harness/plan-check.sh"))
        if root is not None:
            return pairs
    pairs += [(A + "/lint.sh", "scripts/harness/lint.sh"), (A + "/harness.mk", "harness.mk")]
    pairs += [p for p in harness_files() if not repo_owned(p[1])]
    for f in sorted(os.listdir(os.path.join(PLUGIN, A, "githooks"))):
        pairs.append((A + "/githooks/" + f, ".githooks/" + f))
    return pairs


def repo_owned(dest):  # starters the repo then edits: its own sensor registry and planted fixtures
    return dest == "scripts/harness/sensors/registry.json" or dest.startswith("scripts/harness/sensors/fixtures/")


def harness_files():
    base, out = os.path.join(PLUGIN, A, "harness"), []
    for d, _, files in os.walk(base):
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(d, f), base).replace(os.sep, "/")
            out.append((A + "/harness/" + rel, "scripts/harness/" + rel))
    return out


def states(root):
    man = load(os.path.join(root, MANIFEST)).get("sha256", {})
    hist = load(HISTORY)
    out = []
    for src, dest in assets(root):
        p, want = os.path.join(root, dest), sha(os.path.join(PLUGIN, src))
        if not os.path.isfile(p):
            out.append((src, dest, "missing", "", want))
            continue
        have = sha(p)
        known = hist.get(src, {})
        if have == want:
            st = "current"
        elif have == man.get(dest) or have in known:
            st = "stale"
        else:
            st = "modified"
        out.append((src, dest, st, known.get(have, ""), want))
    return out


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    root = os.path.abspath(argv[2] if len(argv) > 2 else ".")
    if cmd not in ("status", "refresh", "install", "count"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    rows = states(root)
    if cmd == "count":
        print(sum(1 for r in rows if r[2] == "stale"))
        return 0
    v = version()
    man = load(os.path.join(root, MANIFEST))
    shas = man.get("sha256") if isinstance(man.get("sha256"), dict) else {}
    counts = {}
    for src, dest, st, was, want in rows:
        if cmd != "status" and (st == "stale" or (st == "missing" and cmd == "install")):
            p = os.path.join(root, dest)
            os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
            shutil.copy(os.path.join(PLUGIN, src), p)  # copies the exec bit too
            print("%s %s%s" % ("updated  " if st == "stale" else "installed", dest, " (was %s)" % was if was else ""))
            st = "current"
        if st == "current":
            shas[dest] = want
        elif st == "stale":
            print("stale     %s (plugin %s%s) — run /agent-harness:harness-upgrade to refresh" % (dest, v, ", copy from " + was if was else ""))
        elif st == "modified":
            print("modified  %s — modified locally, review diff: diff %s \"%s\"" % (dest, dest, os.path.join(PLUGIN, src)))
        elif st == "missing":
            print("missing   %s" % dest)
        counts[st] = counts.get(st, 0) + 1
    if cmd == "install" and not os.path.isfile(os.path.join(root, "harness-workspace.json")):
        for src, dest in harness_files():
            p = os.path.join(root, dest)
            if repo_owned(dest) and not os.path.exists(p):  # copied once, never tracked or refreshed
                os.makedirs(os.path.dirname(p), exist_ok=True)
                shutil.copy(os.path.join(PLUGIN, src), p)
                print("installed %s" % dest)
    if cmd != "status" and shas:
        p = os.path.join(root, MANIFEST)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            json.dump({"plugin": v, "sha256": shas}, f, indent=2, sort_keys=True)
            f.write("\n")
    print("assets: " + ", ".join("%d %s" % (n, k) for k, n in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
