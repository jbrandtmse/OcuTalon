# Epic 16 Context: Anyone can try the online demo

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 16 builds the repository side of the online demo. A visitor with no install and no key signs in from the splash with the published credentials, gets a session of their own that this browser resumes until the reset, sees the reset countdown, the busy state and the allowances, and leaves or signs out cleanly. Stories 16.1 to 16.9 are merged. The epic is re-opened for one launch-text hotfix, Story 16.11. On the live demo host, the splash's "Before you start" list promises Telegram and a QR code, but a signed-in visitor finds neither, because Telegram arrives only with Epic 12. The splash must promise only what the running release has, and local and IPM installs must not change.

## Stories

- Story 16.1: The online demo's settings arrive at start, and its public accounts are safe to publish (done)
- Story 16.2: The splash screen shows the demo and its sign-in details (done)
- Story 16.3: Signing in opens a session this browser resumes until the reset (done)
- Story 16.4: Leaving the page frees its place, and Sign out ends the session (done)
- Story 16.5: A full demo says it is busy, and the host's busy and maintenance pages are ready (done)
- Story 16.6: A probe checks the demo every 15 minutes (done)
- Story 16.8: The page counts down to the reset and waits it out (done)
- Story 16.9: Allowances cap messages, model cost and simulated emails (done)
- Story 16.11: The splash promises Telegram only when the release includes it

Stories 16.7 and 16.10 moved to 29.3 and 31.3.

## Requirements & Constraints

- **One switch decides.** Whether Telegram is in the release comes only from `OcuTalon.Channel.Telegram.In.Included()`. The README's `no-telegram` rule and `/state`'s Telegram block (`included`) read the same switch. It returns 0 until Story 12.7 turns it on. Tests can force it to 1 through the test-only global `^OcuTalonTest("TelegramIncluded")`, which only `OcuTalon.Test` classes set and the judges' install never does.
- **With `Included()` at 0:** the "Before you start" list has no Telegram line, and the allowance line is the new chat-only form, "Each session can send {limit} messages an hour in the chat."
- **With `Included()` at 1:** both of today's lines show word for word: "Have Telegram? You can scan a QR code inside to get the notices on your own phone." and "Each session can send {limit} messages an hour in the chat or Telegram."
- **`{limit}` is unchanged.** It is still the per-session message allowance from the public settings (50 an hour by default).
- **No text in code.** All three texts come from the message catalog: `splash.telegramLine`, `splash.limitLine` and a new key for the chat-only form.
- **Tests:** one test pins each state through the test-only switch, and every existing splash test stays green.
- **Flag off changes nothing.** The splash renders only when the online-demo flag is set, and the local sign-in page stays exactly as it is.
- **Timing:** merge into the feature branch before the online demo goes public on October 31 if possible. Otherwise it must merge before Epic 12 does, which is an accepted risk.

## Technical Decisions

- **Scope.** The planned change is Lane B's `OcuTalon.Web.Public.Splash` and the catalog lines only, with no dependency edges. Lane A owns `OcuTalon.Channel.Telegram` from Epic 12 on, so this story does not edit `In.cls`.
- **Open design point: how the switch reaches the splash.** Planning names no mechanism, so the spec must settle it. Three rules constrain the choice:
  - The splash lives in the public package (`OcuTalon.Web.Public`, in the `OCUTALON_PUBLIC` database). It renders with no roles, before sign-in.
  - A CI check fails the build if `OcuTalon.Web.Public` or `OcuTalon.Data.Public` references anything other than `%CSP`, dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` and each other. The check also reads `##class` calls and dynamic dispatch.
  - The splash reads public values only through `OcuTalon.Data.Public.Settings`.
  - So the splash can't simply call `Included()`. Whatever carries the value must still follow the test switch, and the spec must name any file the mechanism needs outside the planned scope.
- **The catalog copies.** The public package keeps its own copies of the texts it renders (the `Splash` parameters, such as `TELEGRAMLINE` and `LIMITLINE`). A test compares those copies with the `splash.*` catalog keys, so the chat-only form needs both a catalog entry and a matching copy. Elsewhere, the catalog's one renderer is `OcuTalon.Msg.Catalog.Render(key, slots, channel)`.
- **Splash security.** The styles come inline from the token stylesheet under the hashed `style-src`, with no `style=` attributes. The splash has one inline script, pinned by its hash in `script-src`. A change that touches either must keep the CSP pins in step.
- **Where tests go:**
  - The fixed-string test checks every splash text.
  - Flag-on checks go in the `online-demo` live unit and in `web/e2e-online/`, not in `web/e2e/demo-path/`.
  - The REL-2 online-demo run signs in from the splash and must keep passing.
- **Release names.** Where planning says 0.1.0 or 0.1.1, read 1.0.0. 1.0.0 is the first release and Telegram ships in it, so Epic 12 merges when it is done, and from that merge the splash shows the Telegram lines.

## UX & Interaction Patterns

- **Card order.** The "Before you start" card keeps its order: the reset schedule, the isolation line, the Telegram line (only when included), the allowance line, then the no-shell-commands and audit line. Nothing else on the splash changes.
- **Stale UX spec.** The UX spec's splash list (EXPERIENCE.md) still shows both Telegram lines unconditionally. Its amendment is pending (veto item U-196), so the story's criteria govern.

## Cross-Story Dependencies

- **Builds on:** Story 16.2's splash, its catalog copies and its tests, and Story 16.1's public settings (the `{limit}` value).
- **Downstream:** Story 12.7 turns `Included()` on, and from then the splash shows both Telegram lines with no further change. Epic 12 must not merge before this story.
- **Runner and order:** the re-open runs on runner B, after Story 5.12.
- **Not in this story's scope:** DW-378, the About-dialog tagline, is routed to the merged Story 16.4 and is settled at this epic's burndown.
