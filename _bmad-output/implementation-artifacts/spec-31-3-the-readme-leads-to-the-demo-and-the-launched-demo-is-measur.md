---
title: 'Story 31.3: the README leads to the demo (build 109, IPM, Telegram row, licence), the About and finish-state links, two security-overview lines, and the Telegram cases of Stories 16.4 and 16.9 turned on'
type: 'feature'
created: '2026-11-03'
status: 'blocked'
baseline_revision: 'a401f37be6f6221e3621d3522d6d46abf506109f'
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

**Approach:** Apply the ruled wording word for word: build 109 items 1-7, U-238's phrase, the LICENSE line, and the IPM order of `docs/install-ipm.md`. Pin each change in `docker/tests/test-readme.sh`. Add the three links through `web/src/app/links.ts`. Narrow L111 and L187 to what is actually shown, as ruled (pending, see `## Clarification Needed`). Replace each Telegram hold-off with a real case that runs through the CI mock bot. The online demo's own claims do not change.

## Boundaries & Constraints

**Always:**
- Insert ruled text exactly as given: build-109 items 1-7, U-238's phrase, the LICENSE holder line and README line, and the L111/L187 sentences once ruled.
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
- Screenshots: `docs/images/page-incident.png` (297,920 B) and `vt-decision.png` (196,280 B) are tracked.
  - Story 10.5 copied them byte for byte from the lead's vetted shots (spec-10-5 :21, :27, :197-200). No Playwright spec produced them.
  - `vt-decision.png` shows one `AgentStep` and the cut-off Operations lanes, not model requests and tool calls as separate steps.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure, read-only; a fresh throwaway `e31s3i`, never a slot write). For DW-360, confirm on a first-start stack:
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
  8. **Screenshots:** per the ruling on Clarification Q2. Default if ruled "reuse": no new PNG and no `.gitignore` change.
- `LICENSE` (new) -- the standard MIT License text, holder line `Copyright (c) 2026 jbrandtmse`, ASCII.
- `docs/bridge-guide.md:13` -- append ` Build 109, which the Early Access portal now offers in place of build 154, has not been tested with this guide yet.` to the bullet. Nothing else.
- `docs/install-ipm.md:7` -- append ` Build 109, which the Early Access portal now offers in place of build 154, has not been tested with the IPM install yet.` to the line. Nothing else.
- `docs/security-overview.md` -- replace L111 and L187 with the ruled sentences (Clarification Q1). No other line.
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
  - Images per Q2. If image lines are added to "What's interesting", `chk_interesting` counts words with image lines left out.
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
- Given the built page, when the About dialog opens, then its links are README, Bridge developer guide and Security overview, in that order, each opening in a new tab. When the guide reaches its finish state, then "Use the same bridge in your own production ↗" opens the bridge guide in a new tab, with the arrow hidden from screen readers.
- Given `docs/security-overview.md`, when diffed, then only L111 and L187 changed, to the ruled sentences, and the MCP block still opens with L179's sentence.
- Given the CI stacks with the mock bot, when `live:online-session` and `live:online-allowance` run, then L6, row 4 (Telegram part), A5 and AT pass with no SKIP or `notBuilt` left for 31.3 (`rg -n "'31\.3'|Story 31\.3 turns" web docker` finds none).
- Given every public file this story touches, when read, then none claims Telegram, pairing or phone approvals on the online demo, or paired-chat isolation under load (U-239). `docker/tests/test-readme.sh`, `bash ci/checks.sh` and CI on every workflow are green.

## Spec Change Log

## Review Triage Log

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
4. The DW-360 section text (Task 0 confirms each fact):
   - "IRIS also comes with predefined accounts, among them `SuperUser` and `_SYSTEM`, which hold every right, and `Admin`. Change their passwords in the Management Portal: open http://localhost:52773/csp/sys/UtilHome.csp and sign in as `SuperUser` (its first sign-in asks for a new password)."
   - "Then open System Administration, then Security, then Users. For `_SYSTEM`, `Admin` and any other enabled account you don't use, choose its name, enter a new password in Password and Confirm Password, and press Save."
   - "Leave `CSPSystem`, the web gateway's account, and the accounts marked for internal use as they are."
   - No default password is printed.
