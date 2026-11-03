---
title: 'The README shows the product and says how you talk to it'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-10-context.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A judge reading the README sees no picture of OcuTalon before installing it, and nothing says how you talk to it on your own install compared with the online demo. The feature branch's README is what GitHub visitors see, and the Clarity of Instructions and Developer Experience criteria are judged largely on it.

**Approach:** Copy the five vetted screenshots byte for byte into `docs/images/`, put the hero under the opening paragraph and the teaser line and the other four where the text describes them, and add a "How you talk to it" section right after "What you can use it for". In `docker/tests/test-readme.sh`, rework `top` and `teaser` to allow the images and keep every other pin. Add an `images` rule that checks every image link (general, naming no file) and a `how-you-talk` rule that checks the new section.

## Boundaries & Constraints

**Always:**
- Write the README text and alt texts exactly as Design Note 1 gives them. Every claim in them is checked in Design Note 3. If the implement stage finds the build or an image contradicting one, it tightens the wording to what is true and records the change. It never widens a claim.
- The images are the five files the lead delivers. Each one is copied with `cp` and is never re-shot, re-encoded, resized, cropped or edited. Its byte size and sha256 prefix must match the table in Design Note 1. Before it is staged, each image is looked at: an IP address, a credential, a token, a session id, a cookie, a gate user name, a personal or account detail, or any host name other than `demo.ocutalon.com` stops the story with a clarification, and that image is never staged.
- `.gitignore`'s `images/` line ignores `docs/images/`. So the implement stage stages the five files once with `git add -f -- docs/images/<name>` (Design Note 4). After that, nothing ever runs `git add` on them again.
- Story 10.4's owner text stays byte for byte: the opening paragraph, the teaser line (still two lines below the opening), the two use-case items and the model paragraph and table. No existing README line is reworded, moved or deleted. The story only adds lines: the hero block, three indented image paragraphs, and the new section.
- In `test-readme.sh`, every rule other than `top` and `teaser` keeps all its checks, above all `no-telegram` (AD-29: never edited or weakened), `public-text`, `dev-only`, `interesting`, `use-cases`, `key-account`, `readme-links` and `product-links`.
- The script stays hermetic, bash 3.2, BSD or GNU tools. Each new or changed check first proves on broken copies that it can still flag, in the file's own `st` / `st_append` / `st_facts` / `rule_begin` / `finish` style. Each new rule fails closed with no README and is listed in `RULES`.
- Footprint: `README.md`, `docs/images/` (the five PNG files), `docker/tests/test-readme.sh` and this spec.

**Never:**
- The word Telegram anywhere in README.md (alt text included). No Slack, no "from your phone", no "per step", no dotted class name outside "For admins and developers", no OpenClaw outside the note, and no other model provider.
- No README text about the online demo claims Telegram, pairing or phone approvals (U-228 condition (2)). The Simulated phone is described as showing requests, not as a way to approve on a phone.
- Nothing added under "What's interesting". It keeps its 120-word cap, and Story 31.3 adds its own screenshots there. No change to "What you can use it for", which `use-cases` pins as exactly two lines.
- No Mermaid diagram, evaluation line or CI badge (Story 31.3). No fix or crop for the mixed time zones in images 1 to 3 (DW-574, accepted for 1.0.0).
- No `.gitignore` edit. No change under `src/`, `web/`, `ci/`, `release/` or in `docker/tests/lib-scan.sh`. No `<img>` or other HTML image tag. No local absolute path or non-ASCII byte in any text file. No IRIS, slot or throwaway is needed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Real tree | the edited tree, the five PNGs staged | `test-readme.sh` prints the 23 PASS lines of Verification, then `SKIP #telegram`, and exits 0 | No error expected |
| Section drifts | `## How you talk to it` removed, renamed, or moved below "What OcuTalon does"; a fact of the section removed or moved out of it; its table or its image line removed; the word Slack in it | `FAIL how-you-talk` (and `FAIL top` for the heading cases) | exit 1 |
| Hero drifts | no image line between the teaser and the first H2; two image lines there; the image above the teaser or under the first H2 | `FAIL top` | exit 1 |
| Image link broken | empty or blank alt text; a target outside `docs/images/` (an existing file elsewhere, dot segments, a remote address); a target the tree does not list; the second image on a line broken; no image link at all | `FAIL images` | exit 1 |
| Images not staged | a `docs/images/` PNG ignored and not in the index | `FAIL images` and `FAIL readme-links` | exit 1 |
| New image, general | a copy of the listing with an extra `docs/images/` file, linked with alt text | `images` flags nothing | No error expected |
| Embed | an HTML media tag (any case); an image inside a link; a remote, non-PNG or reference-style image | `FAIL teaser` | exit 1 |
| No README | README.md absent | every rule, the two new ones included, prints `FAIL <rule>: README.md is missing` | exit 1 |

