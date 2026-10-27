# Epic 5 Context: OcuTalon watches a production and explains what broke

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

A user asks OcuTalon in plain words to watch a production. New failures are picked up within seconds, grouped by the settle rule into one diagnosed incident that moves through a fixed state table, and the heartbeat checks each watched production every minute and records what it found. All of that is built. The one remaining story, 5.7, makes the watch honest in the chat: asked "is everything fine?", OcuTalon answers only from the code-computed check results that 5.6 records, so the model can never give a false all-clear. This epic is the "what broke" half of the demo path, and Epic 7's approve-and-fix completes it.

## Stories

- Story 5.1: Ask OcuTalon to watch a production, and to stop
- Story 5.2: New failures are picked up within seconds
- Story 5.3: Same-cause failures become one incident by the settle rule
- Story 5.4: The diagnosis explains the cause from the failed messages
- Story 5.5: An incident moves through its states and closes
- Story 5.6: The production watch runs on every heartbeat
- Story 5.7: Asked whether everything is fine, OcuTalon never gives a false all-clear
- Story 5.8: Each noticed incident says what broke, with its evidence behind Show details
- Story 5.9: Ask OcuTalon in the chat to dismiss an incident

## Requirements & Constraints

**Code decides the all-clear**
- Code computes from the check results whether an all-clear may be given. The model can't add one.
- Reply cases, chosen only by `Checks.Render`:
  - Every check passed: "Everything I checked passed."
  - Something failed or wasn't checked: that entry comes first, as "Not everything: {what failed, with its time}." Then "Everything else I checked passed." follows, but only if other checks passed. Example: "Not everything: the Orders production has 50 failed orders since 14:12 ET, and a fix is waiting for your approval."
  - Nothing watched: "I'm not watching any productions yet, so I can't say. Ask me to watch one."
  - In every case, code-computed check rows follow, giving what was checked, the result and when.
- The guard removes two sets of wording from model text and keeps the rest:
  - the reserved sentences: "Everything I checked passed.", "Everything else I checked passed." and "Your IRIS system is healthy";
  - the closed list of banned phrases: "all good", "everything's fine", "everything is fine", "no issues", "no problems", "nothing to worry about".
- Required tests:
  - With Orders failing, "is everything OK?" gets no all-clear, and the failing check is named first.
  - A mock scenario under `ci/mock/scenarios/A/` has the model claim everything is fine while a check fails. The reply still has no all-clear.

**What 5.7 consumes from 5.6**
- Each production watch is one `OcuTalon.Data.BackgroundCheck` row owned by its session.
- `Checks` writes only the row's run fields: `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` and `NextDueAt`. `Result` is a `CheckResult` value: `passed`, `failed` or `not_checked`.
- How a run's result is decided:
  - `not_checked`, with a code-written reason, when any part can't be read;
  - otherwise `failed` when the production isn't running, when the session has new failures since the last run, or when an `open`, `awaiting_approval` or `fixing` incident is in scope (the session's own, plus `instance` incidents off the online demo);
  - otherwise `passed`.
- The finding is joined from `Checks` class parameters, with counts as its only slots. It never holds error, event-log or diagnosis text.
- (inference) The not-checked reason is stored in `Finding`, because no other run field holds text.
- (inference) A watch that has just started has no run yet. The spec decides how `check_status` reports it. Counting it as not checked matches the product's definition of "not checked" for a check that didn't run.

**Security**
- `check_status` is safe, read-only and trusted output, so calling it doesn't taint the turn.
  - Trusted output means code builds it from OcuTalon's own records, and it holds no text from outside a user's untainted turn.
  - 5.6's findings are code-written, so the rows stay trusted as long as no free text gets into them.
- Database row ids never leave the server. Only Ens header and session ids may, for trace links.
- (inference) `dismiss_incident` stays trusted output only while a `Test.Bridge.Gate` test pins its answer to its code-built fields (DW-288). A similar test for `check_status` would hold the same line, but no document requires one.

## Technical Decisions

**How results travel**
1. The Chat agent calls `check_status` in `OcuTalon.Tools`. It returns the session's latest results and puts them in the context's `HostData.checks`, a JSON array.
2. The runner copies `HostData` and the turn's taint onto the `Reply`.
3. `Conversation` (Lane B, Story 2.6) passes `HostData.checks` to `OcuTalon.Checks.Render` without reading it. After the guard has run, it puts the returned key and rows on the outbound reply and on `chat.message`.

