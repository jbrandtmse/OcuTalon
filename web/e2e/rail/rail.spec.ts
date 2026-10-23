import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import {
  cleanFixtureRows,
  fixtureUser,
  publishCheck,
  publishReminder,
  seedApproval,
  seedCheck,
  seedDecision,
  seedDecisions,
  seedIncident,
  seedReminder,
  sendNotification,
  setApprovalState,
  setTelegramIncluded,
  sinkEvent,
} from '../support/iris';
import { plain, tokenColor } from '../support/page';

/**
 * Story 2.8, the status rail (R1 to R13), in a real browser against a real stack. Every case signs in as the rail fixture user that
 * test-sign-in.sh created (OCUTALON_RAIL_USER), whose session holds nothing but what the case seeds: each case seeds run-stamped rows
 * through Test.Data.Fixture, loads the page after its own seeding (or seeds after the load and gives BridgeSink the event, as the
 * bridge would), asserts on its own rows and counts alone, and removes its rows in finally. Approval events come from BridgeSink.OnEvent
 * itself with fixture rows (Lane A's emitters are not merged); check and reminder events are published through Live.Publish. A case
 * that checks a live update waits until the page has applied the Seq that the helper returned (the page's data-session-seq) and then
 * asserts within one second. The browser runs in UTC with the en-GB locale, the stack's own zone, so a time reads the same wherever the
 * specs run.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll that a routed /events handler is still answering when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const LIVE_REGIONS = '[aria-live], [role="log"], [role="status"], [role="alert"]';

const STATE = '/ocutalon/api/v1/state';

/** The middle dot between the parts of a meta line, with its spaces. */
const DOT = ' \u00B7 ';

/** How long the page may take to apply an event after the helper returned: the live poll (1 to 2 s) and the render. */
const APPLIED_MS = 15_000;

/** The bound of "within one live update", counted from the page having applied the event. */
const ONE_UPDATE_MS = 1000;

/** A text no other case or run made. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** Today's date (UTC) with the time given, as a UTC ISO time. */
const today = (time: string): string => `${new Date().toISOString().slice(0, 10)}T${time}Z`;

/** The year before this one: its short dates carry the year. */
const LAST_YEAR = new Date().getUTCFullYear() - 1;

/** A UTC ISO time of the year before this one, at 14:12 on 1 June or the day after. */
const lastYear = (n: number): string => `${LAST_YEAR}-06-0${n + 1}T14:12:00Z`;

/** An ISO time to the second, the given number of milliseconds from the instant. */
const iso = (instant: number, offsetMs = 0): string => new Date(instant + offsetMs).toISOString().replace(/\.\d{3}Z$/, 'Z');

const rail = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
const rowOf = (page: Page, marker: string): Locator => rail(page).locator('li.row').filter({ hasText: marker });
const headings = (page: Page): Locator => rail(page).getByRole('heading', { level: 3 });
const mainOf = (page: Page): Locator => page.locator('main.main');