5. The About link labels "Bridge developer guide" and "Security overview", taken from EXPERIENCE.md :145. The links are `blob/HEAD` GitHub URLs (HEAD resolves to the default branch). The spine's README-link convention (row :1117) covers only README links, so these are new constants beside it.
6. The README's "What's interesting" prose stays as it is: 1.0.0 adds nothing to it beyond the screenshots. The "contest-task table" no longer exists (test-readme `top` forbids it), so there is nothing to update.
7. FR-58's "other providers": the README names Anthropic only (public-text bans other provider names). That is as built, so it is not a gap.
8. The edits to `web/e2e-online/**` are limited to the four AC-named Telegram cases (L6, A5, AT; T2 is in `docker/tests`), under the bindings' exception "except what 31.3's AC itself names".
9. In T1 to T4, the pairing is a fixture (`Test.Data.Fixture.Pairing`, as row 4 already uses); the message path is the real `TelegramIn`/`TelegramOut` through the mock. The mock calls follow `web/e2e/demo-path/telegram-approval.spec.ts` (Rule 2: that file is a Lane A spec with no exported helper, so a small local helper is the reason for the copy).

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
- **Proposed L111 (one sentence; recommended):** "It is fixed to exact targets and shows its dry run (a fix), or the tool and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call)."
  - Alternative keeping the server: "...or the tool, its MCP server when it has one, and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call)."
- **L187 checks:** the block still opens with L179's sentence ("This release can't connect to MCP servers. When a release adds MCP support, these rules apply:"; L178 is blank). The narrowing is accurate for an MCP call, where a server always exists.
  - **Proposed L187:** "Every call passes the gate, an approval request when needed (showing the tool, its server and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record), an audit entry (read-only calls included) and an agent step."
  - Both proposals stay consistent with 13.4's L100 sentence. Neither touches the audit claims.

**Public files touched (U-239 check: none claims Telegram on the online demo, or isolation under load):** `README.md`, `LICENSE`, `docs/bridge-guide.md`, `docs/install-ipm.md`, `docs/security-overview.md`, `web/src/app/about/about-dialog.ts`, `web/src/app/guide/guide-view.ts`, `web/src/app/guide/demo-guide.ts`, `web/src/app/links.ts`. The release notes and splash are untouched.

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
- Consumes: `README_URL`'s file `web/src/app/links.ts`; `TRACE_TEXTS` (`shared/trace-view.ts`); the CI mock bot (`ci/mock`); `Test.Data.Fixture.Pairing`.

**Extend, don't copy:**
- The About links extend the README link's markup.
- The finish link copies the install link's pattern at `demo-guide.ts:174-176`.
- `links.ts` extends `README_URL`.
- T1 to T4 extend L1-L5, row 4, A1 and AP respectively.

**Ledger inbox (Rule 17):**
- DW-360: addressed (task 6, `lan` pin).
- DW-613: addressed through Clarification Q2. Whatever the ruling, no duplicate file is added. Evidence: both files exist, are tracked and are under 300 KB, and Story 10.5 copied them from the lead's vetted shots, not from Playwright.
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
- the web `node --test` scripts run in the hosted `web` job.

**Size:** one story. The work is documentation plus pins, three links and four turned-on cases.

## Clarification Needed

