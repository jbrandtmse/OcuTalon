import { test } from '@playwright/test';

import { ON_MOCK, reminderThroughGuide } from '../support/demo-path';
import { pointKeys } from '../support/devices';
import { signInReadmeLoaded } from '../support/floor';

/**
 * UJ-1 step 3 (REL-2, Stories 8.6 and 11.7): the reminder. On the first-start stack, the README account presses Send on guide step 2,
 * which 02 left as the current step (or, from a page that has not moved on, upcoming: DW-340). The page then shows the exact prompt as the
 * guide's own message, the reply with its decision strip, one Reminders row with its countdown, and the guide's step 2 done
 * (support/demo-path.ts reminderThroughGuide). On the CI mock the strip is the chip Act with the reason of the mock's guide-reminder-triage
 * scenario, the reply is "The CI mock set the reminder." and the row is "stretch". On the CI mock the runners' keys are pointed at the mock
 * (idempotently: 02 already did) and stay pointed through the steps that follow, where 06 puts them back; on the real model
 * (OCUTALON_DEMO_PATH_MODEL=real) the specs leave the keys alone. Nothing cancels the reminder: it fires during step 4's wait, and the chat
 * and the phone show it there.
 * The guide turn and everything else it made stay in the README session, for example its triage decision and its turn decision with its
 * agent steps; the steps that follow must not depend on their absence.
 * It needs the first-start stack (OCUTALON_URL): without it the group skips as it is declared,
 * before any hook or fixture starts, because a run with no stack may have no browser either (the unit tests' demo-path run in the hosted
 * web job), and a skip inside the test would launch one first.
 */
test.describe('Story 8.6: step 2 of the guide sets a reminder through the chat', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 8.6 needs the first-start stack (OCUTALON_URL), which a run without one lacks');

  test.beforeAll(async () => {
    test.setTimeout(240_000);
    if (ON_MOCK) await pointKeys();
  });

  test('the guide prompt gets its reply, the reminder shows with its countdown, and step 2 is done', async ({ page }) => {
    test.setTimeout(120_000);
    await signInReadmeLoaded(page);
    await reminderThroughGuide(page);
  });
});
