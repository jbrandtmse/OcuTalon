import { expect, test, type Locator, type Page } from '@playwright/test';

import { changeSnapshot } from '../support/api';
import { dropPhone, publishMailbox } from '../support/devices';
import {
  CARD_MS,
  SKIP_DEVICES,
  applied,
  expectRingInside,
  expectStopRing,
  mainOf,
  openFloor,
  readFocus,
  seedRow,
  settled,
  skipLink,
  stepKeys,
  unique,
} from '../support/floor';
import { cleanFixtureRows, fixtureUser, sendNotification } from '../support/iris';
import { fromBottom, scrollListTo } from '../support/page';

/**
 * Story 4.5, the simulated device panel and the simulated phone on the floor stack, as the FLOOR user (D1 to D6; the floor stack is in
 * demo mode). D1 runs in all three engines (tag @browsers): the tab stops of the panel in order, the arrow keys and the rings inside the
 * viewport at 1280x720 and 1280x600. D2 reads the layout: 384px from 1440px and 352px below it, the column under the Break the feed
 * box, the drawer band, the stacked order and the short windows, where the phone screen yields to the column. D3 sends real
 * notifications through Notify and SimPhoneOut and reads the phone: the feed follows at the bottom and holds when scrolled up, New
 * messages focuses the first new message, and an unselected tab shows a badge with its count and is never switched by content. D4
 * holds the feed for a pending approval request that a message names. D5 and D5b hold an arrival in the 1280x600 window: New messages
 * is the tab stop after the feed and Enter on it focuses the first new message (D5), and the button is in view of the panel body and
 * the window (D5b). D6 runs in all three engines too (tag @browsers): it lands an announcement and holds that the live region adds no
 * height, so the document does not scroll at 1280x600 and 1280x480 and the announcer's element is a clipped pixel out of the flow. A
 * case that sends removes the FLOOR session's phone and web rows from its start (dropPhone) in finally; the FLOOR session is no fixture
 * session, so Fixture.Clean keeps them. The fixture messages of D2, D4 and D5 are named by their text and live only in the snapshot
 * that the page receives.
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll or a snapshot that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';
const PHONE_TAB = 'Simulated phone';
const MAILBOX_TAB = 'Simulated mailbox';

const regionOf = (page: Page): Locator => page.locator('app-device-panel section');
const tabOf = (page: Page, name: string): Locator => regionOf(page).getByRole('tab', { name, exact: true });
const phoneOf = (page: Page): Locator => page.locator('app-simulated-phone');
const feedOf = (page: Page): Locator => page.locator('app-simulated-phone .feed');
const messageOf = (page: Page, text: string): Locator => page.locator('app-simulated-phone .notification').filter({ hasText: text });
const newMessagesOf = (page: Page): Locator => phoneOf(page).getByRole('button', { name: 'New messages', exact: true });

/** The UTC time to the second, a little before now, as dropPhone wants it. */
const startTime = (): string => new Date(Date.now() - 2000).toISOString().replace(/\.\d{3}Z$/, 'Z');

/** A fixture message of the snapshot's phone, named as one by its ref. */
const fixture = (n: number, text: string, approvalRef = ''): Record<string, unknown> => ({
  ref: `zzfixture${String(n).padStart(2, '0')}`,
  direction: 'out',
  text,
  approvalRef,
  createdAt: `2030-01-01T10:${String(n).padStart(2, '0')}:00Z`,
});

/** Answers /state with this phone. */
async function withPhone(page: Page, phone: Array<Record<string, unknown>>, approvalRef?: string): Promise<void> {
  await changeSnapshot(page, (snapshot) => {
    snapshot['phone'] = phone;
    if (approvalRef !== undefined) {
      const rail = snapshot['rail'] as { approvals: unknown[] };
      rail.approvals.push({ ref: approvalRef, kind: 'tool_call', state: 'pending', toolName: 'zz_fixture_tool', raisedAt: '2030-01-01T10:00:00Z', expiresAt: '2030-01-02T10:00:00Z' });
    }
  });
}

/** Sends a tell-now notification of the text to the FLOOR session through Notify, and waits for it on the phone. */
async function arrive(page: Page, user: string, text: string): Promise<void> {
  await sendNotification(user, { kind: 'tellnow', catalogKey: 'notice.tellNow', slots: { whatHappened: text, reason: 'zz D3 reason' } });
  await expect(messageOf(page, text), `${text} reaches the phone`).toHaveCount(1, { timeout: CARD_MS });
}

