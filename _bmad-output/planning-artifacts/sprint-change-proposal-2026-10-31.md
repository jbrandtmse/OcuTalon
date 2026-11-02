---
project: OcuTalon
date: 2026-10-31
trigger: the owner's decisions of October 31, relayed by the Contest Planner (the release chain, Epic 38, the IPM web page, the README, step 7, daily releases and the personality epics), and two launch faults found on the online demo host the same day
mode: batch; each change was decided on the day through the Contest Planner under the owner's delegation, and the personality epics went to the Contest Planner as one planning veto item (inbox U-195)
status: approved; changes 1 to 5 are applied (feature head 95480ccf, plus the Epic 11 and Epic 12 branches for the moved stories); changes 6 and 7 are applied by the U-195 planning patch and, for the policy file, the hold-10 script
---

# Sprint Change Proposal: one release at 1.0.0, two launch fixes and the personality track (October 31, 2026)

## 1. Issue summary

On October 31 the build was a day from the online demo going public (PRD §7.4: about November 1, Saturday October 31 evening at the earliest) and about three days from 1.0.0. Seven course changes were made that day. None reopens a product rule: classification outside the model, approvals, untrusted and tainted handling, and AD-28 (no model-written all-clear) all stand.

- **Problem type:** a release chain that could not run without idle days, an epic that could not merge, two faults seen on the live demo host, a README that didn't sell the product, and new scope the owner wants shipped right after 1.0.0. No technical limitation and no rollback.
- **What triggered each change:**
  1. **The release chain.** The plan cut 0.1.0, then 0.1.1 with Telegram, then 1.0.0, with tag gates between them (U-189's answer names the chain: v0.1.0, then Epic 12's merge, v0.1.1, Epic 31, 1.0.0). The owner is away from November 2 about noon PST to November 3 morning, and a late Epic 12 merge would have left the runners idle about 18 hours waiting for a tag. At about 13:10Z the Contest Planner asked the owner, who answered "One check, at 1.0.0" and "New Linux droplet".
  2. **Epic 11 could never merge as planned (U-189, 09:04Z).** An epic merges only when every story is done. Story 11.6 (the Contest Planner's real-key pass) and Story 11.3's timed runs on real clean hosts both run on the candidate that Story 11.5 cuts after Epic 11 merges, so each waited on a merge that waited on it. Story 12.7, Epics 13 and 14 and Story 15.3 waited behind it.
  3. **The IPM package and its web page.** Nothing said whether a package installed from the registry carries the built web page, and the load-from-folder path needs Node.js to build it (Story 15.3).
  4. **The README.** The owner: "if OcuTalon can run on just rules, why would anybody need a model? We don't do a good job of selling the value proposition." and "I'm not sure that I want to keep the "Contest task -> where to see it" section. Let's remove it for now and consider adding it back in later if it makes sense."
  5. **Two faults on the online demo host (fe1d81e2).** One in six diagnoses in the load run fell back as `invalid`, though the reply was correct (Story 5.12); a second invalid diagnosis at 12:01:54Z broke the same rule. And the splash promised Telegram and a QR code that the page doesn't have yet (Story 16.11).
  6. **Room for new work after 1.0.0.** The owner wants three personality epics "so we can ship them as soon as possible": "I want Heartbeat enhancements, persona and memory enhancements to be able to be on different lanes so they can ship quickly." Step 7 moves to after the contest to make room, and "After 1.0.0 we'll move to daily releases of whatever features are complete."
  7. **The personality epics,** drafted as one plan (`plans/plan-personality-epics-2026-10-31.md` in the coordination notes), raised as U-195 at 14:38:37Z, and answered at 14:47:21Z by the Contest Planner under the owner's delegation: approved with changes.
- **Settled and unchanged:**
  - 1.0.0's scope and dates (the owner's ask): the 1.0.0 submission milestone still covers Epics 0 to 16 and 29 to 32;
  - the online demo goes public on its own, ahead of 1.0.0 (the October 30 decision);
  - nothing from a step epic or a personality epic enters 1.0.0;
  - every governance rule (the owner's spec: "every governance rule stands").

## 2. Impact analysis

**Epic impact.**

- **New epics:**
  - Epic 38, "1.0.0 is checked by hand and cut" (Stories 38.1 to 38.3);
  - Epic 39, the agent heartbeat (6 stories);
  - Epic 40, the persona (7 stories);
  - Epic 41, memory (7 stories, then 7 more at a re-open).
- **Re-opened under SC-5** (the precedent is Story 32.4):
  - Epic 10, for Story 10.4 (merged at 62d2f251, 11:32Z);
  - Epic 5, for Story 5.12;
  - Epic 16, for Story 16.11.
- **Gates changed:**
  - Epics 12 and 31 lose their tag merge gates;
  - Epics 33, 34, 17 and 18 start once Epic 12 has merged and merge only once `release/1.0.0-rc1` exists.
- **Narrowed:** Epic 11 merges once Stories 11.1, 11.2, 11.4 and 11.5 (with its rehearsal mode) and 11.3's harness and dry runs are done, so the edges on it (12.7, 13, 14, 15.3) clear at that merge.
- **Out of the contest plan:** Epics 27 and 28 (step 7).
- **Runner moves:** Epic 30 yielded runner B to Story 5.12 and integrates it at its re-dispatch, since both change `Decide.cls`.

**Story impact.**

- **Moved:**
  - Story 11.6 to Story 38.1, whole and verbatim, with DW-299, DW-358 and DW-365;
  - Story 11.3's real-host criteria to Story 38.2, verbatim;
  - Story 12.7's real-device criteria to Story 38.3.
- **New:** 5.12, 10.4, 16.11, 39.1 to 39.6, 40.1 to 40.7, and 41.1 to 41.14 (41.10 and 41.11 optional).
- **Criteria added:**
  - Story 11.5: the web page goes into the package;
  - Story 15.3: the registry-first guide, and the proof from a local IPM repository;
  - Story 31.3: the registry-first README section;
  - Story 10.2: markers for what Story 10.4 replaced;
  - Stories 38.1 and 38.2: step 2 runs through the guide's own Send (U-190).
- **Read-as rule:** where a line in `epics.md` names 0.1.0 or 0.1.1 as a release, a candidate or a gate, read 1.0.0.

**Artifact conflicts.**

- **PRD:**
  - §7.2 has the "Superseded on October 31" note.
  - At HEAD, §7.1, §7.3 and §7.4 still state the 0.1.x split: step 1 "(release 1, then 0.1.1)", REL-7's two step-1 passes ("before 0.1.0 … and before 0.1.1"), REL-9's "numbered 0.1.x, with release 1 as 0.1.0", and the 0.1.0 and 0.1.1 timeline rows, and the §7.2 note is the PRD's only marker for the change. The planning patch adds a release-names note to §0 ("read 1.0.0"), marks each of those uses inline, and re-marks §7.2's earlier October 31 marker (step work merging after 0.1.1) as superseded by the note.
  - The U-195 patch adds §4.15 (FR-63 to FR-74), NFR-27 and NFR-28, the [Personality] tag and the daily-release text, and changes NFR-24, NFR-26 and FR-7's safe list.
- **Architecture spine:**
  - AD-29 carries the release markers.
  - The U-195 patch amends AD-1, AD-7, AD-11, AD-18, AD-19, AD-21, AD-29 and AD-33's ownership rows.
- **UX:** `EXPERIENCE.md` and `DESIGN.md` gain three cards and markers (change 7.5).
- **Product brief:** gains one dated addendum note.
- **Graph (`_bmad/custom/epic-dependencies.yaml`):**
  - the `epic-38` row;
  - the new `merge_gate {branch}` form;
  - the dropped gates;
  - the U-195 rows, with step 7 off the lane and pool orders.
- **Policy (`_bmad/custom/unattended.yaml`):**
  - owner_fixed line 14 (with line 15) changes at hold #9;
  - the U-195 find-and-replace pairs, pair 7 included, go in at the hold after it.
  - A policy edit in the middle of a run stops the run (doctrine U3), so until a hold applies the edit, the line as it stands governs.

**Technical impact.**

- **One candidate:** `release/1.0.0-rc1`, recorded under `release/records/1.0.0/`. One clean Linux droplet is created and deleted by the Contest Planner for each check, driven from the Contest Planner's Mac, with no clean macOS run.
- **The IPM artifact** grows by the built web bundle; its size goes into the release notes.
- **The online demo still polls:** the online-demo flag never opens Epic 31's WebSocket (Story 31.1).
- **`DiagnosisPayload.Evidence`** accepts references up to 128 characters instead of 32.
- **The splash's Telegram lines** depend on `OcuTalon.Channel.Telegram.In.Included()`.
- **Heartbeat cost:** the heartbeat adds model calls only on due beats (NFR-28).
- **Evaluation:** the draft expects the release-candidate evaluation run to grow about fivefold for the persona sweep (minutes and a few cents).

## 3. Recommended approach

**Direct adjustment.** Every change edits the existing documents, adds a story to an epic, or adds an epic at the end of the list.

- **No rollback.** Nothing built is reverted. Story 10.4 merged on the day.
- **No MVP cut.** The 1.0.0 scope is unchanged. Step 7 was the Could step, and nothing in steps 1 to 6 depends on it: in the graph only Story 28.1 waits on Epic 27, inside step 7.
- **Why this path:**
  - One candidate check at 1.0.0 removes two cuts, two tag gates and two separate hands-on passes from a chain that would have idled the runners while the owner is away.
  - Epic 38 lets Epic 11 merge on what can be built and dry-run, and puts every human check in one place.
  - The two hotfixes protect the demo path on the day it goes public.
- **Effort:**
  - Epic 38 is people's work on one candidate, plus the fixes it finds.
  - Stories 5.12 and 16.11 are small: payload, prompt and trace in one case; one splash class and its catalog lines in the other.
  - The draft sizes the personality work at about 28 runner-hours for Epic 39, 33 for Epic 40, 33 for Epic 41's first part, and 33 (or 24 without Stories 41.10 and 41.11) for its second.
- **Timeline:**
  - **1.0.0 (forecast logged at 13:11Z; Monday is November 2):** the 1.0.0-scope epics merged about Monday 18Z to Tuesday 06Z, `release/1.0.0-rc1` about Tuesday 00Z to 08Z, and v1.0.0 about Tuesday 20Z to Wednesday 06Z.
  - **The personality epics:** the draft puts Epic 39 in the first daily release after 1.0.0 (about November 4), Epic 40 about November 4 to 5, Epic 41's first part about November 5 and its second part about November 6 to 7, after Epic 19.
  - **The cost to the steps:** the November 8 milestone for steps 2 to 5 slips about half a day.
  - **Idle windows:** with pair 7 approved, the draft expects all three personality epics could use idle windows before rc1 and make the first release after 1.0.0.
- **Risks:**
  - quota holds and account switches;
  - rc1 slipping;
  - Story 40.6's wait on Epic 12;
  - Story 16.11 missing the launch, which is accepted until Epic 12 merges;
  - invalid diagnoses from other causes, since the retry is deferred (DW-483, U-191).
- **Change scope: moderate.** The release chain, the graph and the backlog are reorganized, and three post-1.0.0 epics are added. 1.0.0 keeps its scope and dates, and no planning document is rewritten.

## 4. Detailed change proposals

Every marker cites its decision as the documents do: "[AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; the owner: …]" for the owner's words, or "decided by the Contest Planner under the owner's delegation" for an inbox answer.

### Change 1: 1.0.0 is the first release (owner, about 13:10Z; commit 311aa776)

**1.1 Epic List: the October 31 release decision.**
- **Before** (Epic List intro): "Release 1 (0.1.0) is Epics 0 to 11, the floor. Telegram (Epic 12) … ships as 0.1.1, the very next release".
- **After** (new bullet): "1.0.0 is the first release; 0.1.0 and 0.1.1 are not cut. Where a line in this document names 0.1.0 or 0.1.1 as a release, a candidate or a gate, read 1.0.0". Epic 12 and Epic 31 merge when done, Telegram ships in 1.0.0, and one full candidate check runs at 1.0.0 in Epic 38.

**1.2 Epic 12's merge gate.**
- **Before:** "It merges into the integration branch only once the `v0.1.0` tag exists, so no 0.1.0 candidate, re-cut or not, contains Telegram".
- **After:** the merge gate on v0.1.0 is dropped: Epic 12 merges when done, and Telegram ships in 1.0.0. The graph row notes "merge gate on v0.1.0 dropped 2026-10-31".

**1.3 Epic 31's merge gate.**
- **Before:** "The epic merges into the integration branch only once `v0.1.1` is tagged: polling stays release 1's contract".
- **After:** Epic 31 merges when done and ships in 1.0.0. The online demo still only polls, because the online-demo flag never opens the WebSocket (Story 31.1).

**1.4 The step epics' gates (Epics 33, 34, 17 and 18).** They changed twice on the day.
- **Before** (start of day): `gate: {tag: v0.1.1}`, so no step work started before 0.1.1.
- **Interim** (00:36Z, decided by the Contest Planner under the owner's delegation; the owner: "I agree with your recommendations."): start once Epic 12 has merged and v0.1.0 is tagged; `merge_gate: {tag: v0.1.1}`. The reason was the owner's absence and the 18 idle hours.
- **After** (13:10Z, the owner's decision): they start once Epic 12 has merged and carry `merge_gate: {branch: release/1.0.0-rc1}`, "so no step work enters 1.0.0".
  - The graph gains the `merge_gate {branch: <b>}` form, held until `git ls-remote --heads origin <b>` finds the branch.
  - Their other edges are unchanged: Epics 17 and 18 still start only once Epic 33 has merged, and Story 34.2 needs Epic 33 merged.

**1.5 AD-29.**
- **Before:** "**Prevents:** … step 2 work reaching the integration branch before Telegram ships".
- **After:** "step work reaching the 1.0.0 release (step epics merge only once `release/1.0.0-rc1` exists)".
- The step-contract bullet names `merge_gate: {branch: release/1.0.0-rc1}`. The Telegram bullet adds "1.0.0 is the first release, Telegram ships in it, and 0.1.0 and 0.1.1 are not cut; read the 0.1.x wording of this bullet as history."

**1.6 PRD §7.2.**
- **Before:** "Step 1 is the two-minute demo (UJ-1) plus Telegram, … shipped as two releases: release 1 (0.1.0, the floor) and 0.1.1 (Telegram)."
- **After:** a "Superseded on October 31" note: 1.0.0 is the first release, Telegram ships in it, one full candidate check runs on the 1.0.0 candidate, and step work merges only after the candidate branch exists. "The split below is kept as history."
- **Also, in the planning patch:** the earlier October 31 marker on §7.2's Telegram bullet ("merges only after 0.1.1") gets a marker saying the note supersedes it; §0 gains a release-names note, and every other 0.1.0 or 0.1.1 used as a release term in the PRD, the spine and the UX files gets a read-as-1.0.0 marker. `epics.md` keeps its Epic List rule and gains the same note at its top.

**1.7 A candidate branch is an internal step (09:09Z, an owner decision through the Contest Planner).**
- **Before** (the October 18 proposal, G5): "Pushing the candidate is the first outward step, on the author's word."
- **After:**
  - An rc branch is an internal step, not a release.
  - The release is the tag and the pull request to `main`, both on the owner's word (REL-11).
  - The Contest Planner starts Story 11.5's sequence after Epic 11 merges: it cuts the candidate, now `release/1.0.0-rc1`, and stops at the hands-on gate.

**1.8 The policy file's owner_fixed line 14.**
- **Before:** "0.1.0 is cut at Epic 11, and Telegram ships as 0.1.1."
- **After:** amended at hold #9 by the Contest Planner, with a marker, so that the policy matches the graph. Until then the line governs, and the graph header records it.

### Change 2: Epic 38 and U-189's split (U-189, answered 09:06:08Z; graph 255f5b44; rescoped at 13:10Z)

**2.1 The new epic.**
- **Before:** Epic 11 held Stories 11.3 and 11.6 and could not merge.
- **After, 09:07Z (option (a)):**
  - Epic 38, "0.1.0 is checked by hand and cut", holds Story 11.6 and Story 11.3's real-host timed runs.
  - It depends on Epic 11 and gates the v0.1.0 tag.
  - Epic 11's runner moves the stories. The run builds every script, harness and checklist with dry runs on throwaways and parks only the human parts (U-186, kept).
- **After, 13:10Z:**
  - Epic 38 becomes "1.0.0 is checked by hand and cut".
  - It depends on every 1.0.0-scope epic (0 to 16 and 29 to 32) and gates the v1.0.0 tag.
  - Its `needs_people`: one clean Linux droplet that the Contest Planner creates and deletes for each check; the Contest Planner's Mac as the driver; a real model key; the Contest Planner's real-key pass on `release/1.0.0-rc1`; the owner's Telegram pass on the same candidate; the cut and the tag.

**2.2 Story 11.6 becomes Story 38.1.** It is moved whole and verbatim; its "Given Stories 11.1 to 11.5 merged" now reads as Epic 11 and every other 1.0.0-scope epic merged, with the sequence stopped at the hands-on gate for `release/1.0.0-rc1`. The pass covers the web route. The Telegram pass on the same candidate is Story 38.3.

**2.3 Story 11.3 is narrowed, and Story 38.2 runs it for real.**
- **Before:** Story 11.3 timed the demo path on the owner's clean macOS and Linux hosts.
- **After:**
  - Story 11.3 keeps "what can be built and dry-run on throwaways".
  - Story 38.2 holds the real-host criteria, verbatim, on "one clean Linux droplet … which the Contest Planner creates for the check and deletes after it, and the Contest Planner's Mac as the driver host", with "no clean macOS run".

**2.4 Story 12.7's real-device part becomes Story 38.3.**
- **Before:** Story 12.7 ran the hands-on pass on "the 0.1.1 candidate `release/0.1.1-rc<n>`".
- **After:**
  - Story 38.3 holds it and runs on `release/1.0.0-rc1`.
  - It carries both of Story 12.7's real-bot criteria: the hands-on pass and the 20 timed real-bot runs (the note to Epic 11's runner at 14:28Z).
  - Epic 12's runner removes them from Story 12.7 in its own worktree, and the two edits meet at the merge.

**2.5 The real-key runs drive the judge's path (U-190, kept at 11:55:47Z).**
- **Before:** on the mock, Story 11.1 sends step 2 through the composer behind a marker, a workaround for AD-22.
- **After:** Stories 38.1 and 38.2 drive step 2 "through the guide's own Send, as a judge drives it", so the judge's path is proved on every candidate.

### Change 3: the published IPM package carries the built web page (decided by the Contest Planner under the owner's delegation, 08:44Z; commit 062473f0)

**3.1 Story 11.5.**
- **Before:** the sequence "builds the web bundle with Node.js and commits it on a new candidate branch … so a Docker install needs no Node.js".
- **After** (a criterion on Epic 11's branch, which reaches the feature branch with Epic 11's merge):
  - it also puts the built bundle into `src/ocutalon/csp/`, which `src/module.xml`'s `FileCopy` already copies, before packaging, so a registry install needs no Node.js;
  - `module.xml` doesn't change;
  - it records the artifact it would publish, so Story 15.3 can install exactly that artifact;
  - the registry publish stays the owner's, at 1.0.0.

**3.2 Story 15.3 proves it from a local repository.**
- **Before:** the only registry check ran after the owner's publish: "Given the author has published 1.0.0 to the package registry …".
- **After:**
  - Before any publish, Story 15.3 installs that exact artifact on a clean build 154 throwaway with no Node.js, through a local filesystem IPM repository (`zpm "repo"`, then `zpm "install ocutalon"`).
  - It proves that `/ocutalon/` serves the branded sign-in page and that the README account signs in.
  - The release notes record the artifact's size, and a size over a few MB is reported to the Contest Planner.

### Change 4: the README and the registry-first IPM guide

**4.1 Story 10.4 re-opens Epic 10** (the owner's decision through the Contest Planner, 06:30Z; commit 145b4018; merged at 62d2f251). The owner: "I like the opening draft, go ahead and make that change", "Yes 1,2, 3 and fold 4 into the opening" and "go with what we have for right now."
- **Before** (Story 10.2): "a "Contest task → where to see it" table that maps each part of the contest task … and each judging criterion … to the feature that meets it".
- **After:**
  - The table is gone.
  - Under "# OcuTalon" come an opening paragraph ("Your integrations already tell you when something breaks, usually fifty times. …") and the teaser line.
  - A new H2, "What you can use it for", has two items: the partner feed that breaks at 2am, and "Only tell me if something needs me."
  - The bullet "No key, still works." becomes a "With a model, and without one." paragraph and table (FR-4, FR-38).
  - Each later item goes in with the story that ships its feature: Story 30.4, Epic 12's Telegram section, Story 13.3.
  - Every table cell is checked against the built behaviour, and a cell the build contradicts is reported, never changed to match.

**4.2 Story 10.2.** Its "top of the README" criterion and its table line carry markers that quote what they read. `docker/tests/test-readme.sh` pins the new order, drops the `contest-table` rule, and keeps `public-text` and `no-telegram`.

**4.3 Story 15.3's guide opens with the registry install** (the Contest Planner, 08:43Z; commit b2e61e5e).
- **Before:** `docs/install-ipm.md` had no fixed order.
- **After:**
  - The guide opens with the line that enables the community registry on a fresh IPM, in its exact IPM 0.10.10 form with its output, both measured on the story's throwaway.
  - Then comes `zpm "install ocutalon"` with the two-step namespace message.
  - The load-from-folder path, which needs Node.js, comes second, for developers.
  - Story 15.3 doesn't publish: the registry install is measured after the owner publishes 1.0.0.

**4.4 Story 31.3's README IPM section** opens the same way, "in the order Story 15.3's guide uses".

### Change 5: the launch hotfixes (Epics 5 and 16 re-opened under SC-5)

**5.1 Story 5.12: a correct diagnosis is never refused for an over-long evidence reference** (the orchestrator, at the Contest Planner's request, 11:53Z; commit 8b8fd952; dispatched on runner B at 12:22Z).
- **Before:** `OcuTalon.Watch.Msg.DiagnosisPayload.Evidence` "refuses any reference over 32". A correct reply (the OrderDate cause, a `repair_resend` fix, confidence 0.92) failed on "trace PartnerOrdersIn to OrdersFromPartner", 42 characters, and the visitor got the fallback notice with no fix.
- **After:**
  - Each reference may be up to 128 characters, and the diagnosis prompt states the same limit.
  - A test replays the host's reply byte for byte.
  - Every reply class's limits are audited against its prompt.
  - On an `invalid` reply, the fallback's trace records the check's own error text: internal text that never reaches the page, a notice, the phone or the model.
  - The second invalid diagnosis (12:01:54Z) became the runner's second fixture.
- **Not in this story:** one retry on an invalid reply. It goes to Story 30.1 as DW-483. Kept by U-191: build it only if diagnose still falls back on invalid in more than about 1 in 50 after Story 5.12, and only if it fits NFR-7's 20-second diagnosis budget.

**5.2 Story 16.11: the splash promises Telegram only when the release includes it** (at the Contest Planner's request, 11:56Z; commit 9ac6e499).
- **Before:** the splash always said "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send {limit} messages an hour in the chat or Telegram."
- **After:**
  - With `Included()` returning 0, the Telegram line is hidden and the limit line reads "… an hour in the chat."
  - With 1 (from Story 12.7), both texts stay word for word.
  - All three texts come from the message catalog.
- **When:** it follows Story 5.12 on runner B, to merge before the demo goes public if it can (ETA about 18:00 to 18:30Z); otherwise before Epic 12 merges.

### Change 6: step 7 after the contest, and daily releases after 1.0.0 (the owner, logged at 14:00:56Z; commit 06deaecd)

**6.1 Step 7 leaves the contest plan.**
- **Before:**
  - PRD §7.1: "**7** (if time allows) | Could".
  - Graph: `lanes.A.order` ends "17, 22, 23, 28", and `lanes.pool.order` ends "25, 26, 27".
  - Policy milestone: "steps 6-7 merged (judging week; step 7 is Could)".
- **After:**
  - Epics 27 and 28 leave the lane and pool orders and the contest milestones.
  - Their stories (27.1, 27.2 and 28.1 to 28.3) stay in `epics.md` for after the contest.
  - FR-31, FR-43, FR-46 and FR-51 are delivered after the contest.
  - Their graph rows are kept but never dispatched in this run.

**6.2 Daily releases after 1.0.0.**
- **Before:**
  - The Epic List says "the release that completes a step bumps the minor version", and each step epic's "Ships in the release that completes this step …" line says the same.
  - PRD §7.3 says "From release 1 on, the author can cut a release on demand or daily."
  - The policy milestone reads "(each released on the owner's word, as the next minor version)".
- **After:**
  - After 1.0.0, a release goes out daily with whatever has merged.
  - A release that adds a feature bumps the minor version, and a fixes-only release bumps the patch (U-195, Q4).
  - Each release is still cut on the owner's word (REL-11).
  - A step epic or a personality epic ships in the first daily release after it merges.
  - `hold9-apply.py`'s edit 4 already writes the daily cadence into policy line 14 (the Contest Planner's note at 14:01:37Z).

### Change 7: the personality epics 39, 40 and 41 (U-195, approved with changes)

**7.1 PRD.**
- **Before:** FR-1 to FR-62 and NFR-1 to NFR-26, with no personality features.
  - NFR-24: "Every message OcuTalon writes to a user is in plain English."
  - NFR-26: "The product and its documentation are in English for this contest."
- **After:**
  - a new §4.15, "Personality: heartbeat, persona and memory", with FR-63 to FR-74;
  - NFR-27 (context blocks stay small) and NFR-28 (the heartbeat's cost; a skipped beat makes no model request);
  - a new delivery tag, [Personality];
  - NFR-24, NFR-26 and FR-7's safe list amended with markers, so that a persona may name another language for chat replies and reasons, and proposing a change to one's own persona is safe because it only raises an approval request.

**7.2 Architecture.**
- **Approved in one batch** (U-195: "AD-1, AD-7, AD-11, AD-18, AD-19 and AD-29 and the owner texts … are approved as one batch, each with a marker"):
  - AD-7: the persona as a data block, and the context-block form;
  - AD-18: the agent heartbeat's beat;
  - AD-19: per-person values through `SettingsOps`;
  - AD-11: a `setting` approval kind;
  - AD-1: the persona proposal accepted from a tool;
  - AD-29: the personality epics, step 7 and daily releases;
  - AD-33: ownership rows.
- **Approved by the Contest Planner:** AD-21 (learned and core memory, daily notes, precedents).
- **Not made now:** AD-31's amendment for learning at compaction. It is decided at Epic 41's re-open (Q10), and Stories 41.10 and 41.11 stay optional.
- **Kept as is:** AD-8. A beat's fallback still notifies, followed by a 4-hour back-off (Q8). AD-6, AD-10, AD-14, AD-20, AD-26 and AD-28 are also unchanged.

**7.3 The epics and the graph.**
- **The epics:**
  - Epic 39: the agent heartbeat, Stories 39.1 to 39.6.
  - Epic 40: the persona, Stories 40.1 to 40.7.
  - Epic 41, first part: daily notes and precedents, Stories 41.1 to 41.7.
  - Epic 41, second part: learned and core memory, Stories 41.8 to 41.14. It re-opens Epic 41 under SC-5 once Epic 19 has merged (Q1).
- **In the graph:**
  - All three are pool epics, and each story is built in its home lane's files.
  - None depends on another of the three.
  - Each carries `merge_gate: {branch: release/1.0.0-rc1}`.
  - The pool order puts 39, 40 and 41 right after 33 and 34 (Q2).

**7.4 The behaviour, with the owner's changes.**
- **Heartbeat** (the owner: "Approved, but on the heartbeat, I want to make sure that the model isn't being called every minute, It should only be called every 30 minutes and when a decision needs to be made."):
  - The one-minute tick never calls the model itself, and a beat calls it at most once per interval.
  - The interval defaults to 30 minutes and can't be set below 30.
  - A due beat skips without a model call when:
    - the checklist is empty;
    - it is outside active hours;
    - the 4-hour back-off after a fallback is running;
    - the daily cost cap is reached;
    - there is no model key;
    - the code-built snapshot is unchanged since the last beat whose outcome was Ignore.
  - "Run the heartbeat now" stays as an explicit request, at most every 2 minutes, inside the daily cap. Because it is explicit, active hours and an unchanged snapshot don't hold it back; the other skip rules do.
  - Tests pin that no model request is made on a tick that isn't a due beat, or on an unchanged snapshot.
  - On the online demo the heartbeat is off until the visitor turns it on, and the card offers a sample checklist (Q7).
- **Persona** (the owner: "Bend them, emoji too"):
  - Starship computer, Pirate and Kind friend may bend the "How you write" rules: greetings, exclamation marks and emoji are allowed.
  - Professional, the default, keeps them strictly, and so does Another language, in its language.
  - A custom persona, on local installs only, follows the person's own text.
  - Under every persona, facts, counts, outcomes, confidence, approvals and every catalog or reserved sentence stay exact.
  - A new criterion and test make sure the AD-28 guard and the text filter don't strip emoji from persona text.
  - Evaluation checks, for each fun preset, that outcomes and facts are unchanged and notice frames stay exact.
  - A tell-now notice's reason may carry the persona and the language (Q6).
  - Another language has a free-text language field of about 40 characters at most (letters, spaces, hyphens and parentheses; `{{` and `@{` refused). It is the one free-text field on the online demo, where visitors otherwise get presets only. Notices, cards and buttons stay English (the owner, 14:04Z).
- **Memory:**
  - Core memory is pins only (Q9).
  - "Forget" removes the row, its vector and keyword entries, its search hits, the core memory and later session starts, but doesn't rewrite the current conversation (Q11).
- **Idle windows** (the owner: "Yes, use idle windows"): the policy file's pair 7 is approved. Until v1.0.0 is tagged, a 1.0.0-scope epic that is eligible with no free runner takes the runner of the lowest-placed merge-gated epic at that epic's next story boundary. Pair 7 and the other `_bmad/custom/unattended.yaml` wording go in at the next hold through the hold-10 script, not through the planning patch.

**7.5 UX and the brief.**
- **`EXPERIENCE.md`:**
  - **Before:** "**A chatty persona:** no greetings in replies, no emoji, no enthusiasm. Quiet is the product." UX-DR118 lists "no exclamation marks, emoji, hype …, persona or greeting-led replies".
  - **After:** both are amended with markers. The 0.1.0 and 0.1.1 release terms gain read-as-1.0.0 markers.
- **`EXPERIENCE.md` and `DESIGN.md`:** gain the Heartbeat checklist card, the Persona card (with the language field) and the Memory card.
- **The product brief:** gains one dated addendum note on the broadened pitch the owner adopted, "a general personal assistant, built the IRIS way", and on the three personality features.

## 5. Implementation handoff

**Change scope: moderate.** The backlog and graph are reorganized, the release chain is simplified, and three epics are added after 1.0.0. The owner's decisions are already made, so the work goes to the people below.

| Who | Does what |
| --- | --- |
| **The orchestrator** | Applies the U-195 planning patch as one planning commit: PRD, spine, `epics.md`, graph, `EXPERIENCE.md`, `DESIGN.md`, the brief's addendum and this proposal, each change with its marker. The patch carries the re-recorded `epics_md_hash`; if `epics.md` changes on the feature branch first, the orchestrator re-records it. It dispatches by the graph: Story 5.12, then Story 16.11, on runner B ahead of the launch; Epic 30's re-dispatch integrates 5.12; Epic 11 merges on its buildable parts; and the pool runs in order, with 39, 40 and 41 after 33 and 34. It holds each merge-gated epic until `release/1.0.0-rc1` exists, checking at every notification and dispatch, and re-opens Epic 41 under SC-5 once Epic 19 merges. It has the policy pairs written for the Contest Planner as a guarded script (`hold10-apply.py`, to run after hold 9). |
| **Epic 11's and Epic 12's runners** | Epic 11's runner moves Story 11.6 and Story 11.3's real-host criteria into Epic 38 and adds Story 11.5's web-page criterion (done on its branch). Epic 12's runner removes Story 12.7's real-device criteria. The two edits meet at the merges. |
| **The Contest Planner** | At hold #9, runs `hold9-apply.py` (policy lines 14 and 15). At the next hold, runs the hold-10 script (the U-195 pairs, pair 7 included), with its sha guard and a dry run first. After Epic 11 merges, it starts Story 11.5's sequence, which cuts `release/1.0.0-rc1` and stops at the hands-on gate. It runs the release checks: Story 38.1's real-key pass, and Story 38.2's timed runs on one clean Linux droplet, driven from its Mac, which it creates for the check and deletes after it. It also runs the 1.0.0 step release check (Story 31.3's measurement), and decides the deferrals the passes find. It measures the invalid rate for U-191. |
| **The owner** | Runs Story 38.3, the Telegram pass on the same candidate, providing the bot token and the Telegram Web sign-in. Cuts the release: the v1.0.0 tag and the release pull request to `main`, on the owner's word (REL-11). Publishes the IPM package to the registry at 1.0.0. After 1.0.0, cuts each daily release. AD-31's amendment comes back at Epic 41's re-open. |

**Success criteria.**

- **No step or personality code in 1.0.0:** no step or personality epic merges into the feature branch before `release/1.0.0-rc1` exists.
- **The hotfixes:** Story 5.12 merges before the online demo goes public. Story 16.11 merges then too if it can, and otherwise before Epic 12 merges.
- **Epic 38:** its three checks are recorded in `release/records/1.0.0/rc<n>.md` against the candidate's version and commit SHA before v1.0.0 is tagged. Stories 38.1 and 38.2 drive step 2 through the guide's own Send.
- **The IPM package:** Story 15.3's local-repository install shows the branded sign-in page with no Node.js, and the release notes record the artifact's size.
- **The heartbeat:** its tests pin that no model request is made on a tick that isn't a due beat, or on an unchanged snapshot.
- **The persona:** evaluation shows unchanged outcomes and facts under each fun preset, and a test pins that emoji survive the AD-28 guard and the text filter.
- **The documents:** after the patch the spine lints at its baseline (8 low placeholder findings, no `ad_id` or `ad_fields` finding), the graph parses with every lane and pool epic present, and `epics_md_hash` matches `epics.md`.
