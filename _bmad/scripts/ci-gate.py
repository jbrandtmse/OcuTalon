# /// script
# requires-python = ">=3.10"
# dependencies = ["ruamel.yaml>=0.18,<0.20"]
# ///
"""The /epic-cycle CI gate: is every GitHub Actions workflow a push starts green on one commit?

Run it from the repository or a worktree of it, any directory. It reads the workflow files AT the commit, not the tree,
and asks GitHub about the repository `origin` names (or GH_REPO, [HOST/]OWNER/REPO):
  uv run --no-cache _bmad/scripts/ci-gate.py expected --branch <branch> [--sha <sha>]
  uv run --no-cache _bmad/scripts/ci-gate.py status --branch <branch> --sha <sha>
  uv run --no-cache _bmad/scripts/ci-gate.py selftest

expected  the workflows a push of <sha> (default HEAD) to <branch> starts, judged on the commit's own changes: one line
          per workflow, path TAB required|conditional|optional TAB name. `required`: its branch filter matches and any
          paths filter matches the changes. `conditional`: a paths filter they do not match (or that cannot be judged),
          so GitHub may skip it. `optional`: listed in _bmad/custom/ci-gate.yaml (below).
status    judges the push that carried <sha>, as GitHub does: the push's whole range decides a paths filter (GitHub's
          push activity names it), and a commit pushed beneath others is judged by that push's head. It lists every
          push run for the judged commit, takes each workflow's latest, and adds each required workflow with no run
          yet. A paths-filtered workflow this push did not start keeps its latest run on an earlier commit of the
          branch (`carried`: the code it watches has not changed since) - but for 300 s after the push, and whenever
          GitHub's decision cannot be known (more than 300 files, a force push), it is waited for instead. First line:
            result=<success|failure|cancelled|pending|untriggered|none|unavailable> sha=<asked> branch= runs=<id,...|none> missing=<path,...|none> via=<sha,...|none>
          `via=` names the other commits the verdict draws on: the push head that carried <sha>, and the commits
          carried runs belong to. Then one line per workflow:
          path TAB required|conditional|optional|carried|extra TAB run id|- TAB status TAB conclusion|- TAB url|- TAB head sha
          (`extra`: a workflow the files did not predict but GitHub ran; its result counts all the same).
Results and exit codes (act on the `result=` line; uv and Python have exit codes of their own):
  success 0      every run green (`skipped`, `neutral` count as green)
  failure 10     a run concluded failure, timed_out, startup_failure, action_required or stale; it outranks the rest
  cancelled 11   a run was cancelled (and none is red)
  pending 12     a run is queued or running, or a required workflow has no run yet
  none 13        no active workflow runs on a push to this branch at all
  unavailable 14 gh missing or unauthenticated, an API or network error, a CI-skip token in the commit message, a
                 broken _bmad/custom/ci-gate.yaml, or any other failure of this script
  untriggered 15 workflows exist, but none has a run on this push or a carried one (nothing they watch ever changed)
_bmad/custom/ci-gate.yaml (optional, project-owned): `optional: [.github/workflows/<file>, ...]` - workflows the gate
never waits for (a finished run of one still counts). CI_GATE_GH names a gh-compatible executable (default `gh`).
"""
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse

from ruamel.yaml import YAML
from ruamel.yaml.error import YAMLError

GH = os.environ.get("CI_GATE_GH", "gh")
GREEN = {"success", "skipped", "neutral"}
CANCELLED = {"cancelled"}
EXIT = {"success": 0, "failure": 10, "cancelled": 11, "pending": 12, "none": 13, "unavailable": 14, "untriggered": 15}
SKIP = re.compile(r"\[(skip ci|ci skip|no ci|skip actions|actions skip)\]|^skip-checks: ?true\s*$", re.I | re.M)
CONFIG = "_bmad/custom/ci-gate.yaml"
ZERO = "0" * 40
DIFF_LIMIT = 300  # GitHub judges a paths filter on at most 300 changed files; beyond that it may skip the workflow
WORKFLOW_FILE = re.compile(r"\.github/workflows/[^/]+\.ya?ml")
FRESH = 300  # seconds after a push in which GitHub may still start a workflow


class Unavailable(Exception):
    pass


