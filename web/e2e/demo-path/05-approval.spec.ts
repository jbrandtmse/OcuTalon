import { expect, test } from '@playwright/test';

import { STATE, sessionEvents } from '../support/api';
import { ON_MOCK, approveOnPhone, expectDecision, incidentCard } from '../support/demo-path';
import { CARD_MS, signInReadmeLoaded } from '../support/floor';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/**
 * UJ-1 step 5: the approval (REL-2, Story 11.1; FR-8, FR-25, UX-DR103, UX-DR104). On the incident that step 4 left awaiting approval,
 * with a fresh sign-in (so that the card's footer finds its diagnosis decision from the snapshot, DW-294: a strip that passes
 * expectDecision, with the chip Act on the CI mock), the README account presses Approve on the simulated phone and the real fix runs
 * (support/demo-path.ts approveOnPhone). The phone then reads "Approved from the simulated phone at HH:MM.", the chat's card "Approved
 * from the simulated phone at {clock}", and the card shows the band "All 50 orders went through.", "Recorded in the IRIS audit log." and
 * the chip Resolved. The phone gets the result as a message with no buttons, and the request's row leaves the rail. /state's incident ends
 * with the request done, with the result {total 50, completed 50, failedAgain 0} (on the real model: completed equals total and
 * failedAgain is 0, because the model chooses the fix). The band's count is matched by shape on the real model. The fix is
 * quicker than a poll of the page, so the chip Fixing with "Repairing and resending 50 orders\u2026" is never drawn here (the cards
 * unit pins its texts); the incident events of the session stream show the real chain going through Fixing, with the request approved or
 * executing, to Resolved. HH:MM is the row's AnsweredAt. Telegram's half of this step is 12.7's.
 */
test.describe('Story 11.1: step 4 of the guide approves the fix on the simulated phone', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.1 needs the first-start stack (OCUTALON_URL), which a run without one lacks');

  test('Approve on the simulated phone runs the real fix: Fixing, "All 50 orders went through.", the audit line and Resolved', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);

    const card = incidentCard(page);
    await expect(card, 'the incident card shows after the sign-in').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.chip-row .chip'), 'it awaits approval').toHaveText('Awaiting approval');
    const footer = card.locator('.footer app-decision-strip');
    await expectDecision(footer, "the incident's diagnosis decision, found by the footer after the load (DW-294)");
    if (ON_MOCK) await expect(footer.locator('app-outcome-chip .chip'), 'its chip is Act').toHaveText('Act');

    const request = card.locator('[data-part="approval"]');
    const key = (await request.getAttribute('data-key')) ?? '';
    expect(key, "the request's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);

    const snapshot = await page.request.get(STATE);
    expect(snapshot.status(), await snapshot.text()).toBe(200);
    const cursor = ((await snapshot.json()) as { streams: { session: number } }).streams.session;

    await approveOnPhone(page, key);

    // The fix is quicker than a poll, so the page draws its Fixing step and its Resolved end in one update: the stream is where the step is read.
    const events = await sessionEvents(page.request, cursor, (seen) => seen.some((event) => event.type === 'incident' && event.payload['state'] === 'resolved'), 60);
    const states = events.filter((event) => event.type === 'incident').map((event) => String(event.payload['state']));
    expect(states, 'the incident went through Fixing to Resolved').toEqual(expect.arrayContaining(['fixing', 'resolved']));
    expect(states.indexOf('fixing'), 'in that order').toBeLessThan(states.lastIndexOf('resolved'));
    const fixing = events.find((event) => event.type === 'incident' && event.payload['state'] === 'fixing');
    expect((fixing?.payload['requests'] as Array<{ state: string }>).map((one) => one.state).join(), 'while the approved request was being run').toMatch(/^(approved|executing)$/);

    const state = await page.request.get(STATE);
    expect(state.status(), await state.text()).toBe(200);
    const chat = ((await state.json()) as { chat: Array<{ type: string; payload: { requests?: Array<{ ref: string; state: string; result?: Record<string, unknown> }> } }> }).chat;
    const incident = chat.find((item) => item.type === 'incident');
    const requests = incident?.payload.requests ?? [];
    expect(requests.map((one) => `${one.ref}:${one.state}`), "/state's incident holds the request, done").toEqual([`${key}:done`]);
    const result = requests[0]?.result ?? {};
    if (ON_MOCK) expect(result, 'with the fix result').toMatchObject({ total: 50, completed: 50, failedAgain: 0 });
    else expect([result['completed'], result['failedAgain']], 'with the fix result: all of them completed').toEqual([result['total'], 0]);
  });
});
