import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { post, STATE } from '../support/api';
import { announcements, announcedTexts, recordAnnouncements, tokenColor } from '../support/page';
import { CARD_MS, HEADER, MOST_STOPS, SKIP_CHAT, applied, composerOf, expectStopRing, inMs, loadedAfter, mainOf, openFloor, railOf, readFocus, settled, skipLink, stepKeys } from '../support/floor';
import { publishFixtureEvent } from '../support/devices';
import { awaitOrdersPolls, dropBreakFeed, dropUsage, GUIDE_MARKERS, holdOrdersFailures, ORDERS, ordersFailuresHeld, pressIncidents, publishWatchProgress, refreshGuide, releaseOrdersFailures, rowCount, seedBreakFeedRun, setIncident, settleBatch, startEpochAt } from '../support/guide';
import { cleanFixtureRows, fixtureUser, publishCheck, publishReminder, seedApproval, seedCheck, seedIncident, seedReminder, seedTurns, setApprovalState, turnRows } from '../support/iris';
import { helpSeen, stubTraces, TRACE_PAGE } from '../support/trace';

/**
 * Story 4.4, the demo guide and the Break the feed box on the floor stack, as the FLOOR user (M1 to M6; the floor stack is in demo mode).
 * M1 and M2 run in all three engines (tag @browsers): the keyboard, the names, aria-current, Enter, the rings inside the viewport, the
 * inactive box that stays focusable and described, Hide and Show with their aria-expanded and focus. M3 and M4 read the real guide.state
 * and the real POST /v1/demo/break-feed: the check and the reminder of the Orders watch advance the page to step 2 and step 3, and a real
 * press runs from step 3 to its sent line. M5 reads the layout at 1280x600, 1100x720 and 1000x800 and the collapsed bar.
 * A case removes the check and the reminder it seeds with cleanFixtureRows, and M4 the run and the batch of 50 orders as well (the FLOOR
 * session is no fixture session, so Fixture.Clean keeps its run rows, and a run under 180 s old would show in the next case's guide).
 * M4 holds the Orders failures before it seeds anything and releases them after its batch is complete, so that the real failure poller
 * makes no incident of the batch: an incident would open M7 at step 4, make M9's box inactive and replace M4's own progress lines.
 * Story 4.7 finishes the guide (M7 to M11), each on real guide.state from seeded rows: M7 step 3's instruction line and the waiting line, M8 Show me
 * and the step 4 variants, M9 Open the trace and the finish state with its run total, links and attention box, M10 Run again, M11 the same press with the sign-in help already seen, M12 and M13 (QA) the cells of those rows that need an odd state: Show me with no phone message, the hand-off of focus to an inactive box, a failed marker write and a finish with no turn. Their trace tabs
 * are stand-ins (stubTraces), so they hold no licence connection, and M9 and M10 start from a run_again, so that the run window is clean.
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
const P3 = 'Press Break the feed. The partner will send 50 orders in a new date format.';
const WAITING = 'Waiting for OcuTalon. The reminder may arrive first.';
const APPROVE = 'Approve the fix on the simulated phone, or in the chat.';
const REJECTED = 'Rejected. Nothing was changed. Dismiss the incident in the chat, then press Break the feed again.';
const P5 = "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision.";
const DONE =
  'Done. You saw an AI Hub agent read 50 failed orders and name the cause. Every decision, with its cost, and every step it took landed in Visual Trace, and the fix waited for your approval and was recorded in the audit log.';
const MORE = 'More to try: simulate an incoming email in the simulated mailbox and see what OcuTalon decides. On your own install, ask it to watch any production.';
const README = 'https://github.com/jbrandtmse/OcuTalon#readme';
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
const promptText = (page: Page): Locator => guideOf(page).locator('.prompt-text');

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
    await expect(promptText(page), "step 3's prompt (Story 4.7)").toHaveText(`"${P3}"`);
    await expect(guideOf(page).locator('.prompt').getByRole('button'), 'with no button in the prompt bar').toHaveCount(0);

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

/** M6: an update that removes the focused prompt button moves focus to the box's Break the feed button; an update that removes nothing leaves focus in the composer. */
test('M6: focus in the composer stays through an advance, and a removed Send hands focus to the box\'s Break the feed button', async ({ page }) => {
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

    // Step 2 to step 3 with focus on the prompt bar's Send, which step 3 removes: focus goes to the box's Break the feed button, which is not pressed.
    const posts: string[] = [];
    page.on('request', (request) => {
      if (request.method() === 'POST' && request.url().includes('/demo/break-feed')) {
        posts.push(request.url());
      }
    });
    const reminder = await seedStretch(user, refs);
    await sendOf(page).focus();
    await expect(sendOf(page)).toBeFocused();
    await publishReminder(user, { ref: reminder, text: 'zz M stretch' });
    await expect(stepOf(page, 3, 'current'), 'the reminder advances it to step 3').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(breakOf(page), "the removed Send hands focus to the box's Break the feed button").toBeFocused();
    await settled(page);
    expect(posts, 'nothing is pressed or posted').toEqual([]);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/**
 * M4: a real press from step 3: busy, the sending line, the sent line announced once with the elapsed time ticking, and a watch.progress line.
 * The Orders failures are held while it runs, so that the press's batch makes no incident, group or progress line of its own.
 */
test('M4: a real press is busy, then sent (announced once, the elapsed time ticking), and a watch.progress line replaces it', async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  let pressed = false;
  let held = false;
  const since = inMs(0);
  try {
    await holdOrdersFailures();
    held = true;
    expect(await ordersFailuresHeld(), 'the Orders failures are held before the case seeds anything').toBe(true);
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
    await awaitOrdersPolls(2);
    expect(await pressIncidents(user, since), 'the press made no incident and no failure group').toEqual({ incidents: 0, groups: 0 });
  } finally {
    try {
      if (pressed) await settleBatch(user);
    } finally {
      try {
        if (held) {
          await releaseOrdersFailures();
          expect(await ordersFailuresHeld(), 'the finally released the Orders failures').toBe(false);
        }
      } finally {
        await cleanFixtureRows(refs);
        await dropBreakFeed(user);
      }
    }
  }
});

/** The guide's step 4 and step 5 rows: an Orders incident with the trace session HEADER, and the watch and the reminder that come before it. */
async function seedIncidentPath(user: string, refs: string[], incident: { state: string; openVariant: string }, request: 'pending' | 'approved'): Promise<{ incident: string; approval: string }> {
  await seedWatch(user, refs);
  await seedStretch(user, refs);
  const incidentRef = await seedIncident(user, { ...ORDERS, noticedAt: inMs(0), traceHeaderId: HEADER, ...incident });
  refs.push(incidentRef);
  const approval = await seedApproval(user, { incidentRef, state: request });
  refs.push(approval);
  return { incident: incidentRef, approval };
}

/** M7: step 3 shows only its instruction line, and the box's Next step tag and teal bar point to Break the feed; a run in flight shows only the waiting line, and no notice brings the prompt back. */
test('M7: step 3 shows only its instruction line, with the box\'s Next step tag and teal bar, and a run in flight shows only the waiting line', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const posts: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST') posts.push(new URL(request.url()).pathname);
  });
  let epochStart: string | undefined;
  try {
    // The run window starts 5 minutes back, so that both runs below are the epoch's whatever case ran before.
    epochStart = await startEpochAt(user, inMs(-300_000));
    const check = await seedWatch(user, refs);
    const reminder = await seedStretch(user, refs);
    await publishCheck(user, { ref: check, ...ORDERS, displayName: 'zz M Orders' });
    await publishReminder(user, { ref: reminder, text: 'zz M stretch' });
    await openFloor(page);
    await expect(stepOf(page, 3, 'current'), 'the page opens at step 3').toHaveAttribute('aria-current', 'step');
    await expect(promptText(page), "step 3's prompt, quoted").toHaveText(`"${P3}"`);
    await expect(guideOf(page).locator('.prompt .next'), 'after Next:').toHaveText('Next:');

    posts.length = 0;
    await expect(guideOf(page).locator('.prompt').getByRole('button'), 'with no button').toHaveCount(0);
    await expect(guideOf(page).locator('.prompt').getByRole('link'), 'and no link').toHaveCount(0);
    await expect(boxOf(page), 'the box is the next step').toHaveClass(/next-step/);
    await expect(boxOf(page).getByText('Next step', { exact: true }), 'with its tag').toBeVisible();
    await expect(boxOf(page), 'and the 4px action bar on its left').toHaveCSS('border-inline-start-width', '4px');
    await expect(boxOf(page)).toHaveCSS('border-inline-start-color', await tokenColor(page, '--action'));
    await settled(page);
    await expect(breakOf(page), 'the load moved no focus to the box').not.toBeFocused();
    await expect(breakOf(page), 'and pressed nothing').not.toHaveAttribute('aria-busy', /.*/);
    expect(
      posts.filter((path) => path.includes('/demo/break-feed') || path.includes('/guide/markers') || path.includes('/messages')),
      'nothing was pressed or written',
    ).toEqual([]);

    // A run in flight (sent, no notice yet): only the waiting line, with no Next:, no quotes and no button.
    await seedBreakFeedRun(user, 'sent', inMs(0));
    await refreshGuide(user);
    await expect(promptText(page), 'only the waiting line').toHaveText(WAITING, { timeout: CARD_MS });
    await expect(guideOf(page).locator('.prompt .next'), 'with no Next:').toHaveCount(0);
    await expect(guideOf(page).locator('.prompt .button'), 'and no button').toHaveCount(0);
    await expect(stepOf(page, 3, 'current')).toHaveAttribute('aria-current', 'step');

    // No notice after 3 minutes: the prompt is back.
    await dropBreakFeed(user);
    await seedBreakFeedRun(user, 'sent', inMs(-200_000));
    await refreshGuide(user);
    const stage = ((await (await page.request.get(STATE)).json()) as { guide: { breakFeed: { stage?: string } } }).guide.breakFeed.stage;
    expect(stage, "the run is the epoch's, with no notice after 3 minutes").toBe('no_notice');
    await expect(promptText(page), 'no notice brings the prompt back').toHaveText(`"${P3}"`, { timeout: CARD_MS });
    await expect(guideOf(page).locator('.prompt').getByRole('button'), 'with no button').toHaveCount(0);
  } finally {
    await dropBreakFeed(user);
    await cleanFixtureRows(refs);
    if (epochStart !== undefined) {
      await startEpochAt(user, epochStart);
      await endRun(page);
    }
  }
});

