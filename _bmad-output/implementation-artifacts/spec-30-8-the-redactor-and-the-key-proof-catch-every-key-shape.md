---
title: 'The redactor and the key proof catch every key shape'
type: 'bugfix'
created: '2026-11-02'
status: 'done'
baseline_revision: '528410e08f6416741b64c5147a7f5b8569e3807a'
baseline_commit: '528410e08f6416741b64c5147a7f5b8569e3807a'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Two owner-kept conditions say "before 1.0.0", and both are still open.
- DW-386 (U-184): `OcuTalon.Bridge.Redact` does not replace two shapes that `key_like` (`docker/tests/lib-keys.sh`) flags: DigitalOcean tokens (`dop_v1_` and hex digits) and PEM private-key headers (`-----BEGIN [A-Z ]*PRIVATE KEY`). Its Telegram rule (`(?<![0-9])[0-9]{6,12}:...`) also misses a run of 13 or more digits that `key_like` still flags. So a key in one of these shapes can reach a trace, a log or an audit entry.
- DW-448 (U-185): `Test.Eval.KeyProof`'s `Walk` matches the key only as contiguous characters of one node. A key stored in a `$List` element next to a wide character (stored 16-bit), in a nested list, or in a `$List` subscript reads as clean. Nobody has yet measured whether a message body can store a key in a compressed or split `%Stream.Global*` chunk.

**Approach:**
- Extend `Redact.PatternList` so that every alternative of `KEY_LIKE_ERE` is replaced. Pin it with one test per shape, plus one test that runs a fixture for each alternative of a verbatim copy of `KEY_LIKE_ERE`. A small check script fails when that copy drifts from `lib-keys.sh`.
- Make `Walk` decode `$List` values, in data and in subscripts, nested lists included.
- Measure the stream question on a throwaway and take the branch the measurement picks.
- Start from the 30.7 set-aside patch's hunks for these three files, and only those hunks.

## Boundaries & Constraints

**Always:**
- `Redact.Text`'s signature, its fail-closed contract, idempotence, the JSON passes and its output for every shape it already handles stay as they are. The only behaviour that changes: the new shapes are replaced, and a Telegram id may now have 13 or more digits.
- The redactor covers every alternative of `KEY_LIKE_ERE` as defined in `docker/tests/lib-keys.sh` on this tree: seven alternatives, `sk-ant-` and the Telegram bot token among them.
- Bridge code names no other OcuTalon package (AD-2, `bridge-refs`).
- Every file stays ASCII (Rule 14). Comments state the contract.
- No file holds a key-like string: fixtures are built from fragments at run time, as `Test/Bridge/Redact.cls` already does, and `test-boundaries.sh` stays green.
- `Walk` keeps its counts, its places and its stats. A node counts once, however many ways it holds the value.
- The tests are warm-safe and self-contained. Each test removes what it wrote, also after a failure.

