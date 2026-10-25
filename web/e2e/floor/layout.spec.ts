import { expect, test, type Locator, type Page } from '@playwright/test';

import { STATE, changeSnapshot, holdState } from '../support/api';
import {
  CARD_MS,
  HEADER,
  MOST_STOPS,
  SKIP_CHAT,
  SKIP_STATUS,
  addReminder,
  applied,
  composerOf,
  expectRing,
  expectRingInside,
  mainOf,
  openFloor,
  railOf,
  readFocus,
  rowOf,
  seedRow,
  seedScrollingPage,
  settled,
  skipLink,
  unique,
  type Reading,
} from '../support/floor';
import { cleanFixtureRows, fixtureUser, seedApproval, seedIncident, seedTurns, setApprovalState, sinkEvent, turnRows } from '../support/iris';
import { announcedTexts, announcements, recordAnnouncements } from '../support/page';

/**
 * Story 2.15, the layout at every supported width (G1 to G7), in a real browser against a real stack. It pins the four width bands and
 * the narrow-window note: from 1440px the rail is 320px, and from 1280 to 1439px it is 288px with each region scrolling on its own
 * and the page not scrolling (G1); from 1024 to 1279px the rail is a push drawer behind a "Status" header button that shows the
 * approval request count, Esc closes it after the layers inside it, the skip links open it, and a change of band keeps focus (G2, G3);
 * below 1024px and at 200% (640x360 at device scale 2) the page is one column that scrolls as a page with only the compact header
 * sticky, the rail after main in the DOM and in tab order, and no ring ever under the header (G4, G5); the note shows once per
 * session, silent at load and announced when it appears later, and its Close is remembered for the browser, also when the storage
 * fails (G6, G7). It needs the stack that docker/tests/test-floor.sh starts: every case signs in as the floor user
 * (OCUTALON_FLOOR_USER, the user role) over real HTTP, in a fresh browser context, so its storage is empty. A case removes its rows
 * with cleanFixtureRows (the turns' included) in finally and unroutes in afterEach. No case lets a chat post reach the server, and no
 * poll is held for 8 s or longer.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll, a snapshot or a post that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';

/** The note's text and its Close name, written out here as the independent oracle of the page's own (the UX's words). */
const NOTE = 'This page is designed for a wider window. Everything still works.';
const NOTE_CLOSE = 'Close narrow-window note';

const statusButton = (page: Page): Locator => page.locator('button.status-button');
const railElement = (page: Page): Locator => page.locator('section.rail');
const noteOf = (page: Page): Locator => page.locator('app-inline-notice.narrow-note');

/** The width and left and right edges of an element, in CSS pixels. */
async function edges(element: Locator): Promise<{ left: number; right: number; width: number }> {
  const box = (await element.boundingBox())!;
  return { left: box.x, right: box.x + box.width, width: box.width };
}

/** How far the page itself scrolls: its scrolling element's overflow, and its position. */
const pageScroll = (page: Page): Promise<{ overflow: number; top: number; across: number }> =>
  page.evaluate(() => {
    const root = document.scrollingElement!;
    return { overflow: root.scrollHeight - root.clientHeight, top: root.scrollTop, across: root.scrollWidth - root.clientWidth };
  });