</intent-contract>

## Code Map

- `README.md` (249 lines): the title at line 1, the opening at 3, the teaser at 5, `## Try it in two minutes` at 7, "What's interesting" at 18 (101 words; cap 120), "What you can use it for" at 22, and `## What OcuTalon does` at 27. In that section, the bullets "Chat on a live page." at 38 and "Break the feed." at 39, then the model paragraph and table, which must stay the section's end (`key-account`). `### Demo mode` at 183 (slug `demo-mode`). Pure ASCII.
- `docker/tests/test-readme.sh` (1160 lines). The parts this story touches:
  - the header's "What it pins" list (5-41) and "What it reads" (42-45);
  - `listing=$(scan_files)` (82) and `in_tree` (87);
  - the constants (109-142), with `H_USE`, `OPENING` and `TEASER`;
  - the readers `headings` (148) and `section` (157);
  - `chk_facts` (166), `chk_block` (176), `st` (225), `st_append` (240), `st_move` (244), `st_facts` (249), `rule_begin` (264), `finish` (279);
  - `chk_top` (298): its awk refuses any non-blank line before the first H2 except the opening and the teaser, and it checks the first three H2s;
  - `chk_teaser` (385): the embed scan at line 402 refuses any `![`;
  - `chk_readme_links` (723), which already resolves `](path)` targets through `scan_files`;
  - `rule_top` (748), `rule_teaser` (814), `rule_product_links` (1050), the source of the list-file pattern `$tmp/product.list`;
  - `RULES` (1122) and the no-readme and unlisted loops (1124-1152).
- `docker/tests/lib-scan.sh`, read only: `scan_files` is `git ls-files -co --exclude-standard`, so an ignored untracked file is not listed, but a file in the index is.
- `.gitignore`, read only: line 8 is `images/` (the Early Access image guard), which matches `docs/images/`. `git add` on such a path exits 1 with "paths are ignored" even when the path is tracked, although it still stages the change. This was probed on a scratch repository.
- `docker/tests/test-boundaries.sh`: its ASCII scan covers `docker/`, `src/`, the web sources and similar folders, not `docs/`. Its path and key scans skip binaries. `logo/web/*.png` are already tracked binaries.
- `docker/tests/test-release-notes.sh:866` runs `names_outside_section` on README.md, so the alt texts must hold no dotted class name. `release/checklist.sh` reads README's first line and the note, which are unchanged.
- `ci/units.sh:164` `NOT_IRIS_INPUT_PATTERN` covers `docs/`, `*.md` and `docker/tests/test-*.sh`, so the push runs the hosted `checks` job and skips the IRIS groups (inference; `ci/changes.sh` decides).
- The UI strings, checked at the plan base `61b93a3240a4ece108bf327eb04e71f0b8b71df6`:
  - `web/src/app/devices/device-view.ts:18-20` (`Simulated devices`, `Simulated phone`, `Simulated mailbox`);
  - `web/src/app/header/demo-view-texts.ts:12-13` (`Demo view`, "Off shows the page as it looks on your own install.");
  - `web/src/app/shared/demo-view.ts:15-21` (the switch shows only in demo mode; off hides the guide, Break the feed, the simulated devices and the demo lines);
  - `web/src/app/rail/rail-view.ts:26-32` (`Approval requests`, `Background checks`, `Reminders`, `Recent decisions`);
  - `web/src/app/guide/guide-view.ts:56` ("simulate an incoming email in the simulated mailbox and see what OcuTalon decides");
  - `web/src/app/msg/catalog.ts:24,33,40` (`Approved from {channel} at {time}`, `All {count} {itemNoun} went through.`, `Recorded in the IRIS audit log.`);
  - `web/src/app/header/header.ts:384-388` (the `Online demo` pill);
  - `web/src/app/live/reset-schedule.ts:38` (`Next reset ...`).
