# Story 34.4 (DW-825): why D5 misses the file chooser — evidence (lead, Task 0, 2026-11-07)

## The CI failure state
`ci-42326336355-D5-error-context.md` (artifact `playwright-results-browser-1` of run 42326336355, OCT-epic7 2a96bcb4; runs 42324833841 and
42285847375 carry the same file): `page.waitForEvent('filechooser')` times out after 30 s, then `posted()`'s `waitForResponse` times out. The page
snapshot taken at the failure shows **`button "Add documents" [active]`** (focus still on it), the empty-list text, and **no `photo.png` row**:
the press reached a focused Add documents, no file was ever set, no POST was made.

## The product control is not the cause
`web/src/app/documents/documents-page.ts:46-47`: `<button type="button" … (click)="picker.click()">` and `<input #picker type="file" multiple hidden …>`.
No disabled state, no busy flag, nothing async between the click and `input.click()`. No app key handler swallows Enter (grep of `keydown`
in `web/src/app`: only Escape handlers, the composer's own, the device tabs, the tooltip's Escape, and the session gate's idle `touch`).

## The mechanism: interception is turned on fire-and-forget
Playwright 1.64.1 (`web/node_modules/playwright-core/lib/coreBundle.js`), client `ChannelOwner`:
`addListener(event) { if (!this.listenerCount(event)) this._updateSubscription(event, true); … }` and
`_updateSubscription(event, enabled) { … this._channel.updateSubscription({ event: protocolEvent, enabled }).catch(() => {}); }` —
**not awaited**. On the server, `updateSubscription` for `fileChooser` runs `page.setFileChooserInterceptedBy` →
`CRPage.updateFileChooserInterception` → `Page.setInterceptFileChooserDialog { enabled: true }` on each frame session, asynchronously.
D5 registers `page.waitForEvent('filechooser')` and presses Enter in the same tick, so the key event can reach Chromium before the
interception is on; the chooser the click requests is then not intercepted (headless shows no dialog) and the event never fires.

## Reproduction, no stack (this host, 16 cores, load average 8-9 from the other lanes' stacks)
`filechooser-race-repro.mjs`: a page with the same button → hidden `input.click()` pattern; per iteration a fresh context, focus `main`,
Tab, `waitForEvent('filechooser')`, `keyboard.press('Enter')` — D5's exact sequence.
- MODE=old (D5 as written): 2/40, 1/80, 0/120, 4/150 presses produced no chooser (7 of 390, ~1.8 %).
- Every miss logged `["button-click true","input-click"] active=add`: the button's click ran **with transient user activation**, the
  input's click ran, focus stayed on the button — the CI snapshot's state exactly.
- In each of the 4 misses of the 150 run, the same page, button and Enter pressed again 500 ms later (after a fresh `waitForEvent`)
  **opened the chooser**: the page is fine; what differs is only whether interception was on at the moment of the press.
- MODE=armed (a `page.on('filechooser')` listener registered before the page loads, so interception is on long before the press):
  0/80.
- With `DEBUG=pw:protocol` the race does not appear (0/120): the logging slows the client side — consistent with an ordering race.

## Conclusion
Test-only: D5 turns Playwright's file-chooser interception on in the same tick as the Enter press. The fix arms the interception before
the page is opened (a listener registered at the start of the case), keeping every pin: Tab reaches Add documents, Enter opens the
chooser (the `filechooser` event after the press is still awaited and still required), the .png is refused by the real route with its
reason, shown on its row and announced once. No timeout changes.