def run(cmd):
    env = {**os.environ, "GH_PROMPT_DISABLED": "1", "GIT_TERMINAL_PROMPT": "0"}
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90, env=env)
    except FileNotFoundError:
        raise Unavailable(f"{cmd[0]} not found")
    except subprocess.TimeoutExpired:
        raise Unavailable(f"{' '.join(cmd[:3])}: no answer within 90 s")
    if p.returncode != 0:
        raise Unavailable(f"{' '.join(cmd[:3])}: {(p.stderr or p.stdout).strip()[:300]}")
    return p.stdout


def is_ancestor(a, b):
    """True, False, or None when git cannot tell (an object that is not here)."""
    try:
        rc = subprocess.run(["git", "merge-base", "--is-ancestor", a, b], capture_output=True, timeout=90).returncode
    except (OSError, subprocess.TimeoutExpired):
        return None
    return True if rc == 0 else False if rc == 1 else None


def load_yaml(text):
    return YAML(typ="base", pure=True).load(text)  # every scalar stays a string: branch 1.10 is "1.10", not 1.1


# ---- GitHub's filter patterns (branches, branches-ignore, paths, paths-ignore) -----------------------------
def pattern_re(pat):
    """`*` any run without `/`; `**` any run; `**/` zero or more directories; `?` / `+` zero-or-one / one-or-more of
    the preceding character; `[...]` a character class; `\\` escapes the next character. ValueError if invalid."""
    out, i = [], 0
    def quantifiable():
        return out and out[-1] not in ("?", "+") and not out[-1].endswith(("*", ")?"))
    while i < len(pat):
        c = pat[i]
        if c == "\\" and i + 1 < len(pat):
            out.append(re.escape(pat[i + 1])); i += 2
        elif pat.startswith("**/", i):
            out.append("(?:.*/)?"); i += 3
        elif pat.startswith("**", i):
            out.append(".*"); i += 2
        elif c == "*":
            out.append("[^/]*"); i += 1
        elif c in "?+" and quantifiable():
            out.append(c); i += 1
        elif c == "[" and pat.find("]", i + 1) > i + 1:
            j = pat.find("]", i + 1); out.append("[" + pat[i + 1:j].replace("\\", "\\\\") + "]"); i = j + 1
        else:
            out.append(re.escape(c)); i += 1
    try:
        return re.compile("".join(out) + r"\Z")
    except re.error as e:
        raise ValueError(f"invalid filter pattern {pat!r} ({e})")


def matches(name, patterns):
    """GitHub's order rule: a later `!pattern` excludes what earlier patterns matched; a later pattern re-includes."""
    hit = False
    for p in patterns:
        if p.startswith("!"):
            if pattern_re(p[1:]).match(name):
                hit = False
        elif pattern_re(p).match(name):
            hit = True
    return hit


# ---- which workflows a push starts ----------------------------------------------------------------------
def on_block(doc):
    if not isinstance(doc, dict):
        return None
    for key in ("on", True):  # a YAML 1.1 reader would turn the key `on` into True
        if key in doc:
            return doc[key]
    return None


def as_list(v):
    if v is None or v == "":
        return []
    return [str(x) for x in v] if isinstance(v, list) else [str(v)]


def push_trigger(doc, branch, files):
    """`required`, `conditional` or None (a push to `branch` never starts it). `files`: the push's changed paths, or
    None when they cannot be judged (a new branch, a root commit, more than 300 files). ValueError on a bad pattern."""
    on = on_block(doc)
    if isinstance(on, str):
        on = {on: None}
    elif isinstance(on, list):
        on = {str(e): None for e in on}
    if not isinstance(on, dict) or "push" not in on:
        return None
    cfg = on["push"]
    if not isinstance(cfg, dict):
        return "required"  # `push:` with no filter: every branch
    has_branches = "branches" in cfg or "branches-ignore" in cfg
    if ("tags" in cfg or "tags-ignore" in cfg) and not has_branches:
        return None  # tag pushes only
    if "branches" in cfg and not matches(branch, as_list(cfg["branches"])):
        return None
    if "branches-ignore" in cfg and matches(branch, as_list(cfg["branches-ignore"])):
        return None
    if "paths" in cfg or "paths-ignore" in cfg:
        if not files:
            return "conditional"
        if "paths" in cfg:
            hit = any(matches(f, as_list(cfg["paths"])) for f in files)
        else:
            hit = not all(matches(f, as_list(cfg["paths-ignore"])) for f in files)
        return "required" if hit else "conditional"
    return "required"


