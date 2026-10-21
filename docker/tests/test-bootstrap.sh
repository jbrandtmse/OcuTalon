#!/usr/bin/env bash
# Hermetic test of the worktree bootstrap in _bmad/custom/parallel.yaml (Story 0.7, matrix row 17; AC 6). It runs the file's own
# `bootstrap` and `bootstrap_check` commands, unchanged, in a linked worktree of a synthetic repository that has this repository's
# .gitignore, and starts nothing else: `npm` is a stub that makes the dependency folder the check looks for.
#   - a fresh worktree: bootstrap links irislib and irissys to the main checkout's folders, bootstrap_check exits 0 and
#     `git status --short` is empty, so the anchored .gitignore patterns keep the links out of git;
#   - controls: with a .gitignore that does not name the reference folders the links show as untracked and the check exits 1;
#     with a main checkout that has no reference folders no link is made and the check exits 1;
#   - a second run changes nothing, and a folder that is already there is not replaced by a link;
#   - the runtime lock throwaway-iris is listed with no stage, so that lib-live.sh alone claims it.
# Prints one PASS or FAIL line per check; exits 0 only when all pass. Needs git; takes about 2 s.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-bs.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

yaml=_bmad/custom/parallel.yaml
boot=$(sed -n "s/^bootstrap: '\\(.*\\)'\$/\\1/p" "$yaml")
check=$(sed -n "s/^bootstrap_check: '\\(.*\\)'\$/\\1/p" "$yaml")
if [ -z "$boot" ] || [ -z "$check" ]; then
  echo "FAIL $yaml: the bootstrap or bootstrap_check line is missing or is not a single-quoted one-line command"
  echo "test-bootstrap: 1 check(s) failed"
  exit 1
fi

# npm: `npm --prefix <dir> ci ...` makes <dir>/node_modules/@angular/core, as an install would.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/npm" <<'EOS'
#!/bin/sh
if [ "$1" = --prefix ] && [ "$3" = ci ]; then mkdir -p "$2/node_modules/@angular/core"; exit 0; fi
echo "npm stub: unexpected arguments: $*" >&2
exit 1
EOS
chmod +x "$tmp/bin/npm"

# mkmain <dir> <gitignore file> <with reference folders: yes|no>: a main checkout with one commit; the reference folders are ignored.
mkmain() {
  local d=$1
  git init -q "$d"
  cp "$2" "$d/.gitignore"
  mkdir -p "$d/web"
  echo '{}' > "$d/web/package.json"
  git -C "$d" add -A
  git -C "$d" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m first
  if [ "$3" = yes ]; then
    mkdir -p "$d/irislib/%Library" "$d/irissys/Security"
    echo x > "$d/irislib/%Library/DynamicObject.cls"
    echo x > "$d/irissys/Security/Users.cls"
  fi
}
# bootstrap_in <worktree>: runs the file's bootstrap, then its check; sets boot_rc, check_rc and status (git status --short).
bootstrap_in() {
  boot_rc=0
  check_rc=0
  (cd "$1" && PATH="$tmp/bin:$PATH" bash -c "$boot") > "$tmp/boot.out" 2>&1 || boot_rc=$?
  (cd "$1" && bash -c "$check") > "$tmp/check.out" 2>&1 || check_rc=$?
  status=$(git -C "$1" status --short)
}
worktree() { git -C "$1" worktree add -q --detach "$2"; }

printf 'node_modules/\n' > "$tmp/gitignore.none"

# --- a fresh worktree ---

mkmain "$tmp/main" .gitignore yes
worktree "$tmp/main" "$tmp/wt"
bootstrap_in "$tmp/wt"
want_lib=$(cd "$tmp/main/irislib" && pwd -P)
want_sys=$(cd "$tmp/main/irissys" && pwd -P)
if [ "$boot_rc" -eq 0 ] && [ -L "$tmp/wt/irislib" ] && [ -L "$tmp/wt/irissys" ] \
  && [ "$(cd "$tmp/wt/irislib" && pwd -P)" = "$want_lib" ] && [ "$(cd "$tmp/wt/irissys" && pwd -P)" = "$want_sys" ] \
  && [ -d "$tmp/wt/web/node_modules/@angular/core" ]; then
  pass "bootstrap: the dependencies are installed and irislib and irissys are links to the main checkout's folders"