- Tools may reference only `Msg`, `Data`, `Watch.Reader`, `Commands.Submit` and the bridge's shared classes, never `OcuTalon.Checks`. So `check_status` reads the `BackgroundCheck` rows itself. Core may call `Checks.Render`.
- (inference) A missing `HostData.checks` (the tool wasn't called) must stay distinct from an empty array (nothing is watched). Only the empty array gives the nothing-watched sentence.
- In Story 9.3, when the owner is `eval`, `check_status` reads the request's own `HostData` in place of the session's rows, and `EvalIn` calls `Render`. (inference) Keep the source of the results replaceable, so 9.3 can add that branch without reshaping the tool.

**`Checks.Render`**
- It keeps Epic 0's signature, `Render(results, *rows)`. `OcuTalon.Test.Contract.Ac`'s signature oracle pins that signature, and Lane A keeps the oracle green.
- It returns a catalog key plus rows `{result, entry, finding, checkedAt}`:
  - `result` is the enum value, because display words live only in the catalog and the web app;
  - `checkedAt` is UTC ISO 8601.
- Only `Render` chooses the reserved sentence. The sentences are catalog entries, which two places render:
  - the `*Out` operations, through `Msg.Catalog.Render`;
  - the page, from the generated `web/src/app/msg/catalog.ts`.
- **DW-90.** The keys `checks.notEverything` and `notEverythingRestPassed` take a whatFailed slot that the pinned signature can't return, so the page shows no sentence for them. 5.7 decides how the page gets whatFailed (derived from the failing row, or a slot path through `Render`) and makes both keys render.
  - Times travel as UTC ISO 8601 slots and are rendered only through `Data.Time`, which adds " ET" on the online demo. The renderer puts string slots into the text in a single pass and strips their line breaks.
  - (inference) So whatFailed's time should come from a time slot or from the row's `checkedAt`, not as text that is already rendered.
  - (inference) Each option reaches Lane B files:
    - A slot path changes the pinned signature and adds a property to `Conversation` and `chat.message`.
    - Deriving from the row changes only how the page renders, which is in `web/`.
    - Either way, Lane A asks the owning lane for the change and doesn't edit those files itself.

**`OcuTalon.Checks.ReplyGuard`**
- It extends `OcuTalon.Bridge.Ext.ReplyFilter` and replaces Epic 0's pass-through stub. `Decide`'s `ReplyFilterClass` setting already names it.
- It runs exactly once on every model-written text, before `Decide` records anything or answers its caller.
  - That includes each property a reply class lists in `FILTERED`, such as the diagnosis payload's, and `Decide` validates those again after filtering.
  - (inference) Whatever the guard strips has to leave that text valid.
- The legitimate all-clear arrives later, from `Render`'s key, so the guard can strip all all-clear wording without deleting a real one.
- (inference) The list of phrases is closed. Whether matching also covers case and punctuation variants is for the spec to decide.

**Conventions**
- Edit Lane A files only: `OcuTalon.Checks`, `.Tools`, `.Agent` and `ci/mock/scenarios/A/`.
  - Never edit Lane B files (`Core`, `Live`, `Msg`, `Web`, `web/`). Ask the owner for properties instead.
- Tool classes:
  - declare `CLASSIFICATION`, `READONLY`, `TRUSTEDOUTPUT`, `STEPLABEL` and `RESOURCES`, optionally `<NAME>`-suffixed;
  - take their names from `Tools.Names`;
  - return a dynamic object through `Tools.Result`, never a JSON string that is already encoded.
- Mock scenarios are one JSON file each: `name`; a `match` holding a `marker`; and `replies`, each with `text` or `toolUse`. A request picks one by `[[mock:<name>]]` in its newest user message.
- (inference) The model can call `check_status` only if it is in the Chat agent's toolset.
- Times are UTC ISO 8601 to the second. Tests are named `OcuTalon.Test.<Area>.<Subject>`.

## UX & Interaction Patterns

- Plain English, in the first person, with short sentences and no exclamation marks. No class names or codes outside Show details.
- A check row appears under any reply that answers whether things are fine. It shows:
  - a result icon and word: Passed in green, Failed in red, Not checked in amber;
  - the entry name;
  - the finding or reason with its time, in muted text.

## Cross-Story Dependencies

- **Done:** 5.1 to 5.6, 5.8 and 5.9.
  - 5.7 reads the rows that 5.6 records.
  - The incident states that make a check fail come from 5.5.
- **Upstream:**
  - Epic 0: the pinned `Checks.Render`, the `ReplyGuard` stub, `Bridge.Ext.ReplyFilter`, `Decide`'s `ReplyFilterClass` setting, `HostData` on the context and on the `Reply`, and the catalog keys.
  - Story 2.6: `Conversation` calls `Render`, `chat.message` carries the key and rows, and the page shows check rows.
  - Epic 3: the gate's classifications and taint.
- **Downstream:**
  - Story 9.3: the all-clear evaluation cases, through the `eval` branch.
  - Epic 17: the digest's all-clear and "Your IRIS system is healthy" also come from `Render`.
  - Epic 8: the page's check rows.
  - Story 30.4: finding Items.
