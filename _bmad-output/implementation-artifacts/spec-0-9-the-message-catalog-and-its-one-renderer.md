---
title: 'Story 0.9: The message catalog and its one renderer'
type: 'feature'
created: '2026-10-19'
status: 'done'
baseline_revision: '3586ae5022a994fb7a4c88c05b5c751b15dbdcd9'
baseline_commit: 3586ae5022a994fb7a4c88c05b5c751b15dbdcd9
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 0.4 made `CatalogKey` and `Slots` part of `Item`, `ItemDecision`, `Notification` and `Outbound`, but nothing holds those keys or turns them into text.
- Without one catalog and one renderer, each `*Out` operation (and `TelegramIn`'s press answer) would write its own wording. Its times and plurals would drift from the UX (AD-32).
- The public package keeps its own copies of the sign-in texts, and no test compares them with anything (AD-3).
- DW-12: nobody has measured whether a production job converts times in the container's `TZ`.

**Approach:**
- **The catalog.** Two catalog classes, `OcuTalon.Msg.Catalog.Core` (Lane B) and `OcuTalon.Msg.Catalog.Watch` (Lane A after Epic 0). Each holds its keys in one JSON XData block: the fixed text, an optional web wording, and typed slots. Together they hold the 79 release-1 and 0.1.1 keys listed under Tasks.
- **The renderer.** `OcuTalon.Msg.Catalog.Render(key, slots, channel, *sc)` is the one renderer, fully implemented. It fills the slots and formats times through `OcuTalon.Data.Time`, adding "ET" on the online demo. It picks the item noun's form by `count`. It returns plain text for `web`, `phone`, `mailbox` and `telegram`.
- **Tests.** A test renders every key on every channel against exact expected texts. A second test compares the public package's copies with the catalog.
- **DW-12.** The live production unit starts with a compose-level `TZ` and checks that a production job sees and uses it.

## Boundaries & Constraints

**Always:**
- **Texts.** Copy texts exactly from EXPERIENCE.md, as the key tables below give them.
  - Write non-ASCII characters as JSON escapes in XData (`\u2026`, `\u00B7`), never as literal bytes (Rule 14; `test-boundaries.sh`).
  - Placeholders are `{camelCase}`, named after the UX's braces (`{item noun}` becomes `{itemNoun}`).
- **Slots.** `Slots` is JSON, as AD-32 fixes it: times as UTC ISO 8601, counts as integers, and the item noun as `itemNoun: {"one", "other"}`, whose form is picked by the `count` slot.
- **Times.** Render converts and formats times only through `OcuTalon.Data.Time` (AD-18, Conventions "Times").
- **Settings.** It reads the online-demo flag only through `OcuTalon.Data.Public.Settings.Get("onlineDemo")` (AD-19; the `public-global` rule of `test-class-rules.sh`).
- **Output.** Render returns the whole text or `""` with an error `%Status`, never a partial text. It is a pure function: it writes no global, no log line and no row.
- **Source text.** Comments state contracts (Rule 14). Every new or changed class compiles on slot A with no warning.
- **Runtime targets.**
  - Slot A (`ocutalon-slot-a`) is for loads and `%UnitTest` runs, one class per call. Name `server` and `namespace: OCUTALON` on every MCP call.
  - A production job and a compose-level `TZ` run only in throwaways through `ci/iris.sh`, one stack at a time.

**Never:**
- **Who renders.** No producer renders text. No public-package class (`OcuTalon.Web.Public`, `OcuTalon.Data.Public`) references the catalog; `Test.Web.Status` would fail. No `OcuTalon.Bridge` class references it either (AD-2, `bridge-refs`).
- **Scope.** None of the following is in this story:
  - an `*Out` operation, `TelegramIn` or a web page built;
  - `web/` changed;
  - a key from step 2 or later (the digest, the step 2 "no model key" wording, "Your IRIS system is healthy", "Can't answer");
  - the bot profile texts, which the author sets.
- **Invented text.** No text the UX does not fix. Where the UX lacks a form (see Owner-only), the key renders the UX's fixed text and records the gap in a `gap` field.
- **Escaping.** No Markdown or HTML escaping. Output is plain text, and consumers show it as text (Telegram with no `parse_mode`, Angular interpolation).
- **Forbidden actions.**
  - No new dependency, no new test area, no new live script, no change to `ci/units.sh`.
  - No edit of `.claude/`, `CLAUDE.md`, `irislib/` or `irissys/`.
  - Never read `.env`. No model request.
  - Never stop, remove or recreate a slot, `ocutalon-aihub-test`, `ocupilot*` or `iris-community-edition`.
- **Paths.** No local machine path in any tracked file.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–13: `OcuTalon.Test.Msg.Catalog` and `OcuTalon.Test.Data.Time`, on slot A and in shard `lane-b`.
- Row 14: `OcuTalon.Test.Web.PublicTexts`.
- Row 15: `ci/iris.sh live production`.
- Row 16: `OcuTalon.Test.Contract.Ac`.

Fixture context, unless a row says otherwise:
- the process zone is `America/New_York`, set with `$SYSTEM.Process.TimeZone` and restored after each test, as in `Test.Data.Time`;
- `now` is `2026-10-16T18:20:00Z` (Friday, 14:20 EDT);
- the online-demo flag is on.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Every key, message channels | Each of the 79 keys with its fixture slots (UJ-1 values where the UX gives them), channels `phone`, `mailbox`, `telegram` | The fixture's exact text, identical on the three channels. For example, `incident.withFix` gives "50 orders failed since 14:12 ET. The partner changed its date format. I can repair and resend all 50. Approve?" + blank line + "Dry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet." + blank line + "Details and trace: on your OcuTalon page." `sc` is OK | — |
| 2 | Web wording | The same, channel `web` | The entry's `web` text where it has one: `incident.withFix` and `incident.laterRequest` without " Approve?", and `answered.approved` and `answered.approvedBy` without the final period ("Approved from Telegram at 14:15 ET"). Every other key renders as on the message channels | — |
| 3 | Local install | Flag off | No " ET" ("since 14:12") | — |
| 4 | Times | The local date decides, against the local date of `now`: same day; 1 to 6 days before or after; 7 or more; another year | "14:12"; "Thursday at 14:12" (and "Monday at 10:00" ahead); "Oct 9 at 14:12"; "Dec 30, 2025 at 10:00". `2026-10-17T02:00:00Z` is 22:00 on the same local day, so "22:00". When a dated time follows "at " in the template, that "at" becomes "on": "it was due on Thursday at 10:00 ET", "first on Thursday at 14:12 ET" | — |
| 5 | Item noun | `count` 1, 0, 50 | "1 order failed since…", "0 orders…", "50 orders…". Results take the noun's form from `count` (the total): "48 of 50 orders went through." | — |
| 6 | String slots | `cause` "The partner changed its date format." with a line break inside; `reason` ending with a period; a value holding `{count}` | Trimmed, whitespace runs (line breaks included) become one space, control characters removed. One trailing period is dropped where the template continues with ".", so the result is "...date format. I can...", never "format.. I can". "Why now: {reason}" keeps the reason's own period. A value's braces stay literal, because substitution is a single pass | an empty string slot: row 10 |
| 7 | Failure groups | `groups` `[{itemName, count, errorSummary, firstAt}]` | One line per group, in order: "OrdersFromPartner: 50, 'The order date was not in the expected format', first at 14:12 ET" | empty array: row 10 |
| 8 | Enumerated slots | `channel` `web`/`phone`/`telegram`; `fallbackReason` each of the 12 values of `Msg.Enum` `FALLBACKREASON` | "the web chat", "the simulated phone", "Telegram". Each reason gives its text, and `invalid` and `unusable` both give `fallbackReason.generic`'s | `channel` `mailbox` (or any other value), or an unknown reason: row 10 |
| 9 | Cost | `cap` 5, 1.24, 0.042, 0.0006, 0.00004 | "$5.00", "$1.24", "$0.042", "$0.0006", "<$0.0001" (Formats › Cost) | negative or not a number: row 10 |
| 10 | Errors | An unknown key; channel `email`, `webhook`, `slack`, `system` or `""`; slots not a JSON object; a declared slot missing or an empty string; a time that is not `YYYY-MM-DDThh:mm:ssZ`; a count that is not an integer ≥ 0; `itemNoun` without string `one` and `other`; row 8's bad values; empty `groups` | Returns `""`. `sc` is an error in plain English naming the key and the slot or channel | never a partial text |
| 11 | Extra slots | A slot that the entry does not declare | Ignored, and the text renders | — |
| 12 | The handoff | A real `OcuTalon.Msg.Notification` (kind `incident`, `CatalogKey` `incident.withFix`, `Slots` the `%ToJSON()` of the UJ-1 slots), saved and reopened | `RenderAt(n.CatalogKey, n.Slots, "telegram", <fixture now>, 1)` gives row 1's text, the same as with the slots as a `%DynamicObject`. The row is deleted | — |
| 13 | Clock and flag | `Render`, not `RenderAt`, with `onlineDemo` set to 1 and then 0 through `Data.Public.Settings.Set` (saved and restored), and a time slot of `NowUtc()` | " ET" present, then absent. The text equals `RenderAt` for a `now` read just before or just after the call | — |
| 14 | AD-3 copies | Every own parameter of every class in `OcuTalon.Web.Public` and `OcuTalon.Data.Public`, from the class dictionary | The 8 compared parameters (with `&middot;` decoded to U+00B7) each equal their key's web rendering. The 3 labels the UX doesn't quote and the 18 non-text parameters are listed as such. Every parameter is in exactly one list | a changed text, a new unlisted parameter, or any other `&name;` entity: red |
| 15 | DW-12 | `test-production.sh`'s stack started with compose `TZ: America/New_York` | Every alive item job's `/proc/<job>/environ` holds `TZ=America/New_York`. The row-21 `WatchOps` fixture's `OnInit`, in the item's own production job, records `Zone()` = `America/New_York`, `ToLocal("2026-01-15T17:00:00Z")` = `2026-01-15T12:00:00` and `ToLocal("2026-07-15T16:00:00Z")` = `2026-07-15T12:00:00` | Not so: Task 0's HALT (Design Notes) |
| 16 | Signatures | The signature oracle | `Catalog.Render(key,slots,channel,*sc)` and `Catalog.Entry(key,*sc)` return `%String` and `%DynamicObject`; `Catalog.RenderAt(key,slots,channel,now,onlineDemo,*sc)` and `Data.Time.ForMessage(utc,now)` return `%String` | renamed or reordered: red |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line:
  - AD-3 L122–149 (the public package keeps its own copies, compared with the catalog, L135);
  - AD-12 L337 (the status conditions' closed catalog);
  - AD-14 L392 (`CatalogKey` and `Slots` on `Item`);
  - AD-18 L465–475 (`Data.Time` is the only converter; the instance zone is the container's `TZ`, L475);
  - AD-28 L749–757 (the reserved sentences are catalog entries that only `Checks.Render` picks);
  - AD-29 L770 (one catalog class per lane; Epic 0 creates every key; the renderer is Lane B's);
  - AD-32 L816–825;
  - Conventions L878 (Enumerations), L881 (Times), L884 (Text OcuTalon sends);
  - the cross-area row for `Catalog.Render`, L1044;
  - the event table L1062–1065 (`notification`, the chat's notice cards, from `WebChatOut`; `phone`; `mailbox`).
- **UX** (`_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`), by line:
  - page titles L79; the sign-in page L126–128; the full logo's alt text L316; signed out L340; sign-in errors L360;
  - Voice and Tone › Formats L176–191 (times L181, dates L182, cost L184, counts L187, channels L188, who answered L189, quotes L190);
  - Incidents and Approvals: answered statuses L659–671, Results L673–685;
  - Message Catalog L687–842: pairing L694–707, conversation L714–726, fallback reasons L728–740, notices L742–748, the incident notice L750–781, the fallback notice L783–795, the notice without a fix L797–812, the later request L814–826, banners L828–842.
  - Non-ASCII in these texts: U+2026 in "Reconnecting…" and U+00B7 in "Sign in · OcuTalon" (measured, plan stage).
- **Epics** (`_bmad-output/planning-artifacts/epics.md`): this story L1001–1017. UX-DR109 L418, UX-DR114 L423, UX-DR116 L425.
- **Consumers' ACs** (by `epics.md` line):
  - 1.6 L1244; 2.4 L1549 (the enum-to-reason map); 2.6 L1621–1622; 2.7 L1640–1656 (`WebChatOut` renders through `Render`); 2.10 L1742–1746;
  - 4.5 L2202; 5.4 L2402–2411; 5.6 L2483; 5.7 L2504; 6.3 L2599; 6.4 L2638–2658;
  - 7.2 L2721–2736; 7.4 L2785; 7.5 L2810–2823; 8.3 L2901; 8.5 L2945; 10.3 L3205; 12.6 L3618–3619; 12.7 L3635–3645.
- **Code:**
  - `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `NowUtc`, `ToLocal` (gives `YYYY-MM-DDThh:mm:ss` local, or `""`) and `Zone` (the process `TZ`, or `UTC`). This story adds `ForMessage`.
  - `src/ocutalon/cls/OcuTalon/Msg/Notification.cls` L14–18, `Outbound.cls` L17–21, `Item.cls` L32–36, `ItemDecision.cls` L33–36: `CatalogKey` (`MAXLEN = 128`) and `Slots` (`MAXLEN = ""`).
  - `src/ocutalon/cls/OcuTalon/Msg/Enum.cls`: `FALLBACKREASON` L15 (12 values) and `CHANNEL` L36.
  - `src/ocutalon/cls/OcuTalon/Msg/Command.cls` with the package `Msg/Command/`: the precedent for a class `OcuTalon.Msg.Catalog` beside the package `OcuTalon.Msg.Catalog.*`.
  - `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` L9 (`KEYS` includes `onlineDemo`) and `Get`/`Set` L16/L28. `Install/Step/Public.cls` writes the flag from `OCUTALON_ONLINE_DEMO`.
  - `src/ocutalon/cls/OcuTalon/Web/Public/Login.cls` L12–30: `TITLE` (`Sign in &middot; OcuTalon`), `HEADING`, `USERLABEL`, `PASSWORDLABEL`, `SHOWPASSWORD`, `SUBMIT`, `HELP`, `ERRORCREDENTIALS`, `ERRORNOROLE`, `LOGOALT`. `ApiBase.cls` L14: `MESSAGESIGNEDOUT`. `Web/Api.cls` L62 uses `Login.#ERRORNOROLE` for `no_role`.
  - The own parameters of the public classes: `ApiBase` CONTENTTYPE CHARSET MESSAGESIGNEDOUT; `Login` the ten above plus IMAGES LOGOLIGHT LOGODARK FAVICON ICONEYE ICONALERT; `Shell` U CONTENTTYPE ROLE; `SignInAssets` CSS SCRIPT; `Status` U CONTENTTYPE H; `Data.Public.Settings` KEYS READY.
  - `src/ocutalon/cls/OcuTalon/Bridge/Ext/Accessor.cls` `ClassFor(..., *sc) As %String`: the sibling for Render's trailing `*sc`.
- **Tests to extend:**
  - `src/ocutalon/cls/OcuTalon/Test/Contract.cls` L72 `Read(xdataName, class)`: the XData reader that the new catalog test inherits.
  - `Test/Contract/Ac.cls` L139–162 `TestCrossLaneSignatures` (floor `count >= 43`) and XData `Signatures` L288–336.
  - `Test/Data/Time.cls`: `$SYSTEM.Process.TimeZone` set and restored (`OnAfterOneTest`, `RestoreZone`).
  - `Test/Web/Status.cls` L9–30: the pattern for saving and restoring public settings.
  - `Test/Web/SignIn.cls` L9–24 `TestTexts`: the page's literals, kept as they are.
- **Shell:**
  - `docker/tests/test-production.sh`: `live_start t06` L35; row 14 `check_items_run` L79; the row-21 `WatchOps` fixture L200–232, the sibling for the probe.
  - `docker/tests/lib-live.sh`: `live_add_file` L147, `iris_script` L303, `check_session`, `item_jobs` L596. `docker/after-start.sh` L23 stamps with `date -u`, so a container `TZ` changes no stamp.
- **Recipe:** `ci/units.sh` L17–18. `Test.Msg` and `Test.Web` are already in `lane-b`, so nothing changes there. `ci/iris.sh` finds the classes of a shard by folder (L86–95). Rule 21's fresh-environment line in `_bmad/custom/skill-rules.md` says "27 classes: 9 in lane-a, 18 in lane-b".
- **Read-only evidence (plan stage, October 19):**
  - The base image `ocutalon-iris-base:2026.3.0AI.154.0` (arm64, `docker run --rm`): `TZ` is unset, `/etc/localtime` points to `Etc/UTC` (`/etc/timezone` is `Etc/UTC`), and `/usr/share/zoneinfo/America/New_York` exists.
  - No catalog class, stub or `Render` signature exists yet. `Test.Contract.Ac` pins none.
  - The ledger slice for this key is DW-12 alone.

## Tasks & Acceptance

- [x] [CI] iris (production): `test-production.sh`'s "another production" checks failed on run 39374739457, attempts 1 and 2: `ZzOther.Production`'s `StopProduction(30)` timed out because a stop right after the start raced `Ens.ScheduleHandler`'s update on `^Ens.Runtime` (DW-28). Fixed in code review: each stop first waits until the start's request has settled; the next push's run confirms. https://github.com/jbrandtmse/OcuTalon/actions/runs/39374739457

**Execution:**

**Task 0: measure first** (DW-12; record every value under Verification, and label anything not measured `(inference)`):
1. Write row 15's block in `docker/tests/test-production.sh` first (see below).
2. Run `ci/iris.sh build`, then `ci/iris.sh live production`, with tag `v09a`.
3. Record:
   - each item job's `TZ` from `/proc/<job>/environ` (and whether job ids are OS process ids);
   - the probe's `Zone()`, both `ToLocal` values and `GetEnviron("TZ")` from the item's own job;
   - the unit's other checks, which must stay green with the zone set.
4. **If a production job does not see or use the container's zone:** stop and HALT `blocked` with `intent gap` (Design Notes, DW-12). Build nothing else.

**Catalog and renderer (Lane B, `OcuTalon.Msg`):**
- `src/ocutalon/cls/OcuTalon/Data/Time.cls`: add `ClassMethod ForMessage(utc As %String, now As %String = "") As %String`, with row 4's forms (no " ET"). It converts both times through `ToLocal`, so the local date decides. English weekday and month names are class parameters, so the output does not depend on the locale. An unreadable `utc` gives `""`, and an empty `now` means `NowUtc()`. Update the class doc. Rule 2: extends the converter, so dates are formatted only here.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` (new): the one renderer. Its doc comment states the contract below.
  - `Parameter CLASSES = "OcuTalon.Msg.Catalog.Core,OcuTalon.Msg.Catalog.Watch"`.
  - `Parameter CHANNELS = "web,phone,mailbox,telegram"`.
  - The channel display names and the `FALLBACKREASON`-to-key map are parameters.
  - `ClassMethod Entry(key As %String, Output sc As %Status) As %DynamicObject`:
    - reads the `Entries` XData of each class in `CLASSES` through `%Dictionary.CompiledXData`, on every call, with no cache;
    - returns the key's entry plus `"class"`;
    - an unknown key gives `""` and an error.
  - `ClassMethod Render(key As %String, slots As %String, channel As %String, Output sc As %Status) As %String`. It calls `RenderAt` with `##class(OcuTalon.Data.Time).NowUtc()` and `##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")`.
  - `ClassMethod RenderAt(key As %String, slots As %String, channel As %String, now As %String, onlineDemo As %Boolean, Output sc As %Status) As %String`:
    - `slots` is JSON text or a `%DynamicObject`, and `""` means `{}`;
    - the channel must be in `CHANNELS`;
    - it uses the `web` text for `web` when the entry has one, else `text`;
    - it validates and fills each declared slot by its type (below), in one pass over the template;
    - each time gets `" ET"` when `onlineDemo` is 1, and the "at"-to-"on" rule of row 4 applies;
    - on any failure it returns `""` and an error in plain English (row 10).
  - Rule 2: it extends nothing. The XData read is a three-line copy of `Test.Contract.Read`, because product code must not depend on `OcuTalon.Test`.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` (new; Lane B): doc comment, then `XData Entries [ MimeType = application/json ]` holding the 57 Core keys below.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (new; Lane A after Epic 0): the same shape, with the 22 Watch keys below.

**Entry shape** (the JSON value of each key):

```json
"answered.approved": {
  "text": "Approved from {channel} at {time}.",
  "web": "Approved from {channel} at {time}",
  "slots": {"channel": "channel", "time": "time"},
  "source": "EXPERIENCE Incidents and Approvals / Approval request states / Approved",
  "gap": "optional: the form the UX does not fix"
}
```

- **Keys** match `^[a-z][A-Za-z]*\.[a-z][A-Za-z0-9]*$` and are at most 128 characters. Each prefix lives in one class.
- **Placeholders.** `text` and `web` use exactly the declared slots. `source` is ASCII prose. Line breaks are `\n`, and paragraphs are separated by `\n\n`.
- **Slot types:**
  - `time`: UTC ISO 8601, formatted through `ForMessage`;
  - `count`: an integer ≥ 0, as digits;
  - `noun`: `{"one","other"}`, its form picked by the entry's `count` slot, which every entry with a noun declares;
  - `text`: code-written;
  - `sentence`: model-written, a plain sentence with no time;
  - `channel`: `web`, `phone` or `telegram`, given as its display name;
  - `fallbackReason`: a `FALLBACKREASON` value, given as its reason text;
  - `groups`: an array of `{itemName, count, errorSummary, firstAt}`, one line each as "{itemName}: {count}, '{errorSummary}', first at {firstAt}";
  - `cost`: US dollars, by Formats › Cost.
  - `text` and `sentence` follow row 6, and an empty value is an error.

**Core keys (57; `Catalog.Core`, Lane B).** Slots are written `name:type` and are text unless typed.
- **Pairing** (UX-DR109), no slots:
  - `pairing.paired`: "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair)."
  - `pairing.badCode`: "That code didn't work. Open the OcuTalon page and scan the QR code there for a new one."
  - `pairing.start`: "This is OcuTalon, an assistant that runs inside InterSystems IRIS. To use it here, open your OcuTalon page and scan the QR code there; that pairs this chat with your session."
  - `pairing.notPaired`: "This chat isn't paired yet. Open your OcuTalon page and scan the QR code there."
  - `pairing.stopped`: "Unpaired. This chat won't get OcuTalon messages anymore. Scan the QR code on the OcuTalon page to pair again."
  - `pairing.unpairedFromPage`: "Unpaired from the OcuTalon page. Scan the QR code there to pair again."
  - `pairing.otherChatPaired`: "Another Telegram chat was paired with this OcuTalon session, so this chat is no longer paired."
- **Telegram presses** (UX-DR114). A late press uses `answered.alreadyApproved`, and a press on an expired request uses `answered.expired`.
  - `press.approved` (`count:count`, `itemNoun:noun`): "Approved. Repairing and resending {count} {itemNoun}."
  - `press.rejected`: "Rejected. Nothing was changed."
  - `press.notPairedChat`: "Only the paired chat can answer this request."
  - `press.unavailable`: "That request is no longer available."
  - `press.rejectedFollowUp`: "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page."
- **Answered statuses** (`channel:channel`, `time:time`, and `user` for the `By` forms). The `web` text of `approved` and `approvedBy` has no final period.
  - `answered.approved`: "Approved from {channel} at {time}."
  - `answered.approvedBy`: "Approved by {user} from {channel} at {time}."
  - `answered.rejected`: "Rejected from {channel} at {time}. Nothing was changed."
  - `answered.rejectedBy`: "Rejected by {user} from {channel} at {time}. Nothing was changed."
  - `answered.expired` (`time` only): "Expired at {time}. Nothing was changed."
  - `answered.alreadyApproved` (gap): "Already answered: approved from {channel} at {time}."
- **Conversation:**
  - `conversation.turnFallback` (`fallbackReason:fallbackReason`): "I couldn't answer that: {fallbackReason}. Nothing was changed."
  - `conversation.dailyCap` (`time:time`, `readmeLink`): "The online demo has used today's model allowance. Decisions use fixed rules until {time}. You can install OcuTalon yourself to keep going: {readmeLink}"
  - `conversation.sessionAllowance` (`limit:count`, `time:time`, `readmeLink`): "You've used this session's {limit} messages for the hour. You can send more at {time}, or install OcuTalon yourself to keep going: {readmeLink}"
- **Fallback reasons** (11, no slots):
  - `fallbackReason.timeout` "the model didn't answer within 60 seconds"
  - `.empty` "the model's reply was empty"
  - `.cutOff` "the model's reply was cut off"
  - `.refusal` "the model declined to answer"
  - `.error` "the model returned an error"
  - `.rateLimited` "the model was busy and retries ran out"
  - `.budget` "this would have gone over the token budget"
  - `.tooLarge` "this request would have been too large to send"
  - `.dailyCap` "today's cost limit has been reached"
  - `.noKey` "no model key is set"
  - `.generic` "the model's reply couldn't be used"
  
  The enum map: `no_key` to noKey, `daily_cap` to dailyCap, `too_large` to tooLarge, `rate_limited` to rateLimited, `cut_off` to cutOff, `invalid` and `unusable` to generic; each other value maps to its own name.
- **Notices:**
  - `notice.tellNow` (`whatHappened`, `reason:sentence`): "{whatHappened}\nWhy now: {reason}"
  - `reminder.due` (`text:sentence`): "Reminder: {text}."
  - `reminder.late` (`time:time`, `text:sentence`): "Reminder (late; it was due at {time}): {text}."
- **Banners:**
  - `banner.allowance` (`limit:count`, `time:time`): "You've used this session's {limit} messages for the hour (messages you send in the chat or Telegram). You can send more at {time}."
  - `banner.dailyCap` (`time:time`): "The online demo has used today's model allowance. Decisions use fixed rules until {time}."
  - `banner.unreachable`: "Can't reach OcuTalon. Retrying every 10 seconds."
  - `banner.noModelKey`: "OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon."
  - `banner.costCap` (`cap:cost`, `time:time`): "OcuTalon has reached today's cost limit of {cap}. Decisions use fixed rules until {time}."
  - `banner.heartbeatStalled` (`time:time`): "Background checks have paused: the heartbeat last ran at {time}. Watches and reminders may be late until it recovers."
  - `banner.telegramPaused` (`time:time`): "Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at {time}. Each OcuTalon needs its own bot."
  - `banner.resetSoon`: "The demo resets in 5 minutes. Your session and Telegram pairing will be cleared."
  - `banner.reconnecting`: "Reconnecting\u2026 New messages may be delayed."
- **Banner actions:** `bannerAction.installYourself` "Install it yourself", `bannerAction.howToSetKey` "How to set a key", `bannerAction.budgets` "Budgets", `bannerAction.setUpBot` "Set up a bot".
- **Sign-in:**
  - `signIn.title` "Sign in \u00B7 OcuTalon"
  - `signIn.heading` "Sign in to OcuTalon"
  - `signIn.submit` "Sign in"
  - `signIn.help` "Use the IRIS account your install created; the README lists it."
  - `signIn.errorCredentials` "That user name and password didn't work."
  - `signIn.errorNoRole` "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it."
  - `signIn.logoAlt` "OcuTalon"
  - `signIn.signedOut` "You were signed out. Sign in again to continue."
- **Audit:** `audit.recorded` "Recorded in the IRIS audit log."

**Watch keys (22; `Catalog.Watch`, Lane A after Epic 0):**
- **Watch:**
  - `watch.productionStopped` (`production`, `time:time`): "The {production} production stopped at {time}.\nWhy now: you asked me to watch the {production} production."
  - `watch.itemDisabled` (`itemName`, `production`, `time:time`): "The {itemName} in the {production} production was disabled at {time}.\nWhy now: you asked me to watch the {production} production."
  - `watch.unknownProduction` (`name`, `list`): "I can't find a production called '{name}'. I can see: {list}. Which one did you mean?"
  - `watch.onlyOrders` (`readmeLink`): "On the online demo I can only watch the Orders production. Install OcuTalon to watch your own productions: {readmeLink}"
- **Agent:** `agent.noCommands`: "I can't run commands. I can check productions, read failed messages and propose fixes that wait for your approval."
- **Checks** (AD-28; `whatFailed` is text):
  - `checks.notEverything`: "Not everything: {whatFailed}."
  - `checks.notEverythingRestPassed`: "Not everything: {whatFailed}. Everything else I checked passed."
  - `checks.everythingElsePassed`: "Everything else I checked passed."
  - `checks.allPassed`: "Everything I checked passed."
  - `checks.nothingWatched`: "I'm not watching any productions yet, so I can't say. Ask me to watch one."
- **Incidents** (`count:count`, `itemNoun:noun`, `time:time`, plus the slots each lists). The dry-run paragraph D is "Dry run: {count} {itemNoun} affected. Example: {field} {before} becomes {after}. I'll resend {resendCount} repaired copies; the originals stay unchanged. Nothing has changed yet." The closing line L is "Details and trace: on your OcuTalon page."
  - `incident.withFix` (`cause:sentence`, `fixSummary:sentence`, `field`, `before`, `after`, `resendCount:count`; gap): "{count} {itemNoun} failed since {time}. {cause}. I can {fixSummary}. Approve?\n\n" + D + "\n\n" + L. Its `web` text drops " Approve?".
  - `incident.laterRequest` (the same slots; gap): "{count} more {itemNoun} failed since {time}, with the same cause. I can {fixSummary}. Approve?\n\n" + D + "\n\n" + L. Its `web` text drops " Approve?".
  - `incident.fallback` (`fallbackReason:fallbackReason`, `groups:groups`): "{count} {itemNoun} failed since {time}. I couldn't work out the cause ({fallbackReason}), so I'm not proposing a fix. Nothing was changed.\n\nFailures:\n{groups}\n\n" + L.
  - `incident.noFix` (`cause:sentence`, `groups:groups`): "{count} {itemNoun} failed since {time}. {cause}. None of my fixes applies to this, so I'm not proposing one. Nothing was changed.\n\nFailures:\n{groups}\n\n" + L.
  - `incident.noFixUnknown` (`groups:groups`): "{count} {itemNoun} failed since {time}. I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.\n\nFailures:\n{groups}\n\n" + L.
- **Results** (`count:count` is the total, `itemNoun:noun`, `completed:count`, plus the slots each lists):
  - `result.allThrough` (no `completed`; gap): "All {count} {itemNoun} went through."
  - `result.failedAgain` (`failedAgain:count`, `failReason`; gap): "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}). I won't retry them without a new approval."
  - `result.skipped` (`skipped:count`; gap): "{completed} of {count} {itemNoun} went through. {skipped} had changed since the dry run, so I skipped them; they need a new approval."
  - `result.failedAndSkipped` (`failedAgain:count`, `failReason`, `skipped:count`; gap): "{completed} of {count} {itemNoun} went through. {failedAgain} failed again ({failReason}), and {skipped} had changed since the dry run, so I skipped them. I won't retry any of them without a new approval."
  - `result.stillResending` (gap): "Still resending: {completed} of {count} {itemNoun} have gone through so far. I'll tell you when it's done."
  - `result.interrupted` (`remaining:count`; gap): "The resend stopped when OcuTalon restarted: {completed} of {count} {itemNoun} went through. The other {remaining} need a new approval."
  - `result.couldNotStart` (`reason` only): "Nothing was resent: {reason}. Nothing was changed."

**Tests (Lane B):**
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` (new). It extends `OcuTalon.Test.Contract` for `Read` (Rule 2). It sets the process zone in each test and restores it in `OnAfterOneTest`, and saves and restores `onlineDemo` as `Test.Web.Status` does. It holds:
  - **XData `Fixtures`:** for every key, its `slots` and the exact expected `text`, plus `web` where it differs. Use UJ-1 values: count 50, orders, 14:12 ET, the partner's date format, order date 10/16/2026 to 2026-10-16, results 48/47/45/30 of 50, "Approved from Telegram at 14:15 ET.", the later request "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?".
  - **XData `Gaps`:** the 9 gapped keys.
  - **`TestEntries`:**
    - both classes parse;
    - the keys of Core and Watch are exactly the two lists above, with no key or prefix in both;
    - each entry is well formed (the key pattern, a non-empty `text`, placeholders equal to the declared slots in `text` and `web`, types in the closed set, a `count` slot wherever there is a noun, a `source`);
    - the keys with a `gap` are exactly `Gaps`.
  - **`TestEveryKeyOnEveryChannel`:** rows 1, 2 and 10's channels. The fixture key set equals the catalog's, and every key renders on `web`, `phone`, `mailbox` and `telegram`. The other four `CHANNEL` values and `""` give `""` and an error naming the channel.
  - **`TestTimesAndLocalInstall`:** rows 3 and 4 through `RenderAt`.
  - **`TestNoun`** (row 5), **`TestStringSlots`** (row 6), **`TestGroups`** (row 7), **`TestEnumeratedSlots`** (row 8, reading `FALLBACKREASON` from `Msg.Enum`, so that a new value without a map fails), **`TestCost`** (row 9), **`TestErrors`** (row 10), **`TestExtraSlots`** (row 11).
  - **`TestNotificationHandoff`** (row 12): the saved message is deleted in the test and again in `OnAfterAllTests`.
  - **`TestRenderReadsClockAndFlag`** (row 13).
- `src/ocutalon/cls/OcuTalon/Test/Data/Time.cls`: add `TestForMessage` (row 4 against `ForMessage` directly, in `America/New_York`, plus a winter time, which is EST). Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls` (new; AD-3; row 14). Its XData `Classified` lists:
  - `compared`: `Login` TITLE, HEADING, SUBMIT, HELP, ERRORCREDENTIALS, ERRORNOROLE and LOGOALT, mapped to `signIn.title`, `.heading`, `.submit`, `.help`, `.errorCredentials`, `.errorNoRole` and `.logoAlt`; `ApiBase` MESSAGESIGNEDOUT to `signIn.signedOut`;
  - `notInUx`: `Login` USERLABEL, PASSWORDLABEL and SHOWPASSWORD;
  - `notText`: the other 18 own parameters (Code Map).
  
  `TestCopiesEqualTheCatalog` compares each `compared` value, with `&middot;` decoded, against `Render(key, "", "web")`. Any other `&name;` fails. `TestEveryParameterIsClassified` reads every class of both packages and its own parameters from `%Dictionary.CompiledClass` and `CompiledParameter`, keeping those whose origin is the class. Each must sit in exactly one list, and no list entry may be stale. Rule 2: `Test.Web.SignIn.TestTexts` keeps pinning the page's literals; this class adds the catalog comparison and the classification, and copies no code.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`: add the four signature rows of row 16 (with `*sc` for the output parameter, as `ClassFor`'s row does). Raise the floor to `count >= 47`. Update the header bullet.

**Shell (Lane B; DW-12):**
- `docker/tests/test-production.sh`:
  - **The zone.** Before the start, write `$tmp/compose.tz.yml` (`services: iris: environment: TZ: America/New_York`) and `live_add_file` it, so the whole stack runs in that zone.
  - **The environment check.** After row 14, for each job of `item_jobs`, read `TZ` from `/proc/<job>/environ` in the container (`tr '\0' '\n'`), and pass when every job has `TZ=America/New_York`.
  - **The probe.** Extend row 21's `WatchOpsFail.cls` fixture: its `OnInit` first sets `^OcuTalonTest("TimeProbe",$Job)` to `$ListBuild(##class(OcuTalon.Data.Time).Zone(), ToLocal("2026-01-15T17:00:00Z"), ToLocal("2026-07-15T16:00:00Z"), $SYSTEM.Util.GetEnviron("TZ"))`, then fails as before. After row 21, a new check reads every probe entry (at least one) and asserts row 15's values, then kills `^OcuTalonTest("TimeProbe")`.
  - **Docs.** Document both checks in the header as "DW-12". No new restart is needed, because row 21 already starts the fixture. Rule 2: extends row 21's fixture and `item_jobs`.

**Pipeline:**
- `_bmad/custom/skill-rules.md`: in Rule 21's fresh-environment line only, change the class count to "29 classes: 9 in `lane-a`, 20 in `lane-b`". No local path.

**Acceptance Criteria:**
- **AC1, the catalog classes and keys.** Given the package compiled on slot A or in a throwaway, when `Test.Msg.Catalog` reads both catalog classes, then:
  - `OcuTalon.Msg.Catalog.Core` holds exactly the 57 Core keys and `.Watch` exactly the 22 Watch keys, with the texts above;
  - every entry is well formed, and every noun slot is `itemNoun: {"one","other"}` picked by `count`;
  - the gapped keys are exactly the 9 listed (AD-29, AD-32).
- **AC2, every key on each channel.** Given each key's fixture slots and the fixture context, when `RenderAt` renders it on `web`, `phone`, `mailbox` and `telegram`, then the text equals the fixture's, identical on the three message channels and with the web wording on `web`. When it renders on any other channel, then the result is `""` with an error naming the channel (rows 1, 2, 10).
- **AC3, the message-text rules.** Given the rules of rows 3 to 11, when their tests run, then times follow the instance zone, the dates and "ET" rule; nouns, string slots, groups, enumerated slots and costs follow their rows; every bad input gives `""` and a named error; extra slots are ignored.
- **AC4, the contract handoff (Integration AC).** Given an `OcuTalon.Msg.Notification` saved with a `CatalogKey` and JSON `Slots` as a producer sets them, when the renderer reads them back on `telegram` in the fixture context, then it gives the UJ-1 incident notice exactly. And `Render` itself follows the online-demo flag and the clock (rows 12, 13).
- **AC5, the public copies (AD-3).** Given the public package's own parameters, when `Test.Web.PublicTexts` runs, then each compared copy equals its catalog text and every parameter is classified once. So a changed copy, a changed catalog text or a new unlisted parameter turns it red (row 14).
- **AC6, DW-12.** Given a throwaway started with compose `TZ: America/New_York`, when `ci/iris.sh live production` runs, then every item job's environment holds that `TZ`, and an item's own production job reports `Zone()` and both `ToLocal` values in that zone (EST in January, EDT in July). So `Render`'s times follow the container's zone with no explicit zone (row 15). Otherwise the story halts at Task 0.
- **AC7, the signatures.** Given `Test.Contract.Ac`, when it runs, then `Render`, `RenderAt`, `Entry` and `Data.Time.ForMessage` keep their parameters and return types (row 16).

### Review Findings

Code review of October 20 (Rule 22 standing grant; tier `full-opus`, no model override; layers `blind-hunter`, `edge-case-hunter`, `verification-gap`, `acceptance-auditor`, plus one read-only DW-28 investigator). Rows from the layers: 26, plus 2 of the reviewer's own. After grouping: 16 entries (1 high, 4 medium, 11 low) and 9 rejected lines. Each line gives severity, fix-risk, footprint and the Rule 15 disposition.

- [x] [Review][Patch] DW-28 root cause: the "another production" block stopped a production a few milliseconds after starting it, so `Ens.ScheduleHandler` took the start's request and waited in `Ens.Director.UpdateProduction` for `^Ens.Runtime`, which `StopProduction` holds through `MakeQuiescent` and `StopAll`; the stop then failed at its budget (`ErrProductionNotQuiescent` or `ErrJobsNotStopped`) and left `ZzOther.Production` running [docker/tests/test-production.sh:316] — high (CI red on `2ba8fe8`, both attempts, 30.46 s and 30.47 s, the second alone on the host); fix-risk low (test-only wait, measured); in-story (a file this story changed; the block is Story 0.6's); fixed. Each stop in the block now first waits, up to 10 s, until the handler's queue is empty and its job is Alive, dequeuing and has no active message (`CHK|settled|1`, `CHK|other-settled|1`), and a failed stop prints its error text. Evidence (throwaway `x28`, tag `v09r`, build 154): start, refused step and stop of `ZzOther.Production` in a loop failed 5 of 15 times with `TZ: America/New_York` and 3 of 15 without it, and 0 of 15 with the wait (`waited` about 0.1 s); the event log of each failure shows the handler's "updating..." line only after the stop gave up, and once the handler's own `ErrCanNotAcquireRuntimeLock`. Ruled out: a probe job left running (the probe is a global set in `OnInit` and its check takes no lock; OcuTalon's own stop at the block's start returned OK), a slower start (start-to-ready 141 and 153 s against 163 and 232 s before), a changed order of checks (both new checks are read-only and sit before the "no model" check), the zone in the stop path's deadline math (lock timeouts and `$ZH` only; `MarkDeadJobs` compares `$ZTimeStamp` with `$ZTimeStamp`), and host load (attempt 2 failed with no other job on the host). Not explained: why CI went from 0 of 4 to 2 of 2 at `2ba8fe8`; the zone is not needed for the race (3 of 15 without it). `live production` passed twice with the patch (23 PASS, the block 8 values). DW-28 re-owned to this story for adjudication on a green CI run.
- [x] [Review][Patch] `RenderAt`'s empty clock ("" is the current time, Rule 22 ruling) had no test [src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls:425] — medium (a cross-lane contract form unpinned); fix-risk low (one assertion pair); in-story; fixed in `TestRenderReadsClockAndFlag`.
- [x] [Review][Patch] `Test.Web.PublicTexts` re-implemented `Test.Web.Status.PublicClasses`' query (Rule 2 copy with no stated reason; the spec says the class "copies no code"), and read `CompiledClass`, so a defined but uncompiled public class was skipped silently [src/ocutalon/cls/OcuTalon/Test/Web/PublicTexts.cls:40] — medium (Rule 2); fix-risk low; in-story copy, one-word change in the in-epic `Test.Web.Status` (`PublicClasses` no longer `[ Private ]`); fixed: it calls `PublicClasses()` and asserts each class is compiled.
- [x] [Review][Patch] `Catalog.Clean` kept U+061C (a Bidi_Control character, against its doc), U+180E, U+2061 to U+2064 and U+FFF9 to U+FFFB, and the class doc said "the zero-width characters go" while ZWJ and ZWNJ stay [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:243] — low; fix-risk low (characters added to the removal list); in-story; fixed, with the sweep's `Characters` (113 code points, every Bidi_Control character) and string case 10. The tag characters U+E0000 to U+E007F (surrogate pairs) still pass: rejected below.
- [x] [Review][Patch] A text or sentence slot ending in "?", "!" or U+2026 before a period of the text rendered "?." ("Reminder: Did you call the vendor?.") [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:155] — low; fix-risk low; in-story; fixed. Rule 22 ruling: the text's period goes and the value keeps its mark (rejected: stripping the value's mark, which changes a quoted question; leaving "?."). String case 6 now reads "x Approve? None of my fixes..."; the fake "Approve?" still cannot start a line (AD-32).
- [x] [Review][Patch] Rule 19: AC1's well-formedness check (`Problems`) and AC3 row 8 had no demonstrated mutation [_bmad-output/implementation-artifacts/spec-0-9-the-message-catalog-and-its-one-renderer.md, Verification] — low; closed in this pass (mutations under Verification, code review).
- [x] [Review][Patch] `TestErrors`' case "a noun with no count slot" uses an entry that declares `count`, so it tests a missing count value [src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls:348] — low; relabelled.
- [x] [Review][Patch] The `Catalog` class doc gave a closed list of who renders that misses the banners (2.10), `Checks.Render` (5.7) and the no-commands answer (1.1) of the Consumed-by list [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:1] — low; now states AD-32's rule ("Producers never render text").
- [x] [Review][Patch] `checks.everythingElsePassed`'s `source` cited a Conversation row that does not exist [src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:66] — low; now cites Voice and Tone / Reserved sentences.
- [x] [Review][Patch] `Catalog.Watch`'s doc said Lane A adds keys "from Epic 0 on" (AD-29: after Epic 0) [src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:3] — low; fixed.
- [x] [Review][Patch] `ReadEntries`' doc carried the copy's reason, which Rule 2 keeps in the spec or the commit, never in a code comment [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:299] — low; the comment now states the contract only.
- [x] [Review][Defer] On `web`, the answered statuses on the cards and the banners carry instance message times with " ET", while the UX's Formats gives page times ("Approved from Telegram at 20:15 CEST") [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:140] — deferred: medium, spec-bound (row 2 and the Rule 22 ruling "page times are the web app's"; AD-18), so `by-design` here; the existing DW-29 (owner 2.10) got an occurrence naming 6.3/6.4's cards.
- [x] [Review][Defer] No length cap on a rendered text, while Telegram caps a message at 4,096 characters [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:185] — deferred: medium if reached, out of story; existing DW-30 (owner 12.6), occurrence appended.
- [x] [Review][Defer] AD-32's older sentence can read as putting the Results keys in `Catalog.Core`, while its Story 0.9 bullet and the code put `result.*` in `Catalog.Watch` [ARCHITECTURE-SPINE.md AD-32] — deferred: low, the spine is the lead's (Rule 20); DW-31 `wontfix-accepted` with `reopen_if`.
- [x] [Review][Defer] `Test.Msg.Catalog` repeats `Test.Data.Time`'s process-zone save and restore [src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls:29] — deferred: low (Rule 2 copy with a weak reason: the spec names Test.Data.Time as the pattern); fix-risk med (a shared base is a new `OcuTalon.Test` root class beside the shard discovery); DW-32 `wontfix-accepted` with `reopen_if`.
- [x] [Review][Defer] `Catalog.ReadEntries` repeats `Test.Contract.Read`'s three-line JSON XData read, a copy the spec states (product code may not depend on `OcuTalon.Test`) [src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:299] — deferred: low; no story is planned to unify it and `burndown` may not own a LOW, so DW-33 `wontfix-accepted` with `reopen_if`. No other near-copy was found (the shell checks reuse `item_jobs` and the row-21 fixture).

**Lead's points.** AD-32 holds: `Render` is the one renderer, returns "" with an error and never a partial text, never throws (its own Try), renders only `web`, `phone`, `mailbox` and `telegram`, picks the noun's form by `count`, substitutes in one pass with line breaks collapsed (no placeholder or line injection), escapes nothing, and `RenderAt` writes no global (it opens compiled XData only). AD-29 and AD-33 hold: Core and Watch share no prefix (`TestEntries`), pairing and press texts are in Core, and Watch's doc now says Lane A's after Epic 0. AD-3 holds: `Test.Web.PublicTexts` failed on a new `ApiBase` parameter and on a changed copy (mutations), and `Test.Web.Status` passed on slot A (7 of 7), so the public packages reference only AD-3's allow-list. Texts: QA's independent extraction and the auditor's both matched all 79 keys; source is ASCII with `…` and `·` escapes. Rule 22 ruling: `answered.rejectedBy` needs no `gap`, because both of its parts are fixed by the UX (the "Rejected from {channel} at {time}. Nothing was changed." status and Formats > Who answered, "by <user>" after the verb), so no wording is invented; a `gap` marks a form the UX leaves open. `checks.notEverythingRestPassed` joins the UX's two sentences with one space, as "follows" in the Conversation row says. `ForMessage`: every form, the year boundary (six days back across January 1 gives a weekday, as the spec orders the rules) and both 2026 daylight-saving days hold (QA's tests, run green); " ET" only with the flag; "at" becomes "on" only before a dated time. Rule 3: no user-facing consumer ships yet; AC4's saved and reopened `Notification` is the runtime evidence. Rule 1: AC4 is the Integration AC. Rule 5: no NFR worked around. Rule 6: no AD mismatch.

**Rejected** (one line each):
- Blind Hunter and Edge Case Hunter: " ET" follows the flag, never the zone — `by-design`: the spec and Story 2.7's AC add " ET" on the online demo, and the demo host's story fixes its zone as US Eastern (`epics.md`, "its time zone is US Eastern so message times read like '14:12 ET'").
- Blind Hunter: the dry-run example's `before` and `after` are cleaned as text (whitespace, a final period, empty refused) — `wontfix-theoretical`: release 1's one fix kind reformats dates, whose values are never empty or whitespace-only; real once a fix kind's values can be empty or differ only in spacing (that step adds its own keys, AD-16).
- Blind Hunter: a capitalised or punctuated `fixSummary` reads "I can Repair..." — low, the producer writes the clause (UJ-1 "repair and resend all 50"); the renderer cannot change case without inventing text.
- Edge Case Hunter: a count of 1e400 gives `<MAXNUMBER>` naming no slot — `wontfix-theoretical`: still "" with an error, never a throw or partial text; real only if a producer passes untrusted JSON numbers.
- Edge Case Hunter and Blind Hunter: tag characters U+E0000 to U+E007F survive — low: invisible in Telegram and the page, and removing them needs a surrogate-pair branch; reopen if a notice is ever fed back to a model.
- Verification Gap: the fixture-size counts cannot be turned red by a product change — false as a defect: they guard the fixture lists and pin no AC; the AC pins next to them can.
- Verification Gap: `Test.Web.PublicTexts` calls `Render`, and a failed `TestRenderReadsClockAndFlag` restores the flag only in `OnAfterAllTests` — false: the compared keys have no slot, so no clock or flag reaches them (the spec names `Render` there), and the flag is restored before the class ends.
- Acceptance Auditor: `skill-rules.md`'s timing line changed beyond the class count — false: that line is Rule 21's measurement record, edited by the lead's bookkeeping and QA, not by the implement stage.
- Acceptance Auditor: `banner.costCap` and `bannerAction.budgets` look like step 2 keys — the fix edits the spec, whose key table lists both.

## Spec Change Log

Implement stage (October 19 and 20). These Rule 22 rulings and clarifications settle points the spec left open; none changes an AC, an AD or an NFR.
- Rule 22 ruling: which slots does `incident.laterRequest` declare, given "the same slots" as `incident.withFix`? -> the slots its text uses: `count`, `itemNoun`, `time`, `fixSummary`, `field`, `before`, `after` and `resendCount`, with no `cause`, because the entry rule is that `text` and `web` use exactly the declared slots and the later request's text has no `{cause}`. A producer may still pass `cause`; an undeclared slot is ignored (row 11, pinned by `TestExtraSlots`). (rejected: declaring `cause` without using it, which breaks the placeholder rule that `TestEntries` pins.)
- Rule 22 ruling: what does a cost of 0 show? -> "<$0.0001", by the rule "under $0.0001 shows <$0.0001" (rejected: "$0.00", which the UX does not give).
- Rule 22 ruling: what do `ForMessage` and `RenderAt` do with an unreadable `now`? -> `ForMessage(utc, now)` returns "" for a non-empty `now` that is not a UTC time, and `RenderAt` returns "" with an error naming the clock; an empty `now` is the current time in both. (rejected: ignoring a bad `now`, which would show a time relative to the wrong day.)
- Rule 22 ruling: what exactly does a string slot lose? -> Tab, line feed, vertical tab, form feed, carriage return, NEL, no-break space and the Unicode line and paragraph separators become spaces; the other control characters are removed; runs of spaces become one; the ends are trimmed; one trailing period goes where the text continues with ".". A `channel` or `fallbackReason` value is case-sensitive, and both forms of a `noun` are checked even though one is used. (rejected: a regular-expression pass, which needs the same three steps and more code.)
- Rule 22 ruling: where does a test set the process zone? -> `OnBeforeOneTest` of `Test.Msg.Catalog` sets America/New_York before every test, and `OnAfterOneTest` and `OnAfterAllTests` restore it (rejected: a line at the top of each of the 13 tests).
- Clarification (Code Map, "own parameters of the public classes"): the abbreviations "U" and "H" are `UseSession` and `HandleCorsRequest`. Read from the class dictionary, `Shell` has `CONTENTTYPE`, `ROLE` and `UseSession`, and `Status` has `CONTENTTYPE`, `HandleCorsRequest` and `UseSession`. The count of 18 non-text parameters is unchanged.
- Clarification (Task 0, "the unit's other checks"): the live unit's other checks stay green with the zone set (see Verification, Task 0), apart from two older checks that failed once in the first run and were not reproduced.

Review pass (October 19). Rule 22 rulings that settle points the review found open; none changes an AC, an AD or an NFR.
- Rule 22 ruling: which cost tier applies near a boundary? -> the tier of the amount as shown, so 0.99996 is "$1.00" and 0.009996 is "$0.010" (rejected: the tier of the unrounded amount, which shows "$1.000" and "$0.0100", forms the Formats rule gives no amount).
- Rule 22 ruling: what if a string slot is only a period where the text continues with a period? -> an error naming the slot, because the slot is empty once that period goes (rejected: rendering a blank slot, which is the partial text row 10 forbids).
- Rule 22 ruling: which more characters does a string slot lose? -> the Unicode space separators (U+1680, U+2000 to U+200A, U+202F, U+205F, U+3000) become spaces; the zero-width space, the bidirectional controls (U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069), the word joiner and the byte order mark go. The zero-width joiner and non-joiner stay, because removing them would break emoji and some scripts. (rejected: a general category test, which needs a table the platform does not give.)
- Rule 22 ruling: can `Render` throw? -> No. It wraps its own reads of the clock and the flag, and an omitted argument is empty, so every failure is "" with an error (rejected: leaving the reads outside the Try, which let a missing channel raise `<UNDEFINED>`).

## Review Triage Log

### 2026-10-19 — Review pass
- verdicts: 35 findings — high 0, medium 5, low 29, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind Hunter: banner times render as message times, while the UX says banner times are page times — the intent fixes it (row 2: every other key renders as on the message channels; the Rule 22 ruling "page times are the web app's"), so the fix is a spec edit; Story 2.10 decides how a banner shows its time (residual risk).
  - `[low]` `[reject]` Blind Hunter: " ET" and the "at"-to-"on" rule live in Render, not in `ForMessage`, so a time inside a `text` slot must repeat them — the spec puts both in Render and leaves `checks.*` times to Story 5.7 through `Data.Time`; a public helper is new surface.
  - `[low]` `[reject]` Blind Hunter: the "at"-to-"on" rule reads the rendered text, so a slot ending in "at" before a dated time would be rewritten — no shipped template puts a slot right before " {time}" (all 79 read), so nothing reaches it; theoretical.
  - `[low]` `[patch]` Blind Hunter: the cost tier is picked before rounding ("$1.000", "$0.0100") — patched: the tier is that of the amount as shown (`Catalog.Cost`), pinned in `TestCost` with 0.99996, 0.99949, 0.009996 and 0.009949.
  - `[low]` `[reject]` Blind Hunter: Rule 21's timing sentence ("every class takes under 0.4 s") is now out of date — the instruction allows only the class count to change there, and the sentence is October 19's measurement; `Test.Msg.Catalog` took 0.67 s in the shard (residual risk).
  - `[low]` `[reject]` Blind Hunter: `sentence` is not checked for a time, the groups slot and the rendered length have no limit — the spec asks Render for neither; the producers, `ReplyGuard` and `TelegramOut` own the limits (Design Notes, Consumed-by 5.4, 5.7, 12.x).
  - `[low]` `[reject]` Blind Hunter: `Test.Msg.Catalog` pins Lane A's 22 Watch keys, so a Lane A key edits a Lane B test — the spec's Tests section requires the exact key sets and fixtures, and Epic 0 creates every key (AD-29).
  - `[low]` `[reject]` Blind Hunter: purity has no test, and the error paths of `ReadEntries` and `Find` have none — no AC pins purity; the shipped classes cannot reach those paths, and a key in both classes fails `TestEntries` through the prefix check; theoretical.
  - `[low]` `[reject]` Blind Hunter: `slots` is typed `%String` though objects are accepted — the spec fixes the signature; ObjectScript passes an object reference through a `%String` parameter unchanged (the tests do), and `Test.Contract.Ac` pins names and return types only.
  - `[medium]` `[patch]` Edge Case Hunter: a text or sentence slot that is only "." renders blank with a status OK, against "an empty string slot is an error" — patched: the empty check also runs after the trailing period goes; `TestErrors` pins `cause`, `fixSummary` and `after`.
  - `[low]` `[patch]` Edge Case Hunter: Unicode spaces, zero-width characters and bidirectional controls survive the string cleaning — patched in `Catalog.Clean` (the Spec Change Log lists the characters); `TestStringSlots` cases 8 and 9.
  - `[low]` `[patch]` Edge Case Hunter: `Render` reads the clock and the flag outside its Try and raises `<UNDEFINED>` for an omitted argument — patched: `Render` has its own Try/Catch and `$Get` of its arguments; `TestErrors` renders with no channel.
  - `[low]` `[patch]` Edge Case Hunter: the cost rounds across a tier edge — the same defect as the Blind Hunter's; patched once.
  - `[low]` `[reject]` Edge Case Hunter: no length limit on groups or on the rendered text — the same claim as the Blind Hunter's.
  - `[low]` `[reject]` Edge Case Hunter: the DW-12 probe is keyed by `$Job` only — the fixture's `OnInit` runs only when the production starts the item, in the item's own job; another writer would have to call that `OnInit`; the check also fails closed when there is no entry.
  - `[low]` `[reject]` Edge Case Hunter: an item job could exit between `item_jobs` and the `/proc` read — the read follows row 14's check that every enabled item runs, on a production just started, and fails closed; it passed in the four runs of this story (the earlier flake was in other checks).
  - `[medium]` `[patch]` Edge Case Hunter (claim): "an empty value is an error" does not hold for ".", the same defect as the lone-period finding above — patched once.
  - `[low]` `[reject]` Edge Case Hunter (claim): `sentence` ("with no time") is not enforced — the same claim as the Blind Hunter's.
  - `[medium]` `[patch]` Verification Gap: the empty-`now` default of `ForMessage` is pinned only by assertions that an identity default also satisfies — patched: `TestForMessage` renders a time two days back with an empty `now` and expects a weekday form; the mutation line is under Verification.
  - `[medium]` `[patch]` Verification Gap: `TestExtraSlots` compares two renders and asserts neither — patched: both renders are asserted OK and the first equals the fixture's text.
  - `[medium]` `[patch]` Verification Gap: a string slot of only "." renders blank — the same defect as above; patched once.
  - `[low]` `[patch]` Verification Gap: cost rounding across tier edges is not pinned — the same defect as above; the new `TestCost` cases pin it.
  - `[low]` `[reject]` Verification Gap: AC3's, AC4's and AC1's recorded mutations do not cover every row or rule — Rule 19 asks for one demonstrated mutation per AC, and each of AC1 to AC7 has one; the patched pins have their own lines.
  - `[low]` `[reject]` Verification Gap: the DW-12 shell checks depend on row 21's order, do not intersect the probe jobs with `Ens.Job` and cannot show which path supplied `TZ` — they fail closed, the probe is the production's own `OnInit`, and AC6 asks for exactly these two observations.
  - `[false]` `[reject]` Verification Gap: wall-clock and shared-state use in the tests — no bad outcome is claimed; the clock tests allow a midnight crossing and the flag and the zone are restored.
  - `[low]` `[reject]` Intent Alignment: rows 1 to 11 run through `RenderAt`, and `Render` itself only in row 13 and the public-text comparison — the Rule 22 ruling makes `RenderAt` the testable form; `Render` is `RenderAt` plus the clock and the flag, which row 13 pins.
  - `[low]` `[reject]` Intent Alignment: the expected texts are a second hand-copied XData, and no test reads EXPERIENCE.md — the spec calls for that XData; the catalog was also compared with the spec's key tables by script (79 keys, no difference).
  - `[low]` `[reject]` Intent Alignment: the unit tests set the zone with `$SYSTEM.Process.TimeZone`, and the `TZ` path is only in the live script — row 15 puts that observation in `ci/iris.sh live production`.
  - `[low]` `[reject]` Intent Alignment: the producer side of the handoff is the test itself — row 12 is written that way; no producer exists before Epic 2.
  - `[low]` `[reject]` Intent Alignment: the public copies are compared as class parameters, not as the rendered page — row 14 says so, and `Test.Web.SignIn.TestTexts` pins the page.
  - `[low]` `[reject]` Intent Alignment: banner times are message times, not page times — the same claim as the Blind Hunter's first.
  - `[low]` `[reject]` Intent Alignment: the UX's literal "Orders" became a `{production}` slot with no `gap` — the Design Notes carry the Rule 22 ruling and its VETO WINDOW FYI, and the nine `gap` keys are fixed by the spec.
  - `[low]` `[reject]` Intent Alignment: the time inside `checks.notEverything*`'s `whatFailed` never passes through `Data.Time` here — the Design Notes give it to Story 5.7.
  - `[low]` `[reject]` Intent Alignment: `{limit} messages` has no singular — the limit is a fixed allowance that is never 1, and the UX gives no form.
  - `[low]` `[reject]` Intent Alignment: purity, the flag read only through `Settings.Get` and the no-reference rules have no assertion in this diff — existing static rules (`public-global`, `bridge-refs`) and `Test.Web.Status` hold the references; purity is the same claim as the Blind Hunter's eighth.

## Design Notes

**ADs:**
- AD-32: the notification contract, the one renderer, slots and the item noun.
- AD-29: one catalog class per lane; Epic 0 creates every release-1 and 0.1.1 key; the renderer is Lane B's after Epic 0.
- AD-3: the public package keeps its copies, compared by a test; it references nothing but what AD-3 allows.
- AD-18: `Data.Time` is the only converter, and the instance zone is the container's `TZ`.
- AD-14: `CatalogKey` and `Slots` on `Item`, and the code-fixed notices in `Catalog.Watch`.
- AD-28: the reserved sentences are catalog entries that only `Checks.Render` picks.
- AD-12: the banners follow the closed status catalog.
- AD-8: the fallback reasons.
- AD-15: the incident notice variants and the item noun.
- AD-19: the online-demo flag only through `Data.Public.Settings`.
- AD-2: no bridge reference to the catalog.
- AD-33: the ownership of the two catalog classes.
- AD-22: the tests in the existing shards.

No AC contradicts an AD, and no NFR is unmeasurable. AD-32's "an `*Out` operation picks the item noun's form by count" still holds: the operation does it through `Render`.

**Rule 22 rulings** (each as question → choice (rejected: …)):
- Rule 22 ruling: Render's full signature? → `Render(key, slots, channel, *sc) As %String`. A trailing output `%Status` follows `Accessor.ClassFor`, so the text comes back directly and an error never yields a partial text. (rejected: `As %Status` with the text by reference, which changes AD-32's three leading parameters into four; throwing, which an `*Out` operation would have to catch.)
- Rule 22 ruling: how do tests fix the clock and the flag? → `RenderAt(key, slots, channel, now, onlineDemo, *sc)`, which `Render` calls with `NowUtc()` and the setting. Lane A's render tests use it too. (rejected: tests flipping `onlineDemo` and racing the clock, which is flaky at midnight and shares a global.)
- Rule 22 ruling: which channels render? → `web`, `phone`, `mailbox` and `telegram`, the four with an `*Out` operation in release 1 and 0.1.1. `mailbox` reads as message text. `email`, `webhook`, `slack` and `system` are refused until their step adds them. (rejected: rendering every enumeration value the same, which would let a step 4 email go out in a format nobody chose.)
- Rule 22 ruling: what differs on `web`? → Only the UX's page wording, as an explicit `web` text: the incident notices without "Approve?", and the approved statuses without the final period. Times stay the instance's message times on every channel, because page times in the browser's zone are the web app's (Formats). (rejected: rules computed from the text, which are invisible in the catalog.)
- Rule 22 ruling: where does each key live? → In the class of the lane that owns the key's producer, except Telegram's pairing replies and press alerts, which AD-32 puts in Core.
  - Core: the pairing replies, presses, answered statuses, conversation and allowance, fallback reasons, tell now, reminders, banners and the sign-in texts (Lane B producers, and the web).
  - Watch: production state changes, the watch tool's answers, the agent's no-commands answer, checks, incident notices and results (`WatchOps`, `Checks`, `IncidentManager`, `FixExecutor`, Lane A).
  - (rejected: everything in Core, which would make Lane A edit Lane B's class from Epic 5.)
- Rule 22 ruling: how is the catalog stored and read? → One JSON XData block per class, read through `%Dictionary.CompiledXData` on each call, with no cache. That costs about 1 ms per call `(inference)`, measured by the test's runtime. (rejected: a compile-time generator, which is more code to review; a process-private cache, which goes stale after a recompile.)
- Rule 22 ruling: when does a message time carry a date, and how? → `ForMessage`:
  - the same local date as now gives "14:12";
  - 1 to 6 days before or after gives "Thursday at 14:12";
  - otherwise "Oct 17 at 14:12";
  - another year gives "Oct 17, 2025 at 14:12".
  
  Render adds " ET" on the online demo. It turns a preceding "at " into "on " for a dated time ("it was due on Thursday at 10:00 ET"), because "at Thursday at" is ungrammatical. (rejected: always a bare time, which misleads after a restart; "tomorrow" and "yesterday", which the UX uses only for page expiries.) VETO WINDOW FYI (22.3, public-facing text).
- Rule 22 ruling: is the production's name fixed as "Orders" in the state-change notices? → No. It is a `production` slot, so that a local install watching another production isn't told "Orders" (22.2.3). The online demo renders the UX's text exactly. `watch.onlyOrders` keeps "Orders", because there it is the fact. (rejected: the literal "Orders" everywhere.) VETO WINDOW FYI (22.3).
- Rule 22 ruling: who adds "by {user}"? → The producer picks `answered.approvedBy` or `answered.rejectedBy` when the install is local and has more than one user, as Formats' rule says. Render queries no users. (rejected: an optional segment grammar.)
- Rule 22 ruling: string slots? → Each is trimmed, has its control characters removed, has whitespace runs (line breaks included) collapsed to one space, and loses one trailing period before a template period. Substitution is a single pass, so slot text can't inject a placeholder or an extra line such as a fake "Approve?". There is no escaping. (rejected: HTML or Markdown escaping, which would show as literal characters in plain-text Telegram and in Angular's text binding.)
- Rule 22 ruling: the sign-in texts the comparison covers? → The 8 parameters whose wording the UX fixes (title, heading, button, help, both errors, logo alt and the API's signed-out message). The three labels the UX doesn't quote stay outside it. Every parameter of both public packages must be classified, so a new text can't skip the comparison. (rejected: only the four texts that the epic context names, which leaves the title, heading, button and alt text uncompared.)
- Rule 22 ruling: are the catalog classes added to `Test.Contract.Ac`'s `Classes` list (0.4's AC names them)? → No. That list's oracles pin properties, and the catalog classes have none. `Test.Msg.Catalog` pins their exact key sets. (rejected: an empty contract entry.)
- Rule 22 ruling: does DW-12 get a permanent check? → Yes, inside `test-production.sh`, through row 21's existing fixture and a run-time compose file. It adds no stack, no restart and no tracked compose file. (rejected: a measurement only, which leaves DW-12's "no test" root cause; a new live unit, which adds a stack start against DW-21.)

**Owner-only (Rule 22.4), for the Contest Planner:**
- **Singular forms after a count.** The UX fixes only the plural text. Each key below renders its fixed text for every count, carries a `gap`, and is pinned by `Test.Msg.Catalog`'s `Gaps` list:
  - "repaired copies" when `resendCount` is 1 (`incident.withFix`, `incident.laterRequest`);
  - "All 1 order went through." (`result.allThrough`);
  - "them" and "they need" for one message failed again or skipped (`result.failedAgain`, `.skipped`, `.failedAndSkipped`);
  - "1 of 50 orders have gone through" (`result.stillResending`);
  - "The other 1 need" (`result.interrupted`).
- **The late press after a rejection.** The UX fixes only "Already answered: approved from …". Its rejected form and its "by {user}" form are not fixed (`answered.alreadyApproved`'s `gap`). Until the owner fixes them, Stories 6.3 and 12.7 use the nearest fixed text, `answered.rejected` or `answered.rejectedBy`.
- **The sign-in labels.** "User name", "Password" and "Show password" (0.3's labels) are not quoted in the UX, so they are neither catalog keys nor compared.

**Integration ACs (Rule 1):** No consumer of `Render` ships in this story. The first consumers will be Story 1.6 (Lane A: the 11 fallback-reason texts) and Story 2.7 (Lane B: `WebChatOut` renders every notification through `Render`). AC4 exercises the producer-to-renderer handoff with the real `Notification` class.

**Consumed-by:**
- 1.1: Chat's no-commands answer, `agent.noCommands`.
- 1.6: the fallback-reason keys and their enum map.
- 2.4: `conversation.turnFallback`.
- 2.6, 2.7: `notice.tellNow`, or the Item's own key. `WebChatOut` renders the chat's notice cards on `web`, including the incident card's wording without "Approve?". Whether the "Why now:" line goes to the payload's `whyNow` is 2.7's call.
- 2.10: `banner.*` and `bannerAction.*`.
- 4.5: `SimPhoneOut` on `phone`.
- 5.4: `incident.withFix`, `.noFix`, `.noFixUnknown` and `.fallback`. `incident.withFix` needs 7.2's dry-run slots, so an earlier notice is 5.4's to settle in its own class.
- 5.6: `watch.productionStopped` and `.itemDisabled` on the Item.
- 5.7: `checks.*` from `Checks.Render`, and the reserved sentences for `ReplyGuard`. `whatFailed` is text; a time inside it is 5.7's, through `Data.Time`.
- 6.3, 6.4: `answered.*` and `result.*` on the phone and the card's band; `audit.recorded`.
- 7.2: the dry-run slots and `incident.laterRequest`. 7.3: `result.couldNotStart`. 7.4: `result.allThrough`. 7.5: the mixed, still-resending and interrupted results.
- 8.3, 8.5: `reminder.due` and `.late`.
- 10.3: `pairing.unpairedFromPage` and `.otherChatPaired` from `SessionOps`.
- 12.4–12.7 (Lane A): `TelegramIn`'s replies and press alerts, rendered through `Render`; `TelegramOut` on `telegram`, and its key-by-key comparison with the phone.
- 16.8, 16.9: `banner.resetSoon`, the allowance messages and banners.
- Every later story adds its own keys to its lane's class.

**Consumes:**
- 0.4: `Notification`, `Outbound`, `Item` and `ItemDecision` (`CatalogKey`, `Slots`), `Msg.Enum`, and `Data.Time`.
- 0.3: `Login` and `ApiBase`'s texts.
- 0.2: `Data.Public.Settings` and the `onlineDemo` flag.
- 0.6: the production, its item jobs and row 21's fixture.
- 0.7: `ci/iris.sh` and the shards.

**Reuse (Rule 2):**
- `Data.Time` is extended with `ForMessage`.
- `Test.Msg.Catalog` extends `Test.Contract` for `Read`.
- `Test.Data.Time` and `Test.Contract.Ac` are extended.
- The DW-12 check extends `test-production.sh`'s row 21 fixture and `item_jobs`.
- `Catalog`'s three-line XData read is a stated copy (product code doesn't depend on `OcuTalon.Test`).
- `Test.Web.PublicTexts` is new beside `Test.Web.SignIn.TestTexts`, with a different subject.

**Ledger inbox:**
- DW-12 is addressed by Task 0, matrix row 15, AC6 and the `test-production.sh` check.
- **The contingency.** If a production job doesn't see or use the container's `TZ`, HALT `blocked` with `intent gap` and this recommended amendment:
  - AD-18 and AD-19 gain a structural `Data.Setting` key, `instanceZone`, which the `Public` step writes from the after-start's `TZ` every start;
  - `Data.Time.ToLocal(utc, zone)` gains an optional trailing `zone`, converting under `$SYSTEM.Process.TimeZone(zone)` and restoring the process zone;
  - `Render` passes `Setting.Get("instanceZone")`.
  
  This needs a new configuration home (AD-19, Rule 20), so it is the lead's.
- **Declined DW-12 (only the occurrence residual):** "with TZ unset on a non-UTC host (an IPM install outside the image), Zone() says UTC while ToLocal uses the OS zone". `Render` never calls `Zone()` (it uses `ToLocal` and the flag), and the image has `TZ` unset with `/etc/localtime` at UTC (measured). The residual belongs to the IPM install (Epic 15), for the lead to re-own at adjudication.

**Spine updates for the lead (Rule 20):**
- **AD-32:**
  - `Render(key, slots, channel, *sc) As %String`, `RenderAt(…, now, onlineDemo, *sc)` and `Entry(key, *sc)`;
  - the rendered channels `web`, `phone`, `mailbox` and `telegram`;
  - the `web` wording;
  - the noun's form picked by `count` inside `Render`;
  - plain text with no escaping.
- **AD-29 and Conventions:** the entry shape and its slot types; keys `<prefix>.<name>` with each prefix in one class; the producer-lane placement rule.
- **AD-18 and Conventions Times:** `Data.Time.ForMessage`'s date forms, " ET" on the online demo, and the "at"-to-"on" rule. After Task 0: production jobs inherit the container's `TZ`.

**Time budget (REL-4, inference):** No new stack or restart. The two shard classes add about 1 to 2 s to `lane-b`, and the DW-12 checks add about 2 to 5 s to `live:production`. DW-21's margin is unchanged.

**Size:** One implement pass: 3 new product classes, 2 new test classes, 3 extended tests, 1 shell script and 1 rule line. Most of the volume is the two XData blocks and the fixtures. No split is needed. If one were, the split line would put the AD-3 class and the DW-12 check into Story 0.12.

## Verification

**Runtime targets:**
- **Slot A**, `ocutalon-slot-a` (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON` on every call). First, `iris_server_info` must show build 154 and port 1990.
  - `iris_doc_load` with base `src/bridge/cls`, then `src/ocutalon/cls`.
  - `iris_execute_tests`: one class per call and one call per message.
- **Throwaways** through `ci/iris.sh` only, tag `v09a` (QA `v09q`, review `v09r`), with `OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`, one stack at a time. Each is removed by its trap, then by `ci/iris.sh teardown` with the same tag.
- Nothing else. No push, no `gh workflow run`.

Every command finishes inside one foreground call (`timeout: 600000`).

**Commands:**
- `(loop)` Slot A: `iris_doc_load` of both bases, with no compile error or warning in the new or changed classes.
- `(loop)` Slot A, one call each, all passing:
  - `OcuTalon.Test.Msg.Catalog`;
  - `OcuTalon.Test.Data.Time`;
  - `OcuTalon.Test.Web.PublicTexts`;
  - `OcuTalon.Test.Contract.Ac`;
  - `OcuTalon.Test.Web.SignIn`;
  - `OcuTalon.Test.Web.Status` (the public packages still reference only what AD-3 allows);
  - `OcuTalon.Test.Msg.Contracts`;
  - `OcuTalon.Test.Data.PublicSettings`.
- `(loop)` `bash ci/checks.sh`. Expected: exit 0 (boundaries ASCII, class rules, `ci-config`).
- `(loop)` `OCUTALON_RUN_TAG=v09a OCUTALON_LOCK_OWNER='epic=0 stage=implement' bash ci/iris.sh build`. Expected: exit 0.
- `(loop)` With the same environment: `bash ci/iris.sh live production`. Expected: exit 0, the two DW-12 PASS lines, and every earlier check green with the zone set.
- `(loop)` With the same environment: `bash ci/iris.sh shard lane-b`. Expected: exit 0, with `CLASS OcuTalon.Test.Msg.Catalog passed` and `CLASS OcuTalon.Test.Web.PublicTexts passed`, 20 classes.
- `(loop)` With the same environment: `bash ci/iris.sh teardown`. Expected: nothing of `-v09a-` left.
- `(once)` Fresh-environment check (Rule 19, Rule 21), one per call: `shard lane-a`, `shard lane-b --reverse`, `shard lane-a --reverse`; then `teardown`.
- `(once)` Task 0's measurements and the mutations below.

**Shared surfaces:**
- the two catalog classes and their key sets, which later stories of both lanes add to;
- `Catalog.Render`, `RenderAt` and `Entry`, and `Data.Time.ForMessage`, in `Test.Contract.Ac`'s `Signatures` (floor 47);
- the public setting `onlineDemo`, which `Render` reads (tests save and restore it, as `Test.Web.Status` and `Test.Data.PublicSettings` do);
- the process time zone (set per test and restored in `OnAfterOneTest`);
- the public parameters of `Login` and `ApiBase`, now compared;
- `test-production.sh`'s stack environment (`TZ`) and its row 21 fixture;
- `^OcuTalonTest("TimeProbe",<job>)`, on throwaways only, killed after the check;
- one `Notification` row per run of `TestNotificationHandoff`, deleted;
- Rule 21's class counts;
- `ci/units.sh`'s shards, unchanged.

No test depends on another, and every fixture is unique to its run (the message's row id, the probe's job id).

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, observe red, revert, and confirm `git status --short` and `git diff --stat` are unchanged):
- AC1: `result.allThrough` removed from `Catalog.Watch` → `Test.Msg.Catalog` red at `TestEntries` (the Watch key set).
- AC2: `RenderAt` ignoring `web` → red at `incident.withFix`'s web fixture. The noun's forms swapped (`one` for `count` ≠ 1) → red at row 1.
- AC3: `ForMessage`'s weekday window widened from 6 to 7 days → `Test.Data.Time` red at the 7-day case. The " ET" suffix dropped → `Test.Msg.Catalog` red at row 1.
- AC4: `RenderAt` treating a JSON-text `slots` as an object without parsing it → red at `TestNotificationHandoff`.
- AC5: one character of `Login.HELP` changed → `Test.Web.PublicTexts` red at the comparison. A new `Parameter` on `ApiBase` → red at the classification.
- AC6: `live_add_file "$tmp/compose.tz.yml"` removed → `live production` red at both DW-12 checks.
- AC7: Render's `channel` parameter renamed → `Test.Contract.Ac` red at `TestCrossLaneSignatures`.

**Review-pass pins (Rule 19; each applied, run red, reverted; `git status --short`, `git diff --stat` and the checksums of the five touched files were identical afterwards):**
- mutation: AC3, row 9 - the tier re-pick removed from `Catalog.Cost` -> `Test.Msg.Catalog` red at `TestCost` ("the cost 0.99996 shows as $1.00", "the cost 0.009996 shows as $0.010").
- mutation: AC3, row 10 - the empty check after the period strip removed from `Catalog.SlotText` -> `TestErrors` red (`cause`, `fixSummary` and `after` as a lone period).
- mutation: AC3, row 6 - `Catalog.Clean` back to its first list (no Unicode spaces, no zero-width characters) -> `TestStringSlots` red at string cases 8 and 9.
- mutation: AC3, row 10 - `Render` without its Try/Catch -> `TestErrors` red (`<UNDEFINED>` on the omitted channel).
- mutation: AC3, row 4 - the empty `now` of `ForMessage` defaulting to `utc` -> `Test.Data.Time` red at `TestForMessage` (the two new weekday cases; the older assertions stayed green).
- mutation: AC3, row 11 - the text of `incident.laterRequest` changed ("causes") -> `TestExtraSlots` red at "the later request renders the fixture's text" (and `TestEveryKeyOnEveryChannel`).

**Implement-stage results (October 19 and 20).**

*Task 0, DW-12 (measured in a throwaway of project tag `v09a` with the compose-level `TZ: America/New_York`, build 154 base image, arm64):*
- Each of the 30 alive item jobs of the production has `TZ=America/New_York` in `/proc/<job>/environ`. Every job id that the production lists is an operating-system process id, because each `/proc/<job>/environ` existed.
- The probe in the item's own production job (the row-21 `WatchOps` fixture's `OnInit`, jobs 3199 and 3201 in one run and 3213 and 3215 in another) recorded `Zone()` = `America/New_York`, `ToLocal("2026-01-15T17:00:00Z")` = `2026-01-15T12:00:00` (EST), `ToLocal("2026-07-15T16:00:00Z")` = `2026-07-15T12:00:00` (EDT) and `GetEnviron("TZ")` = `America/New_York`.
- Without the compose file (the AC6 mutation), the jobs have no `TZ` and the probe records `UTC`, `2026-01-15T17:00:00`, `2026-07-15T16:00:00` and an empty `TZ`. So a job inherits the container's zone from the environment and nothing else sets it. The contingency (HALT `blocked`, `intent gap`) does not apply.
- The unit ran three times with the file. The first run (before the catalog existed) failed two of its older checks, "another production: the step fails naming it and leaves it running" (the fixture production's `StopProduction(30)` returned an error) and "another production, Troubled or Suspended" (its IRIS session then printed nothing). The second run (the same script) and the final run (the finished tree) passed every check, and the same two checks passed in the run without the file. `(inference)` a timing flake of those two older checks under load, not a zone effect, because the same script passed twice with the zone set; it was not reproduced and is not explained.

*Commands run (slot A `ocutalon-slot-a`, namespace OCUTALON, build 154; throwaway tag `v09a`, `OCUTALON_LOCK_OWNER='epic=0 stage=implement'`):*
- `iris_doc_load` of `src/bridge/cls` (33 classes) and `src/ocutalon/cls` (163 classes) with flags `ck`: no error and no warning.
- `iris_execute_tests`, one class per call, all passing: `Test.Msg.Catalog` (13 tests, 1,430 assertions), `Test.Data.Time` (5), `Test.Web.PublicTexts` (2), `Test.Contract.Ac` (6, 47 signatures), `Test.Web.SignIn` (9), `Test.Web.Status` (7), `Test.Msg.Contracts` (6), `Test.Data.PublicSettings` (5).
- `bash ci/checks.sh`: exit 0 (all 12 scripts).
- `ci/iris.sh build`: built. `ci/iris.sh live production`: exit 0 with the two DW-12 PASS lines. `ci/iris.sh shard lane-b`: exit 0, `SHARD lane-b passed (20 classes) 58s`, with `CLASS OcuTalon.Test.Msg.Catalog passed 0.67s` and `CLASS OcuTalon.Test.Web.PublicTexts passed 0.04s`. `ci/iris.sh teardown`: 0 projects, containers, volumes, networks and images of the tag left. The `(once)` lines were not run.

*Mutations (Rule 19; each applied, run red, reverted, and `git status --short`, `git diff --stat` and the file's checksum compared with their values before the mutation: byte-identical):*
- mutation: AC1 - `result.allThrough` removed from `Catalog.Watch` -> `Test.Msg.Catalog` red at `TestEntries` ("Watch holds exactly its 22 keys", "the keys with a gap are exactly the 9 listed") and at `TestEveryKeyOnEveryChannel`.
- mutation: AC2 - `RenderAt` always choosing `text` -> red at `TestEveryKeyOnEveryChannel` for the web fixtures of `incident.withFix`, `incident.laterRequest`, `answered.approved` and `answered.approvedBy`. The noun's forms swapped -> red at row 1 (every key with a noun), `TestNoun`, `TestStringSlots`, `TestExtraSlots` and `TestNotificationHandoff`.
- mutation: AC3 - the weekday window of `ForMessage` widened from 6 to 7 days -> `Test.Data.Time` red at `TestForMessage` ("seven days before", "seven days ahead"). The " ET" suffix dropped -> `Test.Msg.Catalog` red at row 1 for every key with a time, and at `TestTimesAndLocalInstall`, `TestRenderReadsClockAndFlag`, `TestGroups` and `TestCost`.
- mutation: AC4 - `RenderAt` taking JSON-text `slots` as the object without parsing -> `TestNotificationHandoff` red ("the slots must be a JSON object").
- mutation: AC5 - "lists" changed to "list" in `Login.HELP` -> `Test.Web.PublicTexts` red at `TestCopiesEqualTheCatalog`. A new `Parameter` on `ApiBase` -> red at `TestEveryParameterIsClassified` ("every own parameter is classified").
- mutation: AC6 - `live_add_file "$tmp/compose.tz.yml"` removed -> `live production` red at both DW-12 checks (30 jobs with no `TZ`; the probe in `UTC` with unconverted times); every other check green in that run.
- mutation: AC7 - the `channel` parameter of `Render` renamed -> `Test.Contract.Ac` red at `TestCrossLaneSignatures` ("Render takes (key,slots,channel,*sc) in that order").

**Review-stage results (October 19 and 20; patched tree).**
- Slot A (`ocutalon-slot-a`, build 154, namespace OCUTALON): both bases loaded with `ck`, no error or warning; `iris_execute_tests`, one class per call, all passing: `Test.Msg.Catalog` (13), `Test.Data.Time` (5), `Test.Web.PublicTexts` (2), `Test.Contract.Ac` (6), `Test.Web.SignIn` (9), `Test.Web.Status` (7), `Test.Msg.Contracts` (6), `Test.Data.PublicSettings` (5).
- `bash ci/checks.sh`: exit 0.
- Throwaway tag `v09a`, one stack at a time: `ci/iris.sh build` exit 0; `live production` exit 0 (23 PASS lines, both DW-12 lines, the probe in two item jobs at `America/New_York`, 12:00:00 in January and in July); `shard lane-b` exit 0 (20 classes, `Test.Msg.Catalog` 0.68 s, `Test.Web.PublicTexts` 0.04 s); `teardown` left nothing.
- The `(once)` lines: `shard lane-a` (9 classes), `shard lane-b --reverse` (20 classes) and `shard lane-a --reverse` (9 classes) all exit 0; the only SKIP is the existing `Install.Production.TestStepHelpers`; `teardown` left nothing of `-v09a-`.
- The catalog texts were also compared by script with the spec's key tables: 57 Core keys and 22 Watch keys, no difference.

**QA-stage results (October 20; slot A `ocutalon-slot-a` build 154, throwaway tag `v09q`; no new test class, so Rule 21's class counts stay).**

*Independent checks (a script outside the repo, reading EXPERIENCE.md and the two catalog classes' XData directly; the implement stage's Fixtures were not used for the texts).*
- Texts: the UX regions read were L79, L126-128, L176-191, L316, L340, L360, L659-685 and L687-842. Of the 79 entries, 61 equal a quoted UX string (or, for the two-line tell-now notice, its two quoted lines) once the placeholders are spelled as the UX spells them (`{itemNoun}` as `{item noun}`, `{readmeLink}` as `{README link}`, and so on); 10 equal a UX string that carries concrete values (the six results, `answered.approvedBy`'s page wording against "Approved by sam from the web chat at 14:15", `answered.alreadyApproved` against "Already answered: approved from Telegram at 14:15.", and the two Orders-production notices, where `{production}` is the Rule 22 ruling); the five incident notices equal the UX code blocks as a whole, blank lines and the closing line included (`incident.noFixUnknown` against the no-fix block with the unknown-cause first line); and 3 are composed (next bullet). The 11 fallback reasons, the 9 banner texts and the 4 banner actions equal the UX's, and the `web` texts equal the UX's page wording. The only characters beyond ASCII in the catalog are U+2026 (`banner.reconnecting`) and U+00B7 (`signIn.title`), the same two characters that the matched UX strings carry.
- Three keys have no verbatim UX quote, and none changes an AC: `answered.rejectedBy` is composed from "Rejected from {channel} at {time}. Nothing was changed." and Formats > Who answered (the UX gives only the approved example); `checks.notEverythingRestPassed` joins the UX's two sentences with one space; `signIn.submit` is the UX's bold **Sign in**, not a quoted string. See Issues Encountered for the first.
- Runtime: the SHA-1 of the UTF-8 text of "key, text, web" for all 79 keys read through `Entry()` on slot A equals the one of the XData parsed from the files (8,520 characters, 8,523 bytes).
- Key sets: the Core and Watch lists parsed from this spec's Tasks section equal the classes' keys (57 and 22, no difference), no prefix is in both classes, and the keys with a `gap` are the 9 listed.

*Tests added (QA), all in existing classes, so they are in `lane-b` already (Rule 8).*
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` (QA): `TestWebWording` (exactly four web wordings, derived by rule), `TestTypography` (the characters of every text), `TestNounForms` (counts 0, 1, 2, 3, 10 and 50 for the 12 keys with a noun), `TestChannelNames` (near-miss channel spellings), `TestStringSlotSweep` (104 code points from the new XData `Characters`, which covers every BMP character of Cc, Zs, Zl and Zp), `TestEverySlotIsValidated` (every declared slot of every key: missing, null and a wrong form), `TestLocalInstallEveryKey` (no " ET" on any key when the flag is 0) and `TestGroupsCannotInject`.
- `src/ocutalon/cls/OcuTalon/Test/Data/Time.cls` (QA): `TestForMessageNames` (7 weekdays, 12 months, EST and EDT by month), `TestForMessageDaylightSaving` (the 23-hour and 25-hour days, the repeated hour, now keeping its own offset) and `TestForMessageOtherZone` (Asia/Kolkata); one case was added to the last-but-one test for the spring midnight crossing.

*Commands (QA).*
- `iris_doc_load` of both bases with `ck`: no error or warning. `iris_execute_tests`, one class per call, all passing: `Test.Msg.Catalog` (21 tests), `Test.Data.Time` (8), `Test.Web.PublicTexts` (2), `Test.Contract.Ac` (6), `Test.Web.SignIn` (9), `Test.Web.Status` (7), `Test.Msg.Contracts` (6), `Test.Data.PublicSettings` (5).
- `bash ci/checks.sh`: exit 0 (after the test edits).
- Throwaway tag `v09q`, one stack at a time: `ci/iris.sh build` exit 0; `live production` (unmutated) exit 0 with 23 PASS lines and both DW-12 lines; `shard lane-b` exit 0 (20 classes, `Test.Msg.Catalog` 1.90 s) and `shard lane-b --reverse` exit 0 (20 classes); `teardown` left nothing.

*Mutations (Rule 19; each applied, run red, reverted; `git status --short`, `git diff --stat` and the checksums of the touched files were identical afterwards). "Older tests green" means every test before the QA stage stayed green for that mutation.*
- mutation: AC1 - `"web"` added to `answered.expired` in `Catalog.Core`, equal to its text -> `Test.Msg.Catalog` red at `TestWebWording` ("exactly four catalog entries have a web wording"); older tests green.
- mutation: AC1 - the apostrophe of `pairing.notPaired` written as `\u2019` in `Catalog.Core` -> red at `TestTypography` (and at `TestEveryKeyOnEveryChannel`, `TestLocalInstallEveryKey`).
- mutation: AC2 - `Catalog.Build` compares the channel in lower case, so "WEB" renders -> red at `TestChannelNames` ("WEB", "Web", "Telegram" and "MAILBOX"); older tests green.
- mutation: AC3, row 5 - the count 2 takes the singular -> red at `TestNounForms` (all 12 keys with a noun at count 2); `TestNoun` green.
- mutation: AC3, row 6 - U+2000 to U+200A removed from `Catalog.Clean`'s space list -> red at `TestStringSlotSweep` (11 code points, four assertions each); older tests red only for U+2003.
- mutation: AC3, row 10 - an empty `readmeLink` accepted -> red at `TestEverySlotIsValidated` (`conversation.dailyCap`, `conversation.sessionAllowance`, `watch.onlyOrders`); `TestErrors` green.
- mutation: AC3, row 3 - `Build` forces the online-demo flag on for `banner.heartbeatStalled` -> red at `TestLocalInstallEveryKey` (that key, on both channels); older tests green.
- mutation: AC3, row 7 - `Groups` fills its lines by chained replacement instead of `Fill` -> red at `TestGroupsCannotInject` (line injection and the braces) and at `TestGroups`.
- mutation: AC3, row 4 - `WEEKDAYS` "Tuesday" changed to "Tues" and `MONTHS` "Sep" to "Sept" -> `Test.Data.Time` red at `TestForMessageNames` (October 13, October 20 and the 3rd of month 9); `TestForMessage` green.
- mutation: AC3, row 4 - `ForMessage` sets the zone to America/New_York itself -> red at `TestForMessageOtherZone` (all three assertions); older tests green.
- mutation: AC3, row 4 - `ForMessage` takes the local date of `now` with the offset of `utc` -> red at `TestForMessageDaylightSaving` (the spring midnight crossing, the 25-hour day and the repeated hour); `TestForMessage` green.
- mutation: AC4 - `Render` passes 0 for the online-demo flag -> red at `TestRenderReadsClockAndFlag` ("ET is present exactly when the flag is 1"); every other test green.
- mutation: AC4 - `Render` uses the fixed clock 2026-10-16T18:20:00Z -> red at `TestRenderReadsClockAndFlag` ("Render equals RenderAt for the clock and the flag 1" and "0").
- mutation: AC5 - the catalog text of `signIn.logoAlt` changed to "OcuTalon logo" -> `Test.Web.PublicTexts` red at `TestCopiesEqualTheCatalog` ("Login.LOGOALT equals the catalog key signIn.logoAlt"), so a changed catalog text turns it red, not only a changed copy.
- mutation: AC6 - `live_add_file "$tmp/compose.tz.yml"` removed from `test-production.sh` -> `ci/iris.sh live production` red at both DW-12 checks (30 jobs read with no `TZ`; the probe in `UTC` with 2026-01-15T17:00:00 and 2026-07-15T16:00:00); the other 21 checks passed in that run.
- mutation: AC7 - `Catalog.Entry` declared `As %String` -> `Test.Contract.Ac` red at `TestCrossLaneSignatures` ("OcuTalon.Msg.Catalog.Entry returns %DynamicObject").

*CI of `2ba8fe8` (QA read; `headSha` 2ba8fe8437b3f6e1b937b3c9b0bb0da7cd372e0d on both runs).*
- `lane-a` 39374739501: success (`standalone-bridge`).
- `ci` 39374739457: failure, 27 min 20 s from creation to the last job. `checks`, `web`, `iris (shards)`, `iris (browser)`, `iris (image)` and `iris (install)` passed; `iris (production)` failed in `live:production` (272 s).
  - Both DW-12 checks passed there ("each of the 30 alive item jobs holds TZ=America/New_York", and the probe at `America/New_York`, 12:00:00 in January and in July). The two failures are the same two older checks that the implement stage saw once: "another production: the step fails naming it and leaves it running" (`StopProduction(30)` of `ZzOther.Production` returned an error after 30.5 s) and "another production, Troubled or Suspended" (the session then printed nothing).
  - In the previous run on the runner (`fcdd9e9`, run 39359136309) the same two checks took under 1.5 s together. Here the stop began at 05:34:10, 14 s after the `iris (image)` job started its build and stack on the same host. `Ens.Director.StopProduction` has two 30-second waits (the runtime lock and `MakeQuiescent`), and neither reads the time zone `(inference)`.
  - Not reproduced locally: three further QA runs of `live production` with the compose `TZ` passed (23 PASS each). With the zone set, 6 of 8 runs of this story passed (the two failures are the implement stage's first run and this CI run); without it, no run of this story failed, and the two earlier CI runs of the unit on the runner passed. That is not enough to link the failure to the zone, and the cause is not shown to be in this story's files, so nothing was patched. This is the second occurrence of one flake (`occurrence=2`), for the lead's Rule 22.7 ledger entry and rerun.

**Code-review results (October 20; slot A `ocutalon-slot-a`, build 154, port 52790, namespace OCUTALON; throwaway tag `v09r`, `OCUTALON_LOCK_OWNER='epic=0 stage=code-review'`).**
- CI: the rerun of `iris (production)` (run 39374739457, attempt 2, job 118478932947) failed the same two checks, the block taking 30.47 s with no other job on the host. Cause and patch: Review Findings, first line.
- DW-28 experiment (a script outside the repo that sources `docker/tests/lib-live.sh`; one stack at a time, each removed by its trap): `StartProduction("ZzOther.Production")`, the refused `Production.Start(15)`, `GetProductionStatus`, then `StopProduction(5)`, 15 times each: with `TZ: America/New_York` 5 failures (`ErrJobsNotStopped` naming the `Ens.ScheduleHandler` job, or `ErrProductionNotQuiescent`), without `TZ` 3 failures, and with the patch's wait first 0 failures (the wait ended after about 0.1 s each time).
- `iris_doc_load` of `src/ocutalon/cls` with `ck`: 163 classes, no error or warning. `iris_execute_tests`, one class per call, all passing: `Test.Msg.Catalog` (21), `Test.Web.PublicTexts` (2), `Test.Web.Status` (7), `Test.Data.Time` (8), `Test.Contract.Ac` (6), `Test.Web.SignIn` (9), `Test.Msg.Contracts` (6), `Test.Data.PublicSettings` (5).
- `bash ci/checks.sh`: exit 0. `ci/iris.sh build`, then `ci/iris.sh live production` twice: exit 0 each, 23 PASS, the "another production" block with 8 values; `ci/iris.sh teardown`: nothing of `-v09r-` left.
- Mutations (Rule 19; each applied, the named test run alone on slot A, reverted; the checksums of `Msg/Catalog.cls`, `Msg/Catalog/Core.cls` and `Web/Public/ApiBase.cls`, `git status --short` and `git diff --stat` were identical afterwards, and the clean tree was reloaded and rerun green):
  - mutation: AC3, row 6 - the `ended` line removed from `Catalog.SlotText` -> `TestStringSlots` red (string case 6, and the reminders ending with U+003F, U+0021 and U+2026).
  - mutation: AC3, row 6 - 1564 (U+061C) removed from `Catalog.Clean`'s list -> `TestStringSlotSweep` red at U+61C (in the middle, repeated, at both ends).
  - mutation: AC4 - `If now = "" Set now = NowUtc()` removed from `Catalog.Build` -> `TestRenderReadsClockAndFlag` red ("RenderAt with an empty clock succeeds", "uses the current time", for both flags).
  - mutation: AC1 - `source` removed from `audit.recorded` in `Catalog.Core` -> `TestEntries` red ("audit.recorded is well formed: the source is missing").
  - mutation: AC3, row 8 - `invalid=generic` changed to `invalid=error` in `REASONKEYS` -> `TestEnumeratedSlots` red ("invalid gives its text").
  - mutation: AC5 - a new `Parameter ZZMUTATION` on `ApiBase`, with the classes now from `Test.Web.Status.PublicClasses` -> `TestEveryParameterIsClassified` red ("every own parameter is classified").
  - The DW-28 wait has no single-run mutation, because the race it removes is not deterministic; the experiment above is its evidence (5 of 15 without the wait, 0 of 15 with it).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The message catalog and its one renderer are in place, and DW-12 is measured and pinned.
- `OcuTalon.Msg.Catalog` renders any of the 79 keys on `web`, `phone`, `mailbox` and `telegram` through `Render` and `RenderAt`, reads the two catalog classes through `Entry` on every call, and returns the whole text or `""` with a plain-English error status.
- `OcuTalon.Msg.Catalog.Core` (57 keys) and `.Watch` (22 keys) hold the texts as XData, with the nine gapped keys marked.
- `Data.Time.ForMessage` formats message times by the local date.
- `Test.Web.PublicTexts` compares the public package's eight sign-in copies with the catalog and classifies all 29 own parameters.
- `test-production.sh` starts its stack with `TZ: America/New_York` and checks that every item job holds it and that the item's own production job converts in it. Task 0 found that a production job inherits the container's zone, so the DW-12 contingency did not apply.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls`, `Msg/Catalog/Core.cls`, `Msg/Catalog/Watch.cls`: new, the renderer and the two catalogs.
- `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `ForMessage` and the English day and month names.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`, `Test/Web/PublicTexts.cls`: new tests; `Test/Data/Time.cls` (`TestForMessage`) and `Test/Contract/Ac.cls` (four signatures, floor 47): extended.
- `docker/tests/test-production.sh`: the compose-level `TZ`, the `/proc/<job>/environ` check and the time probe in row 21's fixture.
- `_bmad/custom/skill-rules.md`: Rule 21's class count, 29 classes (9 in `lane-a`, 20 in `lane-b`).
- This spec: the Spec Change Log, the Review Triage Log, the Verification results and the mutation lines.

**Review findings.** 35 findings from four layers: high 0, medium 5, low 29, false 1.
- Patched (10 findings, which are 6 root causes: 3 medium and 3 low; the fixes are in `Catalog.Cost`, `Catalog.SlotText`, `Catalog.Clean`, `Catalog.Render`, `Test.Data.Time.TestForMessage` and `Test.Msg.Catalog`):
  - a string slot that is only a period no longer renders blank (it is an error), medium;
  - the empty-`now` default of `ForMessage` is now pinned, medium;
  - `TestExtraSlots` now asserts both renders, medium;
  - the cost tier follows the amount as shown ("$1.00" for 0.99996), low;
  - Unicode spaces, bidirectional controls and zero-width characters are cleaned from string slots, and `Render` never throws, low.
- Deferred: none (`deferred:` is empty).
- Rejected, each with its reason in the Review Triage Log: 25 findings (24 low and 1 false), among them these four, each with a one-line reason:
  - banner times as message times: fixed by the intent (row 2) and the Rule 22 ruling, so the fix would be a spec edit;
  - the length of a rendered text and the `sentence` "no time" rule: the producers, `ReplyGuard` and `TelegramOut` own them;
  - the lane coupling of `Test.Msg.Catalog`: the spec's Tests section requires the exact key sets;
  - Rule 21's old timing sentence: only the class count may change there.

**Follow-up review recommended: true.** Three medium entries were patched. The unverified risk: the patched `Catalog.Clean` code-point sets and `Catalog.Cost` re-pick are pinned by tests I wrote, and no independent reviewer has read the patched lines.

**Verification.** All `(loop)` and `(once)` lines are in the Verification section: slot A load and eight classes, `ci/checks.sh`, `live production` with both DW-12 lines, `shard lane-b`, the fresh-environment check of `lane-a` and `lane-b` forward and reverse, and the teardown, all green. Task 0's values and the mutation lines are there too.

**Residual risks.**
- Banner times with a `{time}` render as message times, while the UX says banner times are page times in the browser's zone. Story 2.10 decides how a banner gets its time; the Rule 22 ruling and its VETO WINDOW FYI are in the Design Notes.
- Nothing limits the length of a rendered text. A Telegram message is capped at 4,096 characters, so `TelegramOut` (Story 12.x) and the incident producers must keep notices under it, with `errorSummary` at the UX's 80 characters.
- Rule 21's sentence that every class takes under 0.4 s is out of date: `Test.Msg.Catalog` takes 0.68 s in the shard. Only the class count was allowed to change.
- The first live run with the zone set failed two older checks ("another production") once, and the same script passed in three further runs. `(inference)` a timing flake; not reproduced.
- `incident.laterRequest` declares no `cause` slot, because its text has no `{cause}`; a producer may still pass one, and it is ignored.
- The spine updates listed under "Spine updates for the lead" (AD-32, AD-29, AD-18, Conventions) are the lead's, per Rule 20.
