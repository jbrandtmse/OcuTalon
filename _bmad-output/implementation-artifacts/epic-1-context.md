# Epic 1 Context: Every item gets an attention decision you can audit and afford

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 1 builds the bridge's decision core in Lane A. It has three AI Hub agents on Claude Haiku 5.5, one agent-runner operation per agent, and the `Decide` process. Together they give every item exactly one recorded attention decision, with its reasons, confidence, tokens and cost, and every model request and tool call shows as an agent step in Visual Trace. An unusable reply takes a fallback route that never acts, and OcuTalon starts safely with no model key. Stories 1.1 to 1.12 are done. The last story, the burn-down (1.13), fixes a cross-epic defect found from Epic 2: in a web request, a missing model key reads as present. The page then shows no "no model key" warning, which is a false all-clear. The fix must land in Epic 1 before the merge and is never moved to a later epic.

## Stories

- Story 1.1: Every agent runs on Claude Haiku 5.5 through the Config Store
- Story 1.2: Agent runners send every request under the model rules
- Story 1.3: Decide records exactly one attention decision per item
- Story 1.4: Every turn and decision carries its tokens and cost
- Story 1.5: Every model request and tool call is an agent step in Visual Trace
- Story 1.6: An unusable reply takes the fallback route, and OcuTalon starts with no key
- Story 1.7: Timeouts and rate limits end every decision on time
- Story 1.8: Conversations survive restarts
- Story 1.9: No model request goes over 100,000 tokens
- Story 1.10: The chat agent sets, lists and cancels reminders
- Story 1.12: Items saved for the digest are kept for it
- Story 1.13: Epic 1 burn-down (DW-149)
- (Story 1.11 moved whole to Story 30.2.)

## Requirements & Constraints

- **The key read in a web request (DW-149).** Take a process that holds only the API web application's roles, without `%Admin_ConfigStore`, as Epic 2's `/ocutalon/api` `/state` does, with no model key configured. When it asks whether a runner's key is set, through `Keys.Status(agent)` or a read that replaces it for that caller, the answer must be "missing".
  - A read that is refused or fails never reads as present.
  - A state that can't be known never passes as OK.
  - The key's value never reaches the request.
  - The read writes no audit refusal on each call (today each `/state` audits three, one per runner).
- **The pinning test** runs the read in that request context, or its exact equivalent, with no key configured, and asserts that it reads as missing.
- **`Budget.State()`** must either work in that request context or degrade there without a warning on every call.
- **No false all-clear** is a non-negotiable, and its chat rule binds from release 1. The page must never look all-clear while no model key is set. An all-clear comes only from code, never from the model or from a guess.
- **With no model key,** every production item runs and nothing fails. Every decision falls back with `no_key`, and the web app shows the "no model key" banner.
- **Keys** come only from the environment, as an `@{env:VAR}` placeholder that only AI Hub's provider resolves.
  - A key is never stored in IRIS or shown.
  - No log line, error detail, agent step or return value holds a key.
  - The `Keys` methods return only 0 or 1 and never throw.
- **Rules from the earlier stories still apply:** one decision per (item, kind); a fallback is `tellnow` and triggers no tool, fix or approval; no sampling parameters; output capped at 8,000 tokens; under 100,000 input tokens per request.

## Technical Decisions

- **Config Store entries.** The entries are `AI.LLM.OcuTalon<Agent>`.
  - At install, only `OcuTalon.Install.Step.Provider` writes them. At run time, only `OcuTalon.Bridge.ConfigStore.Merge` changes them (called by `SettingsOps`, which then restarts the runners).
  - Each runner's `ProviderConfig` is `@{config:OcuTalon<Agent>}`.
  - Entries keep the default `%Admin_ConfigStore` resource for read and edit. Only production jobs read them, and the production runs as the Interoperability system user with `%All`. Widening the web roles so a request can read entries goes against this rule.
- **`OcuTalon.Bridge.ConfigStore` is the one bridge class that reads entries.**
  - `Details` returns an entry with its placeholders unresolved, so a caller never logs or returns it.
  - `EntryOf` takes the entry name out of an `@{config:}` reference, and `FullName` gives an entry's full name.
  - `KEYPATTERN` is the only allowed form of `api_key`: one `@{env:NAME}` placeholder.
