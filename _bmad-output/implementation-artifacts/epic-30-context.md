# Epic 30 Context: Lane A post-demo hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 30 holds the Lane A parts of the demo-path stories that were moved after the demo path: compaction of long conversations, scheduled purges, exactly-once replay of an approved tool call, once-only stopped-production and disabled-item findings, and honest mixed or unfinished resend results. Every part lands before 1.0.0. Stories 30.1 to 30.6 are done. Story 30.7, the burn-down, is deferred until after the v1.0.0 tag. The remaining work for 1.0.0 is Story 30.8, a fix-forward that pulls two owner-kept conditions out of 30.7. The product redactor must replace every key shape the boundary scan flags. The release candidate's key proof must find a key stored inside a `$List`. Together these mean no key can reach a trace or log in a shape the redactor misses, and the key proof can't pass over a key stored in a list.

## Stories

- Story 30.1: Long conversations are compacted under the limit (done)
- Story 30.2: Old messages and records are purged on schedule (done)
- Story 30.3: An approved tool call runs exactly once, with no model (done)
- Story 30.4: A stopped production or a disabled item is reported once (done)
- Story 30.5: Mixed and unfinished resends say how far they got (done)
- Story 30.6: The invalid-reply warning names what failed, never the reply (done)
- Story 30.7: Epic 30 burn-down (deferred after the v1.0.0 tag, set aside as one patch)
- Story 30.8: The redactor and the key proof catch every key shape (backlog, next)

## Requirements & Constraints

**Story 30.8 (fix-forward before 1.0.0, full QA and code review).** The owner-kept conditions are unchanged and must be met exactly.

- **DW-386 (U-184), the redactor.**
  - `OcuTalon.Bridge.Redact` replaces every shape that `key_like` flags. That includes DigitalOcean `dop_v1_...` tokens and PEM private-key headers (`-----BEGIN ... PRIVATE KEY`).
  - It also replaces the Anthropic key (`sk-ant-...`) and the Telegram bot token (digits, a colon, then 35 characters), even where `key_like` lacks them.
  - Each shape gets its own test.
  - `key_like` is defined once, in `docker/tests/lib-keys.sh`. `test-boundaries.sh` and the eval run both read it from there. Read the definition on the current tree: Epic 11 part 1 changed `test-boundaries.sh`, and that is why the branch was integrated forward before 30.8.
- **DW-448 (U-185), the key proof.**
  - `Test.Eval.KeyProof`'s `Walk` decodes `$List` elements, nested lists included, so a key stored as one element is found. Today `Walk` matches only contiguous 8-bit bytes within a single node.
  - Measure on a throwaway whether a message body can store a key in a compressed or split `%Stream.Global*` chunk. Background: `%Stream.GlobalCharacter` compresses, and a block of 1 KB or more is zstd-compressed.
    - If it can, `Walk` decodes those chunks too.
    - If it can't, that half closes `wontfix-accepted`, and the ledger entry records the evidence: the throwaway's build, the message class and what was stored.
  - The release candidate's key proof is otherwise unchanged.
  - Lane B's copy of the walk (`Test.Web.SessionEvents.ReferenceHits`, DW-474) stays with its own entry. Don't edit it here.

**Story 30.7 (deferred, not in 1.0.0).** It keeps owner `30-7` for DW-437 (whole-turn purge, U-210), DW-444 (interrupted replay), DW-470 (provider-unreachable replay text, U-214), DW-462 (approval flake), DW-371, DW-541 and DW-581/582/588/589/590. DW-495 and DW-584 join it at integrate-forward. None of these is in scope for 30.8.

## Technical Decisions

- **One redactor.** `OcuTalon.Bridge.Redact` is used by agent steps, audit, logs and error details. Structural rules come first, and the redactor is the backstop. It belongs to the bridge (`src/bridge`, Lane A), and both the bridge and OcuTalon call it.
- **The key proof.**
  - `bash eval/key-proof.sh` builds a fake key at run time. It feeds the key into a `--release-candidate --on-mock` run whose requests reach only the CI mock.
  - The run must prove the key appears in no global, store, trace message, log, container file, output or file under `eval/`, and that its throwaway is gone.
  - The result pair is scanned with `lib-keys.sh`'s patterns, and a match exits 4.
- **Throwaways only.** Do the measurement on a throwaway stack. Never touch shared runtime. Never load anything from `irislib/` or `irissys/`; read them only for reference.
- **Stored data is append-only.** Never rename, retype or remove a stored property, and never hand-edit a `Storage` block. CI diffs storage blocks against the last release tag.
- **Spine lint.** The baseline is `ok: false` with 8 low findings, and it must not get worse.

## Cross-Story Dependencies

- **The set-aside patch.** 30.8's implement starts from the parts of `_bmad-output/implementation-artifacts/set-aside/30-7-epic-30-burn-down-1.patch` that cover these two entries: the hunks in `Bridge/Redact.cls`, `Test/Bridge/Redact.cls` and `Test/Eval/KeyProof.cls`.
  - That build was never QA'd or code-reviewed. Its note says no message-body class has a `%Stream` property. Treat that as a lead to re-measure, not as evidence.
  - Take only those hunks. The rest of the patch stays with 30.7.
- **Lane B's copy of the walk.** Changing how `Walk` matches a node reopens DW-450 (the duplicated walk) until Lane B's copy gets the same decode. That copy is DW-474, owned by Story 31.4 (Epic 31). Name the change so 31.4 can mirror it.
- **Final steps.** The epic finishes with the final integrate-forward and the CI repack (an eighth group, `shards-3`). Then it completes as partial, with 30.7 held out. Epic 13 is the critical path to rc1.