- Continuity: Story 10.4's spec gives the matrix, scratch-tree and mutation format reused here, and its `chk_block` helper.

## Tasks & Acceptance

**Execution:**
- `docs/images/` -- Copy the five files from the source folder the lead names in the implement spawn prompt, with `cp`, under the exact names in Design Note 1. Check each size and sha256 prefix (Verification). Look at each image with the Read tool against the stop list. Then run `git add -f -- docs/images/<each name>` -- AC3 (Design Note 4).
- `README.md` -- Insert the hero block, the three indented image paragraphs and the new section exactly as Design Note 1 gives them. Change no existing line -- AC1, AC2, AC4.
- `docker/tests/test-readme.sh` -- Make Design Note 2's changes -- AC5 to AC7.
- this spec -- Record the Verification results, the image look, and one `mutation:` line per AC -- Rule 19.

**Acceptance Criteria:**
- AC1: Given the README, when a judge reads past "What you can use it for", then the fourth H2 is "How you talk to it", holding Design Note 1's text:
  - the web chat page is OcuTalon on every install;
  - demo mode adds the demo guide, Break the feed, the Simulated phone and the Simulated mailbox, and nothing else is offered as a way to talk to it;
  - email comes in a later release;
  - a three-row table;
  - no Slack, no Telegram and no "from your phone".
- AC2: Given the build at the plan base, when each sentence, table cell and alt text of this story is checked against `web/src` and the README's existing claims, then each one agrees (Design Note 3), and every quoted UI string (`Demo view`, `Break the feed`, `Simulated phone`, `Simulated mailbox`) matches the page's source exactly.
- AC3: Given the five delivered files, when they are added, then:
  - each `docs/images/` file's byte size and sha256 prefix equal Design Note 1's table;
  - `git ls-files docs/images` lists exactly those five;
  - each was looked at before staging, both in the lead's `images_inspected` record and in the implement stage's own look, with nothing from the stop list.
- AC4: Given the README, when a judge reads it, then:
  - the hero is the one image line between the teaser line and `## Try it in two minutes`;
  - `vt-decision.png` sits under the "Chat on a live page." bullet;
  - `incident-card.png` and then `incident-resolved.png` sit under the "Break the feed." bullet;
  - `page-demo-view-off.png` sits in "How you talk to it";
  - each image has Design Note 1's alt text, which says what it shows and never says that image 5 is a local install.
- AC5: Given `test-readme.sh`, when it runs, then `images` checks every Markdown image link in README.md:
  - non-empty alt text;
  - a target that is a file directly in `docs/images/` and that the tree lists;
  - at least one image link.
  It names no image file, so a newly listed and linked `docs/images/` file passes and an unlisted one fails.
- AC6: Given `test-readme.sh`, when it runs:
  - `top` pins the first four H2s in order and exactly one image line between the teaser and the first H2;
  - `teaser` still refuses every HTML media tag, an image inside a link, and any image that is not an inline `docs/images/*.png` image;
  - every other pin of both rules is unchanged, and the no-readme loop covers `how-you-talk` and `images`.
