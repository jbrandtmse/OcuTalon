---
title: 'Story 11.0: Epic 10 Deferred Cleanup'
type: 'refactor'
created: '2026-10-31'
status: 'done'
baseline_revision: '43379f1271aa66112da301117aa60521c9db7107'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Data.Pairing.HashCode` (Story 10.3) repeats `OcuTalon.Data.Session.Hash`'s SHA-256 base64url expression (Story 16.3) instead of calling it, so the release candidate carries two copies of one hash that could drift apart (DW-237, Rule 2).

**Approach:** `HashCode(code)` keeps its signature and its empty-code answer `""` and otherwise quits `##class(OcuTalon.Data.Session).Hash(code)`. The algorithm is the same, so every stored code hash keeps its value byte for byte and nothing is migrated.

## Boundaries & Constraints

**Always:**
- `HashCode` stays the one method both lanes hash a pairing code through (AD-4), with the parameter name `code` and return type `%String` that `Test.Contract.Ac`'s `TestCrossLaneSignatures` pins.
- `HashCode("")` and a call with no argument answer `""`. `Session.Hash("")` answers the hash of the empty string (`47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU`, measured on slot A), so the guard stays in `HashCode`.
- The doc comment states the contract (what the hash is, and that it is `Session.Hash`'s form), never the history (Rule 14).

**Never:**
- Change `OcuTalon.Data.Session` (its code or its doc comment), any stored property, index or `Storage` block, or any caller of `HashCode`.
- Unify other SHA-256 uses (`Core.Conversation`'s retry id, `Web.Public.Login`'s CSP hashes, `Install.Step.Users`' SHA-512). They are different forms.
- Run `Test.Data.PairingRows` or `Test.Web.PairingApi` on slot A. Their headers restrict them to throwaways and CI.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| ASCII code (DW-237) | `HashCode("abc")` | `ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0`, equal to `Session.Hash("abc")` | No error expected |
| 24-character code (DW-237) | `HashCode("Zz-ChatCode_0123456789AB")` | `6f9GcqltZ27RM9XPj-t2niXmYo5dK6Pj--zHN-ak6oM`, equal to `Session.Hash` of it | No error expected |
| Non-ASCII code | `HashCode("caf"_$Char(233))` | the hash of its UTF-8 bytes, equal to `Session.Hash` of it | No error expected |
| Empty or missing code | `HashCode("")`, `HashCode()` | `""` (never `Session.Hash("")`) | No error expected |
| Web route (consumer) | `POST /v1/pairing/code`, then a Pair with `HashCode(code)` | the session's code row holds the hash, and the chat pairs | As today (`PairingApi.TestCodeRoute`) |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls:66-72` -- `HashCode`: the copy to replace (line 71). Lane B's file, in Epic 11's either-lane footprint (AD-29).
- `src/ocutalon/cls/OcuTalon/Data/Session.cls:120-125` -- `Session.Hash(text)`, the sibling it delegates to. It has no `$Get` and no empty-code guard. Read-only.
- `src/ocutalon/cls/OcuTalon/Test/Data/PairingRows.cls:1-18, 23-26, 53-65` -- header list, the `VECTORABC` and `VECTORCODE` vectors, and `TestHashCodeVectors`. The fixed vectors pin byte-identity. The new test goes beside it.
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatMessages.cls:363-378` -- `TestAllowedAsksTheAllowance`, the precedent for pinning a one-call delegation by reading `%Dictionary.MethodDefinition`'s `Implementation`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:695` -- the production caller (`StoreCode(..., HashCode(code), ...)`). Unchanged.
- Callers in tests, unchanged: `Test/Web/PairingApi.cls`, `Test/Core/SessionOps.cls`, `SessionOpsProduction.cls`, `AnswersTelegram.cls`, `AnswersTelegramProduction.cls`. `Test/Contract/Ac.cls:308` pins the signature.
- `ci/units.sh:18` -- the `Data`, `Web`, `Core` and `Contract` areas are in shard `lane-b`, which CI runs as `shard:lane-b` in the `image` group.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls` -- replace line 71 with `Quit ##class(OcuTalon.Data.Session).Hash(code)`, keep line 70's guard, and update the doc comment to say the hash is `Session.Hash`'s form (DW-237).
- `src/ocutalon/cls/OcuTalon/Test/Data/PairingRows.cls` -- add `TestHashCodeIsSessionHash`, and a matching bullet in the header. It asserts that:
  - `HashCode` equals `Session.Hash` for the three sample codes of `TestHashCodeVectors`;
  - `HashCode("")` and `HashCode()` (no argument) are `""`, while `Session.Hash("")` is not;
  - `HashCode`'s source (`%Dictionary.MethodDefinition` `OcuTalon.Data.Pairing||HashCode`) calls `##class(OcuTalon.Data.Session).Hash(` and holds no `SHAHash`. A missing definition fails the test with a named assertion.

  `TestHashCodeVectors` stays unchanged.

**Acceptance Criteria:**
- **AC1 (DW-237, AD-4, Rule 2).** Given `Pairing.HashCode`, when the story is done, then its body is the empty-code guard plus `Quit ##class(OcuTalon.Data.Session).Hash(code)`, with no hashing expression of its own, and `TestHashCodeIsSessionHash` passes.
- **AC2 (AD-5).** Given the committed vectors, when `TestHashCodeVectors` runs unchanged, then it passes: every stored code hash keeps its value byte for byte, and no migration or storage change exists in the diff.
- **AC3 (integration).** Given a throwaway stack running `OcuTalon.Production`, when `Test.Web.PairingApi`, `Test.Core.SessionOps` and `Test.Contract.Ac` run, then each passes unchanged. The web route stores `HashCode(code)`, a Pair with that hash pairs the chat, and the signature pin holds.

## Spec Change Log

## Review Triage Log

### 2026-10-31 -- Review pass
- verdicts: 14 findings -- high 0, medium 0, low 10, false 4, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the spec's Auto Run Result still says `ready-for-dev` -- the section is rewritten at finalize with this pass's result.
  - `[low]` `[reject]` Blind: the Observed mutation lines carry no green-run totals, and the AC1 row names only `TestHashCodeVectors` -- the fix edits this build's spec; the green runs are recorded under Auto Run Result.
  - `[low]` `[reject]` Blind: the delegation check pins the spelling `##class(OcuTalon.Data.Session).Hash(` -- the spec names exactly that form (Tasks & Acceptance, AC1); a `$ClassMethod` rewrite would turn the test red loudly and be a deliberate change.
  - `[low]` `[reject]` Blind: no sample above code point 255 -- `HashCode` no longer converts to UTF-8, `Session.Hash` does, and the equality assertion covers whatever it does; a wide sample cannot go red from a `HashCode` change that the existing samples miss.
  - `[low]` `[reject]` Blind: `Session.Hash`'s comment does not name `HashCode` as a dependent -- the intent forbids touching `Session`; the fixed vectors of `TestHashCodeVectors` are the pin that catches a change of its form.
  - `[low]` `[reject]` Edge: a comment or dead branch holding the call text satisfies the source check -- no user-reachable path; the vectors and the `SHAHASH` absence still fail a live copy.
  - `[low]` `[reject]` Edge: another digest call (SHA3, HMAC) passes the no-`SHAHASH` check -- theoretical; the fixed vectors fail any other digest.
  - `[low]` `[reject]` Edge: an empty `Implementation` (deployed class) fails both source assertions with messages that blame the delegation -- the test classes are never deployed, and the failure is loud.
  - `[low]` `[reject]` Edge: no wide-character sample -- same as the Blind row above.
  - `[false]` `[reject]` Edge: a later edit to `Session.Hash` silently changes every stored pairing hash -- `TestHashCodeVectors` pins the three fixed vectors, so the change goes red.
  - `[low]` `[reject]` Edge: the no-own-hashing claim is pinned only against `SHAHash` -- the same residual as the SHA3/HMAC row.
  - `[low]` `[patch]` Verification-gap: AC3 has no `mutation:` line -- fixed: the parameter of `HashCode` renamed, `Test.Contract.Ac` and `Test.Web.PairingApi` went red, reverted byte-identical, green again; recorded under `## Verification`.
  - `[false]` `[reject]` Verification-gap, other: the Auto Run Result contradicts the frontmatter -- same as the first row; rewritten at finalize.
  - `[false]` `[reject]` Verification-gap, other: the spec records no outcome for the verification commands -- the outcomes are recorded under Auto Run Result at finalize.

The Intent Alignment Auditor found readings A (behaviour-preserving delegation) and B (one source of truth) both implemented, with no divergence: the new test exercises both the runtime surface (outputs) and the source surface (delegation).

## Design Notes

- **Architecture decisions:**
  - AD-4: one pairing-code hash method for both lanes, and only the hash is stored. Its text, "Lane B's `OcuTalon.Data.Pairing.HashCode(code)`", still holds, so the spine needs no change.
  - AD-5: storage is append-only, and nothing stored changes.
  - AD-29: Epic 11 may change either lane's files. At plan time no in-flight epic branch (10, 12, 13, 15, 29, 30, 31) had changed `Pairing.cls`, `Session.cls` or `PairingRows.cls`.
  - AD-22: the tests run in CI's `image` group (`shard:lane-b`).
- **Extend, don't copy (Rule 2):** the sibling is `OcuTalon.Data.Session.Hash`. This story removes the copy.
- **Integration ACs (Rule 1/2):** the story adds no service. It only changes an existing method to delegate to another, and AC3 is its consumer check.
  - **Consumes:** `OcuTalon.Data.Session.Hash` (Story 16.3), for the hash itself.
  - **Consumed-by:**
    - `OcuTalon.Web.Api` `POST /v1/pairing/code` (Story 10.3), which stores the hash;
    - Story 12.4's `TelegramIn`, which hashes `/start <code>` before the pair command;
    - `Core.SessionOps`, which compares hashes only.
- **Ledger:** DW-237 is addressed in Tasks & Acceptance (AC1). It is the only inbox entry.
- **Decided in-stage:**
  - Tests run on lane A's warm throwaway (`ci/iris.sh`), not on slot A through `iris_execute_tests`. The headers of `PairingRows` (its `TestPurge`) and `PairingApi` limit them to throwaways and CI. Slot A gets only a compile check.
  - The delegation is pinned through the method's source, as `WebChatMessages` does. Equal outputs cannot tell a delegate from a copy, so the output assertions alone could never go red against the copy.
  - The guard stays in `HashCode`, and `Session.cls` stays untouched.

## Verification

`<A>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`. QA and review use their own stage names and tags (`e11s0q`/`e11s0qw`, `e11s0c`/`e11s0cw`).

- **Run discipline:**
  - Run everything from the epic-11 worktree root.
  - Run each command in the foreground of its own call with `timeout: 600000`, and keep `ANTHROPIC_API_KEY` unset (CI mock only).
  - Make one test call per message, and never re-submit after a client-side timeout.
  - Pass `server` `ocutalon-slot-a` and namespace `OCUTALON` on every IRIS MCP call.
- **Shared surfaces:** none. The stored hash form, the schema and every count other tests read are unchanged.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-a`, then load and compile `Data/Pairing.cls` and `Test/Data/PairingRows.cls` there -- expected: build 154U, both compile. Run no test on the slot.
- (once) `<A> OCUTALON_RUN_TAG=e11s0iw ci/warm.sh up` -- expected: `LOCK acquired warm-iris`, then ready.
- (loop) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s0iw ci/iris.sh class OcuTalon.Test.Data.PairingRows` -- expected: `CLASS ... passed`, with `TestHashCodeVectors` and `TestHashCodeIsSessionHash` green.
- (loop) the same for `OcuTalon.Test.Web.PairingApi` -- expected: passed.
- (once) the same for `OcuTalon.Test.Core.SessionOps`, then `OcuTalon.Test.Contract.Ac`, each in its own call -- expected: both pass.
- (once) `<A> OCUTALON_RUN_TAG=e11s0i ci/iris.sh class OcuTalon.Test.Data.PairingRows` -- expected: passed on a fresh stack.
- (once) `bash ci/checks.sh` -- expected: every block passes (`class-rules` and `storage` included).
- (once, last; also after a failure) `<A> OCUTALON_RUN_TAG=e11s0iw ci/warm.sh down`, then `<A> OCUTALON_RUN_TAG=e11s0i ci/iris.sh teardown` -- expected: no lock of this stage remains in the lane-a folder.

**Planned mutations (Rule 19).** For each one: apply it, observe the red on the warm stack, revert, confirm that `git status --short` and `git diff --stat` are unchanged, then see green again on the same stack. Record each one as a `mutation:` line here.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `HashCode`'s line 71 goes back to its inline `$Translate(...SHAHash(256, ...))` copy | `TestHashCodeIsSessionHash` (source assertion) |
| AC1/AC2 | drop the `If $Get(code) = "" Quit ""` guard | `TestHashCodeVectors` ("an empty code has an empty hash") and `TestHashCodeIsSessionHash` |
| AC2 | delegate as `Session.Hash($ZConvert(code, "L"))` | `TestHashCodeVectors` (the 24-character vector, and case sensitivity) |

Observed (implement stage, warm stack e11s0iw; each reverted from a backup of this stage, `git status --short` and `git diff --stat` byte-identical, then green again):

- mutation: `HashCode`'s `Quit` goes back to the inline `$Translate(...SHAHash(256, ...))` copy -> `TestHashCodeIsSessionHash` red on "HashCode calls Session.Hash" and "HashCode holds no hashing expression of its own".
- mutation: dropped the `If $Get(code) = "" Quit ""` guard -> `TestHashCodeVectors` red on "an empty code has an empty hash", and `TestHashCodeIsSessionHash` red on "an empty code has an empty hash" (plus an `<UNDEFINED>` error for the no-argument call).
- mutation: delegated as `Session.Hash($ZConvert(code, "L"))` -> `TestHashCodeVectors` red on "a 24-character code" and "the hash is case-sensitive", and `TestHashCodeIsSessionHash` red on "HashCode equals Session.Hash of 24 characters".
- mutation (AC3, review stage, warm stack e11s0iw, reverted from a backup of this stage, `git status --short` and `git diff --stat` byte-identical, then `PairingApi` and `Contract.Ac` green again): the parameter of `HashCode` renamed `code` to `text`, so the body hashes an undefined `code` and answers `""` -> `Test.Contract.Ac` red on `TestCrossLaneSignatures` ("HashCode takes (code) in that order"), and `Test.Web.PairingApi` red on `TestCodeRoute` ("the session's code row holds the hash of the code") and `TestPageUnpair` ("A pairing code is stored as its hash: the hash is empty"). `PairingApi` and `SessionOps` compare `HashCode` with itself, so they pin the plumbing (a hash is stored, and a Pair with it pairs the chat); the hash value is pinned by `PairingRows`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Data.Pairing.HashCode` keeps its signature and its empty-code guard and now quits `##class(OcuTalon.Data.Session).Hash(code)`; the copied SHA-256 base64url expression is gone (DW-237, Rule 2). Every stored code hash keeps its value; no storage, `Session` or caller change.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls` -- `HashCode` delegates to `Session.Hash`; doc comment states the contract.
- `src/ocutalon/cls/OcuTalon/Test/Data/PairingRows.cls` -- new `TestHashCodeIsSessionHash` (equality with `Session.Hash` for three codes, `""` for `""` and no argument, source reads `Session.Hash` and holds no `SHAHash`) and its header bullet; `TestHashCodeVectors` unchanged.
- This spec -- status, baseline, `mutation:` lines, triage log.

**Review.** 14 findings from four layers: patches applied 1 (AC3 mutation evidence, recorded under `## Verification`), deferred 0, rejected 13 with their reasons in the triage log. Follow-up review recommended: false (no high, one low patch).

**Verification.**
- Slot A (`ocutalon-slot-a`, `OCUTALON`, build 154U): both classes loaded and compiled; no test run there.
- Lane A warm throwaway `e11s0iw`: `Test.Data.PairingRows`, `Test.Web.PairingApi`, `Test.Core.SessionOps` and `Test.Contract.Ac` pass (implement stage, then again at review); `PairingRows` passed on a fresh stack `e11s0i`.
- Four mutations observed red and reverted byte-identical, then green again (see `## Verification`).
- `bash ci/checks.sh`: all scripts passed.
- Warm stack taken down and fresh tag torn down; the lane-a lock folder is empty.

**Residual risks.** None found. The delegation pin reads the method source, so a deliberate rewrite of the call spelling would need the test updated.
