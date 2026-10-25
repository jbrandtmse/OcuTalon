import { expect, test, type Locator, type Page } from '@playwright/test';

import { MESSAGES, changeSnapshot, holdState } from '../support/api';
import { freeze } from '../support/clock';
import {
  CARD_MS,
  addReminder,
  addResetSoon,
  applied,
  banner,
  clearFullPage,
  composerOf,
  expectRing,
  expectRingInside,
  mainOf,
  openFloor,
  railOf,
  readFocus,
  replyOf,
  rowOf,
  seedFullPage,
  seedScrollingPage,
  settled,
  unique,
  type Reading,
} from '../support/floor';
import { cleanFixtureRows, fixtureUser, publishStatus, seedDecision, seedTurns, turnRows } from '../support/iris';
import { tokenColor } from '../support/page';

/**
 * Story 2.14, the keyboard and the labels (K1 to K6), in a real browser against a real stack. It pins that the whole page works by the
 * keyboard: the skip links are the first tab stops and move focus to the regions (K1); one Esc acts on the topmost layer only, the
 * tooltip, then the popover, then the disclosure that holds focus (K2); no printable key does anything (K3); the focus ring is 2px, in
 * the focus colour, with its halo, and never falls outside the viewport or a scroller (K4); every control has a name, no icon is read
 * and an icon-only button names its action and its object (K5); and the inactive conversation link stays focusable and says why (K6).
 * It needs the stack that docker/tests/test-floor.sh starts: every case signs in as the floor user (OCUTALON_FLOOR_USER, the user role)
 * over real HTTP, in a fresh browser context, so the Trace help of a rail row is unseen in it. A case removes its rows with
 * cleanFixtureRows and turns the conditions it publishes off in finally. No case lets a chat post reach the server, so no turn of one
 * case replies inside another case's window.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll, a snapshot or a post that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';

const SKIP_CHAT = 'Skip to chat';
const SKIP_STATUS = 'Skip to status';

/** The most tab stops K4 walks before it gives up looking for Send. */
const MOST_STOPS = 150;

/** Expects a focus target that is not a tab stop to draw the ring inside its own edge: 2px solid in the focus colour, with the surface halo inside it. */
async function expectInsideRing(page: Page, reading: Reading, what: string): Promise<void> {
  const focus = await tokenColor(page, '--focus');
  const surface = await tokenColor(page, '--surface');
  expect(reading.outlineStyle, `${what}: the ring is solid`).toBe('solid');
  expect(reading.outlineWidth, `${what}: 2px`).toBe('2px');
  expect(reading.outlineColor, `${what}: in the focus colour`).toBe(focus);
  expect(reading.outlineOffset, `${what}: inside its own edge`).toBe('-2px');
  expect(reading.boxShadow, `${what}: with the surface halo inside the ring`).toContain(`${surface} 0px 0px 0px 4px inset`);
  expectRingInside(reading, what);
}

const skipLink = (page: Page, name: string): Locator => page.getByRole('link', { name, exact: true });
const homeLink = (page: Page): Locator => page.locator('app-header a.home');

/** Seeds the decision rows of a case: one attention decision with a trace link, whose row is a disclosure with a Trace link beside it. */
async function seedRow(user: string, refs: string[], label: string): Promise<string> {
  const summary = unique(label);
  refs.push(await seedDecision(user, { outcome: 'act', summary, reasons: 'zz first reason.\nzz second reason.', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4242 }));
  return summary;
}

/** Whether the focused element is inside the locator's element and is not that element itself. */
const focusIsInside = (region: Locator): Promise<boolean> =>
  region.evaluate((el) => el !== document.activeElement && el.contains(document.activeElement));