/** Signs the rail user in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('RAIL');
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(headings(page).first()).toBeVisible();
}

/** Waits until the page has applied the event of this Seq on the session's stream. */
async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-session-seq')), { message: `the page applied Seq ${seq}`, timeout: APPLIED_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** R1: the rail is the region Status with its sections in order, live counts, empty texts and hints. */
test('R1: the rail is the region Status with its sections in order, live counts, empty texts and hints', async ({ page }) => {
  await open(page);
  const status = rail(page);
  await expect(status, 'the rail is the region Status').toHaveCount(1);
  await expect(headings(page), 'four sections, no Telegram').toHaveCount(4);
  const spoken = ['Approval requests, 0', 'Background checks, 0', 'Reminders, 0', 'Recent decisions, 0'];
  for (const [i, name] of spoken.entries()) {
    await expect(headings(page).nth(i), `heading ${i + 1} is named "${name}"`).toHaveAccessibleName(name);
  }
  await expect(status.locator('h3 > [aria-hidden="true"]'), 'the visible headings carry the counts').toHaveText([
    'Approval requests (0)',
    'Background checks (0)',
    'Reminders (0)',
    'Recent decisions (0)',
  ]);
  await expect(status.getByRole('heading', { name: 'Telegram' }), 'no Telegram section').toHaveCount(0);
  await expect(status.getByRole('link'), 'and no README link').toHaveCount(0);
  await expect(status.locator('.empty'), 'each list shows its empty text').toHaveText([
    'None waiting.',
    'Ask OcuTalon to watch a production.',
    'None pending.',
    'No decisions yet.',
  ]);
  await expect(status.locator('.hint'), 'the check and reminder hints show under an empty list').toHaveText([
    'To stop, ask: "Stop watching Orders."',
    'To cancel, ask: "Cancel my reminder to stretch."',
  ]);
  await expect(status.locator(LIVE_REGIONS), 'the rail has no live region').toHaveCount(0);
  await expect(status.locator('h3[tabindex="-1"]'), 'each heading can take focus').toHaveCount(4);

  await page.setViewportSize({ width: 1280, height: 720 });
  expect((await page.locator('section.rail').boundingBox())!.width, 'the rail is 288px wide at 1280px').toBe(288);
  await page.setViewportSize({ width: 1440, height: 900 });
  expect((await page.locator('section.rail').boundingBox())!.width, 'and 320px wide from 1440px').toBe(320);
  await expect(page.locator('section.rail'), 'it scrolls on its own').toHaveCSS('overflow-y', 'auto');
});

