---
title: 'DW-1412: Redact.Text redacts URL signature parameters'
type: 'security'
created: '2026-11-16'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-24-4a-show-setting-values-redacted-everywhere-and-the-setting-chan.md'
warnings: []
deferred: []
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

## Design Notes

- Governing ADs: AD-31 (the one redactor; the bridge names no OcuTalon package, AD-2), the Redaction convention (Consistency Conventions), AD-17 (logs).
- `X-Amz-Security-Token` may already be caught by the SENSITIVEKEYS `key=value` rule (its normalized name ends with `token`); the new rule must still keep the name and redact only the value, and the pin asserts the exact output.
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

**Shared surfaces:** every test that asserts `Redact.Text` output (logs everywhere use it). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
