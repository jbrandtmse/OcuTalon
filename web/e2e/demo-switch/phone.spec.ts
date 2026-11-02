import { expect, test } from '@playwright/test';

import { STATE } from '../support/api';
import { dropPhone, phoneRows } from '../support/devices';
import { sendNotification } from '../support/iris';
import { README_ACCOUNT } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';

/**
 * The simulated phone follows the demo mode of the stack (Story 4.5, matrix row 17, on a real switch). The README account signs in and
 * a tell-now notification and a reminder go through the real Notify, as the producers of notices will send them (NoticesIn host). With
 * demo mode on both texts are on the simulated phone, in the order sent, and still there after a reload, and the session gets two
 * SimMessage rows. With it off both are chat cards only: there is no region, /state has no `phone` key, and no SimMessage row is made.
 * Every assertion is relative to what the README session held before the case. The case removes what it made (dropPhone: the two chat
 * cards and the phone rows), because test-demo-switch.sh holds the README chat equal to the one it recorded at the start (S0) in the
 * /state answers of its steps 5 and 8.
 */
function stackMode(): '0' | '1' {
  const mode = process.env['OCUTALON_E2E_DEMO_MODE'];
  if (mode !== '0' && mode !== '1') {
    throw new Error('OCUTALON_E2E_DEMO_MODE must be 1 (demo mode on) or 0 (demo mode off)');
  }
  return mode;
}

test('a tell-now notification and a reminder are on the phone in demo mode, and nowhere on it with demo mode off', async ({ page }) => {
  const mode = stackMode();
  const stamp = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  const tellNow = `zz switch ${stamp} Disk almost full`;
  const reminder = `zz switch ${stamp} stretch`;
  const tellNowText = `${tellNow}\nWhy now: zz switch reason`;
  const reminderText = `Reminder: ${reminder}.`;

  const start = new Date(Date.now() - 2000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const before = await phoneRows(README_ACCOUNT.user);
  try {
    await sendNotification(README_ACCOUNT.user, { kind: 'tellnow', catalogKey: 'notice.tellNow', slots: { whatHappened: tellNow, reason: 'zz switch reason' } });
    await sendNotification(README_ACCOUNT.user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text: reminder, dueAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z') } });

    const cards = page.locator('app-chat-panel app-notice-card').filter({ hasText: stamp });
    await expect(cards, 'both notifications are cards of the web chat, in either mode').toHaveCount(2, { timeout: 20_000 });

    if (mode === '1') {
      const phone = page.getByRole('region', { name: 'Simulated devices' }).locator('app-simulated-phone');
      const messages = phone.locator('.notification').filter({ hasText: stamp });
      await expect(messages, 'demo mode is on: both texts are on the phone').toHaveCount(2, { timeout: 20_000 });
      await expect(messages.locator('.text'), 'in the order they were sent').toHaveText([tellNowText, reminderText], { useInnerText: true });
      await page.reload();
      await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
      await expect(
        page.getByRole('region', { name: 'Simulated devices' }).locator('app-simulated-phone .notification').filter({ hasText: stamp }).locator('.text'),
        'and still there after a reload',
      ).toHaveText([tellNowText, reminderText], { useInnerText: true });
      expect(await phoneRows(README_ACCOUNT.user), 'two SimMessage rows were made').toBe(before + 2);
    } else {
      await expect(page.getByRole('region', { name: 'Simulated devices' }), 'demo mode is off: no region').toHaveCount(0);
      await expect(page.locator('app-simulated-phone'), 'and no phone').toHaveCount(0);
      const state = await page.request.get(STATE);
      expect(state.status()).toBe(200);
      expect(Object.keys((await state.json()) as Record<string, unknown>), '/state has no phone key').not.toContain('phone');
      expect(await phoneRows(README_ACCOUNT.user), 'and no SimMessage row was made').toBe(before);
    }
  } finally {
    await dropPhone(README_ACCOUNT.user, start);
  }
});
