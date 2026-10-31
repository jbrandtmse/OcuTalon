import { expect, test } from '@playwright/test';

import { STATE, post, sessionEvents } from '../support/api';
import { BREAK_FEED, ON_MOCK, breakFeedButton, breakFeedLeft, expectIncidentAwaitingApproval, phoneNotes, readmeSession, refusal } from '../support/demo-path';
import { CARD_MS, signInReadmeLoaded } from '../support/floor';
import { chk, irisScript } from '../support/iris';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const IN_PROGRESS = 'Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.';

/**
 * UJ-1 step 4: the incident and its approval request. The first test is Break the feed over real HTTP (Story 4.3, REL-2), with the README
 * account, on the watch that step 2 set up. The page's own button is pressed. In order: the press is sent (200 {state, startedAt});
 * /events holds breakfeed.progress sending and sent with that startedAt and then a guide.state, the stage waiting; a second press is
 * refused (409 incident_in_progress); and the Orders production holds 50 failed orders for the session's TraceRef, none at the warehouse,
 * and one run. Every assertion about the stream is relative to the cursor taken at the start. NFR-7's 60 s is measured in the
 * rehearsal, not here. The refusal of a press before the watch is step 2's.
 */
test("Break the feed sends the session's 50 orders, which fail for real in the Orders production", { tag: '@floor' }, async ({ page }) => {
  test.setTimeout(150_000);
  await signInReadmeLoaded(page);
  const snapshot = await page.request.get(STATE);
  expect(snapshot.status(), await snapshot.text()).toBe(200);
  const cursor = ((await snapshot.json()) as { streams: { session: number } }).streams.session;
  const session = await readmeSession();

  await expect(breakFeedButton(page), 'Break the feed is active: step 2 set up the watch').not.toHaveAttribute('aria-disabled', 'true', { timeout: CARD_MS });
  const sentAnswer = page.waitForResponse((response) => response.request().method() === 'POST' && new URL(response.url()).pathname === BREAK_FEED);
  await breakFeedButton(page).click();
  const sent = await sentAnswer;
  expect(sent.status(), await sent.text()).toBe(200);
  const answer = (await sent.json()) as { state: string; startedAt: string };
  expect(Object.keys(answer).sort(), 'the answer is {state, startedAt}').toEqual(['startedAt', 'state']);
  expect(answer.state).toBe('sent');
  expect(answer.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);

  const events = await sessionEvents(page.request, cursor, (seen) => seen.some((event) => event.type === 'breakfeed.progress' && event.payload['state'] === 'sent') && seen.some((event) => event.type === 'guide.state' && (event.payload['breakFeed'] as { stage?: string }).stage === 'waiting'));
  const progress = events.filter((event) => event.type === 'breakfeed.progress');
  expect(
    progress.map((event) => event.payload['state']),
    'breakfeed.progress: sending, then sent',
  ).toEqual(['sending', 'sent']);
  expect(
    progress.map((event) => event.payload['startedAt']),
    'both carry the run start',
  ).toEqual([answer.startedAt, answer.startedAt]);
  const guides = events.filter((event) => event.type === 'guide.state' && event.seq > progress[1].seq);
  expect(guides.length, 'a guide.state follows the sent event').toBeGreaterThan(0);
  expect((guides[guides.length - 1].payload['breakFeed'] as { stage: string }).stage, 'its stage is waiting').toBe('waiting');

  const second = await refusal(await post(page.request, BREAK_FEED, {}));
  expect(second, 'a second press is refused: the first has no notice yet').toEqual({ status: 409, code: 'incident_in_progress', message: IN_PROGRESS });

  const counts = async (): Promise<number> => Number((await breakFeedLeft(session)).failed);
  await expect.poll(counts, { message: "OCUORDERS holds the session's 50 failed orders", timeout: 60000, intervals: [1000, 2000, 3000] }).toBe(50);
  expect(await warehouseCount(session.trace), 'none of them reaches the warehouse').toBe('0');

  // The refused second press sent nothing: after a pause, still one run and one batch (50 orders, not 100).
  await new Promise((done) => setTimeout(done, 3000));
  expect(await breakFeedLeft(session), 'one run (sent) and one batch of 50 orders after the second press').toEqual({ runs: '1:sent', headers: '50', failed: '50' });
});

/** The number of the session's messages at the warehouse. */
async function warehouseCount(trace: string): Promise<string> {
  const lines = await irisScript(`Write !,"CHK|warehouse|",##class(OcuTalon.Test.Demo.Production).Count("${trace}","OrdersToWarehouse",9)`);
  return chk(lines, 'warehouse') ?? '';
}

test.describe('Story 11.1: step 3 of the guide breaks the feed and the incident awaits approval', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.1 needs the first-start stack (OCUTALON_URL), which a run without one lacks');

  /**
   * The incident card and the phone's notice from the real chain (Story 6.3, REL-2; FR-16, FR-24, FR-34): the failures that Break the feed
   * made become one incident, whose card awaits approval in the chat and on the simulated phone (support/demo-path.ts
   * expectIncidentAwaitingApproval: within 90 s of the press the chat shows the card with its chip, headline, cause, evidence line, dry
   * run and its two buttons, the phone the incident notice with the same two buttons, the rail "Approval requests (1)" with one row, and
   * the guide step 4 current; the diagnosis's own words are exact on the CI mock and matched by shape on the real model). The step-3
   * reminder lands by the end of this step: the chat shows "Reminder: stretch." and the phone a stretch message (on the real model,
   * "Reminder: " followed by the model's text in the chat, and a phone message without buttons).
   */
  test('the incident card, the request, the phone notice and the rail show the real incident, and the reminder lands', async ({ page }) => {
    test.setTimeout(180_000);
    await signInReadmeLoaded(page);
    await expectIncidentAwaitingApproval(page);

    const landed = page.locator('main app-notice-card').filter({ hasText: ON_MOCK ? 'Reminder: stretch.' : /Reminder: \S/ });
    await expect(landed, 'the reminder of step 3 landed in the chat').toHaveCount(1, { timeout: 90_000 });
    const onPhone = ON_MOCK ? phoneNotes(page).filter({ hasText: 'stretch' }) : phoneNotes(page).filter({ hasNot: page.getByRole('button') });
    await expect(onPhone, 'and on the phone').toHaveCount(1, { timeout: CARD_MS });
    if (!ON_MOCK) await expect(onPhone, 'as a message with text').toHaveText(/\S/);
  });
});