- **Status reads.** `StatusMonitor` and `/state` read key presence only through `Keys.Status(agent)`. They read the cost cap only through `Budget.State()`, which returns spent, cap, capped and resetsAt, in UTC.
- **`Keys` today:**
  - `Status` reads the runner item's `ProviderConfig` adapter setting through `Ens.Director`. It returns 0 when no production is active or the item is unknown. Otherwise `Present` decides.
  - `Present` gives 0 for an empty config. For an `@{config:}` entry it calls `Details` and judges the `api_key`, and it does the same for an inline JSON config. Any other form gives 1.
  - The `api_key` judgement: a missing or empty key is 0. A single `@{env:NAME}` is 1 only when that variable is set in the process. Any other value is 1.
  - **The defect:** `Status`'s `Catch` returns 1. When `Details` fails, `Present` falls back to `%ConfigStore.Configuration.Exists`, which also gives 1.
  - **The tension:** `Decide`'s precheck (`noKey`) also calls `Keys.Status(runner)` inside production jobs. There, counting "unknown" as present is deliberate: it never blocks a setup the bridge can't judge, and the runner's own failure is classified instead. A fix must keep that precheck correct while the web read never turns "unknown" into OK.
  - The current tests in `OcuTalon.Test.Bridge.Keys` assert that `Status` equals `Present` of each runner's config.
- **`Budget` today:**
  - `State(now, .faults)` sums `CostUSD` from `OcuTalon_Bridge_Data.Usage` with a dynamic SQL `SELECT`. Without an SQL grant, that query fails, logs `$$$LOGWARNING` on every call and counts the spend as 0.
  - It reads `Decide`'s settings `DailyCostCapUSD`, `GatewaySpendUSD` and `GatewaySpendDate` through `Ext.Accessor.ValueFor`.
  - It reads the day's mark in `^OcuTalonBP.UsageCapped(day)`, which `MarkCapped` sets once under a lock.
  - Faults that weaken the cap go into the `faults` output (DW-76).
- **Web applications and roles.**
  - `/ocutalon` and `/ocutalon/api` share one CSP session and one sign-in group, `OcuTalon`.
  - `OcuTalonUser` holds no database resources itself. Both applications grant `APPLICATIONROLES`, which are only the code, data and private database roles: no `%Admin_ConfigStore` and no SQL grants.
  - The API's own queries are prepared without the SQL privilege check, but only in `Session.ForUser` and `Live.Event.Since`. A CI allow-list keyed by class and method fails any other unchecked prepare.
- **Privilege limits.**
  - No role may grant more than the security overview says.
  - No OcuTalon role holds `%All`, `%Development` or the `%Ens_*` edit, discard, run or config resources.
  - The service user `OcuTalonService` is a privilege profile only.
  - Areas declare their grants in `Grants()`, and one Lane A step composes every role from them.
- **Bridge boundary.** `OcuTalon.Bridge` references no other OcuTalon package, and a CI check enforces this. It reaches its host only through the extension classes named in settings, and it never reads the public settings.
- **Ownership.** `OcuTalon.Web.Api` and `OcuTalon.Install.Step.Web` belong to Lane B. Ask Lane B for changes there.
- **Tests** are `%UnitTest` classes named `OcuTalon.Test.<Area>.<Subject>`. Bridge tests run in the `lane-a` shard. Hosts log through `$$$LOG*`, nothing secret is logged, and `%Status` is used throughout.

## UX & Interaction Patterns

- **No model key, local install:** an unclosable warning banner says every decision uses fixed rules and explains how to add `ANTHROPIC_API_KEY` to `.env` and restart. It links to the README with "How to set a key".
- **Decisions without a key** show the fallback flag with the reason "no model key is set".
- The bridge never renders text for the user. The page and the catalog do that.

## Cross-Story Dependencies

- **Where the defect came from.** DW-149 (Epic 2's DW-148) was found by Epic 2 while planning Story 2.10. Epic 2's `/state` sets `noModelKey` from `Keys.Status(agent)` and shows the budget banner from `Budget.State()`. Agree any change to that call with Lane B.
- **What Story 1.13 builds on:**
  - Story 1.6: `Keys.Status` and the `no_key` precheck.
  - Stories 1.4 and 1.6: `Budget.State`, `MarkCapped` and the DW-76 faults.
  - Story 1.1: the Provider step and the Config Store merge.
- **Lane B owns** `OcuTalon.Core`, `.Msg`, `.Web`, `.Data.Setting`, `.Data.Ownership` and most of `ci/`.