/**
 * D1: the stops of the panel in order, the arrow keys, and every ring inside the viewport, at two heights. At 1280x600 the column is
 * shorter than the phone's minimum, so the screen yields to it and the feed's ring is still wholly inside the viewport and every scroller.
 */
test('D1: the device tabs and the phone feed are tab stops in order, the arrows move between the tabs, and every ring is inside the viewport', { tag: '@browsers' }, async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await openFloor(page);
  await expect(regionOf(page)).toHaveCount(1);
  for (const height of [720, 600]) {
    await page.setViewportSize({ width: 1280, height });
    await settled(page);
    const keys = await stepKeys(page);
    const box = (await page.locator('app-device-panel').boundingBox())!;
    expect(box.y + box.height, `the panel ends inside the ${height}px window`).toBeLessThanOrEqual(height + 0.5);
    expect(box.x + box.width, 'and at its right edge').toBeLessThanOrEqual(1280.5);

    const send = page.locator('app-composer button');
    await send.focus();
    await expect(send).toBeFocused();
    await page.keyboard.press(keys.next);
    await expect(tabOf(page, PHONE_TAB), `the stop after the chat is the phone tab (${height})`).toBeFocused();
    await expectStopRing(page, (await readFocus(page))!);
    await page.keyboard.press(keys.next);
    await expect(feedOf(page), 'then the phone feed, which is the region named by its tab').toBeFocused();
    await expect(feedOf(page)).toHaveAttribute('role', 'region');
    await expect(page.getByRole('region', { name: PHONE_TAB, exact: true }), 'it is named by the tab').toHaveCount(1);
    await expectStopRing(page, (await readFocus(page))!);
    await page.keyboard.press(keys.back);
    await expect(tabOf(page, PHONE_TAB)).toBeFocused();

    await page.keyboard.press('ArrowRight');
    await expect(tabOf(page, MAILBOX_TAB), 'ArrowRight moves focus to the other tab').toBeFocused();
    await expect(tabOf(page, MAILBOX_TAB), 'and selects it').toHaveAttribute('aria-selected', 'true');
    expectRingInside((await readFocus(page))!, 'the mailbox tab');
    await page.keyboard.press(keys.next);
    await expect(page.locator('app-device-panel .mailbox'), 'the next stop is the mailbox panel, which has no focusable content').toBeFocused();
    await expectStopRing(page, (await readFocus(page))!);
    await page.keyboard.press(keys.back);
    await expect(tabOf(page, MAILBOX_TAB)).toBeFocused();
    await page.keyboard.press('ArrowLeft');
    await expect(tabOf(page, PHONE_TAB), 'ArrowLeft moves back').toBeFocused();
    await expect(tabOf(page, PHONE_TAB)).toHaveAttribute('aria-selected', 'true');
    await skipLink(page, SKIP_DEVICES).focus();
    await page.keyboard.press('Enter');
    await expect(regionOf(page), 'the skip link focuses the region').toBeFocused();
    await expectStopRing(page, (await readFocus(page))!);
  }
});

/** The left edges and widths of the panel and the Break the feed box's column, and the viewport width. */
function columns(page: Page): Promise<{ panelLeft: number; panelWidth: number; panelRight: number; boxLeft: number; width: number }> {
  return page.evaluate(() => {
    const panel = document.querySelector('app-device-panel')!.getBoundingClientRect();
    const box = document.querySelector('app-break-feed-box')!.getBoundingClientRect();
    return { panelLeft: panel.left, panelWidth: panel.width, panelRight: panel.right, boxLeft: box.left, width: document.documentElement.clientWidth };
  });
}