- AC7: Given the real tree, when the script runs, then it prints exactly the 23 PASS names of Verification plus `SKIP #telegram`, exits 0, and each rule goes red on its matrix row.
- AC8: Given the story's diff, when it is reviewed, then:
  - it touches only the footprint;
  - its text files hold no local absolute path and no non-ASCII byte;
  - it adds no Mermaid diagram, evaluation line or CI badge;
  - `git diff <baseline> -- README.md` shows only added lines.

## Spec Change Log

## Review Triage Log

## Design Notes

**1. What goes in.**

Images (copied as delivered; the acceptance pin):

| File | Bytes | sha256, first 16 hex |
| --- | --- | --- |
| `docs/images/page-incident.png` | 297920 | 07972ee2613d6599 |
| `docs/images/incident-card.png` | 265772 | 74338f24e974ba0b |
| `docs/images/incident-resolved.png` | 248087 | 62a447eef5cf6f7d |
| `docs/images/vt-decision.png` | 196280 | f9c28d8959be1fac |
| `docs/images/page-demo-view-off.png` | 206381 | 0b276504dcbca13e |

(a) Hero. Insert after line 5, the teaser line, so that the teaser stays two lines below the opening and the hero follows:
```
Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU

![The OcuTalon page on the online demo: an incident card for 50 failed orders names the cause and shows a dry run of the fix waiting for approval; the simulated phone shows the same approval request.](docs/images/page-incident.png)

## Try it in two minutes
```

(b) In "What OcuTalon does", add indented continuation paragraphs (two spaces, each with an empty line before it) inside the bullets. Insert after the "Chat on a live page." line:
```

  ![Visual Trace of the decision: the incident goes to the decision process, which calls the diagnosis agent; each agent step and the dry run is a production message.](docs/images/vt-decision.png)

```
Insert after the "Break the feed." line:
```

  ![An incident card: the partner changed the order date format, so 50 orders failed; OcuTalon shows the fix's dry run and waits for Approve or Reject.](docs/images/incident-card.png)

  ![The same incident resolved: approved from the web chat, all 50 orders went through, and the approval is recorded in the IRIS audit log.](docs/images/incident-resolved.png)

```
The list stays one list, now loose. The model paragraph and table stay the section's end, and its five `|` lines stay the only ones in the section.

(c) The new section, between the use-case items and `## What OcuTalon does`. Each paragraph and row is one line:
```
## How you talk to it

The web chat page is OcuTalon on every install. Demo mode adds four parts to it for trying OcuTalon out: the demo guide, Break the feed, the Simulated phone and the Simulated mailbox.

| Part | What you do there | Where you have it |
| --- | --- | --- |
| The web chat page | Chat with OcuTalon, answer its approval requests, and follow its decisions, background checks and reminders as they happen | Every install |
| The demo guide and Break the feed | Follow one incident in about two minutes: Break the feed makes a simulated partner's orders fail for real | Demo mode |
| The Simulated phone and the Simulated mailbox | See OcuTalon's notices, reminders and approval requests on a phone simulated on the page, and simulate an incoming email to see what OcuTalon decides | Demo mode |

Demo mode is on in the online demo, and on the Docker install until an admin switches it off ([Demo mode](#demo-mode)). Email comes in a later release.

In demo mode, the Demo view switch in the header hides those four parts. With it off, you see what the page has on your own install:

![The online demo's page with Demo view off: the chat, approval requests, background checks and recent decisions that the page has on your own install, with no demo guide and no simulated devices.](docs/images/page-demo-view-off.png)
```
No alt text holds `[`, `]`, `(` or `)`.

**2. `test-readme.sh` changes.** These extend the existing framework (Rule 2). Reused siblings: `headings`, `section`, `chk_facts`, `st`, `st_append`, `st_move`, `st_facts`, `rule_begin`, `finish`, and `rule_product_links`'s list-file pattern.
- **Helper `image_links <file>`**, beside `headings`. It prints `<line>\t<alt>\t<target>` for every inline Markdown image `![alt](target)` outside a code fence, every match on a line, not just the first. Both `teaser` and `images` read it, so neither rule keeps its own parser.
- **Constants:** add `H_TALK='How you talk to it'`, and `TALK_FACTS`, one per line:
  - `The web chat page is OcuTalon on every install.`
  - `| The web chat page |`
  - `Every install`
  - `Demo mode`
  - `demo guide`
  - `Break the feed`
  - `Simulated phone`
  - `Simulated mailbox`
  - `Demo view`
  - `Email comes in a later release.`
  - `](#demo-mode)`
