#!/usr/bin/env bash
# Test of the web build from a fresh copy of the tree (Story 0.3): copies the files that git tracks or has not
# ignored into an empty directory, as a checkout holds them, stages them in a repository of that directory, and
# runs `npm --prefix web ci` and `npm --prefix web run build` there. Then it checks
#   - the copy's `git status --short`: nothing is modified and nothing is new, so the bundle, the brand copies and
#     node_modules are ignored and the generated tokens.css and SignInAssets.cls are current;
#   - the bundle: index.html with <base href="/ocutalon/"> and no inline script, main-*.js and styles-*.css,
#     3rdpartylicenses.txt, and the font and icon licence texts under assets/licenses/.
# It never touches the working tree it is run from, makes no commit, and removes its copy on every exit. It needs
# Node 24.15 or later with npm, and network access or a warm npm cache. Takes about 1 to 2 minutes.
# In place (Story 0.7): with OCUTALON_WEB_BUILD_IN_PLACE=1, and only when GITHUB_ACTIONS is true and `git status --short` of the
# checkout is empty, the hosted web job builds in the checkout itself, which is a fresh clone, and runs the same checks on it
# (npm's cache is the job's); in any other case it copies as above.
# Prints one PASS or FAIL line per check; exits 0 only when all pass.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1

fails=0
pass() { echo "PASS $1"; }
fail() {
  echo "FAIL $1"
  fails=$((fails + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-wb.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM HUP

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "FAIL node and npm are not installed (Node 24.15 or later is needed)"
  exit 1
fi

# --- the tree: a copy, or the checkout itself ---

in_place=0
if [ "${OCUTALON_WEB_BUILD_IN_PLACE:-0}" = 1 ] && [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "$(git status --short)" ]; then
  in_place=1
fi

# Every git command below names the tree; a command that ran in the working tree of a copy would be a defect of this script.
# Only the repository's own ignore rules count: the user's global excludes file is switched off.
copy_git() { git -c core.excludesFile=/dev/null -C "$tree" "$@"; }

if [ "$in_place" -eq 1 ]; then
  tree=$root
  where="the checkout"
  echo "INFO building in place: the checkout is clean"
else
  where="the copy"
  tree="$tmp/tree"
  mkdir -p "$tree"
  tree=$(cd "$tree" && pwd -P)
  copied=0
  while IFS= read -r -d '' f; do
    if [ -f "$f" ]; then
      mkdir -p "$tree/$(dirname "$f")"
      cp "$f" "$tree/$f"
      copied=$((copied + 1))
    fi
  done < <(git ls-files -co --exclude-standard -z)
  if [ "$copied" -lt 50 ] || [ ! -f "$tree/web/package-lock.json" ] || [ -e "$tree/.env" ] || [ -e "$tree/web/node_modules" ]; then
    echo "FAIL the copy is not a fresh checkout ($copied files)"
    exit 1
  fi

  copy_git init -q >/dev/null 2>&1
  if [ "$(copy_git rev-parse --show-toplevel 2>/dev/null)" != "$tree" ]; then
    echo "FAIL the copy is not a repository of its own"
    exit 1
  fi
  copy_git add -A >/dev/null 2>&1
  staged=$(copy_git status --short | grep -vc '^A  ')
  if [ "$staged" -ne 0 ]; then
    echo "FAIL the copy is not staged cleanly before the build"
    copy_git status --short | grep -v '^A  ' | head -n 5
    exit 1
  fi
fi

# --- npm ci and the build ---

if npm --prefix "$tree/web" ci --no-audit --no-fund > "$tmp/ci.log" 2>&1; then
  pass "npm --prefix web ci succeeds on $where"
else
  tail -n 15 "$tmp/ci.log"
  fail "npm --prefix web ci failed"
  exit 1
fi
if npm --prefix "$tree/web" run build > "$tmp/build.log" 2>&1; then
  pass "npm --prefix web run build succeeds on $where"
else
  tail -n 15 "$tmp/build.log"
  fail "npm --prefix web run build failed"
  exit 1
fi

# --- AC6: the tree is clean ---

dirty=$(copy_git status --short | grep -v '^A  ')
if [ -z "$dirty" ]; then
  pass "git status --short after ci and build: nothing is modified and nothing is new"
else
  echo "$dirty" | head -n 10
  fail "git status --short after ci and build is not clean"
fi

# --- the bundle ---

bundle="$tree/src/ocutalon/csp"
index="$bundle/index.html"
if [ -f "$index" ]; then
  if grep -q '<base href="/ocutalon/">' "$index"; then
    pass "index.html has <base href=\"/ocutalon/\">"
  else
    fail "index.html has no <base href=\"/ocutalon/\">"
  fi
  scripts=$(grep -o '<script[^>]*>' "$index")
  inline=$(printf '%s\n' "$scripts" | grep -vc 'src=')
  if [ -n "$scripts" ] && [ "$inline" -eq 0 ]; then
    pass "index.html loads its scripts by src and has no inline script"
  else
    fail "index.html has an inline script, or no script"
  fi
else
  fail "the build wrote no src/ocutalon/csp/index.html"
fi
for pattern in 'main-*.js' 'styles-*.css'; do
  if ls "$bundle"/$pattern >/dev/null 2>&1; then
    pass "the bundle holds $pattern"
  else
    fail "the bundle holds no $pattern"
  fi
done
if [ -s "$bundle/3rdpartylicenses.txt" ]; then
  pass "the bundle holds 3rdpartylicenses.txt"
else
  fail "the bundle holds no 3rdpartylicenses.txt"
fi
for licence in inter-OFL.txt jetbrains-mono-OFL.txt montserrat-OFL.txt lucide-LICENSE.txt; do
  if [ -s "$bundle/assets/licenses/$licence" ]; then
    pass "the bundle holds assets/licenses/$licence"
  else
    fail "the bundle holds no assets/licenses/$licence"
  fi
done

if [ "$fails" -ne 0 ]; then
  echo "test-web-build: $fails check(s) failed"
  exit 1
fi
echo "test-web-build: all checks passed"