/** K1: the skip links are the first tab stops, show while focused, and move focus to the regions without changing the address. */
test('K1: Skip to chat and Skip to status are the first tab stops and move focus to their regions', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  let hold: Awaited<ReturnType<typeof holdState>> | undefined;
  try {
    const summary = await seedRow(user, refs, 'K1 row');
    await openFloor(page);
    await expect(rowOf(page, summary), 'the rail has a control to reach').toHaveCount(1);
    const home = page.url();
    const mark = (): Promise<void> => page.evaluate(() => history.replaceState(null, '', `${location.pathname}${location.search}#/k1`));
    await mark();
    const address = page.url();
    expect(address, 'the case gives the address a mark that a followed link would change').not.toBe(home);

    await page.keyboard.press('Tab');
    await expect(skipLink(page, SKIP_CHAT), 'the first tab stop is Skip to chat').toBeFocused();
    let reading = (await readFocus(page))!;
    expect(reading.clipPath, 'it shows while it has focus').toBe('none');
    expect(reading.ring.left, 'at the top left of the page').toBeLessThan(16);
    expect(reading.ring.top).toBeLessThan(16);
    await expectRing(page, reading, SKIP_CHAT);
    expectRingInside(reading, SKIP_CHAT);
    await expect(skipLink(page, SKIP_STATUS), 'the other link is hidden').toHaveCSS('clip-path', 'inset(50%)');

    await page.keyboard.press('Tab');
    await expect(skipLink(page, SKIP_STATUS), 'the second is Skip to status').toBeFocused();
    reading = (await readFocus(page))!;
    expect(reading.clipPath).toBe('none');
    await expectRing(page, reading, SKIP_STATUS);
    expectRingInside(reading, SKIP_STATUS);
    await expect(skipLink(page, SKIP_CHAT), 'and the first is hidden again').toHaveCSS('clip-path', 'inset(50%)');

    await page.keyboard.press('Tab');
    await expect(homeLink(page), 'the third is the home link').toBeFocused();

    await page.keyboard.press('Shift+Tab');
    await page.keyboard.press('Shift+Tab');
    await expect(skipLink(page, SKIP_CHAT)).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(mainOf(page), 'Enter puts focus on the main region').toBeFocused();
    expect(page.url(), 'and leaves the address as it was').toBe(address);
    reading = (await readFocus(page))!;
    expectRingInside(reading, 'main');
    await page.keyboard.press('Tab');
    expect(await focusIsInside(mainOf(page)), 'the next Tab is inside main').toBe(true);

    await page.evaluate((url) => history.replaceState(null, '', url), home);
    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(rowOf(page, summary)).toHaveCount(1);
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await expect(skipLink(page, SKIP_STATUS)).toBeFocused();
    await mark();
    await page.keyboard.press('Enter');
    const rail = page.locator('section.rail');
    await expect(rail, 'Enter on Skip to status puts focus on the region Status').toBeFocused();
    await expect(railOf(page)).toHaveCount(1);
    expect(page.url(), 'and leaves the address as it was').toBe(address);
    reading = (await readFocus(page))!;
    expectRingInside(reading, 'the rail');
    await page.keyboard.press('Tab');
    expect(await focusIsInside(rail), "the next Tab reaches the rail's first control").toBe(true);

    await page.clock.install();
    hold = await holdState(page);
    await page.goto('/ocutalon/');
    await expect.poll(() => hold!.held(), { message: 'the snapshot is held' }).toBeGreaterThan(0);
    await expect(mainOf(page), 'the page is still loading').toHaveAttribute('data-snapshot', 'loading');
    await expect(page.locator('.skeleton').first()).toBeVisible();
    await freeze(page);
    await page.keyboard.press('Tab');
    await expect(skipLink(page, SKIP_CHAT), 'while loading, the first stop is the same').toBeFocused();
    await page.keyboard.press('Tab');
    await expect(skipLink(page, SKIP_STATUS), 'and so is the second').toBeFocused();
    await page.keyboard.press('Tab');
    await expect(homeLink(page)).toBeFocused();
    await page.keyboard.press('Shift+Tab');
    await page.keyboard.press('Shift+Tab');
    await expect(skipLink(page, SKIP_CHAT)).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(mainOf(page), 'Enter puts focus on main while it shows its skeletons').toBeFocused();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loading');
    expectRingInside((await readFocus(page))!, 'main while loading');
  } finally {
    hold?.release();
    await cleanFixtureRows(refs);
  }
});

