import { expect, test, type Locator, type Page } from '@playwright/test';

import {
  ON_MOCK,
  WATCH_PROMPT,
  approveOnPhone,
  breakFeedButton,
  checkRow,
  dismissIncident,
  guideRegion,
  incidentCardOf,
  incidentRefs,
  incidentRow,
  incidentRows,
  newIncidentRef,
  openTraceFromGuide,
  phoneNotes,
  pressBreakFeed,
  expectIncidentAwaitingApproval,
  reminderRows,
  rejectOnPhone,
  sendThroughComposer,
} from '../e2e/support/demo-path';
import { post } from '../e2e/support/api';
import { pointKeys, restoreKeys } from '../e2e/support/devices';
import { CARD_MS, signInReadmeLoaded } from '../e2e/support/floor';
import { chk, irisScript } from '../e2e/support/iris';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the cases set to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const REMINDER_PROMPT = 'Remind me in 1 minute to stretch.';
/** The route of the guide's UI markers (the page posts run_again when Run again is pressed). */
const GUIDE_MARKERS = '/ocutalon/api/v1/guide/markers';

/**
 * One repeat of the demo path for runs 2 to N of the clean-machine rehearsal (release/rehearse.sh, Story 11.12; REL-6, UX-DR101), on the
 * install that run 1 (the REL-2 project) left: the guide at its finish, or at step 4 with 07's replay request pending. Run again reopens
 * only steps 3 to 5, so steps 1 and 2 go through the composer. Every count is relative to a count taken in the run, or scoped to the run's
 * own incident card. Each title starts with its step id and a colon: it names the step in a FAIL line.
 *  again:     clears what the earlier run left, so that Break the feed is allowed (the replay rule needs the previous incident resolved):
 *             07's pending request is rejected on the phone and its incident dismissed (run 2), or Run again is pressed (run 3 and later).
 *             After the dismissal the guide still has run 1's opened trace and reads step 5 with no Run again on screen (the finish is not
 *             shown), so run 2 posts the run_again marker that the Run again press posts; then the guide reads step 3, current
 *  watch:     the guide's watch prompt through the composer (the page marks step1_*); the "Orders production" check row stays one
 *  reminder:  "Remind me in 1 minute to stretch." through the composer; a Reminders row with its countdown shows
 *  incident:  Break the feed; the new incident awaits approval
 *  approval:  Approve on the simulated phone (the page marks approve_pressed and approval_result_seen), read on this incident's card
 *  trace:     step 5 opens the trace of the incident's diagnosis; the finish shows
 *  reminder:  the reminder landed in the chat and on the phone
 * On the CI mock the runners' keys are pointed at the mock before the first test and put back after the last, as 08 does; on `real`
 * (OCUTALON_DEMO_PATH_MODEL=real) they are never touched. It needs the stack (OCUTALON_URL).
 */
