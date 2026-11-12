---
title: 'Story 0.34: The install-path OAuth2 check skips the built web bundle, so a release candidate passes it'
type: 'bugfix'
created: '2026-11-12'
status: 'done'
baseline_revision: '916fcfbf056848b4d4f0d44d0b9d0ea1f372ac63'
baseline_commit: '916fcfbf056848b4d4f0d44d0b9d0ea1f372ac63'
review_loop_iteration: 0
followup_review_recommended: false
context: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** PR #12 (release/1.0.8-rc1, e7b1ccf4) fails its `checks` job (job 131432798383, log line 628) on test-compose-file's row "install: no Dockerfile, compose file, script, manifest, CPF merge or preload names /csp/sys/oauth2 or IRIS's OAuth2 objects", which is Story 21.3's U-320 check. `oauth_app_untouched_by_install_paths` (docker/tests/test-compose-file.sh:634-647) scans git-tracked files, and its list includes `src/ocutalon/csp/*`. That folder is untracked on the feature branch, but the release cut commits the built web bundle into it. The bundle's main-*.js holds the *displayed* redirect path "/csp/sys/oauth2/OAuth2.Response.cls" (web/src/app/settings/email-view.ts REDIRECT_PATH), which the admin copies into the provider's console. So every RC since 21.3 fails this row, and feature CI cannot see it.

**Approach (the Contest Planner's 1.0.8 hotfix ruling, ~20:00Z, owner's delegation; binding):** exclude the built bundle (`src/ocutalon/csp/`) from THAT scan only. A browser bundle cannot enable a server web application. Every other install path stays fully scanned, and the function keeps its other behaviour, including the `n` floor, so it holds on the feature branch and on an RC. Add fixture pins in the same file that run the scan on a throwaway git repository: (a) the string in `src/ocutalon/csp/x.js` passes; (b) the same string in a `Dockerfile`, or in `docker/merge.cpf`, still fails. Demonstrate the mutation: undo the exclusion and (a) goes red; revert and the tree is byte-identical.

## Boundaries & Constraints

**Always:** change only `docker/tests/test-compose-file.sh` (plus bookkeeping: epics.md Story 0.34, the tracker, this spec, the cycle log). Keep the scan's regex, its path list (minus the bundle), its `docker/tests/` exclusion, its hit message and its floor of 40 for the real repository. Fixtures live in a `mktemp -d` repository that is always removed, never in the real tree.

**Never:** no product change (no web, ObjectScript, Python, Dockerfile, compose, release-script or CI-workflow edit). Do not exclude any path other than `src/ocutalon/csp/`. Do not weaken the regex.

</intent-contract>

## I/O & Edge-Case Matrix

| Case | Input | Expected |
| --- | --- | --- |
| Feature branch | the real repository (58 files scanned before this story, 58 after: the bundle is untracked on feature) | the row passes; n >= 40 |
| Release candidate | the real repository with the built bundle committed under `src/ocutalon/csp/` | the row passes (the bundle is not scanned); n is unchanged by the bundle |
| Pin (a) | throwaway repo: clean `Dockerfile` + `src/ocutalon/csp/x.js` holding "/csp/sys/oauth2/OAuth2.Response.cls" | scan returns 0 |
| Pin (b1) | throwaway repo: `Dockerfile` holding the string | scan returns 1 and names `Dockerfile` |
| Pin (b2) | throwaway repo: clean `Dockerfile` + `docker/merge.cpf` holding the string | scan returns 1 and names `docker/merge.cpf` |
| Fixture setup error | `mktemp`, `git init` or `git add` fails | the pin fails (never a false pass) |

## Code Map

- `docker/tests/test-compose-file.sh` — `oauth_app_untouched_by_install_paths` (lines ~630-647) and its `check` row (~line 659). The `check <label> <command...>` helper (line 13) runs a command with output discarded.

## Tasks & Acceptance

- [x] Split the scan into `oauth_install_paths_clean <repo dir> <floor>`, which runs `git -C <repo dir> ls-files` over the same path list without `'src/ocutalon/csp/*'`, keeps the `docker/tests/` exclusion, the regex and the hit message; `oauth_app_untouched_by_install_paths` calls it with `.` and 40. Update the comment: the bundle is not scanned, and why.
- [x] Add a fixture helper that builds a throwaway git repository (`mktemp -d`, `git init -q`, a clean `Dockerfile`, the redirect path appended to the named file, `git add -A`), runs `oauth_install_paths_clean <repo> 1`, removes the repository and returns the scan's result (a setup failure returns non-zero distinct from a pass).
- [x] Add three `check` rows: (a) `src/ocutalon/csp/x.js` passes; (b1) `Dockerfile` fails with the hit message naming `Dockerfile`; (b2) `docker/merge.cpf` fails with the hit message naming `docker/merge.cpf`.
- [x] Demonstrate the mutations (Rule 19) and record them under `## Verification`.
- [x] Simulate the RC: run the patched test file on a scratch clone at e7b1ccf4 (the rc1 head, bundle committed); the row passes there.

