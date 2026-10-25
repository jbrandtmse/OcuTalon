import { expect, test } from '@playwright/test';

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