/** M8: Show me selects the Simulated phone tab and focuses the pending notification, never a button; a rejection shows its text with no button. */
test('M8: Show me selects the phone and focuses the pending notification, and a rejected fix shows its text with no button', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const message = `zzm8${Date.now().toString(36)}`;
  try {
    const { incident, approval } = await seedIncidentPath(user, refs, { state: 'open', openVariant: 'fix' }, 'pending');
    await openFloor(page);
    await expect(stepOf(page, 4, 'current'), 'the page opens at step 4').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(promptText(page), 'the unpaired text, quoted').toHaveText(`"${APPROVE}"`);
    const showMe = guideOf(page).getByRole('button', { name: 'Show me', exact: true });
    await expect(showMe).toBeVisible();

    // The phone message that names the request, with the mailbox tab selected first.
    const seq = await publishFixtureEvent(user, 'phone', 'OcuTalon.Live.Payload.Phone', { Ref: message, Direction: 'out', Text: 'zz approve the fix', ApprovalRef: approval, CreatedAt: inMs(0) });
    await applied(page, seq);
    const phoneTab = page.getByRole('tab', { name: /^Simulated phone/ });
    const mailboxTab = page.getByRole('tab', { name: /^Simulated mailbox/ });
    await mailboxTab.click();
    await expect(mailboxTab).toHaveAttribute('aria-selected', 'true');
    await expect(phoneTab).toHaveAttribute('aria-selected', 'false');

    await showMe.click();
    await expect(phoneTab, 'Show me selects the phone tab').toHaveAttribute('aria-selected', 'true');
    await expect(page.locator(`app-simulated-phone .notification[data-key="${message}"]`), "and focuses the pending notification's container").toBeFocused();
    await expect(page.locator('button:focus, a:focus'), 'never a button').toHaveCount(0);

    // A rejection: the rejected text, no button, and step 5 still available.
    await setApprovalState(approval, 'rejected');
    await setIncident(incident, { state: 'open', openVariant: 'rejected' });
    await refreshGuide(user);
    await expect(promptText(page), 'the rejected text').toHaveText(`"${REJECTED}"`, { timeout: CARD_MS });
    await expect(guideOf(page).locator('.prompt .button, .prompt app-trace-link'), 'with no action button').toHaveCount(0);
    await expect(stepOf(page, 4, 'current'), 'step 4 stays current').toHaveAttribute('aria-current', 'step');
    await stepOf(page, 5, 'upcoming').click();
    await expect(promptText(page), 'step 5 is available').toHaveText(`"${P5}"`);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** Everything M9 and M10 start from: the guide at step 5 of a run that ended with an approved fix and a resolved incident, with its run total seeded. */
async function seedFinishingRun(page: Page, user: string, refs: string[], usage: string[]): Promise<void> {
  await openFloor(page);
  const marked = await post(page.request, GUIDE_MARKERS, { marker: 'run_again' });
  expect(marked.status(), await marked.text()).toBe(200);
  await seedIncidentPath(user, refs, { state: 'resolved', openVariant: 'fix' }, 'approved');
  const seeded = await seedTurns(
    user,
    [
      {
        createdAt: inMs(0),
        text: 'zz M9 turn',
        replyText: 'zz M9 reply',
        traceHeaderId: HEADER + 1,
        triage: { outcome: 'tellnow', costUSD: 0.002 },
        turn: { outcome: 'tellnow', costUSD: 0.0021 },
        usage: [
          { of: 'triage', inputTokens: 5000, outputTokens: 400, costUSD: 0.002 },
          { of: 'turn', inputTokens: 4000, outputTokens: 450, costUSD: 0.0021 },
        ],
      },
    ],
    true,
  );
  refs.push(...turnRows(seeded));
  usage.push(...seeded.decisions.flatMap((one) => [one.triage, one.turn]).filter((ref) => ref !== ''));
  await refreshGuide(user);
  await expect(stepOf(page, 5, 'current'), 'the guide is at step 5').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
}

/**
 * Holds the page's polls of /events until the returned release is called, and returns once a poll is waiting, so that no live view
 * reaches the page in between.
 */
async function holdPolls(page: Page): Promise<() => void> {
  let release!: () => void;
  let held!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const polled = new Promise<void>((resolve) => (held = resolve));
  await page.route('**/ocutalon/api/v1/events?*', async (route) => {
    held();
    await gate;
    await route.continue();
  });
  await polled;
  return release;
}

/** Ends the run the case finished, so that the FLOOR user's next case starts from a clean guide. */
async function endRun(page: Page): Promise<void> {
  await post(page.request, GUIDE_MARKERS, { marker: 'run_again' }).catch(() => undefined);
}

/** The Open the trace link of the prompt bar. */
const openTraceOf = (page: Page): Locator => guideOf(page).locator('.prompt app-trace-link a');

/** M9: Open the trace opens the incident's trace and writes trace_opened, and the finish state replaces the prompt bar with the run total and its links. */
test('M9: Open the trace, then the finish state: the exact lines, the run total, the two links, the attention box, focus on the first line, no announcement', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const usage: string[] = [];
  try {
    await stubTraces(page.context());
    await recordAnnouncements(page);
    await seedFinishingRun(page, user, refs, usage);
    const before = (await announcedTexts(page)).length;

    await expect(promptText(page), "step 5's prompt, quoted").toHaveText(`"${P5}"`);
    const link = openTraceOf(page);
    await expect(link, "its address is the incident's TraceLink URL").toHaveAttribute('href', `${TRACE_PAGE}${HEADER}`);
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(link).toHaveClass(/button-primary/);
    await expect(breakOf(page), 'while step 5 is current the box is the secondary style').toHaveClass(/button-secondary/);

    const markers: string[] = [];
    page.on('request', (request) => {
      if (request.method() === 'POST' && new URL(request.url()).pathname.endsWith('/guide/markers')) markers.push(request.postData() ?? '');
    });
    const written = page.waitForResponse((response) => new URL(response.url()).pathname.endsWith('/guide/markers') && (response.request().postData() ?? '').includes('trace_opened'));
    const tab = page.context().waitForEvent('page');
    await expect(link, 'on a local install it is named for the help it shows first').toHaveAccessibleName('Open the trace (shows sign-in help first)');
    await expect(link).toHaveAttribute('aria-haspopup', 'dialog');
    await link.click();
    const dialog = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(dialog, 'the help shows first').toBeVisible();
    await settled(page);
    expect(markers, 'the press that only shows the help writes no marker').toEqual([]);
    await dialog.getByRole('link', { name: 'Open Visual Trace (opens in a new tab)', exact: true }).click();
    const opened = await tab;
    await opened.waitForLoadState('domcontentloaded');
    expect(new URL(opened.url()).pathname + new URL(opened.url()).search, 'a new tab opened at the incident trace').toBe(`${TRACE_PAGE}${HEADER}`);
    expect((await written).status(), 'trace_opened was written').toBe(200);

    // The finish state replaces the prompt bar.
    const finish = guideOf(page).locator('.finish');
    await expect(finish, 'the finish replaces the prompt bar').toBeVisible({ timeout: CARD_MS });
    await expect(guideOf(page).locator('.prompt')).toHaveCount(0);
    await expect(finish.locator('.finish-done'), 'the first line').toHaveText(DONE);
    await expect(finish.locator('.finish-done'), 'takes focus when the update removed the focused link').toBeFocused();
    await expect(finish.locator('.run-total'), 'the run total').toHaveText('This run: 2 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on Claude Haiku 5.5.');
    const totalStyle = await finish.locator('.run-total').evaluate((node) => {
      const style = getComputedStyle(node);
      return { numbers: style.fontVariantNumeric, size: style.fontSize, color: style.color, bodySm: getComputedStyle(document.documentElement).getPropertyValue('--type-body-sm-font-size').trim() };
    });
    expect(totalStyle.numbers, 'in tabular figures').toContain('tabular-nums');
    expect(totalStyle.size, 'in body-sm').toBe(totalStyle.bodySm);
    expect(totalStyle.color, 'in ink-muted').toBe(await tokenColor(page, '--ink-muted'));
    await expect(finish.locator('.more')).toHaveText(MORE);

    const conversation = finish.locator(`a[href="${TRACE_PAGE}${HEADER + 1}"]`);
    await expect(conversation, 'the whole-conversation link').toHaveAccessibleName('See the whole conversation in Visual Trace (opens in a new tab)');
    await expect(conversation).toHaveAttribute('target', '_blank');
    await expect(conversation.locator('[aria-hidden="true"]'), 'with a hidden arrow').toHaveText('\u2197');
    const install = finish.locator(`a[href="${README}"]`);
    await expect(install, 'the install link').toHaveAccessibleName('Install OcuTalon yourself (opens in a new tab)');
    await expect(install).toHaveAttribute('target', '_blank');
    await expect(install).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(install.locator('[aria-hidden="true"]')).toHaveText('\u2197');
    expect(await install.evaluate((node) => getComputedStyle(node).textDecorationLine), 'underlined').toContain('underline');
    await expect(finish.getByRole('button', { name: 'Run again', exact: true })).toBeVisible();
    await expect(guideOf(page).locator('ol .step'), 'the step list stays').toHaveCount(5);

    // The box takes the attention style again.
    await expect(breakOf(page)).toHaveClass(/button-attention/);
    expect(await breakOf(page).evaluate((node) => getComputedStyle(node).backgroundColor), 'in the attention colour').toBe(await tokenColor(page, '--button-attention-background'));
    expect((await announcedTexts(page)).slice(before).filter((text) => text.includes('Done') || text.includes('This run')), 'the finish is not announced').toEqual([]);
  } finally {
    await dropUsage(usage);
    await cleanFixtureRows(refs);
    await endRun(page);
  }
});

/** M11: with the sign-in help already seen, a press of Open the trace opens the tab and writes trace_opened at once, and the finish state follows. */
test('M11: with the sign-in help seen, Open the trace opens the tab and writes trace_opened with no popover', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const usage: string[] = [];
  try {
    await stubTraces(page.context());
    await helpSeen(page);
    await seedFinishingRun(page, user, refs, usage);
    const link = openTraceOf(page);
    await expect(link, 'named as a plain link').toHaveAccessibleName('Open the trace (opens in a new tab)');
    await expect(link, 'with no popover').not.toHaveAttribute('aria-haspopup', /.*/);
    const written = page.waitForResponse((response) => new URL(response.url()).pathname.endsWith('/guide/markers') && (response.request().postData() ?? '').includes('trace_opened'));
    const tab = page.context().waitForEvent('page');
    await link.click();
    const opened = await tab;
    await opened.waitForLoadState('domcontentloaded');
    expect(new URL(opened.url()).pathname + new URL(opened.url()).search, 'a new tab opened at the incident trace').toBe(`${TRACE_PAGE}${HEADER}`);
    expect((await written).status(), 'trace_opened was written').toBe(200);
    await expect(guideOf(page).locator('.finish'), 'and the finish replaces the prompt bar').toBeVisible({ timeout: CARD_MS });
  } finally {
    await dropUsage(usage);
    await cleanFixtureRows(refs);
    await endRun(page);
  }
});

