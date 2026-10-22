#!/usr/bin/env bash
# Integration test for script/worktree's branch resolution.
#
# Builds a real bare origin plus a clone under mktemp -d and runs the real script
# from the clone. The fixture has no Gemfile, .nvmrc, package.json or .githooks, so
# every dependency-setup step is a no-op. Pins git config/locale for hermeticity.
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export LC_ALL=C
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

pass=0
fail=0
note() { printf '%s\n' "$*" >&2; }
ok()   { pass=$((pass + 1)); note "ok - $*"; }
bad()  { fail=$((fail + 1)); note "FAIL - $*"; }

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# fixture NAME -- origin.git with main (carrying the scripts) and remote-only
# branch feat/remote on an unrelated commit; clone at $root/NAME/repo on main.
fixture() {
  local d="$root/$1"
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$d/seed"
  mkdir "$d/seed/script"
  cp "$repo_root/script/worktree" "$repo_root/script/set_worktree_identity" "$d/seed/script/"
  git -C "$d/seed" add -A
  git -C "$d/seed" commit -q -m base
  git -C "$d/seed" remote add origin "$d/origin.git"
  git -C "$d/seed" push -q origin main
  git -C "$d/seed" checkout -q -b feat/remote
  echo remote >"$d/seed/remote.txt"
  git -C "$d/seed" add remote.txt
  git -C "$d/seed" commit -q -m remote-work
  git -C "$d/seed" push -q origin feat/remote
  git clone -q "$d/origin.git" "$d/repo"
  # Move the clone's HEAD off main so "branch off HEAD" is distinguishable.
  echo local >"$d/repo/local.txt"
  git -C "$d/repo" add local.txt
  git -C "$d/repo" commit -q -m local-only
  echo "$d"
}

run_wt() { # dir branch [args...]
  local d="$1"; shift
  (cd "$d/repo" && bash script/worktree "$@" 2>&1)
}

# 1. remote-only branch -> worktree at origin tip, tracking it
d="$(fixture remote_only)"
want="$(git -C "$d/origin.git" rev-parse feat/remote)"
out="$(run_wt "$d" feat/remote "$d/wt")"; rc=$?
got="$(git -C "$d/wt" rev-parse HEAD 2>/dev/null)"
up="$(git -C "$d/wt" rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
if [ $rc -eq 0 ] && [ "$got" = "$want" ] && [ "$up" = "origin/feat/remote" ]; then
  ok "remote-only branch checks out origin tip and tracks it"
else
  bad "remote-only branch: rc=$rc head=$got want=$want upstream=$up"; note "$out"
fi

# 2. branch nowhere -> new branch off invoking HEAD
d="$(fixture nowhere)"
want="$(git -C "$d/repo" rev-parse HEAD)"
out="$(run_wt "$d" feat/new "$d/wt")"; rc=$?
got="$(git -C "$d/wt" rev-parse HEAD 2>/dev/null)"
if [ $rc -eq 0 ] && [ "$got" = "$want" ]; then
  ok "branch absent everywhere branches off HEAD"
else
  bad "nowhere: rc=$rc head=$got want=$want"; note "$out"
fi

# 3. origin unreachable -> refuse (the lookup error, not some other failure), nothing created
d="$(fixture unreachable)"
git -C "$d/repo" remote set-url origin "$d/does-not-exist.git"
out="$(run_wt "$d" feat/remote "$d/wt")"; rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "could not check origin" \
   && [ ! -e "$d/wt" ] && ! git -C "$d/repo" show-ref --verify --quiet refs/heads/feat/remote; then
  ok "unreachable origin refuses without creating a branch"
else
  bad "unreachable: rc=$rc"; note "$out"
fi

# 4. local branch exists -> used as-is, even if origin has a different tip
d="$(fixture local_exists)"
git -C "$d/repo" branch feat/remote HEAD
want="$(git -C "$d/repo" rev-parse feat/remote)"
out="$(run_wt "$d" feat/remote "$d/wt")"; rc=$?
got="$(git -C "$d/wt" rev-parse HEAD 2>/dev/null)"
if [ $rc -eq 0 ] && [ "$got" = "$want" ]; then
  ok "existing local branch wins over origin"
else
  bad "local exists: rc=$rc head=$got want=$want"; note "$out"
fi

# 5. --from wins over a same-named remote branch
d="$(fixture from)"
want="$(git -C "$d/origin.git" rev-parse main)"
out="$(run_wt "$d" feat/remote --from main "$d/wt")"; rc=$?
got="$(git -C "$d/wt" rev-parse HEAD 2>/dev/null)"
if [ $rc -eq 0 ] && [ "$got" = "$want" ]; then
  ok "--from takes precedence over origin/<branch>"
else
  bad "--from: rc=$rc head=$got want=$want"; note "$out"
fi

note "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