/** D2: the layout at every width: the column's width and place, the drawer band, the stacked order, and the short windows. */
test('D2: the panel is 384px from 1440px and 352px below it, aligned under the box, stacked below 1024px, and the phone yields to a short column', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await seedRow(user, refs, 'D2 row');
    await layoutCase(page);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** The body of D2, after its rail row is seeded. */
async function layoutCase(page: Page): Promise<void> {
  await withPhone(page, Array.from({ length: 12 }, (_unused, n) => fixture(n + 1, `zz D2 fixture message ${n + 1}\nWhy now: zz fixture`)));

  await page.setViewportSize({ width: 1440, height: 900 });
  await openFloor(page);
  await expect(phoneOf(page).locator('.notification')).toHaveCount(12);
  let c = await columns(page);
  expect(c.panelWidth, 'at 1440px the panel is 384px wide').toBeCloseTo(384, 0);
  expect(c.panelRight, 'at the right edge of the window').toBeCloseTo(c.width, 0);
  expect(Math.abs(c.panelLeft - c.boxLeft), 'under the left edge of the Break the feed box').toBeLessThanOrEqual(1);

  await page.setViewportSize({ width: 1280, height: 720 });
  await settled(page);
  c = await columns(page);
  expect(c.panelWidth, 'at 1280px it is 352px').toBeCloseTo(352, 0);
  expect(Math.abs(c.panelLeft - c.boxLeft), 'still under the box').toBeLessThanOrEqual(1);
  const main = (await mainOf(page).boundingBox())!;
  expect(main.x + main.width, 'main ends where the panel starts').toBeCloseTo(c.panelLeft, 0);
  const screen = await page.locator('app-simulated-phone .screen').evaluate((el) => ({ width: el.clientWidth, height: el.clientHeight }));
  expect(screen.width, 'the phone screen keeps its width').toBeCloseTo(296, 0);
  expect(screen.height, 'and is at least its minimum high').toBeGreaterThanOrEqual(359.5);

  await page.setViewportSize({ width: 1100, height: 720 });
  await settled(page);
  c = await columns(page);
  expect(c.panelWidth, 'in the drawer band the panel is 352px').toBeCloseTo(352, 0);
  expect(Math.abs(c.panelLeft - c.boxLeft), 'under the box').toBeLessThanOrEqual(1);
  await expect(page.locator('section.rail'), 'with the rail in its closed drawer').toBeHidden();

  await page.setViewportSize({ width: 1000, height: 800 });
  await settled(page);
  await expect(page.locator('main.main + app-device-panel + section.rail'), 'stacked: main, the devices, the rail').toHaveCount(1);
  c = await columns(page);
  expect(c.panelWidth, 'the panel spans the page').toBeCloseTo(c.width, 0);
  const placed = await page.evaluate(() => {
    const frame = document.querySelector('app-simulated-phone .frame')!.getBoundingClientRect();
    const panel = document.querySelector('app-device-panel section')!.getBoundingClientRect();
    const screen = document.querySelector('app-simulated-phone .screen') as HTMLElement;
    const feed = document.querySelector('app-simulated-phone .feed') as HTMLElement;
    return { off: Math.abs(frame.left + frame.width / 2 - (panel.left + panel.width / 2)), screen: screen.clientHeight, feedScrolls: feed.scrollHeight - feed.clientHeight };
  });
  expect(placed.off, 'the phone is centred').toBeLessThanOrEqual(1);
  expect(placed.screen, 'its screen is at least the minimum high').toBeGreaterThanOrEqual(359.5);
  expect(placed.feedScrolls, 'and its feed scrolls').toBeGreaterThan(40);
  const keys = await stepKeys(page);
  await page.locator('app-composer button').focus();
  const places: string[] = [];
  for (let i = 0; i < 8; i += 1) {
    await page.keyboard.press(keys.next);
    const place = await page.evaluate(() => (document.activeElement?.closest('app-device-panel') ? 'devices' : document.activeElement?.closest('section.rail') ? 'rail' : 'other'));
    places.push(place);
    if (place === 'rail') break;
  }
  expect(places.join(','), 'the tab order after the chat is the devices, then the rail').toMatch(/^devices(,devices)*,rail$/);

  await page.setViewportSize({ width: 1280, height: 600 });
  await settled(page);
  const short = await page.evaluate(() => {
    const root = document.scrollingElement!;
    const panel = document.querySelector('app-device-panel')!.getBoundingClientRect();
    const body = document.querySelector('app-device-panel .body') as HTMLElement;
    return { page: root.scrollHeight - root.clientHeight, bottom: panel.bottom, overflowY: getComputedStyle(body).overflowY, height: window.innerHeight };
  });
  expect(short.page, 'at 1280x600 the page does not scroll').toBeLessThanOrEqual(0);
  expect(short.bottom, 'the panel ends inside the window').toBeLessThanOrEqual(short.height + 0.5);
  expect(short.overflowY, 'and the panel body scrolls on its own').toBe('auto');
  for (const height of [600, 480]) {
    await page.setViewportSize({ width: 1280, height });
    await settled(page);
    const fit = await page.evaluate(() => {
      const root = document.scrollingElement!;
      const body = document.querySelector('app-device-panel .body') as HTMLElement;
      const view = body.getBoundingClientRect();
      const screen = document.querySelector('app-simulated-phone .screen')!.getBoundingClientRect();
      const feed = document.querySelector('app-simulated-phone .feed') as HTMLElement;
      return {
        page: root.scrollHeight - root.clientHeight,
        bodyScrolls: body.scrollHeight - body.clientHeight,
        screen: screen.height,
        screenBottom: screen.bottom,
        bodyBottom: view.top + body.clientTop + body.clientHeight,
        feedScrolls: feed.scrollHeight - feed.clientHeight,
      };
    });
    expect(fit.page, `in a window of ${height}px high the page does not scroll`).toBeLessThanOrEqual(0);
    expect(fit.screen, `the column is shorter than the phone, so its screen yields to it (${JSON.stringify(fit)})`).toBeLessThan(359.5);
    expect(fit.bodyScrolls, 'and the panel body holds nothing that it does not show').toBeLessThanOrEqual(1);
    expect(fit.screenBottom, 'the screen ends inside the panel body').toBeLessThanOrEqual(fit.bodyBottom + 0.5);
    expect(fit.feedScrolls, 'and its feed scrolls inside it').toBeGreaterThan(0);
  }
}

/** D3: real notifications reach the phone: the feed follows at the bottom, holds when scrolled up, and a tab with new content gets a badge. */
test('D3: the feed follows at the bottom and holds when scrolled up, and an unselected tab shows a badge and is never switched', async ({ page }) => {
  test.setTimeout(240_000);
  const { user } = fixtureUser(KIND);
  const start = startTime();
  try {
    await page.setViewportSize({ width: 1280, height: 720 });
    await openFloor(page);
    for (let i = 0; i < 8; i += 1) await arrive(page, user, unique(`D3 fill ${i}`));
    const feed = feedOf(page);
    await expect.poll(() => feed.evaluate((el) => el.scrollHeight - el.clientHeight), { message: 'the feed holds more than it shows' }).toBeGreaterThan(40);
    await expect.poll(() => fromBottom(feed), { message: 'at the bottom, new messages scroll into view' }).toBeLessThanOrEqual(24);
    const followed = unique('D3 followed');
    await arrive(page, user, followed);
    await expect.poll(() => fromBottom(feed), { message: 'the newest message is in view' }).toBeLessThanOrEqual(24);
    await expect(newMessagesOf(page), 'with no New messages button').toHaveCount(0);
    await expect(tabOf(page, PHONE_TAB), 'the selected phone tab gets no count from what arrives on it').toHaveAttribute('aria-selected', 'true');
    await expect(regionOf(page).locator('.badge'), 'and no badge').toHaveCount(0);

    await scrollListTo(feed, 'top');
    const held = unique('D3 held');
    await arrive(page, user, held);
    await settled(page);
    expect(await feed.evaluate((el) => el.scrollTop), 'scrolled up, the feed does not move').toBe(0);
    await expect(newMessagesOf(page), 'and New messages shows').toBeVisible();
    await newMessagesOf(page).click();
    await expect.poll(() => fromBottom(feed), { message: 'pressing it scrolls to the bottom' }).toBeLessThanOrEqual(24);
    await expect(messageOf(page, held), 'and focuses the first new message').toBeFocused();
    await expect(newMessagesOf(page), 'the button goes').toHaveCount(0);

    await tabOf(page, MAILBOX_TAB).click();
    await expect(tabOf(page, MAILBOX_TAB)).toHaveAttribute('aria-selected', 'true');
    const badged = unique('D3 badged');
    await arrive(page, user, badged);
    await expect(tabOf(page, `${PHONE_TAB}, 1 new`), 'the unselected phone tab has the count in its name').toBeVisible();
    await expect(tabOf(page, `${PHONE_TAB}, 1 new`).locator('.badge'), 'and the badge').toHaveText('1');
    await expect(tabOf(page, MAILBOX_TAB), 'the mailbox stays selected').toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#device-panel-phone'), 'and the phone stays hidden').toBeHidden();
    await tabOf(page, `${PHONE_TAB}, 1 new`).click();
    await expect(tabOf(page, PHONE_TAB), 'selecting the tab clears the badge').toBeVisible();
    await expect(regionOf(page).locator('.badge')).toHaveCount(0);

    await tabOf(page, MAILBOX_TAB).click();
    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(tabOf(page, MAILBOX_TAB), 'after a reload the mailbox is still selected').toHaveAttribute('aria-selected', 'true');
    await expect(tabOf(page, PHONE_TAB), 'and what the snapshot holds is no news: the phone tab has no badge').toBeVisible();
    await tabOf(page, PHONE_TAB).click();

    const first = await publishMailbox(user, `zzmail${Date.now().toString(36)}a`);
    const second = await publishMailbox(user, `zzmail${Date.now().toString(36)}b`);
    await applied(page, Math.max(first, second));
    await expect(tabOf(page, `${MAILBOX_TAB}, 2 new`), 'two mailbox events give the mailbox tab its count').toBeVisible();
    await expect(tabOf(page, PHONE_TAB), 'the phone stays selected').toHaveAttribute('aria-selected', 'true');
    await tabOf(page, `${MAILBOX_TAB}, 2 new`).click();
    await expect(tabOf(page, MAILBOX_TAB), 'selecting it clears its badge').toBeVisible();
  } finally {
    await dropPhone(user, start);
  }
});

/** D4: a message that names a pending approval request holds the feed: a later arrival does not move it, and New messages shows. */
test('D4: with a pending approval request on the phone, an arrival does not move the feed and shows New messages', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const start = startTime();
  const approval = `zzd4approval${Date.now().toString(36)}`;
  try {
    await withPhone(
      page,
      [...Array.from({ length: 8 }, (_unused, n) => fixture(n + 1, `zz D4 fixture message ${n + 1}\nWhy now: zz fixture`)), fixture(9, 'zz D4 fixture approval request', approval)],
      approval,
    );
    await page.setViewportSize({ width: 1280, height: 720 });
    await openFloor(page);
    const feed = feedOf(page);
    await expect(phoneOf(page).locator('.notification')).toHaveCount(9);
    await expect.poll(() => fromBottom(feed), { message: 'the feed starts at the bottom' }).toBeLessThanOrEqual(24);
    const before = await feed.evaluate((el) => el.scrollTop);
    const text = unique('D4 arrival');
    await arrive(page, user, text);
    await settled(page);
    expect(await feed.evaluate((el) => el.scrollTop), 'the feed does not move for an arrival').toBe(before);
    expect(await fromBottom(feed), 'so the new message is below the view').toBeGreaterThan(24);
    await expect(newMessagesOf(page), 'and New messages shows').toBeVisible();
    await newMessagesOf(page).click();
    await expect(messageOf(page, text), 'it focuses the arrival').toBeFocused();
    await expect(regionOf(page).locator('[aria-live], [role="status"], [role="alert"], [role="log"]'), 'nothing in the region is a live region').toHaveCount(0);
  } finally {
    await dropPhone(user, start);
  }
});