def diff_files(a, b):
    """Paths changed between two commits (plumbing: no diff.relative, no renames); None if not judgeable."""
    try:
        out = [f for f in run(["git", "diff-tree", "-r", "--name-only", "-z", "--no-renames", a, b]).split("\0") if f]
    except Unavailable:
        return None
    return out if len(out) <= DIFF_LIMIT else None


def commit_files(sha):
    parents = run(["git", "rev-list", "--parents", "-n", "1", sha]).split()[1:]
    return diff_files(parents[0], sha) if parents else None


def optional_paths():
    top = run(["git", "rev-parse", "--show-toplevel"]).strip()
    path = os.path.join(top, CONFIG)
    if not os.path.exists(path):
        return set()
    try:
        with open(path, encoding="utf-8") as f:
            doc = load_yaml(f.read())
    except (YAMLError, OSError, UnicodeDecodeError) as e:
        raise Unavailable(f"{CONFIG} is unreadable: {str(e).splitlines()[0] if str(e) else type(e).__name__}")
    items = doc.get("optional") if isinstance(doc, dict) else None
    good = set()
    for x in (items if isinstance(items, list) else [] if items in (None, "") else [items]):
        if isinstance(x, str) and WORKFLOW_FILE.fullmatch(x):
            good.add(x)
        else:
            print(f"WARNING: {CONFIG}: optional entry {x!r} is not a .github/workflows/<file>.yml path; ignored", file=sys.stderr)
    return good


def expected(branch, sha, optional, files):
    """[(path, kind, name)] for the workflow files at `sha` (top level of .github/workflows only, as GitHub reads)."""
    listing = run(["git", "ls-tree", "--full-tree", "-z", "--name-only", sha, "--", ".github/workflows/"])
    out = []
    for p in sorted(x for x in listing.split("\0") if WORKFLOW_FILE.fullmatch(x)):
        try:
            doc = load_yaml(run(["git", "show", f"{sha}:{p}"]))
            kind = push_trigger(doc, branch, files)
        except YAMLError:
            kind, doc = "required", {"name": "(unparsed: GitHub reports a broken workflow as a failed run)"}
        except ValueError as e:
            kind, doc = "required", {"name": f"({e}: GitHub reports the workflow as failed)"}
        if kind:
            name = doc.get("name") if isinstance(doc, dict) else None
            out.append((p, "optional" if p in optional else kind, str(name) if name else p))
    return out


# ---- the verdict ----------------------------------------------------------------------------------------
def latest_by_path(runs, sha):
    """{workflow path: its latest run on `sha`}."""
    latest = {}
    for r in runs:
        if r.get("headSha") != sha:
            continue
        cur = latest.get(r["path"])
        if cur is None or (r.get("createdAt") or "", r.get("databaseId") or 0) > (cur.get("createdAt") or "", cur.get("databaseId") or 0):
            latest[r["path"]] = r
    return latest


def verdict(exp, states, runs, sha):
    """exp: [(path, kind, name)]; states: {path: workflow state}; runs: [dict with "path"]. Returns (result, rows)."""
    kinds = {p: k for p, k, _ in exp}
    latest = latest_by_path(runs, sha)
    rows = [(p, kinds.get(p, "extra"), r) for p, r in latest.items()]
    rows += [(p, k, None) for p, k, _ in exp
             if p not in latest and k == "required" and states.get(p, "active") == "active"]
    return result_of(rows, exp, states), rows


def result_of(rows, exp, states):
    """The verdict over rows [(path, kind, run-or-None)]; a None run is a workflow GitHub has not started (yet)."""
    rows.sort(key=lambda row: row[0])
    done = [r for _, _, r in rows if r and r.get("status") == "completed"]
    if any((r.get("conclusion") or "") not in GREEN | CANCELLED for r in done):
        return "failure"
    if any(r.get("conclusion") in CANCELLED for r in done):
        return "cancelled"
    if any(r is None or (r.get("status") != "completed" and k != "optional") for _, k, r in rows):
        return "pending"
    if rows:
        return "success"
    live = [p for p, _, _ in exp if states.get(p, "active") == "active"]
    return "none" if not live else "untriggered"


