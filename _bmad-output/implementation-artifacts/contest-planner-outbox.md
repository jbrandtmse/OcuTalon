# Messages for the Contest Planner (undelivered)

Rule 22.6: the Contest Planner relays owner-only and VETO WINDOW items. When its session is unreachable, the lead writes the message here and resends it when the session is back. Each entry is marked `sent` once delivered.

## 2026-10-19 19:15 UTC: correction to the Story 0.6 VETO WINDOW item 2 (production recover)

Status: pending (the Contest Planner session was not reachable at 19:15 UTC)

I said queued messages "stay Suspended, never discarded". That is inaccurate. Code review measured IRIS's recover on build 154:

- in-progress messages go back on their queues;
- asynchronous queues are kept for the next start;
- queued synchronous messages are marked Suspended;
- private-queue messages (in-flight synchronous replies) are discarded.

The step still never runs clean and never kills application data.

- **Ruling:** unchanged. Recover rather than refuse to start.
- **Rejected:** refusing to start, which leaves the judge's install unhealthy after any crash.
- **Reversal:** drop the recover branch.
- **Spine:** AD-23's wording is corrected in Story 0.6's commit.

Also from the 0.6 review:

- AD-3 now says business processes set no `DEFAULTGLOBAL`, because they store in `Ens.BusinessProcess`'s extent, and that they keep no private text in their properties.
- Code review fixed two HIGHs in-pass: lane-shared test counts, and `TelegramIn` missing `STUB`.