/**
 * Holds a short window (1280x600, where the column is shorter than the phone's minimum and its screen yields to the panel body) with a
 * held arrival: the feed is scrolled up, so the next real arrival shows New messages. `check` reads the page at that point.
 */
async function heldInShortWindow(page: Page, label: string, check: (text: string) => Promise<void>): Promise<void> {
  const { user } = fixtureUser(KIND);
  const start = startTime();
  try {
    await withPhone(page, Array.from({ length: 12 }, (_unused, n) => fixture(n + 1, `zz ${label} fixture message ${n + 1}\nWhy now: zz fixture`)));
    await page.setViewportSize({ width: 1280, height: 600 });
    await openFloor(page);
    const feed = feedOf(page);
    await expect(phoneOf(page).locator('.notification')).toHaveCount(12);
    await scrollListTo(feed, 'top');
    const text = unique(`${label} arrival`);
    await arrive(page, user, text);
    await settled(page);
    await expect(newMessagesOf(page), 'the held arrival shows New messages').toBeVisible();
    await check(text);
  } finally {
    await dropPhone(user, start);
  }
}

/**
 * D5: in a window shorter than the phone, New messages is the tab stop after the feed, its ring is inside the viewport and the panel
 * body's view, and Enter on it focuses the first new message.
 */
