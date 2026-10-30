---
title: "Story 29.5: The address counter's hash is keyed per reset"
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: '115abb74e451d458b14ec4ffe43c11982f99924b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The online demo's per-address sign-in counter stores `Session.Hash(address)`, a plain SHA-256. All 2^32 IPv4 values can be tried in minutes, so a counter row, or the lock name built from it, gives the visitor's address back within the row's one-hour life (DW-233, kept by veto ruling U-156).

**Approach:** The counter stores and looks up `AddressCounter.AddressHash(address)`: an HMAC-SHA-256 of the address, keyed by a per-instance secret in the private database. The key's node holds the reset marker it was made for (the public `lastReset`, which the `Public` step writes from `OCUTALON_LAST_RESET` at every start). The key is made at its first use after a start whose marker differs from the node's. On the online demo that use is always a counted sign-in, never a start, so no golden copy holds a key. This is the owner's second option, "it lives outside what the golden copy captures" (Design Notes). A unit test walks two resets and gets two different keys. The live unit proves that a start and exempt sign-ins make no key, that the first counted sign-in makes one, and that a restart keeps it.

## Boundaries & Constraints

**Always:**
- The owner decision `epic29_brief` (DW-233, U-156) binds. It is quoted under Design Notes.
- The key is 32 bytes from `$SYSTEM.Encryption.GenCryptRand(32)`. It is kept only in `^OcuTalonP.AddrCountK` as `$ListBuild(marker, key)`, in the private database (AD-3's `OcuTalonP.*` mapping).
- Only the private class method `Key()` reads or writes the key. It is never written to output, a log, a status text, a message, a live event or the trace, and never put in a test description. Tests read the node and compare keys and hashes as values, with a fixed description and never a value in it (for example `$$$AssertTrue(k2 '= k1, "the first reset gives a new key")`), so neither is ever printed.
- `Recent`, `Add`, `Lock` and `Unlock` use `AddressHash`. With no key to be had (the key lock was not taken within 5 s, or `lastReset` could not be read), `AddressHash` is "" and the counter fails closed: `Lock` answers 0, `Add` answers an error that names no address, `Recent` answers 0, and no node is made. `Web.SessionEvents` keeps its existing "The address counter is busy" refusal.
- Rows and storage keep their form: `AddressHash` is 43 base64url characters without padding, in the existing `%String(MAXLEN = 128)` property. No storage, index or contract changes (AD-5, `Test.Data.Tables`).
- Every test added or changed creates and removes its own rows. A test that changes `lastReset` or the key node puts both back, whatever its outcome.
- Files under `docker/tests/` and `release/` stay ASCII. No tracked file holds a local path, host, address of a real host, or key.

**Never:**
- Connect to, configure or probe the demo host. Run `ocutalon-demo`, SSH or DNS commands. Applying this on the host is the Contest Planner's, after the epic lands.
- Edit `Install/**` (Epic 15's), `src/cpf/**`, `docker/merge.cpf`, `src/short-names.tsv`, `docs/**` or any other contended path. No new live unit, and no change to a CI group.
- Make the key at a start: no hook in `Data/Public/Settings.Set`, `Core/StatusMonitor` or the production (Design Notes, "Which option").
- Keep the key outside the private database (for example in IRISTEMP). A restart with the same marker must keep the key (AD-5).
- Migrate or rewrite existing SHA-256 rows. They stop matching and the hourly purge removes them.

## I/O & Edge-Case Matrix

`A` is a fixture address, and `Hmac(A)` is `AddressHash(A)` under the current key.

| # | Scenario | Input / State | Expected | Error handling |
|---|---|---|---|---|
| 1 | A counted row holds the HMAC (AC1) | `Add(A)`, or one proxied sign-in from A | One row whose `AddressHash` is `Hmac(A)`: 43 base64url characters, not `Session.Hash(A)`, not A. `Recent(A)` counts it. `Lock(A)` and `Unlock(A)` take and free the lock named by `Hmac(A)` | none |
| 2 | The limit is unchanged (AC1, integration) | Five counted sign-ins from A, then a sixth (`Test.Web.SessionEvents` `TestLimit`, live rows 10 and 11, and L1) | Five rows under `Hmac(A)`. The sixth is refused with the splash's field error and the oldest counted time plus one hour, as today | none |
| 3 | The key's home (AC2) | After any use | `^OcuTalonP.AddrCountK` is `$ListBuild(lastReset, <32 bytes>)`, with no subscripted node. It resolves to the private database. `Key` is a private method. Live, after the restart: no other node of OCUTALON_DATA, OCUTALON_PRIVATE or OCUTALON_PUBLIC holds the key, raw or base64url | Only counts and 1/0 are printed |
| 4 | Two resets, two keys (AC3) | `lastReset` T1 and no node (what a golden copy holds). Then a reset: the node is put back as it was captured at T1, and `lastReset` is T2. Again with T3. Then T4 with no node | Each reset gives a key that differs from every earlier one, and `Hmac(A)` differs each time. The row of A added at T1 does not count after the first reset. A second use at an unchanged marker keeps both the key and `Hmac(A)` | none |
| 5 | A start makes no key (AC4) | Live: the first start, the splash checks and row 12's six exempt sign-ins (the proxy address is one that no request comes from) | No key node | none |
| 6 | The first counted sign-in makes it (AC4) | Live phase 2: the node is removed, then the precondition's one proxied sign-in, as the demo account | The node exists, and its marker is the public `lastReset`. The precondition's row is under `Hmac`, and no row is under `Session.Hash` of that address | If the demo account cannot make the key, the sign-in writes no row and the existing precondition check fails |
| 7 | A restart keeps it (AC5) | Live row 13: a fixture row added before `dc stop`/`dc start` (the same `OCUTALON_LAST_RESET`) | After the restart, `Recent` counts it (1) and the node's marker still equals `lastReset` | none |
| 8 | No key can be made (AC6) | Another process holds the key lock, and no valid node exists | `Lock(A)` answers 0 after its 5 s wait, and no node is made. Once the lock is free, the next use makes the key | `AttachVisitor`'s existing "The address counter is busy": no session, row or cookie |
| 9 | Rows of the old form | A row stored as `Session.Hash(A)` (written before this change) | Not counted for A. The purge deletes it after an hour | none |

</intent-contract>

## Code Map

**The counter (the change)**
- `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls`:
  - :1-6, the class comment ("the SHA-256 of one client address (Session.Hash...)") states the contract and becomes stale;
  - :11 `DEFAULTGLOBAL`;
  - :27-44 `Recent` (its hash at :30);
  - :47-53 `Add` (:50);
  - :56-60 `Lock` (:58, `Lock +^OcuTalon.Data.AddressCounter(<hash>):5`);
  - :63-66 `Unlock` (:65);
  - :70-79 `Purge` (unchanged; it deletes old rows whatever their hash).
- `src/ocutalon/cls/OcuTalon/Data/Session.cls:122-125`: `Hash`, SHA-256 base64url, the sibling. It is unchanged, and resume references keep it.
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls`: `Get(key, .sc)` :19 and `Set(key, value)` :31. Read-only here.
- `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls:39-62` (read-only, contended): at every online-demo start it writes `lastReset` from `OCUTALON_LAST_RESET` through `Settings.Set`. That call is the one `TestKeyPerReset` makes to stand for a start.
- `src/ocutalon/cls/OcuTalon/Web/SessionEvents.cls:66-104` `AttachVisitor` (unchanged). It is the only caller of the counter with an address, in the proxied branch at :79-95: `Lock`, then `Recent`, then `Add`, then `Unlock`. An exempt sign-in (the probe, an operator) never calls the counter.
- `docker/merge.cpf:11` maps `OcuTalonP.*` to OCUTALON_PRIVATE (read-only), so `^OcuTalonP.AddrCountK` needs no mapping change. `Install/Step/PrivateData.cls` checks storage globals and samples only (read-only).

**Tests that compute the row hash today (all move to `AddressHash`)**
- `src/ocutalon/cls/OcuTalon/Test/Data/AddressCounter.cls`:
  - header :1-5;
  - `Session.Hash` at :37, :55, :65, :77, :83, :110, :132, :136-139 and in `Clean` at :208;
  - `TestAddStoresOnlyTheHash` :70-92;
  - `FreeInAnotherJob` and `Probe` :155-175, a job that runs `Lock(address)`;
  - `Row` :178;
  - `Clean` :194-212, which computes a hash for every run number times every case.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls`:
  - `CounterRows` :658, `OldestCounter` :674 and `DropCounter` :682, which build their hash with `Session.Hash`;
  - `TestLimit` :207, the consumer test;
  - `ReferenceHits(value, databases)` :563, which scans every node of the three databases for a value.
  - The resume-reference uses of `Session.Hash` (:99, :161, :198) stay.
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls:137-160`: `TestPurgeAddressCounter` builds its rows with `Session.Hash` at :141.
- `docker/tests/test-online-demo.sh` (the first-pass draft's line numbers have drifted by about 19):
  - `counter_rows` :585-590 (:587);
  - row 12 :600-620, where the first call with an address, `counter_rows "$a0"`, is at :617. It runs before the browser step (:751), and nothing before it computes an address hash (row 14 at :593 reads the limit setting only);
  - phase 2's precondition :812-822;
  - `aged` :847 and `oldest` :852;
  - `drop_counter` :961-963;
  - row 13, the restart, :1793-1821.
  - `check_session` and `session_value` are `lib-live.sh`'s.
- `web/e2e-online/address-limit.spec.ts`: L1 computes `sha256url(address)` in Node (:5, :23) for its count (:42) and its cleanup (:67).
- `web/e2e-online/support.ts:159-161`: `sha256url`. `resume.spec.ts` keeps using it. Its comment says "a reference or an address".

**Release check and CI**
- `release/demo-host-checks.md:56`: H17 (DW-233, "Story 29.5", pending).
- `docker/tests/test-online-host.sh:893-911`: pins that H1 to H24 appear once each, each with one of three statuses and none a pass, plus row 15's ASCII and host-detail scan (:866-872).
- `ci/units.sh:18`: shard `lane-b` holds the `Data` and `Web` areas. `live:online-demo` is in `install-upgrade` (:39, 30.9 min).

**Measured (Task 0, slot C, build 154U, OCUTALON, 2026-10-30; no node was made, and no random value was printed):**
- `$SYSTEM.Encryption.HMACSHA(256, text, key)` gives 32 bytes and matches RFC 4231 test case 2.
- `GenCryptRand(32)` gives 32 characters, all below 256, and two calls differ.
- `$Translate($SYSTEM.Encryption.Base64Encode(mac, 1), "+/=", "-_")` is 43 characters with no `=`. It differs across keys, differs from `Session.Hash`, and is the same on a second call.
- `^OcuTalonP.AddrCountK` resolves where `^OcuTalonP.Zz` does (the private database), and does not exist yet.
- Not measured here (inference):
  - The golden copy is the whole durable volume (AD-25's text). The host is owner-only.
  - The demo account can write `^OcuTalonP.AddrCountK`, as it writes `^OcuTalonP.AddrCountD` in the same database. Matrix row 6 proves it live.
  - A start clears IRISTEMP. Only AC5's mutation relies on this.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls`:
  - Add `Parameter KEYGLOBAL = "^OcuTalonP.AddrCountK"`.
  - Add the public `AddressHash(address)`: base64url without padding (Session.Hash's encoding) of `$SYSTEM.Encryption.HMACSHA(256, $ZConvert(address, "O", "UTF8"), ..Key())`; "" when `Key()` is "".
  - Add the private `Key()`:
    1. Read `marker = Settings.Get("lastReset", .sc)`. On an error, answer "".
    2. A node that is a 2-element list with this marker and a 32-byte key answers that key, with no lock.
    3. Otherwise take `Lock +` the key global for at most 5 s. On a timeout, answer "".
    4. Read the node again. If it is still not valid, set it to `$ListBuild(marker, GenCryptRand(32))`.
    5. Release the lock and answer the key.
  - `Recent`, `Add`, `Lock` and `Unlock` use `AddressHash`, with the "" rules of Always. A failed `Add` answers `$SYSTEM.Status.Error(5001, "The address counter has no key")`.
  - Rewrite the class comment as the contract: the HMAC, where the key lives, when it is made, and why no golden copy holds it.
- `src/ocutalon/cls/OcuTalon/Test/Data/AddressCounter.cls`: every hash becomes `AddressHash`. Then:
  - `TestAddStoresOnlyTheHash` adds that the stored hash is not `Session.Hash(address)`.
  - `TestRecentWindow` adds row 9 (a `Session.Hash` row of the address is not counted).
  - `Clean` computes each fixture's `AddressHash` and `Session.Hash` once, uppercased, into a local set, and deletes every row whose uppercased hash is in it. That covers rows from before this change.
  - New `TestKeyIsPrivate` (matrix row 3): the parameter's value; it resolves where `^OcuTalonP.Zz` does; after a use, the node is a 2-element list whose marker is `lastReset` and whose key is 32 bytes, with no subscripted node; and `%Dictionary.CompiledMethod` `OcuTalon.Data.AddressCounter||Key` has `Private` 1.
  - New `TestKeyPerReset` (matrix row 4): it saves `lastReset` and the node (`$Data` and value) first, and puts both back and deletes its rows by id in all paths. Fixture markers are T1 to T4 (`2026-01-01T00:00:00Z`, then 04, 08 and 12 hours). It asserts the keys and hashes pairwise different, and the same marker keeping both. The T1 row does not count after the first reset.
  - New `TestKeyBusyFailsClosed` (matrix row 8): it saves and removes the node, takes `Lock +` the key global itself, and expects `FreeInAnotherJob(A)` to be 0 with still no node. It releases the lock and expects `FreeInAnotherJob(A)` to be 1 with a node. Then it puts the saved node back. The lock is released and the node restored in all paths.
  - Update the header comment.
- `src/ocutalon/cls/OcuTalon/Test/Web/SessionEvents.cls`: `CounterRows`, `OldestCounter` and `DropCounter` use `AddressHash`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls:141`: `AddressHash`.
- `docker/tests/test-online-demo.sh`:
  - (a) The counter's hash is `##class(OcuTalon.Data.AddressCounter).AddressHash(...)` at :587, :847, :852 and :962.
  - (b) Row 12 (matrix row 5): before :617's first `counter_rows "$a0"`, one `check_session` prints `CHK|key|0`. It reads the node through `#KEYGLOBAL`, as `$Data`.
  - (c) Phase 2 (matrix row 6): before the precondition's sign-in, the node is killed, since row 12's lookups made one. After the sign-in, besides the existing row check, one `check_session` prints:
    - `CHK|key|1` (`$Data` of the node);
    - `CHK|marker|1` (the node's marker equals `Settings.Get("lastReset")`);
    - `CHK|sha|0` (the rows under `Session.Hash` of the precondition's address).
  - (d) Row 13 (matrix rows 7 and 3):
    - Before `dc stop iris`, `AddressCounter.Add("zz-row13-restart")` prints `CHK|added|1`.
    - After the restart, it prints `CHK|counted|1` (`Recent`), `CHK|marker|1`, `CHK|raw|1` and `CHK|b64|0`, then drops the fixture rows. `raw` is `Test.Web.SessionEvents.ReferenceHits` of the key: its own node only. `b64` is the same for the key's base64url.
  - (e) The header comment names the new checks. It names no key.
  - Nothing else in the unit writes `lastReset`.
- `web/e2e-online/address-limit.spec.ts`: L1's count and cleanup scripts use `##class(OcuTalon.Data.AddressCounter).AddressHash(${quoted(address)})` inside IRIS. `sha256url` and its import go from this file.
- `web/e2e-online/support.ts:159`: the comment says it is the form of a resume reference only.
- `release/demo-host-checks.md`, H17's "The Planner's check" cell: after "Runs before and after a reset show a new `lastReset`", add: "At the release's update, before IRIS stops for the capture, `Write $Data(^OcuTalonP.AddrCountK)` in a terminal of the updated instance prints 0: the golden copy holds no address key (Story 29.5). The terminal takes a licence unit, so never at the cap (DW-287)." Its status stays `pending`.

**Acceptance Criteria:**
- AC1: Given the online demo's counter, when a counted sign-in stores or looks up a client address, then the row and the lock name hold `AddressHash` (43 base64url characters, not the SHA-256, not the address), and the five-an-hour limit refuses the sixth exactly as before (matrix rows 1, 2 and 9). Integration: `Web.SessionEvents.AttachVisitor` consumes it in `TestLimit` and in the live unit's rows 10 and 11 and L1.
- AC2: Given any use of the key, when its home is inspected, then it lives only in `^OcuTalonP.AddrCountK` in the private database, only the private `Key()` reaches it, and after the live unit's run no other node of the three databases holds it, raw or base64url (matrix row 3).
- AC3: Given two resets (the node as a golden copy holds it, and a new `lastReset` written as the `Public` step writes it), when the counter is used after each, then the two resets give two different keys and two different hashes of one address, and a row from before a reset no longer counts (matrix row 4).
- AC4: Given the live online-demo start, when the start, the splash checks and the exempt sign-ins have run, then no key exists; and when the demo account's first counted sign-in runs, then it makes the key with the start's `lastReset` as its marker (matrix rows 5 and 6).
- AC5: Given a counted row and a restart with the same `OCUTALON_LAST_RESET`, when the counter is read after the restart, then the row still counts and the key is unchanged (matrix row 7).
- AC6: Given the key lock held elsewhere and no valid key, when `Lock(A)` runs, then it answers 0 within its wait and makes no key (matrix row 8).

## Spec Change Log

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 29 findings - high 0, medium 8, low 17, false 4, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind Hunter: an unset `lastReset` is a valid marker "" - real only off the online demo (the `Public` step requires `OCUTALON_LAST_RESET` as a time at every online start); the golden copy still holds no key, so the reset renews it; refusing "" would force every counter test to set `lastReset`, more than a direct correction.
  - `[medium]` `[patch]` Blind Hunter: Add, Recent and Unlock with no key have no test - `TestKeyBusyFailsClosed` now runs `ClosedInAnotherJob` (Add answers an error that names no address and writes no row, Recent 0, Unlock raises nothing, still no node); mutation recorded.
  - `[medium]` `[patch]` Blind Hunter: nothing ties `AddressHash` to the key - `TestAddStoresOnlyTheHash` compares the stored hash with an independent HMAC under the node's key; mutation recorded.
  - `[low]` `[reject]` Blind Hunter: Lock and Unlock each derive the lock name - the key changes only at a start, which ends every process and lock, so the two names cannot differ within one run.
  - `[low]` `[patch]` Blind Hunter: `Clean` null subscript, cost and stale rows - the null subscript is real (a row with an empty hash, which the AC6 mutation left, made `Clean` raise); `Clean` now skips an empty hash and deletes rows with none. Cost (microseconds per hash, n in the tens) and rows of an aborted run (removed by the hourly purge) are not worth more.
  - `[low]` `[patch]` Blind Hunter: H17 names no namespace - the check now says namespace OCUTALON. The note about a key captured off procedure is already Design Notes' marker guard.
  - `[false]` `[reject]` Blind Hunter: `^OcuTalonP.AddrCountK` is missing from `src/short-names.tsv` - the registry has one row per class and the key global sits under `AddrCount`'s prefix (Design Notes, AD-3); the spine's AD-3 wording is the lead's call (Rule 20).
  - `[medium]` `[patch]` Blind Hunter: live checks unproven, the phase 2 kill unchecked, a boundary flake and a leftover row - the live unit ran green and both live mutations went red (rows 12 and 13); the kill is now a `check_session` that prints `CHK|key|0`; a restart keeps the environment, so no boundary is crossed; the row-13 fixture lives in a throwaway.
  - `[low]` `[reject]` Edge Case Hunter: Unlock may release another name - same root cause as the Lock and Unlock finding above.
  - `[low]` `[reject]` Edge Case Hunter: Recent answers 0 after Lock when Key then fails, so a session row is left - Lock succeeding proves a valid key, and Key fails afterwards only if `lastReset` becomes unreadable, which it cannot at run time.
  - `[low]` `[reject]` Edge Case Hunter: an unset `lastReset` gives a non-renewing key - same as the first finding.
  - `[low]` `[reject]` Edge Case Hunter: the `Key()` catch is silent - the live phase 2 proves the demo account makes the key; a log line would add public surface the spec does not ask for.
  - `[medium]` `[patch]` Edge Case Hunter: the phase 2 kill is unchecked - same fix as above.
  - `[false]` `[reject]` Edge Case Hunter: row 13's `Recent` runs first and may renew the key - a renewal would leave the row under the old key, so `CHK|counted|1` would be 0; the AC5 mutation went red there.
  - `[low]` `[patch]` Edge Case Hunter: H17 needs a namespace - same fix as above.
  - `[low]` `[reject]` Edge Case Hunter (claim): Recent 0 reads as under the limit when the key is lost mid-request - same as the second finding.
  - `[low]` `[reject]` Edge Case Hunter (claim): an unreadable `lastReset` - same as the first finding.
  - `[medium]` `[patch]` Verification Gap: the lock name is never observed - new `TestLockNameIsTheKeyedHash` (a second job cannot take the lock named by `AddressHash` while `Lock` is held, and takes the one named by the SHA-256); mutation recorded.
  - `[medium]` `[patch]` Verification Gap: the in-lock re-read has no test (filed as a defer) - new `TestKeyMadeOnceUnderContention` (a job waits on the key lock, the test stores a key and releases, the job must keep it); mutation recorded.
  - `[medium]` `[patch]` Verification Gap: the fail-closed branches of Add, Recent and Unlock - same fix as the second finding.
  - `[medium]` `[patch]` Verification Gap: the phase 2 removal is unchecked - same fix as above.
  - `[low]` `[reject]` Verification Gap: the first assertion of `TestKeyBusyFailsClosed` also holds if the probe never ran - the later "= 1" pair and the node check fail in that case.
  - `[low]` `[patch]` Verification Gap: `Clean` null subscript - same fix as above.
  - `[low]` `[reject]` Verification Gap: `Clean` cannot delete rows of an earlier key - same as above (aborted runs only; purged within the hour).
  - `[low]` `[reject]` Verification Gap: `Clean` cost grows with the run number - same as above.
  - `[false]` `[reject]` Verification Gap: helper tests leave a key in place - nothing reads "no key" except the tests that set it themselves.
  - `[false]` `[reject]` Intent Alignment: the lifecycle claim (no key at start, one at the first counted sign-in, a restart keeps it) is proven only by the live unit - the live unit ran green (rows 12 and 13, phase 2) and went red under the two live mutations.
  - `[low]` `[reject]` Intent Alignment: a reset between Lock and Unlock - same as the Lock and Unlock finding.
  - `[low]` `[reject]` Intent Alignment: no `SessionEvents`-level test of the no-key case - `AttachVisitor` is unchanged and its refusal is the Lock-answers-0 case, pinned at the class level.

## Design Notes

**Owner decision for Epic 29** (`owner_decision id=epic29_brief`, 2026-10-30, decided by the Contest Planner under the owner's delegation; DW-233 is kept by veto ruling U-156). It binds, and is planned as given:
> **DW-233 (veto U-156, kept):** the address counter stores an HMAC of the client address, keyed by a per-instance secret in the private database and renewed at each reset, instead of a plain SHA-256. The key must never be in the golden copy: a reset restores the golden copy, so a stored key would come back unchanged after every reset. Either the key is made at start whenever the reset marker changes, or it lives outside what the golden copy captures. The spec names which one, and a test proves that two resets give two different keys.

**Which option: "it lives outside what the golden copy captures."** The key is in the private database while visitors are counted, but it is never in a golden copy, because of how the key is made and how the copy is captured:
- **What the golden copy captures.** AD-25 defines it. The first golden copy comes from a fresh install. Each release's update restores the current copy, starts it once on the new image "with no visitor data", waits for ready, stops IRIS and captures it.
- **When the key is made.** Only at its first use after a start whose `lastReset` differs from the node's marker. The only caller with an address is `AttachVisitor`'s proxied branch, which is a counted visitor sign-in. A start never makes a key, and neither does an exempt sign-in (the probe connects directly, AD-25).
- **So no golden copy holds a key, by induction.** The fresh install's copy has none. An update restores a copy with none, and its own start makes none. The key belongs to visitor-time state, like the counter rows, sessions and pairings. It goes away with each reset, and the first counted sign-in after the reset makes a new one: "renewed at each reset".
- **The marker is a second guard.** Suppose a copy were captured off procedure, for example after a proxied sign-in during an update. Its key's marker would be that start's `lastReset`, so the first use after the next reset (a new `lastReset`) replaces it. Matrix row 4 tests both cases, a copy with no key and a copy with one.
- **The repository proves the lifecycle.** AC4 shows that a start and exempt sign-ins make no key and that the first counted sign-in makes it. The host's capture itself is a release check: H17 has the Planner see `$Data` 0 at the update's capture.

**Why not "made at start".** The epic may change only two start paths: `Data/Public/Settings.Set` (the `Public` step's write of `lastReset`) and `Core/StatusMonitor` (a production service polled every 15 s, which can race that write). `Install/**` is contended. Both also run at the start that precedes a capture, so a key would be in every golden copy. "Never in the golden copy" would then hold only as "never used after a reset whose marker differs". Worse, AD-25's update starts from the new copy at the same reset boundary, presumably with the same `OCUTALON_LAST_RESET` (inference), so the captured key would be live until the next reset. Of the forms buildable here, the lazy one is the only one that keeps the key literally out of the copy.

**The surface of the "two resets" test.** As IRIS sees it, a reset is two things: the volume becomes the golden copy, and IRIS starts with a new `OCUTALON_LAST_RESET`, which the `Public` step writes through `Settings.Set("lastReset", ...)`. `TestKeyPerReset` makes the same write and puts the node back as a copy holds it, covering both cases. The live unit already pins that the start writes the variable as `lastReset` (rows 1 to 3). AC4 and AC5 run the real start path.

**Architecture decisions that govern this story (Rule 6):**
- AD-3: the private database, the `OcuTalonP.*` mapping, and `DEFAULTGLOBAL`. The key global sits under `AddrCount`'s prefix, so the registry needs no row (one row per class).
- AD-5: state survives restarts (AC5). Storage is untouched.
- AD-13: the counter "stores a hashed address with timestamps", which an HMAC still is. The client-address rule and the probe's exemption are unchanged.
- AD-19: `lastReset` is a start value. Its Prevents ("a key stored in IRIS") and its first Rule bullet concern model keys and bot tokens, which come from the environment. This key is generated inside IRIS and guards no external account. The owner's ruling U-156 puts it in the private database, and AD-19's Rule says nothing of generated secrets, so no AC contradicts it. The unattended non-negotiable "no key or token in IRIS" is read the same way, by that ruling.
- AD-25: the golden copy, resets and the probe.
- AD-27: the purge keeps one hour, so the old SHA-256 rows go within the hour.
- AD-22: tests, throwaways and CI groups.
- AD-29 and AD-33: Lane B's class. No new table, item or event type.

No AC contradicts an AD's Rule.

**For the lead (Rule 20; the spine is not written here):** the key's home (`^OcuTalonP.AddrCountK`, made lazily and per reset marker) may deserve one line under AD-19's fixed homes for secrets. That is the lead's call.

**Integration ACs (Rule 1).** `AddressHash` is a new public method of a shared class. In this story its consumer is `Web.SessionEvents.AttachVisitor`, through `Lock`, `Recent` and `Add`. AC1's integration clause runs it: `TestLimit`, and the live rows 10 and 11 and L1, against a real instance.
- **Consumed-by:** Story 29.7 (parked, U-163) may read counter rows through `AddressHash` in its load run; its plan decides. No other story yet.
- **Consumes:** Story 16.3's counter and sign-in hook; Story 16.1's `Public` step (`lastReset` at every start); Story 29.3's check list (H17).

**Extend, don't copy (Rule 2):**
- `AddressHash` repeats `Session.Hash`'s one-expression base64url encoding around a different primitive (an HMAC with a key, not a SHA-256). A shared encoder would change `Session.Hash`, which resume references rely on, for no behaviour gain, so the copy is the better choice.
- `TestKeyBusyFailsClosed` reuses `FreeInAnotherJob`.
- The live checks reuse `check_session`, `counter_rows` and `ReferenceHits`.

**Ledger inbox (Rule 17):** DW-233 is addressed by AC1 to AC6 and matrix rows 1 to 9. No residual.

**footprint_extensions:** none. Every file is in Epic 29's footprint: `Data/AddressCounter.cls`, `Test/Data/**`, `Test/Web/**`, `docker/tests/test-online-demo.sh`, `web/e2e-online/**`, and `release/demo-host-checks.md`, a `release/` file new in this epic (Story 29.3).

**Decided in-stage:**
9. (implement) The wait of `Key()` and `Lock` is a class parameter `WAIT` (5 s), so the key lock and the address lock name one number.
10. (implement) An unset `lastReset` is a marker like any other (""). The online demo's start always writes it, and the golden copy holds no key, so a reset still renews it.
11. (implement) MEASURED: `live online-demo` took 383 s (the 29.4 head: about 360 s) with the warm stack up beside it, and 378 s in the mutation run; the key scans together took about 0.5 s. `bash ci/checks.sh` 264 s. `shard lane-b@Data,Web` 148 s forward and 147 s reversed (28 classes). `Test.Data.AddressCounter` takes about 29 s (the busy case waits three times 5 s in its job, and the contention case 1.5 s).
1. The lazy key with a marker guard: the owner's second option, read by lifecycle (above).
2. HMAC-SHA-256, base64url without padding. It is 43 characters, as before, so the Tables contract and storage stay as they are.
3. The key global is a parameter of the class (`KEYGLOBAL`). Tests and the live unit read it through the parameter, so a mutation that moves it is followed and caught.
4. Fail closed. With no key, the counter refuses rather than counting nothing, so a lock timeout never lets a sign-in past the limit.
5. No migration of SHA-256 rows. They stop counting, which restarts an address's hour once, at the upgrade. On the demo host an update restores a copy with no rows anyway.
6. The "two resets" proof is a unit test (above). A live restart with a changed `OCUTALON_LAST_RESET` would recreate the container inside `install-upgrade` (30.9 min of REL-4's 35) and add nothing the unit test and AC4 and AC5 do not.
7. The key scans run once, after the restart, and print counts only. If the two scans together add more than 60 s locally, the implement stage keeps the raw scan only and records why here.
8. Like every private record, the key is in the private database's journal while the instance runs. The journal is on the durable volume and goes with it at each reset (inference: the journal's placement was not measured).

## Verification

Every call runs in the foreground with `timeout: 600000`, one test call per message, against named lane-C throwaways, never a slot. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`. A local live run that dies of its deadline with no failed check is that deadline: re-run it once with `OCUTALON_LIVE_DEADLINE=900` on the call.

**Commands:**
- (once, first) `LANE OCUTALON_RUN_TAG=e29s5iw bash ci/warm.sh up`. Expected: a warm stack (about 56 s).
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s5iw bash ci/iris.sh class OcuTalon.Test.Data.AddressCounter`. Expected: PASS, about 10 s (the busy case waits 5 s).
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s5iw bash ci/iris.sh class OcuTalon.Test.Web.SessionEvents`. Expected: PASS (`TestLimit` included).
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s5iw bash ci/iris.sh class OcuTalon.Test.Web.Install`. Expected: PASS.
- (once) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e29s5iw bash ci/iris.sh class OcuTalon.Test.Data.Tables`. Expected: PASS (contract and private records unchanged).
- (loop) `bash -n docker/tests/test-online-demo.sh`. Expected: no output.
- (once) `npm --prefix web run lint`. Expected: the e2e TypeScript compiles without `sha256url` in L1.
- (once) `LANE OCUTALON_RUN_TAG=e29s5i bash ci/iris.sh build`. Expected: the web bundle is built for the browser step.
- (once) `LANE OCUTALON_RUN_TAG=e29s5i bash ci/iris.sh live online-demo`. Expected: PASS with rows 12, 10, 11, 13, phase 2 and L1, and the new `CHK` lines as in Tasks. About 6 to 7 min (29.4 measured about 360 s). Record the extra seconds of the key checks as a MEASURED line.
- (once) `bash docker/tests/test-online-host.sh`. Expected: PASS (H17 present once and `pending`, ASCII, no host detail).
- (once) `grep -n 'Session).Hash' src/ocutalon/cls/OcuTalon/Data/AddressCounter.cls; grep -c sha256url web/e2e-online/address-limit.spec.ts`. Expected: no line, then `0`.
- (once) `bash ci/checks.sh`. Expected: every block passes (about 4 min).
- (once) `LANE OCUTALON_RUN_TAG=e29s5i bash ci/iris.sh shard lane-b@Data,Web`, then (once) the same with `--reverse`, one per call. Expected: PASS both times on fresh stacks (Rule 19, either order).
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s5iw bash ci/warm.sh down`, then `LANE OCUTALON_RUN_TAG=e29s5i bash ci/iris.sh teardown`. Expected: nothing tagged `e29s5i` or `e29s5iw` is left.

**Shared surfaces:**
- The hash form of counter rows, in every test that reads or writes them by hash: `Test.Data.AddressCounter`, `Test.Web.SessionEvents` (`CounterRows`, `OldestCounter`, `DropCounter`), `Test.Web.Install` (`TestPurgeAddressCounter`), `test-online-demo.sh` (`counter_rows`, `aged`, `oldest`, `drop_counter`) and `address-limit.spec.ts`. The implement stage searches `src/ocutalon/cls/OcuTalon/Test`, `docker/tests` and `web/e2e*` for `AddressCounter` and for `Session).Hash` next to it.
- The public `lastReset`. `TestKeyPerReset` writes it and puts it back; `Test.Web.Status` and `Test.Web.ResetSchedule` also write it, and touch no counter row.
- The key node (new).
- H17's row (`test-online-host.sh`).

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. Each creates its own rows and removes them, and the key tests save and restore `lastReset` and the node.

**Mutations (Rule 19), one per AC.** Apply each, observe red, revert, and confirm the tree byte-identical (`git status --short` and `git diff --stat` unchanged). Warm reds count only when the class is green again on the same stack after the revert.
- AC1: `AddressHash` returns `##class(OcuTalon.Data.Session).Hash(address)`. Red: `TestAddStoresOnlyTheHash` ("not the address's SHA-256"), on a warm class run.
- AC2: `Key()` also sets `^OcuTalonP.AddrCountK("copy")` to the key's base64url. Red: `TestKeyIsPrivate` ("no subscripted node"), on a warm class run. The live `CHK|b64|0` scan is a second guard and is not required to run against this mutation.
- AC3: `Key()` answers a stored 32-byte key whatever its marker. Red: `TestKeyPerReset` at the first reset ("a new key"), on a warm class run.
- AC4: `AttachVisitor` calls `##class(OcuTalon.Data.AddressCounter).AddressHash(address)` before its proxied branch, so an exempt sign-in makes a key. Red: `live online-demo` row 12 (`CHK|key|1`, wanted 0).
- AC5: `KEYGLOBAL` becomes `^IRIS.Temp.OcuTalonAddrCountK` (IRISTEMP, which a start clears; inference). Red: `live online-demo` row 13 (`CHK|counted|0`, wanted 1). `TestKeyIsPrivate` also goes red. AC4's and AC5's mutations may share one live run, since each turns a different row red. If either row stays green, run them apart.
- AC6: `Key()` ignores a lock timeout and makes the key anyway. Red: `TestKeyBusyFailsClosed` (`FreeInAnotherJob` answers 1, wanted 0), on a warm class run.
- mutation: AC1 applied on the warm stack (`AddressHash` returns `Session.Hash(address)`): red in `TestAddStoresOnlyTheHash` ("not the address's SHA-256"), also `TestRecentWindow` ("a row stored as the address's SHA-256 is not counted"), `TestKeyBusyFailsClosed` and `TestKeyPerReset`; reverted, the class green again on the same stack, the file byte-identical to its backup.
- mutation: AC2 applied (`Key()` also sets `^OcuTalonP.AddrCountK("copy")` to the key's base64url): red in `TestKeyIsPrivate` ("the node has no descendant, so no subscripted node holds the key") and `TestKeyBusyFailsClosed` ("and makes the key"); reverted, the class green again on the same stack, the file byte-identical.
- mutation: AC3 applied (`Key()` answers a stored 32-byte key whatever its marker): red in `TestKeyPerReset` at the first reset ("the first reset gives a new key", then the hash, marker and "the row of T1 no longer counts" lines); reverted, green again.
- mutation: AC6 applied (`Key()` ignores a lock timeout): red in `TestKeyBusyFailsClosed` ("Lock answers 0 while the key lock is held elsewhere", "and no node is made"); reverted, green again, and `git status --short` and `git diff --stat` unchanged by the mutation round.
- mutation: AC1 (lock name) applied: `Lock` names its lock by `Session.Hash(address)`; red in `TestLockNameIsTheKeyedHash` ("the lock named by AddressHash is held" and "the lock named by the plain SHA-256 is not"); reverted, green again.
- mutation: AC1 (HMAC under the key) applied: `AddressHash` keys the HMAC with the reversed key; red in `TestAddStoresOnlyTheHash` ("it is the HMAC-SHA-256 of the UTF-8 address under the node's key"); reverted, green again.
- mutation: AC3 (one key per reset under contention) applied: the in-lock re-read in `Key()` is removed; red in `TestKeyMadeOnceUnderContention` ("the job did not replace the stored key"); reverted, green again.
- mutation: AC6 (fail closed for `Add`) applied: `Add` has no no-key guard; red in `TestKeyBusyFailsClosed` ("Add answers an error" and "and writes no row"); reverted, green again, `git status --short` unchanged by the round.
- mutation: AC4 and AC5 applied together in one live run: `AttachVisitor` calls `AddressHash` before its proxied branch, and `KEYGLOBAL` is `^IRIS.Temp.OcuTalonAddrCountK`; red in `live online-demo` row 12 (`CHK|key|1`, wanted 0) for AC4, and in row 13 (`CHK|counted|0`, wanted 1; also `CHK|raw|0`) for AC5; reverted from backups, the tree byte-identical (`git status --short` and `git diff --stat` unchanged).

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-30, runner C, unattended).** Planned only; nothing implemented. The key is made lazily, at its first use after a start whose `lastReset` differs from the node's marker. That use is always a counted sign-in, so no golden copy holds a key: the owner's second option, "it lives outside what the golden copy captures", read by lifecycle (Design Notes, "Which option"). The marker guard renews even a key that a copy did hold. Task 0 on slot C (build 154U) measured HMACSHA(256) against RFC 4231, `GenCryptRand(32)`, the 43-character base64url form, and that `^OcuTalonP.AddrCountK` resolves to the private database. It made no node and printed no random value. No live unit or CI group is added; the live checks go into `live:online-demo`'s rows 12, 13 and phase 2. DW-233 is addressed by AC1 to AC6. footprint_extensions: none.

**Implement stage (2026-10-30, runner C, unattended).**
- Summary: `AddressCounter.AddressHash` is the HMAC-SHA-256 of the address under a 32-byte key in `^OcuTalonP.AddrCountK` (`$ListBuild(lastReset, key)`), made by the private `Key()` at its first use after a start with a new marker; `Recent`, `Add`, `Lock` and `Unlock` use it and fail closed with no key. Rows keep their form.
- Files: `Data/AddressCounter.cls` (the change); `Test/Data/AddressCounter.cls` (all hashes moved; new `TestKeyIsPrivate`, `TestKeyPerReset`, `TestKeyBusyFailsClosed`, `TestKeyMadeOnceUnderContention`, `TestLockNameIsTheKeyedHash`); `Test/Web/SessionEvents.cls` and `Test/Web/Install.cls` (hash helpers); `docker/tests/test-online-demo.sh` (rows 12 and 13, phase 2, header); `web/e2e-online/address-limit.spec.ts` and `support.ts` (L1 hashes inside IRIS); `release/demo-host-checks.md` (H17's check, status still `pending`).
- Review: 29 findings from four layers - high 0, medium 8, low 17, false 4. Patches applied: 8 medium (fail-closed Add/Recent/Unlock test, independent HMAC assertion, lock-name test, contention test for the in-lock re-read, the phase 2 key removal checked) and 3 low (`Clean` robust to an empty hash, H17 namespace). Deferred: none. Rejected with reasons: see the Review Triage Log (empty `lastReset`, Lock/Unlock name drift, a silent catch, `short-names.tsv`, and others).
- Follow-up review recommended: true. Patched medium entries: 8 (two or more). The unverified risk: the new tests of the contention case rely on a 1.5 s wait for the job to reach the key lock, and the busy case adds about 20 s to `Test.Data.AddressCounter`; a slow runner could make the contention case pass vacuously (never red falsely).
- Verification: warm classes `Test.Data.AddressCounter`, `Test.Web.SessionEvents` (`TestLimit` included), `Test.Web.Install`, `Test.Data.Tables` pass; `bash -n` and `npm --prefix web run lint` clean; `live online-demo` passes (rows 12, 10, 11, 13, phase 2, L1, the new `CHK` lines); `test-online-host.sh` and `ci/checks.sh` pass; `shard lane-b@Data,Web` passes forward and reversed on fresh stacks; the greps give no line and `0`. Every AC has a recorded mutation, applied and observed red (AC4 and AC5 together in one live run).
- Residual risks: the demo account's right to write and lock `^OcuTalonP.AddrCountK` is proven only on the throwaway (phase 2), not on the host; the host's capture check is H17, pending (the Contest Planner's). The lead may want one line under AD-19 for the key's home (Design Notes).
