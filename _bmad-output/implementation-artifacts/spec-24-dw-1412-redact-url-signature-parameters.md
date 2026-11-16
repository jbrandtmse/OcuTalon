---
title: 'DW-1412: Redact.Text redacts URL signature parameters'
type: 'security'
created: '2026-11-16'
status: 'done'
baseline_revision: '415e837b772d8a9b3782c95e3127a1bcca8dcc37'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-24-4a-show-setting-values-redacted-everywhere-and-the-setting-chan.md'
warnings: []
deferred:
  - summary: >-
      The unquoted value of the SENSITIVEKEYS rule (KeyPattern) still takes a backslash before a closing escaped quote, so in escaped JSON `token=abc\"` comes out as `token=[redacted]"`.
    evidence: |-
      Pre-existing shape of KeyPattern's last pattern (`[^\s"',;&]+`), not caused by DW-1412; the bare-name rule now stops before `\"`. Display-only: nothing leaks. It touches X-Amz-Security-Token only when that parameter is the last one of a URL inside escaped JSON (S3 presigned URLs end with X-Amz-Signature, so rarely).
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Redact.cls (PatternList, the keys pattern)
    severity: low
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Bridge.Redact.Text` (the one redactor, AD-31 and the Redaction convention) does not catch common URL signature query parameters. An Azure SAS URL (`...?sv=...&sig=<secret>`) or an S3 presigned URL (`...&X-Amz-Credential=...&X-Amz-Signature=<secret>&X-Amz-Security-Token=...`) in a setting value is shown unredacted on the web card, the evidence panel, the phone page and Telegram (Story 24.4a's display paths), and in any log line that passes through `Redact.Text` (DW-1412, a SECURITY item that blocks the 1.0.12 cut).

**Approach:** add these query parameters to `Redact.Text`, case-insensitive: `sig=`, `signature=`, `X-Amz-Signature=`, `X-Amz-Credential=`, `X-Amz-Security-Token=`, `auth=`. Redact the VALUE only and keep the parameter name, so a URL stays readable: `...&sig=[redacted]`. One redactor; no web redactor; logs get the same redaction because they already pass through `Redact.Text`.

## Boundaries & Constraints

- Files: `src/bridge/cls/OcuTalon/Bridge/Redact.cls` (the rule and its class-doc bullet; a Lane A shared file, the edit granted by the Contest Planner), `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls` (pins), and, only if needed for the log pin, an existing Lane A test that already scans a log line through `Redact.Text`. `docker/tests/test-redact-shapes.sh` only if it enumerates the shapes.
- The parameter value ends at the next `&`, `#`, whitespace, a quote (real or escaped), or the end of the text, exactly as the existing bare `key=` shape bounds its value (reuse that rule; Rule 2).
- A parameter name matches only as a whole query-parameter name: preceded by `?`, `&`, the start of the text or a non-name character (not a letter, digit, `_`, `.` or `-`), so `designature=`, `mysig=` and `oauth=` are kept. Match the name case-insensitively.
- `Redact.Text` stays idempotent (`Text(Text(x)) = Text(x)`), never throws, and fails closed as today.
- No other behaviour of `Redact.Text` changes. The display-only JSON reformat is accepted (Planner).

</intent-contract>

## Tasks & Acceptance

**Execution:**
- [ ] `Bridge/Redact.cls`: add the six signature parameters as one rule beside the bare `key=` shape (same value boundary, same "not preceded by" guard on the name), and add the shapes to the class-doc bullet that lists the patterns.
- [ ] `Test/Bridge/Redact.cls`: a new `TestUrlSignatureParameters` that pins, through the existing `Check` helper:
  - an Azure SAS URL `https://acct.blob.core.windows.net/c/b?sv=2022-11-02&ss=b&sp=r&se=2026-12-01T00:00:00Z&sig=<fragment-built secret>` gives `...&sig=[redacted]` with every other parameter unchanged;
  - an S3 presigned URL with `X-Amz-Algorithm`, `X-Amz-Credential=<id>/...`, `X-Amz-Date`, `X-Amz-Expires`, `X-Amz-SignedHeaders`, `X-Amz-Signature=<hex>` and `X-Amz-Security-Token=<t>` gives each of the three named values `[redacted]` and the other parameters unchanged;
  - `signature=` and `auth=` in any letter case (`SIG=`, `Auth=`) are redacted, value only;
  - a plain URL `https://example.test/orders?page=2&sort=asc` is returned unchanged, and so are `designature=1`, `mysig=1`, `oauth=1`;
  - the escaped-quote form inside JSON text is redacted, and `Text(Text(x)) = Text(x)` for each case.
  Build secret values from fragments (no literal secret in the repository).