test('D5: in a short window New messages is the tab stop after the feed and Enter focuses the first new message', async ({ page }) => {
  test.setTimeout(150_000);
  await heldInShortWindow(page, 'D5', async (text) => {
    const keys = await stepKeys(page);
    await feedOf(page).focus();
    await expect(feedOf(page)).toBeFocused();
    await page.keyboard.press(keys.next);
    await expect(newMessagesOf(page), 'the stop after the feed is New messages').toBeFocused();
    expectRingInside((await readFocus(page))!, 'New messages');
    await page.keyboard.press('Enter');
    await expect(messageOf(page, text), 'Enter focuses the first new message').toBeFocused();
    await expect(newMessagesOf(page), 'and the button goes').toHaveCount(0);
  });
});

/**
 * D5b: at 1280x600 the column is shorter than the phone's 360px minimum, so the phone's screen yields to the panel body's height and
 * New messages sits at the screen's visible bottom: a pointer user who has scrolled up sees the button for a held arrival without
 * scrolling the panel (EXPERIENCE L265 and L301, row 15).
 */
test('D5b: in a short window the New messages button is in view without scrolling the panel', async ({ page }) => {
  test.setTimeout(150_000);
  await heldInShortWindow(page, 'D5b', async () => {
    const seen = await newMessagesOf(page).evaluate((el) => {
      const rect = el.getBoundingClientRect();
      const body = document.querySelector('app-device-panel .body') as HTMLElement;
      const box = body.getBoundingClientRect();
      return { top: rect.top, bottom: rect.bottom, bodyTop: box.top + body.clientTop, bodyBottom: box.top + body.clientTop + body.clientHeight, height: window.innerHeight };
    });
    expect(seen.top, `the button is not above the panel body's view (${JSON.stringify(seen)})`).toBeGreaterThanOrEqual(seen.bodyTop - 0.5);
    expect(seen.bottom, `nor below it, where the panel body clips it (${JSON.stringify(seen)})`).toBeLessThanOrEqual(seen.bodyBottom + 0.5);
    expect(seen.bottom, 'and it is inside the window').toBeLessThanOrEqual(seen.height + 0.5);
  });
});