/** K2: one Esc acts on one layer: a shown tooltip, then an open popover, then the disclosure that holds focus. */
test('K2: Esc hides the tooltip first, closes the popover next, and collapses the row last', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const summary = await seedRow(user, refs, 'K2 row');
    await openFloor(page);
    const row = rowOf(page, summary);
    const button = row.locator('app-decision-row button.line1');
    const link = row.locator('app-trace-link a');
    const tooltip = page.locator('app-tooltip');
    await expect(link, 'the decision row carries a Trace link').toHaveCount(1);

    await button.focus();
    await page.keyboard.press('Enter');
    await expect(button, 'the row is opened by the keyboard').toHaveAttribute('aria-expanded', 'true');
    await row.locator('app-outcome-chip .chip').hover();
    await expect(tooltip, 'the pointer rests on the chip and its tooltip shows').toBeVisible();
    await page.keyboard.press('Escape');
    await expect(tooltip, 'the first Esc hides the tooltip').toHaveCount(0);
    await settled(page);
    await expect(button, 'the row stays open').toHaveAttribute('aria-expanded', 'true');
    await expect(button, 'and focus stays').toBeFocused();
    await page.keyboard.press('Escape');
    await expect(button, 'the second Esc collapses the row').toHaveAttribute('aria-expanded', 'false');
    await expect(button, 'and focus stays').toBeFocused();

    await page.mouse.move(0, 0);
    await page.keyboard.press('Enter');
    await expect(button, 'the row is opened again').toHaveAttribute('aria-expanded', 'true');
    await link.click();
    const help = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(help, 'pressing the Trace link opens the help').toBeVisible();
    await expect(help.locator(':focus'), 'with focus inside it, where the popover puts it').toHaveCount(1);
    await link.focus();
    await expect(link, 'focus is back on the link').toBeFocused();
    await expect(help, 'and the help stays open').toBeVisible();
    await page.keyboard.press('Escape');
    await expect(help, 'Esc closes the help').toHaveCount(0);
    await settled(page);
    await expect(button, 'and only the help: the row stays open').toHaveAttribute('aria-expanded', 'true');
    await expect(link, 'with focus on the link').toBeFocused();

    await composerOf(page).focus();
    await page.keyboard.press('Escape');
    await settled(page);
    await expect(button, 'with focus outside the row, Esc leaves it open').toHaveAttribute('aria-expanded', 'true');
    await expect(composerOf(page)).toBeFocused();

    // A tooltip that only waits out its 300 ms delay lets the Esc through. The page drives the pointer's enter and the Esc in one
    // task, so that no timer can run between them, whatever the runner's speed.
    await button.focus();
    const showed = await row.locator('app-outcome-chip .chip').evaluate(async (chip) => {
      const focused = document.activeElement as HTMLElement;
      let seen = false;
      const observer = new MutationObserver(() => {
        if (document.querySelector('app-tooltip')) seen = true;
      });
      observer.observe(document.body, { childList: true, subtree: true });
      chip.dispatchEvent(new PointerEvent('pointerenter', { pointerType: 'mouse' }));
      focused.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
      await new Promise((done) => setTimeout(done, 600));
      observer.disconnect();
      return seen;
    });
    expect(showed, 'the Esc cancelled the waiting tooltip: it never shows').toBe(false);
    await expect(button, 'and that Esc reached the row, which collapsed').toHaveAttribute('aria-expanded', 'false');
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** K2, the reply strip: the Esc that closes the Trace help opened from a strip leaves the strip's details open. */
test('K2: Esc closes the Trace help of a reply strip and leaves its details open', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const traceUrl = `https://example.invalid/zz-floor-k2-${Date.now().toString(36)}`;
  try {
    const seeded = await seedTurns(user, [
      {
        createdAt: '2019-04-02T10:00:00Z',
        text: unique('K2 strip question'),
        replyText: 'zz K2 strip reply.',
        turn: { outcome: 'act', reasons: 'zz first reason.\nzz second reason.', confidence: 0.9, costUSD: 0.0003 },
      },
    ]);
    refs.push(...turnRows(seeded));
    const ref = seeded.refs[0]!;
    await changeSnapshot(page, (snapshot) => {
      for (const item of (snapshot['chat'] ?? []) as Array<{ type: string; payload: Record<string, unknown> }>) {
        if (item.type === 'chat.message' && item.payload['ref'] === ref) item.payload['traceUrl'] = traceUrl;
      }
    });
    await openFloor(page);
    const strip = replyOf(page, ref).locator('app-decision-strip');
    const details = strip.getByRole('button', { name: 'Decision details' });
    const link = strip.locator('app-trace-link a');
    await expect(link, 'the strip carries a Trace link').toHaveCount(1);

    await details.click();
    await expect(details, 'the details are open').toHaveAttribute('aria-expanded', 'true');
    await link.click();
    const help = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(help, 'pressing the Trace link opens the help').toBeVisible();
    await link.focus();
    await expect(link, 'focus is back on the link').toBeFocused();
    await page.keyboard.press('Escape');
    await expect(help, 'Esc closes the help').toHaveCount(0);
    await settled(page);
    await expect(details, 'and only the help: the details stay open').toHaveAttribute('aria-expanded', 'true');
    await expect(link, 'with focus on the link').toBeFocused();
    await page.keyboard.press('Escape');
    await expect(details, 'the next Esc collapses the details').toHaveAttribute('aria-expanded', 'false');
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** K2, a popover that closes before the next render: the render that was to focus into it finds nothing to do, and logs no error. */
test('K2: a popover that Esc closes in the task that opened it logs no error', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  page.on('pageerror', (error) => errors.push(String(error)));
  await openFloor(page);
  const menu = page.getByRole('button', { name: 'Visual Trace', exact: true });
  await menu.focus();
  await expect(menu).toBeFocused();
  errors.length = 0;

  // The page opens the popover and presses Esc in one task, so that the render that waits to focus into it comes after it has closed.
  const opened = await menu.evaluate((trigger) => {
    const button = trigger as HTMLElement;
    button.click();
    const shown = document.querySelectorAll('.app-popover').length;
    (document.activeElement ?? document.body).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    return shown;
  });
  await settled(page);
  expect(opened, 'the click opened the Visual Trace popover').toBe(1);
  await expect(page.locator('.app-popover'), 'Esc closed it').toHaveCount(0);
  await expect(menu, 'and focus stays on its trigger').toBeFocused();
  expect(errors, 'and the page logged no error').toEqual([]);
});

/** K3: no printable key does anything: nothing moves focus, opens, sends or navigates. */
test('K3: the keys a, s, t, /, ? and 1 change nothing', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const posts: string[] = [];
  try {
    const summary = await seedRow(user, refs, 'K3 row');
    page.on('request', (request) => {
      if (request.method() === 'POST' && new URL(request.url()).pathname === MESSAGES) posts.push(request.url());
    });
    await openFloor(page);
    const row = rowOf(page, summary);
    const address = page.url();
    const overlays = page.locator('[role=dialog], [role=menu], .app-popover, .cdk-overlay-pane');

    const pressKeys = async (where: string): Promise<void> => {
      await page.evaluate(() => {
        (window as unknown as { kept: Element | null }).kept = document.activeElement;
      });
      for (const key of ['a', 's', 't', '/', '?', '1']) {
        await page.keyboard.press(key);
        await settled(page);
        const kept = await page.evaluate(() => document.activeElement === (window as unknown as { kept: Element | null }).kept);
        expect(kept, `${where}: "${key}" moves no focus`).toBe(true);
        await expect(overlays, `${where}: "${key}" opens nothing`).toHaveCount(0);
        expect(page.url(), `${where}: "${key}" navigates nowhere`).toBe(address);
      }
      expect(posts, `${where}: nothing is sent`).toEqual([]);
    };

    await page.evaluate(() => (document.activeElement as HTMLElement | null)?.blur());
    await pressKeys('on the body');
    await mainOf(page).focus();
    await expect(mainOf(page)).toBeFocused();
    await pressKeys('on main');
    const button = row.locator('app-decision-row button.line1');
    await button.focus();
    await expect(button).toBeFocused();
    await pressKeys("on a rail row's button");
    await expect(button, 'the row did not open').toHaveAttribute('aria-expanded', 'false');
    await expect(composerOf(page), 'and the composer holds nothing').toHaveValue('');
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** K4: the focus ring is 2px, solid, in the focus colour with its halo, and lies inside the viewport and inside every scroller. */
test('K4: no focus ring is clipped, at every tab stop of a page whose rail and chat both scroll', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 720 });
    const stamp = unique('K4');
    await seedScrollingPage(user, refs, stamp);
    await openFloor(page);
    await addResetSoon(page, user);
    await expect(railOf(page).locator('app-decision-row').filter({ hasText: stamp }), 'twelve decision rows').toHaveCount(12);
    const scrolls = await page.evaluate(() => {
      const rail = document.querySelector('section.rail')!;
      const list = document.querySelector('app-chat-panel .list')!;
      return { rail: rail.scrollHeight - rail.clientHeight, list: list.scrollHeight - list.clientHeight };
    });
    expect(scrolls.rail, 'the rail scrolls').toBeGreaterThan(40);
    expect(scrolls.list, 'and so does the chat list').toBeGreaterThan(40);

    const stops: string[] = [];
    for (let i = 0; i < MOST_STOPS; i += 1) {
      await page.keyboard.press('Tab');
      const reading = await readFocus(page);
      expect(reading, `Tab ${i + 1} lands on an element`).not.toBeNull();
      await expectRing(page, reading!, reading!.what);
      expectRingInside(reading!, reading!.what);
      stops.push(reading!.what);
      if (await page.locator('app-composer button').evaluate((el) => el === document.activeElement)) break;
    }
    expect(stops[0], 'the walk starts at the first skip link').toContain(SKIP_CHAT);
    expect(stops[stops.length - 1], 'and ends at Send').toContain('Send');
    expect(stops.filter((one) => /^a[ #]/.test(one) && one.includes('Trace')).length, 'it passed the Trace link of every rail row').toBeGreaterThanOrEqual(12);
    expect(stops.length, 'at every stop of the page').toBeGreaterThan(30);

    // New messages is no stop of the walk: it shows only when a turn lands while the list is scrolled up.
    await page.locator('app-chat-panel > .list').evaluate((el) => {
      el.scrollTop = 0;
    });
    const landed = await seedTurns(user, [{ createdAt: '2019-03-09T10:00:00Z', text: `${stamp} landed`, replyText: `${stamp} reply landed.` }], true);
    refs.push(...turnRows(landed));
    await applied(page, landed.seqs[0]!);
    const newMessages = page.getByRole('button', { name: 'New messages' });
    await expect(newMessages, 'a turn that lands while the list is scrolled up shows New messages').toBeVisible();
    await composerOf(page).focus();
    await page.keyboard.press('Shift+Tab');
    await expect(newMessages, 'Shift+Tab from the composer reaches it').toBeFocused();
    const newReading = (await readFocus(page))!;
    await expectRing(page, newReading, 'New messages');
    expectRingInside(newReading, 'New messages');

    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');
    await expect(mainOf(page)).toBeFocused();
    await expectInsideRing(page, (await readFocus(page))!, 'main');
    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');
    await expect(page.locator('section.rail')).toBeFocused();
    await expectInsideRing(page, (await readFocus(page))!, 'the rail');
    const first = page.locator('app-banner-stack [data-banner]').first();
    await expect(first, 'a banner shows after the reload').toHaveCount(1);
    await first.evaluate((el) => el.focus());
    await expect(first).toBeFocused();
    await expectInsideRing(page, (await readFocus(page))!, 'a banner');

    const gutter = await page.evaluate(() => {
      const read = (el: Element): { start: number; end: number } => {
        const style = getComputedStyle(el);
        return { start: parseFloat(style.paddingInlineStart), end: parseFloat(style.paddingInlineEnd) };
      };
      return { rail: read(document.querySelector('section.rail')!), list: read(document.querySelector('app-chat-panel .list')!) };
    });
    for (const [name, padding] of Object.entries(gutter)) {
      expect(padding.start, `the ${name}'s inline start keeps the gutter`).toBeGreaterThanOrEqual(4);
      expect(padding.end, `the ${name}'s inline end keeps the gutter`).toBeGreaterThanOrEqual(4);
    }
    await page.locator('app-header button.header-button').last().click();
    await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
    const about = page.locator('app-about-dialog');
    await expect(about).toBeVisible();
    const aboutPadding = await about.evaluate((el) => ({ start: parseFloat(getComputedStyle(el).paddingInlineStart), end: parseFloat(getComputedStyle(el).paddingInlineEnd) }));
    expect(aboutPadding.start, "About's inline start keeps the gutter").toBeGreaterThanOrEqual(4);
    expect(aboutPadding.end, "About's inline end keeps the gutter").toBeGreaterThanOrEqual(4);
  } finally {
    await publishStatus(user, { condition: 'resetSoon', active: false });
    await cleanFixtureRows(refs);
  }
});

/** The names of the controls of a page, as the accessibility tree gives them: every control has one, no icon is read, and nothing is named Close alone. */
async function expectNamed(page: Page, what: string): Promise<void> {
  const snapshot = await page.locator('body').ariaSnapshot();
  const unnamed = snapshot.split('\n').filter((line) => /^\s*- (button|link|textbox|menuitem)(?!\w)(?!\s+")/.test(line));
  expect(unnamed, `${what}: every button, link, textbox and menuitem has a name`).toEqual([]);
  expect(snapshot, `${what}: no control is named Close alone`).not.toContain('"Close"');
  expect(snapshot, `${what}: no image is read`).not.toMatch(/^\s*- img\b/m);
  const open = await page.evaluate(() => Array.from(document.querySelectorAll('svg')).filter((svg) => svg.getAttribute('aria-hidden') !== 'true').length);
  expect(open, `${what}: every svg is hidden from assistive technology`).toBe(0);
}

/** K5: every control is named, an icon-only button names its action and its object, and no icon is read. */
test('K5: every control has a name, and the banner and About Close buttons name their object', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const full = await seedFullPage(user, refs);
    await openFloor(page);
    await addReminder(page, user, full.stamp);
    await addResetSoon(page, user);
    await expect(banner(page, 'noModelKey'), 'the no-key banner shows').toHaveCount(1, { timeout: CARD_MS });
    const own = railOf(page).locator('li.row').filter({ hasText: full.stamp }).or(railOf(page).locator(`li.row[data-row-key="approvals:${full.approval}"]`));
    await expect(own, 'one row of each rail kind').toHaveCount(4);
    await expect(own.locator('app-trace-link a'), 'each with a trace link').toHaveCount(4);
    await expect(page.locator('app-decision-strip'), 'a done turn has its strip').not.toHaveCount(0);

    await expectNamed(page, 'the page');
    await expect(banner(page, 'resetSoon').getByRole('button', { name: 'Close reset notice', exact: true }), "Reset soon's Close names its notice").toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Close', exact: true }), 'no control is named Close alone').toHaveCount(0);
    await expect(page.getByRole('button', { name: /^Theme: (System|Light|Dark)$/ }), "the theme button keeps the UX's name").toHaveCount(1);

    await page.getByRole('button', { name: 'Visual Trace', exact: true }).click();
    await expect(page.locator('.app-popover'), 'the Visual Trace popover is open').toHaveCount(1);
    await expectNamed(page, 'with the Visual Trace popover open');
    await page.keyboard.press('Escape');
    await expect(page.locator('.app-popover')).toHaveCount(0);

    await page.locator('app-header button.header-button').last().click();
    await expect(page.getByRole('menuitem', { name: 'About OcuTalon' })).toBeVisible();
    await expectNamed(page, 'with the account menu open');
    await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await expectNamed(page, 'with About open');
    await expect(page.getByRole('dialog').getByRole('button', { name: 'Close About OcuTalon', exact: true }), "About's Close names its dialog").toHaveCount(1);
  } finally {
    await clearFullPage(user, refs);
  }
});

/** K6: with no turn the conversation link stays a focusable link, aria-disabled, and says why; with a turn it is a plain link. */
test('K6: the inactive conversation link is described by its visible reason, and a turn takes both away', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const posts: string[] = [];
  let phase: 'empty' | 'traced' = 'empty';
  const traceUrl = `https://example.invalid/zz-floor-k6-${Date.now().toString(36)}`;
  try {
    page.on('request', (request) => {
      if (request.method() === 'POST' && new URL(request.url()).pathname === MESSAGES) posts.push(request.url());
    });
    refs.push(...turnRows(await seedTurns(user, [{ createdAt: '2019-04-01T10:00:00Z', text: unique('K6 question'), replyText: 'zz K6 reply.' }])));
    await changeSnapshot(page, (snapshot) => {
      const chat = (snapshot['chat'] ?? []) as Array<{ type: string; payload: Record<string, unknown> }>;
      if (phase === 'empty') {
        snapshot['chat'] = [];
        return;
      }
      const newest = [...chat].reverse().find((item) => item.type === 'chat.message');
      if (newest !== undefined) newest.payload['traceUrl'] = traceUrl;
    });
    await openFloor(page);
    const menu = page.getByRole('button', { name: 'Visual Trace', exact: true });
    await menu.click();
    const popover = page.locator('.app-popover');
    await expect(popover).toHaveCount(1);
    const link = popover.getByRole('link', { name: /^Open my conversation in Visual Trace/ });
    await expect(link, 'the conversation link is a link').toHaveCount(1);
    await expect(link, 'that cannot act').toHaveAttribute('aria-disabled', 'true');
    await expect(link, 'and has focus').toBeFocused();
    const reasonId = await link.getAttribute('aria-describedby');
    expect(reasonId, 'it is described by an element').toBeTruthy();
    const reason = page.locator(`[id="${reasonId}"]`);
    await expect(reason, "the reason is visible, in the popover's words").toBeVisible();
    await expect(reason).toHaveText('Available after your first message.');
    await expect(link).toHaveAccessibleDescription('Available after your first message.');
    await expect(link, 'with no address').not.toHaveAttribute('href', /.*/);
    await page.keyboard.press('Escape');
    await expect(popover).toHaveCount(0);

    phase = 'traced';
    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await menu.click();
    await expect(popover).toHaveCount(1);
    const active = popover.getByRole('link', { name: /^Open my conversation in Visual Trace/ });
    await expect(active, 'given a turn with an address, the link has it').toHaveAttribute('href', traceUrl);
    await expect(active, 'it can act').not.toHaveAttribute('aria-disabled', /.*/);
    await expect(active, 'it is described by nothing').not.toHaveAttribute('aria-describedby', /.*/);
    await expect(popover.getByText('Available after your first message.'), 'and the reason is gone').toHaveCount(0);
    expect(posts, 'no post reached the server').toEqual([]);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await cleanFixtureRows(refs);
  }
});