- [ ] **Log pin:** a test shows a log line gets the same redaction: write a warning or event-log line through the product's redacting path (`$$$LOGWARNING(... Redact.Text(...))` as `Fix/Run.cls` does, or the existing log-scan helper the Watch/Fix tests use) with an S3 presigned URL, and assert the stored log text holds `X-Amz-Signature=[redacted]` and not the signature.
- [ ] **Lifetime pin (Planner, same commit):** `Test.Watch.SettingCause` `TestValuesLifetime` already asserts that the test seam `Fix.Executor.Lifetime` can only shorten the 60 s lifetime (a global above 60 or not a whole number gives 60). Re-run it and re-demonstrate its mutation (`Lifetime` without its upper bound -> red), recording the mutation line in `## Verification`; add an assertion only if a lengthening case is missing.
- [ ] If `docker/tests/test-redact-shapes.sh` enumerates the shapes, add the new ones there.

**Acceptance Criteria:**
- Given an Azure SAS URL, an S3 presigned URL or any text holding `sig=`, `signature=`, `X-Amz-Signature=`, `X-Amz-Credential=`, `X-Amz-Security-Token=` or `auth=` as a query parameter, when it passes through `Redact.Text`, then each such value is `[redacted]`, the name and every other parameter are unchanged, and a plain URL is unchanged. Mutation: drop the new rule -> `TestUrlSignatureParameters` red; drop the "not preceded by" guard -> red (`mysig=`, `oauth=` kept).
- Given a log line written through the product's redacting path, when it holds a presigned URL, then the stored line holds the redacted value. Mutation: the log path skips `Redact.Text` -> the log pin red (or, if the path is shared, drop the new rule -> red).
- Given the `Fix.Executor.Lifetime` test seam, when the test global asks for more than 60 s, then the lifetime is 60. Mutation: `Lifetime` without its upper bound -> `TestValuesLifetime` red.

## Spec Change Log

- 2026-11-16 (lead). Chartered by the Contest Planner's ruling "DW-1412 and the 24.4a notes" (~03:45Z Nov 16, BINDING), quoted from `<coordination>/prompts/story-244-rulings-20261115.md`:

  > ### DW-1412: a SECURITY follow-up that BLOCKS the 1.0.12 cut
  > Add these query parameters to Redact.Text, case-insensitive: sig=, signature=, X-Amz-Signature=, X-Amz-Credential=, X-Amz-Security-Token=, auth=. Redact the VALUE only and keep the parameter name, so the URL stays readable: ...&sig=[redacted]. Pin each of these: an Azure SAS URL; an S3 presigned URL; a plain URL with ?page=2, unchanged; a log line, to show logs get the same redaction. Owner: lane D, which knows Redact.Text from 24.4a. Do it FIRST, ahead of 24.4b. Redact.Text is a Lane A shared file, and the edit is granted.
  > ### Fix.Executor.Lifetime
  > The test seam is accepted. In the same commit, PIN that it can only shorten the lifetime, never lengthen it.
  > ### Accepted
  > DW-1413; the display-only JSON reformat.

  Branch `OCT-epic24-dw1412` from feature cdd250d0 (Story 24.4a merged).

## Review Triage Log

