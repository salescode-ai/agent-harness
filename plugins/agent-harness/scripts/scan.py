#!/usr/bin/env python3
"""Deterministic repo scan -> .harness/scan.json. Usage: scan.py [repo-dir] [--write]. Never runs project commands."""
import json, os, re, subprocess, sys
from pathlib import Path

SKIP = {"node_modules", ".git", "build", "dist", "target", ".venv", "vendor", ".harness"}
MAX_DEPTH, MAX_FILES, MAX_READ = 4, 20000, 1_000_000
MANIFESTS = {"package.json": "node", "pom.xml": "java-maven", "build.gradle": "java-gradle",
             "build.gradle.kts": "java-gradle", "pyproject.toml": "python", "go.mod": "go"}
RISK = {"auth", "security", "payment", "payments", "billing", "crypto"}


def read(p):
    try:
        with open(p, "rb") as f:
            return f.read(MAX_READ).decode("utf-8", "replace").splitlines()
    except OSError:
        return []


def find(lines, pat, start=0):
    """1-based line of the first regex match at/after start, else 1."""
    for i in range(start, len(lines)):
        if re.search(pat, lines[i]):
            return i + 1
    return 1


def walk(root):
    files, dirs = [], []
    for cur, ds, fs in os.walk(root):
        rel = os.path.relpath(cur, root)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        ds[:] = sorted(d for d in ds if d not in SKIP) if depth < MAX_DEPTH else []
        for d in ds:
            dirs.append(os.path.normpath(os.path.join(rel, d)))
        for f in sorted(fs):
            files.append(os.path.normpath(os.path.join(rel, f)))
        if len(files) > MAX_FILES:
            break
    return files, dirs


def node_cmds(root, mod, out):
    p = root / mod / "package.json"
    lines = read(p)
    try:
        scripts = json.loads("\n".join(lines)).get("scripts", {})
    except ValueError:
        return
    base = Path(mod) / "package.json"
    here = root / mod
    if (here / "pnpm-lock.yaml").exists(): run, inst = "pnpm run", "pnpm install"
    elif (here / "yarn.lock").exists(): run, inst = "yarn", "yarn install"
    elif (here / "bun.lockb").exists() and not (here / "package-lock.json").exists(): run, inst = "bun run", "bun install"
    else: run, inst = "npm run", "npm ci"
    roles = {"lint": "lint", "typecheck": "typecheck", "type-check": "typecheck", "tsc": "typecheck",
             "test": "test", "build": "build"}
    sec = find(lines, r'"scripts"')
    out.append({"module": mod, "role": "install", "cmd": inst, "source": f"{base}:1"})
    for name, role in roles.items():
        if name in scripts:
            cmd = run.replace(" run", "") + " test" if name == "test" and run == "npm run" else f"{run} {name}"
            out.append({"module": mod, "role": role, "cmd": cmd, "source": f"{base}:{find(lines, '\"' + re.escape(name) + '\"', sec)}"})


def module_cmds(root, mod, manifest, out):
    here, src = root / mod, str(Path(mod) / manifest)
    lines = read(root / src)
    def add(role, cmd, line=1): out.append({"module": mod, "role": role, "cmd": cmd, "source": f"{src}:{line}"})
    if manifest == "package.json":
        node_cmds(root, mod, out)
    elif manifest == "pom.xml":
        m = "./mvnw" if (here / "mvnw").exists() else "mvn"
        add("test", f"{m} test"); add("build", f"{m} package -DskipTests")
    elif manifest.startswith("build.gradle"):
        g = "./gradlew" if (here / "gradlew").exists() else "gradle"
        add("test", f"{g} test"); add("build", f"{g} build")
    elif manifest == "pyproject.toml":
        text = "\n".join(lines)
        if "pytest" in text: add("test", "pytest", find(lines, "pytest"))
        if "ruff" in text: add("lint", "ruff check .", find(lines, "ruff"))
        if "mypy" in text: add("typecheck", "mypy .", find(lines, "mypy"))
    elif manifest == "go.mod":
        add("test", "go test ./..."); add("build", "go build ./..."); add("lint", "go vet ./...")


