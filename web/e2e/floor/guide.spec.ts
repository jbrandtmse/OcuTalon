import { expect, test, type Locator, type Page } from '@playwright/test';

import { announcements, announcedTexts, recordAnnouncements } from '../support/page';
import { CARD_MS, MOST_STOPS, SKIP_CHAT, composerOf, expectStopRing, mainOf, openFloor, railOf, readFocus, settled, skipLink, stepKeys } from '../support/floor';
import { dropBreakFeed, ORDERS, publishWatchProgress, settleBatch } from '../support/guide';
import { cleanFixtureRows, fixtureUser, publishCheck, publishReminder, seedCheck, seedReminder } from '../support/iris';

/**
 * Story 4.4, the demo guide and the Break the feed box on the floor stack, as the FLOOR user (M1 to M5; the floor stack is in demo mode).
 * M1 and M2 run in all three engines (tag @browsers): the keyboard, the names, aria-current, Enter, the rings inside the viewport, the
 * inactive box that stays focusable and described, Hide and Show with their aria-expanded and focus. M3 and M4 read the real guide.state
 * and the real POST /v1/demo/break-feed: the check and the reminder of the Orders watch advance the page to step 2 and step 3, and a real
 * press runs from step 3 to its sent line. M5 reads the layout at 1280x600, 1100x720 and 1000x800 and the collapsed bar.
 * A case removes the check and the reminder it seeds with cleanFixtureRows, and M4 the run and the batch of 50 orders as well (the FLOOR
 * session is no fixture session, so Fixture.Clean keeps its run rows, and a run under 180 s old would show in the next case's guide).
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll, a snapshot or a post that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';
const BREAK_FEED = '**/ocutalon/api/v1/demo/break-feed';

const P1 = 'Watch the Orders production and only tell me if something needs me.';
const P2 = 'Remind me in 1 minute to stretch.';
const H1 = 'Ask OcuTalon to watch the Orders production first (step 1).';
const SENT = 'Sent. OcuTalon usually notices within a minute.';
const SENDING = 'Sending 50 orders\u2026';
const NOTICED = 'OcuTalon noticed failures in the Orders production';
const LABELS = ['Watch', 'Reminder', 'Break the feed', 'Approve', 'Open the trace'];

const guideOf = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const stepOf = (page: Page, n: number, state: 'current' | 'done' | 'upcoming'): Locator =>
  guideOf(page).getByRole('button', { name: `Step ${n}, ${LABELS[n - 1]}, ${state}`, exact: true });
const sendOf = (page: Page): Locator => guideOf(page).locator('.prompt').getByRole('button', { name: 'Send', exact: true });
const breakOf = (page: Page): Locator => guideOf(page).getByRole('button', { name: 'Break the feed', exact: true });
const boxOf = (page: Page): Locator => page.locator('app-break-feed-box');
const hideOf = (page: Page): Locator => guideOf(page).getByRole('button', { name: 'Hide guide', exact: true });
const showOf = (page: Page): Locator => guideOf(page).getByRole('button', { name: 'Show guide', exact: true });

