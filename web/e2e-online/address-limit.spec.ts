import { expect, test } from '@playwright/test';

import { pageTime } from '../src/app/chat/page-time';
import { irisScript, chk, quoted } from '../e2e/support/iris';
import { removeCounterRows, removeSession, signInFromSplash, signInOverHttpFrom, signOutGroup, SIGN_OUT } from './support';

/**
 * Story 16.3, the address limit on the page (L1; matrix row 11). It runs in the unit's proxied phase only, when the unit has set the
 * public proxy address to the address that IRIS sees for this host's requests and gives a client address of its own in
 * OCUTALON_ONLINE_LIMIT_ADDRESS: every sign-in here is then a proxied one, counted under the address of its X-Forwarded-For header.
 * - L1: five API sign-ins of that address use its places; the splash, opened from the same address in a browser context in the zone
 *   Asia/Kolkata and the locale en-US, then refuses the sixth with the field error under **Sign in and start**: the sentence with the page
 *   time of the oldest counted creation plus one hour, focused, with no field marked, the button enabled and no shell. The address's
 *   counter rows are removed after.
 * The text is written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 180_000 });
test.skip(process.env['OCUTALON_ONLINE_PROXIED'] !== '1', "runs in the unit's proxied phase");

test('L1: the sixth new session of an address is refused under the button, with the time of the next place', async ({ browser, playwright }) => {
  const address = process.env['OCUTALON_ONLINE_LIMIT_ADDRESS'] ?? '';
  expect(address, 'the unit names the address of the case').not.toBe('');
  const epochsToRemove: string[] = [];
  const context = await browser.newContext({ timezoneId: 'Asia/Kolkata', locale: 'en-US', extraHTTPHeaders: { 'X-Forwarded-For': address } });
  const page = await context.newPage();
  try {
    for (let i = 1; i <= 5; i += 1) {
      const { api, answer } = await signInOverHttpFrom(playwright, address);
      try {
        expect(answer.status(), `API sign-in ${i} from the address gives the shell`).toBe(200);
        const state = await api.get('/ocutalon/api/v1/state');
        expect(state.status(), `API sign-in ${i} has a session`).toBe(200);
        epochsToRemove.push(((await state.json()) as { epoch: string }).epoch);
      } finally {
        await api.get(SIGN_OUT).catch(() => undefined);
        await api.dispose();
      }
    }
    const counted = await irisScript(
      [
        `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*), MIN(CreatedAt) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?",##class(OcuTalon.Data.AddressCounter).AddressHash(${quoted(address)}))`,
        'Do rs.%Next()',
        'Write !,"CHK|count|",rs.%GetData(1),!,"CHK|oldest|",rs.%GetData(2)',
      ].join('\n'),
    );
    expect(chk(counted, 'count'), 'five counter rows for the address').toBe('5');
    const oldest = chk(counted, 'oldest') ?? '';
    const until = new Date(Date.parse(oldest) + 3600 * 1000).toISOString();

    await signInFromSplash(page);
    const error = page.locator('#ocu-error');
    const sentence = `Too many new sessions from your network this hour. You can start another at ${pageTime(until, 'en-US', 'Asia/Kolkata')}.`;
    await expect(error, "the error is the AC's sentence with the page time of the oldest creation plus one hour").toHaveText(sentence);
    await expect(error.locator('time'), 'the time element carries the moment').toHaveAttribute('datetime', until.replace('.000Z', 'Z'));
    const button = page.getByRole('button', { name: 'Sign in and start', exact: true });
    expect(await button.evaluate((node) => node.nextElementSibling?.id), "the error is the button's next element sibling").toBe('ocu-error');
    expect(await page.evaluate(() => document.activeElement?.id), 'and has the focus').toBe('ocu-error');
    await expect(page.getByLabel('User name', { exact: true }), 'the user name is not marked').not.toHaveAttribute('aria-invalid', /.*/);
    await expect(page.getByLabel('Password', { exact: true }), 'the password is not marked').not.toHaveAttribute('aria-invalid', /.*/);
    await expect(button, 'the button is enabled').toBeEnabled();
    await expect(page.locator('app-root'), 'no shell is served').toHaveCount(0);
  } finally {
    await signOutGroup(context);
    await context.close();
    for (const epoch of epochsToRemove) await removeSession(epoch);
    await removeCounterRows(address);
  }
});