- **top:**
  - Between the title and the first H2, a non-blank line may be the opening, the teaser, or a line made only of one image link (`^!\[.*\]\(.*\)$`). There must be exactly one image line, and it must come after the teaser.
  - The first four H2s are `H_TRY`, `H_INT`, `H_USE` and `H_TALK`, in this order.
  - Every other check stays.
  - New self-tests: the hero removed; a second image line; the hero moved above the teaser; the hero moved under the first H2; `## How you talk to it` removed; renamed; swapped with "What OcuTalon does"; swapped with "What you can use it for".
  - The existing 'a line between the teaser and the first H2 section' self-test must still go red.
- **teaser:** replace the line-402 scan with these refusals:
  - (i) the HTML tags `img`, `iframe`, `video`, `embed`, `object` and `picture`, in any case;
  - (ii) `[![`, an image inside a link: the video-thumbnail shape;
  - (iii) any `![` on a line beyond that line's count of inline images whose target matches `^docs/images/[^/]+\.png$`. This covers remote, local-elsewhere, non-PNG and reference-style images.
  - Keep the six existing embed self-tests. Add: a linked image, `[![Teaser](docs/images/page-incident.png)](https://youtu.be/wycbyfnXFMU)`; a remote image, `![teaser](https://youtu.be/wycbyfnXFMU)`; a GIF, `![teaser](docs/images/teaser.gif)`; a reference-style image, `![teaser][t]`.
  - The real README, with five PNG images, is the negative case.
- **images** (new rule `images`):
  - `chk_images <readme> <list file>`, where the list file is `$tmp/files.list`, holding `$listing`.
  - It flags a README with no image link.
  - For each image link: an alt that is empty after trimming spaces; a target that is not `docs/images/<name>`, with no `/` in `<name>` and no `..`; a target that is not a whole line of the list file.
  - Self-tests use the README's own first image target, never a fixed name: empty alt; blank alt; a missing file; an existing file outside `docs/images/` (the first line of the listing that matches `^logo/.*\.png$`); dot segments; a remote address; a second image on the line with no alt; every image line removed; the first image's file dropped from a copy of the list.
  - Negative self-test (generality): a copy of the list plus `docs/images/zz-extra.png`, with a README copy that adds `![Extra.](docs/images/zz-extra.png)`, is not flagged.
- **how-you-talk** (new rule `how-you-talk`), on the section `H_TALK`:
  - It flags: a missing or empty section; any missing `TALK_FACTS` line; no line that starts with `| --- |`; no image line; the word `slack` in any case.
  - Self-tests: the heading removed; `st_facts` on `TALK_FACTS`; the Demo-mode paragraph moved out (`st_move` with the prefix `Demo mode is on in the online demo`); the table rows removed; the image line removed; `It also works in Slack.` inserted under the heading.
- **Housekeeping:**
  - `RULES='top try_it interesting use_cases how_you_talk teaser images outcomes install install_pointer commands key_account lan sign_in_address demo_mode admin_commands after_start_log dev_only public_text no_telegram product_links readme_links must_scan'`.
  - Update the header: Stories 10.2, 10.4 and 10.5; the two new rule lines; the new `top` and `teaser` wording; and "What it reads" gains the tree's file list for `docs/images/`.
  - Contract comments only (Rule 14).

