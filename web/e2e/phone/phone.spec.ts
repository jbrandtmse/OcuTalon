import { expect, test, type Locator, type Page } from '@playwright/test';

import { changeSnapshot } from '../support/api';
import { clock, tokenColor } from '../support/page';
import { signInReadme } from '../sign-in/helpers';

/**
 * Story 4.5, the simulated device panel and the simulated phone (P1 to P4), in a real browser against the live sign-in stack, as the
 * README account (the stack is in demo mode). The cases write nothing on the server: the snapshot's `phone` is changed on its way to
 * the page (changeSnapshot) to the fixture messages a case names, so that what the README session holds does not matter. The
 * messages that arrive through the real SimPhoneOut are the specs of the floor (D3, D4), the chat (N11) and the demo switch.
 *   P1  the region, the two tabs, their names and selection, the arrow keys, the memory of the choice and its failures, the skip link;
 *   P2  the phone's look: the frame, the top bar, the Simulated label, no composer;
 *   P3  the empty text, and the messages: order, line breaks, markup as text, the caption time in a browser zone unlike the instance's;
 *   P4  demo mode off with a `phone` key present: no region and no middle skip link.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US', viewport: { width: 1280, height: 720 } });

/** A poll or a snapshot that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const PHONE_TAB = 'Simulated phone';
const MAILBOX_TAB = 'Simulated mailbox';
const EMPTY = "Notifications, reminders and approval requests appear here. The simulated phone is a real channel in the production; you'll see it in the trace.";

/** A message of the snapshot's phone, named as a fixture by its ref and its text. */
const fixture = (n: number, text: string, createdAt = `2030-01-01T10:0${n}:00Z`): Record<string, unknown> => ({ ref: `zzfixture${n}`, direction: 'out', text, approvalRef: '', createdAt });