/** The ring and the name of every tab stop inside the demo guide, from the first skip link until focus leaves it, each judged by expectStopRing. */
async function guideStops(page: Page): Promise<string[]> {
  const keys = await stepKeys(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await skipLink(page, SKIP_CHAT).focus();
  const stops: string[] = [];
  let inside = false;
  for (let i = 0; i < MOST_STOPS; i += 1) {
    await page.keyboard.press(keys.next);
    const reading = await readFocus(page);
    expect(reading, `Tab ${i + 1} lands on an element`).not.toBeNull();
    const here = await page.evaluate(() => document.activeElement?.closest('app-demo-guide') !== null && document.activeElement?.closest('app-demo-guide') !== undefined);
    if (here) {
      inside = true;
      await expectStopRing(page, reading!);
      stops.push(reading!.what);
    } else if (inside) {
      return stops;
    }
  }
  throw new Error(`the walk did not leave the demo guide within ${MOST_STOPS} Tab stops: ${stops.join(' | ')}`);
}

/** M1: the guide by keyboard: the stops, their names and aria-current, Enter selecting a step, and the rings inside the viewport at two heights. */
test('M1: the guide is reached by keyboard, with its names and aria-current, and every ring inside the viewport', { tag: '@browsers' }, async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await openFloor(page);
  await expect(guideOf(page)).toHaveCount(1);
  await expect(stepOf(page, 1, 'current'), 'step 1 is current').toHaveAttribute('aria-current', 'step');
  await expect(guideOf(page).locator('[aria-current="step"]'), 'and the only one').toHaveCount(1);

  for (const height of [720, 600]) {
    await page.setViewportSize({ width: 1280, height });
    await settled(page);
    const stops = await guideStops(page);
    expect(
      stops,
      `at 1280x${height} the stops are the five steps, Hide guide, Send, and the box's button and Do step 1`,
    ).toEqual([
      'button "Step 1, Watch, current"',
      'button "Step 2, Reminder, upcoming"',
      'button "Step 3, Break the feed, upcoming"',
      'button "Step 4, Approve, upcoming"',
      'button "Step 5, Open the trace, upcoming"',
      'button "Hide guide"',
      'button "Send"',
      'button "Break the feed"',
      'button "Do step 1"',
    ]);
  }

  // Enter on a step selects it and leaves focus where it is.
  const second = stepOf(page, 2, 'upcoming');
  await second.focus();
  await page.keyboard.press('Enter');
  await expect(guideOf(page).locator('.prompt-text'), 'Enter selects step 2').toHaveText(`"${P2}"`);
  await expect(second, 'focus stays on the step').toBeFocused();
  await expect(second).not.toHaveAttribute('aria-current', /.*/);
  await expect(stepOf(page, 1, 'current'), 'aria-current stays on the current step').toHaveAttribute('aria-current', 'step');
  await expect(guideOf(page).locator('.step.done'), 'nothing became done').toHaveCount(0);
});

/** M2: the inactive box is focusable, aria-disabled and described, a press sends nothing; Hide and Show carry aria-expanded and move focus. */
test('M2: the inactive box is focusable and described, and Hide and Show move focus', { tag: '@browsers' }, async ({ page }) => {
  const presses: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname.endsWith('/demo/break-feed')) presses.push(request.url());
  });
  await openFloor(page);

  const button = breakOf(page);
  await expect(boxOf(page).getByText('Demo control', { exact: true })).toBeVisible();
  await expect(button, 'aria-disabled, never disabled').toHaveAttribute('aria-disabled', 'true');
  await expect(button).not.toHaveAttribute('disabled', /.*/);
  await button.focus();
  await expect(button, 'the inactive button takes focus').toBeFocused();
  await expect(button, 'described by its hint').toHaveAccessibleDescription(H1);
  await page.keyboard.press('Enter');
  await page.keyboard.press(' ');
  await settled(page);
  expect(presses, 'a press on it sends nothing').toEqual([]);
  await expect(button).toBeFocused();

  const hide = hideOf(page);
  await expect(hide, 'Hide guide has no aria-expanded').not.toHaveAttribute('aria-expanded', /.*/);
  await hide.focus();
  await page.keyboard.press('Enter');
  await expect(showOf(page), 'Show guide has aria-expanded false').toHaveAttribute('aria-expanded', 'false');
  await expect(showOf(page), 'and takes focus').toBeFocused();
  await expect(boxOf(page), 'the box keeps its place and rules').toBeVisible();
  await expect(breakOf(page)).toHaveAttribute('aria-disabled', 'true');
  await expect(guideOf(page).locator('ol'), 'the steps are gone').toHaveCount(0);

  await page.keyboard.press('Enter');
  await expect(hideOf(page), 'Show guide restores the guide, with focus on Hide guide').toBeFocused();
  await expect(stepOf(page, 1, 'current')).toBeVisible();
  expect(presses).toEqual([]);
});

/** Seeds an Orders watch check, as the Orders production is named, and returns its ref; the caller removes it with cleanFixtureRows. */
async function seedWatch(user: string, refs: string[]): Promise<string> {
  const ref = await seedCheck(user, { ...ORDERS, displayName: 'zz M Orders' });
  refs.push(ref);
  return ref;
}

/** Seeds a pending reminder row, and returns its ref. */
async function seedStretch(user: string, refs: string[]): Promise<string> {
  const ref = await seedReminder(user, { text: 'zz M stretch' });
  refs.push(ref);
  return ref;
}