/**
 * D6: once an announcement has landed, the live region adds no height to the page: at 1280x600 and 1280x480 the document does not
 * scroll, and the announcer's element is visually hidden (a pixel, clipped).
 */
test('D6: after an announcement the page does not scroll in a short window, and the live region is visually hidden', { tag: '@browsers' }, async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const start = startTime();
  try {
    await page.setViewportSize({ width: 1280, height: 720 });
    await openFloor(page);
    await arrive(page, user, unique('D6 arrival'));
    const announcer = page.locator('.cdk-live-announcer-element');
    await expect(announcer, 'the announcement landed in the one live region').toHaveText(/\S/, { timeout: CARD_MS });
    for (const height of [600, 480]) {
      await page.setViewportSize({ width: 1280, height });
      await settled(page);
      const seen = await announcer.evaluate((el) => {
        const root = document.documentElement;
        const style = getComputedStyle(el);
        const box = el.getBoundingClientRect();
        return { scrolls: root.scrollHeight - root.clientHeight, width: box.width, height: box.height, position: style.position, clip: style.clip, overflow: style.overflow };
      });
      expect(seen.scrolls, `at 1280x${height} the document does not scroll (${JSON.stringify(seen)})`).toBeLessThanOrEqual(0);
      expect(seen.width, 'the announcer is a pixel wide').toBeLessThanOrEqual(1);
      expect(seen.height, 'and a pixel high').toBeLessThanOrEqual(1);
      expect(seen.position, 'out of the flow').toBe('absolute');
      expect(seen.clip.replace(/,/g, ''), 'and clipped').toBe('rect(0px 0px 0px 0px)');
      expect(seen.overflow, 'its overflow hidden').toBe('hidden');
    }
  } finally {
    await dropPhone(user, start);
  }
});