else
  fail "bootstrap: it did not install the dependencies and link both reference folders to the main checkout (exit $boot_rc; $(cat "$tmp/boot.out" | head -n 3 | tr '\n' '|'))"
fi
if [ "$check_rc" -eq 0 ] && [ -z "$status" ]; then
  pass "bootstrap_check: it exits 0 on the bootstrapped worktree, and git status --short is empty"
else
  fail "bootstrap_check: exit $check_rc, and git status --short holds '$(printf '%s' "$status" | tr '\n' ' ')'"
fi

# --- a second run changes nothing ---

before=$(ls -l "$tmp/wt" | awk '{ print $9, $10, $11 }')
bootstrap_in "$tmp/wt"
after=$(ls -l "$tmp/wt" | awk '{ print $9, $10, $11 }')
if [ "$boot_rc" -eq 0 ] && [ "$check_rc" -eq 0 ] && [ "$before" = "$after" ] && [ -z "$status" ]; then
  pass "bootstrap: a second run changes nothing and the check still passes"
else
  fail "bootstrap: a second run failed or changed the worktree (exit $boot_rc, check $check_rc)"
fi

# --- a folder that is already there is kept ---

worktree "$tmp/main" "$tmp/wt-kept"
mkdir -p "$tmp/wt-kept/irislib"
bootstrap_in "$tmp/wt-kept"
if [ "$boot_rc" -eq 0 ] && [ ! -L "$tmp/wt-kept/irislib" ] && [ -d "$tmp/wt-kept/irislib" ] && [ -L "$tmp/wt-kept/irissys" ]; then
  pass "bootstrap: a name that is not free is left alone, and the other folder is still linked"
else
  fail "bootstrap: a folder that was already there was replaced, or the other link is missing"
fi

# --- controls: the check sees what is wrong ---

mkmain "$tmp/main-old" "$tmp/gitignore.none" yes
worktree "$tmp/main-old" "$tmp/wt-old"
bootstrap_in "$tmp/wt-old"
if [ "$check_rc" -ne 0 ] && printf '%s\n' "$status" | grep -q 'irislib'; then
  pass "control: with a .gitignore that does not name the reference folders the links show in git status, and bootstrap_check exits non-zero"
else
  fail "control: a .gitignore without the reference folders left the worktree clean, or the check passed (exit $check_rc; status '$(printf '%s' "$status" | tr '\n' ' ')')"
fi
mkmain "$tmp/main-none" .gitignore no
worktree "$tmp/main-none" "$tmp/wt-none"
bootstrap_in "$tmp/wt-none"
if [ ! -e "$tmp/wt-none/irislib" ] && [ ! -L "$tmp/wt-none/irislib" ] && [ "$check_rc" -ne 0 ]; then
  pass "control: with no reference folders in the main checkout nothing is linked, and bootstrap_check exits non-zero"
else
  fail "control: a main checkout without reference folders still gave a passing worktree (check exit $check_rc)"
fi

# --- the real .gitignore ignores both names, as a folder and as a link ---

rm -rf "$tmp/probe"
mkdir -p "$tmp/probe/target"
git init -q "$tmp/probe/repo"
cp .gitignore "$tmp/probe/repo/.gitignore"
ln -s "$tmp/probe/target" "$tmp/probe/repo/irislib"
ln -s "$tmp/probe/target" "$tmp/probe/repo/irissys"
mkdir -p "$tmp/probe/repo/web"
if [ -z "$(git -C "$tmp/probe/repo" status --short | grep -v '\.gitignore')" ]; then
  pass ".gitignore: a link named irislib and a link named irissys are ignored"
else
  fail ".gitignore: a link named irislib or irissys shows in git status --short"
fi

# --- the runtime locks ---

lock_block=$(awk '/^runtime_locks:/ { p = 1; next } p && /^[a-z_]+:/ { p = 0 } p' "$yaml")
if printf '%s\n' "$lock_block" | awk '/- name: throwaway-iris/ { f = 1; next } f && /- name:/ { f = 0 } f && /stages: \[\]/ { ok = 1 } END { exit !ok }'; then
  pass "runtime_locks: throwaway-iris is listed with no stage"
else
  fail "runtime_locks: throwaway-iris is missing from $yaml, or lists a stage"
fi

if [ "$fails" -ne 0 ]; then
  echo "test-bootstrap: $fails check(s) failed"
  exit 1
fi
echo "test-bootstrap: all checks passed"
