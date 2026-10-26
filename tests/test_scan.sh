SCAN="$PLUGIN/scripts/scan.py"
# _j <json> <python-expr over d> : prints the expression value
_j() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$2"; }

t_node_fixture() {
  local d o; d="$(mk_repo node-app)"; o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "'node' in d['stacks']")" True "stack node"
  assert_eq "$(_j "$o" "[c['source'] for c in d['commands'] if c['cmd']=='npm run lint']")" "['package.json:5']" "lint cmd"
  assert_eq "$(_j "$o" "[c['role'] for c in d['commands'] if c['cmd']=='npm test']")" "['test']" "test cmd"
  assert_eq "$(_j "$o" "[(v['version'],v['source']) for v in d['versions'] if v['tool']=='node']")" "[('20', '.nvmrc:1')]" "node version"
  assert_eq "$(_j "$o" "[(s['image'],s['source']) for s in d['services']]")" "[('postgres:16', 'docker-compose.yml:3')]" "service"
  assert_eq "$(_j "$o" "[(e['source'],e['resolved']) for e in d['env_vars'] if e['name']=='DB_HOST']")" "[('.env.example:1', True)]" "env"
  assert_eq "$(_j "$o" "d['migrations']")" "['db/migrations']" "migrations"
  assert_eq "$(_j "$o" "(d['version'],d['is_worktree'],len(d['head']))")" "(1, False, 40)" "meta"
  assert_eq "$(_j "$o" "d['harness_files']['CLAUDE.md']")" absent "claude absent"
}
t_spring_fixture() {
  local d o; d="$(mk_repo spring-app)"; o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "'java-gradle' in d['stacks']")" True "stack"
  assert_eq "$(_j "$o" "[e['source'] for e in d['env_vars'] if e['name']=='spring.datasource.url']")" "['src/main/resources/application.yml:3']" "env"
}
t_pack_residue() {
  local d o; d="$(mk_repo pack-residue)"; o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "d['harness_files']['CLAUDE.md']")" content "content"
  assert_eq "$(_j "$o" "d['pasted_guidance']")" "[{'file': 'CLAUDE.md', 'lines': [2, 20]}]" "pasted"
  assert_eq "$(_j "$o" "sorted(d['pack_folders'])")" "['.scratch', 'docs/acme-flow/plans']" "packs"
}
t_maven_and_ci() {
  local d o; d="$(mktemp -d)"; mkdir -p "$d/.mvn/wrapper" "$d/jenkins"
  printf '<project/>\n' > "$d/pom.xml"; : > "$d/mvnw"; : > "$d/Jenkinsfile"; : > "$d/jenkins/build.groovy"
  o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "'java-maven' in d['stacks']")" True "stack"
  assert_eq "$(_j "$o" "[(c['cmd'],c['source']) for c in d['commands'] if c['role']=='test']")" "[('./mvnw test', 'pom.xml:1')]" "mvnw"
  assert_eq "$(_j "$o" "sorted(d['ci'])")" "['Jenkinsfile', 'jenkins']" "ci"
  assert_eq "$(_j "$o" "d['head']")" "" "no git head empty"
}
t_cra_craco() {
  local d o; d="$(mktemp -d)"
  printf '{\n "scripts": {\n  "start": "craco start",\n  "test": "craco test",\n  "build": "craco build"\n }\n}\n' > "$d/package.json"
  o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "sorted((c['role'],c['cmd']) for c in d['commands'])")" "[('build', 'npm run build'), ('install', 'npm ci'), ('test', 'npm test')]" "roles"
}
t_worktree_is_repo() {
  local d w o; d="$(mk_repo node-app)"; w="$(mktemp -d)/with space"
  git -C "$d" worktree add -q "$w" -b wt
  o="$(python3 "$SCAN" "$w")"
  assert_eq "$(_j "$o" "d['is_worktree']")" True "worktree"
  assert_eq "$(_j "$o" "len(d['head'])")" 40 "head"
}
t_cache_by_head() {
  local d m1 m2; d="$(mk_repo node-app)"
  python3 "$SCAN" "$d" --write >/dev/null
  m1="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$d/.harness/scan.json")"
  sleep 1
  python3 "$SCAN" "$d" --write >/dev/null
  m2="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$d/.harness/scan.json")"
  assert_eq "$m2" "$m1" "mtime"
}
t_wrapper() {
  local d; d="$(mk_repo node-app)"
  assert_contains "$(bash "$PLUGIN/skills/harness-init/scripts/scan.sh" "$d")" '"stacks"' "wrapper"
}
t_deep_java_paths() {
  local d o; d="$(mktemp -d)"
  mkdir -p "$d/src/main/java/com/acme/app/security" "$d/src/main/resources/db/migration"
  : > "$d/src/main/java/com/acme/app/security/A.java"; : > "$d/src/main/resources/db/migration/V1__a.sql"
  printf 'spring:\n  datasource:\n    url: x\n' > "$d/src/main/resources/application.yml"
  o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "d['risk_paths']")" "['src/main/java/com/acme/app/security']" "risk"
  assert_eq "$(_j "$o" "d['migrations']")" "['src/main/resources/db/migration']" "migr"
  assert_eq "$(_j "$o" "[e['source'] for e in d['env_vars']]")" "['src/main/resources/application.yml:3']" "env"
}
t_cache_dirty_rescans() {
  local d; d="$(mk_repo node-app)"
  python3 "$SCAN" "$d" --write >/dev/null
  printf '{"scripts":{"lint":"x","build":"y"}}\n' > "$d/package.json"
  assert_contains "$(python3 "$SCAN" "$d" --write)" "npm run build" "rescanned"
  assert_contains "$(cat "$d/.harness/scan.json")" "npm run build" "rewritten"
}
t_engines_node() {
  local d o; d="$(mktemp -d)"; printf '{\n "engines": {\n  "node": ">=18"\n }\n}\n' > "$d/package.json"
  o="$(python3 "$SCAN" "$d")"
  assert_eq "$(_j "$o" "[(v['version'],v['source']) for v in d['versions']]")" "[('>=18', 'package.json:3')]" "engines"
}
t_lefthook_variants() {
  local d o v
  for v in lefthook.yaml .lefthook.yml; do
    d="$(mktemp -d)"; : > "$d/$v"; o="$(python3 "$SCAN" "$d")"
    assert_eq "$(_j "$o" "d['hook_manager']")" lefthook "$v"
  done
}