/** M10: Run again brings the prompt bar back at step 3, with focus on the box's Break the feed button and nothing pressed, silently; the session's data stays and the epoch rises. */
test('M10: Run again returns the prompt bar at step 3 with focus on the box\'s Break the feed button, silently, and changes only the guide markers', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const usage: string[] = [];
  try {
    await stubTraces(page.context());
    await recordAnnouncements(page);
    await seedFinishingRun(page, user, refs, usage);
    const epochOf = async (): Promise<number> => ((await (await page.request.get(STATE)).json()) as { guide: { runEpoch: number } }).guide.runEpoch;
    const epoch = await epochOf();
    const checks = refs.filter((ref) => ref.length > 0);

    // Step 5 is done by the marker alone, as the page writes it.
    const marked = await post(page.request, GUIDE_MARKERS, { marker: 'trace_opened' });
    expect(marked.status(), await marked.text()).toBe(200);
    const finish = guideOf(page).locator('.finish');
    await expect(finish, 'the finish shows').toBeVisible({ timeout: CARD_MS });
    const counts = async (): Promise<number[]> => [
      await rowCount('BackgroundCheck', checks),
      await rowCount('Reminder', checks),
      await rowCount('Incident', checks),
      await rowCount('Turn', checks),
    ];
    const rows = await counts();
    expect(rows.every((count) => count > 0), 'the check, the reminder, the incident and the turn exist').toBe(true);
    const before = (await announcedTexts(page)).length;

    // The page's polls are held while Run again is pressed, so that only the 200 answer can bring the prompt bar back: it is the guide view at once.
    const breakPosts: string[] = [];
    page.on('request', (request) => {
      if (request.method() === 'POST' && request.url().includes('/demo/break-feed')) {
        breakPosts.push(request.url());
      }
    });
    const release = await holdPolls(page);
    await finish.getByRole('button', { name: 'Run again', exact: true }).click();
    try {
      await expect(promptText(page), "the 200 answer's view brings the prompt bar back at step 3, before any poll").toHaveText(`"${P3}"`, { timeout: 5000 });
    } finally {
      release();
    }
    await expect(finish, 'in place of the finish').toHaveCount(0);
    await expect(stepOf(page, 3, 'current')).toHaveAttribute('aria-current', 'step');
    await expect(breakOf(page), "with focus on the box's Break the feed button").toBeFocused();
    await settled(page);
    expect(breakPosts, 'which is not pressed').toEqual([]);
    expect(await epochOf(), 'the run epoch rose').toBe(epoch + 1);
    expect(await counts(), 'the session\'s checks, reminders, incidents and conversation are as they were').toEqual(rows);
    await page.waitForTimeout(1500);
    expect((await announcedTexts(page)).slice(before), 'Run again is silent').toEqual([]);

    // The held answer stands only until the next live view: a run in flight, seeded after Run again, shows its waiting line.
    await seedBreakFeedRun(user, 'sent', inMs(0));
    await refreshGuide(user);
    await expect(promptText(page), 'the next live view replaces the held answer').toHaveText(WAITING, { timeout: CARD_MS });
  } finally {
    await dropUsage(usage);
    await cleanFixtureRows(refs);
    await dropBreakFeed(user);
    await endRun(page);
  }
});