/** The tops of the page's layers, in the viewport's coordinates (the note's is -1 while it does not show), and whether main comes before the rail in the DOM. */
function layers(page: Page): Promise<{ header: number; slot: number; note: number; main: number; rail: number; mainFirst: boolean; headerBlock: number }> {
  return page.evaluate(() => {
    const top = (selector: string): number => document.querySelector(selector)?.getBoundingClientRect().top ?? -1;
    const main = document.querySelector('main.main')!;
    const rail = document.querySelector('section.rail')!;
    return {
      header: top('app-header'),
      slot: top('.banner-slot'),
      note: top('app-inline-notice.narrow-note'),
      main: top('main.main'),
      rail: top('section.rail'),
      mainFirst: (main.compareDocumentPosition(rail) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0,
      headerBlock: document.querySelector('app-header')!.getBoundingClientRect().height,
    };
  });
}

/** What the focused element is: a skip link, in the header, in main, in the rail, or elsewhere. */
function placeOfFocus(page: Page): Promise<'skip' | 'header' | 'main' | 'rail' | 'other'> {
  return page.evaluate(() => {
    const el = document.activeElement;
    if (el === null) return 'other';
    if (el.classList.contains('skip-link')) return 'skip';
    if (el.closest('app-header')) return 'header';
    if (el.closest('main.main')) return 'main';
    if (el.closest('section.rail')) return 'rail';
    return 'other';
  });
}

/** The bottom of the sticky header, now. */
const headerBottom = (page: Page): Promise<number> => page.evaluate(() => document.querySelector('app-header')!.getBoundingClientRect().bottom);

/**
 * Presses Tab from the page's start and reads every stop: its ring (the page's ring, inside the viewport and every scroller), where it is,
 * and what `each` makes of it. `ends` says that a stop is where the walk ends before the stop is read (focus left the page or came
 * back to the start), and `last` that the stop just read is the last. A walk that never ends is a failure.
 */
async function walk(
  page: Page,
  rules: { ends?: (reading: Reading | null, place: string) => boolean; last?: (reading: Reading) => boolean },
  each: (reading: Reading, place: string, index: number) => Promise<void>,
): Promise<Array<{ what: string; place: string }>> {
  const stops: Array<{ what: string; place: string }> = [];
  for (let i = 0; i < MOST_STOPS; i += 1) {
    await page.keyboard.press('Tab');
    const reading = await readFocus(page);
    const place = reading === null ? 'none' : await placeOfFocus(page);
    if (rules.ends?.(reading, place)) return stops;
    expect(reading, `Tab ${i + 1} lands on an element`).not.toBeNull();
    await expectRing(page, reading!, reading!.what);
    expectRingInside(reading!, reading!.what);
    await each(reading!, place, i);
    stops.push({ what: reading!.what, place });
    if (rules.last?.(reading!)) return stops;
  }
  throw new Error(`the walk did not end within ${MOST_STOPS} Tab stops: ${stops.slice(-5).map((one) => one.what).join(' | ')}`);
}

/** G1: from 1440px the rail is 320px; at 1439px 288px; at 1280x600 the page does not scroll, each region does, and Tab reaches Send. */
test('G1: the rail is 320px from 1440px and 288px below it, and at 1280x600 each region scrolls and the page does not', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await seedScrollingPage(user, refs, unique('G1'));
    await openFloor(page);
    await expect(statusButton(page), 'no Status button from 1280px up').toHaveCount(0);
    let rail = await edges(railOf(page));
    let main = await edges(mainOf(page));
    expect(Math.abs(rail.width - 320), `at 1440px the region Status is 320px wide (${rail.width})`).toBeLessThanOrEqual(1);
    expect(Math.abs(rail.right - main.left), 'and main starts at its right edge').toBeLessThanOrEqual(1);

    await page.setViewportSize({ width: 1439, height: 900 });
    await expect(statusButton(page), 'still no Status button').toHaveCount(0);
    await expect.poll(async () => Math.round((await edges(railOf(page))).width), { message: 'at 1439px the rail is 288px wide' }).toBe(288);
    rail = await edges(railOf(page));
    main = await edges(mainOf(page));
    expect(Math.abs(rail.right - main.left), 'and main starts at its right edge').toBeLessThanOrEqual(1);

    await page.setViewportSize({ width: 1280, height: 600 });
    await expect.poll(async () => Math.round((await edges(railOf(page))).width), { message: 'at 1280px the rail is 288px wide' }).toBe(288);
    await expect(noteOf(page), 'there is no narrow-window note').toHaveCount(0);
    await settled(page);
    const scrolls = await page.evaluate(() => {
      const root = document.scrollingElement!;
      const rail = document.querySelector('section.rail')!;
      const list = document.querySelector('app-chat-panel .list')!;
      return { page: root.scrollHeight - root.clientHeight, rail: rail.scrollHeight - rail.clientHeight, list: list.scrollHeight - list.clientHeight };
    });
    expect(scrolls.page, 'the page does not scroll').toBeLessThanOrEqual(0);
    expect(scrolls.rail, 'the rail scrolls').toBeGreaterThan(40);
    expect(scrolls.list, 'and so does the chat list').toBeGreaterThan(40);

    const stops = await walk(
      page,
      { last: (reading) => reading.what.includes('Send') },
      async (_reading, _place, index) => {
        expect((await pageScroll(page)).top, `the page stays at its top at Tab ${index + 1}`).toBe(0);
      },
    );
    const last = stops[stops.length - 1]!;
    expect(stops[0]!.what, 'the walk starts at the first skip link').toContain(SKIP_CHAT);
    expect(last.what, 'and ends at Send').toContain('Send');
    expect(stops.filter((one) => one.place === 'rail' && /^a[ #]/.test(one.what) && one.what.includes('Trace')).length, 'it passed the Trace link of every rail row').toBeGreaterThanOrEqual(12);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** G2: the drawer behind the Status button: its count, opening, Esc one layer at a time, closing, and the band's edges. */
test('G2: the Status button shows the approval request count and opens a drawer that Esc closes last', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  let hold: Awaited<ReturnType<typeof holdState>> | undefined;
  try {
    await page.setViewportSize({ width: 1100, height: 720 });
    for (let i = 0; i < 2; i += 1) {
      const incident = await seedIncident(user, { traceHeaderId: HEADER });
      refs.push(incident);
      refs.push(await seedApproval(user, { incidentRef: incident, dryRun: { affected: 3, itemNoun: { one: 'order', other: 'orders' } } }));
    }
    const summary = await seedRow(user, refs, 'G2 row');
    refs.push(...turnRows(await seedTurns(user, [{ createdAt: '2019-05-01T10:00:00Z', text: unique('G2 question'), replyText: 'zz G2 reply.' }])));
    await openFloor(page);

    hold = await holdState(page);
    await page.goto('/ocutalon/');
    await expect.poll(() => hold!.held(), { message: 'the snapshot is held' }).toBeGreaterThan(0);
    await expect(mainOf(page), 'the page is still loading').toHaveAttribute('data-snapshot', 'loading');
    const button = statusButton(page);
    await expect(button, 'before the snapshot the name is "Status" alone').toHaveAccessibleName('Status');
    await expect(button.locator('.count'), 'with no pill').toHaveCount(0);
    await expect(railOf(page), 'and the region Status is not shown').toHaveCount(0);
    hold.release();
    hold = undefined;
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');

    const approvalsHeading = page.locator('app-status-rail [data-section="approvals"] h3 .visually-hidden');
    const heading = (await approvalsHeading.textContent())!;
    const n = Number(/(\d+)$/.exec(heading.trim())![1]);
    expect(n, 'the rail holds at least the two approval requests of the case').toBeGreaterThanOrEqual(2);
    await expect(button, 'loaded, the name carries the count').toHaveAccessibleName(`Status, ${n} approval requests`);
    await expect(button.locator('.count'), 'the pill shows the same count').toHaveText(String(n));
    await expect(button.locator('.count')).toHaveAttribute('aria-hidden', 'true');
    await expect(button).toHaveAttribute('aria-controls', 'status-region');
    await expect(railElement(page), 'which is the id of the region Status').toHaveAttribute('id', 'status-region');
    await expect(button).toHaveAttribute('aria-expanded', 'false');
    await expect(railOf(page), 'the region Status is not shown while the drawer is closed').toHaveCount(0);

    // The count follows the live store, as the rail's heading does: a request raised live adds to it, and one answered live leaves it.
    const raised = await seedApproval(user, { kind: 'tool_call', toolName: `zz_tool_g2_${Date.now().toString(36)}`, dryRun: null });
    refs.push(raised);
    await applied(page, await sinkEvent(user, 'approval.raised', { ref: raised }));
    await expect(approvalsHeading, 'the rail counts the request raised live').toHaveText(new RegExp(`\\D${n + 1}\\s*$`));
    await expect(button, 'and so does the Status button').toHaveAccessibleName(`Status, ${n + 1} approval requests`);
    await expect(button.locator('.count')).toHaveText(String(n + 1));
    await setApprovalState(raised, 'approved');
    await applied(page, await sinkEvent(user, 'approval.answered', { ref: raised }));
    await expect(approvalsHeading, 'the rail leaves out the request answered live').toHaveText(new RegExp(`\\D${n}\\s*$`));
    await expect(button, 'and so does the Status button').toHaveAccessibleName(`Status, ${n} approval requests`);

    await button.click();
    await expect(button).toHaveAttribute('aria-expanded', 'true');
    await expect(railOf(page), 'pressed, the region shows').toHaveCount(1);
    const rail = await edges(railOf(page));
    const main = await edges(mainOf(page));
    expect(Math.abs(rail.width - 288), `the drawer is 288px wide (${rail.width})`).toBeLessThanOrEqual(1);
    expect(Math.abs(main.left - rail.right), 'and main starts at its right edge').toBeLessThanOrEqual(1);
    await expect(railElement(page), 'focus is on the region').toBeFocused();
    expect((await pageScroll(page)).overflow, 'the page does not scroll').toBeLessThanOrEqual(0);

    const row = rowOf(page, summary);
    const line = row.locator('app-decision-row button.line1');
    await line.focus();
    await page.keyboard.press('Enter');
    await expect(line, 'the row is opened by the keyboard').toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(line, 'the first Esc collapses only the row').toHaveAttribute('aria-expanded', 'false');
    await settled(page);
    await expect(button, 'and the drawer stays open').toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(button, 'the second Esc closes the drawer').toHaveAttribute('aria-expanded', 'false');
    await expect(button, 'and focus moves to the Status button').toBeFocused();
    await expect(railOf(page)).toHaveCount(0);

    await button.click();
    await expect(button).toHaveAttribute('aria-expanded', 'true');
    const link = row.locator('app-trace-link a');
    await link.click();
    const help = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(help, 'pressing the Trace link opens the help').toBeVisible();
    await link.focus();
    await expect(link, 'focus is back on the link').toBeFocused();
    await page.keyboard.press('Escape');
    await expect(help, 'Esc closes the help').toHaveCount(0);
    await settled(page);
    await expect(button, 'and only the help: the drawer stays open').toHaveAttribute('aria-expanded', 'true');
    await expect(railOf(page)).toHaveCount(1);

    await button.click();
    await expect(button, 'a press while it is open closes the drawer').toHaveAttribute('aria-expanded', 'false');
    await expect(button, 'with focus on the button').toBeFocused();

    for (const width of [1024, 1279]) {
      await page.setViewportSize({ width, height: 720 });
      await expect(statusButton(page), `at ${width}px the Status button shows`).toHaveCount(1);
    }
    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(statusButton(page), 'at 1280px it does not').toHaveCount(0);
    await expect(railOf(page), 'and the region shows as a column').toHaveCount(1);
    expect(Math.round((await edges(railOf(page))).width)).toBe(288);
  } finally {
    hold?.release();
    await cleanFixtureRows(refs);
  }
});

/** G2, a failed load: the Status button shows "Status" alone, with no pill, so it never shows a zero that it does not know. */
test('G2: after a failed load the Status button shows "Status" alone', async ({ page }) => {
  await page.setViewportSize({ width: 1100, height: 720 });
  await openFloor(page);
  await page.route(`**${STATE}`, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } }));
  await page.reload();
  await expect(mainOf(page), 'the load failed').toHaveAttribute('data-snapshot', 'failed');
  const button = statusButton(page);
  await expect(button, 'the name is "Status" alone').toHaveAccessibleName('Status');
  await expect(button.locator('.count'), 'with no pill').toHaveCount(0);
});

/** G2, the tooltip: a shown tooltip in the drawer takes its Esc first, and the drawer closes with the next one. */
test('G2: a shown tooltip takes its Esc before the drawer, which closes with the next', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await page.setViewportSize({ width: 1100, height: 720 });
    const summary = await seedRow(user, refs, 'G2 tip row');
    await openFloor(page);
    const button = statusButton(page);
    await button.click();
    await expect(button, 'the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await expect(railElement(page), 'with focus on the region').toBeFocused();
    const tooltip = page.locator('app-tooltip');
    await rowOf(page, summary).locator('app-outcome-chip .chip').hover();
    await expect(tooltip, 'the pointer rests on a chip in the drawer and its tooltip shows').toBeVisible();
    await page.keyboard.press('Escape');
    await expect(tooltip, 'the first Esc hides the tooltip').toHaveCount(0);
    await settled(page);
    await expect(button, 'and the drawer stays open').toHaveAttribute('aria-expanded', 'true');
    await expect(railOf(page)).toHaveCount(1);
    await page.mouse.move(0, 0);
    await page.keyboard.press('Escape');
    await expect(button, 'the next Esc closes the drawer').toHaveAttribute('aria-expanded', 'false');
    await expect(button, 'and focus moves to the Status button').toBeFocused();
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** G3: the skip links open a closed drawer; a change of band keeps the focus that is in the rail and starts closed otherwise. */
test('G3: Skip to status opens the drawer, and a change of band keeps focus in the rail', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await page.setViewportSize({ width: 1100, height: 720 });
    const summary = await seedRow(user, refs, 'G3 row');
    await openFloor(page);
    const button = statusButton(page);
    await expect(button).toHaveAttribute('aria-expanded', 'false');
    const home = page.url();
    await page.evaluate(() => history.replaceState(null, '', `${location.pathname}${location.search}#/g3`));
    const address = page.url();
    expect(address, 'the case marks the address, which a followed link would change').not.toBe(home);

    await page.keyboard.press('Tab');
    await page.keyboard.press('Tab');
    await expect(skipLink(page, SKIP_STATUS)).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(button, 'Enter on Skip to status opens the drawer').toHaveAttribute('aria-expanded', 'true');
    await expect(railElement(page), 'and focus is on the region').toBeFocused();
    expectRingInside((await readFocus(page))!, 'the drawer');
    expect(page.url(), 'the address is unchanged').toBe(address);

    await page.keyboard.press('Escape');
    await expect(button, 'Esc closes the drawer').toHaveAttribute('aria-expanded', 'false');
    await expect(button, 'and returns focus to the Status button').toBeFocused();

    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(statusButton(page), 'widened, the Status button leaves with its band').toHaveCount(0);
    await expect(mainOf(page), 'and the focus it held goes to the main region, not to the page').toBeFocused();
    await page.setViewportSize({ width: 1100, height: 720 });
    await expect(button).toHaveAttribute('aria-expanded', 'false');

    await skipLink(page, SKIP_CHAT).focus();
    await page.keyboard.press('Enter');
    await expect(mainOf(page), 'Skip to chat focuses main').toBeFocused();
    await expect(button, 'and the drawer stays closed').toHaveAttribute('aria-expanded', 'false');

    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(statusButton(page)).toHaveCount(0);
    const heading = page.locator('app-status-rail h3.heading').first();
    await heading.focus();
    await expect(heading).toBeFocused();
    await page.setViewportSize({ width: 1100, height: 720 });
    await expect(statusButton(page), 'narrowed with focus in the rail, the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await expect(heading, 'and focus is unchanged').toBeFocused();

    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(statusButton(page)).toHaveCount(0);
    await composerOf(page).focus();
    await expect(composerOf(page)).toBeFocused();
    await page.setViewportSize({ width: 1100, height: 720 });
    await expect(statusButton(page), 'narrowed with focus elsewhere, the drawer starts closed').toHaveAttribute('aria-expanded', 'false');
    await expect(composerOf(page)).toBeFocused();

    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(statusButton(page)).toHaveCount(0);
    await rowOf(page, summary).locator('app-trace-link a').click();
    const help = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(help, 'the help of a rail Trace link is open').toBeVisible();
    await expect(help.locator(':focus'), 'and focus is inside it, outside the rail').toHaveCount(1);
    await page.setViewportSize({ width: 1100, height: 720 });
    await expect(statusButton(page), 'narrowed with the help of a rail trigger open, the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await expect(rowOf(page, summary).locator('app-trace-link a'), 'and the trigger of the help shows').toBeVisible();
    await expect(help.locator(':focus'), 'and focus is still inside the help').toHaveCount(1);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** Opens the scrolling page at 1280x720, reads what the narrow layouts compare against, focuses a rail control, and narrows the window. */
async function narrowFrom1280(page: Page, user: string, refs: string[], narrow: { width: number; height: number }): Promise<{ block: number; link: Locator }> {
  await page.setViewportSize({ width: 1280, height: 720 });
  await seedScrollingPage(user, refs, unique('G4'));
  await openFloor(page);
  const block = (await layers(page)).headerBlock;
  const link = railOf(page).locator('app-trace-link a').first();
  await expect(link, 'the rail has a Trace link').toBeVisible();
  await link.focus();
  await expect(link).toBeFocused();
  await page.setViewportSize(narrow);
  return { block, link };
}

/** The checks of the stacked column that G4 makes at each of its sizes. */
async function expectColumn(page: Page, wideBlock: number, link: Locator): Promise<void> {
  await expect(noteOf(page), 'the narrow-window note shows').toHaveCount(1);
  await expect(page.locator('main.main + section.rail'), 'the rail follows main in the DOM').toHaveCount(1);
  await expect(link, 'a rail control that held focus keeps it when the layout moves the rail').toBeFocused();
  await settled(page);
  const tops = await layers(page);
  expect(tops.mainFirst, 'main precedes the rail in the DOM').toBe(true);
  expect(tops.header, 'the header is at the top').toBe(0);
  expect(tops.slot, 'the banners come after the header').toBeGreaterThan(tops.header);
  expect(tops.note, 'the note comes under the banners').toBeGreaterThanOrEqual(tops.slot);
  expect(tops.main, 'main comes under the note').toBeGreaterThan(tops.note);
  expect(tops.rail, 'and the rail comes under main').toBeGreaterThan(tops.main);

  const width = await page.evaluate(() => document.documentElement.clientWidth);
  expect(Math.abs((await edges(mainOf(page))).width - width), 'main spans the page').toBeLessThanOrEqual(1);
  expect(Math.abs((await edges(railOf(page))).width - width), 'and so does the rail').toBeLessThanOrEqual(1);
  const scroll = await pageScroll(page);
  expect(scroll.across, 'there is no horizontal scroll').toBeLessThanOrEqual(0);
  expect(scroll.overflow, 'the page scrolls').toBeGreaterThan(0);

  await page.evaluate(() => window.scrollTo(0, document.scrollingElement!.scrollHeight));
  await settled(page);
  const after = await layers(page);
  expect(Math.abs(after.header), 'after scrolling to the bottom the header is still at the top').toBeLessThanOrEqual(0.5);
  expect(after.headerBlock, 'and it is shorter than at 1280x720').toBeLessThan(wideBlock);
  const positions = await page.evaluate(() => {
    const sticky: string[] = [];
    const fixed: string[] = [];
    for (const el of Array.from(document.querySelectorAll('*'))) {
      const position = getComputedStyle(el).position;
      const name = `${el.tagName.toLowerCase()}${el.className && typeof el.className === 'string' ? `.${el.className.split(' ')[0]}` : ''}`;
      if (position === 'sticky') sticky.push(name);
      if (position === 'fixed' && !el.classList.contains('skip-link') && !(el.classList.contains('cdk-overlay-container') && el.children.length === 0)) fixed.push(name);
    }
    return { sticky, fixed };
  });
  expect(positions.sticky, 'only the header is sticky').toEqual(['app-header']);
  expect(positions.fixed, 'nothing is fixed but the clipped skip links and the empty overlay container').toEqual([]);
  await page.evaluate(() => window.scrollTo(0, 0));
}

/** G4: below 1024px the page is one column that scrolls as a page, in the order of the page, with only the compact header sticky; widened again, the rail goes back. */
test('G4: at 1000x800 the page is one column with the rail after main, and only the header sticks', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const { block, link } = await narrowFrom1280(page, user, refs, { width: 1000, height: 800 });
    await expectColumn(page, block, link);
    const text = await addReminder(page, user, unique('G4').replace(/ /g, '-'));
    await expect(rowOf(page, text), 'a reminder published after the move shows its row in the region Status').toBeVisible();
    expect(await placeOfFocus(page), 'and the move left focus in the rail').toBe('rail');

    const held = await page.evaluateHandle(() => document.activeElement);
    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(page.locator('section.rail + main.main'), 'widened again, the rail goes back before main in the DOM').toHaveCount(1);
    await expect.poll(() => page.evaluate((el) => el !== null && el === document.activeElement, held), { message: 'and the rail control that held focus keeps it' }).toBe(true);
    const rail = await edges(railOf(page));
    const main = await edges(mainOf(page));
    expect(Math.abs(rail.right - main.left), 'and main starts at the right edge of the rail').toBeLessThanOrEqual(1);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/**
 * G4, an empty chat: the list is as tall as its content (the empty chat's own box, which a stretched list would centre in more space),
 * and shorter than 70% of the window. The case empties the chat and the rail of its snapshot and opens a tall window, so that main has
 * room below the chat whatever rows the floor user holds, and checks that room first. (At 200% the empty chat's content is taller than
 * 70% of the window, and the list scrolls.)
 */
test('G4: below 1024px an empty chat list is as tall as its content', async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 1400 });
  await changeSnapshot(page, (snapshot) => {
    snapshot['chat'] = [];
    const rail = snapshot['rail'] as Record<string, unknown>;
    for (const section of ['approvals', 'checks', 'reminders', 'decisions']) rail[section] = [];
  });
  await openFloor(page);
  await expect(page.locator('main.main + section.rail'), 'the column').toHaveCount(1);
  const sizes = await page.locator('app-chat-panel .list').evaluate((el) => ({
    client: el.clientHeight,
    scroll: el.scrollHeight,
    inner: window.innerHeight,
    content: el.querySelector('app-empty-chat .empty')!.getBoundingClientRect().height,
    main: document.querySelector('main.main')!.clientHeight,
    dock: document.querySelector('app-chat-panel .dock')!.getBoundingClientRect().height,
  }));
  expect(sizes.main - sizes.dock - sizes.content, `main has room below the empty chat, where a list that stretched would grow (main ${sizes.main}px)`).toBeGreaterThan(40);
  expect(sizes.scroll - sizes.client, 'the list holds its whole content').toBeLessThanOrEqual(1);
  expect(Math.abs(sizes.client - sizes.content), `and is no taller than it: the empty chat's ${sizes.content}px, not ${sizes.client}px`).toBeLessThanOrEqual(1);
  expect(sizes.client, 'and is shorter than 70vh').toBeLessThan(0.7 * sizes.inner);
});

test.describe('at 200%: 640x360 at device scale 2', () => {
  test.use({ viewport: { width: 640, height: 360 }, deviceScaleFactor: 2 });

  /** G4 at 200%: the same column, and a chat list that is 70% of the window and scrolls on its own, or as tall as its content when short. */
  test('G4: at 200% the column holds, and the chat list is 70% of the window high', async ({ page }) => {
    test.setTimeout(150_000);
    const { user } = fixtureUser(KIND);
    const refs: string[] = [];
    try {
      const { block, link } = await narrowFrom1280(page, user, refs, { width: 640, height: 360 });
      await expectColumn(page, block, link);
      const list = page.locator('app-chat-panel .list');
      const sizes = await list.evaluate((el) => ({ client: el.clientHeight, scroll: el.scrollHeight, inner: window.innerHeight }));
      expect(Math.abs(sizes.client - 0.7 * sizes.inner), `the list is 70% of the window (${sizes.client} of ${sizes.inner})`).toBeLessThanOrEqual(1);
      expect(sizes.scroll, 'and it scrolls on its own').toBeGreaterThan(sizes.client + 1);
    } finally {
      await cleanFixtureRows(refs);
    }
  });

  /** G5: the keyboard in the column: every ring inside the window and clear of the sticky header, and main before the rail. */
  test('G5: at 200% every ring is inside the window and below the header, and main comes before the rail', async ({ page }) => {
    test.setTimeout(150_000);
    const { user } = fixtureUser(KIND);
    const refs: string[] = [];
    try {
      await seedScrollingPage(user, refs, unique('G5'));
      await openFloor(page);
      await expect(page.locator('main.main + section.rail'), 'the column').toHaveCount(1);
      await settled(page);

      // The skip links show above the header, with nothing painted over them; every other stop must lie below it.
      let seenRail = false;
      const stops = await walk(
        page,
        { ends: (reading, place) => seenRail && (reading === null || place === 'skip') },
        async (reading, place) => {
          if (place === 'rail') seenRail = true;
          if (place === 'skip') {
            const onTop = await page.evaluate(() => {
              const link = document.activeElement!;
              const box = link.getBoundingClientRect();
              const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
              return hit !== null && link.contains(hit);
            });
            expect(onTop, `${reading.what}: it shows above the sticky header`).toBe(true);
          }
          if (place !== 'skip' && place !== 'header') {
            const bottom = await headerBottom(page);
            expect(reading.ring.top, `${reading.what}: its ring lies below the header (${bottom})`).toBeGreaterThanOrEqual(bottom - 0.5);
          }
          if (place === 'main') expect(seenRail, `${reading.what}: no stop of main comes after a stop of the rail`).toBe(false);
        },
      );
      expect(stops.some((one) => one.place === 'main'), 'the walk passed main').toBe(true);
      expect(stops.filter((one) => one.place === 'rail').length, 'and the rail').toBeGreaterThan(12);
      const order = stops.map((one) => one.place).join(',');
      expect(order, 'main comes before the rail').toMatch(/main(,main)*,rail/);

      // Backwards, a stop scrolls to the top edge of the window, where the header would cover it.
      await railOf(page).locator('a[href], button:not([disabled])').last().focus();
      let checked = 0;
      for (let back = 0; back < stops.length; back += 1) {
        await page.keyboard.press('Shift+Tab');
        const reading = (await readFocus(page))!;
        expect(reading, `Shift+Tab ${back + 1} lands on an element`).not.toBeNull();
        const place = await placeOfFocus(page);
        if (place === 'skip' || place === 'header') break;
        const bottom = await headerBottom(page);
        expect(reading.ring.top, `${reading.what}: going back, its ring lies below the header (${bottom})`).toBeGreaterThanOrEqual(bottom - 0.5);
        expectRingInside(reading, reading.what);
        checked += 1;
      }
      expect(checked, 'going back, the walk read every stop of the rail').toBeGreaterThan(12);
    } finally {
      await cleanFixtureRows(refs);
    }
  });

  test('G5: at 200% the skip links bring each region below the header, and About opens inside the window and scrolls', async ({ page }) => {
    const { user } = fixtureUser(KIND);
    const refs: string[] = [];
    try {
      await seedScrollingPage(user, refs, unique('G5b'));
      await openFloor(page);
      await settled(page);
      const measured = await page.evaluate(() => ({
        property: document.documentElement.style.getPropertyValue('--app-header-block-size'),
        height: document.querySelector('app-header')!.getBoundingClientRect().height,
      }));
      expect(Math.abs(parseFloat(measured.property) - measured.height), `the header writes its measured block size to the root (${measured.property} against ${measured.height})`).toBeLessThanOrEqual(0.5);
      const target = async (name: string, region: Locator): Promise<void> => {
        await skipLink(page, name).focus();
        await page.keyboard.press('Enter');
        await expect(region, `${name} focuses its region`).toBeFocused();
        await settled(page);
        const reading = (await readFocus(page))!;
        const bottom = await headerBottom(page);
        expect(reading.ring.top, `${name}: the ring lies below the header (${bottom})`).toBeGreaterThanOrEqual(bottom - 0.5);
        expect(reading.ring.left, `${name}: and inside the window on the left`).toBeGreaterThanOrEqual(-0.5);
        expect(reading.ring.right, `${name}: and on the right`).toBeLessThanOrEqual(reading.viewport.right + 0.5);
        const scrolled = await page.evaluate(() => window.scrollY);
        expect(reading.ring.top, `${name}: and its top is inside the window (${reading.viewport.bottom}; the page is scrolled to ${scrolled})`).toBeLessThan(reading.viewport.bottom);
      };
      await target(SKIP_STATUS, railElement(page));
      await target(SKIP_CHAT, mainOf(page));

      const account = page.locator('app-header button.header-button').last();
      await account.click();
      await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
      const about = page.locator('app-about-dialog');
      await expect(about).toBeVisible();
      const seen = await about.evaluate((el) => {
        const box = el.getBoundingClientRect();
        const paragraphs = el.querySelectorAll('p');
        paragraphs[paragraphs.length - 1]!.scrollIntoView({ block: 'nearest' });
        const last = paragraphs[paragraphs.length - 1]!.getBoundingClientRect();
        return {
          top: box.top,
          left: box.left,
          right: box.right,
          bottom: box.bottom,
          width: window.innerWidth,
          height: window.innerHeight,
          overflow: getComputedStyle(el).overflowY,
          lastBottom: last.bottom,
          lastTop: last.top,
        };
      });
      expect(seen.top, 'About opens inside the window').toBeGreaterThanOrEqual(-0.5);
      expect(seen.left).toBeGreaterThanOrEqual(-0.5);
      expect(seen.right).toBeLessThanOrEqual(seen.width + 0.5);
      expect(seen.bottom).toBeLessThanOrEqual(seen.height + 0.5);
      expect(seen.overflow, 'it scrolls when it is taller than the window allows').toBe('auto');
      expect(seen.lastBottom, 'and its last paragraph can be scrolled into view, inside the window').toBeLessThanOrEqual(Math.min(seen.bottom, seen.height) + 0.5);
      expect(seen.lastTop).toBeGreaterThanOrEqual(-0.5);
      await page.keyboard.press('Escape');
      await expect(about, 'Esc closes it').toHaveCount(0);
      await expect(account, 'and focus returns to the account button').toBeFocused();
    } finally {
      await cleanFixtureRows(refs);
    }
  });
});

/** G6: the note shows once per session in the stacked layout, silent at load, and its Close is remembered for the browser. */
test('G6: the note shows once per session, is silent at load, and its Close is remembered for the browser', async ({ page }) => {
  await recordAnnouncements(page);
  await page.setViewportSize({ width: 1000, height: 800 });
  await openFloor(page);
  const note = noteOf(page);
  await expect(note, 'on the first load the note shows').toHaveCount(1);
  await expect(note).toHaveText(NOTE);
  await expect(note.locator('svg').first(), 'its icon is hidden from assistive technology').toHaveAttribute('aria-hidden', 'true');
  await expect(note.getByRole('button', { name: NOTE_CLOSE, exact: true }), 'its Close is named').toHaveCount(1);
  const tops = await layers(page);
  expect(tops.note, 'it sits under the banners').toBeGreaterThanOrEqual(tops.slot);
  expect(tops.note, 'and above main').toBeLessThan(tops.main);
  await settled(page);
  await page.waitForTimeout(1_500);
  expect(await announcements(page, NOTE), `nothing announced holds its text (${JSON.stringify(await announcedTexts(page))})`).toBe(0);

  await page.setViewportSize({ width: 1280, height: 720 });
  await expect(note, 'at 1280px the note is gone').toHaveCount(0);
  await page.setViewportSize({ width: 1000, height: 800 });
  await expect(page.locator('main.main + section.rail')).toHaveCount(1);
  await settled(page);
  await expect(note, 'narrowed again in the same session it does not come back').toHaveCount(0);
  await page.reload();
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await settled(page);
  await expect(noteOf(page), 'a reload in the same tab shows none').toHaveCount(0);

  const second = await page.context().newPage();
  try {
    await second.setViewportSize({ width: 1000, height: 800 });
    await second.goto('/ocutalon/');
    await expect(mainOf(second)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(noteOf(second), 'a new tab session shows the note').toHaveCount(1);
    await noteOf(second).getByRole('button', { name: NOTE_CLOSE, exact: true }).click();
    await expect(noteOf(second), 'Close takes it away').toHaveCount(0);
    await expect(mainOf(second), 'and focus is on the main region').toBeFocused();
  } finally {
    await second.close();
  }

  const third = await page.context().newPage();
  try {
    await third.setViewportSize({ width: 1000, height: 800 });
    await third.goto('/ocutalon/');
    await expect(mainOf(third)).toHaveAttribute('data-snapshot', 'loaded');
    await settled(third);
    await expect(noteOf(third), 'a closed note is closed for the browser').toHaveCount(0);
  } finally {
    await third.close();
  }
});

/** G7: a note that appears after load is announced once; a storage that fails still gives a note that shows and closes. */
test('G7: a note that appears later is announced once', async ({ page }) => {
  await recordAnnouncements(page);
  await page.setViewportSize({ width: 1280, height: 720 });
  await openFloor(page);
  await expect(noteOf(page), 'at 1280px there is no note').toHaveCount(0);
  await page.setViewportSize({ width: 1000, height: 800 });
  await expect(noteOf(page), 'narrowed, the note appears').toHaveCount(1);
  await expect.poll(() => announcements(page, NOTE), { message: 'its text is announced', timeout: CARD_MS }).toBe(1);
  await page.waitForTimeout(1_500);
  expect(await announcements(page, NOTE), 'and once').toBe(1);
});

/** G7, the failing storage: the note shows once, closes for the page, and the console holds no error. */
test('G7: with a storage that throws the note still shows, closes, and the page logs no error', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error' && !/Failed to load resource/.test(message.text())) errors.push(message.text());
  });
  page.on('pageerror', (error) => errors.push(String(error)));
  await page.addInitScript(() => {
    const fail = (): never => {
      throw new Error('storage is blocked');
    };
    Storage.prototype.getItem = fail;
    Storage.prototype.setItem = fail;
  });
  await page.setViewportSize({ width: 1000, height: 800 });
  await openFloor(page);
  const note = noteOf(page);
  await expect(note, 'the note shows').toHaveCount(1);
  await note.getByRole('button', { name: NOTE_CLOSE, exact: true }).click();
  await expect(note, 'Close takes it away').toHaveCount(0);
  await expect(composerOf(page), 'the composer is visible').toBeVisible();
  await settled(page);
  expect(errors, 'the console holds no error').toEqual([]);
});