**3. Claims checked against the build** (plan base `61b93a32`). Every claim agrees, so there is no intent gap.
- "web chat page ... every install": FR-12, and the page's chat and rail are the same on every install (`rail-view.ts:26-32`).
- "answer its approval requests" in the chat: Story 6.2.
- "decisions, background checks and reminders as they happen": the rail labels, and FR-12's live updates.
- Demo mode adds the guide, Break the feed and the simulated phone and mailbox: FR-12 ("in demo mode, ..."), and README "Demo mode" ("It adds the demo guide, the Simulated phone and mailbox, and Break the feed").
- "on the Docker install until an admin switches it off": README "Demo mode is on for the Docker install", and `SetDemoMode`.
- "about two minutes": `guide-view.ts` "About 2 minutes", and README item 1.
- "makes a simulated partner's orders fail for real": the README's Break the feed bullet.
- The Simulated phone shows notices, reminders and approval requests: FR-13 and AD-14.
- "simulate an incoming email to see what OcuTalon decides": `guide-view.ts:56`.
- "Email comes in a later release": AD-14 (Email, step 4), and AD-29 (step work after 1.0.0).
- The Demo view switch is in the header, only in demo mode, and off hides the four parts: `demo-view.ts:15-21` and `header.ts:74`.
- "what the page has on your own install": `demo-view-texts.ts:13`. The Online demo pill and the reset countdown stay, so the alt says "The online demo's page", never that it is a local install.
- Alt texts 2 and 3: `catalog.ts:24,33,40`.
- Alt text 4: the lead's description of the image (IncidentManager -> Decide -> DiagnosisAgent, AgentStep, DryRun) and AD-9/AD-26. It uses no class name, because `dev-only` and `test-release-notes` forbid dotted names outside the admin section.

**4. The `.gitignore` trap (decided in-stage).** `images/` ignores `docs/images/`. If nothing handled this, the step-03 diff and the finalize commit would leave the PNGs out without any error, the working copy would still look clean, and only CI's `readme-links` and `images` would go red.
- Chosen: `git add -f` once in the implement stage. It keeps the footprint AC and leaves the Early Access image guard unchanged.
- Rejected: a `!docs/images/` negation. It is outside the footprint AC and touches the guard file.
- `images` is also the local alarm: a PNG that is not staged is unlisted, so `images` and `readme-links` go red before commit.
- For the finalize commit, the files are already in the index. Commit with a pathspec or a plain `git commit`, and do not `git add` them again: that exits 1 even though it stages.

**5. Architecture decisions.**
- AD-29: README.md and `test-readme.sh` are Lane B files; `no-telegram` is the guard and stays unedited.
- AD-22: `test-readme.sh` runs in the hosted `checks` job.
- AD-14 and AD-25: the channels, and the online demo has no bot, which backs the claims.
- AD-9 and AD-26: the Visual Trace content.
- No AC contradicts an AD's Rule.

**6. Rules 1, 2 and 17.** No service, module or shared component: docs, five images and a hermetic test script, so no Integration AC applies.
- Consumes: none.
- Consumed-by: Story 10.6 adds the Telegram row to this section and its pin to `how-you-talk`. The facts are not a row count, so a row adds cleanly. Story 31.3 adds `docs/images/` screenshots, which `images` covers with no edit.
- Ledger inbox: none. DW-554 is routed elsewhere and is not in this story.

**7. Plan-stage probe.** A scratch tree had the README built from Design Note 1's blocks and five stand-in PNGs staged with `git add -f`. The current `test-readme.sh` failed only `top` (the hero line) and `teaser` (the five image lines), the two rules this story reworks. Every other rule passed, `interesting` included (still 101 words), and so did `test-boundaries.sh` and `names_outside_section` on the README. So no kept rule rejects the planned text.

**Decided in-stage.**
- (a) The hero goes after the teaser line. Story 10.4 pins the teaser as the second line below the opening, and the hero still sits under the opening block.
- (b) Images 2 to 4 go in "What OcuTalon does". "What's interesting" would break its 120-word cap and collide with Story 31.3, and "What you can use it for" is pinned to two lines. The VT shot goes under "Chat on a live page." because it is the README bullet that describes Visual Trace.
- (c) The text says "demo mode", not "the online demo", because the Docker install also runs demo mode. FR-12 says the same.
- (d) No caption lines: the alt text and the sentence above carry the meaning.
- (e) `top` requires the hero, not just allows it, because it pins AC4.
- (f) `teaser` allows only `docs/images/*.png`. An animated GIF could serve as a player.
- (g) Slack is refused within the section only, as the AC's scope says.
- (h) Design Note 4.

