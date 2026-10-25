import { expect, test, type Page } from '@playwright/test';

import { STATE } from '../support/api';
import { signIn } from '../sign-in/helpers';
import { addReminder, addResetSoon, clearFullPage, mainOf, openFloor, seedFullPage, settled } from '../support/floor';
import { fixtureUser } from '../support/iris';
import { scanPage } from '../support/scan';

/**
 * Story 2.16, the scan (U1 to U3), in a real browser against a real stack, in Chromium, Firefox and WebKit. It pins that the in-house
 * scan of support/scan.ts finds nothing on the page: no widget without a name, no text, boundary or focus ring under its WCAG ratio, no
 * link that points at nothing (DW-178), on the full page at 1280x720 and 1280x600 and on its overlays, in the light and the dark theme
 * (U1, U2); and that it does report a planted fault of each kind, and a backdrop it cannot measure (U3). It needs the stack that
 * docker/tests/test-floor.sh starts: U1 and U2 sign in as the floor user (OCUTALON_FLOOR_USER, the user role) over real HTTP, in a fresh
 * browser context. U1 removes the rows it seeds with clearFullPage and turns Reset soon off in finally; U3 removes its plant in finally.
 * All three run in every engine (tag @browsers); no case lets a chat post reach the server.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A held poll or a held snapshot that a routed handler still holds when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';
const SCHEMES = ['light', 'dark'] as const;
const SERVER_ERROR = '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}';

/** Scans the page in the light and then the dark theme, and expects no finding in either. */
async function expectClean(page: Page, what: string): Promise<void> {
  for (const scheme of SCHEMES) {
    await page.emulateMedia({ colorScheme: scheme });
    await settled(page);
    expect(await scanPage(page, `${what} (${scheme})`), `${what}, ${scheme}: the scan finds nothing`).toEqual([]);
  }
}

/** U1: the full page, with a row of every rail kind, a done turn and two banners, at both window heights and in both themes. */
test('U1: the full page has no unnamed control, no contrast failure and no link to nothing, at 1280x720 and 1280x600', { tag: '@browsers' }, async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const full = await seedFullPage(user, refs);
    await openFloor(page);
    await addReminder(page, user, full.stamp);
    await addResetSoon(page, user);
    for (const height of [720, 600]) {
      await page.setViewportSize({ width: 1280, height });
      await expectClean(page, `the full page at 1280x${height}`);
    }
  } finally {
    await clearFullPage(user, refs);
  }
});

/** U2: the overlays and the failed load, at 1280x720, in both themes. */
test('U2: Visual Trace, the account menu, About and the failed load have no finding, in both themes', { tag: '@browsers' }, async ({ page }) => {
  const { user, password } = fixtureUser(KIND);
  await page.setViewportSize({ width: 1280, height: 720 });

  // The failed load: the first /state answers 500, and Retry's request is held until the page's clock has passed 10 s, which shows its busy notice.
  await page.clock.install();
  const waiting: Array<() => void> = [];
  let answers = 0;
  let released = false;
  await page.route(`**${STATE}`, async (route) => {
    answers += 1;
    if (answers === 1) {
      await route.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
      return;
    }
    if (!released) await new Promise<void>((resolve) => waiting.push(resolve));
    await route.continue().catch(() => undefined);
  });
  try {
    await signIn(page, user, password);
    const main = mainOf(page);
    await expect(main, 'the first load fails').toHaveAttribute('data-snapshot', 'failed');
    const retry = main.getByRole('button', { name: 'Retry', exact: true });
    await retry.click();
    await expect.poll(() => answers, { message: 'Retry asks for the snapshot again' }).toBe(2);
    await page.clock.runFor(10_000);
    await expect(main.locator('app-inline-notice'), "Retry's busy notice shows").toHaveCount(1);
    await expectClean(page, 'the failed load');
  } finally {
    released = true;
    for (const resolve of waiting.splice(0)) resolve();
  }
  await expect(mainOf(page), 'the held answer loads the page').toHaveAttribute('data-snapshot', 'loaded');

  const traceButton = page.getByRole('button', { name: 'Visual Trace', exact: true });
  await traceButton.click();
  await expect(page.locator('.app-popover'), 'the Visual Trace popover is open').toHaveCount(1);
  await expectClean(page, 'with Visual Trace open');
  await page.keyboard.press('Escape');
  await expect(page.locator('.app-popover')).toHaveCount(0);

  await page.locator('app-header button.header-button').last().click();
  const about = page.getByRole('menuitem', { name: 'About OcuTalon' });
  await expect(about, 'the account menu is open').toBeVisible();
  await expectClean(page, 'with the account menu open');
  await about.click();
  await expect(page.getByRole('dialog'), 'About is open').toBeVisible();
  await expectClean(page, 'with About open');
});

/** U3: a planted fault of each kind is reported, and nothing else is: five findings, one for each rule. */
test('U3: a planted unnamed button, low text, dead fragment, faint border and image backdrop are the scan\'s five findings', { tag: '@browsers' }, async ({ page }) => {
  await openFloor(page);
  await page.emulateMedia({ colorScheme: 'light' });
  try {
    await page.evaluate(() => {
      const plant = document.createElement('div');
      plant.id = 'scan-plant';
      Object.assign(plant.style, { background: '#ffffff', color: '#000000', padding: '8px' });
      const add = <K extends keyof HTMLElementTagNameMap>(tag: K, style: Partial<CSSStyleDeclaration>): HTMLElementTagNameMap[K] => {
        const el = document.createElement(tag);
        Object.assign(el.style, { display: 'block', margin: '4px', background: '#ffffff', color: '#000000' }, style);
        plant.append(el);
        return el;
      };
      // An icon-only button with no name.
      const button = add('button', { width: '24px', height: '24px' });
      button.type = 'button';
      // Text at about 2.8:1.
      add('p', { color: '#9a9a9a' }).textContent = 'plant low text';
      // A link to a fragment that no element has.
      const link = add('a', {});
      link.href = '#nowhere';
      link.textContent = 'plant dead link';
      // An input whose border is about 1.4:1.
      const input = add('input', { border: '1px solid #dadada' });
      input.setAttribute('aria-label', 'plant field');
      // Text on a background image: a backdrop that cannot be measured.
      add('div', { backgroundImage: 'linear-gradient(#ffffff, #eeeeee)' }).textContent = 'plant image text';
      document.body.append(plant);
    });
    const findings = await scanPage(page, 'the plant');
    expect(findings.map((one) => one.split(': ')[1]).sort(), `exactly one finding for each rule: ${findings.join(' | ')}`).toEqual([
      'contrast boundary',
      'contrast text',
      'links',
      'names',
      'unmeasured',
    ]);
    for (const [rule, element] of [
      ['names', 'button'],
      ['contrast text', 'plant low text'],
      ['links', '#nowhere'],
      ['contrast boundary', 'input'],
      ['unmeasured', 'plant image text'],
    ] as const) {
      expect(findings.some((one) => one.includes(`: ${rule}: `) && one.includes(element)), `the ${rule} finding names ${element}: ${findings.join(' | ')}`).toBe(true);
    }
  } finally {
    await page.evaluate(() => document.getElementById('scan-plant')?.remove());
  }
  expect(await page.evaluate(() => document.getElementById('scan-plant')), 'the plant is gone').toBeNull();
});