# ---- the repository and its pushes ---------------------------------------------------------------------
def mask(url):
    return re.sub(r"//[^/@]+@", "//***@", url)


def ssh_hostname(alias):
    try:
        for line in run(["ssh", "-G", alias]).splitlines():  # resolves ~/.ssh/config aliases; never connects
            if line.startswith("hostname "):
                return line.split(None, 1)[1].strip().lower()
    except Unavailable:
        pass
    return alias


def parse_remote(url, resolve=None):
    m = re.match(r"^(?:([a-z][a-z0-9+.-]*)://)?(?:[^@/]+@)?([^/:]+)(?::\d+)?[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$", url.strip(), re.I)
    if not m:
        raise Unavailable(f"origin ({mask(url)}) is not a GitHub repository URL")
    scheme, host, owner, name = m.groups()
    host = host.lower()
    if (scheme or "ssh").lower() not in ("http", "https", "git") and resolve:
        host = resolve(host)
    if host == "ssh.github.com":  # GitHub's SSH-over-443 host; the API lives on github.com
        host = "github.com"
    return host, owner, name


def repo():
    """(host, owner, name) of GH_REPO, else of `origin` - never gh's own pick, which prefers a remote named upstream."""
    spec = os.environ.get("GH_REPO", "")
    if spec:
        parts = spec.strip("/").split("/")
        if len(parts) in (2, 3):
            return (parts[0].lower() if len(parts) == 3 else "github.com"), parts[-2], parts[-1]
        raise Unavailable(f"GH_REPO={spec} is not [HOST/]OWNER/REPO")
    return parse_remote(run(["git", "remote", "get-url", "origin"]), ssh_hostname)


