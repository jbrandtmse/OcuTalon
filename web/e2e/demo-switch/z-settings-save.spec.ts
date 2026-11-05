import { expect, test, type Locator, type Page } from '../support/fixtures';

import { signInReadmeLoaded } from '../support/floor';

/**
 * Story 33.2: the Demo mode section of the settings page switches demo mode through the real SettingsOps path and the real Demo step (the same as
 * Core.Admin.SetDemoMode). It runs only on a stack in demo mode on (OCUTALON_E2E_DEMO_MODE=1), saves demo mode off, then on, and shows the saved text each
 * time; it ends with demo mode on, which is the state test-demo-switch.sh expects after its last page run. The file name makes it run last of the folder,
 * because Setting.Get in a CSP job can hold the old mode for 60 s and the other specs of the folder read it.
 */
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const SETTINGS = '/ocutalon/api/v1/settings';

/** The section's own saved line, not the announcer's copy of it. */
const savedText = (page: Page): Locator => page.locator('p.saved').filter({ hasText: SAVED });

test('the Demo mode section saves demo mode off, then on, and shows the saved text', async ({ page }) => {
  test.skip(process.env['OCUTALON_E2E_DEMO_MODE'] !== '1', 'only on a stack in demo mode on');
  test.setTimeout(120_000);
  await signInReadmeLoaded(page);
  await page.getByRole('navigation', { name: 'Pages', exact: true }).getByRole('link', { name: 'Settings', exact: true }).click();
  await page.getByRole('navigation', { name: 'Settings sections', exact: true }).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const toggle = page.getByRole('switch', { name: /^Demo mode/ });
  await expect(toggle, 'the stack is in demo mode, so the switch is on').toHaveAttribute('aria-checked', 'true');
  const save = page.getByRole('button', { name: 'Save changes', exact: true });
  const demoMode = async (): Promise<boolean> => ((await (await page.request.get(SETTINGS)).json()) as { sections: { 'demo-mode': { demoMode: boolean } } }).sections['demo-mode'].demoMode;

  try {
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', 'false');
    await save.click();
    await expect(savedText(page), 'saving off shows the saved text').toBeVisible({ timeout: 60_000 });
    expect(await demoMode(), 'GET /v1/settings shows demo mode off at once').toBe(false);

    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    await expect(savedText(page), 'switching again clears the saved text').toHaveCount(0);
    await save.click();
    await expect(savedText(page), 'saving on shows the saved text').toBeVisible({ timeout: 60_000 });
    expect(await demoMode(), 'and demo mode is on again').toBe(true);
  } finally {
    if (!(await demoMode())) {
      await toggle.click();
      await save.click();
      await expect(savedText(page)).toBeVisible({ timeout: 60_000 });
    }
  }
});
