---
title: 'Story 31.3: the README leads to the demo (build 109, IPM, Telegram row, licence), the About and finish-state links, two security-overview lines, and the Telegram cases of Stories 16.4 and 16.9 turned on'
type: 'feature'
created: '2026-11-03'
status: 'done'
baseline_revision: '9849b256c32f182581b35b90bd394cffb80b96c8'
baseline_commit: '9849b256c32f182581b35b90bd394cffb80b96c8'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The README still shows only build 154, which the Early Access portal no longer offers. It also has no IPM section, no Telegram row in "How you talk to it", no project licence, and no steps for the default IRIS accounts' passwords (DW-360). The About dialog and the guide's finish state do not link the bridge guide or the security overview. Security-overview L111 says a tool call's request "shows the exact call", which this release does not do. The Telegram cases of Stories 16.4 and 16.9 are still switched off, although Epic 12 has merged.

**Approach:** Apply the ruled wording word for word: build 109 items 1-7, U-238's phrase, the LICENSE line, and the IPM order of `docs/install-ipm.md`. Pin each change in `docker/tests/test-readme.sh`. Add the three links through `web/src/app/links.ts`. Narrow L111 and L187 to what is actually shown, with the sentences ruled under veto U-242 (orchestrator, 2026-11-03; kept by the Contest Planner 2026-11-03T15:07:51Z#727). Reuse Story 10.5's vetted `docs/images/page-incident.png` as image 1 and re-shoot only `docs/images/vt-decision.png` with a Playwright spec (U-242, option C). Replace each Telegram hold-off with a real case that runs through the CI mock bot. The online demo's own claims do not change.

## Boundaries & Constraints

