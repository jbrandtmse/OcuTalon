# Epic 25 Context: Usage, history and files in the page (step 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 25 is Lane B's half of step 6. It added the History page, sending a file from the web app or Telegram, approver and viewer roles in Settings with enforcement, and OcuTalon's reply to a sent file, which turned file reading on. All of that is merged. The epic's retrospective found five small web gaps where these stories meet, and Story 25.8 closes them together. The Usage page must withdraw its failed-read announcement once a later read answers, as History already does. The Announcer's retract guard and History's double-Retry test need behavioural pins. A viewer must not be offered file controls that the server would refuse: the **Add to documents** button on an older file reply, and the drop target on the Documents page. The work is web and test only. It closes ledger items DW-1120, DW-1121, DW-1122, DW-1386 and DW-1387.

## Stories

- Story 25.2: Filter past decisions and incidents on the History page (done)
- Story 25.3: Send a PDF, Word file or photo from the web app or Telegram (done)
- Story 25.4: Assign approver and viewer roles in Settings (done)
- Story 25.5: Answer only with the right approver role, and say why otherwise (done)
- Story 25.6: Reply to a sent file: Add to documents, Saved to memory and the read failure (done)
- Story 25.7: Epic 25 burn-down: a cancelled CI job's stack no longer blocks its runner's web port (done)
- Story 25.8: Epic 25 burn-down: the web gap-fill (Usage withdraws its stale error, and a viewer gets no file-reply add or Documents drop) (ready-for-dev)

## Requirements & Constraints

- **Hard scope limits.** No new user-visible string. No change to any route, IRIS class or role, and no widening of the user role. The ownership tables don't change. Nothing may depend on Story 26.4's new approver roles.
- **Bundle cap.** The initial web bundle stays at or under 921 kB (921,000 bytes, checked by `initial-bundle.test.mjs`). The `web/angular.json` budget stays at `maximumError` 1MB and is never raised. New web code goes into lazy chunks where it can. Settings, History and Usage are already lazy chunks.
- **Mutation-proof tests.** Each new or changed test must fail when the behaviour it pins is removed, and the story records that failure (a demonstrated mutation, one per acceptance criterion). Pins must be behavioural, not source-regex checks. Every test creates and removes its own state and passes in either order.
- **Stale error.** After Usage announces its failed read (`USAGE_TEXTS.error`), a later successful read withdraws that announcement through `Announcer.retract`. The browser test runs on a frozen page clock and covers the queued case: a second failure waiting in the queue must not be spoken after the answer.
- **Retract guard.** `Announcer.retract` leaves the live region alone when a different text was spoken last. Test it by speaking one text and retracting another; the region must keep the spoken text.
- **History H15.** H15 presses Retry a second time. Before it asserts, it waits on a page-side signal that the refused second read was handled, so the queued case is really exercised. Any such signal is a test anchor (an attribute), never rendered text.
- **Viewer and file reply.** On a viewer's page, an older file reply whose read is `addable` shows no **Add to documents** button. The Saved to memory chip stays. `chat/file-reply.ts` joins the `GUARDED` list in `web/scripts/viewer-sources.test.mjs`. The server already refuses a viewer's add with 403 `read_only`; today the page shows the generic add-failed line and keeps the button.
- **Viewer and Documents drop.** On the Documents page, a viewer gets no drag outline and no drop. The shared `FileDrop` gets `[active]` false for a viewer. Today `active` defaults to true, and only `addFiles` returns early. A test pins this, and a non-viewer user's drop works as before.
- **No substitutes.** A hidden button or inactive drop gets no message or replacement control. A viewer's drop is left to the browser's own handling, as the chat already does.

## Technical Decisions

- **One announcer.** The page speaks only through `Announcer`, a single polite live region. One update's messages are announced as one text, at least 1 s apart, at most three in 2 s, and two or more waiting become "{n} new updates". Each event is announced from one place, and the first snapshot is silent. This speaking path does not change. `retract` withdraws a text only if it was the last one spoken, on its own and not joined with others, so it never empties another page's announcement.
- **Viewer model.** A viewer holds `OcuTalonViewer` and not `OcuTalonUser`. `/v1/state` carries `viewer`, and `admin` is false for a viewer. The server refuses every non-`GET` request from a viewer with 403 `read_only` before reading the body (except `POST /v1/session/end`). The page hides every control that would only fail: the composer, Approve, Reject, Dismiss, Break the feed, the chat paperclip and the chat drop. The page tests for a viewer with the existing snapshot helper (`isViewer`), never a new role check. `GUARDED` is the hand-kept list of web sources that must check `viewer`.
- **Lane exception.** Lane A runs Story 25.8 under an AD-33 exception and may change only the Lane B web files that exception names. Source: `shared/announce-queue.ts`, `shared/announcer.ts`, `usage/usage-page.ts`, `history/history-page.ts`, `chat/file-reply.ts`, `chat/file-reply-view.ts` and `documents/documents-page.ts`. Unit tests: `announce-queue.test.mjs`, `announce-focus-sources.test.mjs`, `viewer-sources.test.mjs` and `file-reply-view.test.mjs`. Browser specs: `usage/usage.spec.ts`, `history/history.spec.ts`, `sign-in/viewer.spec.ts`, `files/files.spec.ts`, `support/clock.ts` and a new `support/files.ts`. File ownership stays as it is, and the final diff must show only these files.
- **Runtime.** Tests run on real runtimes (Lane A throwaway stacks), with no shared slot or MCP target.

## UX & Interaction Patterns

- A viewer can open OcuTalon but can't chat, answer or change anything.
- A failed read's announcement must not be spoken after a successful Retry.
- Drag-and-drop is never the only way to add a file. When dropping isn't allowed, the target shows no drag affordance.

## Cross-Story Dependencies

- Story 25.8 builds on merged work:
  - 25.2 rework 2: History's `Announcer.retract` use and test H15.
  - 25.3: the shared `FileDrop`, which the Documents page and the chat drop use.
  - 25.4: the viewer snapshot and the `GUARDED` list. Story 26.4 keeps the viewer model.
  - 25.6: `chat/file-reply.ts` and its `addable` read result.
  - Story 2.12: the Announcer and its queue.
- **Shared controls.** The story changes the Announcer and the drop control. Before pushing, grep `web/e2e` for every spec that pins them and run those parts with `node web/scripts/e2e-part.mjs`. The new tests shift the browser part cut, so recompute the parts first. Three of the epic's four reworks were failures of this kind.