class Ctx:
    def __init__(self, branch):
        self.branch = branch
        self.optional = optional_paths()
        self.host, self.owner, self.name = repo()
        self.paths, self.states = {}, {}
        for line in self.gh_api(f"repos/{self.owner}/{self.name}/actions/workflows", "--paginate",
                                "--jq", ".workflows[] | [.id, .path, .state] | @tsv").splitlines():
            f = line.split("\t")
            if len(f) >= 3 and f[0].isdigit():
                self.paths[int(f[0])] = f[1]; self.states[f[1]] = f[2]
        self._pushes = False

    def gh_api(self, endpoint, *args):
        return run([GH, "api", "--hostname", self.host, *args, endpoint])

    def pushes(self):
        """Every push to the branch, newest first ({before, after, type, ts}); None if GitHub's activity cannot be read.
        A branch's first push is GitHub's `branch_creation` (before = 000...0); `force_push` rows rewrite history."""
        if self._pushes is False:
            ref = urllib.parse.quote(f"refs/heads/{self.branch}", safe="")
            try:
                out = self.gh_api(f"repos/{self.owner}/{self.name}/activity?ref={ref}&per_page=100", "--paginate", "--jq",
                                  '.[] | select(.activity_type != "branch_deletion") | [.before, .after, .activity_type, .timestamp] | @tsv')
            except Unavailable:
                self._pushes = None
                return None
            self._pushes = []
            for line in out.splitlines():
                f = line.split("\t")
                if len(f) >= 4:
                    self._pushes.append({"before": f[0], "after": f[1], "type": f[2], "ts": epoch(f[3])})
        return self._pushes

    def push_of(self, sha):
        """(push, listed): the push that carried `sha` - the one whose head it is, or the one that carried it beneath its
        head - and whether GitHub's activity shows `sha` on the branch at all (False: not yet, so a push of it is still
        arriving; None: cannot tell - no activity, or older than the activity GitHub keeps)."""
        plist = self.pushes() or []
        for p in plist:
            if p["after"] == sha:
                return p, True
        seen = False
        for p in plist:  # newest first; stop as soon as the answer is known
            on_head = is_ancestor(sha, p["after"])
            if on_head is None:
                continue  # that head is not here (not fetched): look at an older push
            if not on_head:
                return None, (False if not seen else None)  # not under the newest head GitHub lists
            seen = True
            if p["before"] == ZERO:
                return p, True
            below = is_ancestor(sha, p["before"])
            if below is False:
                return p, True
            if below is None:
                return None, None  # a force push whose old head is gone: cannot tell
        return None, None

    def map_paths(self, runs):
        if not isinstance(runs, list) or not all(isinstance(r, dict) for r in runs):
            raise Unavailable("gh run list returned an unexpected shape")
        for r in runs:
            wid = r.get("workflowDatabaseId")
            if wid not in self.paths:  # a workflow the listing did not carry yet (just added); never guess its file
                try:
                    self.paths[wid] = json.loads(self.gh_api(f"repos/{self.owner}/{self.name}/actions/workflows/{wid}")).get("path")
                except ValueError:
                    raise Unavailable(f"workflow {wid}: unreadable answer")
            r["path"] = self.paths.get(wid) or f"workflow-id:{wid}"
        return runs

    def run_list(self, *args):
        try:
            return self.map_paths(json.loads(run([GH, "run", "list", "-R", f"{self.host}/{self.owner}/{self.name}",
                                                  "--branch", self.branch, "--event", "push", "-L", "200", *args, "--json",
                                                  "databaseId,workflowDatabaseId,workflowName,status,conclusion,headSha,createdAt,url"]) or "[]"))
        except ValueError:
            raise Unavailable("gh run list did not return JSON")

    def runs(self, sha):
        return self.run_list("--commit", sha)

    def carried(self, sha, wanted):
        """{path: (run, from-sha)} - for each wanted workflow, its latest run on the nearest earlier commit of the branch
        (first parents) that has one. The code a paths filter watches has not changed since that run."""
        if not wanted or not run(["git", "rev-list", "--parents", "-n", "1", sha]).split()[1:]:
            return {}
        by_sha = {}
        for r in self.run_list():
            by_sha.setdefault(r.get("headSha"), []).append(r)
        found = {}
        for c in run(["git", "rev-list", "--first-parent", "-n", "200", f"{sha}^"]).split():
            if c in by_sha:
                for path, r in latest_by_path(by_sha[c], c).items():
                    if path in wanted and path not in found:
                        found[path] = (r, c)
            if len(found) == len(wanted):
                break
        return found


def epoch(stamp):
    try:
        return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def judge(ctx, sha):
    """(result, rows, vias) for the push that carried `sha`. rows: [(path, kind, run-or-None)]; vias: other commits the
    verdict draws on - the push head that carried `sha`, and any earlier commit a carried run belongs to."""
    push, listed = ctx.push_of(sha)
    if push:
        judged, pushed_at = push["after"], push["ts"]
        exact = push["before"] != ZERO and push["type"] != "force_push"
        files = diff_files(push["before"], judged) if exact else None
    else:  # no push record (yet, or GitHub's activity is unreadable): the commit's own changes and its commit time
        judged, exact = sha, True
        files = commit_files(sha)
        pushed_at = time.time() if listed is False else float(run(["git", "log", "-1", "--format=%ct", sha]).strip() or 0)
    exp = expected(ctx.branch, judged, ctx.optional, files)
    result, rows = verdict(exp, ctx.states, ctx.runs(judged), judged)
    vias = [judged] if judged != sha else []
    started = {p for p, _, r in rows if r}
    waiting_on = [p for p, k, _ in exp if k == "conditional" and p not in started and ctx.states.get(p, "active") == "active"]
    if waiting_on:
        fresh = time.time() - pushed_at < FRESH                     # GitHub may still start them
        unknowable = (exact and files is None) or (push and push["type"] == "force_push")  # >300 files, rewritten history
        if fresh or unknowable:
            rows += [(p, "conditional", None) for p in waiting_on]
        else:  # GitHub did not start them: the code they watch is unchanged since their latest run on an earlier push
            for p, (r, c) in ctx.carried(judged, set(waiting_on)).items():
                rows.append((p, "carried", r))
                if c not in vias:
                    vias.append(c)
        result = result_of(rows, exp, ctx.states)
    if result == "pending" and not any(r for _, _, r in rows):
        messages = run(["git", "log", "--format=%B", f"{push['before']}..{judged}" if push and push["before"] != ZERO else "-1", judged])
        if SKIP.search(messages):
            raise Unavailable("a commit message in the push carries a CI-skip token: GitHub starts no push workflow for it; push a commit without one")
    return result, rows, vias


