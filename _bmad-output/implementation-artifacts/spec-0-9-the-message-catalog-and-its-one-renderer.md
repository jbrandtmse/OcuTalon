---
title: 'Story 0.9: The message catalog and its one renderer'
type: 'feature'
created: '2026-10-19'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
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

## Spec Change Log

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