**Always:**
- Insert ruled text exactly as given: build-109 items 1-7, U-238's phrase, the LICENSE holder line and README line, and the L111/L187 sentences.
- **Ruled under veto U-242 (orchestrator, 2026-11-03; kept by the Contest Planner, 2026-11-03T15:07:51Z#727):**
  - `docs/security-overview.md` L111 becomes exactly: "It is fixed to exact targets and shows its dry run (a fix), or the tool, its MCP server when it has one, and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call)."
  - L187 becomes exactly: "Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry (read-only calls included) and an agent step."
  - Leave the MCP block's framing sentence (L179, "This release can't connect to MCP servers. When a release adds MCP support, these rules apply:") and every other line of that file untouched.
  - Screenshots (option C): keep Story 10.5's vetted `docs/images/page-incident.png` as image 1 (the page on the demo path, with the incident card, the dry run with counts and the approval request) and reference it again under "What's interesting". Re-shoot only `docs/images/vt-decision.png`, into the same file name, with a Playwright spec on a throwaway stack with the mocked model (the way `web/e2e/trace` opens real Visual Trace pages), and reference it under "What's interesting" too. No other new PNG; `.gitignore` unchanged (use `git add -f` for the re-shot file if needed). DW-613 closes with this story.
  - The re-shot `vt-decision.png` (the Planner's conditions, binding before the story commit): (1) it shows the WHOLE decision with its Operations lanes, and more than one agent step (the decision's model requests and tool calls as steps); (2) it shows no mock, test, CI or host names, no localhost or port, and nothing secret -- check the trace's own labels: if a session, host, production item or prompt text shows such a name, change the capture (crop, fixture naming) so it does not; (3) under 300 KB, no key, secret or password other than the README account's; (4) the README alt text, wherever `vt-decision.png` appears (Story 10.5's Chat bullet and this story's placement), describes the new image. The image is vetted by the Planner before the story commit (the lead handles that gate).
  - The in-stage public texts 1 to 6 under Design Notes are kept as proposed, ruled under U-242.
  - One story, despite the `oversized` and `multiple-goals` warnings.
- Keep every other build 154 fact: bridge-guide L322, install-ipm L96, security-overview L87, `release/notes.sh` L79, and install.sh's messages.
- README rules: plain English; no class name or error code outside "For admins and developers"; no "from your phone"; never 'IRIS Couch'.
- Keep the not-affiliated note and the credits word for word. Every link must resolve.
- A sentence that mentions Telegram outside `## Telegram` says "your own install".
- The README claims nothing that isn't merged.
- Author non-ASCII in source as escapes: write ↗ as `'↗'` through `TRACE_TEXTS.arrow`.
- Every Telegram case runs against the CI mock bot (`ci/mock`), never api.telegram.org.
- Every test added or changed creates and removes its own rows and pairings.

**Never:**
- Never edit security-overview L100 (Epic 13). Edit no line of `docs/security-overview.md` other than L111 and L187.
- Never edit `docs/bridge-guide.md` beyond the one appended sentence, and never edit `docker/tests/test-bridge-guide.sh`.
- Never edit Epic 12's Telegram steps 1-5, except U-238's phrase.
- Never change `install.sh`, `docker-compose.yml`, the Dockerfiles, CI image pins, `docker/merge.cpf`, `docker/after-start.sh`, `.gitignore`, or Lane A's files (`Watch/**`, `Fix/**`, `src/bridge/**`, `Test/Bridge/**`, `Test/Watch/**`, `Channel/Telegram/**`, `web/e2e/demo-path/telegram-*.spec.ts`).
- Never edit `web/e2e/support/*`, `web/e2e/support/floor.ts` or `web/e2e/banners/banners.spec.ts`.
- Under `web/e2e-online/**`, edit only the four Telegram cases this spec names.
- No claim of Telegram, pairing, phone approvals or paired-chat isolation on the online demo (U-228 (2), U-239).
- No Story 31.4 work, no new CI group or job, and no change to how the measurement after launch is done (it is a release check).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Build 109 path | A judge with build 109 opens Try it step 2 | The link reaches `### Start it with build 109`, whose block names `IRIS_IMAGE` in `.env`; `docker-compose.yml:10` reads it (`IRIS_IMAGE: ${IRIS_IMAGE:-...}`) | test-readme `install` and `readme-links` fail on a missing fact or anchor |
| Telegram row | "How you talk to it" table | One row: Telegram, chat and answer approval requests on your phone, "on your own install with your own bot token", linking `#telegram` | `telegram-demo` fails on a row without "your own install" |
| LICENSE | Repo root | MIT text with "Copyright (c) 2026 jbrandtmse"; the README line under "Credits and licences" | the `licence` rule fails on a missing file, a holder or a line |
| About links | About dialog | README, then "Bridge developer guide", then "Security overview", each opening in a new tab, before the credits | frame/words e2e and `ux-strings` |
| Finish link | Guide finish state | "Use the same bridge in your own production" + aria-hidden ↗ + visually hidden "(opens in a new tab)", after the install link | guide e2e |
| 16.4 L6 (T1) | Paired chat (fixture pairing), page closed, CSP sessions gone | A chat message through the mock gets OcuTalon's reply in that chat | the test fails; `finally` removes the rows and the pairing |
| 16.4 row 4 (T2) | C has a fixture pairing and is seen gone | C's reminder notice reaches C's chat (`sendMessage` in the mock's calls) | FAIL line instead of SKIP |
| 16.9 hourly (T3) | Paired chat at 50 messages in the hour | The 51st message through TelegramIn is refused: a Turn with channel telegram, and one allowance notice in the chat | the test fails |
| 16.9 both caps (T4) | Both caps hold; pending approval; paired chat | The chat's Approve button (a callback through the mock) answers it, and the run completes `done` | the test fails |
| Screenshot 2 (U-242 C) | The capture spec runs on a throwaway with the mocked model | `docs/images/vt-decision.png` is rewritten: one whole decision with its Operations lanes and several agent steps (model requests and tool calls), no mock/test/CI/host name, no localhost or port, nothing secret, under 300 KB; README alt texts describe it | test-readme `images` fails on a missing file, a missing link or a file over 300 KB |

</intent-contract>

## Code Map

- `README.md` (288 lines). Insertion points:
  - Try it steps 1-2 at :15-16.
  - "Get the image" first paragraph at :91.
  - `### Start it with the install script` at :101.
  - `### Start it by hand` at :121-131.
  - "The IRIS (non-Health) image" first paragraph at :135.
  - The "How you talk to it" table at :34-38.
  - The LAN warning at :174.
  - Telegram step 5 at :186.
  - Troubleshooting "No IRIS build 154" at :200.
  - `### Change the README account's password` at :249-263.
  - "Credits and licences" at :278-288.
  - Images: the hero `page-incident.png` at :7, and `vt-decision.png` under the Chat bullet at :59.
- `docker/tests/test-readme.sh` (1544 lines; a hosted CHECK_SCRIPTS script, `readme`). Each rule tests broken copies first, so every new pin needs its own broken copy.
  - Data: `TRY_FACTS` :396, `chk_try_it` :400-421 (exactly four steps), `INT_FACTS`/`chk_interesting` :423-440 (at most 120 words, alt text counted), `TALK_FACTS` :166, `chk_how_you_talk`, `INSTALL_FACTS` :548, `PUBLIC_FACTS` :746, `ALLOWED_HOSTS` :942.
  - Telegram rules: `chk_telegram_facts` :870-890 (step 5 needs 'In the Status section' and `LAYOUT_TEXTS.status`), `chk_telegram_demo` :892-907.
  - `RULES=` :1506.
- `web/src/app/links.ts`: only `README_URL`. Add `BRIDGE_GUIDE_URL` and `SECURITY_OVERVIEW_URL`. `web/scripts/host-pages.test.mjs:154` pins `README_URL` (unchanged).
- `web/src/app/about/about-dialog.ts`: README link :35-39 (external-link icon + visually hidden "(opens in a new tab)"); credits :41; note :42; `readme = README_URL` :94.
- `web/src/app/guide/demo-guide.ts:170-177`: the finish links. The install-link pattern is at :174-176. `FINISH_PARTS` is at :43.
- `web/src/app/guide/guide-view.ts:54-55`: `GUIDE_TEXTS` `conversationLink` and `installLink`.
- `web/src/app/shared/trace-view.ts:18,21`: `opensInNewTab` and `arrow` (`'↗'`).
- `web/src/app/shared/layout-view.ts:33`: `LAYOUT_TEXTS.status: 'Status'`, the button U-238 names.
- `docs/bridge-guide.md:13`: the "What you need" bullet.
  - `docker/tests/test-bridge-guide.sh:46` `PROSE_PHRASES` needs 'build 154' present and pins no exact bullet line, so appending a sentence keeps it green. Never edit the pin.
- `docs/install-ipm.md:7`: the build 154 requirement line. Registry install :12-185; folder install :186; the first command in USER :88-104.
  - `docker/tests/test-cpf.sh` :18-26, :467, :517 pins the doc's order and USER sentence, not L7's wording.
- `docs/security-overview.md`: L109 parent line, L111, L179 (the MCP block's opening sentence; L178 is blank), L187.
  - Only generated sections are checked (`test-security-overview.sh` header :5-6); prose is never regenerated.
- Telegram hold-offs (all `Included()`-independent; `Channel/Telegram/In.cls:692` is `Quit $Get(^OcuTalonTest("TelegramIncluded")) '= 0` since 8bead6ac):
  - `web/e2e-online/session/leave.spec.ts:351`: `notBuilt('L6: a paired Telegram chat keeps working while no CSP session is open', '31.3');`, plus header :47. Unit `live:online-session`, group `shards`.
  - `docker/tests/test-online-session.sh:336`: `echo "SKIP row 4: Telegram keeps working with no CSP session open (Story 31.3 turns this on)"`, plus header :20. The fixture pairing is at :185. Same unit.
  - Story 16.9 has no skip marker. Its Telegram case is the fixture `TestTelegramFixtureIsRefusedTheSameWay` (`Test/Core/Allowance.cls:138`), kept (spec-16-9 :76, :687).
    - The real cases go in `web/e2e-online/allowance/messages.spec.ts` (A1 at :71 is the model) and `daily-cap.spec.ts` (AP at :183-221). Unit `live:online-allowance`, group `install-upgrade`.
  - Real Lane A paths already on, no change: `WatchOps` = `Watch/Ops.cls`, stopped by `Core/SessionOps.cls` (:62, :278-300) and pinned by `sign-out.spec.ts` O2 :33-38 and `Test.Core.SessionOpsProduction`. `Approval.Answer` is real in AP (:206).
  - Mock: `ci/mock/mock.mjs:9-23` (`/_mock/telegram/{updates,replies,calls,reset}`), `ci/compose.ci.yml:21-22`. The pattern to follow is `web/e2e/demo-path/telegram-approval.spec.ts` (Lane A, read-only).
  - Out of scope: `web/e2e-online/demo-path/demo-path.spec.ts:370-372` are `notBuilt(..., '31.4')`.
- Tool-call request evidence (L111):
  - `Core/BridgeSink.cls:103` (`INPUTSMAX = 200`), :232-239 (`ToolNoticeOf`), :271-281 (`ServerOf`, "" unless `mcp:`), :288-298 (`InputsOf`: `Bridge.Redact.Text`, folded, cut).
  - `Msg/Catalog/Core.cls:572-585` (`toolCall.request` / `toolCall.requestOnServer`).
  - `Bridge/Data/ApprovalRequest.cls:30,33,78` (`ToolName`, `ToolArguments` MAXLEN "", `ToolSource`).
  - `src/bridge/.../Policy/Gate.cls:12,92,185-190` (an `mcp:` toolref is the source; otherwise `origin_class`).
  - `Bridge/Context.cls:141` and `Gate.cls:144` (the single-use grant: name, args hash, source). `Bridge/Replay.cls:65`.
  - Fix side: `Watch/IncidentManager.cls:917`, `Bridge/Approval.cls:221`, `Fix/Executor.cls:274,333`.
  - Workflow task: `Bridge/Approval.cls:585-586,622-633` (subject and actions only).
  - Card: `web/src/app/approvals/approval-request-card.ts:111`, `Channel/WebChat/Out.cls:12-14`, `Channel/Telegram/Out.cls:6-8,78`.
- Screenshots (U-242 option C):
  - Tracked, not gitignored: `docs/images/page-incident.png` (297,920 B), `vt-decision.png` (196,280 B), `incident-card.png` (265,772), `incident-resolved.png` (248,087), `page-demo-view-off.png` (206,381). All are under 300,000 B.
  - Story 10.5 copied the first two byte for byte from the lead's vetted shots (spec-10-5 :21, :27, :197-200). No Playwright spec produced them. So the AC's Playwright capture is met only by this story's re-shoot of `vt-decision.png`.
  - Today's `vt-decision.png` (2513x1055) is cropped on two sides. On the right, the Operations lanes stop after `Ens Alarm` and `DiagnosisAgent`; the third lane (`AgentSteps`, `Bridge/Process/Decide.cls:133` `STEPSITEM`) is cut. At the bottom it stops at row [11], with only one `AgentStep` ([8]) visible.
  - README: hero `page-incident.png` at :7. "What's interesting" at :20-24 (one paragraph, no image). `vt-decision.png` under the Chat bullet at :59 (alt "Visual Trace of the decision: ...").
- The capture's siblings (Rule 2):
  - `web/playwright.rehearsal.config.ts`: a config of its own that spreads the base config and has one project on a folder outside `e2e/`, so CI's units never see it. `web/package.json:16` `e2e:rehearsal`. `web/tsconfig.e2e.json` `include` lists `e2e-rehearsal/**/*.ts` and the config (`npm run lint` typechecks it).
  - `docker/tests/record-eval.sh`: the manual recording tool. "Not a CI unit and not a check", named outside `test-*`. Exit 2 on an unknown argument; `live_start` with its own label; an EXIT trap; writes only after every check passes.
  - `docker/tests/test-demo-path.sh`:
    - :43-56: a first-start stack (`live_start`, `live_web_port`, `live_first_start 900`).
    - :74-77: the Playwright call with `OCUTALON_URL="http://127.0.0.1:$web_port"`. The demo-path specs need only that variable: `support/iris.ts:29-45` finds the container by the web port.
  - `web/e2e/demo-path/01..05-*.spec.ts`: the journey up to an approved, resolved incident.
  - `06-trace.spec.ts:26-29`: reads the incident's diagnosis header (`/state` chat item `incident`, `payload.traceTargets.diagnosis.traceHeaderId`) and opens `${TRACE_PAGE}${header}`. The tab is already signed in with the README account (its header, :16).
  - `web/e2e/support/trace.ts`, import only:
    - `TRACE_PAGE` :15;
    - `signOutTrace` :45 (a trace page holds one of the stack's 8 licence connections until it is signed out);
    - `drawnMessages` :144 (the `embed[type="image/svg+xml"]` SVG document; message groups are `g` with an all-digit id).
  - `support/floor.ts`: `signInReadmeLoaded`, import only. `support/demo-path.ts:562-588`: `openTraceFromGuide`, which closes its tab, so it cannot be used to take the shot.
- Agent steps in the decision:
  - `Decide.cls:459-505` sends one `AgentStep` per step record of the runner's reply to `AgentSteps`, without waiting.
  - The mock's `ci/mock/scenarios/A/diagnosis.json` answers with a `read_failed_messages` tool use, then the final text. So the decision holds two model steps and one tool step, three `AgentStep` messages (inference, measured in Task 1).
- `docker/tests/test-readme.sh` images and interesting:
  - `chk_interesting` :429-440: `wc -w` over the whole section, at most 120 words, alt text counted.
  - `chk_images` :471-500: alt text, the target in `docs/images/` and listed by the tree, image paragraphs, three images in "What OcuTalon does", Chat ≥1 and Break the feed ≥2. No size check today.
  - `rule_images` :1088-1115: the self-tests name no image file; they use the README's first image link.
- `ci/changes.sh` classes a new `docker/tests/<helper>.sh` as unclassified, so a change to it runs every group (pinned: `test-ci-changes.sh:264`). `record-eval.sh` alone is declared (`ci/units.sh` `NOT_IRIS_INPUT_PATTERN`).

## Tasks & Acceptance

**Execution** (in this order; lane A runs one fresh throwaway at a time):
- Task 1 (FIRST: the image, so the Planner can vet it early). Re-shoot `docs/images/vt-decision.png` with a Playwright spec, on a throwaway with the mocked model.
  - Before you start: run `ci/iris.sh build` once, then install Chromium (Verification), and back up today's PNG to the stage scratch folder.
  - `web/e2e-capture/vt-decision.spec.ts` (new; header: what it captures and what it needs).
    - Sign in with `signInReadmeLoaded` and read the diagnosis header from `/state`, as `06-trace.spec.ts:26-29` does.
    - Open `${TRACE_PAGE}${header}` in a new page of the same signed-in context. If that page asks for a sign-in, use the guide's link flow instead (Open the trace, then the help's "Open Visual Trace"), copied locally from `openTraceFromGuide` without its `popup.close()`. The reason for the copy: `web/e2e/support/*` is import-only for this epic.
    - Wait for `drawnMessages` to list the header.
    - Then check, and fail with the reason (writing nothing) when a check does not hold:
      - (a) Whole decision: the drawn message count equals the session's `Ens.MessageHeader` rows (`irisScript`, `SessionId` = the header's session), so there is no second page.
      - (b) More than one agent step: at least 2 drawn messages labelled `AgentStep`.
      - (c) Every lane fits in the clip: every host column label of Services, Processes and Operations (the `AgentSteps` lane included) lies inside the shot.
      - (d) No forbidden name: the SVG document's whole text matches none of `/mock|test|\bci\b|localhost|127\.0\.0\.1|:5\d{4}\b|password|secret|api[_ ]?key|sk-ant/i`. If a session, host, production-item or prompt label matches, change the crop or the fixture naming, never the product. If the hit is an ordinary word that is not a name (for example `test` inside another word), narrow only that alternative to a whole word and record it in the spec.
    - Shoot the diagram element only: the SVG embed, sized to the SVG's full extent, `scale: 'css'` at device scale factor 1. That keeps out the portal header, the server or namespace line and the URL.
    - If the PNG is 300,000 B or more, shrink it in the page through a canvas, in 10 % width steps, to no less than 60 % of its width. Fail if it still does not fit.
    - Write the PNG to `OCUTALON_CAPTURE_OUT`. Fail when that variable is unset (fail, not skip).
    - In `finally`, call `signOutTrace(page.request)`.
  - `web/playwright.capture.config.ts` (new). Extend `playwright.rehearsal.config.ts`'s pattern: `{...base, projects: [...]}`. It has two projects, both Desktop Chrome:
    - `capture-setup`: `testDir: './e2e/demo-path'`, `testMatch: /0[1-5]-[^/]*\.spec\.ts$/`;
    - `capture`: `testDir: './e2e-capture'`, `dependencies: ['capture-setup']`.
    - Its header says why CI never sees it: the folder is outside `e2e/` and `e2e-online/`, and no unit names the config.
  - `web/package.json`: add `"e2e:capture": "playwright test --config=playwright.capture.config.ts"`. `web/tsconfig.e2e.json`: add `e2e-capture/**/*.ts` and `playwright.capture.config.ts` to `include`.
  - `docker/tests/record-screenshot.sh` (new; extends `record-eval.sh`'s pattern). The header says: "Not a CI unit and not a check". Its usage is `record-screenshot.sh vt-decision`; any other argument exits 2.
    - Start: `live_start r31v`, `live_web_port`, `live_first_start 900`, with the default deadline.
    - Run `OCUTALON_URL=http://127.0.0.1:$web_port OCUTALON_CAPTURE_OUT=$tmp/vt-decision.png npm --prefix web run e2e:capture`.
    - Then check that the file starts with the PNG signature and is under 300,000 B (`wc -c`).
    - Only then copy it over `docs/images/vt-decision.png`. Print `record-screenshot: docs/images/vt-decision.png written (<bytes> B)` and the spec's `CAPTURE agent-steps=<n> messages=<m> size=<w>x<h>` line. Exit 0 only when written.
    - The EXIT trap removes the project.
    - `ci/units.sh` is not changed. The path is unclassified, so a change to it runs every group, the safe direction.
  - Look at the written PNG (Read tool) against the four conditions of the intent block before you go on. If a condition cannot be met without a product change, or the decision holds fewer than 2 `AgentStep` messages, HALT with `## Clarification Needed`. Never change the mock, the scenario or the product for the shot.
- Task 2 (measure, read-only; a fresh throwaway `e31s3i`, never a slot write). For DW-360, confirm on a first-start stack:
  - which predefined accounts are enabled and hold `%All` or `%Manager`;
  - their change-password-on-next-login flag;
  - the portal's menu labels (System Administration > Security > Users), and the Password / Confirm Password / Save fields;
  - that the README account cannot open that page.

  Slot A (2026-11-03, read-only `iris_user_get`) shows these enabled: `SuperUser` (%All, change flag 1), `_SYSTEM` (%All), `Admin` (%Manager, change flag 1), `CSPSystem` (gateway), `_Ensemble` and `irisowner`. A fresh stack decides. If a fact in the proposed text below is false, HALT with `## Clarification Needed`.
- `README.md` -- apply, in this order:
  1. **Build 109, items 1-6, verbatim** (see Design Notes, "Ruled text"). Replace steps 1-2. Replace the "Get the image" first paragraph with the two paragraphs. Add the note under the install-script heading. Add `### Start it with build 109` with its code block, right after "Start it by hand". Append the plain-IRIS sentence to :135 and the troubleshooting sentence to :200.
  2. **U-238:** in step 5 (:186), insert ` (in a narrower window, open it with the Status button at the top of the page)` right after "In the Status section". Change nothing else in `## Telegram`.
  3. **Telegram row (U-234):** append to the :34-38 table: `| Telegram | Chat with OcuTalon and answer its approval requests on your phone, on your own install with your own bot token ([how to set up Telegram](#telegram)) | Your own install |`.
  4. **Try it:** after :11 add `The splash screen also shows a read-only Visual Trace account, for opening Visual Trace in the portal yourself; on the demo, the trace links on the page open Visual Trace without a second sign-in.`
  5. **IPM section:** add `### Install it with IPM` at the end of "Install it yourself", after "Check that it is ready". Text in Design Notes.
  6. **DW-360:** add `### Change the default IRIS accounts' passwords` right after the README-account how-to. Text in Design Notes. Also extend the LAN warning at :174 with `[How to change the default IRIS accounts' passwords](#change-the-default-iris-accounts-passwords).`
  7. **LICENSE line:** under "Credits and licences", after the not-affiliated note: `OcuTalon is under the MIT License: [LICENSE](LICENSE).`
  8. **Screenshots (U-242 option C):** under "What's interesting", after its paragraph, add two image lines, each a paragraph of its own (an empty line before and after it):
     - first, the hero's line again, with :7's alt text word for word and `docs/images/page-incident.png`;
     - then `![<text 10>](docs/images/vt-decision.png)`.
     - Replace the Chat bullet's alt text at :59 with the same text 10. Both alt texts for `vt-decision.png` must match the re-shot image.
     - No other PNG; `.gitignore` unchanged. The files are tracked, so no `git add -f` is needed.
- `LICENSE` (new) -- the standard MIT License text, holder line `Copyright (c) 2026 jbrandtmse`, ASCII.
- `docs/bridge-guide.md:13` -- append ` Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet.` to the bullet. Nothing else.
- `docs/install-ipm.md:7` -- append ` Build 109, which the Early Access portal now offers in place of build 154, has not been tested with the IPM install yet.` to the line. Nothing else.
- `docs/security-overview.md` -- change exactly two lines, keeping each line's `- ` bullet prefix:
  - L111: `- It is fixed to exact targets and shows its dry run (a fix), or the tool, its MCP server when it has one, and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call).`
  - L187: `- Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry (read-only calls included) and an agent step.`
  - No other line. L179's framing sentence and L100 stay as they are; `git diff --stat` shows 2 insertions and 2 deletions.
- `docker/tests/test-readme.sh` -- update the header and add pins, each with a broken copy that must flag:
  - `INSTALL_FACTS` gains `irishealth-community:2027.1.0AI.109.0`, `IRIS_IMAGE=`, `#start-it-with-build-109` and `Build 109's plain IRIS image has not been tested.`
  - `TRY_FACTS` gains `#start-it-with-build-109` and `read-only Visual Trace account`.
  - A check that `### Start it with build 109` sits between "Start it by hand" and "The IRIS (non-Health) image".
  - `TALK_FACTS` gains `| Telegram |`, `your own bot token` and `(#telegram)`.
  - `telegram-facts` gains U-238's exact phrase.
  - A new rule `ipm`: the IPM section exists; `zpm "enable -community"` comes before the first `zpm "install ocutalon"`; that command is said to run in USER; `docs/install-ipm.md` is linked; the folder install (`zpm "load`) comes after the registry install; and the section never says "any namespace".
  - `lan` gains the default-accounts heading and its link.
  - A new rule `licence`: `LICENSE` holds the MIT grant and warranty paragraphs and exactly `Copyright (c) 2026 jbrandtmse`, and the README holds the exact LICENSE line under "Credits and licences".
  - Add both new rules to `RULES`.
  - `chk_interesting` counts words with the image lines (`^!\[`) left out. It also requires at least two image lines in "What's interesting": one with the hero's target (the first image link of the README) and one with the Chat bullet's target. The rule names no file, as `rule_images` does.
    - Broken copies: drop either image line; prose over 120 words with the image lines left out still flags.
  - `chk_images` gains a size check: every linked `docs/images/` file must be under 300,000 B in the tree. It reads `wc -c` from a root it is passed, defaulting to the repository.
    - Broken copy: a temp root whose linked file is exactly 300,000 B (`head -c 300000 /dev/zero`) must flag.
- `web/src/app/links.ts` -- add `BRIDGE_GUIDE_URL = 'https://github.com/jbrandtmse/OcuTalon/blob/HEAD/docs/bridge-guide.md'` and `SECURITY_OVERVIEW_URL` (same form, `docs/security-overview.md`), each with a doc comment.
- `web/src/app/about/about-dialog.ts` -- after the README link, add "Bridge developer guide" and "Security overview" in the README link's pattern (icon + visually hidden "(opens in a new tab)"), each in its own `<p>`, before the credits (EXPERIENCE.md :145).
- `web/src/app/guide/guide-view.ts` + `demo-guide.ts` -- add `bridgeLink: 'Use the same bridge in your own production'` to `GUIDE_TEXTS`, and the link after the install link at :176 in the same pattern (`data-guide-focus="finishLink"`, aria-hidden `trace.arrow`, visually hidden `trace.opensInNewTab`). `[href]` is `BRIDGE_GUIDE_URL` (EXPERIENCE.md :614).
- Web tests (shared surfaces):
  - `web/scripts/guide-view.test.mjs:36`: the `GUIDE_TEXTS` deep-equal.
  - `web/scripts/ux-strings.test.mjs`: sources for the new strings.
  - `web/e2e/frame/frame.spec.ts:276-277`: About's link list becomes README, Bridge developer guide, Security overview, each with its href and `target=_blank`.
  - `web/e2e/floor/words.spec.ts:105`.
  - `web/e2e/floor/guide.spec.ts:567-576`: both finish links plus the bridge link and its href. At :875 the count becomes 2: the install link and the bridge link.
- `web/e2e-online/session/leave.spec.ts:351` (+ header :47) -- T1: replace `notBuilt` with a real `test('L6: ...')`.
  - Session A gets a fixture pairing for a mock chat id; its page closes and its CSP sessions are seen gone (the L-cases' helpers).
  - A text update from that chat posted to the mock gets OcuTalon's reply to that chat in `/_mock/telegram/replies` within 90 s.
  - `finally` resets the mock chat, unpairs, and removes the session's rows.
- `docker/tests/test-online-session.sh:336` (+ header :20) -- T2: replace the SKIP line with a check. After C is seen gone, C's fired reminder notice reaches C's fixture chat (a `sendMessage` to C's chat id in `/_mock/telegram/calls`, within the same deadline style). The result is a `pass`/`fail` line.
- `web/e2e-online/allowance/messages.spec.ts` -- T3: new case `A5: a paired chat's 51st message in the hour is refused, with one allowance notice in the chat`.
  - Setup: `seedAllowance` at 50, plus a fixture pairing.
  - Assert: the Turn has `State` refused and channel telegram; one allowance notice reaches the chat; a second refused message sends no second notice.
- `web/e2e-online/allowance/daily-cap.spec.ts` -- T4: new case `AT: an approval answered from the paired chat completes while both caps hold`, built on AP's setup (:183-206).
  - Press the approval's Approve button in the paired chat (a `callback_query` through the mock, as in `telegram-approval.spec.ts`). Expect `done` and the chat's message edited.
  - Leave D1 and AP unchanged.

**Acceptance Criteria:**
- Given the README, when a judge opens it, then "Try it in two minutes" leads with the demo link, the splash note and the read-only Visual Trace account sentence. Build 109 is offered in steps 1-2, and every build-109 item reads word for word as ruled.
- Given `docs/bridge-guide.md` and `docs/install-ipm.md`, when read, then each carries its item-7 sentence verbatim, and every other build 154 mention is unchanged (`git diff` shows exactly two added sentences in these files).
- Given the README's IPM section, when read, then the registry install comes first (the community-registry line, then `zpm "install ocutalon"` in USER, an Interoperability-enabled namespace), the folder install is second via `docs/install-ipm.md`, and it never says "any namespace" (AD-23 / U-231).
- Given the repository root, when listed, then `LICENSE` holds the MIT text with "Copyright (c) 2026 jbrandtmse", and the README carries the ruled LICENSE line (`test-readme.sh` pins both).
- Given the README, when a judge reads "What's interesting":
  - then it shows `docs/images/page-incident.png` (Story 10.5's vetted file, unchanged), then `docs/images/vt-decision.png`, each with plain-English alt text;
  - `vt-decision.png` is the file that `docker/tests/record-screenshot.sh vt-decision` wrote with the Playwright spec on a throwaway with the mocked model;
  - it shows one whole decision, with every Operations lane and at least two agent steps; it shows no mock, test, CI or host name, no localhost or port, and nothing secret; it is under 300,000 B;
  - every alt text for it describes it;
  - no docs/images file is added or duplicated (DW-613);
  - `test-readme.sh` `images` and `interesting` pin the links, the placement and the size.
- Given the built page, when the About dialog opens, then its links are README, Bridge developer guide and Security overview, in that order, each opening in a new tab. When the guide reaches its finish state, then "Use the same bridge in your own production ↗" opens the bridge guide in a new tab, with the arrow hidden from screen readers.
- Given `docs/security-overview.md`, when diffed, then only L111 and L187 changed, to the ruled sentences, and the MCP block still opens with L179's sentence.
- Given the CI stacks with the mock bot, when `live:online-session` and `live:online-allowance` run, then L6, row 4 (Telegram part), A5 and AT pass with no SKIP or `notBuilt` left for 31.3 (`rg -n "'31\.3'|Story 31\.3 turns" web docker` finds none).
- Given every public file this story touches, when read, then none claims Telegram, pairing or phone approvals on the online demo, or paired-chat isolation under load (U-239). `docker/tests/test-readme.sh`, `bash ci/checks.sh` and CI on every workflow are green.

### Review Findings

Code review (stage code-review, 2026-11-03, run tag e31s3cr; four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, no model override). 22 rows: high 0, medium 4, low 18; 0 decision-needed left, 9 patches applied, 0 deferred, 13 closed without a change (5 by-design or accepted, 8 rejected).

- [x] [Review][Patch] L6 accepted a refused Turn: the poll kept only the channel (`split(':')[1]`), so a refused message plus its allowance notice passed as "keeps working" (medium, fix-risk low: one assertion) [web/e2e-online/session/leave.spec.ts:373] -- it now expects `['done:telegram']`; `live online-session` green, and the refusal mutation below turns L6 red ("refused:telegram").
- [x] [Review][Patch] F6's focus-trap loop no longer wrapped: four Tabs and four Shift+Tabs over four stops never pass Close or the first link, so the old trap check went vacuous (medium, Rule 19 shared surface; fix-risk low) [web/e2e/frame/frame.spec.ts:294] -- five presses each way; `live sign-in --part 2/3` 76 passed.
- [x] [Review][Patch] The DW-360 steps miss the portal's own step: on an existing user's page the Password choice shows with "Leave as is" selected and both password fields hidden (`%CSP.UI.Portal.User` :109, :203, :369-378, :855-857), so "enter a new password in Password and Password (confirm)" cannot be followed as written (medium, fix-risk low: three words) [README.md:317] -- "select Enter new password, " inserted before it (Decided in-stage 26, veto-window text for the lead), pinned in `lan`.
- [x] [Review][Patch] AC 1's "every build-109 item word for word" was pinned only in fragments: items 1, 2 and 4 could be reworded with every rule green (medium, Rule 19; fix-risk low: data lines only) [docker/tests/test-readme.sh:430,621] -- steps 1-2 joined `TRY_FACTS`; the two "Get the image" paragraphs, item 4's two paragraphs and its `.env` line joined `INSTALL_FACTS`, each with its broken copy through `st_facts`.
- [x] [Review][Patch] Row 4 never checked that C's first chat id was put back (`set_chat ... > /dev/null`) (low, mechanical) [docker/tests/test-online-session.sh:391] -- a failed restore is now a FAIL line; `live online-session` green.
- [x] [Review][Patch] `interesting` did not pin the ruled order (hero, then the Chat bullet's image) (low, mechanical) [docker/tests/test-readme.sh:chk_interesting] -- order check plus the broken copy "the two image lines swapped".
- [x] [Review][Patch] `ipm` left the repositories warning (Decided in-stage 23) and the second run in OCUTALON unpinned (low, mechanical) [docker/tests/test-readme.sh:chk_ipm] -- both checked, each with a broken copy.
- [x] [Review][Patch] `lan` checked only the default-accounts heading, not its steps (low, mechanical) [docker/tests/test-readme.sh:chk_lan] -- the portal address, the menu path, the password step and the CSPSystem line are pinned (`ACCOUNTS_FACTS`, each with a broken copy).
- [x] [Review][Patch] `licence` skipped the MIT condition paragraph, the licence's only condition (low, mechanical) [docker/tests/test-readme.sh:chk_licence] -- checked, with the broken copy "no condition paragraph".
- [x] [Review][Resolved] AT asserts the Approve press's answer, not `done` directly nor an edit of the chat's message (low; Decided in-stage 19 and 25) -- accepted as by-design: the press text "Approved. Repairing and resending N orders." is shown only for the verdict `done` with a dry-run count (`Core/AnswersIn.cls:90-100`, `Channel/Telegram/In.cls:420-423`), so completion is pinned; the edit is sent only for an incident's request (`Watch/IncidentManager.cls:178,1187`) and stays pinned by demo-path T8. A real incident under both caps would duplicate T8. The lead may still rule otherwise.
- [x] [Review][Resolved] "Password (confirm)" departs from ruled text 4's "Confirm Password" -- by-design: TRUE (`%CSP.UI.Portal.User` :111 `label="Password (confirm)"`); Decided in-stage 14, a veto-window item for the lead.
- [x] [Review][Resolved] The IPM repositories sentence goes beyond ruled text 3 -- by-design: TRUE (`docs/install-ipm.md:22` "first deletes the repositories configured in %SYS", :28-31 `repo -delete-all`); Decided in-stage 23, a veto-window item for the lead.
- [x] [Review][Resolved] The `vt-decision.png` alt text describes only the first half of the re-shot image (rows [1]-[13]); rows [14]-[33] (the approval start, the Workflow task, the approval outcome, the fix run and the notices) go unmentioned (low) -- spec-bound (text 10: implement may only drop clauses); everything it says is shown. Relayed to the Planner's image vetting, with one cosmetic note: row [1]'s "[1]" index overlaps its own icon (Visual Trace's drawing). The image was not changed.
- [x] [Review][Resolved] The IPM section points to no model-key or sign-in steps for an IPM install (low) -- by-design: ruled text 3 (U-242); it links `docs/install-ipm.md`, which carries them.

Rejected:
- low: "How you talk to it"'s lead-in does not mention the Telegram row -- the table row says "on your own install"; a fix adds unruled public text.
- low: the spec's bookkeeping (status `done` vs `review`, "29 rules" vs QA's 30) -- the fix edits the spec under review (tracking prose, not behaviour).
- low: the Code Map names L179 for the MCP framing sentence, which is L178 -- the fix edits the spec; the edited lines are right.
- low: the capture's header count is not checked as numeric -- a non-numeric count fails the capture closed (manual tool).
- low: the Chat image target parse assumes the line ends with ")" -- it would fail loud, and no README line has a trailing space or title.
- low: the commit message's "finish state link the ... security overview" -- the About dialog links both and the finish state the bridge guide, as the spec rules; the message is history.
- low: the capture tool has no executed test host (shrink path, exit 2, refusals) -- `wontfix-accepted`, reopen_if a re-shoot's first capture is 300,000 B or more (the untested shrink path then runs); a manual tool (Decided in-stage 11).
- low: A5's fixed 6 s wait for "no second notice" -- a bounded negative check, after the second Turn is awaited (as the self-review found).

## Spec Change Log

- 2026-11-03 (lead, after code review): the vt-decision.png alt text, in both README places, now describes the whole re-shot image (the review found it covered rows 1-13 only): "... and each of the agent's model requests and tool calls shows as an agent step of its own; then come the dry run, the approval request held as a Workflow task and its answer, the fix run, and the notices to the web chat and the phone, each a production message." It goes to the Contest Planner's image vet with the image (U-242 condition 4).

- 2026-11-03 (lead, re-plan after the plan halt): the orchestrator ruled Q1 and Q2 under veto U-242 (kept by the Contest Planner, 2026-11-03T15:07:51Z#727): L111 alternative with the MCP server clause; L187 as proposed; screenshots option C with the Planner's image conditions; texts 1 to 6 kept; one story. Written into the intent block and `## Rulings`; epics.md AC 1's last "And" gained the U-242 marker (Rule 5 tier 1). Status reset to `draft` for a re-plan.

- 2026-11-03 (implement): Task 1 first. `docs/images/vt-decision.png` re-shot by `docker/tests/record-screenshot.sh vt-decision`; Tasks 2 and the rest follow; see Verification, "Implement results". Decided in-stage 14 to 22 are the implement stage's.

## Review Triage Log

### 2026-11-03 - Review pass
- verdicts: 31 findings - high 0, medium 1, low 30, false 0, maybe-false 0. Routes: 15 `patch` rows (8 root causes; the one medium is the IPM repository warning), 16 `reject`, no `defer`, no `bad_spec`, no `intent_gap`. The Intent Alignment Auditor reported no findings (descriptive; its table of divergences is carried in the rows below).
- findings:
  - Blind Hunter
    - `[low]` `reject` README says build 109 "runs unchanged" but the diff shows no build 109 run, and two docs say "has not been tested" -- the sentence is build-109 item 2, ruled word for word (U-241); items 7's two sentences are ruled too. Not editable here.
    - `[low]` `reject` the internal registry host `docker.iscinternal.com/...` in the build 109 section -- ruled word for word (item 4).
    - `[low]` `patch` a failed or partial `startTelegram` left TelegramIn/TelegramOut changed (callers skip `finishTelegram` when `saved` is empty) -- `startTelegram` now calls `finishTelegram` with the partial `saved` before it throws (`web/e2e-online/telegram.ts`).
    - `[low]` `patch` row 4: `chat_c_was` empty skips the restore and a legitimately empty `saved` skips the wait -- the unit now fails with a reason when Start gives nothing to put back or C's chat id cannot be read (`docker/tests/test-online-session.sh`).
    - `[low]` `patch` L6 passes on any non-empty reply -- L6 now also requires the text to be a Turn of the channel telegram in the session; `repliesOf` throws on a fixture reason.
    - `[low]` `reject` AT covers less than the task line (no edit, no run to `done`) -- Decided in-stage 19 and 25: the press text is shown only for verdict `done` (`AnswersIn.cls:90-100`); the edit is T8's. Reported to the lead as a ruling item.
    - `[low]` `reject` no MIT licence in `src/module.xml` or `web/package.json` -- the AC names LICENSE and the README line only; package metadata is outside the spec and the release (owner-only) path.
    - `[low]` `reject` default-accounts steps give no first-sign-in password, a hard-coded port, and omit `_Ensemble`/`irisowner` -- in-stage text 4, ruled "kept as proposed" under U-242 ("No default password is printed"); the README hard-codes localhost:52773 everywhere.
    - `[low]` `reject` the same screenshot twice and legibility at README width -- both placements are ruled (U-242 option C); the Planner vets the image.
    - `[low]` `patch` the capture spec settles on two equal reads -- it now reads until the drawn count equals the session's `Ens.MessageHeader` rows, for 15 s at most (`web/e2e-capture/vt-decision.spec.ts`; the capture ran again green).
  - Edge Case Hunter
    - `[low]` `reject` `echo ... >> .env` with no trailing newline or run twice -- item 4's block is ruled word for word.
    - `[medium]` `patch` the README's IPM section does not say that `zpm "enable -community"` removes the repositories already set up (`docs/install-ipm.md:22,28-31` says so) -- one sentence added, recorded as Decided in-stage 23.
    - `[low]` `reject` no SuperUser password and a fixed port in the default-accounts steps -- as above (ruled text 4).
    - `[low]` `reject` the portal address assumes port 52773 -- as above; the README's other addresses do the same.
    - `[low]` `patch` check (c) did not require the Services lane -- the three lane titles are required (`vt-decision.spec.ts`).
    - `[low]` `patch` same settle loop as the Blind Hunter's -- same fix.
    - `[low]` `reject` `record-screenshot.sh` default 540 s deadline against a 900 s first start -- the spec says "with the default deadline"; the run took well under it; a slower machine sets `OCUTALON_LIVE_DEADLINE` as `live` units do.
    - `[low]` `patch` L6's non-empty reply is not tied to the sent text -- as above (Turn check).
    - `[low]` `reject` A5's fixed 6 s wait before "no second notice" -- a negative check is bounded in time by nature; the Turn of the second message is awaited first.
    - `[low]` `patch` row 4's empty `chat_c_was` -- as above.
    - `[low]` `reject` claim: AT does not assert an edit or `done` -- as above (Decided in-stage 25).
    - `[low]` `patch` claim: check (c) requires only some lane titles -- as above (Services added).
    - `[low]` `patch` claim: L6 accepts any message to the chat -- as above.
  - Verification Gap Reviewer
    - `[low]` `patch` row 4 counts any sendMessage to C's chat -- it now counts only one that carries the reminder's text (`online session fire`); the unit passed.
    - `[low]` `patch` L6's precondition `toEqual([])` was vacuous when the fixture call failed, and the reply was not content-checked -- `repliesOf` throws on a reason; Turn check added (same patch as above).
    - `[low]` `patch` A5 has no mutation for its allowance assertions -- mutation line added: `Allowed` made to `Quit 1` turns A5 red (11 other cases green).
    - `[low]` `reject` AC 2 (item-7 sentences) and AC 7 (L111/L187 only) have no pinning test -- the spec states `git diff` evidence for both; `test-security-overview.sh` is generated sections only; a prose pin would be brittle and the ruled sentences are in the diff.
    - `[low]` `patch` new README pins have no mutation lines, and items 3 and 6 have no pin -- item 3's note joined `INSTALL_FACTS`, a new Troubleshooting check pins item 6 (with a broken copy in `st`), and the mutation lines are written (each went red, README restored).
    - `[low]` `reject` the About "Bridge developer guide" link has no mutation line -- F6 asserts the exact three-link list and hrefs; the Security overview mutation shows the list check is falsifiable.
    - `[low]` `reject` the capture tooling has no executed test host (shrink path, exit 2, non-PNG refusal) -- a manual tool by Decided in-stage 11; it fails closed on the `CAPTURE` line and ran twice green.
    - `[low]` `reject` self-containment notes (silent skip without `OCUTALON_URL`; `chat_c_was` restore) -- the script dies without a CAPTURE line; the restore case is patched above.

## Design Notes

**Ruled text (data; insert verbatim).**
- Item 1, Try it steps:
  - `1. Load the IRIS for Health AI Hub Early Access image into Docker: build 154, or build 109, which the download portal now offers ([where to get it](#get-the-image)).`
  - `2. Clone this repository and run `./install.sh` in its folder ([what it does](#start-it-with-the-install-script)). With build 109, follow [Start it with build 109](#start-it-with-build-109) instead.`
- Item 2, "Get the image", the first paragraph replaced by two:
  - "OcuTalon 1.0.0 is built and tested on IRIS for Health AI Hub Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`). The InterSystems Early Access Program portal now offers build 109 (`irishealth-community:2027.1.0AI.109.0`) in its place: https://evaluation.intersystems.com/Eval/early-access/AIHub"
  - "OcuTalon 1.0.0 also runs unchanged on build 109: its install, production and test checks and the demo guide pass on it. In this release, `./install.sh` looks only for build 154, so with build 109, start OcuTalon as [Start it with build 109](#start-it-with-build-109) shows."
  - "Choose the file ..." and "Then load it:" stay.
- Item 3, under "Start it with the install script", before its code block: "The install script needs build 154. With build 109, see [Start it with build 109](#start-it-with-build-109)."
- Item 4, the new section `### Start it with build 109`, after "Start it by hand" and before "The IRIS (non-Health) image":
  - Paragraph: "`docker load` printed the loaded image's name; for the IRIS for Health archive it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0`. Name it in `.env` as `IRIS_IMAGE`, so that OcuTalon builds from it, then start OcuTalon:"
  - Code block: `git clone https://github.com/jbrandtmse/OcuTalon.git` / `cd OcuTalon` / `cp .env.example .env` / `echo 'IRIS_IMAGE=<the name docker load printed>' >> .env` / `docker compose up -d`.
  - Paragraph: "Skip the `cp` step when `.env` already exists. Keep the `IRIS_IMAGE` line in `.env`, because every `docker compose up -d` reads it, an update included. Then [check that it is ready](#check-that-it-is-ready) and [sign in](#sign-in)."
- Item 5, appended to the first paragraph of "The IRIS (non-Health) image": "Build 109's plain IRIS image has not been tested."
- Item 6, appended to the troubleshooting entry "No IRIS build 154 image is loaded in Docker": "With build 109, follow [Start it with build 109](#start-it-with-build-109) instead of running `./install.sh`."
- Item 7, two sentences appended:
  - To the bridge-guide bullet: "Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet."
  - To install-ipm L7: "Build 109, which the Early Access portal now offers in place of build 154, has not been tested with the IPM install yet."
- U-238, inserted after "In the Status section": "(in a narrower window, open it with the Status button at the top of the page)".
- LICENSE line: "OcuTalon is under the MIT License: [LICENSE](LICENSE)."
- MIT holder line: "Copyright (c) 2026 jbrandtmse".

**Decided in-stage (veto-window text; the lead classifies each).**
1. The Try-it sentence, from the splash's own text (`Web/Public/Splash.cls:86`): "The splash screen also shows a read-only Visual Trace account, for opening Visual Trace in the portal yourself; on the demo, the trace links on the page open Visual Trace without a second sign-in."
   - Evidence: `demo-path.spec.ts:194` step 6 "opens Visual Trace ... signed in", and spec-16-1 :141.
   - It gives no user name or password; the README prints only the README account's.
2. The Telegram row's wording (task 3). The third column reads "Your own install", and the second column carries "your own install" for the `telegram-demo` rule.
3. The IPM section text:
   - "To install OcuTalon into an IRIS instance you already run (AI Hub build 154 with IPM 0.10.10), use the InterSystems Package Manager. In an IRIS terminal in %SYS, point IPM at the community package registry:" + `zpm "enable -community"`.
   - "Then open an IRIS terminal in USER, an Interoperability-enabled namespace, and run:" + `zpm "install ocutalon"`.
   - "This first run ends early by design: it creates the namespace OCUTALON and stops with a line that says what to do next. Switch to OCUTALON and run the same command:" + `zn "OCUTALON"` / `zpm "install ocutalon"`.
   - "This second run installs OcuTalon with demo mode off. [Install OcuTalon with IPM](docs/install-ipm.md) shows the output of both runs, and the install from the package folder, for developers."
   - AD-23's "Presenting the stop" is met by the link to the outputs.
4. The DW-360 section text (Task 2 confirms each fact):
   - "IRIS also comes with predefined accounts, among them `SuperUser` and `_SYSTEM`, which hold every right, and `Admin`. Change their passwords in the Management Portal: open http://localhost:52773/csp/sys/UtilHome.csp and sign in as `SuperUser` (its first sign-in asks for a new password)."
   - "Then open System Administration, then Security, then Users. For `_SYSTEM`, `Admin` and any other enabled account you don't use, choose its name, enter a new password in Password and Confirm Password, and press Save."
   - "Leave `CSPSystem`, the web gateway's account, and the accounts marked for internal use as they are."
   - No default password is printed.
5. The About link labels "Bridge developer guide" and "Security overview", taken from EXPERIENCE.md :145. The links are `blob/HEAD` GitHub URLs (HEAD resolves to the default branch). The spine's README-link convention (row :1117) covers only README links, so these are new constants beside it.
6. The README's "What's interesting" prose stays as it is: 1.0.0 adds nothing to it beyond the screenshots. The "contest-task table" no longer exists (test-readme `top` forbids it), so there is nothing to update.
7. FR-58's "other providers": the README names Anthropic only (public-text bans other provider names). That is as built, so it is not a gap.
8. The edits to `web/e2e-online/**` are limited to the four AC-named Telegram cases (L6, A5, AT; T2 is in `docker/tests`), under the bindings' exception "except what 31.3's AC itself names".
9. In T1 to T4, the pairing is a fixture (`Test.Data.Fixture.Pairing`, as row 4 already uses); the message path is the real `TelegramIn`/`TelegramOut` through the mock. The mock calls follow `web/e2e/demo-path/telegram-approval.spec.ts` (Rule 2: that file is a Lane A spec with no exported helper, so a small local helper is the reason for the copy).
10. The alt text for `vt-decision.png`, in both places (veto-window text; a draft that Task 1 checks against the shot): "Visual Trace of one whole decision: the incident manager hands the incident to the decision process, which calls the diagnosis agent; each of the agent's model requests and tool calls shows as an agent step of its own, and the dry run follows, each a production message."
    - Implement may only drop a clause the image does not show. Any other change is a Clarification.
    - Under "What's interesting", the `page-incident.png` line reuses the hero's vetted alt text word for word, so it adds no new public text.
11. Where the capture lives, and why it is not in CI:
    - It lives in `web/e2e-capture/vt-decision.spec.ts`, `web/playwright.capture.config.ts` and `docker/tests/record-screenshot.sh`, following the rehearsal config and `record-eval.sh`.
    - It is neither cheap nor hermetic: it needs a first-start stack plus demo steps 1-5 (about 3-5 min), and it writes a tracked file. So no CI unit, group or job runs it, and it adds no new test unit.
    - The README's checks stay in CI through `test-readme.sh`.
12. "Under 300 KB" is read as under 300,000 B, the stricter reading. Every image file passes it today.
13. "What's interesting" keeps its 120-word cap for prose, with image lines left out of the count. The ruling's two image lines would otherwise push it over the cap with their alt text alone.
14. (implement) DW-360 text, one word corrected from the measurement (veto-window text; the lead classifies): the portal's field is labelled "Password (confirm)" (`%CSP.UI.Portal.User`, line 111), not "Confirm Password". The README says "enter a new password in Password and Password (confirm), and press Save." Everything else in text 4 is as measured (Task 2 below). To restore the ruled wording, change that one phrase and nothing else.
15. (implement) A5 and AT use the paired chat's own numeric id (`CHAT_A`, 84017734151, an 11-digit fixture id): the fixture pairing's `zz<n>` chat id reaches the Bot API as `chat_id 0` (measured on a warm stack), so no message would reach the mock under it. T2 (the shell) gives C's fixture pairing the id 84017734152 after the Telegram fixture has started (its Start deletes the rows of such chats) and puts C's first id back after Finish.
16. (implement) The Telegram cases share one new helper module, `web/e2e-online/telegram.ts` (import only; no edit of `web/e2e-online/support.ts` or `web/e2e/support/*`). It wraps `OcuTalon.Test.Channel.TelegramPageFixture` as `web/e2e/demo-path/telegram-approval.spec.ts` does, and adds the paired-chat helpers (a fixture pairing with a numeric chat id, `Send`, `Press`, the replies and buttons, the approval notice). Rule 2: a third copy in each of three specs was the alternative.
17. (implement) The mock's calls are read through the fixture (`Replies`, `Buttons`, `PressAnswers`; in the shell `Test.Contract.Mock.Calls()`), not through `/_mock/telegram/replies` (a POST that queues replies): the calls list is `/_mock/telegram/calls`, and the throwaway publishes no mock port.
18. (implement) L6 ends the CSP sessions with the group sign-out and closes the page, then checks that the session's CSP session no longer exists (a 120 s timeout would add minutes to the unit). The chat's text then gets a reply, which is any non-empty message to the chat.
19. (implement) AT asserts the Approve press, not an edit of the chat's message: the edit is sent by `IncidentManager` for an incident's request (`ANSWEREDKIND`), and AP's fixture request has no incident (measured: the row is approved from telegram, the press is answered "Approved. Repairing and resending 4 orders.", the answered Notification never comes). The request notice (a Notification of kind approval through Notify) is what puts the buttons in the chat. The edit stays pinned by `telegram-approval.spec.ts` T8 on the demo-path stack. This differs from the task line "Expect `done` and the chat's message edited"; the lead decides whether AT should raise a real incident instead.
20. (implement) `frame.spec.ts` F7 presses Tab four times (README, bridge guide, security overview, then Close) where it pressed twice; the About dialog gained two links before Close.
21. (implement) `ux-strings.test.mjs` holds "Bridge developer guide" and "Security overview" as a ruled entry for this story (EXPERIENCE.md About item 5 names the links, but not these two labels); "Use the same bridge in your own production" is in EXPERIENCE.md :614 and sits with the UX strings.
22. (implement) Check (d) of the capture kept the ruled expression whole (`/mock|test|\bci\b|.../i`): no narrowing was needed, the SVG text had no hit. Check (c) is split: the lane titles Processes and Operations and the host `AgentSteps` must be drawn, and every lane title, host rectangle and host title must lie inside the diagram extent (`traceCanvas`'s width and height); the spec also checks that the shot is exactly that extent, and that nothing of the page lies over the diagram (the contents pane and its expanders are hidden, then `elementFromPoint` finds only the embed on an 11 x 11 grid; the first shot had the pane over the right-most column). The embed screenshot is one capture of the SVG embed sized to the extent (2040 x 1420), so the diagram is not cropped.

23. (review) The IPM section warns that `zpm "enable -community"` first removes the repositories already set up in %SYS (veto-window text; the lead classifies): "This command first removes the package repositories that are already set up in %SYS, so note any you use before you run it." Evidence: `docs/install-ipm.md:22` and :28-31 show `repo -delete-all` in its output. No other IPM wording changed.
24. (review) L6 now also pins that the chat's text became a Turn of the channel telegram in the session (`chatTurnsOf`, moved to `web/e2e-online/telegram.ts` and shared with A5); the fixture readers (`repliesOf`, `buttonsOf`, `pressAnswers`) throw the fixture's reason instead of returning an empty list; `startTelegram` puts back a partial start before it throws. Row 4's check counts only a sendMessage to C's chat that carries the reminder's text, and the unit fails when C's chat id cannot be read.
25. (review) AT keeps the Approve press's answer text as the pin for the run's completion: TelegramIn shows "Approved. Repairing and resending N orders." only when `AnswersIn.TelegramCode` got the verdict `done` (`Core/AnswersIn.cls:90-100`, `Channel/Telegram/In.cls:420-423`), which is the verdict AP reads from `Approval.Answer`. The edit of the chat's message stays with demo-path T8 (Decided in-stage 19); the lead rules whether AT should raise a real incident instead.

26. (code review) DW-360 text, three words added from the portal source (veto-window text; the lead classifies): on an existing user's page the Password choice shows with "Leave as is" selected and the two password fields hidden (`%CSP.UI.Portal.User` :109 `radioSet id="passwordChoice"` with "Enter new password,Leave as is", :855-857 value 1 when editing, :203 and :369-378 hiding Password and Password (confirm)). The README now says "choose its name, select Enter new password, enter a new password in Password and Password (confirm), and press Save." To restore the earlier wording, remove "select Enter new password, " and nothing else.

**Security-overview L111: clause-by-clause evidence.**
- (a) "fixed to exact targets": TRUE.
  - Fix: `IncidentManager.cls:917` stores `FixTargets`; `Approval.cls:221` refuses a fix without them; `Executor.cls:274,333` re-checks only `row.FixTargets`.
  - Tool call: `Context.cls:141` builds a single-use grant (name, args hash, source); `Gate.cls:144` denies any other call; `Replay.cls:65` runs `row.ToolName` with `row.ToolArguments`.
- (b) "shows its dry run (a fix)": TRUE for the request on the page (`approval-request-card.ts:111`). The Workflow task shows only its subject and Approve/Reject (`Approval.cls:585-586,631-632`).
- (c) "the exact call (a tool call)": FALSE as worded. What is shown:
  - the tool (`BridgeSink.cls:234`);
  - the inputs through `Bridge.Redact.Text`, on one line, cut to 200 characters with '…' (`:103`, `:288-298`);
  - a server **only when ToolSource starts `mcp:`** (`:236-237`, `:271-281`). Otherwise the source is `origin_class` (`Gate.cls:185-190`), and the text is "Run {tool}" (`Core.cls:573`).
  - The full call is kept in the approval record (`ApprovalRequest.cls:30,33,78`).
  - OcuTalon's own agent makes no MCP call in this release (L179), and every built-in tool is safe (L100). So a server appears only for a developer's own AI Hub MCP tool held by the bridge's gate (`Gate.cls:12`).
- (d) The parent line (one request, one Workflow task): TRUE (`Approval.cls:622-633`).
- **Ruled L111 (U-242; the first plan's alternative):** "It is fixed to exact targets and shows its dry run (a fix), or the tool, its MCP server when it has one, and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call)."
  - The first plan's other proposal (without the server clause) was not taken.
- **L187 checks:** the block still opens with L179's sentence ("This release can't connect to MCP servers. When a release adds MCP support, these rules apply:"; L178 is blank). The narrowing is accurate for an MCP call, where a server always exists.
  - **Ruled L187 (U-242, as proposed):** "Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry (read-only calls included) and an agent step."
  - Both ruled sentences stay consistent with 13.4's L100 sentence. Neither touches the audit claims.

**Public files touched (U-239 check: none claims Telegram on the online demo, or isolation under load):** `README.md`, `LICENSE`, `docs/bridge-guide.md`, `docs/install-ipm.md`, `docs/security-overview.md`, `web/src/app/about/about-dialog.ts`, `web/src/app/guide/guide-view.ts`, `web/src/app/guide/demo-guide.ts`, `web/src/app/links.ts`, `docs/images/vt-decision.png` (re-shot; the Planner vets it before the story commit). The release notes and splash are untouched.

**Architecture decisions:**
- AD-29: lanes; Telegram's files are Lane A's; Epic 31 keeps Lane B's.
- AD-23: one image recipe; `IRIS_IMAGE`; the IPM install is two commands, the first in USER.
- AD-24: the trace accounts.
- AD-13: one sign-in group, so trace links need no second sign-in.
- AD-11 and AD-10: the approval row is the truth; the gate's single-use grant (L111 evidence).
- AD-14: channels.
- AD-22: tests on throwaways, CI groups.
- Conventions row "README link" (spine :1117).
- No AC contradicts an AD's Rule.

**Integration ACs:** no service or shared component is introduced. The new `links.ts` constants are consumed in this story by `about-dialog.ts` and `demo-guide.ts`, and the frame, words and guide e2e tests observe them.
- Consumed-by: About dialog and guide finish state (this story).
- Consumes: `README_URL`'s file `web/src/app/links.ts`; `TRACE_TEXTS` (`shared/trace-view.ts`); the CI mock bot (`ci/mock`); `Test.Data.Fixture.Pairing`; for the capture, the real Visual Trace page (`TRACE_PAGE`, `drawnMessages`, `signOutTrace`), the demo-path steps 01-05 and the mock's `diagnosis` scenario, on a real throwaway.

**Extend, don't copy:**
- The About links extend the README link's markup.
- The finish link copies the install link's pattern at `demo-guide.ts:174-176`.
- `links.ts` extends `README_URL`.
- T1 to T4 extend L1-L5, row 4, A1 and AP respectively.
- The capture extends three siblings:
  - `web/playwright.capture.config.ts` extends `playwright.rehearsal.config.ts`'s pattern (base spread, own projects, a folder outside `e2e/`).
  - `docker/tests/record-screenshot.sh` extends `record-eval.sh` (the manual-tool shape) and `test-demo-path.sh` :43-77 (the first start and the `OCUTALON_URL` call).
  - `vt-decision.spec.ts` imports `support/trace.ts` and `support/floor.ts` and reads the header as `06-trace.spec.ts` does.
  - The one copy is the guide's link flow from `openTraceFromGuide`, and only if the direct open needs a sign-in. The reason: that helper closes the tab before a shot can be taken, and `web/e2e/support/*` is import-only.

**Ledger inbox (Rule 17):**
- DW-360: addressed (task 6, `lan` pin).
- DW-613: addressed; it closes with this story (U-242).
  - No docs/images file is added or duplicated.
  - `page-incident.png` is reused unchanged: the hero, and again under "What's interesting".
  - `vt-decision.png` is re-shot in place, under the same name, by the Task 1 capture, and stays linked under the Chat bullet and under "What's interesting".
  - Evidence for the binding's "confirm and record": Story 10.5 copied both files from the lead's vetted shots, not from Playwright (spec-10-5 :21, :27, :197-200). So the AC's Playwright capture is met by this re-shoot, as U-242 rules.
- Declined DW-416: the fix would change how the origin check (`Web/Api.cls:965-973`, `Web/Live.cls:72`) trusts a TLS-terminating proxy. That is a security-posture change (a veto item), and the setting lives on the demo host (owner-only). The host's mapping works today. Route it to the decision sheet or to Story 31.4 (the demo host's isolation).
- Declined DW-432: a flake in `web/e2e-online/allowance/daily-cap.spec.ts` D1 (:105-139), racing with `Core/StatusMonitor.cls:47-75`. It is not one of the AC-named cases, the test side is in a path this epic must not edit, and a server-side fix changes StatusMonitor's publish timing, outside this story. It keeps its flake status.
- Declined DW-549: the fix is in `web/e2e-online/resume.spec.ts:84`, a path this epic must not edit (not AC-named). Flake.
- Declined DW-599: `Test/Core/ThreadProduction.cls:162` went red once and passed unchanged on the rerun. The root cause is unknown, and nothing in this story touches the thread code. Flake.
- DW-453 (`Test/Web/GuideApi.cls:75`) is terminal (`wontfix-accepted`, Epic 12 review) and not in scope unless CI reopens it.

**New test units:** none. Every case joins an existing unit:
- `readme` is a hosted check;
- `live:online-session` is in group `shards`;
- `live:online-allowance` is in `install-upgrade`;
- `live:floor` is in `shards-3`;
- `live:sign-in` is in `browser`;
- the web `node --test` scripts run in the hosted `web` job;
- the capture (`record-screenshot.sh`, `web/e2e-capture/`) is a manual recording tool, not a test unit (Decided in-stage 11).

**Size:** one story. The work is documentation plus pins, three links, four turned-on cases and one re-shot image with its capture tool.

## Rulings (orchestrator, veto U-242, 2026-11-03; kept 2026-11-03T15:07:51Z#727)

- **Q1 (security-overview L111/L187):** the alternative L111 with "its MCP server when it has one" (a bridge-held MCP tool does show its server, `BridgeSink.cls:236-237,271-281`, so the sentence stays true for every call), and the proposed L187, both exactly as in the intent block. The framing sentence (L179) and the rest of the block stay untouched.
- **Q2 (screenshots):** option (C), as in the intent block, with the Planner's image conditions. AC 1's last "And" carries the marker "[AMENDED 2026-11-03, orchestrator unattended ruling, veto U-242: image 1 is Story 10.5's vetted docs/images/page-incident.png, reused per DW-613; image 2 is re-shot by this story's Playwright spec]" in epics.md (Rule 5 tier 1). DW-613 closes with this story.
- **In-stage public texts 1 to 6** (Design Notes, "Decided in-stage"): kept as proposed, ruled under U-242.
- **One story**, despite the warnings.

## Verification

Use these variables on every `ci/iris.sh`, `ci/warm.sh` and `docker/tests` live call (`record-screenshot.sh` included): `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s3i` (fresh) and `e31s3iw` (warm).
- Pass `timeout: 600000` on every call. Make one test-runner call per message, and never re-submit a call.
- Run `ci/iris.sh build` before any browser unit.
- No real model key and no real bot, ever.

**Commands:**
- Task 1, first, in this order:
  - (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh build` -- expected: the bundle is built from the current tree.
  - (once) `npx --prefix web playwright install chromium` -- expected: done.
  - (once) `OCUTALON_RUN_TAG=e31s3i bash docker/tests/record-screenshot.sh vt-decision`, with the lane variables -- expected:
    - `CAPTURE agent-steps=<n≥2> messages=<m> size=<w>x<h>`, then `record-screenshot: docs/images/vt-decision.png written (<bytes> B)`, with fewer than 300,000 bytes, and exit 0;
    - its EXIT trap removes the project;
    - about 3-5 min locally, with the default 540 s deadline.
  - (once) `wc -c < docs/images/vt-decision.png && file docs/images/vt-decision.png` -- expected: under 300000; PNG image data.
  - Then view the PNG (Read tool) against the four conditions.
- (loop) `bash docker/tests/test-readme.sh` -- expected: every rule PASS, `ipm` and `licence` included; no SKIP.
- (loop) `bash docker/tests/test-bridge-guide.sh` and `bash docker/tests/test-cpf.sh`, one per call -- expected: PASS (item-7 sentences tolerated, pins unchanged).
- (loop) `npm --prefix web test` and `npm --prefix web run lint`, one per call -- expected: pass (`guide-view`, `ux-strings` and `host-pages` included).
- (once) `bash ci/checks.sh` -- expected: every script passes (`boundaries`: ASCII, no local path).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh build`, again after the web edits -- expected: the bundle is rebuilt with the links.
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh live online-session` -- expected: passes, with L6 and row 4's Telegram line as PASS.
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh live online-allowance` -- expected: passes with A5 and AT (about 400 s in CI).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh live floor` -- expected: passes (`guide.spec.ts`, `words.spec.ts`).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh live sign-in --part 1/3`, then `--part 2/3`, then `--part 3/3`, one per call -- expected: pass (`frame.spec.ts`).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh live demo-path` -- expected: passes (UJ-1).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh live security-overview` -- expected: no DRIFT (prose edits only).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh teardown`.

**Shared surfaces:**
- About's link list: `frame.spec.ts:276-277` (count 1 → 3) and `words.spec.ts:105`.
- The finish links: `guide.spec.ts:567-576` and :875 (count 1 → 2).
- `GUIDE_TEXTS`: `guide-view.test.mjs:36`.
- The UX string sources: `ux-strings.test.mjs`.
- `links.ts` exports: `host-pages.test.mjs:154`.
- The README sections and table that `test-readme.sh` pins: `try-it`, `how-you-talk`, `install`, `images`, `interesting`, `lan`, `public-text` and `telegram-*`.
- The online-session row 4 output (SKIP → PASS).
- The mock's Telegram state: each case resets its own chat.
- `docs/images/vt-decision.png`: linked under the Chat bullet and under "What's interesting"; `test-readme` `images` (now with the size check) and `interesting` (image lines left out of the word count, plus the hero and Chat image lines).
- `web/tsconfig.e2e.json` `include` (`npm run lint` typechecks the capture spec and config). `web/package.json` scripts.
- The capture project's dependency `capture-setup` reuses demo-path 01-05 unchanged, on its own throwaway. No CI unit runs it, so no CI shared state changes.

Every test added or changed passes on a fresh environment, in either order.

### Implement results (2026-11-03, tags e31s3i fresh and e31s3iw warm)

**Task 1, the image.** `OCUTALON_RUN_TAG=e31s3i bash docker/tests/record-screenshot.sh vt-decision`: `CAPTURE agent-steps=3 messages=30 size=2040x1420`, `record-screenshot: docs/images/vt-decision.png written (231535 B)`, exit 0, project removed by the trap. `file`: PNG image data, 2040 x 1420, 8-bit/color RGB, non-interlaced. Copy: scratch `e31s3impl/vt-decision.png`; the original (196,280 B, 2513 x 1055, sha1 21e15f3a...) is backed up there as `vt-decision.orig.png`. The first run showed the portal's contents pane over the right-most column; the capture spec now hides the page's other elements and checks that nothing lies over the diagram, and the second run is the image.
Self-check against the four conditions: (1) the whole decision: 30 drawn messages = the 30 `Ens.MessageHeader` rows of the session, all three lanes (Services, Processes, Operations with `AgentSteps`) inside the shot, 3 AgentStep messages (rows [8] to [10]); (2) the SVG text matches none of `mock|test|\bci\b|localhost|127.0.0.1|:5xxxx|password|secret|api key|sk-ant`, and the Read of the PNG shows only product hosts (ApprovalStartIn, IncidentManager, Decide, ApprovalHold, Notify, Ens Alarm, DiagnosisAgent, AgentSteps, FixExecutor, OcuTalonApprovals, WebChatOut, SimPhoneOut), message classes and UTC times; no URL, port or portal header; (3) 231,535 B, under 300,000; (4) both README alt texts are the draft text 10, kept whole: the image shows the incident manager's request to Decide, Decide's request to DiagnosisAgent, the three AgentStep messages and the DryRun after them (it also shows the approval and the fix below).

**Task 2, DW-360 (read-only, fresh throwaway `e31s3i`, first start).** Enabled accounts: `SuperUser` (%All, change flag 1), `_SYSTEM` (%All, 1), `_Ensemble` (%All, 1), `Admin` (%Manager and the Ensemble and HealthShare roles, 1), `irisowner` (%All, 0), `CSPSystem` (no role, 0), `UnknownUser` (no role, 0), and the README account `ocutalon`. `SuperUser` with the default password gets the page "Password change" (its first sign-in asks for a new password). The README account gets 302 on `/csp/sys/UtilHome.csp` and 403 on the Users pages; `SuperUser` gets 200. Portal labels (irissys sources): the home page's "System Administration", the tile "Security", "Users"; the user page's fields "Password" and "Password (confirm)", the command "Save". One word of the proposed text was false ("Confirm Password"); see Decided in-stage 14. No default password is printed.

**Commands (once each, after the last edit unless noted).**
- `ci/iris.sh build` x3 (the last after the mutation runs) -- built; `npx --prefix web playwright install chromium` -- done.
- (loop) `bash docker/tests/test-readme.sh` -- all 29 rules pass, `ipm` and `licence` included, no SKIP; `test-bridge-guide.sh` and `test-cpf.sh` -- pass; `npm --prefix web test` -- 1302 pass; `npm --prefix web run lint` -- clean; `test-boundaries.sh` -- pass.
- `bash ci/checks.sh` -- all scripts passed (it takes about 12 minutes; the harness moved it to the background and it was polled).
- `live online-session` -- all checks passed, L6 (8 s) and row 4's Telegram line PASS; `live online-allowance` -- 12 passed, A5 and AT pass; `live floor` -- 107 passed; `live sign-in --part 1/3`, `2/3`, `3/3` -- pass (part 2 first failed F7's Tab count, fixed, then passed); `live demo-path` -- 8 of 8 steps, audit checks pass; `live security-overview` -- no DRIFT; `ci/iris.sh teardown` -- nothing left (tags e31s3i, e31s3iw).
- `rg -n "'31\.3'|Story 31\.3 turns" web docker` -- no hit.
- `git diff --stat docs/bridge-guide.md docs/install-ipm.md docs/security-overview.md`: 1 + 1, 1 + 1, 2 + 2.

**Mutations (each applied, observed red, reverted with the file's checksum identical; `git status --short` shows no stray change).**
- mutation: remove `### Start it with build 109` from the README -> test-readme `install` red ("no section"), `readme-links` red (the `#start-it-with-build-109` links reach no heading).
- mutation: drop U-238's phrase from step 5 -> test-readme `telegram-facts` red.
- mutation: drop "your own install" from the Telegram row -> test-readme `telegram-demo` red.
- mutation: swap the README's `zpm "enable -community"` and its first `zpm "install ocutalon"` -> test-readme `ipm` red.
- mutation: change the LICENSE holder -> test-readme `licence` red.
- mutation: drop the `### Change the default IRIS accounts' passwords` heading -> test-readme `lan` red (and `readme-links`).
- mutation: remove the Security overview link from `about-dialog.ts` -> `frame.spec.ts` F6 red (and F7), in `live sign-in --part 2/3`.
- mutation: point the bridge link at `README_URL` in `demo-guide.ts` -> `guide.spec.ts` M9 red, in `live floor`.
- mutation: overwrite `docs/images/vt-decision.png` with 300,000 zero bytes (copy kept in the scratch folder) -> test-readme `images` red ("300000 bytes, not under 300000"); restored, checksum identical.
- mutation: drop the "What's interesting" `vt-decision.png` line -> test-readme `interesting` red.
- mutation: add the literal `localhost` to the text that check (d) reads -> `vt-decision.spec.ts` fails on (d), `record-screenshot.sh` prints "nothing was written", exit 1, and the PNG is byte-identical to before.
- mutation: `TelegramIn.Other` and `TelegramIn.Press` made to `Quit` first (a guard that drops a paired chat's messages and presses) -> L6 red (`live online-session`), A5 and AT red (`live online-allowance`).
- mutation: `TelegramOut.Target` made to leave the chat id empty (C's chat id off the reminder notice) -> `live online-session` row 4 "C's chat got no sendMessage" FAIL. Both Telegram files restored byte-identical (checksums).
- mutation (review pass): `Channel/Telegram/In.cls` `Allowed` made to `Quit 1` (a telegram message is never refused) -> `live online-allowance` A5 red, the other 11 cases green; file restored byte-identical (checksum).
- mutation (review pass): drop "your own bot token" from the Telegram row -> test-readme `how-you-talk` red. Drop "read-only Visual Trace account" from Try it -> `try-it` red. Drop "Build 109's plain IRIS image has not been tested." -> `install` red. Drop item 3's note ("The install script needs build 154. ...") -> `install` red. Drop item 6's sentence from the Troubleshooting entry -> `install` red (new check). README restored byte-identical (checksum).

**Pinning tests and mutations** (the implement stage writes `mutation: <change> → <red test>`):
- Build 109: remove `### Start it with build 109` → `test-readme` `install`/`readme-links` red.
- U-238: drop the phrase → `telegram-facts` red.
- Telegram row: drop "your own install" from the row → `telegram-demo` red.
- IPM: swap the registry and folder order → `ipm` red.
- LICENSE: change the holder line → `licence` red.
- DW-360: drop the new heading → `lan` red.
- Links: drop the Security overview link → `frame.spec.ts` red. Point the bridge link at `README_URL` → `guide.spec.ts` red.
- Screenshots:
  - Copy `vt-decision.png` to the stage scratch folder, then overwrite it with 300,000 zero bytes → `images` red. Restore it from that copy and confirm with `git status --short` and `git diff --stat`.
  - Drop the "What's interesting" `vt-decision.png` line → `interesting` red.
- Capture spec: temporarily add the literal `localhost` to the text that the forbidden-name check (d) reads → the spec fails, and `record-screenshot.sh` writes nothing (the PNG is byte-identical to before). Revert.
- T1 to T4: make `TelegramIn` drop updates for an online-demo session (a temporary guard) → L6, A5 and AT red. Leave C's chat id off the reminder notice → row 4 red.

### QA results (2026-11-03, stage qa, run tag e31s3q; no live unit run)

The gap found: AC 2 (the two item-7 sentences) and AC 7 (only L111 and L187 of the security overview changed, to the ruled sentences, under the MCP framing sentence) had no pinning test (the review pass rejected a pin as brittle; the sentences are ruled public text, so a word-for-word pin is the right guard). Every other AC already has a pin and a mutation line above.
- (QA) `docker/tests/test-readme.sh` (changed, no new file): new rule `docs` (`rule_docs`, `chk_docs`, added to `RULES`; header updated). It pins the build 109 sentence at the end of the bridge guide's and the IPM page's build 154 bullets (substring on the bullet, so Story 13.4's union with the bullet stays green), the two ruled security-overview lines word for word (once each), no remaining "the exact call", and the MCP rules line under the framing sentence with no heading between. 12 broken copies, each of which must flag. `docker/tests/test-bridge-guide.sh` is unchanged and passes.
- mutation (QA): remove the build 109 sentence from `docs/bridge-guide.md` -> test-readme `docs` red.
- mutation (QA): remove the build 109 sentence from `docs/install-ipm.md` -> test-readme `docs` red.
- mutation (QA): put L111 back to "or the exact call (a tool call)" -> test-readme `docs` red.
- mutation (QA): drop "its server" from L187 -> test-readme `docs` red (and the framing check).
- mutation (QA): change the LICENSE holder -> test-readme `licence` red.
- mutation (QA): drop "on your own install" from the Telegram row -> test-readme `telegram-demo` red.
- All files restored byte-identical (shasum against the pre-run sums; `git status --short` shows only test-readme.sh from this stage); `docs/images/vt-decision.png` byte-identical; `test-readme.sh` all 30 rules pass, `test-bridge-guide.sh` and `test-boundaries.sh` pass.

### Code review results (2026-11-03, stage code-review, run tag e31s3cr, lane A)

- `bash docker/tests/test-readme.sh` -- all 30 rules pass with the new pins; `npm --prefix web run lint` -- clean; `test-boundaries.sh` -- pass.
- `live online-session` -- 13 passed, L6 (`done:telegram`) and every row 4 line PASS, the restore check silent; `live sign-in --part 2/3` -- 76 passed (`frame.spec.ts` F6 with five presses each way). Each stack removed by its run (`LOCK released`).
- mutation (code review): seed the L6 session's allowance at 50 just before the chat's message (a refused message gets a refusal notice, the case the old poll let through) -> `live online-session` L6 red ("refused:telegram", wanted "done:telegram"); the spec restored byte-identical (shasum).
- mutation (code review): drop "select Enter new password, " from the README -> test-readme `lan` red.
- mutation (code review): reword "also runs unchanged on build 109" -> `install` red; reword step 1's "which the download portal now offers" -> `try-it` red.
- mutation (code review): swap the two "What's interesting" image lines -> `interesting` red.
- mutation (code review): drop the IPM repositories warning -> `ipm` red.
- mutation (code review): drop the MIT condition paragraph from LICENSE -> `licence` red.
- README and LICENSE restored byte-identical after each (shasum); `docs/images/vt-decision.png` untouched.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The README leads to the demo and carries the build 109 path (items 1-6), the Telegram row, the IPM section, the default-accounts steps (DW-360), U-238's phrase and the LICENSE line; `LICENSE` is added; the two item-7 sentences and the two ruled security-overview lines (L111, L187) are in; the About dialog and the guide's finish state link the bridge guide and the security overview; `docs/images/vt-decision.png` is re-shot by a Playwright capture (`docker/tests/record-screenshot.sh vt-decision`); the Telegram cases L6, row 4, A5 and AT run through the CI mock bot.

**The re-shot image.** 2040x1420 px, 231,535 B, `docs/images/vt-decision.png` (copy in the scratch folder `e31s3impl/vt-decision.png`); 30 drawn messages = the session's 30 headers, three `AgentStep` messages, the Services, Processes and Operations lanes (`AgentSteps` included), no forbidden name. The review pass re-ran the capture (30 messages, 3 agent steps, 230,004 B) and the vetted file was kept byte for byte. Both README alt texts are draft text 10.

**Files changed.**
- `README.md`, `LICENSE`, `docs/bridge-guide.md`, `docs/install-ipm.md`, `docs/security-overview.md` (L111, L187), `docs/images/vt-decision.png`: the public text and image.
- `docker/tests/test-readme.sh`: the new pins and rules (`ipm`, `licence`), the size check, the Troubleshooting check.
- `web/src/app/links.ts`, `about/about-dialog.ts`, `guide/guide-view.ts`, `guide/demo-guide.ts`: the three links.
- `web/scripts/guide-view.test.mjs`, `ux-strings.test.mjs`, `web/e2e/floor/guide.spec.ts`, `floor/words.spec.ts`, `frame/frame.spec.ts`: the shared-surface tests.
- `web/e2e-online/telegram.ts` (new), `session/leave.spec.ts`, `allowance/messages.spec.ts`, `allowance/daily-cap.spec.ts`, `docker/tests/test-online-session.sh`: the Telegram cases.
- `web/e2e-capture/vt-decision.spec.ts`, `web/playwright.capture.config.ts`, `docker/tests/record-screenshot.sh`, `web/package.json`, `web/tsconfig.e2e.json`: the capture tool.

**Review.** 31 findings from three layers (the intent-alignment layer reported none): 15 patch rows, 16 rejected with their reasons in the triage log, none deferred. Patched: the IPM repository warning (Decided in-stage 23), the Telegram helper's partial-start cleanup and throwing readers, L6's Turn check, row 4's text match and chat-id guards, the capture's settle wait and the Services lane check, the item 3 and item 6 pins, and the A5 allowance mutation line. Patched counts by verdict: medium 1, low 14. Follow-up review recommended: false (one medium patched; every patch was run live afterwards).

**Verification.** After the last patch: `test-readme` all 29 rules, `npm --prefix web run lint` clean, `npm --prefix web test` 1302 passed, `ci/checks.sh` all scripts passed, `live online-session` passed (L6 and row 4's Telegram line PASS), `live online-allowance` 12 passed (A5, AT), the capture re-run green, and one A5 mutation red then restored. `live floor`, `live sign-in --part 1/3..3/3`, `live demo-path`, `live security-overview` and `ci/iris.sh build` ran once before the review pass (the Verification section's Implement results); the patches touch no file they read.

**Residual risks / for the lead.**
- AT deviates from the task line (no message edit; Decided in-stage 19 and 25): the lead rules whether AT should raise a real incident.
- DW-360 text says "Password (confirm)" (Decided in-stage 14) and the IPM warning (23) are veto-window public text.
- The Contest Planner vets the re-shot image before the story commit's push.