def report(result, rows, sha, branch, vias):
    ids = [str(r["databaseId"]) for _, _, r in rows if r]
    missing = [p for p, _, r in rows if r is None]
    print(f"result={result} sha={sha} branch={branch} runs={','.join(ids) or 'none'} missing={','.join(missing) or 'none'} via={','.join(vias) or 'none'}")
    for p, k, r in rows:
        if r is None:
            print(f"{p}\t{k}\t-\tnot-started\t-\t-")
        else:
            print(f"{p}\t{k}\t{r['databaseId']}\t{r.get('status')}\t{r.get('conclusion') or '-'}\t{r.get('url') or '-'}\t{r.get('headSha')}")


# ---- selftest -------------------------------------------------------------------------------------------
def selftest():
    bad, n = [], 0

    def check(label, got, want):
        nonlocal n
        n += 1
        if got != want:
            bad.append(f"{label}: got {got!r}, want {want!r}")

    for pats, name, want in [
        (["PROJ-epic*"], "PROJ-epic0", True), (["PROJ-epic*"], "PROJ-epic0/x", False), (["**"], "a/b", True),
        (["feature/**"], "feature/a/b", True), (["feature/*"], "feature/a/b", False), (["main"], "main2", False),
        (["v[12].*"], "v1.x", True), (["v[12].*"], "v3.x", False), (["ab?c"], "ac", True), (["ab+c"], "abbc", True),
        (["releases/**", "!releases/**-alpha"], "releases/1-alpha", False), (["releases/**", "!releases/**-alpha"], "releases/1", True),
        (["*", "!main", "main"], "main", True), (["a\\*b"], "a*b", True), (["a\\*b"], "axb", False),
        (["**/README.md"], "README.md", True), (["**/README.md"], "docs/x/README.md", True), (["**/*-post.md"], "my-post.md", True),
        (["**/PROJ-epic*"], "PROJ-epic1", True), (["a*+"], "a+", True), (["a*+"], "ab", False),
    ]:
        check(f"matches({pats}, {name})", matches(name, pats), want)
    try:
        pattern_re("[z-a]"); check("invalid pattern raises", "no error", "ValueError")
    except ValueError:
        check("invalid pattern raises", "ValueError", "ValueError")
    for text, branch, files, want in [
        ("on: push\n", "PROJ-epic0", None, "required"), ("on: [push, pull_request]\n", "x", None, "required"),
        ("on: pull_request\n", "x", None, None), ("on:\n  push:\n    branches: [main]\n", "PROJ-epic0", None, None),
        ("on:\n  push:\n    branches: [main]\n", "main", None, "required"),
        ("on:\n  push:\n    branches:\n      - main\n      - \"PROJ-epic*\"\n  pull_request:\n", "PROJ-epic3", None, "required"),
        ("on:\n  push:\n    branches: [main, 1.10, 010]\n", "1.10", None, "required"),
        ("on:\n  push:\n    branches: [main, 1.10, 010]\n", "010", None, "required"),
        ("%YAML 1.1\n---\non: push\n", "x", None, "required"),
        ("on:\n  push:\n    tags: ['v*']\n", "main", None, None), ("on:\n  push:\n    branches-ignore: ['PROJ-*']\n", "PROJ-epic1", None, None),
        ("on:\n  push:\n    branches-ignore: ['PROJ-*', '!PROJ-keep']\n", "PROJ-keep", None, "required"),
        ("on:\n  push:\n    branches: [main]\n    tags: ['v*']\n", "x", None, None),
        ("on:\n  push:\n    paths: ['src/**']\n", "x", None, "conditional"),
        ("on:\n  push:\n    paths: ['src/**']\n", "x", ["src/a.py", "README.md"], "required"),
        ("on:\n  push:\n    paths: ['src/**']\n", "x", ["README.md"], "conditional"),
        ("on:\n  push:\n    paths-ignore: ['**.md']\n", "x", ["docs/a.md", "README.md"], "conditional"),
        ("on:\n  push:\n    paths-ignore: ['**.md']\n", "x", ["README.md", "app.py"], "required"),
        ("on:\n  push:\n", "x", None, "required"), ("on:\n  workflow_dispatch:\n", "x", None, None), ("name: no trigger\n", "x", None, None),
    ]:
        check(f"push_trigger({text!r}, {branch}, {files})", push_trigger(load_yaml(text), branch, files), want)
    check("on_block(YAML 1.1 True key)", push_trigger({True: "push"}, "x", None), "required")

    alias = lambda h: "github.com" if h == "gh-work" else h
    for url, want in [
        ("https://github.com/acme/widget.git", ("github.com", "acme", "widget")),
        ("HTTPS://GitHub.com/acme/widget/", ("github.com", "acme", "widget")),
        ("https://user:tok@github.com/acme/widget", ("github.com", "acme", "widget")),
        ("git@github.com:acme/widget.git", ("github.com", "acme", "widget")),
        ("ssh://git@ghe.example.com:2222/org/repo.git", ("ghe.example.com", "org", "repo")),
        ("ssh://git@ssh.github.com:443/acme/widget.git", ("github.com", "acme", "widget")),
        ("git@gh-work:acme/widget.git", ("github.com", "acme", "widget")),
    ]:
        check(f"parse_remote({url})", parse_remote(url, alias), want)
    try:
        parse_remote("/srv/git/widget"); check("parse_remote(local path) raises", "no error", "Unavailable")
    except Unavailable:
        check("parse_remote(local path) raises", "Unavailable", "Unavailable")
    check("mask credentials", mask("https://user:tok@github.com/a/b"), "https://***@github.com/a/b")

    S = "a" * 40
    def r(i, path, st, concl, t="2026-01-01T00:00:00Z", sha=S):
        return {"databaseId": i, "path": path, "status": st, "conclusion": concl, "createdAt": t, "headSha": sha}
    req2 = [("w/ci.yml", "required", "ci"), ("w/lane.yml", "required", "lane")]
    for label, exp, states, runs, want in [
        ("both green", req2, {}, [r(1, "w/ci.yml", "completed", "success"), r(2, "w/lane.yml", "completed", "success")], "success"),
        ("one running", req2, {}, [r(1, "w/ci.yml", "completed", "success"), r(2, "w/lane.yml", "in_progress", "")], "pending"),
        ("red beats running", req2, {}, [r(1, "w/ci.yml", "completed", "failure"), r(2, "w/lane.yml", "queued", "")], "failure"),
        ("one not registered", req2, {}, [r(1, "w/ci.yml", "completed", "success")], "pending"),
        ("conditional absent", [("w/ci.yml", "required", "ci"), ("w/docs.yml", "conditional", "d")], {}, [r(1, "w/ci.yml", "completed", "success")], "success"),
        ("conditional only, no run", [("w/docs.yml", "conditional", "d")], {}, [], "untriggered"),
        ("conditional only, run registered", [("w/docs.yml", "conditional", "d")], {}, [r(5, "w/docs.yml", "queued", "")], "pending"),
        ("optional never waited for", [("w/ci.yml", "required", "ci"), ("w/slow.yml", "optional", "s")], {}, [r(1, "w/ci.yml", "completed", "success"), r(6, "w/slow.yml", "waiting", "")], "success"),
        ("optional red still counts", [("w/ci.yml", "required", "ci"), ("w/slow.yml", "optional", "s")], {}, [r(1, "w/ci.yml", "completed", "success"), r(6, "w/slow.yml", "completed", "failure")], "failure"),
        ("optional not started", [("w/slow.yml", "optional", "s")], {}, [], "untriggered"),
        ("extra run red", req2[:1], {}, [r(1, "w/ci.yml", "completed", "success"), r(3, "w/x.yml", "completed", "failure")], "failure"),
        ("disabled not required", req2, {"w/lane.yml": "disabled_manually"}, [r(1, "w/ci.yml", "completed", "success")], "success"),
        ("all disabled is none", req2, {"w/ci.yml": "disabled_manually", "w/lane.yml": "disabled_inactivity"}, [], "none"),
        ("latest run wins", req2[:1], {}, [r(1, "w/ci.yml", "completed", "failure", "2026-01-01T00:00:00Z"), r(4, "w/ci.yml", "completed", "success", "2026-01-01T01:00:00Z")], "success"),
        ("cancelled", req2, {}, [r(1, "w/ci.yml", "completed", "cancelled"), r(2, "w/lane.yml", "completed", "success")], "cancelled"),
        ("timed out is red", req2[:1], {}, [r(1, "w/ci.yml", "completed", "timed_out")], "failure"),
        ("stale is red", req2[:1], {}, [r(1, "w/ci.yml", "completed", "stale")], "failure"),
        ("skipped is green", req2[:1], {}, [r(1, "w/ci.yml", "completed", "skipped")], "success"),
        ("other sha ignored", req2[:1], {}, [r(1, "w/ci.yml", "completed", "success", sha="b" * 40)], "pending"),
        ("two ids never merged", [], {}, [r(7, "workflow-id:7", "completed", "failure"), r(8, "workflow-id:8", "completed", "success", "2026-01-02T00:00:00Z")], "failure"),
        ("nothing at all", [], {}, [], "none"),
    ]:
        check(f"verdict({label})", verdict(exp, states, runs, S)[0], want)
    docs = [("w/ci.yml", "conditional", "ci"), ("w/docs.yml", "conditional", "d")]
    for label, rows, want in [
        ("carried red beats a green on this push", [("w/docs.yml", "conditional", r(1, "w/docs.yml", "completed", "success")), ("w/ci.yml", "carried", r(2, "w/ci.yml", "completed", "failure", sha="c" * 40))], "failure"),
        ("carried green", [("w/ci.yml", "carried", r(2, "w/ci.yml", "completed", "success", sha="c" * 40))], "success"),
        ("held conditional waits", [("w/docs.yml", "conditional", r(1, "w/docs.yml", "completed", "success")), ("w/ci.yml", "conditional", None)], "pending"),
        ("nothing ran, nothing carried", [], "untriggered"),
    ]:
        check(f"result_of({label})", result_of(list(rows), docs, {}), want)
    for line in bad:
        print("FAIL " + line)
    print(f"selftest {'ok' if not bad else 'FAILED'}: {n - len(bad)}/{n} cases")
    return 0 if not bad else 1