def scan(root):
    root = Path(root).resolve()
    files, dirs = walk(root)
    fset = set(files)
    base = lambda f: os.path.basename(f)
    r = {"version": 1, "head": "", "is_worktree": (root / ".git").is_file()}
    try:
        r["head"] = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True,
                                   text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    stacks, modules, cmds, versions, services, env = [], [], [], [], [], []
    for f in files:
        if base(f) in MANIFESTS and f.count(os.sep) < MAX_DEPTH:
            mod = os.path.dirname(f) or "."
            modules.append({"path": mod, "manifest": f})
            if MANIFESTS[base(f)] not in stacks: stacks.append(MANIFESTS[base(f)])
            module_cmds(root, mod, base(f), cmds)
    for f in files:
        b, lines = base(f), None
        if b in (".nvmrc", ".node-version", ".python-version"):
            lines = read(root / f)
            if lines: versions.append({"tool": "python" if "python" in b else "node",
                                       "version": lines[0].strip().lstrip("v"), "source": f"{f}:1"})
        elif b == ".tool-versions":
            for i, l in enumerate(read(root / f)):
                p = l.split()
                if len(p) >= 2: versions.append({"tool": p[0], "version": p[1], "source": f"{f}:{i+1}"})
        elif b == "go.mod":
            for i, l in enumerate(read(root / f)):
                m = re.match(r"go\s+(\S+)", l)
                if m: versions.append({"tool": "go", "version": m.group(1), "source": f"{f}:{i+1}"}); break
        elif b == "pom.xml":
            for i, l in enumerate(read(root / f)):
                m = re.search(r"<(?:java\.version|maven\.compiler\.source)>([^<]+)<", l)
                if m: versions.append({"tool": "java", "version": m.group(1), "source": f"{f}:{i+1}"}); break
        elif re.match(r"(docker-)?compose.*\.ya?ml$", b):
            for i, l in enumerate(read(root / f)):
                m = re.match(r"\s*image:\s*['\"]?([^'\"\s]+)", l)
                if m: services.append({"name": re.split(r"[:@]", m.group(1).split("/")[-1])[0], "image": m.group(1), "source": f"{f}:{i+1}"})
        elif re.match(r"\.env\.(example|sample|template)$", b):
            for i, l in enumerate(read(root / f)):
                m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)", l)
                if m: env.append({"name": m.group(1), "source": f"{f}:{i+1}", "resolved": bool(m.group(2).strip())})
        elif re.match(r"application[\w-]*\.(ya?ml|properties)$", b):
            lines = read(root / f)
            if b.endswith(".properties"):
                n = find(lines, r"^\s*spring\.datasource\.url\s*[=:]")
                hit = n <= len(lines) and re.search(r"^\s*spring\.datasource\.url\s*[=:]", lines[n - 1])
            else:  # shortcut: only the nested spring/datasource/url form, flat dotted keys not handled
                d = find(lines, r"^\s*datasource:\s*$"); n = find(lines, r"^\s+url:", d)
                hit = d <= len(lines) and re.search(r"^\s*datasource:\s*$", lines[d - 1]) and re.search(r"^\s+url:", lines[n - 1])
            if hit: env.append({"name": "spring.datasource.url", "source": f"{f}:{n}", "resolved": True})
    r["stacks"], r["modules"], r["commands"], r["versions"], r["services"], r["env_vars"] = stacks, modules, cmds, versions, services, env
    r["migrations"] = [d for d in dirs if base(d) in ("migrations", "migration") and any(f.startswith(d + os.sep) for f in files)]
    r["seeds"] = sorted({os.path.dirname(f) or "." for f in files if re.match(r"seeds?[._-].*\.(sql|js|ts|py)$|seeds?\.(sql|js|ts|py)$", base(f))}
                        | {d for d in dirs if base(d) in ("seed", "seeds")})
    hm = "none"
    for d, name in ((".husky", "husky"), ("lefthook.yml", "lefthook"), (".pre-commit-config.yaml", "pre-commit")):
        if (root / d).exists(): hm = name; break
    r["hook_manager"] = hm
    ci = [f for f in files if re.match(r"\.github/workflows/[^/]+\.ya?ml$", f)]
    ci += [f for f in (".gitlab-ci.yml", "Jenkinsfile", ".circleci/config.yml", "azure-pipelines.yml", "bitbucket-pipelines.yml") if f in fset]
    ci += [d for d in dirs if base(d) == "jenkins" and d.count(os.sep) == 0]
    r["ci"] = sorted(ci)
    cl = "absent"
    pasted = []
    if "CLAUDE.md" in fset:
        idx = [i + 1 for i, l in enumerate(read(root / "CLAUDE.md"))
               if l.strip() and not re.match(r"\s*(#|<!--|@\S+\s*$)", l)]
        cl = "content" if idx else "shim"
        if idx: pasted.append({"file": "CLAUDE.md", "lines": [idx[0], idx[-1]]})
    r["harness_files"] = {"AGENTS.md": "AGENTS.md" in fset, "INVARIANTS.md": "INVARIANTS.md" in fset, "CLAUDE.md": cl}
    r["pasted_guidance"] = pasted
    r["pack_folders"] = sorted(d for d in dirs if d == ".scratch" or re.fullmatch(r"docs/[^/]+/(plans|specs)", d.replace(os.sep, "/")))
    r["risk_paths"] = sorted(d for d in dirs if base(d).lower() in RISK)[:20]
    return r


def main():
    args = [a for a in sys.argv[1:] if a != "--write"]
    root = args[0] if args else "."
    out = Path(root) / ".harness" / "scan.json"
    if "--write" in sys.argv and out.is_file():
        try:
            old = json.loads(out.read_text())
            head = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
            if head and old.get("head") == head:
                print(json.dumps(old, indent=2)); return
        except (ValueError, OSError):
            pass
    text = json.dumps(scan(root), indent=2)
    if "--write" in sys.argv:
        out.parent.mkdir(exist_ok=True)
        out.write_text(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