**For the lead (not decided here; route as you see fit).**
- (1) Story 31.3's AC adds two screenshots under "What's interesting": the page on the demo path, and a Visual Trace of one decision. These overlap this story's `page-incident.png` and `vt-decision.png`. The epic context says an overlap is raised, not decided here. This story leaves "What's interesting" untouched, so 31.3 keeps a free choice.
- (2) Story 31.3's new `docs/images/` files will hit the same `.gitignore` line. Either it uses `git add -f`, or a later story adds `!docs/images/`. No epic owns `.gitignore`.

## Verification

No IRIS, slot or throwaway is needed. If a live check ever runs, it is runner C's: MCP `server` `ocutalon-slot-c`, namespace `OCUTALON`, `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c"`, `OCUTALON_TEST_WEB_PORT=52803`, `OCUTALON_LOCK_OWNER='epic=10 stage=<stage>'`.

Names used below:
- `<scratch>` is the implement stage's own scratchpad subfolder, whose absolute path its spawn prompt gives. It is never written into a committed file.
- `<tree>` is `<scratch>/tree`, built with `git ls-files -co --exclude-standard -z | tar --null -T - -cf - | tar -xf - -C <tree> && git -C <tree> init -q && git -C <tree> add -f docs/images`. Without the `add -f`, the tree's own `.gitignore` hides the PNGs from `scan_files`. Never commit in it. Each row edits the tree's copy and is reset with `cp` from the worktree.
- `<baseline>` is the frontmatter `baseline_commit` that the implement stage records.

**Commands:**
- (loop) `bash docker/tests/test-readme.sh` -- expected: 23 PASS lines, `SKIP #telegram`, `test-readme: all rules passed`, exit 0.
- (loop) `bash docker/tests/test-readme.sh | sed -n 's/^PASS \([a-z-]*\):.*/\1/p' | tr '\n' ' '` -- expected exactly: `top try-it interesting use-cases how-you-talk teaser images outcomes install install-pointer commands key-account lan sign-in-address demo-mode admin-commands after-start-log dev-only public-text no-telegram product-links readme-links must-scan `.
- (loop) Image pin: `for f in page-incident incident-card incident-resolved vt-decision page-demo-view-off; do p=docs/images/$f.png; echo "$p $(wc -c < $p | tr -d ' ') $(shasum -a 256 $p | cut -c1-16)"; done; git ls-files docs/images` -- expected: the five rows of Design Note 1's table, then exactly those five paths.
- (loop) Placement: `awk '/^## /{s=$0} { line=$0; while ((i=index(line,"](docs/images/"))>0) { line=substr(line,i+14); t=line; sub(/\).*/,"",t); print (s==""?"(top)":s) " -> " t } }' README.md` -- expected exactly these five lines, in order: `(top) -> page-incident.png`, `## How you talk to it -> page-demo-view-off.png`, `## What OcuTalon does -> vt-decision.png`, `## What OcuTalon does -> incident-card.png`, `## What OcuTalon does -> incident-resolved.png`. A plan-stage probe built the target README from Design Note 1 and printed exactly these lines.
- (loop) Owner text kept: `git diff <baseline> -- README.md | grep -c '^-[^-]'` -- expected `0` (added lines only).
- (loop) `LC_ALL=C grep -n '[^[:print:][:space:]]' README.md docker/tests/test-readme.sh _bmad-output/implementation-artifacts/spec-10-5-*.md` -- expected: no output.
- (loop) `uvx --from shellcheck-py==0.9.0.6 shellcheck docker/tests/test-readme.sh` -- expected: no findings.
- (loop) `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-release-notes.sh` -- expected: each exits 0.
- (loop) Matrix: each row is a one-line edit of `<tree>`'s README.md, unless another file is named. `bash <tree>/docker/tests/test-readme.sh` must exit 1 with the rule's FAIL.
  - how-you-talk: `Email comes in a later release.` removed; `It also works in Slack.` under the heading.
  - top: the hero line moved under `## Try it in two minutes`; the heading `## How you talk to it` renamed.
  - images: the alt of `vt-decision.png` emptied; `incident-card.png` renamed to `incident-cards.png` in its link; `git -C <tree> rm --cached -q docs/images/page-incident.png` (not staged).
  - teaser: `[![Teaser](docs/images/page-incident.png)](https://youtu.be/wycbyfnXFMU)` appended; `<img src=docs/images/page-incident.png>` appended.
  - no-telegram: `Telegram` added to the section's first paragraph.
  - Every row of Story 10.4's matrix still goes red for its own rule.
  - No README: every rule prints that README.md is missing.
