---
title: 'Story 11.4: The release gets draft notes and a checklist (the checklist half; the notes generator is the proposed Story 11.13)'
type: 'feature'
created: '2026-11-01'
status: 'done'
review_loop_iteration: 0
baseline_revision: 'fc28b0159723146d0c6c0834cab8764ce741bc8b'
baseline_commit: 'fc28b0159723146d0c6c0834cab8764ce741bc8b'
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: >-
      The draft notes are scanned for local paths and key-like text only; the inspiration's name outside the not-affiliated note is not
      checked in them.
    evidence: |-
      row_public_text (release/checklist.sh) runs local_path and key_like on the notes file, as the matrix row says. The notes live
      under release/records/, which is untracked while the notes are drafted, so name-only-in-note (which reads scan_files) never reads
      them. A draft that names the inspiration without the note would pass every row. Story 11.13 writes the notes and runs
      row_public_text on its draft, so its developer-section rule is the natural place to add the same name-outside-the-note filter.
    location: >-
      release/checklist.sh:row_public_text
    severity: low
---

<intent-contract>

## Intent

**Problem:** Release 1 has no release checklist. Nothing checks a candidate for the not-affiliated note, a product name with the inspiration's name in it, a lost licence notice, a public-text slip in the tree or in the draft notes, or a tracked file of the IRIS reference source. Nothing records the items that only the author can confirm, or states that posts and bonus claims are the author's. The release sequence (Story 11.5) needs that gate.

**Approach:** Add `release/checklist.sh`. It runs on the checkout of a candidate and checks every automated item, each with one `PASS` or `FAIL` line. It reads the author's confirmations from the candidate's record, where only the author writes them. It writes a `## Release checklist` section into `release/records/<version>/rc<n>.md` through Story 11.3's `record_write`. The notes generator goes to a proposed sibling, Story 11.13 (Design Notes, Proposed split).

## Boundaries & Constraints

**Always:**
- **No false all-clear.** The result is:
  - `fail` when any automated row fails;
  - otherwise `not confirmed` while any author row is not confirmed;
  - otherwise `pass`.
  - Exit codes: 0 only for `pass`; 1 for `fail` or `not confirmed`; 2 for a refusal (usage, version, rc, candidate, record), with nothing written.
- **The script never confirms anything for the author.** It only reads the author rows from the record's `## Author confirmations` section, and it never writes that section. A row that the record does not confirm reads `not confirmed`. The detail of a confirmed row repeats only what the record says.
- **No network, ever.** The checklist makes no network call, and runs no `curl`, `wget`, `gh`, `ssh`, `nc`, `git fetch`, `git pull`, `git push`, `git ls-remote` or `git clone`. Whatever needs the public page is an author row (DW-359).
- **Failure detail names the place, never the text.** A scan failure gives `file:line` only, as `lib-scan.sh`'s scanners do. Key-like text and local paths are never printed.
- **The script's own text keeps the rules it checks.** It never spells the inspiration's name outside a line that holds the note word for word. Its patterns are written so that they cannot match themselves, for example `[o]pen[c]law` and `gh[ ]release`. The self-test builds its samples by concatenation, as `test-boundaries.sh` does (`/Use[r]s`).
- **Portability.** Bash 3.2 and ASCII only (Rule 14). Mode 100755, `umask 077`, and main only when executed (`[ "${BASH_SOURCE[0]}" != "$0" ] && return 0`), so the self-test and Story 11.13 can source it.