/** M3: the real guide advances to step 2 and to step 3, each announced once; focus stays where the update did not remove it. */
test('M3: the real guide.state advances the page to step 2 and step 3, announced once each, with focus kept', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await recordAnnouncements(page);
    await openFloor(page);
    await expect(stepOf(page, 1, 'current')).toHaveAttribute('aria-current', 'step');
    await expect(guideOf(page).locator('.prompt-text')).toHaveText(`"${P1}"`);

    // Step 1 to step 2: focus on the prompt bar's Send stays on it.
    const check = await seedWatch(user, refs);
    await sendOf(page).focus();
    await expect(sendOf(page)).toBeFocused();
    await publishCheck(user, { ref: check, ...ORDERS, displayName: 'zz M Orders' });
    await expect(stepOf(page, 2, 'current'), 'the watch advances the guide to step 2').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(stepOf(page, 1, 'done'), 'step 1 is done').toHaveCount(1);
    await expect(guideOf(page).locator('.prompt-text'), 'the selection followed: step 2\'s prompt').toHaveText(`"${P2}"`);
    await expect(sendOf(page), 'focus on the prompt bar\'s Send stays on the prompt bar\'s action').toBeFocused();
    await expect.poll(() => announcements(page, 'Step 2 of 5: Reminder'), { message: 'announced', timeout: CARD_MS }).toBe(1);

    // Step 2 to step 3: focus in the composer stays there.
    const reminder = await seedStretch(user, refs);
    await composerOf(page).focus();
    await publishReminder(user, { ref: reminder, text: 'zz M stretch' });
    await expect(stepOf(page, 3, 'current'), 'the reminder advances it to step 3').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(stepOf(page, 2, 'done')).toHaveCount(1);
    await expect(composerOf(page), 'focus in the composer stays there').toBeFocused();
    await expect.poll(() => announcements(page, 'Step 3 of 5: Break the feed'), { message: 'announced', timeout: CARD_MS }).toBe(1);
    await expect(guideOf(page).locator('.prompt-text'), 'step 3 holds no prompt yet (Story 4.7)').toHaveCount(0);

    // At step 3 the box is active, with the tag.
    await expect(breakOf(page)).toHaveClass(/button-attention/, { timeout: CARD_MS });
    await expect(breakOf(page)).not.toHaveAttribute('aria-disabled', /.*/);
    await expect(boxOf(page).getByText('Next step', { exact: true })).toBeVisible();
    await page.waitForTimeout(1500);
    const said = await announcedTexts(page);
    expect(said.filter((text) => text.includes('Step 2 of 5')), 'each advance once').toHaveLength(1);
    expect(said.filter((text) => text.includes('Step 3 of 5')), 'each advance once').toHaveLength(1);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** M6: an update that removes the focused prompt button moves focus to the prompt bar; an update that removes nothing leaves focus in the composer. */
test('M6: focus in the composer stays through an advance, and a removed prompt button hands focus to the prompt bar', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await openFloor(page);
    await expect(stepOf(page, 1, 'current')).toHaveAttribute('aria-current', 'step');

    // Step 1 to step 2 with focus in the composer: it stays there.
    const check = await seedWatch(user, refs);
    await composerOf(page).focus();
    await publishCheck(user, { ref: check, ...ORDERS, displayName: 'zz M Orders' });
    await expect(stepOf(page, 2, 'current'), 'the watch advances the guide to step 2').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(composerOf(page), 'focus in the composer stays there').toBeFocused();

    // Step 2 to step 3 with focus on the prompt bar's Send, which step 3 does not have: focus goes to the prompt bar.
    const reminder = await seedStretch(user, refs);
    await sendOf(page).focus();
    await expect(sendOf(page)).toBeFocused();
    await publishReminder(user, { ref: reminder, text: 'zz M stretch' });
    await expect(stepOf(page, 3, 'current'), 'the reminder advances it to step 3').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(guideOf(page).locator('.prompt'), 'the removed Send hands focus to the prompt bar').toBeFocused();
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** M4: a real press from step 3: busy, the sending line, the sent line announced once with the elapsed time ticking, and a watch.progress line. */
test('M4: a real press is busy, then sent (announced once, the elapsed time ticking), and a watch.progress line replaces it', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  let pressed = false;
  try {
    const check = await seedWatch(user, refs);
    const reminder = await seedStretch(user, refs);
    await publishCheck(user, { ref: check, ...ORDERS, displayName: 'zz M Orders' });
    await publishReminder(user, { ref: reminder, text: 'zz M stretch' });
    await page.route(BREAK_FEED, async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      await route.continue();
    });
    await recordAnnouncements(page);
    await openFloor(page);
    await expect(stepOf(page, 3, 'current'), 'the page opens at step 3').toHaveAttribute('aria-current', 'step');
    await expect(breakOf(page)).toHaveClass(/button-attention/);
    await expect(boxOf(page).getByText('Next step', { exact: true })).toBeVisible();

    // An earlier run's watch.progress, in the page's store before the press: its line never shows for this run. The check's renamed
    // event follows it in the same stream, so the rail showing the new name means the page holds the earlier event.
    await publishWatchProgress(user, { ref: `zzold${Date.now().toString(36)}`, stage: 'noticed' });
    await publishCheck(user, { ref: check, ...ORDERS, displayName: 'zz M Orders again' });
    await expect(railOf(page).getByText('zz M Orders again').first(), 'the page holds the earlier progress event').toBeVisible({ timeout: CARD_MS });

    const button = breakOf(page);
    await button.click();
    pressed = true;
    await expect(button, 'busy while the press has no answer').toHaveAttribute('aria-busy', 'true');
    await expect(boxOf(page).locator('.line')).toHaveText(SENDING);
    await expect(boxOf(page).getByText('Next step', { exact: true }), 'the tag leaves once it is pressed').toHaveCount(0);
    await expect(boxOf(page).locator('.line'), 'then the sent line').toContainText(SENT, { timeout: CARD_MS });
    await page.waitForTimeout(1500);
    await expect(boxOf(page).locator('.line'), 'the earlier run\'s progress does not replace it').toContainText(SENT);
    await expect(button, 'inactive after the real 200, whatever the view still says').toHaveAttribute('aria-disabled', 'true');
    await expect(button).not.toHaveAttribute('aria-busy', /.*/);
    await expect(button).toHaveClass(/button-inactive/);
    await expect.poll(() => announcements(page, SENT), { message: 'Sent is announced', timeout: CARD_MS }).toBe(1);

    const elapsed = boxOf(page).locator('.line .elapsed [aria-hidden="true"]');
    const first = await elapsed.textContent();
    await expect.poll(async () => elapsed.textContent(), { message: 'the elapsed time ticks', timeout: CARD_MS }).not.toBe(first);
    await page.waitForTimeout(3000);
    expect(await announcedTexts(page), 'and nothing more is announced for the ticking or for the views that follow').toEqual([expect.stringContaining(SENT)]);
    await expect(button, 'the box follows the server: still inactive while the run waits').toHaveAttribute('aria-disabled', 'true');

    // A progress line of this run replaces the sent line, with the elapsed time and no count.
    await publishWatchProgress(user, { ref: `zz${Date.now().toString(36)}`, stage: 'noticed' });
    await expect(boxOf(page).locator('.line'), 'the run\'s own watch.progress line').toContainText(NOTICED, { timeout: CARD_MS });
    await expect(boxOf(page).locator('.line .elapsed'), 'the elapsed time stays').toHaveCount(1);
    const words = await boxOf(page)
      .locator('.line')
      .evaluate((node) => [...node.childNodes].filter((child) => child.nodeType === Node.TEXT_NODE).map((child) => child.textContent ?? '').join(''));
    expect(words, 'and the line, read without its elapsed time, shows no count').not.toMatch(/\b50\b/);
    expect((await announcedTexts(page)).length, 'the progress line is not announced').toBe(1);
  } finally {
    if (pressed) await settleBatch(user);
    await cleanFixtureRows(refs);
    await dropBreakFeed(user);
  }
});