test.describe('Story 11.12: one repeat of the demo path', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.12 needs the first-start stack (OCUTALON_URL), which a run without one lacks');
  test.describe.configure({ mode: 'serial' });

  let ref = '';
  let key = '';
  let cardsBefore = 0;
  let phoneBefore = 0;

  const landedCards = (page: Page): Locator =>
    page.locator('main app-notice-card').filter({ hasText: ON_MOCK ? 'Reminder: stretch.' : /Reminder: \S/ });
  const landedPhone = (page: Page): Locator => (ON_MOCK ? phoneNotes(page).filter({ hasText: 'stretch' }) : phoneNotes(page).filter({ hasNot: page.getByRole('button') }));

  test.beforeAll(async () => {
    test.setTimeout(240_000);
    if (ON_MOCK) await pointKeys();
  });

  test('again: what the earlier run left is cleared and Break the feed is active', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    const guide = guideRegion(page);
    const pending = (await incidentRows(page)).find((row) => row.requests.some((request) => request.state === 'pending'));
    if (pending !== undefined) {
      const request = pending.requests.find((one) => one.state === 'pending')!;
      const card = incidentCardOf(page, pending.ref);
      await rejectOnPhone(page, request.ref, card);
      await dismissIncident(page, card, pending.ref);
      const marked = await post(page.request, GUIDE_MARKERS, { marker: 'run_again' });
      expect(marked.status(), await marked.text()).toBe(200);
    } else if ((await guide.locator('.finish').count()) > 0) {
      await guide.getByRole('button', { name: 'Run again', exact: true }).click();
      await expect(guide.locator('.finish'), 'the finish leaves').toHaveCount(0, { timeout: CARD_MS });
    } else {
      const shown = ((await guide.innerText()) ?? '').replace(/\s+/g, ' ').slice(0, 200);
      throw new Error(`the earlier run left neither a pending request nor the guide's finish (the guide reads: ${shown})`);
    }
    await expect(guide.getByRole('button', { name: 'Step 3, Break the feed, current', exact: true }), 'the guide reads step 3, current').toHaveCount(1, { timeout: CARD_MS });
    await expect(breakFeedButton(page), 'Break the feed is active').not.toHaveAttribute('aria-disabled', 'true', { timeout: CARD_MS });
  });

  test('watch: the watch prompt through the composer is decided, and the check row stays one', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    await sendThroughComposer(page, WATCH_PROMPT, true);
    await expect(checkRow(page), 'the "Orders production" check row is still one').toHaveCount(1, { timeout: 30_000 });
  });

  test('reminder: the reminder prompt through the composer sets a reminder with its countdown', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    cardsBefore = await landedCards(page).count();
    phoneBefore = await landedPhone(page).count();
    const rowsBefore = await reminderRows(page).count();
    await sendThroughComposer(page, REMINDER_PROMPT, false);
    const rows = reminderRows(page);
    await expect(rows, 'one more reminder shows under Reminders').toHaveCount(rowsBefore + 1, { timeout: 30_000 });
    await expect(rows.last().locator('.countdown'), 'with its countdown').toHaveText(/^in \d+ (s|min)$/);
  });

  test('incident: Break the feed opens a new incident that awaits approval', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    const known = await incidentRefs(page);
    await pressBreakFeed(page);
    ref = await newIncidentRef(page, known);
    key = await expectIncidentAwaitingApproval(page, incidentCardOf(page, ref));
  });

  test('approval: Approve on the simulated phone resolves this incident', async ({ page }) => {
    test.setTimeout(240_000);
    expect(key, 'the incident test ran first').toMatch(/^[A-Za-z0-9_-]{22}$/);
    await signInReadmeLoaded(page);
    await approveOnPhone(page, key, '', incidentCardOf(page, ref));
  });

  test('trace: step 5 opens the trace of this incident, and the finish shows', async ({ page, context }) => {
    test.setTimeout(240_000);
    expect(ref, 'the incident test ran first').not.toBe('');
    await signInReadmeLoaded(page);
    const row = await incidentRow(page, ref);
    expect(row.diagnosisHeader, "the incident's diagnosis trace header").toBeGreaterThan(0);
    await openTraceFromGuide(page, context, row.diagnosisHeader);
    await expect(guideRegion(page).locator('.finish'), 'the finish shows').toBeVisible({ timeout: CARD_MS });
  });

  test('reminder: the reminder landed in the chat and on the phone', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    await expect(landedCards(page), 'the chat has one more reminder notice card').toHaveCount(cardsBefore + 1, { timeout: 90_000 });
    if (ON_MOCK) {
      await expect(landedPhone(page), 'and the phone one more stretch message').toHaveCount(phoneBefore + 1, { timeout: CARD_MS });
    } else {
      await expect.poll(() => landedPhone(page).count(), { message: 'and the phone a message without buttons', timeout: CARD_MS }).toBeGreaterThan(phoneBefore);
    }
  });

  test.afterAll(async () => {
    test.setTimeout(240_000);
    if (!ON_MOCK) return;
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
    }
  });
});