/** The guide's marker endpoint as the page calls it, to route it. */
const MARKERS_ROUTE = '**/ocutalon/api/v1/guide/markers';

/** An error answer of the marker endpoint, as the server gives one. */
const failMarker = (route: Route): Promise<void> => route.fulfill({ status: 500, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"zz"}}' });

/**
 * M12 (QA, rows 1 and 3): with no phone message that names the request, Show me selects the phone tab and focuses the phone's feed
 * region (never a button); and when the guide jumps from step 1 to step 3 by the removed Send while the box is inactive (an open Orders
 * incident noticed before the run window), the inactive button (aria-disabled) still takes focus, pressing nothing.
 */
test('M12: Show me with no pending notification focuses the phone feed, and a jump to step 3 hands focus to an inactive box without pressing it', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  const posts: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST') posts.push(new URL(request.url()).pathname);
  });
  let epochStart: string | undefined;
  try {
    await seedIncidentPath(user, refs, { state: 'open', openVariant: 'fix' }, 'pending');
    await openFloor(page);
    await expect(stepOf(page, 4, 'current'), 'the page opens at step 4').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    const phoneTab = page.getByRole('tab', { name: /^Simulated phone/ });
    const mailboxTab = page.getByRole('tab', { name: /^Simulated mailbox/ });
    await mailboxTab.click();
    await expect(mailboxTab).toHaveAttribute('aria-selected', 'true');

    await guideOf(page).getByRole('button', { name: 'Show me', exact: true }).click();
    await expect(phoneTab, 'Show me selects the phone tab').toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('app-simulated-phone .feed'), 'no message names the request, so focus goes to the phone feed region').toBeFocused();
    await expect(page.locator('app-simulated-phone .notification:focus'), 'and not to a notification').toHaveCount(0);
    await expect(page.locator('button:focus, a:focus'), 'never a button').toHaveCount(0);

    // Step 3 reached from step 1 by the removed Send, while an open incident noticed before the run window keeps the box inactive: it still takes focus.
    await cleanFixtureRows(refs);
    refs.length = 0;
    // The marker gives the session its guide state row, so that the run window below is set whichever case ran before.
    const marked = await post(page.request, GUIDE_MARKERS, { marker: 'run_again' });
    expect(marked.status(), await marked.text()).toBe(200);
    epochStart = await startEpochAt(user, inMs(-300_000));
    refs.push(await seedIncident(user, { ...ORDERS, noticedAt: inMs(-600_000), state: 'open', openVariant: 'fix' }));
    await loadedAfter(page, () => page.reload());
    await expect(composerOf(page)).toBeVisible();
    await expect(stepOf(page, 1, 'current'), 'the page reloads at step 1').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await seedWatch(user, refs);
    await seedStretch(user, refs);
    await sendOf(page).focus();
    await expect(sendOf(page)).toBeFocused();
    posts.length = 0;
    await refreshGuide(user);
    await expect(stepOf(page, 3, 'current'), 'the one update jumps the guide from step 1 to step 3').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    await expect(promptText(page), "step 3's prompt").toHaveText(`"${P3}"`);
    await expect(breakOf(page), 'the box is inactive while an incident is open').toHaveAttribute('aria-disabled', 'true');
    await expect(breakOf(page), 'the inactive button takes focus').toBeFocused();
    await expect(breakOf(page), 'and stays inactive').toHaveAttribute('aria-disabled', 'true');
    await settled(page);
    expect(
      posts.filter((path) => path.includes('/demo/break-feed') || path.includes('/guide/markers') || path.includes('/messages')),
      'nothing was pressed or written',
    ).toEqual([]);
  } finally {
    await cleanFixtureRows(refs);
    if (epochStart !== undefined) {
      await startEpochAt(user, epochStart);
      await endRun(page);
    }
  }
});