/** The element's box, and whether two boxes share a row: their vertical ranges overlap. */
async function box(locator: Locator): Promise<{ x: number; y: number; width: number; height: number }> {
  return (await locator.boundingBox())!;
}

/** M5: the guide at 1280x600 (one compact row), 1100x720 (numbers), 1000x800 (stacked) and collapsed (the box at the bar's right end). */
test('M5: the layout: one compact row under 680px tall, numbers from 1024 to 1279px, the stacked order, and the collapsed bar', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await openFloor(page);
  const guide = guideOf(page);
  await expect(guide.locator('.step-label').first(), 'at 1280x720 the steps carry their labels').toBeVisible();

  await expect(guide.locator('[aria-live], [aria-atomic], [role="log"], [role="status"], [role="alert"], [role="timer"]'), 'neither the guide nor the box is live').toHaveCount(0);

  // Under 680px tall: one compact row; the page does not scroll.
  await page.setViewportSize({ width: 1280, height: 600 });
  await settled(page);
  const row = await box(guide.locator('.row1'));
  const prompt = await box(guide.locator('.prompt'));
  expect(Math.abs(prompt.y + prompt.height / 2 - (row.y + row.height / 2)), 'the steps and the prompt bar share one row').toBeLessThan(row.height);
  expect(prompt.x, 'the prompt bar follows the steps on that row').toBeGreaterThan(row.x + row.width - 1);
  expect((await box(guide)).height, 'the compact row is at least 56px').toBeGreaterThanOrEqual(56);
  await expect(guide.locator('.step-label').first(), 'the steps are numbers only').toBeHidden();
  await expect(stepOf(page, 1, 'current'), 'with their names unchanged').toBeVisible();
  const overflow = await page.evaluate(() => document.scrollingElement!.scrollHeight - document.scrollingElement!.clientHeight);
  expect(overflow, 'the page does not scroll at 1280x600').toBeLessThanOrEqual(0);
  expect(await guide.locator('.button').evaluateAll((nodes) => nodes.every((node) => node.scrollHeight - node.clientHeight <= 1)), 'nothing in it is clipped').toBe(true);

  // 1024 to 1279px wide: numbers instead of labels, names unchanged.
  await page.setViewportSize({ width: 1100, height: 720 });
  await settled(page);
  await expect(guide.locator('.step-label').first()).toBeHidden();
  await expect(guide.locator('.step .marker').first()).toBeVisible();
  for (const [n, state] of [[1, 'current'], [2, 'upcoming'], [3, 'upcoming'], [4, 'upcoming'], [5, 'upcoming']] as const) {
    await expect(stepOf(page, n, state)).toBeVisible();
  }
  const wide = await box(guide.locator('.row1'));
  const side = await box(boxOf(page));
  expect(side.x, 'the box stays at the right of the guide').toBeGreaterThanOrEqual(wide.x + wide.width - 1);

  // Under 1024px: header, banners, the guide (the box after the prompt bar), then main, then the rail.
  await page.setViewportSize({ width: 1000, height: 800 });
  await settled(page);
  const order = await page.evaluate(() => {
    const top = (selector: string): number => document.querySelector(selector)!.getBoundingClientRect().top + window.scrollY;
    const bottom = (selector: string): number => document.querySelector(selector)!.getBoundingClientRect().bottom + window.scrollY;
    return {
      header: top('app-header'),
      guide: top('app-demo-guide'),
      prompt: bottom('app-demo-guide .prompt'),
      box: top('app-break-feed-box'),
      main: top('main.main'),
      rail: top('section.rail'),
    };
  });
  expect(order.guide, 'the guide comes after the header').toBeGreaterThanOrEqual(order.header);
  expect(order.box, 'the box comes after the prompt bar').toBeGreaterThanOrEqual(order.prompt - 1);
  expect(order.main, 'main comes after the guide').toBeGreaterThan(order.box);
  expect(order.rail, 'and the rail after main').toBeGreaterThan(order.main);
  await expect(railOf(page)).toHaveCount(1);
  await expect(mainOf(page)).toHaveCount(1);

  // The collapsed bar: the box at its right end, with Demo control inline before the button.
  await page.setViewportSize({ width: 1280, height: 720 });
  await settled(page);
  await hideOf(page).click();
  await expect(showOf(page)).toBeVisible();
  const bar = await box(guide);
  expect(bar.height, 'the bar is at least 40px tall').toBeGreaterThanOrEqual(40);
  expect(bar.height, 'and is one bar, with the box\'s hint under its button').toBeLessThan(110);
  const collapsedBox = await box(boxOf(page));
  expect(collapsedBox.x + collapsedBox.width, 'the box is at the bar\'s right end').toBeGreaterThanOrEqual(bar.x + bar.width - 1);
  const label = await box(boxOf(page).getByText('Demo control', { exact: true }));
  const button = await box(breakOf(page));
  expect(label.x + label.width, '"Demo control" sits inline before the button').toBeLessThanOrEqual(button.x + 1);
  expect(Math.abs(label.y + label.height / 2 - (button.y + button.height / 2)), 'on the button\'s line').toBeLessThan(button.height / 2);
  await expect(guide.locator('[aria-live], [aria-atomic], [role="log"], [role="status"], [role="alert"], [role="timer"]'), 'still no live attribute').toHaveCount(0);
});