**Q1 (intent gap, security overview L111; the bindings' HALT condition).** A true L111 needs more than the "what is shown" narrowing as ruled ("the tool, the server, and the inputs through the redactor, cut to 200 characters, with the full call kept in the approval record"). "The server" is shown only when the held call's source starts `mcp:` (`BridgeSink.cls:236-237,271-281`). For every other tool call there is no server: the source is a class name, and the text is "Run {tool}" (`Catalog/Core.cls:573`). OcuTalon's own agent makes no MCP call in this release (L179), and its built-in tools are all safe (L100). A server can appear only for a developer's own AI Hub MCP tool that the bridge's gate holds (`Gate.cls:12`).
- Recommended L111: "It is fixed to exact targets and shows its dry run (a fix), or the tool and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call)."
- Alternative: "...or the tool, its MCP server when it has one, and its inputs through the redactor, cut to 200 characters, with the full call kept in the approval record (a tool call)."
- L187 as proposed under Design Notes is unaffected: an MCP call always has a server.

**Q2 (intent gap, screenshots; AC 1's last "And" and DW-613).** The bindings say the AC's Playwright capture "is met by the existing captures of Story 10.5, if they were produced that way". They were not: Story 10.5 copied the lead's vetted shots byte for byte, with no capture spec (spec-10-5 :21, :27, :197-200). Also, `vt-decision.png` shows one `AgentStep`, with the Operations lanes cut off, not "the agent's model requests and tool calls as steps". And "What's interesting" holds no image today. The hero sits above "Try it", and `vt-decision.png` sits under the Chat bullet, which the `images` rule pins. Options:
- (A) A Playwright capture spec on a throwaway with the mocked model re-shoots both images into the same file names. Both are placed under What's interesting (the hero keeps the file, re-shot), and the alt texts are updated.
- (B) Keep both vetted files, reference them again under What's interesting (no new file), and amend the AC to accept them as captured (narrowing the AC: ask-first).
- (C) Keep `page-incident.png` (vetted), and reference it again under What's interesting. A Playwright capture re-shoots only `vt-decision.png`, from a decision with model requests and tool calls as separate AgentSteps, moves it there, and updates the `images` pin.
- Recommended: (C), with the AC noted for image (1).

## Verification

Use these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s3i` (fresh) and `e31s3iw` (warm).
- Pass `timeout: 600000` on every call. Make one test-runner call per message, and never re-submit a call.
- Run `ci/iris.sh build` before any browser unit.
- No real model key and no real bot, ever.

**Commands:**
- (loop) `bash docker/tests/test-readme.sh` -- expected: every rule PASS, `ipm` and `licence` included; no SKIP.
- (loop) `bash docker/tests/test-bridge-guide.sh` and `bash docker/tests/test-cpf.sh`, one per call -- expected: PASS (item-7 sentences tolerated, pins unchanged).
- (loop) `npm --prefix web test` and `npm --prefix web run lint`, one per call -- expected: pass (`guide-view`, `ux-strings` and `host-pages` included).
- (once) `bash ci/checks.sh` -- expected: every script passes (`boundaries`: ASCII, no local path).
- (once) `OCUTALON_RUN_TAG=e31s3i ci/iris.sh build` -- expected: the bundle is rebuilt with the links.
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

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and mutations** (the implement stage writes `mutation: <change> → <red test>`):
- Build 109: remove `### Start it with build 109` → `test-readme` `install`/`readme-links` red.
- U-238: drop the phrase → `telegram-facts` red.
- Telegram row: drop "your own install" from the row → `telegram-demo` red.
- IPM: swap the registry and folder order → `ipm` red.
- LICENSE: change the holder line → `licence` red.
- DW-360: drop the new heading → `lan` red.
- Links: drop the Security overview link → `frame.spec.ts` red. Point the bridge link at `README_URL` → `guide.spec.ts` red.
- T1 to T4: make `TelegramIn` drop updates for an online-demo session (a temporary guard) → L6, A5 and AT red. Leave C's chat id off the reminder notice → row 4 red.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: (Q1) security-overview L111's true sentence needs more than the ruled "what is shown" narrowing, because "the server" is shown only for an `mcp:`-sourced tool call (BridgeSink.cls:236-237,271-281), which OcuTalon's own agent never makes in this release (L179); proposed L111 and L187 are under ## Clarification Needed; (Q2) the AC's Playwright-captured screenshots are not met by Story 10.5's images (lead-delivered vetted shots, spec-10-5 :21,:27,:197-200), and vt-decision.png shows one AgentStep rather than the model requests and tool calls as steps; options A/B/C with recommendation C are under ## Clarification Needed. The rest of the spec is planned and ready once both are ruled.
