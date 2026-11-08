# Epic 17 Context: A daily digest you can trust, and model choice with budgets (step 2)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Once a day at the set time, and whenever the user asks, OcuTalon sends one short digest. It holds the vital signs, a coverage list where every entry is passed, failed or not checked, what needs the user, what was saved for later, and yesterday's model cost. Only code decides whether an all-clear is given. The epic also lets an admin choose each agent's provider and model, set prices, budgets and the time zone through the bridge, and name a second model for one retry. Stories 17.2 to 17.10 are done: the digest now shows as a plain-text card in the web chat, and the scheduled run skips online-demo sessions. Story 17.11 is left, a burn-down story under the SC-5 re-open. The online demo shows a visitor the demo instance's own vital signs. This is allowed only if the digest never names a host path, an IP address, a user name or a key, and the story pins that with a test. It is test-only unless the pin finds a real leak.

## Stories

- Story 17.2: Retry once on a second model before falling back (done)
- Story 17.3: Run each agent on a supported provider (done)
- Story 17.4: Apply model, price, budget and zone changes through the bridge (done)
- Story 17.5: Check the vital signs and every coverage entry (done)
- Story 17.6: Send the daily digest at the set time and on request (done)
- Story 17.7: Give an all-clear only when every check passed (done)
- Story 17.8: Only Decide moves a conversation's link (done)
- Story 17.9: Epic 17 burn-down (done)
- Story 17.10: The digest shows in the web chat, and the online demo's digest is visible (done)
- Story 17.11: Epic 17 burn-down: the online-demo digest names no host path, address, user or key

## Requirements & Constraints

- **The leak pin (DW-898, the U-303 keep-condition).**
  - Setup: the online demo (`Data.Public.Settings` "onlineDemo" on).
  - Plant five values in the instance facts the digest reads (the vital signs and the coverage rows): a host path, an IP address, a user name, an `sk-ant-` key and a Telegram bot token.
  - Compose a visitor's digest and render it for the web chat. None of the planted values may appear in the text.
  - Show a mutation turning the pin red: the composer lets a planted value through.
- **No product string changes.** If the pin finds a real leak, fix it in this story (a HIGH).
- **Where host facts can enter the digest.** The vital signs are:
  - whether the instance responds;
  - free space for OcuTalon's databases and for each watched namespace's databases;
  - journal space;
  - license use;
  - errors in the instance's own system log since the last digest.
  - Each watched production adds an entry (running state, items in error or disabled, failed messages, queue backlog). On the online demo only the Orders production can be watched.
- **Keys never reach IRIS text.**
  - Model keys and bot tokens come only from environment variables. They are never stored in IRIS and never shown.
  - The online demo's IRIS holds only a dummy model key and a dummy bot token. The outbound gateway swaps in the real ones.
- **Digest rules from earlier stories still hold:**
  - The all-clear and its reserved sentences come only from `Checks.Render`. "Your IRIS system is healthy" appears only when every vital-sign row passed.
  - The cost shows two decimals (slot type `dailyCost`).
  - The greeting depends on the hour in the instance zone.
  - The digest has no Markdown and keeps one piece per line.
  - The model summary runs only when something was saved for later.
- **Online demo.** No session is due for the scheduled digest there. A visitor gets a digest only by asking (`SendDigest`), and it shows in that visitor's own web chat. REL-2 stays green.
- **Public-text guard (DW-755).** No README, guide, settings page or release text may say that a provider other than Anthropic runs decisions.
- **Flakes.** A flake gets one rerun and an occurrence line in the ledger.

## Technical Decisions

- **Coverage builder.** `OcuTalon.Checks.Coverage.Build(sessionRef, fromUtc, toUtc, *rows, *lines[, *vitals])` is the one builder of the digest's rows.
  - It reads the vital signs at that moment through `Watch.Reader`, with the `checks.thresholds.*` values.
  - `rows` have the shape `{result, entry, finding, checkedAt}`. A not-checked row's finding is a short phrase written in code from `Checks` class parameters.
  - `lines` hold one `{key, slots}` per row, in the rows' order.
  - The optional `vitals` holds the five vital-sign rows plus `upDays`, `databasesFull` and `licenseUse`.
- **Digest eval case.** A digest eval case composes with recorded rows in place of `Coverage.Build`. It writes no `Notification`, `Delivery` or live event.
- **The digest notification.** A digest is one `OcuTalon.Msg.Notification` of kind `digest`.
  - Its `Slots` are `{"parts": [{key, slots}...], "lines": [...], "rows": [...]}`.
  - Producers never render text. Only the `*Out` operations render, through `Msg.Catalog.Render(key, slots, channel)`.
- **One renderer.** `OcuTalon.Channel.DigestText.Text(slots, channel, .sc)` is the shared renderer. Both `TelegramOut` and `WebChatOut` call it, so the text the pin checks is `Text(slots, "web")`.
  - `WebChatOut` stores the whole text on a `Delivery` row of kind `digest` and publishes one `notification` event.
  - Telegram's output stays byte-identical, pinned by the golden test `TelegramText`.
- **Redaction.** `OcuTalon.Bridge.Redact` is the one redactor, used for agent steps, audit, logs and error details. Structural rules come first and the redactor is the backstop. Watch error text is redacted before it enters OcuTalon's messages. No names, user names or phone numbers are stored in production messages.
- **Ownership.** `Digest`, `Checks`, `Watch` and `TelegramOut` are Lane A's. `WebChatOut`, `Data.Delivery`, `Data.Ownership` and the web chat are Lane B's.
- **Testing.** Tests use the CI model mock (`ci/mock/`, scenarios under `ci/mock/scenarios/`). The digest summary's model request goes through `Decide`. If the summary is unusable, the digest still goes out with the count and no summary.

## UX & Interaction Patterns

- In the web chat the digest is a notice card with no title. It shows the catalog text exactly, keeps its line breaks, and has its own class and icon. The full UX card (the teal bar, grouped check rows and "What I checked ({n})") waits for Story 18.4.
- In chat, "send my digest now" is a safe tool action that submits `SendDigest` (origin `tool`). The tool result says the digest is being sent, never that it was sent.

## Cross-Story Dependencies

- Story 17.11 builds on:
  - Story 17.5's `Coverage.Build` and the vital signs;
  - Stories 17.6 and 17.7's `Digest.Process` and `Checks.Render`;
  - Story 17.10's `Channel.DigestText` helper, the web digest card and the online-demo skip of the scheduled run;
  - Epic 16's online-demo settings.
- Lane B's Epic 18 is in backlog:
  - Story 18.2 owns Notify's `digest.channels` route.
  - Story 18.4 owns the full digest card, the phone copy and **Got it** on the web.