**Never:**
- Publish, post, tag, push, open a pull request, claim a bonus, or change the repository's visibility or settings. Nothing in this story does any of these (REL-11).
- Build the notes generator. That is the proposed Story 11.13.
- Write into `release/records/` from a test or a verification run. Always pass `--record <tmp file>`.
- Edit `README.md` or `docker/tests/test-readme.sh` (Epic 10's; read and run only). Do not edit any open epic's file: `docker/tests/lib-live.sh`, `docker/tests/test-pinned-sources.sh`, `release/standalone-bridge.sh`, `release/ipm*`, `src/module.xml`, `.github/workflows/*`, `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls`. The one exception is the `CHECK_SCRIPTS` line of `ci/units.sh`, which is shared by region (the 11.1 lead ruling).
- Make the checklist itself a CI unit. Only its hermetic self-test joins `CHECK_SCRIPTS`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Options | `--version <x.y.z> --rc <n> [--candidate <ref>] [--record <file>] [--notes <file>]` | `--record` defaults to `record_path <v> <rc>`, and `--notes` to `notes_path <v> <rc>` (`release/records/<v>/rc<n>-notes.md`) | An unknown option, a missing `--version` or `--rc`, a version that is not `x.y.z`, an rc that is not a positive whole number, a version that differs from `src/module.xml`'s `<Version>`, an unknown `--candidate`, a `--candidate` whose commit is not `HEAD`, or not inside a git repository: exit 2, one line, nothing written |
| checkout | `git status --porcelain` outside `release/records/` | PASS when it is empty. The section's `Candidate:` line gives the full `HEAD` sha | Any other change, or any untracked file that is not ignored: FAIL, naming the count of paths |
| note-readme | `README.md` | PASS when one line equals the note exactly | FAIL `README.md: the note is missing or not word for word` |
| note-about | `web/src/app/about/about-dialog.ts`; the built page's `main-*.js` | PASS when a trimmed line of the source equals `<p>` + note + `</p>`, and one `main-*.js` of the bundle holds the note | FAIL naming which of the two lacks it. With no bundle, only the source is checked, and the detail says so |
| product-name | `README.md`'s first line; `src/module.xml` `<Name>`; `web/package.json` `"name"`; `web/src/index.html` `<title>`; `docker-compose.yml` `name:` | PASS when none of them holds the name, case-insensitive | FAIL `file:line` |
| name-only-in-note | Every file of `scan_files`, except under `_bmad-output/` and `_bmad/`, and except `docker/tests/test-readme.sh` | PASS when each line that holds the name, case-insensitive, still has no such text once the note is removed from it | FAIL `file:line` for each offending line |
| licences | `web/public/assets/licenses/*`; `docker/ipm/LICENSE`; the bundle's `3rdpartylicenses.txt` and `assets/licenses/` | PASS when every source licence file is non-empty, and `docker/ipm/LICENSE` holds the lines `MIT License` and `Copyright (c) 2019 InterSystems Developer Community`. With the bundle, `3rdpartylicenses.txt` must hold `Package: <name>` for each `dependencies` package of `web/package.json` that a non-spec `web/src/**/*.ts` file imports (`from '<name>'` or `'<name>/...'`), and `assets/licenses/` must hold the same non-empty files as the source folder | FAIL naming the missing or empty file or package |
| web-bundle | `src/ocutalon/csp/index.html` | PASS when it exists. Story 11.5 commits the bundle on the candidate | FAIL `the built web bundle is not in the checkout (Story 11.5 commits it on the candidate branch)` |
| readme | `bash docker/tests/test-readme.sh` | PASS on exit 0: the README's note, links, anchors and heading slugs are checked offline, from its own fixtures | FAIL with the script's FAIL lines indented, at most 10 |
| public-text | `bash docker/tests/test-boundaries.sh`, then `local_path` and `key_like` on the notes file | PASS when the script exits 0 and both scanners find nothing in the notes | FAIL with `file:line` only. A missing notes file fails: `no draft notes at <path>` |
| iris-source | `.gitignore`, `git ls-files` | PASS when `git check-ignore -q` ignores `irislib/x` and `irissys/x`, and no tracked path has an `irislib/` or `irissys/` component, or a component that starts with `%` | FAIL naming the rule and the count of paths |
| no-outward | Every `*.sh`, `*.mjs` and `*.js` file under `release/`, `ci/`, `eval/` and `docker/`, plus `install.sh` and `.github/workflows/*` | PASS when no line runs `gh release` (create, edit, upload or delete), `gh repo edit`, `--visibility`, `action-gh-release` or `create-release`, or names `community.intersystems.com` (not `pm.community...`), `openexchange.intersystems.com`, `twitter.com`, `x.com/`, `linkedin.com`, `youtube.com`, `medium.com`, `dev.to/` or `reddit.com` | FAIL `file:line` |
| Author rows | `## Author confirmations` in the record: lines `- <id>: confirmed <YYYY-MM-DD>[ <text>]` for `no-copied-code`, `no-artwork`, `no-ai-hub-copy`, `public-review` and `public-links` | A row is `confirmed` only with exactly that line form and a real calendar date. Its detail is `the record says the author confirmed this on <date>` | Missing, malformed, a date such as `2026-13-40`, or any other word: `not confirmed`. A `CONFIRM <id>` line prints the exact line to add and the record's path |
| Record | An existing record with other `## ` sections | Only `## Release checklist` is replaced, or appended when it is missing, through `record_write`. `RECORD <file>` and `RESULT <result>` are printed | A missing file is created with `# OcuTalon <v> rc<n>` (11.3's rule) |

</intent-contract>

## Code Map

**Story 11.3's interface (planned, built before this story; read its spec's Tasks and Design Notes):**
- `release/lib-release.sh`: `record_path <version> <rc>`, `record_write <file> <section> [<heading>]` (it replaces the matching `## ` section, or appends it; it creates the file and its folder; it writes through a temporary file and `mv`), and the main-guard and `umask 077` conventions.
- `release/rehearse.sh`: the shape this script follows (the header as the usage and the contract, `PASS|FAIL` lines, `RECORD`/`RESULT`, exit codes 0/1/2), and its record section `## Clean-machine rehearsal`.
- `docker/tests/test-rehearsal.sh`: the synthetic-git-repository pattern and the static rules (mode, ASCII, `umask`).
- If `release/lib-release.sh` is missing when this story is implemented, stop with a `## Clarification Needed`. Never create it here.

**Siblings to reuse or call:**
- `docker/tests/lib-scan.sh:11-20` `scan_files` (tracked or not ignored, never `.env`); `:22-40` `scan_rule`.
- `docker/tests/test-boundaries.sh:34-38` `local_path`. It moves into `lib-scan.sh` (Tasks). `:203` is its `scan_rule` call, and `:196` the bad-sample check, both unchanged. `:9-14` the CON-5 rules over every tracked file: this is "Epic 0's public-text check" (epics.md, Story 0.7's checks job: "a tracked file containing a local machine path or a key-like string (CON-5)").
- `docker/tests/lib-keys.sh:15-30` `KEY_LIKE_ERE` and `key_like`.
- `docker/tests/test-readme.sh` (Epic 10's, read and run only): `:33-40` the public-text, readme-links and product-links rules (DW-359's offline half); `:622-647` `public_text_scan`, whose line `l ~ /openclaw/ && $0 != note` is the README-only form of `name-only-in-note`. It is a top-level script and cannot be sourced.
- `docker/tests/test-web-build.sh:137-146` (the bundle's licence files) and `docker/tests/test-pinned-sources.sh:122-124` (the IPM licence lines): the facts `licences` checks again at release time. Both are top-level scripts, and `test-pinned-sources.sh` is Epic 15's.
- `release/demo-host-check.sh:46-47` -- the `PASS|FAIL|SKIP <id> <text>` line precedent.

**Facts (read at plan time):**
- The note, word for word: `README.md:243` and `web/src/app/about/about-dialog.ts:42` (`<p>...</p>`, trimmed). The built `src/ocutalon/csp/main-*.js` holds it once.
- Outside `_bmad-output/`, the name appears only in the note, in `_bmad/custom/unattended.yaml:11`, in two `_bmad/custom/skill-rules.md.bak-*` files, and in `docker/tests/test-readme.sh:33, 617, 631, 993`.
- The tagline is "An AI assistant for InterSystems IRIS." (`EXPERIENCE.md:142, 165`, amended 2026-10-29). UX-DR16 forbids the name in a tagline.
- Product names: `src/module.xml:5` `ocutalon`; `web/package.json:2` `ocutalon-web`; `web/src/index.html:5` `OcuTalon`; `docker-compose.yml:2` `ocutalon`; `README.md:1` `# OcuTalon`.
- Licences: `web/public/assets/licenses/` holds `inter-OFL.txt`, `jetbrains-mono-OFL.txt`, `lucide-LICENSE.txt` and `montserrat-OFL.txt`, and the bundle's `assets/licenses/` holds the same. The bundle's `3rdpartylicenses.txt` lists `Package: <name>` for every imported runtime dependency (measured: `@angular/cdk`, `common`, `core`, `platform-browser`, `router` and `rxjs`; `qrcode-generator` is not imported yet, and Story 12.3 imports it).
- `.gitignore:12-15` ignores `irislib/` and `irissys/`. No tracked path has a `%` component.
- `README_URL` (`web/src/app/links.ts:5`) is `https://github.com/jbrandtmse/OcuTalon#readme`. The repository has been public since 2026-10-31.
- `src/module.xml:6` holds `<Version>0.1.0</Version>` on this branch. Story 11.5 sets it at the cut.

**CI recipe:**
- `ci/units.sh:6` `CHECK_SCRIPTS`: add `release-checklist` at the end. `NOT_IRIS_INPUT_PATTERN` already declares `release/` and `docker/tests/test-*.sh` non-inputs, so no IRIS group runs on this story's files.
- `docker/tests/test-ci-config.sh:633-648`: every `docker/tests/test-*.sh` must sit in exactly one list. No pin names check scripts.

## Tasks & Acceptance

**Execution:**
- `docker/tests/lib-scan.sh` -- move `local_path` here from `test-boundaries.sh`, unchanged, with its comment, and update the header's list. This is the one definition (Rule 2: extend).
- `docker/tests/test-boundaries.sh` -- delete its `local_path` (it already sources `lib-scan.sh`). Nothing else changes, and it stays green.
- `release/lib-release.sh` -- add `notes_path <version> <rc>`, which prints `release/records/<v>/rc<n>-notes.md`. This is the notes file's one contract, which Story 11.13 writes.
- `release/checklist.sh` -- new. The header is the usage and Story 11.5's contract: options, rows, the author-confirmation line form, the section, the result rules and the exit codes. It sources `lib-release.sh`, `docker/tests/lib-scan.sh` and `docker/tests/lib-keys.sh` from its own root (`$(dirname "$0")/..`). It runs from the repository root.
  - One function per row: `row_checkout`, `row_note_readme`, `row_note_about`, `row_product_name`, `row_name_only_in_note`, `row_licences`, `row_web_bundle`, `row_readme`, `row_public_text`, `row_iris_source` and `row_no_outward` (the matrix), then `author_rows <record>`. Each prints one `PASS|FAIL|CONFIRM <id> <detail>` line and adds a `id|result|detail` line to the results.
  - `checklist_section <results> <options>` builds the section (Design Notes), and `checklist_result <results>` applies the result rules.
  - Main: parse and refuse (exit 2) before anything runs, run every row, write with `record_write`, print `RECORD <file>` and `RESULT <result>`, and exit.
- `docker/tests/test-release-checklist.sh` -- new, hermetic: no container and no network. It needs bash, git and awk.
  - **A synthetic git repository** in a temporary folder holds copies of `release/checklist.sh`, `release/lib-release.sh`, `docker/tests/lib-scan.sh` and `docker/tests/lib-keys.sh`, and fixture files: a README with the note, `about-dialog.ts`, `module.xml` (`1.0.0`), `package.json`, `index.html`, `docker-compose.yml`, the licence files, `docker/ipm/LICENSE`, a fixture bundle (`index.html`, a `main-x.js` with the note, `3rdpartylicenses.txt`, `assets/licenses/`), a `.gitignore`, and a stub `docker/tests/test-readme.sh` and `test-boundaries.sh`, each exiting 1 only when a marker file exists. Everything is committed on `release/1.0.0-rc1`.
  - **The base case:** a record with `## Clean-machine rehearsal` and all five confirmations gives `RESULT pass` and exit 0. Both other sections stay byte for byte, and the checklist section appears once.
  - **One case per automated row**, each mutated in a fresh copy and expected to FAIL, alone, with `file:line` and no planted text in the output:
    - the note altered in the README, in the About source, and in the bundle;
    - the name in `module.xml`'s `<Name>`;
    - a tagline-like line with the name in a fixture `web/src/x.ts`, while the same line under `_bmad-output/` passes;
    - an empty licence file, an import of a package that `3rdpartylicenses.txt` lacks, and a bundle without a licence file;
    - no bundle;
    - each stub's marker;
    - a local path, and then a key-like string, in the notes (both built by concatenation), and also no notes file;
    - a file under `irislib/` added with `git add -f`, and a `%Library/X.cls` path;
    - a `gh release create` line, a `--visibility` line and a social host, each in a fixture `release/x.sh`;
    - an uncommitted change outside `release/records/` (while a change inside it passes).
  - **Author rows:** with no confirmations section, `RESULT not confirmed`, exit 1, and five `CONFIRM` lines that name the line to add. A malformed line (`confirmed yesterday`), an impossible date, and `- public-review: done` are each `not confirmed`. Running the checklist never changes the confirmations section.
  - **Refusals (exit 2, the record unchanged):** each refusal of the Options row.
  - **No network:** stubs for `curl`, `wget`, `gh`, `ssh` and `nc` on `PATH` write a marker when called, and no case leaves one.
  - **Static rules on `checklist.sh`:** mode 100755, `umask 077`, ASCII, the main guard, no network command, and no line that holds the name without the note.
- `ci/units.sh` -- add `release-checklist` to the end of `CHECK_SCRIPTS`, and nothing else. Then run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml`.

**Acceptance Criteria:**
- **AC1 (the note and the name; CON-2, UX-DR16, UX-DR28).** Given a candidate checkout, when the checklist runs, then `note-readme`, `note-about`, `product-name` and `name-only-in-note` pass only if:
  - the README and the About text (source and built page) carry the note "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation." word for word;
  - no product name holds the inspiration's name;
  - outside the planning files, that name appears only in the note.
  - Each broken form fails its row with `file:line`.
- **AC2 (licence notices; CON-2).** Given the candidate, when the checklist runs, then `licences` and `web-bundle` pass only if every font and icon licence file, the IPM licence, and the bundle's `3rdpartylicenses.txt` (one entry for each imported runtime package) and licence folder are present and non-empty. A missing one fails and is named.
- **AC3 (public text and the reference source; CON-5).** Given the repository at the candidate, when the public-text rows run, then:
  - `public-text` passes only if Epic 0's public-text check (`test-boundaries.sh`) passes on the tree and its path and key scanners find nothing in the draft notes, and a missing notes file fails;
  - `iris-source` passes only if `irislib/` and `irissys/` are ignored and none of their files is tracked.
  - No failure prints the offending text.
- **AC4 (the author's items; CON-2, CON-5).** Given the record's `## Author confirmations`, when the checklist runs, then:
  - each of `no-copied-code`, `no-artwork`, `no-ai-hub-copy`, `public-review` and `public-links` is confirmed only by the author's own line, and is otherwise `not confirmed`, with the line to add printed;
  - the result is `not confirmed` and the exit is 1 until all five are confirmed;
  - the script never writes or changes that section;
  - `public-review`'s detail says only what the record says.
- **AC5 (README links on the public page; DW-359).** Given the candidate, when the checklist runs, then:
  - `readme` passes only if `docker/tests/test-readme.sh` passes (the links, anchors and slugs, checked offline from its own fixtures);
  - the recheck on the public page is the author row `public-links`;
  - no case of the self-test calls a network tool.
- **AC6 (the author's actions; REL-11).** Given any run, when the section is written, then it states that posts, articles, the video and bonus claims are the author's actions, and `no-outward` passes only if no script or workflow publishes a release, changes the repository's visibility or settings, or posts to a public site. A planted line fails it with `file:line`.
- **AC7 (the record and the result; integration: the checklist consumes Story 11.3's `record_write`).** Given a record that holds `## Clean-machine rehearsal` and `## Author confirmations`, when the checklist writes, then:
  - both stay byte for byte;
  - `## Release checklist` appears once (it is replaced on a second run);
  - the result and the exit follow the result rules;
  - `checkout` fails on an uncommitted change outside `release/records/`;
  - each refusal exits 2 and writes nothing.
- **AC8 (the moved scanner; integration: `test-boundaries.sh` consumes `lib-scan.sh`'s `local_path`).** Given `local_path` in `lib-scan.sh`, when `test-boundaries.sh` runs on the tree, then it passes, and its bad-sample check still flags each planted local path.

## Spec Change Log

## Review Triage Log

### 2026-11-01 -- Review pass
- verdicts: 50 findings -- high 0, medium 8, low 40, false 2, maybe-false 0
- findings:
  - Blind Hunter
    - `[medium]` `[patch]` an absolute notes or record path reached the committed record (the missing-notes detail, the Notes line) -- fixed: `ck_rel` writes a path inside the checkout relative to it; a test runs the default paths and asserts no local folder in the record or the output (same root cause as Edge 10 and Gap 14)
    - `[low]` `[patch]` row_public_text read undocumented globals -- fixed: it takes `[<notes file>]` and the header says to run it from the repository root; a sourced test calls it on a clean and on a bad draft
    - `[medium]` `[patch]` three of the five product-name sources were never planted in the test -- fixed: package.json, the page title and the compose name now have cases (same root cause as Gap 1); the other untested branches (the symlink fallback, a missing About source, `--rc 01`) are `[low]` and not worth a case
    - `[low]` `[reject]` the licence row recognises only `from '<dep>'` imports -- the matrix defines exactly that rule; a wider scan is a spec change
    - `[low]` `[reject]` no-outward covers few file kinds and patterns -- the file kinds and the patterns are the matrix's own; the claim that `gh  release` (two spaces) passes is wrong (the pattern is `gh[ ]+release`); test coverage is patched under Gap 2
    - `[false]` `[reject]` the note rows treat whitespace differently -- the matrix asks for an exact README line and a trimmed About line, and the code does both
    - `[low]` `[reject]` a record-write failure exits 1 and there is no trap -- exit 1 is never a pass, so Story 11.5 cannot be misled; a leftover temporary folder holds no secret
    - `[low]` `[reject]` a future date confirms a row -- the matrix asks for a real calendar date only; the line is the author's own
    - `[low]` `[reject]` a path with a colon, or a rename out of release/records/ -- rare; the porcelain case fails safe
  - Edge Case Hunter
    - `[low]` `[reject]` irislib/ ignored only by .git/info/exclude -- the matrix names `git check-ignore`; on the candidate checkout the committed `.gitignore` is what the repository ships, and the cost of a stricter check is a second source of truth
    - `[low]` `[reject]` the awk location parse drops a path with a colon -- no tracked path has one; same as Blind 9
    - `[low]` `[reject]` spelled variants of the name ("Open Claw") -- the matrix fixes the pattern
    - `[low]` `[reject]` grep errors in name-only-in-note are silent -- the files are the tracked ones of the checkout; no failing read was shown
    - `[low]` `[patch]` a failing mktemp left a row without a result line (a false all-clear) -- fixed: each of the three sites writes a FAIL (or CONFIRM) line instead
    - `[low]` `[reject]` an empty or binary draft passes public-text -- an empty draft holds nothing to leak; the matrix scans text
    - `[low]` `[defer]` the draft notes are not checked for the name outside the note -- the matrix scans the notes for paths and keys only; Story 11.13 owns the draft's rules (deferred, low)
    - `[false]` `[reject]` a `--candidate` that starts with a dash is read as a git option -- `rev-parse --verify` fails on it and the script refuses with exit 2, which is the wanted result
    - `[low]` `[reject]` a record folder that cannot be created exits 1 after the rows -- never a pass; same as Blind 7
    - `[medium]` `[patch]` the Notes line and the RECORD line could hold an absolute path -- fixed with Blind 1
    - `[low]` `[reject]` porcelain rename and quoted paths -- both fail safe
    - `[medium]` `[patch]` `note-about` passed "no built page" beside a present index.html -- fixed: the built page is there when its `index.html` or a `main-*.js` is; a test removes `main-x.js`
    - `[low]` `[reject]` a one-line "dependencies" or a non-`from` import -- the matrix's rule; package.json here is multi-line
    - `[low]` `[reject]` a whitespace-only licence file is non-empty -- the matrix says non-empty
    - `[low]` `[reject]` `gh api` and other routes to the settings -- not in the matrix's list
    - `[low]` `[reject]` publishing scripts in other file kinds or folders -- the matrix names the kinds and folders
    - `[low]` `[reject]` a confirmation line inside a fence or a comment counts -- the Planner writes the section; a template line there would be the author's own choice
    - `[low]` `[reject]` a pipe in a path splits the table row -- detail_clean removes pipes from details
    - `[low]` `[reject]` AC2 claim: a licence deleted from both folders -- the matrix compares the bundle with the source folder
    - `[low]` `[reject]` AC6 claim: other file kinds -- as Edge 16
    - `[low]` `[reject]` AC7 claim: exit codes of a write failure -- as Edge 9
    - `[low]` `[reject]` AC3 claim: sub-script FAIL lines are printed -- the matrix asks for the script's FAIL lines (readme) and the scanners print file:line only
  - Verification Gap Reviewer
    - `[medium]` `[patch]` product-name pinned for one of five sources -- fixed (Blind 3)
    - `[medium]` `[patch]` no-outward patterns and roots unpinned -- fixed: two groups of planted lines (ten patterns, four roots, `.mjs`, `.js`, `install.sh`) and a longer-host-name negative; a mutation on `gh repo edit` goes red
    - `[medium]` `[patch]` the test-readme.sh exception unpinned -- fixed: a case plants the name in the stub; removing the exclusion goes red
    - `[low]` `[patch]` the note-about no-bundle detail was asserted against the whole section -- fixed: the assertion is the table row
    - `[low]` `[patch]` the MIT line was unpinned -- fixed (copyright-only LICENSE case); the empty-licence-folder branch is `[low]` and not worth a case
    - `[low]` `[patch]` heading exactness claimed but not asserted -- fixed: look-alike headings case
    - `[low]` `[patch]` t_sourcing relied on the previous rule's copy -- fixed: it starts with newcase
    - `[low]` `[reject]` t_nonetwork is an aggregate and some runs have no stubs -- the rule runs last by construction and the static rule covers the remaining commands
    - `[low]` `[reject]` the git-mode break sample is untracked -- the working-tree mode check is the demonstrated one; the git-mode check is one line
    - `[low]` `[reject]` the network regex is exercised for four commands -- the regex is one alternation; each name is in the same group
    - `[low]` `[patch]` the byte-for-byte claim compared sections after command substitution -- fixed: the record's earlier bytes are compared with a prefix checksum after the first and the second run
    - `[low]` `[patch]` the change-inside-release/records/ case was untracked only -- fixed: the file is committed, then changed, and a new file is added
    - `[low]` `[patch]` the (once) timing was not recorded -- recorded in Verification
    - `[medium]` `[patch]` an absolute path in the Notes line -- fixed with Blind 1
    - `[low]` `[reject]` rename in row_checkout -- fails safe (as Blind 9)
    - `[low]` `[reject]` a CRLF record reads as not confirmed -- fails safe
  - Intent Alignment Auditor
    - `[low]` `[reject]` no committed test runs the real tree -- by design (the matrix says hermetic); the (once) real-tree run was done and recorded
    - `[low]` `[reject]` author rows print CONFIRM on stdout and "not confirmed" in the record -- the Tasks fix the line form (`PASS|FAIL|CONFIRM`)
    - `[low]` `[reject]` a record-write failure exits 1 -- as Blind 7

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-22 | the CI checks this story reuses (the CON-5 path and key scans of `test-boundaries.sh`; `lib-keys.sh` is the one key-like definition), and a hosted, hermetic self-test |
| AD-29 | `release/` is Lane A's; `ci/units.sh` is shared by region; the open epics' files stay untouched |
| AD-19 | no key or configuration value is printed or recorded (the scans name only `file:line`) |

No AC contradicts an AD.

**The record section** (indented two spaces here, so that no section scan reads it; in the record each line starts at column 1, and the order is fixed):
```
  ## Release checklist

  Result: not confirmed
  Candidate: 1.0.0 rc1 at <full sha>
  Notes: release/records/1.0.0/rc1-notes.md
  Run: <UTC time>
  Author's actions: Posts, articles, the video and bonus claims are the author's actions, done by hand. No script or workflow posts anything or claims a bonus.

  | Item | Result | Detail |
  | --- | --- | --- |
  | checkout | pass | the checkout is the candidate commit, with no uncommitted change outside release/records/ |
  | note-readme | pass | README.md holds the not-affiliated note word for word |
  | note-about | pass | the About dialog's source and the built page hold the note word for word |
  | product-name | pass | no product name holds the name from the note |
  | name-only-in-note | pass | outside the planning files, the name appears only in the note |
  | licences | pass | every font, icon and package licence notice is present |
  | web-bundle | pass | the built web bundle is in the checkout |
  | readme | pass | docker/tests/test-readme.sh passed: README links, anchors and headings checked offline |
  | public-text | pass | docker/tests/test-boundaries.sh passed, and the draft notes hold no local path or key-like text |
  | iris-source | pass | irislib/ and irissys/ are ignored, and none of their files is tracked |
  | no-outward | pass | no script or workflow publishes a release, changes the repository's settings or posts to a public site |
  | no-copied-code | not confirmed | No code, prompts or workflows are copied from the project named in the not-affiliated note, or from a project like it. |
  | no-artwork | not confirmed | None of that project's logo or artwork is used. |
  | no-ai-hub-copy | not confirmed | Nothing is copied from InterSystems' published AI Hub examples. |
  | public-review | not confirmed | Before the repository went public, the author reviewed every planning file under _bmad-output/ and the agent instructions (CLAUDE.md and the .claude/ and _bmad/ folders) for keys, local machine paths, private infrastructure details and names of other contest entrants. |
  | public-links | not confirmed | On the public repository page, every README link and section link opens, and the README's clone command works. |
```
- A confirmed author row reads `confirmed` with `the record says the author confirmed this on <date>`.
- The author's lines, which the author adds by hand:
  ```
  ## Author confirmations

  - no-copied-code: confirmed 2026-11-02
  ```

**New public-facing text (for the lead to rule; product default 3).** The checklist and its record are user-facing. Every sentence above is new: the `Author's actions:` line, each row's detail, and the five author-row texts. So are the `CONFIRM` hint (`CONFIRM <id>: add the line "- <id>: confirmed <YYYY-MM-DD>" under "## Author confirmations" in <record>`) and the FAIL details of the matrix. None names the inspiration except through the note, none names a rival entry or entrant, and none says "IRIS Couch".

**Interface (Rule 1/2).**

| Link | Who |
| --- | --- |
| Consumed-by | Story 11.5's checklist gate: `bash release/checklist.sh --version <v> --rc <n> --candidate release/<v>-rc<n>` on the candidate checkout. It reads `Result:`; only exit 0 with `Result: pass` passes, and the record names the failed rows |
| Consumed-by | The proposed Story 11.13: it writes the draft notes at `notes_path <v> <rc>`, and may source `checklist.sh` to run `row_public_text` on its draft |
| Consumes | Story 11.3's `lib-release.sh` (`record_path`, `record_write`); `lib-scan.sh` (`scan_files`, `local_path`); `lib-keys.sh` (`key_like`); `docker/tests/test-readme.sh` and `test-boundaries.sh`, both run as they are |

- **Integration ACs:** AC7 (the checklist consumes `record_write` against a record with other sections) and AC8 (`test-boundaries.sh` consumes the moved `local_path`). There are no other consumers in this story; the first outside consumer will be Story 11.5.

**Extend, don't copy (Rule 2).**
- **Epic 0's public-text check** is `test-boundaries.sh`'s CON-5 scans. The checklist runs it as it is. For the notes, which are not a tracked file in a test, it calls the same scanners (`local_path`, now in `lib-scan.sh`, and `key_like`). So nothing is written twice.
- **The README rules** (the note, the links, the slugs) are `test-readme.sh`'s. The checklist runs it rather than copying them.
- **`name-only-in-note`** is the all-files form of one line of `test-readme.sh`'s `public_text_scan`. It is written again here (about 5 awk lines), because that script runs at top level, cannot be sourced, and is Epic 10's read-only file. The copy can be unified only when Epic 10 next changes `test-readme.sh` and sources a shared scanner (not this story's file).
- **The licence facts** repeat `test-web-build.sh:137-146` and `test-pinned-sources.sh:122-124` at release time, on the candidate's committed bundle. Both are top-level scripts, and the second is Epic 15's. The font list is not copied: the bundle's folder is compared with `web/public/assets/licenses/`.
- **The existing not-affiliated tests** (`web/scripts/ux-strings.test.mjs:287`, `OcuTalon.Test.Web.Splash`, `web/e2e/frame/frame.spec.ts`) pin the note in the product on every push. This checklist reads the candidate's files once, at release time, and changes none of them.
- **The record writer and the line style** are Story 11.3's (`record_write`; `PASS|FAIL` lines; exit codes 0/1/2) and `demo-host-check.sh`'s.

**Decided in-stage.**
1. **Split.** The checklist stays in 11.4, and the notes generator goes to the proposed Story 11.13. The checklist depends on nothing new, owns DW-359, and gives 11.13 its notes path and its public-text scan, so the order follows the dependency.
2. **Where the author's confirmations live:** in the candidate's record, in a section that only the author writes. The record is the auditable home of the candidate's gates, and no script can then claim a confirmation. Each new candidate (rc) is confirmed again, because new commits can change the answer (about a minute of the author's time).
3. **"Planning files"** are `_bmad-output/` and `_bmad/`, the method's folders. `_bmad/custom/unattended.yaml:11` names the inspiration in a planning rule, and `_bmad/` is owner-only to edit. `docker/tests/test-readme.sh` is excepted by name, because it is the README's own test of the same rule.
4. **Name only in the note.** The AC allows the name "only in the tagline and that note". The tagline was changed on 2026-10-29 and no longer holds it, and UX-DR16 forbids the name in a tagline. So the check allows it only in the note. This is the stricter reading, and it fails nothing that UX-DR16 allows.
5. **DW-359** is split into an offline half and an author half. The offline half is the `readme` row: `test-readme.sh`'s fixture-driven link, anchor and slug rules, with no network. The author half is the `public-links` row (the public page and the clone command). The checklist never calls the network, so CI and the self-test never do.
6. **The bundle is required** (`web-bundle`), because the candidate commits it (Story 11.5). A dev checkout without one fails that row and does not hide it.
7. **`checkout` ignores `release/records/`**, where the sequence writes the record and the notes during a run.

**Lead update 2026-11-01 (the Contest Planner under the owner's delegation, via the orchestrator; U-200 kept).** The pre-public review happened before the repository went public: the Planner's audit of all 9 origin heads, 2026-10-30T22:45Z to 2026-10-31T00:10Z, whose log lives outside the repository as CON-5 requires. At each candidate the Planner supplies the five `- <id>: confirmed <date> <text>` lines under `## Author confirmations` under the standing delegation. The script still never writes that section, and stopping at `not confirmed` without those lines is correct. No checklist text, row detail, hint, comment or note may be worded as if the review were missing. The paragraph below is superseded on that point.

**For the lead: the "before the repository goes public" item.** The repository went public on 2026-10-31, before any candidate record existed, and nothing in the repository records the author's review of `_bmad-output/` and the agent instructions. The `public-review` row reads only the author's own line in the record, and it never says that the review happened, or that it happened before going public, unless that line says so. Whether a review recorded after the fact satisfies CON-5 for 1.0.0 is the owner's call (outward-facing; owner-only). The row blocks the result until the author confirms it.

**Proposed split (smaller is better; for the lead).**
- **Story 11.13, "The release gets draft notes",** planned next in this epic, before Story 11.5, takes these verbatim:
  - the first criterion's Given/When/Then and its And (the notes generator, the evaluation summary, the rehearsal timings, the upgrade result and any REL-5 override, and "the author edits and publishes it");
  - the story preamble's 1.0.0 sentence (the previous tag is none, so 1.0.0's notes cover every story merged for the release).
- It writes the draft at `notes_path <v> <rc>`. It runs `row_public_text` on the draft, plus a developer-section rule (no class names or error codes outside it, the README's `dev_names` form).
- It reads:
  - `eval/release-candidate.json` (`ocutalon.evalResult/1`: `summary.scores`, `summary.attentionCost` with `meanUSD` and `maxUSD`, `summary.size.largestTokens`, `override.reason`; `OcuTalon.Eval.Gate:22-31`);
  - the rehearsal's bound rows and `### Runs` table (Story 11.11);
  - the first start (Story 11.3);
  - the `## Upgrade harness` `Result:` and rows (Story 11.2).
- It must face these facts:
  - Which stories are "merged since the previous tag" is best read as the `done` keys of `sprint-status.yaml` at the candidate that are not `done` at the previous tag (none for 1.0.0).
  - Areas need a mapping from epics.
  - Some story titles name internal work, which belongs in the developer section.
- Story 11.5 then composes 11.4 and 11.13.

**Ledger (Rule 17).** DW-359 (routed to this story) is addressed by Decided 5: the `readme` row and the `public-links` author row. The repository being public (2026-10-31) is stated in the Code Map. This story is expected to close it as `resolved-by` at adjudication. No other entry is owned.

**Contended paths (U14).** Checked at plan time against the diffs of `origin/OCT-epic12`, `-13` and `-15`, and against `contended-epic-11.txt`:
- New files: `release/checklist.sh` and `docker/tests/test-release-checklist.sh`.
- Changed:
  - `release/lib-release.sh` (this epic's, from Story 11.3; one function appended);
  - `docker/tests/lib-scan.sh` and `docker/tests/test-boundaries.sh` (no open epic changes them; one function moved);
  - `ci/units.sh` (the `CHECK_SCRIPTS` line only, contended by Epics 12, 13, 15 and 29, and shared by region: a plain union).
- `README.md` and `docker/tests/test-readme.sh` are read and run only.

**CI budget (REL-4).** No IRIS group changes. The self-test runs in the hosted `checks` job, as Story 11.3's does, and adds a few seconds (inference: a synthetic repository and about 30 short runs).

**Continuity.** The previous `done` story, 11.1 (the REL-2 web demo path), shares no file with this story.

## Clarification Needed (non-blocking: the plan does not depend on the answers)

1. Accept the proposed split into Story 11.13 (decide; product default 6, as at 11.3). If it is rejected, re-plan 11.4 with the notes criterion. This spec stays valid as its first part.
2. Rule the new public-facing sentences listed in Design Notes (veto window 5).
3. The `public-review` item after the repository went public (Design Notes, For the lead; owner-only).

## Verification

**Commands:**
- `(loop)` `bash docker/tests/test-release-checklist.sh` -- expected: every PASS line, exit 0.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0, with the paths rule's bad sample still flagged.
- `(loop)` `bash docker/tests/test-rehearsal.sh` -- expected: exit 0. Story 11.3's self-test stays green with `notes_path` added.
- `(loop)` `bash docker/tests/test-ci-config.sh && bash docker/tests/test-ci-changes.sh && bash ci/changes.sh ci.yml` -- expected: exit 0, with `release-checklist` in exactly one list.
- `(once)` On the real tree, with a fixture draft (`mkdir -p "${TMPDIR:-/tmp}/e11s4-check" && printf '# OcuTalon draft\n\nA plain sentence.\n' > "${TMPDIR:-/tmp}/e11s4-check/notes.md"`), run `bash release/checklist.sh --version "$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/module.xml)" --rc 1 --record "${TMPDIR:-/tmp}/e11s4-check/rc1.md" --notes "${TMPDIR:-/tmp}/e11s4-check/notes.md"` (`timeout: 600000`). Expected:
  - every automated row passes except `checkout` while the story's changes are uncommitted;
  - the five author rows are `not confirmed`;
  - `RESULT fail` and exit 1;
  - no file under `release/records/` is created.
  - If `src/ocutalon/csp/index.html` is missing, first run `ci/iris.sh build` once, with lane A's variables (`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement' OCUTALON_RUN_TAG=e11s4b`), and then `ci/iris.sh teardown` with the same tag and variables.
  - Record the seconds the run took here. Measured 2026-11-01: 11.8 s (exit 1, `RESULT fail`; `checkout` failed on the 7 uncommitted paths, the other ten automated rows passed, five `CONFIRM` lines, no file under `release/records/`).
- `(once)` `bash ci/checks.sh` -- expected: every check script passes.

**Mutations to demonstrate (Rule 19; one per AC, recorded here as `mutation: <change> -> <test red>`):**
- AC1: compare the README's note case-insensitively, so the altered-note case fails.
  - mutation: AC1: `grep -Fxq` -> `grep -Fxiq` in `row_note_readme` -> `note-rows` red (the note-in-another-case case)
  - mutation: AC1: the `ck_name_in web/package.json` call removed from `row_product_name` -> `name-rows` red (the name-in-package.json case); the `docker/tests/test-readme.sh` exclusion removed from `row_name_only_in_note` -> `name-rows` red; the `index.html` test dropped from `row_note_about` -> `licence-rows` red (a built page with no `main-*.js`)
- AC2: skip the bundle's `3rdpartylicenses.txt` package check, so the missing-package case fails.
  - mutation: AC2: the `Package: <dep>` test in `row_licences` replaced by `true` -> `licence-rows` red (the imported-package-without-an-entry case); the `MIT License` line test replaced by `true` -> `licence-rows` red
- AC3: drop `key_like` from `row_public_text`, so the key-in-notes case fails.
  - mutation: AC3: `key_like` dropped from the notes scan of `row_public_text` -> `script-rows` red (the key-like-text-in-the-notes case); `ck_rel` made to return its argument -> `script-rows` red (the default-paths case: no local folder in the record)
- AC4: accept any line that starts with `- <id>: confirmed`, so the malformed-line case fails.
  - mutation: AC4: the heading test of `author_rows` made a prefix match -> `author` red (the look-alike-headings case)
  - mutation: AC4: `ck_confirmed_date` accepts any line that starts with `- <id>: confirmed` (no date check) -> `author` red (the malformed, impossible-date and bare-word cases)
- AC5: treat a non-zero exit of `test-readme.sh` as a pass, so the readme-marker case fails.
  - mutation: AC5: `row_readme` passes whatever `test-readme.sh` exits -> `script-rows` and `author` red (the readme-marker cases)
- AC6: remove `--visibility` from the no-outward patterns, so that case fails.
  - mutation: AC6: the `--visibility` pattern removed from `outward_hits` -> `outward-rows` red (the visibility-line case); the `gh repo edit` pattern removed -> `outward-rows` red (the first-group case)
- AC7: write the section by appending it to the record (`>>`) in place of `record_write`, so the second-run replace case fails.
  - mutation: AC7: the section appended with `>>` in place of `record_write` -> `base` red (the second-run replace case)
- AC8: remove `local_path` from `lib-scan.sh`, so `test-boundaries.sh` fails.
  - mutation: AC8: `local_path` renamed away in `lib-scan.sh` -> `test-boundaries.sh` red (its paths rule, samples 2 to 6)

**Shared surfaces:**
- `CHECK_SCRIPTS` in `ci/units.sh`, read by the units rule of `test-ci-config.sh`.
- `lib-scan.sh`'s function list (it gains `local_path`) and `test-boundaries.sh`'s scanners.
- `lib-release.sh`'s function list (it gains `notes_path`).
- Every test added or changed passes on a fresh environment, in either order. The self-test builds its own repository, stubs and records in a temporary folder, and removes them.

## Auto Run Result

Status: done
Blocking condition: none

Summary: `release/checklist.sh` is the release checklist. It checks eleven automated items on a candidate checkout (the note in the README, the About source and the built page; the product names; the name only inside the note; the licence notices; the built bundle; the README test; the public-text check and the draft notes; the IRIS reference source rule; no outward action), reads the five author confirmations from the record, and writes `## Release checklist` through `record_write` without touching the confirmations. The result is `fail`, `not confirmed` or `pass`, with exit 1, 1 and 0, and a refusal exits 2. `local_path` moved into `docker/tests/lib-scan.sh`, `notes_path` joined `release/lib-release.sh`, and the hermetic self-test `release-checklist` joined `CHECK_SCRIPTS`.

Files changed:
- `release/checklist.sh` (new): the checklist.
- `docker/tests/test-release-checklist.sh` (new): the hermetic self-test (a synthetic git repository, 13 rules, about 20 s).
- `docker/tests/lib-scan.sh`: gains `local_path`, moved unchanged from `test-boundaries.sh`.
- `docker/tests/test-boundaries.sh`: loses its copy of `local_path`.
- `release/lib-release.sh`: gains `notes_path`.
- `ci/units.sh`: `release-checklist` at the end of `CHECK_SCRIPTS`.

Review: 50 findings (medium 8, low 40, false 2). Patched: 5 entries (a local path in the record; product-name tests; no-outward tests; the test-readme.sh exception test; `note-about` with a page but no `main-*.js`), plus 10 low items (a missing temporary file, the sourced `row_public_text`, and eight test gaps). Deferred: 1 (the name outside the note in the draft notes, for Story 11.13). Rejected: the rest, each with its reason in the Review Triage Log.

Follow-up review recommended: true. Five medium entries were patched after the review layers ran (`ck_rel`, the `note-about` bundle test, the `row_public_text` parameter, and the new cases of the self-test), and no layer has read those edits.

Verification: `test-release-checklist.sh`, `test-boundaries.sh`, `test-rehearsal.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml` exit 0 after the last patch. The `(once)` real-tree run gave `RESULT fail`, exit 1, `checkout` failing on the uncommitted paths and the other ten rows passing, five `CONFIRM` lines, in 11.8 s, with no file under `release/records/`. Every script of `CHECK_SCRIPTS` was run one by one and passed (the longest: `eval-set`, 170 s). Eight mutations went red and were reverted, and six more for the patched cases.

Residual risks: the matrix defines the patterns of `no-outward`, the licence import form and the name spelling, so a script that publishes by another route (`gh api`, another file kind) would not be seen. `row_iris_source` asks `git check-ignore`, which also honours `.git/info/exclude`.