- (once) GNU tools: run `<tree>`'s test in the local `ubuntu:24.04` image (`docker run --rm`, the tree mounted read-only, with a `git ls-files` stand-in that prints the tree's file list, the five PNGs included, filtered by the pathspec prefix, as Story 10.4 did) -- expected: the same 23 PASS and the SKIP. If the image is absent, record that and rely on the hosted `checks` job.
- (once) `bash ci/checks.sh` with `timeout: 600000` -- expected: `checks: all scripts passed`.

**Manual checks:**
- Look at each of the five images, compare it with Design Note 1's placement and alt text, and record "looked at; nothing from the stop list". The lead's `images_inspected` line in the cycle log also covers this.
- Render check by reading: each image paragraph has an empty line before and after it, and the three in "What OcuTalon does" are indented two spaces.
- `git diff --stat <baseline>` names only README.md, the five PNGs, `docker/tests/test-readme.sh` and this spec.

Shared surfaces:
- README.md's H2 list and slugs. They are read by `top` (now the first four), `readme-links`, `product-links`, `install-pointer`, `sign-in-address` and `lan`. The new slug is `how-you-talk-to-it`; no page anchor names it.
- README.md's image lines, read by `teaser`, `images` and `readme-links`. `test-release-notes.sh`'s `names_outside_section` and `release/checklist.sh`'s first-line and note checks read README too, and both are unchanged (DW-554's shared scanner is not touched).
- `test-readme.sh`'s `RULES`, now 23 names. No other test reads it, and `CHECK_SCRIPTS`' `readme` is unchanged.
- The `docs/images/` folder: Story 31.3 adds to it.

Every test added or changed passes on a fresh environment, in either order: `test-readme.sh` starts nothing and reads only the tree's listed files, the five PNGs tracked after the commit.

Mutations (Rule 19; the implement stage writes one `mutation:` line per AC, each on `<tree>`, reverted and compared byte for byte):
- AC1: `Email comes in a later release.` removed -> `FAIL how-you-talk`.
- AC2: none, because it is a recorded check (Design Note 3). Confirm `git diff --stat <baseline> -- src web ci` is empty.
- AC3: one byte appended to `<tree>/docs/images/vt-decision.png` -> the image-pin command shows a different size and prefix.
- AC4: the hero line moved under the first H2 -> `FAIL top`.
- AC5: `chk_images`'s alt test replaced by `true` -> `FAIL images: a broken copy was not flagged`. Also: `chk_images` made to accept only the five current names -> the generality self-test is flagged.
- AC6: the new teaser refusal (ii) removed -> `FAIL teaser: a broken copy was not flagged` (the linked-image self-test).
- AC7: `images` dropped from `RULES` -> `FAIL rules: rule_images is not in RULES`.
- AC8: `![badge](https://example.org/b.svg)` appended -> `FAIL teaser` and `FAIL images`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). For the lead: Design Note "For the lead" items (1) and (2): the Story 31.3 screenshot overlap, and the `.gitignore` `images/` line that ignores `docs/images/`, which this story handles in-footprint with `git add -f`.