### 2026-11-16 -- Review pass
- verdicts: 22 findings -- high 0, medium 1, low 17, false 4, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: X-Amz-Security-Token in BARENAMES is redundant with the `token` rule and the BARENAMES comment said none of the names is a SENSITIVEKEYS name -- real as a wrong comment; the comment now says it ends with `token`, is also replaced by that rule and is listed so its value is replaced whichever rule reads it (the exact output is pinned in the S3 tests).
  - `[low]` `[defer]` Blind: the backslash fix covers only the bare-name rule, so `token=abc\"` in escaped JSON still loses its backslash -- pre-existing KeyPattern behaviour, not caused by this story; display-only, nothing leaks; recorded under `deferred`.
  - `[low]` `[reject]` Blind: `(sig=<secret>)` swallows the closing bracket and a test pins it -- fails closed, identical to the existing key= value rule, and the fix would add a bracket set to a shared value class; the test description now says so.
  - `[low]` `[reject]` Blind: other providers' signatures (X-Goog-Signature, AWSAccessKeyId, CloudFront) and `auth=none` over-redaction -- the intent lists the six names explicitly, so more names are outside it; `auth=` anywhere is the specified guard.
  - `[false]` `[reject]` Blind: the `Fix.Executor.Lifetime` mutation line is unrelated -- the spec's task and the Planner's ruling require it in this commit.
  - `[low]` `[reject]` Edge: `%26sig=` inside an encoded nested URL is not matched -- the contract's name guard says a name preceded by a letter or digit is kept (`%26` ends in a digit); spec-bound, by-design.
  - `[low]` `[reject]` Edge: X-Goog-Signature, X-Goog-Credential, oauth_signature -- outside the six names the intent lists; `oauth` and `_`/`-`-prefixed names are kept by the contract.
  - `[low]` `[reject]` Edge: `#` and closing brackets do not end the value -- the contract says "end at `#`" and also "exactly as the existing bare key= shape bounds its value (reuse that rule)"; the existing rule does not stop at `#`. Decided in-stage: reuse (fail closed: an unusual fragment is over-redacted, never leaked; ending at `#` would also change `key=` and could leak the tail of a secret holding `#`). Not pinned either way.
  - `[low]` `[reject]` Edge: an unclosed escaped quote (`sig=\"VALUE` with no closing `\"`) is not redacted -- the shape of a truncated JSON key of an existing rule, no bare-name URL form of it; theoretical hardening, would need a new fallback rule.
  - `[low]` `[reject]` Edge: a doubled escape `\\\"` directly after a value -- theoretical (JSON nested twice around a signature); no user-reachable case shown.
  - `[false]` `[reject]` Edge: `(?:x|y)+` may overflow ICU's stack on a very long value -- measured: a 300000-character `sig=` value was replaced and the class passed on the warm stack, so no overflow at that size; the probe was not kept.
  - `[low]` `[reject]` Edge: `auth=none` or `auth = true` is redacted in non-URL text -- the specified guard allows any non-name character before the name, and the intent says `auth=` is redacted; spec-bound, by-design.
  - `[low]` `[patch]` Edge: the test misses whitespace-ended, empty-value and (unclosed-quote) cases -- added a whitespace-ended and an empty-value Check; `#` is left unpinned by the in-stage decision above; the unclosed quote is theoretical.
  - `[low]` `[patch]` Edge (claim): the key= value boundary changed (a backslash before `"` ends it) and nothing pins it for key= -- the change is required by the contract's "escaped quote ends the value"; added a `key=` escaped-JSON Check.
  - `[medium]` `[patch]` Verification gap: the `\(?!")` alternative of the bare-name value has no test or mutation -- added `a?sig=ab\cd9Z&b=1` (a backslash inside a value is part of it) and recorded its mutation line.
  - `[low]` `[patch]` Verification gap: X-Amz-Security-Token in escaped JSON is not pinned, and dropping its BARENAMES entry alone stays green because the `token` rule redacts it -- added an S3 escaped-JSON Check with the token in the middle of the URL; the redundancy is stated in the BARENAMES comment, and a token as the last parameter in escaped JSON is the deferred pre-existing item.
  - `[low]` `[reject]` Verification gap (other): `#` is not a terminator although the contract lists it -- same in-stage decision as the Edge row.
  - `[false]` `[reject]` Intent: tests exercise Redact.Text and one log line, not the card, panel, phone and Telegram -- the display paths call `Redact.Text` (Watch/SettingCause, Live/Payload/Approval, Watch/EvidencePack, Channel/Telegram/Out; Story 24.4a pins them) and the intent says one redactor, no web redactor.
  - `[false]` `[reject]` Intent: the shared value alternative may also be KeyPattern's -- only the bare-name patterns changed; KeyPattern's value class is untouched (the diff).
  - `[low]` `[reject]` Intent: `#` is not in the value's terminators -- same in-stage decision as the Edge row.
  - `[low]` `[reject]` Intent: bare names are redacted outside URLs (`auth=basic`) -- the contract's guard is "not a name character", spec-bound.