**Never:**
- Never apply the whole set-aside patch, and never take any part of it beyond the three file hunks named in the Code Map. Purge, approvals, replay, IncidentManager, WatchAnswers and the spine hunk stay with Story 30.7.
- Never edit `docker/tests/lib-keys.sh`, `docker/tests/test-boundaries.sh`, `ci/mock/mock.mjs` (its `KEY_LIKE` copy belongs to Lane B's mock, AD-22), `eval/*.sh`, or Lane B's copy of the walk (`Test.Web.SessionEvents.ReferenceHits`, DW-474, Story 31.4).
- Never change the rest of the key proof: `Trace`, the stores, the mock count, `Lines` and the CHK lines, `Scan`'s shape and the raw container-file grep.
- Never change a stored class or a `Storage` block.
- Never add an iris group or a job, and never rename one. Never load anything from `irislib/` or `irissys/`.
- Never run these tests on slot B: it is for load, compile and read-only probes only.

## I/O & Edge-Case Matrix

In this table, `T(x)` means `Redact.Text(x)`, and M means `[redacted]`. Every fixture is built from fragments.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|---|
| 1 | dop_v1_ token | `dop_v1_` plus 64 hex digits, in text, as the whole text, in a JSON string, in a nested array; upper-case hex | Each replaced by M, text around kept | No error expected |
| 2 | dop_v1_ too short | `dop_v1_` plus 19 hex digits | Kept as it is | No error expected |
| 3 | PEM block with an END line | Header, body and END line, with real line breaks and with escaped `\n`; one block with no algorithm name; two blocks | Each block, BEGIN through END line, becomes M; text after the END line kept | No error expected |
| 4 | PEM header only | Header and body, no END line, in text and in a JSON string | From BEGIN to the end of the text (or of the JSON string value) becomes M | No error expected |
| 5 | Not a private key | A `BEGIN CERTIFICATE` block | Kept as it is | No error expected |
| 6 | sk-ant- key | `sk-ant-api03-` plus 40 more characters, in text, upper case, in a JSON string, in an array | Each replaced by M | No error expected |
| 7 | Telegram token | Ids of 6, 10 and 13 digits, a colon, then 35 characters, in text and in a JSON string; a 13-digit id inside a URL | Each replaced by M | No error expected |
| 8 | Telegram too short | A 5-digit id | Kept as it is | No error expected |
| 9 | Every key_like alternative | For each alternative of `KEYLIKE` (a verbatim copy of `KEY_LIKE_ERE`): a fixture that the alternative matches (asserted), in free text and in a JSON string; Telegram also with a 13-digit id, PEM both with and without an END line | `T(fixture)` matches no alternative of `KEYLIKE`, holds M, and `T(T(x)) = T(x)`. The fixture count equals the alternative count | A missing fixture fails the test, naming the alternative |
| 10 | Copy drift | `KEYLIKE` in `Test/Bridge/Redact.cls` vs `KEY_LIKE_ERE` in `lib-keys.sh` | Equal: PASS. Different: FAIL naming both files, never a key | The script first proves it flags a synthetic mismatch |
| 11 | Consumer: the audit log | `Bridge.Audit.Write("Action", {marker, note: <dop_v1_ token>}, "<word> <marker> <PEM header and body>")`, read back by marker | The entry's data and description hold M, never the token, never the PEM header, and keep the marker | No error expected |
| 12 | $List, 8-bit (control) | `^OcuTalonTest("KeyProof","list8") = $LB("a", "x"_v_"y", "b")` | `GlobalHits(v, <db>)` counts it (today's Walk already does) | No error expected |
| 13 | $List, 16-bit | `$LB("a", $C(8364)_v_$C(8364))` as data | Counted | No error expected |
| 14 | Nested $List | `$LB("a", $LB("b", $LB("c", $C(8364)_v)))` as data | Counted | No error expected |
| 15 | $List subscript | `^OcuTalonTest("KeyProof", $LB("s", $C(8364)_v)) = ""` | Counted | No error expected |
| 16 | Message body row | A saved `OcuTalon.Eval.Msg.IncidentCase` whose `Snapshot` is `$C(8364)_v` | `GlobalHits(v, <database of its data global>)` is at least 1 | The row is deleted after the test |
| 17 | Absent value | `v_"-nobody"` over rows 12 to 16 | 0 | No error expected |
| 18 | Stream question (measured) | Throwaway: the message-body classes and their properties | No global stream: the guard test passes with its control found. A global stream exists: Walk decodes stream chunks (Tasks, branch Y) | The evidence is recorded either way |

</intent-contract>

## Code Map

**The set-aside patch (the starting point).** `_bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch`. Only these hunks are taken:
- lines 86-119: `src/bridge/cls/OcuTalon/Bridge/Redact.cls`;
- lines 736-818: `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`;
- lines 1298-1391: `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls`.

Extract them with `git apply --include=<path>` for each of the three paths, or `filterdiff -i`. The hunks were written against an older blob (`index 0747ed25`, `71aa75af`, `1587cbee`). If a hunk does not apply cleanly, port it by hand. That build was self-reviewed only, never QA'd or code-reviewed: review every line you take.

**Redactor**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls`:
  - `:12-16` the doc's pattern list (it says "6 to 12 digits": update it);
  - `:178-187` `Patterns`;
  - `:190-212` `PatternList`, the one place that changes;
  - `:220-233` `KeyPattern` (unchanged).
  - The patch adds `dop_v1_[A-Fa-f0-9]{20,}`, a PEM rule `BEGIN [A-Z ]*PRIVATE KEY(?:[\s\S]*?END [A-Z ]*PRIVATE KEY-----|[\s\S]*)` (with the dashes, built from fragments), and widens Telegram to `(?<![0-9])[0-9]{6,}:[A-Za-z0-9_-]{30,}`.
- `docker/tests/lib-keys.sh:19` `KEY_LIKE_ERE`, seven alternatives (read-only):
  - `sk-ant-[A-Za-z0-9_-]{8,}`: already covered;
  - `[0-9]{8,10}:[A-Za-z0-9_-]{35}`: not covered for runs of 13 or more digits;
  - `gh[pousr]_...`, `github_pat_...` and `AKIA...`: already covered;
  - `dop_v1_[a-f0-9]{20,}` and `-----BEGIN [A-Z ]*PRIVATE KEY`: not covered.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`:
  - the header list `:1-26`;
  - `TestPatterns :58-92`, which already pins `ghp_`, `github_pat_`, `AKIA`, `sk-ant-` and a 9-digit Telegram token;
  - `TestIdempotent :134`;
  - the helpers `Check :275` (asserts both the result and idempotence) and `Quote :289`;
  - the fragment idiom, for example `"gh" _ "p_" _ ...`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Audit.cls`:
  - `TestNoSecretInAnyEntry :185-275` is the pattern for the consumer test;
  - the helpers `Valid :278` and `Random :314`;
  - `Test.Bridge.AuditLog.Now()` and `Wait(since, source, type, event, marker, username, count, seconds)` (`AuditLog.cls:23,61`).
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:186-187` (the consumer): `Write` redacts the data's JSON and the description, then cuts the description to 128 characters.
- `ci/units.sh:6` `CHECK_SCRIPTS`. `docker/tests/test-ci-config.sh:633-648` requires every `docker/tests/test-*.sh` to be in exactly one list.
- Other product callers of `Redact.Text`, which change no code: StepBuffer (the agent steps), Decide's warnings, the Executor, IncidentManager and others. `Test.Bridge.Steps` pins the redact-then-cut behaviour.

**Key proof**
- `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls`:
  - `Walk :252-302`: the match lines `:276-277` (root data) and `:283-284` (`$Query` nodes);
  - `TestGlobalHits :39-66`;
  - `TestTraceHits :69-103` (the IncidentCase body fixture and its cleanup);
  - `Trace :353-441` and `Lines :240-249`: unchanged.
- The patch adds `Holds(text, value, depth)` (a substring match, else a `$ListValid` non-empty value decoded with `$ListNext`, recursing to `LISTDEPTH` 10) and `HoldsSubscript(reference, value)` (`$QSubscript` of each subscript through `Holds`).
- `src/ocutalon/cls/OcuTalon/Eval/Msg/IncidentCase.cls`: extends `Ens.Request`; `Snapshot` is a `%String(MAXLEN = "")`.
- `eval/key-proof.sh`: the outer surface. It takes about 126 s on a fresh throwaway (Story 9.10), and its globals scan reported 4,037,146 nodes in 2.62 s.
- Streams:
  - `irislib/%Stream/GlobalCharacter.cls:13` (`COMPRESS = 1`) and `:33-45,98-101`: the root node is `<maxnode>,<size>[,<compress>]`, and its chunks are children 1 to maxnode;
  - `irislib/%occStream.inc:21`: chunks are decoded with `$System.Util.Decompress` when compress is above 0;
  - `irislib/%Stream/TmpCharacter.cls:16` (`BUFFERLEN = 163280`).
  - `src/bridge/cls/OcuTalon/Bridge/RequestSize.cls:77` reads `%AI.Agent.Session.ContextData`, a `%Stream.GlobalCharacter`: the positive control.
  - No product class in `src/` has a stream property (grep, 2026-11-02).

## Tasks & Acceptance

**Execution:**
- [ ] Task 0, measurement (warm throwaway `e30s8iw`, before the branch choice).
  - Write an ObjectScript script under `<scratchpad>/e30s8impl/` and run it in the warm stack's iris container. Get the project P from `ci/warm.sh status`, then run `docker compose -p <P> exec -T iris iris session IRIS -U OCUTALON < <script>`.
  - Run it after `OcuTalon.Test.Bridge.Decide` has run on that stack, so that the trace holds product messages.
  - The script lists the build (`$ZVersion`), and the distinct `Ens.MessageHeader.MessageBodyClassName` of every Interoperability namespace. Its enumerated set is every compiled class under `OcuTalon` that extends `Ens.Request`, `Ens.Response` or `Ens.MessageBody`, together with the system body classes seen in the trace.
  - It lists each enumerated class's compiled properties, inherited ones included. A property counts as a stream when its type class has `ClassType` stream or extends `%Stream.Object`. A serial-object property counts when its class has a stream, to a depth of 3.
  - Positive control: the same check must find `%AI.Agent.Session.ContextData`.
  - A **global stream** is a stream whose data lives in a global: `%Stream.GlobalCharacter`, `%Stream.GlobalBinary`, their subclasses, `%Library.GlobalCharacterStream` and `%Library.GlobalBinaryStream`. Other streams are only listed.
  - Record in Design Notes, "Measured at implementation": the build, the classes, the property count, any stream found, and the control.
  - No global stream in the set takes **branch N**. One or more takes **branch Y**. -- DW-448's measurement; the 30.7 note ("no message-body class has a %Stream property") is a lead, not evidence.
- [ ] Task 0b, a DW-589 measurement that gates nothing. Run `eval/key-proof.sh` once before the `KeyProof.cls` change, with tag `e30s8i`. Record its globals CHK figures (nodes, seconds). The run after the change is under Verification. DW-589 stays with Story 30.7; this only records the numbers.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Redact.cls` -- take the patch hunk: add the `dop_v1_` and PEM rules before the Telegram rule, and widen Telegram to 6 or more digits. Update the doc. No regex source may match `key_like` (the patch builds the PEM rule from fragments, and that form may stay). -- DW-386.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`:
  - Take the patch's `TestDigitalOceanToken`, `TestPrivateKey`, `TestAnthropicKey` and `TestTelegramToken` (rows 1-8).
  - Add `Parameter KEYLIKE`, a verbatim copy of `KEY_LIKE_ERE`.
  - Add `TestEveryKeyLikeShape` (row 9): split `KEYLIKE` on `|`, keep one or more fragment-built fixtures per alternative, and assert per alternative, by its index and its text (never the fixture), that:
    - the alternative's `%Regex.Matcher` `Locate()` finds the fixture;
    - `T(fixture)`, alone and inside a JSON string, is located by no alternative;
    - the result holds M and is idempotent (`Check`).
  - Extend the header list. -- DW-386 (one test per shape: these four, `TestPatterns` for `ghp_`, `github_pat_` and `AKIA`, and the oracle for all seven).
- [ ] `docker/tests/test-redact-shapes.sh` (new) -- source `lib-keys.sh`, read the `KEYLIKE` parameter line from `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`, and compare it byte for byte with `$KEY_LIKE_ERE`.
  - The script first runs its comparison on a synthetic mismatching pair, so that a broken comparison fails.
  - It prints PASS or FAIL lines with file names only, and exits 0 only when every check passes.
  - Keep it under about 40 lines, executable, ASCII. -- row 10: the drift that caused DW-386.
- [ ] `ci/units.sh` -- add `redact-shapes` to `CHECK_SCRIPTS` (a plain union). -- `test-ci-config.sh` requires the registration.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Audit.cls`:
  - Add `TestNewKeyShapesInNoEntry` (row 11, the Integration AC). Write one `Action` entry with a fresh marker, a fragment-built `dop_v1_` token as the value of the non-sensitive key `note`, and a description of a word, the marker and a PEM header with a short body. Keep the description under 128 characters before redaction.
  - Read it back with `AuditLog.Wait(mark, "OcuTalon", "", "", marker, "", 1)`. Assert that the data and the description each hold M and the marker, and hold neither the token nor `PRIVATE KEY`.
  - Extend the header list.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls`:
  - Take the patch hunk (`LISTDEPTH`, `Holds`, `HoldsSubscript`, and the `Walk` lines through them).
  - Extend `TestGlobalHits` with rows 12-15 and 17. The 8-bit row is a control that today's Walk already finds, so the discriminating rows are 13-15.
  - Add `TestGlobalHitsMessageBody` (row 16): save an `IncidentCase` whose `Snapshot` is `$C(8364)_v`. Scope `GlobalHits` to the database of the class's compiled storage `DataLocation`, found through `%SYS.Namespace.GetGlobalDest` as `TestGlobalHits` does. Delete the row, also after a failure.
  - Update the header. -- DW-448.
- [ ] Branch N (no global stream), `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls`:
  - Add `TestNoMessageBodyHoldsAGlobalStream`. It applies Task 0's stream check to a static set: every compiled `OcuTalon` subclass of `Ens.Request`, `Ens.Response` and `Ens.MessageBody`, plus the system body classes that Task 0 saw in the trace, named in a parameter.
  - It asserts that none has a global stream, naming any class and property it finds, and that the control `%AI.Agent.Session.ContextData` is found.
  - It reads no trace contents, so it is hermetic.
  - It is the automated `reopen_if` of the `wontfix-accepted` close. Record the evidence for the lead in Design Notes: the build, the throwaway tag, the classes and what was checked. -- DW-448, stream half.
- [ ] Branch Y (a global stream exists), `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls` instead of branch N:
  - First, on the warm stack, save a body of that class whose global stream holds a fake value of at least 1,024 characters, built at run time. Record that today's `GlobalHits` misses it.
  - Then make `Walk` decode stream chunks. A node whose data is a stream root header `<maxnode>,<size>[,<compress>]` with children 1 to maxnode is read child by child: each child through `$System.Util.Decompress` when compress is above 0, and the chunk boundaries joined by keeping the last length minus 1 characters. The node counts one hit.
  - Add a test with a compressed chunk and with a value split across a chunk boundary.
  - Record the measurement in Design Notes. -- DW-448, stream half.

**Acceptance Criteria:**
- Given each of the seven alternatives of `KEY_LIKE_ERE`, when a fixture that the alternative matches passes through `Redact.Text` in free text and inside a JSON string, then no alternative matches the result, the result holds `[redacted]`, the text around the fixture is kept, and a second pass changes nothing (rows 1-9).
- Given `Redact.Text`'s existing tests (`Test.Bridge.Redact`'s other methods, `Test.Bridge.Steps` and `Test.Bridge.Audit.TestNoSecretInAnyEntry`), when they run after the change, then each passes unchanged.
- Given `KEYLIKE` in `Test/Bridge/Redact.cls` differs from `KEY_LIKE_ERE` in `lib-keys.sh`, when `bash docker/tests/test-redact-shapes.sh` runs, then it exits non-zero naming both files. Given they are equal, it passes (row 10).
- Given `Bridge.Audit.Write` gets a `dop_v1_` token in a data value and a PEM header in its description, when the entry is read back from the IRIS audit log, then neither the token nor the header is in it and `[redacted]` stands in their place (row 11, Integration AC).
- Given a value stored as a 16-bit `$List` element, in a nested list, in a `$List` subscript, or in a message body row next to a wide character, when `GlobalHits` scans the database that holds it, then it is counted. An absent value gives 0, and the existing assertions of `TestGlobalHits` hold (rows 12-17).
- Given Task 0's measurement, when it ends, then Design Notes record the build, the classes enumerated, their stream properties and the control. Branch N then has `TestNoMessageBodyHoldsAGlobalStream` green with its control found. Branch Y has `Walk` finding a value in a compressed chunk and across a chunk boundary (row 18).
- Given the changed tree, when `eval/key-proof.sh` runs on a fresh throwaway, then it exits 0 with "eval/key-proof: all checks passed", and its globals figures are recorded beside Task 0b's.

## Spec Change Log

## Review Triage Log

### 2026-11-02 — Review pass
- verdicts: 23 findings (blind 8, edge 10, verification-gap 3 plus 2 other, intent-alignment 0: descriptive only), logged in 16 rows where several layers filed the same root cause — high 0, medium 0, low 22, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1: no Audit case for a PEM key that straddles the 128-character cut — Write redacts first and cuts after (pinned by the existing `TestNoSecretInAnyEntry`); a header-only block is replaced to the end of the text before the cut, so the cut cannot expose it.
  - `[low]` `[patch]` Blind 2 / VG 1: `TestNewKeyShapesInNoEntry` asserts that the data holds no PEM header and the description no token, where neither field ever held that fixture (vacuous) — patched: the token and the PEM block are now in both the data and the description, and each field is asserted clean of both (the PEM-rule mutation turns four assertions red).
  - `[low]` `[reject]` Blind 3 / Edge 10: the PEM fallback runs to the end of the text, and the shape test drops the trailing text — by design (Design Notes "Decided in-stage": the secret is the body; errs toward replacing more; inside JSON it stops at the string value); the doc comment states it.
  - `[low]` `[reject]` Blind 4: `-----END ... PRIVATE KEY BLOCK-----` (PGP) is not matched as an END line — the block then runs to the end of the text, which still replaces the whole block (over-redaction, the safe side); not a `key_like` shape of its own.
  - `[low]` `[reject]` Blind 5 / Edge 9: the stream guard checks three system base classes and does not follow persistent-class references — Task 0 measured the trace and the compiled set (46 classes, 369 properties, 0 streams) and saw no other system body class; `Ens.StreamContainer` and `Ens.StringRequest` appear only in tests under `src/ocutalon/cls/OcuTalon/Test`, not in product code. wontfix-theoretical: a product body class that holds a persistent reference to a stream-holding class does not exist; reopen_if the guard's set gains a class that does.
  - `[low]` `[reject]` Blind 6 / Edge 7 / VG other 1: `Walk` is heavier per node, and the `LISTDEPTH` cut-off is untested — measured: `eval/key-proof.sh` globals line 18.76 s against 3.19 s on about 4.1 million nodes, far inside any cap, so a prefilter would add a branch for no user-visible gain; the depth cut-off is a safety bound that no stored value reaches (also Edge 6: a list more than 10 deep).
  - `[low]` `[patch]` Blind 7: `>= 7` with the wording "of the day" in `TestEveryKeyLikeShape` breaks when an alternative is legitimately removed from `lib-keys.sh` — patched to `> 0`; the every-alternative-has-a-fixture assertion and the drift script keep the rest.
  - `[low]` `[patch]` Blind 8: the class header's `TestTelegramToken` bullet omits the 6-digit bound, the URL and the 5-digit case — patched. Its other two points (lower-case hex in `KEYLIKE`, one awkward doc wrap in `Redact.cls`) are rejected: the wrap predates this story, and the upper-case `dop_v1_` superset is recorded in Design Notes.
  - `[low]` `[reject]` Edge 1: a PEM split over several JSON string values leaves the body strings — values are scrubbed one by one by design (Design Notes), and the rule targets `key_like`'s header; wontfix-accepted, reopen_if a trace or audit entry is seen holding PEM body lines in separate members.
  - `[low]` `[reject]` Edge 2: `doo_v1_` and `dor_v1_` DigitalOcean tokens are not replaced — `key_like` does not flag them, so they are outside the intent ("every alternative of KEY_LIKE_ERE"); the oracle script fails the moment `lib-keys.sh` adds them.
  - `[false]` `[reject]` Edge 3: a multi-MB text with a BEGIN line and no END line could overflow ICU's backtrack stack — Measured at planning: a 3 MB header-only text is replaced in 0.03 s; `Redact.Text` is fail-closed besides.
  - `[low]` `[patch]` Edge 4 / VG 3: the oracle test does not assert that the text around a fixture is kept (an over-redacting rule stays green) — patched: the "in text" case now asserts the text before the fixture is kept (header-only PEM eats the text after, by design).
  - `[low]` `[reject]` Edge 5: a double quote or backslash in `KEY_LIKE_ERE` makes the verbatim copy impossible in an ObjectScript literal — none today; wontfix-theoretical, and the script fails loudly rather than passing.
  - `[low]` `[reject]` Edge 8 / VG other 2: `Catch {}` in `TestNoMessageBodyHoldsAGlobalStream` could silently shrink the set — the compiled classes come from the dictionary query, `%IsA` does not throw for them, and the `> 10` and `IncidentCase` membership assertions bound the shrinkage.
  - `[low]` `[patch]` VG 2 (part): no test sets a `$List` at the root node of a global, so reverting only `Walk`'s root-node line stays green (AC 5) — patched: `TestGlobalHits` sets a root-node `$List` when the root is free, asserts it is found and counts five rows, and clears it with `ZKill`; the mutation is recorded.
  - `[low]` `[reject]` VG 2 (rest): `mutation:` lines for `TestAnthropicKey`, alternatives 1, 3, 4 and 6, the 19-hex and 5-digit negatives, the PEM fallback branch, the control lines, and the serial-object recursion of `GlobalStreams` — Rule 19 asks one demonstrated mutation per AC (AC 1 has four, AC 5 four, AC 6 one); the serial recursion would need a new stored test class for a shape no body class has, and is not a two-way door (wontfix-accepted, reopen_if a body class gains a serial property with a stream).
  - Intent-alignment: no findings (a description: it reads the diff as the consumer-surface reading with a static guard for the stream question; the stream evidence is in Design Notes).

## Design Notes

**Architecture decisions (Rule 6).**
- AD-31 and Conventions: Redaction. The one redactor is the bridge's, and this story only extends its pattern list.
- AD-2: `Redact` names no OcuTalon package.
- AD-17: the audit writer passes its data and description through the redactor, and the consumer test reads the IRIS audit log back.
- AD-19: no key in IRIS, a log or the trace. The redactor is the backstop.
- AD-22: tests run on throwaway stacks, and the key proof's definition is unchanged except for the walk's match.
- AD-29 and AD-33: Lane A's files only. Lane B's walk copy is not touched.
- No AC contradicts an AD's Rule.

**Measured at planning** (slot B, `ocutalon-slot-b`, build 154U, port 52791; process-private globals and string probes only, nothing saved or compiled):
- `$Query` returns a `$List` subscript as its raw list bytes. An 8-bit element is matched by `reference [ v`; a 16-bit one is not. `$QSubscript` of the reference, the extended form `^|"^^dir"|G(...)` included, returns the `$List` itself, and its element holds the value. So `HoldsSubscript` works as the patch writes it.
- As data, an 8-bit `$List` element is already found by `data [ v`. A 16-bit element and a nested 16-bit element are not, and `$ListNext` decoding finds both.
- `$ListValid` is 0 for plain strings such as "abc", and 1 for "" (the patch's `$ListLength = 0` check covers that).
- The patch's PEM rule through `%Regex.Matcher`:
  - a block with an END line (real or escaped `\n`) becomes M, and the text after it is kept;
  - a header-only block runs to the end of the text;
  - two blocks give `M\nM`;
  - a certificate is kept;
  - a 3 MB header-only text is replaced in 0.03 s.
- The widened Telegram rule replaces a 13-digit id.

**Measured at implementation** (warm throwaway `e30s8iw`, fresh `e30s8i`, 2026-11-02; Task 0 and Task 0b; branch N taken):
- **Build:** `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:05:18 EDT`.
- **Method:** a throwaway class `E30S8.Meas` (scratchpad, loaded into the warm stack and deleted after the run) ran in the iris container, in namespace OCUTALON, after `OcuTalon.Test.Bridge.Decide` had passed on the stack. It listed the namespaces and, for each Interoperability namespace (HSCUSTOM, HSLIB, HSSYS, OCUORDERS, OCUTALON, USER and the ENSLIB mapping), the distinct `Ens.MessageHeader.MessageBodyClassName`. It then enumerated the compiled classes under `OcuTalon.` that extend `Ens.Request`, `Ens.Response` or `Ens.MessageBody`, and read each one's compiled properties (inherited included). A property is a global stream when its type class is, or extends, `%Stream.GlobalCharacter`, `%Stream.GlobalBinary`, `%Library.GlobalCharacterStream` or `%Library.GlobalBinaryStream`; other streams (ClassType stream or extends `%Stream.Object`) were to be listed only; a serial-object property is read to a depth of 3.
- **Trace:** after Decide, the trace of the stack held few product messages: only `OcuTalon.Core.Msg.RunTurns` and `OcuTalon.Msg.Tick` (both in the set below), plus headers with an empty body class name (OCUTALON and OCUORDERS). No system body class (`Ens.*`) was seen in any namespace. So `SYSTEMBODIES` lists only the three base classes.
- **Classes:** 46 compiled `OcuTalon` classes extend `Ens.Request`, `Ens.Response` or `Ens.MessageBody` (42 product classes in the Bridge, Checks, Core, Demo, Eval, Fix, Msg, Schedule and Watch packages, `Eval.Msg.IncidentCase` among them, and four test-only body classes: `Test.Core.CommandsSubVerb`, `Test.Eval.Feed.Claim`, `Test.Eval.Feed.LabResult`, `Test.Eval.Feed.Shipment`).
- **Properties:** 369 compiled properties in all (inherited included). **Global streams found: 0. Other streams found: 0.** Serial-object properties with a stream: none.
- **Control:** the same check on `%AI.Agent.Session` (11 properties) finds `ContextData` as a `%Stream.GlobalCharacter`: 1 global stream.
- **Branch:** no global stream in the set, so **branch N**. The 30.7 note ("no message-body class has a %Stream property") is now evidence: it is measured, and `TestNoMessageBodyHoldsAGlobalStream` (green on `e30s8iw`) holds it.
- **For the ledger (DW-448, stream half):** close `wontfix-accepted` with this evidence (build 154U, tags e30s8iw/e30s8i, 46 classes, 369 properties, 0 streams, control found). `reopen_if`: `Test.Eval.KeyProof.TestNoMessageBodyHoldsAGlobalStream` goes red.
- **Task 0b (DW-589 figures, `eval/key-proof.sh` on fresh `e30s8i`, before the KeyProof change; `KeyProof.cls` was put back to its committed form for the run):** exit 0, "eval/key-proof: all checks passed"; `PASS key proof globals: no key in 4258041 node(s) of 801 global(s) in 16 database(s) (... control found 188 time(s); 3.19 s)`.

**DW-450 Walk-change record (for Story 31.4, the mirror in `Test.Web.SessionEvents.ReferenceHits`, DW-474).** `Test.Eval.KeyProof.Walk` changed how it matches a node. Nothing else in `Walk` changed (its counts, places and stats are the same; a node counts once).
- New `Parameter LISTDEPTH = 10`.
- New private `Holds(text, value, depth = 0)`: 1 when `text [ value`; else, when `depth < LISTDEPTH`, `$ListValid(text)` and `$ListLength(text) > 0`, it reads each element with `$ListNext` and recurses into every element that is defined (`$Data(element)`), with `depth + 1`; else 0. A 16-bit (wide-character) element is not stored as the characters, so a plain `[` misses it.
- New private `HoldsSubscript(reference, value)`: 1 when `reference [ value`, else 1 when `Holds($QSubscript(reference, i), value)` for some subscript i of `$QLength(reference)` (a subscript can be a `$List`).
- `Walk`: root node `data [ value` became `..Holds(data, value)` (and the same for the control); the `$Query` nodes' `(reference [ value) || (data [ value)` became `..Holds(data, value) || ..HoldsSubscript(reference, value)` (and the same for the control).
- No stream decode (branch N). Test rows: `TestGlobalHits` (8-bit, 16-bit, nested, `$List` subscript, absent) and `TestGlobalHitsMessageBody`.

**Decided in-stage.**
- **The PEM rule replaces the whole block, not only the header.** `key_like` flags the header, but the secret is the body. Running to the end of the text when there is no END line errs toward replacing more. Inside JSON, it stops at the end of the string value, because values are scrubbed one by one.
- **Telegram is widened to 6 or more digits.** `key_like`'s unanchored `[0-9]{8,10}:` flags a longer digit run, and the old `{6,12}` with its look-behind missed it. This is the only change to an existing shape, and it only replaces more.
- **`dop_v1_` accepts upper-case hex too.** That is a superset of `key_like`'s lower case.
- **The drift guard.** A verbatim copy in the test plus `test-redact-shapes.sh` keeps "every key_like shape" true when `lib-keys.sh` gains a shape: the redactor fell behind `key_like` exactly that way (DW-386). The guard is one new check script, a hosted check with no iris group, and one `CHECK_SCRIPTS` entry. Neither `lib-keys.sh` nor `test-boundaries.sh` changes.
- **The Integration consumer is `Bridge.Audit`.** The IRIS audit log is the outermost surface a key could be stored on, and it is read back as stored.
- **Branch N's guard test uses a static class set.** A set read from the trace would depend on which tests ran first. The trace's class list is the measurement's evidence, not the test's input.
- **The scope of the stream question is the owner's: message bodies.** `%AI.Agent.Session.ContextData` (the saved AI session history) is a compressed global stream that `Walk` also cannot read. It is out of U-185's scope and is used here only as the positive control. See "For the lead".

**For the lead (spec gate).**
- **DW-450 reopens.** Its `reopen_if` is "either walk changes how it matches a node ... and the other does not", and this story changes `Walk`. Lane B's copy is DW-474, owned by Story 31.4, which is deferred after the tag. The implement records the exact change (`Holds`, `HoldsSubscript`, `LISTDEPTH`, and any branch-Y stream decode) in Design Notes, so that 31.4 can mirror it. Routing is the lead's job.
- **Branch N's ledger close.** The stream half closes `wontfix-accepted` with the evidence from Design Notes (the build, the tag, the classes, what was stored or checked). Its `reopen_if` is `TestNoMessageBodyHoldsAGlobalStream` going red.
- **Possibly a separate entry.** The saved AI session history is a compressed global stream that the key proof's global walk cannot read. U-185 scopes the question to message bodies, so nothing is built here. Whether that needs an entry is the lead's call.
- `ci/mock/mock.mjs` keeps its own `KEY_LIKE` copy (Lane B), which the guard does not cover.

**Integration ACs (Rule 1).** This story introduces no service or module: it extends the redactor's pattern list and a test helper. The Integration AC is row 11: `Bridge.Audit.Write`, a real production caller of `Redact.Text`, writes an IRIS audit entry, and the entry read back holds neither new shape.

**Consumed-by** (`Redact.Text`):
- `Bridge.Audit` (Story 3.7), the AC above;
- the agent steps' `StepBuffer` (AD-9);
- the trace warnings of Decide, the Executor, IncidentManager, Checks and Watch;
- `Watch.EvidencePack` and `Watch.ErrorText` (model-bound evidence);
- `Eval.Record`;
- Epic 12's Delivery.Text redaction (U-218), which calls it unchanged.

**Consumed-by** (`KeyProof.GlobalHits` and `Walk`): `Scan`, which `eval/run.sh --release-candidate --on-mock --key-path` calls, and `eval/key-proof.sh` (Story 9.10).

**Consumes:** `%Regex.Matcher`; `$ListValid`, `$ListNext` and `$QSubscript`; `%Dictionary.CompiledClass` and `CompiledProperty` (branch N); `$System.Util.Decompress` (branch Y); `Test.Bridge.AuditLog`.

**Extend, don't copy (Rule 2).**
- `PatternList` is extended in place.
- The new tests reuse `Check`, `Quote` and the fragment idiom, and Audit's `Valid`, `Random` and `AuditLog.Wait`.
- `test-redact-shapes.sh` sources `lib-keys.sh` and copies no pattern.
- `Holds` and `HoldsSubscript` sit beside `Walk`. Their sibling, `Test.Web.SessionEvents.ReferenceHits`, is a Lane B file that this story may not edit (AD-33). That duplication is DW-450 and DW-474, routed to Story 31.4, not closed here.

**Ledger inbox (Rule 17).**
- DW-386: addressed (rows 1-11; the Redact, Test.Redact, drift-check and Audit tasks).
- DW-448: addressed (rows 12-18; Task 0; the KeyProof tasks; branch N or Y).

**Contended edits:** none.

**Files outside "Ours"** (`footprint_extensions`):
- `docker/tests/test-redact-shapes.sh` (new);
- `ci/units.sh` (the `CHECK_SCRIPTS` line, a plain union).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=<stage>'`, run from the worktree root.

**Tags:**
- implement: fresh `e30s8i`, warm `e30s8iw`;
- QA: `e30s8q` and `e30s8qw`;
- review: `e30s8r` and `e30s8rw`.

**How to run:**
- One command per tool call, in the foreground, with `timeout: 600000`. Never two IRIS runs in one message.
- The harness moves a call to the background after about 180 s. Poll its output in loops of under 170 s, and never start a second copy.
- Run on throwaways only. Use warm for the classes and fresh for `eval/key-proof.sh` and the shards. Slot B is never used for tests.
- Tear down only your own tags, also after a failure.

**Commands:**
- (loop) `bash docker/tests/test-redact-shapes.sh` -- expected: PASS lines, exit 0.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: every rule passes ("keys: nothing key-like" included).
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: all pass (`redact-shapes` registered once).
- (loop) `<lane> OCUTALON_RUN_TAG=e30s8iw ci/warm.sh up`, once -- expected: the stack is up.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s8iw ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed`:
  - `OcuTalon.Test.Bridge.Redact`
  - `OcuTalon.Test.Eval.KeyProof`
  - `OcuTalon.Test.Bridge.Audit`
  - `OcuTalon.Test.Bridge.Steps`
- (once) Task 0: `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s8iw ci/iris.sh class OcuTalon.Test.Bridge.Decide`, then the measurement script through `docker compose -p <P> exec -T iris ...`, each in its own call -- expected: the evidence recorded in Design Notes.
- (once) Task 0b, before the KeyProof change, then again after it: `<lane> OCUTALON_RUN_TAG=e30s8i bash eval/key-proof.sh` (about 130 s each) -- expected: exit 0, "eval/key-proof: all checks passed", and the globals nodes and seconds recorded.
- (once) `bash ci/checks.sh` -- expected: "checks: all scripts passed".
- (once) `<lane> OCUTALON_RUN_TAG=e30s8i ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, fresh, one call each -- expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s8i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3, fresh, one call each -- expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e30s8iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s8i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- **`Redact`'s pattern list.** Two shapes are added, and a Telegram id may now have 13 or more digits.
  - Search the test trees for pinned outputs that contain `dop_`, `PRIVATE KEY`, or a digit run of 13 or more followed by `:` and 30 or more token characters, and update any test that asserts the old output.
  - A search on 2026-11-02 found none outside `Test/Bridge/Redact.cls`.
- **`CHECK_SCRIPTS`** gets one entry. `test-ci-config.sh` asserts that each script is listed once, and no script counts the entries.
- **`Test.Bridge.Redact` and `Test.Eval.KeyProof` header lists.**
- **`TestGlobalHits`'s counts.** The existing assertions keep their own value, so the new rows use a separate value.
- **CI time.** No new unit in an iris group. The new methods run in `shards-2` (Bridge and Eval are in `lane-a@rest`). Expect a few seconds (inference). The new check script runs in the hosted `checks` job and takes under 1 s.
- **Hermeticity.**
  - Every test added or changed passes on a fresh environment, in either order.
  - Each test removes its `^OcuTalonTest("KeyProof")` nodes and its IncidentCase rows, also after a failure.
  - Audit entries are read only by a fresh marker.
  - The branch N guard reads compiled classes only.

**Pinning mutations (Rule 19).** One mutation per AC, each run in its own foreground call on the warm stack. Revert byte for byte (`git status --short` and `git diff --stat` unchanged). A red counts only when the class is green again on the same stack after the revert. Record each result here as `mutation: ... -> ...`.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1, rows 1, 9 | Remove the `dop_v1_` rule | `TestDigitalOceanToken`, `TestEveryKeyLikeShape` (that alternative) |
| AC 1, rows 3, 4, 9 | Remove the PEM rule | `TestPrivateKey`, `TestEveryKeyLikeShape` |
| AC 1, rows 7, 9 | Telegram back to `{6,12}` | `TestTelegramToken` (13 digits), `TestEveryKeyLikeShape` |
| AC 1, row 5 | PEM rule without `PRIVATE KEY` (any BEGIN) | `TestPrivateKey`'s certificate case |
| AC 2 | none: a regression gate, pinned by the existing suites | -- |
| AC 3, row 10 | Change one character of `KEYLIKE` | `test-redact-shapes.sh` FAIL; then also `TestEveryKeyLikeShape` if a fixture no longer matches |
| AC 4, row 11 | Remove the `dop_v1_` rule (or the PEM rule) | `Test.Bridge.Audit.TestNewKeyShapesInNoEntry` |
| AC 5, rows 13, 16 | `Walk` matches `data [ value` again (no `Holds` for data) | `TestGlobalHits` (16-bit), `TestGlobalHitsMessageBody` |
| AC 5, row 14 | `Holds` does not recurse | `TestGlobalHits` (nested) |
| AC 5, row 15 | `HoldsSubscript` reverts to `reference [ value` | `TestGlobalHits` (list subscript) |
| AC 6 (branch N) | The guard's stream check always returns 0 | `TestNoMessageBodyHoldsAGlobalStream` (the control not found) |
| AC 6 (branch Y) | The stream-chunk decode removed | The branch Y test (compressed and split rows) |
| AC 7 | none: the outer-surface run; its parts are pinned above | -- |

**Pinning mutation results (implement, warm `e30s8iw`, each reverted byte for byte; the class green again on the same stack after every revert):**
- mutation: remove the `dop_v1_` rule -> `Test.Bridge.Redact` `TestDigitalOceanToken` (5 assertions) and `TestEveryKeyLikeShape` (alternative 5) red; `Test.Bridge.Audit` `TestNewKeyShapesInNoEntry` red (data holds the token, no `[redacted]`).
- mutation: remove the PEM rule -> `TestPrivateKey` (8 assertions) and `TestEveryKeyLikeShape` (alternative 7, 24 assertions) red.
- mutation: Telegram back to `{6,12}` -> `TestTelegramToken` (13-digit id in text, in JSON, in a URL) and `TestEveryKeyLikeShape` (alternative 2) red.
- mutation: the PEM rule without `PRIVATE KEY` (any BEGIN) -> `TestPrivateKey`: "a certificate is no private key" red.
- mutation: one character of `KEYLIKE` changed (`{20,}` to `{21,}` in the dop alternative) -> `bash docker/tests/test-redact-shapes.sh` FAIL naming both files, exit 1.
- mutation: `Walk` matches data with `data [ value` again -> `TestGlobalHits` (16-bit, nested, count) and `TestGlobalHitsMessageBody` red.
- mutation: `Holds` does not recurse (`element [ value`) -> `TestGlobalHits` (nested, count) red.
- mutation: `HoldsSubscript` back to a plain `[` on each subscript -> `TestGlobalHits` (list subscript, count) red.
- mutation: the guard's stream check always 0 -> `TestNoMessageBodyHoldsAGlobalStream` red (the control not found).
- mutation (after the review patches): `Walk`'s root-node line back to `data [ value` alone -> `TestGlobalHits` red (the root-node row and the count); the PEM rule removed again -> `Test.Bridge.Audit.TestNewKeyShapesInNoEntry` red on the PEM header and body in the data and in the description. Each reverted byte for byte; the class green again on the same stack; `Test.Eval.KeyProof` also green on a fresh stack (156 s call, 4.8 s class).

**Measured at implementation (Verification runs; the machine was shared with other lanes, so wall times include contention):**
- Loop: `test-redact-shapes.sh`, `test-boundaries.sh`, `test-ci-config.sh` pass; `Test.Bridge.Redact` 2.9 s, `Test.Eval.KeyProof` 3.9 s, `Test.Bridge.Audit` 2.6 s and `Test.Bridge.Steps` 0.9 s pass on the warm stack.
- `bash ci/checks.sh`: "checks: all scripts passed", 14 min wall (other lanes' runs were using the machine; `redact-shapes` itself 0 s).
- `eval/key-proof.sh` on fresh `e30s8i`, after the change: exit 0, "eval/key-proof: all checks passed"; globals line: 4,110,069 nodes of 798 globals in 16 databases, control found 188 times, 18.76 s (before: 4,258,041 nodes, 801 globals, 3.19 s). `Walk` now decodes `$List` values per node and every subscript, so the globals scan is slower per node; the node counts differ between the two stacks, so the ratio is approximate. DW-589's figures: the scan stays under 20 s.
- Shards (fresh, one part per call; wall seconds from the call): `lane-a` 1/6 491 (20 classes), 2/6 196, 3/6 200, 4/6 540, 5/6 415, 6/6 474; `lane-b` 1/3 271, 2/3 250, 3/3 403. All passed, no failure, no flake rerun. `Test.Core.ThreadProduction` ran and passed (8.58 s). Parts 1, 4, 5, 6 of lane-a and part 3 of lane-b ran while other lanes loaded the machine.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `Redact.PatternList` now replaces `dop_v1_` tokens, PEM private-key blocks (BEGIN through END, or to the end of the text or JSON string value) and Telegram ids of 6 or more digits, so every alternative of `KEY_LIKE_ERE` is covered (DW-386). `Test.Eval.KeyProof.Walk` decodes `$List` values in data and in subscripts, nested lists included (DW-448), and Task 0 measured that no message-body class holds a global stream (branch N), guarded by `TestNoMessageBodyHoldsAGlobalStream`.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls`: the new rules and the doc.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`: the four shape tests, `KEYLIKE`, `TestEveryKeyLikeShape` and its helpers.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Audit.cls`: `TestNewKeyShapesInNoEntry` (the Integration AC).
- `src/ocutalon/cls/OcuTalon/Test/Eval/KeyProof.cls`: `Holds`, `HoldsSubscript`, `LISTDEPTH`, the extended `TestGlobalHits` (root row included), `TestGlobalHitsMessageBody`, the stream guard.
- `docker/tests/test-redact-shapes.sh` (new) and `ci/units.sh` (`CHECK_SCRIPTS`): the drift check.
- This spec: Design Notes (the measurement and the Walk change for Story 31.4) and Verification records.

**Review.** 23 findings from the layers in 16 rows: 5 rows patched (all low), 0 deferred, 11 rejected with the reasons in the Review Triage Log. Follow-up review recommended: false (patched counts: high 0, medium 0, low 5).

**Verification.** `test-redact-shapes.sh`, `test-boundaries.sh`, `test-ci-config.sh` and `ci/checks.sh` pass; `Test.Bridge.Redact`, `Test.Eval.KeyProof`, `Test.Bridge.Audit` and `Test.Bridge.Steps` pass on the warm stack, `Test.Eval.KeyProof` also fresh after the patches; `eval/key-proof.sh` passes on a fresh stack; `lane-a` parts 1 to 6 and `lane-b` parts 1 to 3 pass; the mutations are recorded under Verification.

**Residual risks.** `Walk` is about six times slower per node on the globals scan (18.76 s against 3.19 s on about 4.1 million nodes, the stacks differing); the saved AI session history (`%AI.Agent.Session.ContextData`, a compressed global stream) is still unreadable to `Walk` and out of U-185's scope; DW-450 reopens (Lane B's walk copy, Story 31.4, the exact change is in Design Notes).