/**
 * M13 (QA, rows 5, 7, 8 and 9, error cells): a failed trace_opened write adds no text and leaves step 5 undone, and a later press
 * writes it again; a finish with no turn has no whole-conversation link and a run total of zeros with no model; a failed Run again
 * leaves the finish as it is, and the next press brings the prompt bar back.
 */
test('M13: a failed marker write changes nothing and is written again by the next press; a finish with no turn has no conversation link', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await stubTraces(page.context());
    await helpSeen(page);
    await openFloor(page);
    const marked = await post(page.request, GUIDE_MARKERS, { marker: 'run_again' });
    expect(marked.status(), await marked.text()).toBe(200);
    await seedIncidentPath(user, refs, { state: 'resolved', openVariant: 'fix' }, 'approved');
    await refreshGuide(user);
    await expect(stepOf(page, 5, 'current'), 'the guide is at step 5').toHaveAttribute('aria-current', 'step', { timeout: CARD_MS });
    const finishedOf = async (): Promise<boolean> => ((await (await page.request.get(STATE)).json()) as { guide: { finished: boolean } }).guide.finished === true;
    const link = openTraceOf(page);

    // A failed trace_opened write: no text, step 5 undone.
    let writes = 0;
    const failing = async (route: Route): Promise<void> => {
      writes += 1;
      await failMarker(route);
    };
    await page.route(MARKERS_ROUTE, failing);
    const bar = await guideOf(page).textContent();
    const tab = page.context().waitForEvent('page');
    await link.click();
    await (await tab).waitForLoadState('domcontentloaded');
    await expect.poll(() => writes, { message: 'the page wrote trace_opened', timeout: CARD_MS }).toBe(1);
    await page.waitForTimeout(1500);
    expect(await guideOf(page).textContent(), 'the failed write adds no text').toBe(bar);
    await expect(guideOf(page).locator('.finish'), 'and no finish').toHaveCount(0);
    await expect(promptText(page)).toHaveText(`"${P5}"`);
    expect(await finishedOf(), 'step 5 is not done on the server').toBe(false);

    // The next press writes it again.
    await page.unroute(MARKERS_ROUTE, failing);
    const written = page.waitForResponse((response) => new URL(response.url()).pathname.endsWith('/guide/markers') && (response.request().postData() ?? '').includes('trace_opened'));
    await link.click();
    expect((await written).status(), 'a later press writes trace_opened again').toBe(200);
    const finish = guideOf(page).locator('.finish');
    await expect(finish, 'and the finish replaces the prompt bar').toBeVisible({ timeout: CARD_MS });

    // No turn with a trace: no conversation link, and a run total with no usage reads zeros and names no model.
    await expect(finish.getByRole('link'), 'only the install link').toHaveCount(1);
    await expect(finish.getByRole('link', { name: /^See the whole conversation/ })).toHaveCount(0);
    await expect(finish.locator('.run-total')).toHaveText('This run: 0 decisions \u00B7 0 tokens \u00B7 <$0.0001.');

    // A failed Run again: the finish stays as it is. The page's polls are held, so that no live view arrives to put right what the failure did.
    writes = 0;
    await page.route(MARKERS_ROUTE, failing);
    const release = await holdPolls(page);
    const shown = await finish.textContent();
    try {
      await finish.getByRole('button', { name: 'Run again', exact: true }).click();
      await expect.poll(() => writes, { message: 'the page wrote run_again', timeout: CARD_MS }).toBe(1);
      await page.waitForTimeout(1500);
      await expect(finish, 'the finish stays').toBeVisible();
      expect(await finish.textContent(), 'with no text added').toBe(shown);
      expect(await finishedOf(), 'and the server still has the finish').toBe(true);
    } finally {
      release();
    }

    // The next press brings the prompt bar back.
    await page.unroute(MARKERS_ROUTE, failing);
    await finish.getByRole('button', { name: 'Run again', exact: true }).click();
    await expect(promptText(page), 'the next press brings the prompt bar back at step 3').toHaveText(`"${P3}"`, { timeout: CARD_MS });
    await expect(finish).toHaveCount(0);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await cleanFixtureRows(refs);
    await endRun(page);
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
