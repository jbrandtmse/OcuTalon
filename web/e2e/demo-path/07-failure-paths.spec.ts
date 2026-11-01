import { expect, test } from '@playwright/test';

import {
  ON_MOCK,
  approvalRows,
  breakFeedButton,
  breakFeedForRefusal,
  dismissIncident,
  expectFallbackIncident,
  expectIncidentAwaitingApproval,
  guideRegion,
  incidentCardOf,
  incidentRefs,
  incidentRow,
  newIncidentRef,
  openTraceFromGuide,
  pressBreakFeed,
  readmeSession,
  rejectOnPhone,
} from '../support/demo-path';
import { CARD_MS, signInReadmeLoaded } from '../support/floor';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** The key of the request that the rejection test rejected: the replay's request is another one. */
let rejectedKey = '';

/**
 * UJ-1's failure paths (REL-2, Story 11.10; FR-4, FR-8, FR-16, FR-24, UX-DR45, UX-DR104), run after the main route (02 to 06) on the same
 * stack, which 06 left with the incident resolved and the guide finished. Every press is the page's own Break the feed and every answer
 * is pressed on the simulated phone; Dismiss is pressed on the card, with no reload between a rejection and its Dismiss.
 *  1. Run again: the finish leaves, the guide reads "Step 3, Break the feed, current" and Break the feed is active.
 *  2. The refusal (the CI mock only; the real model cannot be made to refuse, so on `real` the test is not declared): the test seam
 *     pauses FailurePoller, presses Break the feed, marks the new run's 50 failed orders with `[[mock:refusal]]` and lets FailurePoller
 *     read again (support/demo-path.ts breakFeedForRefusal). The incident is a fallback: its card, /state row and the guide are checked
 *     (expectFallbackIncident), step 5 still opens the trace, and Dismiss closes the incident and frees Break the feed.
 *  3. The rejection: a new incident awaits approval; Reject on the phone returns it to Open, with the texts of the phone and the card,
 *     the rail and the guide; then Dismiss.
 *  4. The replay: a new incident with its own request, which awaits approval and is left pending for 08.
 * On `real` (OCUTALON_DEMO_PATH_MODEL=real) the model-written texts are matched by their shape and the keys are never touched.
 * It needs the first-start stack (OCUTALON_URL): without it the group skips as it is declared, before any hook starts.
 */
test.describe('Story 11.10: the failure paths of the guide', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.10 needs the first-start stack (OCUTALON_URL), which a run without one lacks');
  test.describe.configure({ mode: 'serial' });

  test('Run again leaves the finish and brings the guide back to Break the feed', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    const guide = guideRegion(page);
    await expect(guide.locator('.finish'), 'the guide shows its finish').toBeVisible({ timeout: CARD_MS });
    await guide.getByRole('button', { name: 'Run again', exact: true }).click();
    await expect(guide.locator('.finish'), 'the finish leaves').toHaveCount(0, { timeout: CARD_MS });
    await expect(guide.getByRole('button', { name: 'Step 3, Break the feed, current', exact: true }), 'the guide reads step 3, current').toHaveCount(1, { timeout: CARD_MS });
    await expect(breakFeedButton(page), 'Break the feed is active').not.toHaveAttribute('aria-disabled', 'true', { timeout: CARD_MS });
  });

  if (ON_MOCK) {
    test('a mocked refusal of the diagnosis gives the fallback card, step 5 opens its trace, and Dismiss frees Break the feed', async ({ page, context }) => {
      test.setTimeout(240_000);
      await signInReadmeLoaded(page);
      const session = await readmeSession();
      const known = await incidentRefs(page);
      await breakFeedForRefusal(page, session);

      const ref = await newIncidentRef(page, known);
      const card = incidentCardOf(page, ref);
      await expectFallbackIncident(page, card);
      const row = await incidentRow(page, ref);
      expect([row.state, row.openVariant, row.fallbackReason], "/state holds the incident open, as a fallback for the model's refusal").toEqual(['open', 'fallback', 'refusal']);
      expect(row.requests, 'with no request').toEqual([]);
      expect(row.diagnosisHeader, 'and the diagnosis trace header').toBeGreaterThan(0);

      await openTraceFromGuide(page, context, row.diagnosisHeader, 'upcoming');
      // The trace sign-out ends the page's own sign-in group too: the incident is dismissed from a fresh sign-in.
      await signInReadmeLoaded(page);
      await dismissIncident(page, card, ref);
    });
  }

  test('Reject on the simulated phone returns the incident to Open, and Dismiss frees Break the feed', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    const known = await incidentRefs(page);
    await pressBreakFeed(page);

    const ref = await newIncidentRef(page, known);
    const card = incidentCardOf(page, ref);
    const key = await expectIncidentAwaitingApproval(page, card);
    await rejectOnPhone(page, key, card);
    const row = await incidentRow(page, ref);
    expect([row.state, row.openVariant, row.requests.map((one) => `${one.ref}:${one.state}`)], "/state holds the incident open, with the request rejected").toEqual(['open', 'rejected', [`${key}:rejected`]]);
    await dismissIncident(page, card, ref);
    rejectedKey = key;
  });

  test('a replay opens a new incident with its own request, which awaits approval', async ({ page }) => {
    test.setTimeout(240_000);
    expect(rejectedKey, 'the rejection test ran first').toMatch(/^[A-Za-z0-9_-]{22}$/);
    await signInReadmeLoaded(page);
    const known = await incidentRefs(page);
    await pressBreakFeed(page);

    const ref = await newIncidentRef(page, known);
    const card = incidentCardOf(page, ref);
    const key = await expectIncidentAwaitingApproval(page, card);
    expect(key, 'the replay has its own request').not.toBe(rejectedKey);
    await expect(approvalRows(page), "the rail's one row is the replay's request").toHaveAttribute('data-row-key', `approvals:${key}`);
  });
});