/** R2: an approval request shows its action, its times and the attention bar. */
test('R2: an approval request shows its action, its times and the attention bar', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const noon = Date.parse(today('12:00:00'));
    await page.clock.setFixedTime(noon);
    refs.push(await seedApproval(user, { raisedAt: iso(noon, -60_000), expiresAt: iso(noon, 86_400_000 - 60_000), dryRun: { affected: 50, itemNoun: { one: 'order', other: 'orders' } } }));
    refs.push(await seedApproval(user, { raisedAt: iso(noon), expiresAt: iso(noon, 86_400_000), dryRun: { affected: 1, itemNoun: { one: 'order', other: 'orders' } } }));
    await open(page);
    const rows = rail(page).locator('li.row.request');
    await expect(headings(page).first(), 'two pending requests').toHaveAccessibleName('Approval requests, 2');
    await expect(rows.locator('.title'), 'each names its action, the noun by the count, oldest first').toHaveText(['Repair and resend 50 orders', 'Repair and resend 1 order']);
    await expect(rows.locator('.meta'), 'with when it was raised and when it expires').toHaveText([
      `Raised 11:59${DOT}expires tomorrow at 11:59`,
      `Raised 12:00${DOT}expires tomorrow at 12:00`,
    ]);
    await expect(rows.first(), 'a 3px bar').toHaveCSS('border-left-width', '3px');
    await expect(rows.first(), 'in the attention colour').toHaveCSS('border-left-color', await tokenColor(page, '--attention'));
    await expect(rows.first().locator('a, button'), 'a row holds no button and no link').toHaveCount(0);
    await expect(rows.first().locator('.detail'), 'and no detail line').toHaveCount(0);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R3: a raised request appears, and an answered, expired or cancelled one leaves within one live update. */
test('R3: a raised request appears, and an answered, expired or cancelled one leaves within one live update', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    await open(page);
    await expect(headings(page).first()).toHaveAccessibleName('Approval requests, 0');
    const cases = [
      ['approved', 'approval.answered'],
      ['expired', 'approval.expired'],
      ['cancelled', 'approval.cancelled'],
    ] as const;
    for (const [state, type] of cases) {
      const tool = `zz_tool_${state}_${Date.now().toString(36)}`;
      const ref = await seedApproval(user, { kind: 'tool_call', toolName: tool, dryRun: null });
      refs.push(ref);
      await applied(page, await sinkEvent(user, 'approval.raised', { ref }));
      await expect(rowOf(page, tool), `a raised request appears (${state})`).toHaveCount(1, { timeout: ONE_UPDATE_MS });
      await expect(rowOf(page, tool).locator('.title'), 'as the tool it runs').toHaveText(`Run ${tool}`);
      await expect(headings(page).first(), 'and the count counts it').toHaveAccessibleName('Approval requests, 1', { timeout: ONE_UPDATE_MS });

      await setApprovalState(ref, state);
      await applied(page, await sinkEvent(user, type, { ref }));
      await expect(rowOf(page, tool), `the ${state} request leaves`).toHaveCount(0, { timeout: ONE_UPDATE_MS });
      await expect(headings(page).first(), 'and the count drops').toHaveAccessibleName('Approval requests, 0', { timeout: ONE_UPDATE_MS });
    }
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R4: an instance incident's request reaches the session that watches its production (DW-68). */
test('R4: an instance incident\'s request reaches the session that watches its production', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const production = `Zz.Rail.${Date.now().toString(36)}`;
    const tool = `zz_tool_instance_${Date.now().toString(36)}`;
    refs.push(await seedCheck(user, { production, displayName: unique('R4 watch') }));
    refs.push(await seedIncident('instance', { production }));
    await open(page);
    await expect(headings(page).first(), 'no request is waiting before the event').toHaveAccessibleName('Approval requests, 0');
    const request = await seedApproval(user, { kind: 'tool_call', toolName: tool, dryRun: null, incidentRef: refs[1] }, 'instance');
    refs.push(request);
    await applied(page, await sinkEvent(user, 'approval.raised', { ref: request }, 'instance'));
    await expect(rowOf(page, tool), 'the instance request shows as a row').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(headings(page).first()).toHaveAccessibleName('Approval requests, 1', { timeout: ONE_UPDATE_MS });
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R5: a check shows its name, schedule and last run, and a later check event updates its row in place. */
test('R5: a check shows its name, schedule and last run, and a later check event updates its row in place', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const name = unique('R5').replace(/^zz /, 'Orders ');
    const production = `Zz.Rail.${Date.now().toString(36)}`;
    const ref = await seedCheck(user, { production, displayName: name, lastRunAt: today('12:00:00'), result: 'failed', finding: '50 new failures' });
    refs.push(ref);
    await open(page);
    const row = rowOf(page, name);
    await expect(row, 'the check shows as one row').toHaveCount(1);
    await expect(row.locator('.title'), 'named by its production').toHaveText(`${name} production`);
    await expect(row.locator('.detail'), 'with its schedule').toHaveText('Live, plus a check every minute');
    await expect(row.locator('.meta'), 'its last run and finding').toHaveText(`Last run 12:00${DOT}50 new failures`);
    await expect(rail(page).locator('.hint').first(), 'the hint sits under the list').toHaveText('To stop, ask: "Stop watching Orders."');
    await expect(row.locator('a, button'), 'the row is read-only').toHaveCount(0);
    await expect(headings(page).nth(1)).toHaveAccessibleName('Background checks, 1');
    await row.evaluate((node) => node.setAttribute('data-mark', 'same'));

    await applied(page, await publishCheck(user, { ref, production, displayName: name, lastRunAt: today('12:05:00'), result: 'passed', finding: 'No new failures' }));
    await expect(row.locator('.meta'), 'a later event changes the text').toHaveText(`Last run 12:05${DOT}No new failures`, { timeout: ONE_UPDATE_MS });
    await expect(row, 'in the same row').toHaveAttribute('data-mark', 'same');
    await expect(rowOf(page, name), 'still one row').toHaveCount(1);
    await expect(headings(page).nth(1), 'and the same count').toHaveAccessibleName('Background checks, 1');
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R6: a reminder counts down in tabular figures and a later event updates it in place. */
test('R6: a reminder counts down in tabular figures and a later event updates it in place', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const text = unique('R6').replace(/^zz /, 'zz stretch ');
    const start = Date.parse(today('12:00:00'));
    await page.clock.install({ time: start });
    await page.clock.setFixedTime(start);
    const ref = await seedReminder(user, { text, dueAt: iso(start, 90_000) });
    refs.push(ref);
    await open(page);
    const row = rowOf(page, text);
    await expect(row.locator('.lead'), 'the reminder shows its text').toHaveText(text);
    await expect(row.locator('.countdown'), 'with its countdown').toHaveText('in 1 min');
    await expect(row.locator('.countdown'), 'in tabular figures').toHaveCSS('font-variant-numeric', 'tabular-nums');
    await expect(row.locator('.visually-hidden'), 'and the countdown in words for assistive technology').toHaveText('in 1 minute');
    await row.evaluate((node) => node.setAttribute('data-mark', 'same'));

    await applied(page, await publishReminder(user, { ref, text, dueAt: iso(start, 59_000) }));
    await expect(row.locator('.countdown'), 'a later event with the same ref changes it in place').toHaveText('in 59 s', { timeout: ONE_UPDATE_MS });
    await expect(row.locator('.visually-hidden'), 'spoken in full words').toHaveText('in 59 seconds');
    await expect(row.locator('.meta'), 'with its due time').toHaveText(/^Due \d{1,2}:\d\d$/);
    await expect(row, 'in the same row').toHaveAttribute('data-mark', 'same');
    await expect(rowOf(page, text), 'still one row').toHaveCount(1);

    await page.clock.setFixedTime(start + 2000);
    await expect(row.locator('.countdown'), 'and it ticks').toHaveText('in 57 s', { timeout: 3000 });
    await expect(row.locator('.visually-hidden')).toHaveText('in 57 seconds');
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R7: a fired reminder leaves and its notice card shows in the chat; a cancelled one leaves. */
test('R7: a fired reminder leaves and its notice card shows in the chat; a cancelled one leaves', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const fired = unique('R7').replace(/^zz /, 'zz fired ');
    const cancelled = unique('R7').replace(/^zz /, 'zz cancelled ');
    const start = Date.now();
    const firedRef = await seedReminder(user, { text: fired, dueAt: iso(start, 300_000) });
    const cancelledRef = await seedReminder(user, { text: cancelled, dueAt: iso(start, 300_000) });
    refs.push(firedRef, cancelledRef);
    await open(page);
    await expect(rowOf(page, fired)).toHaveCount(1);
    await expect(rowOf(page, cancelled)).toHaveCount(1);
    await expect(headings(page).nth(2)).toHaveAccessibleName('Reminders, 2');

    const seq = await publishReminder(user, { ref: firedRef, text: fired, dueAt: iso(start, 300_000), state: 'fired' });
    await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text: fired, dueAt: today('12:00:00') } });
    await applied(page, seq);
    await expect(rowOf(page, fired), 'the fired reminder leaves the list').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(headings(page).nth(2), 'and the count drops').toHaveAccessibleName('Reminders, 1', { timeout: ONE_UPDATE_MS });
    await expect(page.locator('main app-notice-card').filter({ hasText: fired }), 'its notice card is in the chat').toHaveCount(1, { timeout: APPLIED_MS });

    await applied(page, await publishReminder(user, { ref: cancelledRef, text: cancelled, dueAt: iso(start, 300_000), state: 'cancelled' }));
    await expect(rowOf(page, cancelled), 'a cancelled reminder leaves too').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(headings(page).nth(2)).toHaveAccessibleName('Reminders, 0', { timeout: ONE_UPDATE_MS });
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** The decisions of R8 to R10: a summary and a time of its own, a minute apart. */
const summaryOf = (stamp: string, n: number): string => `${stamp} decision ${String(n).padStart(2, '0')}`;
const REASONS = 'zz first reason.\nzz second reason.';

/** R8: Recent decisions shows the 20 newest attention decisions as disclosures. */
test('R8: Recent decisions shows the 20 newest attention decisions as disclosures', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const stamp = unique('R8');
    const rows = Array.from({ length: 21 }, (_unused, n) => ({
      outcome: 'act',
      summary: summaryOf(stamp, n),
      reasons: REASONS,
      confidence: 0.9,
      costUSD: 0.0003,
      recordedAt: n < 2 ? lastYear(n) : today(`12:${String(n).padStart(2, '0')}:00`),
      ...(n === 10 ? { fallback: true, fallbackReason: 'refusal' } : {}),
    }));
    refs.push(...(await seedDecisions(user, rows)));
    refs.push(await seedDecision(user, { outcome: 'act', summary: `${stamp} turn decision`, recordedAt: today('12:30:00') }, 'turn'));
    await open(page);
    const decisions = rail(page).locator('app-decision-row');
    await expect(headings(page).nth(3), 'twenty rows').toHaveAccessibleName('Recent decisions, 20');
    await expect(decisions).toHaveCount(20);
    await expect(decisions.last().locator('.meta'), 'the 20th row dates from last year, so its time carries the year').toHaveText(`Jun 2, ${LAST_YEAR} at 14:12${DOT}Confidence 0.90${DOT}$0.0003`);
    const sideways = await page.locator('section.rail').evaluate((rail) => rail.scrollWidth - rail.clientWidth);
    expect(sideways, 'and the rail does not scroll sideways').toBeLessThanOrEqual(0);
    await expect(decisions.locator('.summary'), 'the newest first, the oldest cut, the turn decision left out').toHaveText(
      Array.from({ length: 20 }, (_unused, i) => summaryOf(stamp, 20 - i)),
    );

    const first = decisions.first();
    await expect(first.locator('app-outcome-chip'), 'line 1 holds the chip').toHaveText('Act');
    await expect(first.locator('.summary'), 'the summary').toHaveText(summaryOf(stamp, 20));
    await expect(first.locator('app-icon svg path[d="m6 9 6 6 6-6"]'), 'and the chevron down').toHaveCount(1);
    const button = first.getByRole('button');
    await expect(button, 'the row is a disclosure').toHaveAttribute('aria-expanded', 'false');
    await expect(first.locator('.reason'), 'line 2 is the first reason').toHaveText('zz first reason.');
    await expect(first.locator('.meta'), 'the meta line holds the time, the confidence and the cost').toHaveText(`12:20${DOT}Confidence 0.90${DOT}$0.0003`);

    await button.click();
    await expect(button, 'a press expands it').toHaveAttribute('aria-expanded', 'true');
    await expect(first.locator('.reason'), 'every reason line replaces line 2').toHaveText(['zz first reason.', 'zz second reason.']);
    await expect(first.locator('app-icon svg path[d="m18 15-6-6-6 6"]'), 'with the chevron up').toHaveCount(1);
    await button.press('Escape');
    await expect(button, 'Esc collapses it').toHaveAttribute('aria-expanded', 'false');
    await expect(button, 'and focus stays on the button').toBeFocused();

    const fallback = decisions.filter({ hasText: summaryOf(stamp, 10) });
    await expect(fallback.locator('app-outcome-chip'), 'a fallback shows Tell now').toHaveText('Tell now');
    await expect(fallback.locator('app-fallback-flag'), 'with the Fallback flag').toHaveText('Fallback');
    await expect(fallback.locator('.reason'), 'its sentence is the first line').toHaveText('The model declined to answer.');
    await expect(fallback.locator('.meta'), 'and it has no confidence').toHaveText(`12:10${DOT}$0.0003`);
    await expect(fallback.getByText('Confidence')).toHaveCount(0);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R9: a decision event puts the new decision first, the oldest leaves, and focus on the leaving row goes to the heading. */
test('R9: a decision event puts the new decision first, the oldest leaves, and focus on the leaving row goes to the heading', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const stamp = unique('R9');
    const rows = Array.from({ length: 20 }, (_unused, n) => ({
      outcome: 'act',
      summary: summaryOf(stamp, n),
      reasons: REASONS,
      confidence: 0.9,
      costUSD: 0.0003,
      recordedAt: today(`12:${String(n).padStart(2, '0')}:00`),
    }));
    refs.push(...(await seedDecisions(user, rows)));
    await open(page);
    const decisions = rail(page).locator('app-decision-row');
    await expect(decisions).toHaveCount(20);
    const oldest = decisions.nth(19);
    await expect(oldest.locator('.summary')).toHaveText(summaryOf(stamp, 0));
    await oldest.getByRole('button').focus();
    await expect(oldest.getByRole('button'), 'focus is on the 20th row\'s button').toBeFocused();

    const newest = await seedDecision(user, { outcome: 'act', summary: summaryOf(stamp, 30), reasons: REASONS, confidence: 0.9, costUSD: 0.0003, recordedAt: today('12:30:00') });
    refs.push(newest);
    await applied(page, await sinkEvent(user, 'decision.recorded', { ref: newest }));
    await expect(decisions.first().locator('.summary'), 'the new decision is first').toHaveText(summaryOf(stamp, 30), { timeout: ONE_UPDATE_MS });
    await expect(decisions, 'the list still holds twenty').toHaveCount(20);
    await expect(decisions.filter({ hasText: summaryOf(stamp, 0) }), 'the oldest left').toHaveCount(0);
    const heading = rail(page).getByRole('heading', { name: 'Recent decisions, 20' });
    await expect(heading, 'focus moved to the Recent decisions heading').toBeFocused();
    expect(await page.evaluate(() => document.activeElement?.id), 'which is document.activeElement').toBe('rail-heading-decisions');

    const before = await decisions.locator('.summary').allTextContents();
    const turn = await seedDecision(user, { outcome: 'act', summary: summaryOf(stamp, 40), recordedAt: today('12:40:00') }, 'turn');
    refs.push(turn);
    await applied(page, await sinkEvent(user, 'decision.recorded', { ref: turn }));
    expect(await decisions.locator('.summary').allTextContents(), 'a turn decision changes nothing').toEqual(before);
    await expect(heading).toBeFocused();
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R10: after live events the rail holds what a reload shows. */
test('R10: after live events the rail holds what a reload shows', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const stamp = unique('R10');
    const suffix = Date.now().toString(36);
    const tools = { staying: `zz_tool_staying_${suffix}`, leaving: `zz_tool_leaving_${suffix}`, added: `zz_tool_added_${suffix}` };
    const production = `Zz.Rail.${suffix}`;
    refs.push(await seedCheck(user, { production, displayName: `${stamp} Orders`, lastRunAt: today('12:00:00'), result: 'failed', finding: '50 new failures' }));
    const staying = await seedApproval(user, { kind: 'tool_call', toolName: tools.staying, dryRun: null });
    const leaving = await seedApproval(user, { kind: 'tool_call', toolName: tools.leaving, dryRun: null });
    refs.push(staying, leaving);
    refs.push(...(await seedDecisions(user, [0, 1, 2].map((n) => ({ outcome: 'act', summary: summaryOf(stamp, n), reasons: REASONS, confidence: 0.9, costUSD: 0.0003, recordedAt: today(`12:0${n}:00`) })))));
    await open(page);

    const added = await seedApproval(user, { kind: 'tool_call', toolName: tools.added, dryRun: null });
    refs.push(added);
    await sinkEvent(user, 'approval.raised', { ref: added });
    await setApprovalState(leaving, 'approved');
    await sinkEvent(user, 'approval.answered', { ref: leaving });
    // The decision is older than two that the store holds, so the live rail must sort by the time recorded to match a reload.
    const decided = await seedDecision(user, { outcome: 'digest', summary: summaryOf(stamp, 9), reasons: REASONS, confidence: 0.8, costUSD: 0.0005, recordedAt: today('12:01:30') });
    refs.push(decided);
    await applied(page, await sinkEvent(user, 'decision.recorded', { ref: decided }));

    await expect(headings(page).first(), 'the live rail holds two requests').toHaveAccessibleName('Approval requests, 2', { timeout: ONE_UPDATE_MS });
    await expect(headings(page).nth(3), 'and four decisions').toHaveAccessibleName('Recent decisions, 4', { timeout: ONE_UPDATE_MS });
    const live = plain(await rail(page).innerText());
    expect(live, 'the departed request is gone').not.toContain(tools.leaving);
    expect(live, 'and the others are there').toContain(tools.staying);
    expect(live).toContain(tools.added);

    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(headings(page).nth(3)).toHaveAccessibleName('Recent decisions, 4');
    expect(plain(await rail(page).innerText()), 'a reload shows the same rail').toBe(live);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R11: with Telegram included, the first section is the Telegram card with its README link. */
test('R11: with Telegram included, the first section is the Telegram card with its README link', async ({ page }) => {
  const before = await setTelegramIncluded(1);
  try {
    await open(page);
    const status = rail(page);
    await expect(headings(page).first(), 'the first section is Telegram, with no count').toHaveText('Telegram');
    await expect(headings(page).first().locator('[aria-hidden="true"]'), 'the Telegram heading has no count').toHaveCount(0);
    await expect(headings(page), 'then the four lists').toHaveCount(5);
    await expect(status.locator('app-telegram-card'), 'the card says it is not set up').toContainText('Telegram not set up');
    const link = status.getByRole('link', { name: 'How to set it up (opens in a new tab)', exact: true });
    await expect(link, 'with a link to set it up').toHaveCount(1);
    await expect(link, 'to the README\'s Telegram section').toHaveAttribute('href', 'https://github.com/jbrandtmse/OcuTalon#telegram');
    await expect(link, 'in a new tab').toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(page.locator('.banner-slot'), 'no banner appears').toBeEmpty();

    for (const [state, setUp] of [['rejected', false], ['on', true]] as const) {
      await page.route(`**${STATE}`, async (route) => {
        const response = await route.fetch();
        const body = (await response.json()) as { telegram: Record<string, unknown> };
        body.telegram = { ...body.telegram, included: true, state };
        await route.fulfill({ response, json: body });
      });
      await page.reload();
      await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
      await expect(headings(page).first(), `with the state ${state} the first section is still Telegram`).toHaveText('Telegram');
      await expect(status.locator('app-telegram-card'), `state ${state}: the card ${setUp ? 'shows nothing yet' : 'says it is not set up'}`).toHaveText(setUp ? '' : /^Telegram not set up\s*How to set it up/);
      await expect(link, `state ${state}: the link ${setUp ? 'is not there' : 'is there'}`).toHaveCount(setUp ? 0 : 1);
    }
  } finally {
    await setTelegramIncluded(before);
  }
});

/** R12: markup in a summary or a reminder shows as text. */
test('R12: markup in a summary or a reminder shows as text', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const stamp = unique('R12');
    const summary = `<i>zz</i> ${stamp} summary`;
    const reminder = `<b>zz</b> ${stamp} reminder`;
    refs.push(...(await seedDecisions(user, [{ outcome: 'act', summary, reasons: 'zz <u>reason</u>.', confidence: 0.9, costUSD: 0.0003, recordedAt: today('12:00:00') }])));
    refs.push(await seedReminder(user, { text: reminder }));
    await open(page);
    const status = rail(page);
    await expect(status.locator('app-decision-row .summary'), 'the summary shows as typed').toHaveText(summary);
    await expect(status.locator('li.row .lead'), 'and the reminder').toHaveText(reminder);
    await expect(status.locator('i, b, u'), 'no element was made from either').toHaveCount(0);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** R13: the clock ticks every minute while no countdown shows, so the day words roll over, and every second once a reminder arrives. */
test('R13: the clock ticks every minute while no countdown shows, and every second once a reminder arrives', async ({ page }) => {
  const { user } = fixtureUser('RAIL');
  const refs: string[] = [];
  try {
    const hour = 3_600_000;
    const start = Date.parse(today('12:00:00'));
    await page.clock.install({ time: start });
    await page.clock.setFixedTime(start);
    const tool = `zz_tool_clock_${Date.now().toString(36)}`;
    refs.push(await seedApproval(user, { kind: 'tool_call', toolName: tool, dryRun: null, raisedAt: iso(start, -60_000), expiresAt: iso(start, 22.5 * hour) }));
    await open(page);
    const meta = rowOf(page, tool).locator('.meta');
    await expect(meta, 'before midnight the request expires tomorrow').toHaveText(`Raised 11:59${DOT}expires tomorrow at 10:30`);

    await page.clock.setFixedTime(start + 13 * hour);
    await page.clock.runFor(60_000);
    await expect(meta, 'a minute on, the page is on the next date and the day words follow').toHaveText(new RegExp(`^Raised [A-Z][a-z]+ at 11:59${DOT}expires 10:30$`), { timeout: 3000 });

    const text = unique('R13').replace(/^zz /, 'zz tick ');
    await applied(page, await publishReminder(user, { text, dueAt: iso(start + 13 * hour, 59_000) }));
    const countdown = rowOf(page, text).locator('.countdown');
    await expect(countdown, 'a reminder that arrives after the load shows its countdown').toHaveText('in 59 s', { timeout: ONE_UPDATE_MS });
    await page.clock.setFixedTime(start + 13 * hour + 2000);
    await expect(countdown, 'and the clock now ticks every second').toHaveText('in 57 s', { timeout: 3000 });
  } finally {
    await cleanFixtureRows(refs);
  }
});