## Design Notes

- Governing ADs: AD-31 (the one redactor; the bridge names no OcuTalon package, AD-2), the Redaction convention (Consistency Conventions), AD-17 (logs).
- `X-Amz-Security-Token` may already be caught by the SENSITIVEKEYS `key=value` rule (its normalized name ends with `token`); the new rule must still keep the name and redact only the value, and the pin asserts the exact output.
- Decided in-stage: (1) the value rule is the existing bare `key=` value rule, as the contract says, so `#` does not end a value (the contract's "ends at `#`" conflicts with "exactly as the existing rule"; reuse fails closed); (2) a backslash directly before a double quote ends an unquoted bare-name value, so escaped JSON keeps its escaped quote; this also applies to `key=` and is the one change beyond the six names; (3) the six names are added to `key` as the `BARENAMES` parameter of one rule, extending the sibling (Rule 2); (4) the log pin extends `Test.Checks.Runs` `TestBeatLogsAreRedacted`, an existing Lane A test that already scans the LOGBEAT warning line (the spec allows it).
- Ledger: DW-1412 is resolved by this commit (`status=resolved-by:...` appended by the lead at merge time if no tracker key exists).

## Verification

Lane D: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'`, warm tag `e24dw12w`, fresh tag `e24dw12`. One class per foreground call (about 150 s each).
- (once) warm up `e24dw12w`.
- (loop) `ci/iris.sh class OcuTalon.Test.Bridge.Redact` (warm) -- passed.
- (once) `ci/iris.sh class OcuTalon.Test.Watch.SettingCause` (warm) -- passed (`TestValuesLifetime`).
- (once) the log pin's class (warm) -- passed.
- (once) every class that asserts `Redact.Text` output (`Test.Bridge.Redact`, `Test.Watch.SettingValues`, `Test.Channel.TelegramOut`, `Test.Core.SecretHandoff` if it does, any Audit/log scan class) -- passed.
- (once) `bash docker/tests/test-redact-shapes.sh` and `bash docker/tests/test-class-rules.sh` -- exit 0.
- (once) fresh `ci/iris.sh class OcuTalon.Test.Bridge.Redact` on tag `e24dw12` -- passed.
- (once) warm down.
- mutation: BARENAMES cut back to `key` (the new rule dropped) -> `Test.Bridge.Redact` `TestUrlSignatureParameters` red.
- mutation: the "not preceded by" guard removed from `BareKeyPattern` -> `TestUrlSignatureParameters` red (`designature=`, `mysig=`, `oauth=` redacted) and `TestSettingValueShapes` red (`monkey=`).
- mutation: the new rule dropped (shared log path) -> `Test.Checks.Runs` `TestBeatLogsAreRedacted` red (the stored LOGBEAT line holds the signature).
- mutation: `Fix.Executor.Lifetime` without its upper bound (`$Number(..., "I", 0)`) -> `Test.Watch.SettingCause` `TestValuesLifetime` red (the test global 600 and 61 give 600 and 61, not 60). Each mutated file reverted and confirmed byte-identical (`cmp` against a scratch copy, `git diff` clean for Executor.cls).
- mutation: the `|\(?!")` alternative removed from the bare-name value class -> `Test.Bridge.Redact` `TestUrlSignatureParameters` red ("a backslash inside a value is part of the value"); reverted, `cmp` identical to the scratch copy, class green again on the same warm stack.
- Review patches (comments, and `TestUrlSignatureParameters` gains the backslash, whitespace, empty-value, `key=` escaped-JSON and escaped S3 with security token cases): `Test.Bridge.Redact` warm passed, `test-redact-shapes.sh` and `test-class-rules.sh` exit 0, fresh `Test.Bridge.Redact` on tag `e24dw12` passed; warm `e24dw12w` and fresh `e24dw12` torn down.
- Run: warm `Test.Bridge.Redact`, `Test.Checks.Runs`, `Test.Watch.SettingCause`, `Test.Watch.SettingValues`, `Test.Channel.TelegramOut`, `Test.Core.SecretHandoff`, `Test.Bridge.Audit`, `Test.Bridge.Steps`, `Test.Watch.Evidence`, `Test.Bridge.Gate`, `Test.Core.BridgeSink`, `Test.Bridge.Decide`, `Test.Bridge.Budget`, `Test.Fix.DryRun` passed; `test-redact-shapes.sh` and `test-class-rules.sh` passed; fresh `Test.Bridge.Redact` and `Test.Checks.Runs` (tag `e24dw12`) passed. `test-redact-shapes.sh` only compares KEYLIKE, so it needed no new shape. The log pin is in `Test.Checks.Runs` `TestBeatLogsAreRedacted` (an existing log-scan test of the Tick's LOGBEAT warning).

**Shared surfaces:** every test that asserts `Redact.Text` output (logs everywhere use it). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

Summary: `Redact.Text` now replaces the VALUE of `sig=`, `signature=`, `X-Amz-Signature=`, `X-Amz-Credential=`, `X-Amz-Security-Token=` and `auth=` (any case, whole-name guard), keeping the name; the bare `key=` rule was extended with a `BARENAMES` parameter (one redactor, no web change). Pins: Azure SAS, S3 presigned, plain `?page=2` URL unchanged, `designature=`/`mysig=`/`oauth=` kept, escaped JSON, idempotence, and the log pin (LOGBEAT warning line). `TestValuesLifetime` already pinned that `Fix.Executor.Lifetime` can only shorten the lifetime; its mutation was re-demonstrated, no assertion added.

Files changed:
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls`: `BARENAMES`, `BareKeyPattern` over it, the backslash-before-quote end of an unquoted bare-name value, class-doc bullet.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`: `TestUrlSignatureParameters`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls`: presigned URL in `TestBeatLogsAreRedacted` (the log pin).
- This spec: Verification, Review Triage Log, Design Notes, Auto Run Result.

Review findings: 22 (4 layers). Patches applied: 5 (1 medium, 4 low; the missing backslash pin and its mutation, the key=, whitespace, empty-value and escaped security-token pins, the BARENAMES comment). Deferred: 1 (KeyPattern keeps the backslash before an escaped quote, pre-existing, display-only). Rejected: 16, each with its reason in the Review Triage Log (spec-bound guard or name list, `#` decided in-stage, theoretical, or false).

Follow-up review recommended: false (one medium patched, no high).

Verification: warm `Test.Bridge.Redact`, `Test.Checks.Runs`, `Test.Watch.SettingCause`, `Test.Watch.SettingValues`, `Test.Channel.TelegramOut`, `Test.Core.SecretHandoff`, `Test.Bridge.Audit`, `Test.Bridge.Steps`, `Test.Watch.Evidence`, `Test.Bridge.Gate`, `Test.Core.BridgeSink`, `Test.Bridge.Decide`, `Test.Bridge.Budget`, `Test.Fix.DryRun` passed (before the review patches; the patches changed comments and `TestUrlSignatureParameters` only); after them warm and fresh `Test.Bridge.Redact` passed and the two shell checks exited 0. Mutations observed red: new rule dropped (`TestUrlSignatureParameters`), name guard removed (`TestUrlSignatureParameters`, `TestSettingValueShapes`), rule dropped on the log path (`TestBeatLogsAreRedacted`), `Lifetime` without its upper bound (`TestValuesLifetime`), backslash alternative removed (`TestUrlSignatureParameters`).

Residual risks: `#` does not end a value (over-redaction, fails closed); the deferred escaped-quote item; no end-to-end browser or Telegram pin of an SAS or S3 URL (Story 24.4a pins those surfaces with other URL shapes).