USAGE = 64


def main(argv):
    if not argv or argv[0] not in ("expected", "status", "selftest") or (argv[0] == "selftest" and len(argv) > 1):
        print(__doc__, file=sys.stderr); return USAGE
    if argv[0] == "selftest":
        return selftest()
    opts, args = {}, argv[1:]
    if len(args) % 2:
        print(__doc__, file=sys.stderr); return USAGE
    for flag, value in zip(args[::2], args[1::2]):
        if flag not in ("--branch", "--sha") or flag in opts or not value or value.startswith("-"):
            print(__doc__, file=sys.stderr); return USAGE
        opts[flag] = value
    branch, sha = opts.get("--branch"), opts.get("--sha")
    if not branch or (argv[0] == "status" and not sha):
        print(__doc__, file=sys.stderr); return USAGE
    try:
        sha = run(["git", "rev-parse", "--verify", "--quiet", f"{sha or 'HEAD'}^{{commit}}"]).strip()
        if argv[0] == "expected":
            exp = expected(branch, sha, optional_paths(), commit_files(sha))
            for p, k, name in exp:
                print(f"{p}\t{k}\t{name}")
            return 0 if exp else EXIT["none"]
        result, rows, vias = judge(Ctx(branch), sha)
        report(result, rows, sha, branch, vias)
        return EXIT[result]
    except Unavailable as e:
        reason = " ".join(str(e).split())
        print(f"result=unavailable sha={sha or '-'} branch={branch} runs=none missing=none via=none reason={reason}")
        return EXIT["unavailable"]


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")  # Windows pipes default to a code page
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # never let a crash read as a CI verdict: uv and Python exit 1 or 2 on their own
        reason = " ".join(f"{type(e).__name__}: {e}".split())[:300]
        print(f"result=unavailable sha=- branch=- runs=none missing=none via=none reason=internal error: {reason}")
        sys.exit(EXIT["unavailable"])
