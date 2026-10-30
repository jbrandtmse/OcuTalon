import { expect, test } from '@playwright/test';

import { notBuilt } from '../e2e/demo-path/not-built';
import { fixtureUser } from '../e2e/support/iris';
import { signOutGroup } from './support';

/**
 * REL-2's online run (Story 16.2): the UJ-1 path as a judge walks it on the online demo. It starts from the test start values of the
 * online-demo throwaway: a fresh browser context opens the splash and finds the published demo credentials prefilled. Step 1 is real:
 * the button signs in without typing and the page loads. Steps 2 to 6 are the web run's (web/e2e/demo-path/02-watch.spec.ts to
 * 06-trace.spec.ts) and wait for Story 11.1, which turns them on here. The online-demo unit runs this file with the project's other
 * specs.
 */
test('step 1: the splash holds the published credentials, and Sign in and start opens the page', async ({ page }) => {
  try {
    const { user, password } = fixtureUser('DEMOACCOUNT');
    await page.goto(`/ocutalon/?probe=${Date.now()}`);
    await expect(page).toHaveTitle('Try OcuTalon');
    await expect(page.getByLabel('User name', { exact: true }), 'the user name is the published demo user').toHaveValue(user);
    await expect(page.getByLabel('Password', { exact: true }), 'the password is the published demo password').toHaveValue(password);
    await page.getByRole('button', { name: 'Sign in and start', exact: true }).click();
    await expect(page).toHaveTitle('OcuTalon');
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  } finally {
    await signOutGroup(page);
  }
});

notBuilt("step 2: the watch prompt and the background check, as the web run's 02-watch.spec.ts", '11.1');
notBuilt("step 3: the reminder prompt, as the web run's 03-reminder.spec.ts", '11.1');
notBuilt("step 4: Break the feed and the incident card, as the web run's 04-incident.spec.ts", '11.1');
notBuilt("step 5: Approve and the result, as the web run's 05-approval.spec.ts", '11.1');
notBuilt("step 6: the trace link to Visual Trace, as the web run's 06-trace.spec.ts", '11.1');
