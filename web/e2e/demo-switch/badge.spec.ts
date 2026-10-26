import { expect, test } from '@playwright/test';

import { changeSnapshot } from '../support/api';
import { signInReadme } from '../sign-in/helpers';

/**
 * The demo-mode switch, as the page shows it (Story 4.1): the README account signs in and the page loads its snapshot, which
 * reports the demo mode that the stack is in (docker/tests/test-demo-switch.sh, OCUTALON_E2E_DEMO_MODE). With demo mode on the
 * header shows the badge "Demo mode"; with it off there is no badge, and the chat region is shown.
 */
function stackMode(): '0' | '1' {
  const mode = process.env['OCUTALON_E2E_DEMO_MODE'];
  if (mode !== '0' && mode !== '1') {
    throw new Error('OCUTALON_E2E_DEMO_MODE must be 1 (demo mode on) or 0 (demo mode off)');
  }
  return mode;
}

test('the header badge follows the demo mode of the stack', async ({ page }) => {
  const mode = stackMode();

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const badge = page.locator('app-header .context-badge');
  if (mode === '1') {
    await expect(badge, 'demo mode is on: the header says so').toHaveText('Demo mode');
  } else {
    await expect(badge, 'demo mode is off: the header shows no badge').toHaveCount(0);
  }
  await expect(page.getByRole('main').getByRole('textbox', { name: 'Message OcuTalon' }), 'the chat region is shown').toBeVisible();
});

/**
 * The demo guide and its texts follow the demo mode of the stack (Story 4.4, matrix rows 2 and 3, on a real switch): with demo mode on the
 * region "Demo guide" and the Break the feed box show, and the empty chat and Background checks point at the guide; with it off there is
 * no region and no box, and the old texts return. The snapshot's chat and rail checks are emptied, so that the result does not depend on
 * what this stack's README session holds; its demo mode is the real one.
 */
test('the demo guide, the Break the feed box and the demo texts follow the demo mode of the stack', async ({ page }) => {
  const mode = stackMode();
  await changeSnapshot(page, (snapshot) => {
    snapshot['chat'] = [];
    (snapshot['rail'] as { checks: unknown[] }).checks = [];
  });

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const guide = page.getByRole('region', { name: 'Demo guide' });
  const lastLine = page.getByRole('main').locator('app-empty-chat .line').last();
  const emptyChecks = page.getByRole('region', { name: 'Status', exact: true }).locator('.empty').nth(1);
  if (mode === '1') {
    await expect(guide, 'demo mode is on: the region Demo guide shows').toHaveCount(1);
    await expect(guide.getByText('Demo control', { exact: true }), 'with the Break the feed box').toBeVisible();
    await expect(guide.getByRole('button', { name: 'Break the feed', exact: true }), 'and its button').toHaveCount(1);
    await expect(lastLine).toHaveText('Start with step 1 of the demo guide above.');
    await expect(emptyChecks).toHaveText('Nothing yet. Step 1 of the guide sets up a watch.');
  } else {
    await expect(guide, 'demo mode is off: no region Demo guide').toHaveCount(0);
    await expect(page.locator('app-break-feed-box'), 'and no Break the feed box').toHaveCount(0);
    await expect(lastLine).toHaveText('Ask OcuTalon to watch a production, set a reminder, or say what you need.');
    await expect(emptyChecks).toHaveText('Ask OcuTalon to watch a production.');
  }
});
