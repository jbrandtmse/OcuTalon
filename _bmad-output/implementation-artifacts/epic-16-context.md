# Epic 16 Context: Anyone can try the online demo

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 16 builds the repository side of the online demo. A visitor with no install and no key signs in from the splash with the published credentials and gets a session of their own, which this browser resumes until the reset. The visitor sees the reset countdown, the busy state and the allowances, and can leave or sign out cleanly. Stories 16.1 to 16.9 are merged. The epic is re-opened for one launch-text hotfix, Story 16.11. On the live demo host, the splash's "Before you start" list promises Telegram and a QR code, but a signed-in visitor finds neither, because Telegram arrives only with Epic 12. The fix is that the splash promises only what the demo has. The splash shows Telegram again only when Story 12.7 adds it.

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

Stories 16.7 and 16.10 moved to Stories 29.3 and 31.3.

## Requirements & Constraints

- **No gate.** The change applies unconditionally, with no release switch. The "Before you start" list shows no Telegram line. The allowance line always reads "Each session can send {limit} messages an hour in the chat."
- **`{limit}` is unchanged.** It is still the per-session message allowance from the public settings (50 an hour by default).
- **No text in code.** The chat-only allowance line gets its own new message-catalog key.
- **Keep the old keys.** `splash.telegramLine` and `splash.limitLine` keep their current text, word for word, because Story 12.7 brings them back.
- **Tests:**
  - Pin both that the Telegram line is missing and that the chat-only allowance line is shown.
  - The splash's existing tests and the public-text checks stay green.
- **Flag off changes nothing.** The splash renders only when the online-demo flag is set, and the local sign-in page stays exactly as it is.
- **Timing:** merge into the feature branch before the online demo goes public on October 31 if it can. Otherwise it must merge before Epic 12 does, which is an accepted risk.

## Technical Decisions

- **Why there is no gate (orchestrator ruling, veto U-197, option C):**
  - The splash can't call `OcuTalon.Channel.Telegram.In.Included()`, because the public package's allow-list forbids it.
  - Carrying the switch in a new public setting would amend the fixed key set of `OcuTalon.Data.Public.Settings`, and that amendment is the owner's.
  - The launch doesn't need it. The "Telegram included" case and its mechanism move to Story 12.7.
- **Scope:**
  - Lane B's splash class in `OcuTalon.Web.Public`, plus the catalog lines and their tests.
  - No Lane A file: not `OcuTalon.Channel.Telegram`, and not the installer's `Public` step or its tests.
  - No new public setting, and no read of `^OcuTalonTest`.
- **The public package's allow-list.** `OcuTalon.Web.Public` and `OcuTalon.Data.Public` load from `OCUTALON_PUBLIC` and run with no roles before sign-in. They may reference only these: `%CSP`, dynamic objects, `$SYSTEM.License`, `$SYSTEM.Status`, `$SYSTEM.Encryption` (compile-time generator only) and each other. A CI check enforces this, and it reads `##class` calls and dynamic dispatch. The splash reads public values only through `OcuTalon.Data.Public.Settings`.
- **The public package's copies of its texts.** The public package keeps its own copies of the texts it renders, and a test compares them with the `splash.*` catalog keys. So the chat-only line needs both a catalog entry and a matching copy in the splash. Elsewhere, the catalog's one renderer is `OcuTalon.Msg.Catalog.Render(key, slots, channel)`.
- **Splash security.** Styles are inline from the token stylesheet under the hashed `style-src`, with no `style=` attributes. The one inline script is pinned by its hash in `script-src`. A change that touches either must keep the CSP pins in step.
- **Where tests go:**
  - The fixed-string test checks every splash text.
  - Flag-on checks go in the online-demo live unit and in `web/e2e-online/`, not in `web/e2e/demo-path/`.
  - The REL-2 online-demo run signs in from the splash and must keep passing.
- **Release names.** Where planning says 0.1.0 or 0.1.1, read 1.0.0. 1.0.0 is the first release and Telegram ships in it.

## UX & Interaction Patterns

- **Card order.** The "Before you start" card keeps its order: the reset schedule, the isolation line, the allowance line (chat-only form), then the no-shell-commands and audit line. Nothing else on the splash changes.
- **The UX spec.** EXPERIENCE.md's splash list now marks the Telegram line as shown only once the release includes Telegram (Story 12.7), and gives the chat-only allowance form until then (U-196).

## Cross-Story Dependencies

- **Builds on:**
  - Story 16.2's splash, its copies of the catalog texts and its tests.
  - Story 16.1's public settings, for the `{limit}` value.
- **Downstream (Story 12.7, Epic 12):**
  - Story 12.7 turns `Included()` on.
  - It now owns the "Telegram included" splash case: it restores both `splash.telegramLine` and the "or Telegram" form of `splash.limitLine`, and decides how the switch reaches the public package.
  - DW-501, the page's allowance banner wording, is also routed to Story 12.7.
  - Epic 12 must not merge before this story.
- **Runner and order:** the re-open runs on runner B, after Story 5.12.
- **Not in this story's scope:** DW-378, the About dialog's tagline, belongs to the merged Story 16.4 and is settled at this epic's burndown.