## Design Notes

- Governing AD: **AD-19** (configuration and secrets have fixed homes; its Story 21.3 bullet: `/csp/sys/oauth2` is enabled only during an admin's register or sign-in action). This story narrows only the test's view to the paths that can install or start something; the AD's Rule is unchanged, and the class test `TestOnlyOneCallerOfTheClass` still pins who may enable the application.
- Rule 2 (extend, don't copy): the fixture pins reuse the real scan (`oauth_install_paths_clean`) rather than a copy of its loop; the mktemp-plus-cleanup pattern follows the file's existing `gate_rules` / constraints fixtures (`mktemp -d "${TMPDIR:-/tmp}/ocutalon-....XXXXXX"`).
- Integration AC: not service-introducing (test-only change). No consumers.
- Ledger inbox: (none) — `LEDGER slice 0-34-the-install-path-oauth2-check-skips-the-built-web-bundle-so` was empty at spec time.
- Plan spawn skipped: the ruling makes it optional and allows a lead-written spec, as Story 0.33 did.

## Spec Change Log

- 2026-11-12: written by the lead from the Contest Planner's 1.0.8 hotfix ruling.

## Verification

Shared surfaces: `test-compose-file.sh`'s check list (three rows added; the U-320 row's label is unchanged); `ci/checks.sh` runs it (the `checks` job). No other test asserts on this function.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands**, from the worktree root, one per call, with `timeout: 600000`. No IRIS runtime and no MCP target is needed.
- `bash docker/tests/test-compose-file.sh` (loop, about 5 s): `test-compose-file: all checks passed`, the U-320 row and the three new rows PASS.
- `bash ci/checks.sh` (once): every script passes.
- The RC simulation on a scratch clone at e7b1ccf4 (once): the U-320 row PASSes with the patched test file.

**Mutations (Rule 19; each applied to `docker/tests/test-compose-file.sh`, run, observed red, reverted; `cmp` against the saved copy byte-identical, `git diff --stat` unchanged):**
- mutation: re-add `'src/ocutalon/csp/*'` to the scan's pathspec (undo the exclusion) → pin (a) "the OAuth2 scan skips the built web bundle ... src/ocutalon/csp/x.js passes" FAIL.
- mutation: drop `'docker/*'` from the pathspec → pin (b2) "... docker/merge.cpf, and names it" FAIL.
- mutation: drop `Dockerfile` from the pathspec → pin (b1) "... in a Dockerfile, and names it" FAIL (and pin (a), whose floor of 1 the clean Dockerfile meets, FAIL).
- mutation: raise the real scan's floor from 40 to 100 → the U-320 row FAIL (the floor is live; 58 files are scanned on the feature branch).

### Implement-stage results (2026-11-12, lead handoff edit)

- `bash docker/tests/test-compose-file.sh`: `test-compose-file: all checks passed`, 132 PASS (129 before + 3 new); no `ocutalon-oauth-scan.*` directory left in `$TMPDIR`.
- `bash ci/checks.sh`: `checks: all scripts passed` (32 scripts, 22.7 min; compose-file 3 s).
- RC simulation: scratch clone (`git clone --shared`) checked out at e7b1ccf4 (19 tracked files under `src/ocutalon/csp/`, `main-P7PESGFU.js` holds the redirect path). The rc1 test file as shipped: `FAIL install: no Dockerfile ... OAuth2 objects`, `1 check(s) failed` (reproduces job 131432798383). With this story's test file: the row PASSes, the three pins PASS, `all checks passed`.

## Auto Run Result

Status: done
Blocking condition: none

Summary: `oauth_app_untouched_by_install_paths` now calls `oauth_install_paths_clean . 40`, which scans the same git-tracked install paths minus `src/ocutalon/csp/*` (the built bundle the release cut commits). Three fixture pins run the same scan on a throwaway repository: the redirect path in `src/ocutalon/csp/x.js` passes; in a `Dockerfile` or `docker/merge.cpf` it fails and is named. Files changed: `docker/tests/test-compose-file.sh` only (plus bookkeeping).