/** Answers /state with this phone, and opens the README page. */
async function open(page: Page, phone: Array<Record<string, unknown>>, demoMode = true): Promise<void> {
  await changeSnapshot(page, (snapshot) => {
    snapshot['phone'] = phone;
    snapshot['demoMode'] = demoMode;
  });
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

const regionOf = (page: Page): Locator => page.getByRole('region', { name: 'Simulated devices' });
const tabOf = (page: Page, name: string): Locator => regionOf(page).getByRole('tab', { name, exact: true });
const phoneOf = (page: Page): Locator => regionOf(page).locator('app-simulated-phone');

/** P1: the region and its ARIA tabs: names, selection, roving tabindex, the arrow keys, the memory of the choice, and the skip link. */
test('P1: the region has the two tabs, the arrows move between them, and the choice is remembered', async ({ page }) => {
  await open(page, []);
  const region = regionOf(page);
  await expect(region, 'the region Simulated devices is there once').toHaveCount(1);
  await expect(region.getByRole('tab'), 'it holds two tabs').toHaveText([PHONE_TAB, MAILBOX_TAB]);
  const phone = tabOf(page, PHONE_TAB);
  const mailbox = tabOf(page, MAILBOX_TAB);
  await expect(phone, 'the phone is selected by default').toHaveAttribute('aria-selected', 'true');
  await expect(phone).toHaveAttribute('tabindex', '0');
  await expect(mailbox).toHaveAttribute('aria-selected', 'false');
  await expect(mailbox, 'and only the selected tab is a tab stop').toHaveAttribute('tabindex', '-1');
  await expect(region.getByRole('tabpanel', { name: PHONE_TAB }), 'each tab controls a panel that it names').toBeVisible();
  await expect(phone).toHaveAttribute('aria-controls', 'device-panel-phone');
  await expect(region.locator('#device-panel-phone')).toHaveAttribute('aria-labelledby', 'device-tab-phone');
  await expect(region.locator('#device-panel-mailbox'), 'the other panel is hidden').toBeHidden();
  await expect(mailbox).toHaveAttribute('aria-controls', 'device-panel-mailbox');
  await expect(region.locator('#device-panel-mailbox')).toHaveAttribute('aria-labelledby', 'device-tab-mailbox');
  await expect(region.locator('[aria-live], [aria-atomic], [aria-relevant], [role="log"], [role="status"], [role="alert"]'), 'nothing in the region is a live region').toHaveCount(0);

  await phone.focus();
  await page.keyboard.press('ArrowRight');
  await expect(mailbox, 'ArrowRight focuses the other tab').toBeFocused();
  await expect(mailbox, 'and selects it').toHaveAttribute('aria-selected', 'true');
  await expect(mailbox).toHaveAttribute('tabindex', '0');
  await expect(phone).toHaveAttribute('tabindex', '-1');
  await expect(region.getByRole('tabpanel', { name: MAILBOX_TAB }), 'its panel shows, with the header').toBeVisible();
  await expect(region.getByRole('tabpanel', { name: MAILBOX_TAB })).toContainText('Simulated mailbox');
  await expect(region.locator('#device-panel-phone')).toBeHidden();
  await page.keyboard.press('ArrowRight');
  await expect(phone, 'ArrowRight wraps').toBeFocused();
  await expect(phone).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('ArrowLeft');
  await expect(mailbox, 'ArrowLeft wraps the other way').toBeFocused();
  await expect(mailbox).toHaveAttribute('aria-selected', 'true');

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(tabOf(page, MAILBOX_TAB), 'the mailbox is still selected after a reload').toHaveAttribute('aria-selected', 'true');
  expect(await page.evaluate(() => localStorage.getItem('ocutalon.devices.tab')), 'under its own key').toBe('mailbox');
  await tabOf(page, MAILBOX_TAB).focus();
  await page.keyboard.press('ArrowLeft');
  await expect(tabOf(page, PHONE_TAB)).toHaveAttribute('aria-selected', 'true');
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(tabOf(page, PHONE_TAB), 'and so is the phone').toHaveAttribute('aria-selected', 'true');

  await expect(page.getByRole('link', { name: 'Skip to simulated devices', exact: true }), 'the middle skip link exists in demo mode').toHaveCount(1);
  await page.getByRole('link', { name: 'Skip to simulated devices', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('app-device-panel section'), 'it focuses the region').toBeFocused();
});

/** P1, a storage that throws: the choice holds for the page's life, and nothing reaches the console. */
test('P1: a storage that throws leaves the tabs working, with no console error', async ({ page }) => {
  const problems: string[] = [];
  page.on('pageerror', (error) => problems.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(message.text());
  });
  await page.addInitScript(() => {
    const fail = (): never => {
      throw new Error('storage is off');
    };
    Object.defineProperty(window, 'localStorage', { get: fail, configurable: true });
  });
  await open(page, []);
  await tabOf(page, PHONE_TAB).focus();
  await page.keyboard.press('ArrowRight');
  await expect(tabOf(page, MAILBOX_TAB), 'the arrow still selects').toHaveAttribute('aria-selected', 'true');
  await tabOf(page, MAILBOX_TAB).click();
  await page.keyboard.press('ArrowLeft');
  await expect(tabOf(page, PHONE_TAB)).toHaveAttribute('aria-selected', 'true');
  expect(problems, 'and nothing was logged as an error').toEqual([]);
});

/** P2: the phone's look: frame, screen, top bar, the Simulated label and no composer. */
test('P2: the phone is a generic silhouette with OcuTalon and the Simulated label, and no composer', async ({ page }) => {
  await open(page, []);
  const phone = phoneOf(page);
  await expect(phone).toBeVisible();
  const frame = phone.locator('.frame');
  await expect(frame, 'the frame has the large corners').toHaveCSS('border-radius', '28px');
  await expect(frame, 'the phone-frame colour').toHaveCSS('background-color', await tokenColor(page, '--simulated-phone-frame'));
  await expect(frame, 'and a device shadow').not.toHaveCSS('box-shadow', 'none');
  await expect(phone.locator('.screen'), 'the screen is on the surface').toHaveCSS('background-color', await tokenColor(page, '--surface'));
  const bar = phone.locator('.bar');
  await expect(bar.locator('.name'), 'the top bar reads OcuTalon').toHaveText('OcuTalon');
  await expect(bar, 'with the Simulated label and nothing else').toHaveText(/^\s*OcuTalon\s*Simulated\s*$/);
  const label = bar.locator('app-simulated-label .label');
  await expect(label).toHaveText('Simulated');
  await expect(label, 'the label is amber').toHaveCSS('color', await tokenColor(page, '--simulated-label-foreground'));
  await expect(label).toHaveCSS('background-color', await tokenColor(page, '--simulated-label-background'));
  await expect(label).toHaveCSS('border-top-color', await tokenColor(page, '--simulated-label-foreground'));
  await expect(label).toHaveCSS('border-radius', '9999px');
  const stop = await label.evaluate((el) => ({ own: el.tabIndex, host: (el.closest('app-simulated-label') as HTMLElement).tabIndex, focusable: el.matches('a[href], button, input, [tabindex]') || el.closest('app-simulated-label')!.matches('[tabindex]') }));
  expect(stop, 'the label takes no focus').toEqual({ own: -1, host: -1, focusable: false });
  await expect(phone.getByRole('textbox'), 'there is no composer or textbox').toHaveCount(0);
  await expect(phone.getByRole('button'), 'and no button until a message needs one').toHaveCount(0);
});

/** P3: the empty text, then the messages: order, line breaks, markup as text and the caption time in the browser's own zone. */
test('P3: the empty phone says what it is for', async ({ page }) => {
  await open(page, []);
  await expect(phoneOf(page).locator('.empty')).toHaveText(EMPTY);
  await expect(phoneOf(page).locator('.notification')).toHaveCount(0);
});

test('P3: the messages are notifications, newest at the bottom, with their line breaks, a caption time, and markup as text', async ({ page }) => {
  const first = '2030-01-01T10:01:00Z';
  await open(page, [
    fixture(1, 'zz fixture first', first),
    fixture(2, 'zz fixture second\nWhy now: zz reason'),
    fixture(3, '<b>zz fixture markup</b>'),
  ]);
  const messages = phoneOf(page).locator('.notification');
  await expect(messages, 'three notifications').toHaveCount(3);
  await expect(messages.locator('.text'), 'in the snapshot\'s order, the newest at the bottom').toHaveText(['zz fixture first', 'zz fixture second\nWhy now: zz reason', '<b>zz fixture markup</b>'], { useInnerText: true });
  await expect(messages.nth(2).locator('b'), 'markup is text, not an element').toHaveCount(0);
  const second = messages.nth(1).locator('.text');
  await expect(second, 'a line break is kept').toHaveCSS('white-space', 'pre-line');
  const lines = await second.evaluate((el) => Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight)));
  expect(lines, 'and shows as two lines').toBe(2);
  await expect(messages.first().locator('.time'), 'the caption reads the time in the browser\'s zone, named because it differs from the instance\'s').toHaveText(new RegExp(`^${clock(first)} (IST|GMT\\+5:30)$`));
  await expect(messages.first(), 'a notification is on the sunken colour').toHaveCSS('background-color', await tokenColor(page, '--sunken'));
  const order = await messages.evaluateAll((all) => all.map((one) => one.getBoundingClientRect().top));
  expect([...order].sort((a, b) => a - b), 'the layout order is the list order').toEqual(order);
});

/** P4: with demo mode off the page shows no region and no middle skip link, even when the snapshot carries a phone. */
test('P4: demo mode off with a phone key gives no region and no middle skip link', async ({ page }) => {
  await open(page, [fixture(1, 'zz fixture first')], false);
  await expect(regionOf(page), 'no region Simulated devices').toHaveCount(0);
  await expect(page.locator('app-device-panel section'), 'no section at all').toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Skip to simulated devices', exact: true }), 'no middle skip link').toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Skip to chat', exact: true })).toHaveCount(1);
  await expect(page.getByRole('link', { name: 'Skip to status', exact: true })).toHaveCount(1);
  await expect(page.locator('app-simulated-phone'), 'and no phone').toHaveCount(0);
  const main = (await page.locator('main.main').boundingBox())!;
  const viewport = await page.evaluate(() => document.documentElement.clientWidth);
  expect(main.x + main.width, 'main reaches the right edge').toBeCloseTo(viewport, 0);
});
