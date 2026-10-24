import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { changeSnapshot, EVENTS, STATE } from '../support/api';
import {
  cleanFixtureRows,
  decideIsStub,
  fixtureUser,
  publishCheck,
  publishStatus,
  seedCheck,
  seedDecision,
  type StatusSlots,
} from '../support/iris';
import { announcementCount, announcements, plain, recordAnnouncements, tokenColor } from '../support/page';

/**
 * Story 2.10, the status banners (B1 to B12), in a real browser against a real stack. Every case signs in as the banners fixture user
 * that test-sign-in.sh created (OCUTALON_BANNERS_USER), whose session holds nothing but what the case seeds. A case turns a condition on
 * and off by publishing a status event on that user's own session stream through Live.Publish, which the page applies exactly as it
 * applies StatusMonitor's events on the instance stream (no spec publishes on the instance stream, whose counts api.spec pins), and
 * clears every condition it turned on in finally; its fixture rows are removed there too. A case that checks a live update waits until
 * the page has applied the Seq that the helper returned (the page's data-session-seq) and then asserts within one second. Every
 * stack of this build shows the no-key banner from its snapshot (the model key is not set in CI, and the Keys stub answers 0), so a
 * case never assumes an empty banner slot beyond that one banner. The browser runs in Asia/Kolkata with the en-GB locale, so a page
 * time (instance zone UTC) reads differently from the instance's: 12:00 UTC is 17:30.
 *
 * B7 to B12 are the QA cases of the story: the heartbeat that the snapshot holds (B7), a 12-hour browser on the online demo with all six
 * conditions from the snapshot (B8), a closed banner that returns when its slots change (B9), focus that only a leaving, focused banner
 * moves, and the Tab order (B10), a banner that a reloaded snapshot brings (B11), and the stack's size at the reference viewport and
 * below 1024px (B12). B7, B8, B11 and B12 take the conditions they start with from a changed /state or a changed poll; B8, B11 and B12
 * publish nothing, and B7 publishes only one check update and the clear.
 *
 * B13 to B16 are Story 2.11's connection tests: the page's own two banners, Reconnecting and Unreachable, for a page that loses contact.
 * They are described where they stand, after B12.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' });

/** A poll that a routed /events handler is still answering when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const README = 'https://github.com/jbrandtmse/OcuTalon#readme';
const TELEGRAM = 'https://github.com/jbrandtmse/OcuTalon#telegram';
const LIVE_REGIONS = '[aria-live], [role="log"], [role="status"], [role="alert"]';

/** The middle dot between the parts of a meta line, with its spaces. */
const DOT = ' \u00B7 ';

/** How long the page may take to apply an event after the helper returned: the live poll (1 to 2 s) and the render. */
const APPLIED_MS = 15_000;

/** The bound of "within one live update", counted from the page having applied the event. */
const ONE_UPDATE_MS = 1000;

/** A text no other case or run made. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** The date (UTC) the run began on: every time a case seeds falls on this one date, even in a run that crosses midnight. */
const DAY = new Date().toISOString().slice(0, 10);

/** The run's date with the time given, as a UTC ISO time. */
const today = (time: string): string => `${DAY}T${time}Z`;

/** The page's clock for a case that reads the rail's times: half past noon UTC on the run's date, 18:00 in Asia/Kolkata. */
const PAGE_NOON = (): number => Date.parse(today('12:30:00'));

/** The time of the conditions' slots: 12:00 UTC, which the page shows as 17:30. */
const T = '2026-10-23T12:00:00Z';

const mainOf = (page: Page): Locator => page.locator('main.main');
const slot = (page: Page): Locator => page.locator('.banner-slot');
const banner = (page: Page, id: string): Locator => slot(page).locator(`[data-banner="${id}"]`);
const banners = (page: Page): Locator => slot(page).locator('[data-banner]');
const rail = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });

/** The ids of the banners the slot holds, in order. */
const stack = (page: Page): Promise<Array<string | null>> => banners(page).evaluateAll((nodes) => nodes.map((node) => node.getAttribute('data-banner')));

/** Signs the banners user in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('BANNERS');
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
}

/** Waits until the page has applied the event of this Seq on the session's stream. */
async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-session-seq')), { message: `the page applied Seq ${seq}`, timeout: APPLIED_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** Turns a condition on (or off) on the user's session stream and waits until the page has applied it. */
async function turn(page: Page, user: string, condition: string, active: boolean, slots?: StatusSlots): Promise<void> {
  await applied(page, await publishStatus(user, { condition, active, slots }));
}

/** Turns these conditions off, each one on its own, for the finally of a case; one that fails to clear does not stop the others. */
async function clear(user: string, conditions: string[]): Promise<void> {
  for (const condition of conditions) {
    await publishStatus(user, { condition, active: false }).catch(() => undefined);
  }
}

/** The text of the no-key banner. */
const NO_KEY = 'OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon.';

/** The text of the Reset soon banner. */
const RESET = 'The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.';

/** The text of the banner for the heartbeat that last ran at 16:30 in the page's zone. */
const STALLED = 'Background checks have paused: the heartbeat last ran at 16:30. Watches and reminders may be late until it recovers.';

/** The Lucide path of the triangle-alert icon, and the line that only the circle-alert icon has. */
const TRIANGLE = 'svg path[d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"]';
const CIRCLE_ALERT = 'svg line[x1="12"][x2="12"][y1="8"][y2="12"]';

/** The colour of a variant's token pair, as the page paints it. */
const variantColors = async (page: Page, variant: 'warning' | 'danger' | 'info'): Promise<{ background: string; foreground: string; accent: string }> => ({
  background: await tokenColor(page, `--status-banner-${variant}-background`),
  foreground: await tokenColor(page, `--status-banner-${variant}-foreground`),
  accent: await tokenColor(page, `--status-banner-${variant}-accent`),
});

/** Asserts the look of a banner (UX-DR34): full width under the header, at least 44px tall, the variant's colours and a 4px accent. */
async function expectLook(page: Page, one: Locator, variant: 'warning' | 'danger' | 'info', what: string): Promise<void> {
  const colors = await variantColors(page, variant);
  await expect(one, `${what} has the ${variant} background`).toHaveCSS('background-color', colors.background);
  await expect(one, `${what}'s text is the ${variant} foreground`).toHaveCSS('color', colors.foreground);
  await expect(one, `${what} has a 4px left accent`).toHaveCSS('border-left-width', '4px');
  await expect(one, `${what}'s accent is the ${variant} accent`).toHaveCSS('border-left-color', colors.accent);
  await expect(one.locator('app-icon').first(), `${what}'s icon is in the accent colour`).toHaveCSS('color', colors.accent);
  await expect(one, `${what} is marked with its variant`).toHaveAttribute('data-variant', variant);
  const box = (await one.boundingBox())!;
  const viewport = await page.evaluate(() => document.documentElement.clientWidth);
  expect(box.height, `${what} is at least 44px tall`).toBeGreaterThanOrEqual(44);
  expect(Math.abs(box.width - viewport), `${what} spans the page`).toBeLessThanOrEqual(1);
  expect(box.x, `${what} starts at the left edge`).toBeLessThanOrEqual(1);
  const header = (await page.locator('app-header').boundingBox())!;
  expect(box.y, `${what} sits under the header`).toBeGreaterThanOrEqual(header.y + header.height - 1);
}

/** Asserts the action of a banner: one underlined link that opens a new tab and says so. */
async function expectAction(one: Locator, name: string, href: string, what: string): Promise<void> {
  const link = one.getByRole('link');
  await expect(link, `${what} has one action`).toHaveCount(1);
  await expect(link, `${what}'s action is named, with the new-tab words`).toHaveAccessibleName(`${name} (opens in a new tab)`);
  await expect(link, `${what}'s action leads to the README`).toHaveAttribute('href', href);
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
  await expect(link, `${what}'s action is underlined`).toHaveCSS('text-decoration-line', 'underline');
  await expect(link.locator('app-icon svg'), 'with the external-link icon').toHaveCount(1);
}

/** The summary of a seeded decision. */
const summaryOf = (stamp: string): string => `${stamp} decision`;

/** A fallback decision (a decide row) with this reason, for the rail. */
const fallbackDecision = (stamp: string, fallbackReason: string) => ({
  outcome: 'act',
  summary: summaryOf(stamp),
  reasons: 'zz first reason.',
  confidence: 0.9,
  costUSD: 0.0003,
  fallback: true,
  fallbackReason,
});

/** B1: with no model key, the page loads the unclosable warning banner from the snapshot, silently; decisions show the fallback flag. */
test('B1: with no model key the snapshot shows the no-key banner on load, unclosable and not announced', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const refs: string[] = [];
  try {
    const stamp = unique('B1');
    refs.push(await seedDecision(user, fallbackDecision(stamp, 'no_key')));
    await recordAnnouncements(page);
    await open(page);

    const one = banner(page, 'noModelKey');
    await expect(one, 'the no-key banner shows on load').toHaveCount(1);
    await expect(one.locator('.text'), 'with the exact text').toHaveText(NO_KEY);
    await expect(banners(page), 'and it is the only banner').toHaveCount(1);
    await expectLook(page, one, 'warning', 'the no-key banner');
    await expect(one.locator(TRIANGLE), 'with the triangle-alert icon').toHaveCount(1);
    await expectAction(one, 'How to set a key', README, 'the no-key banner');
    await expect(one.getByRole('button'), 'it cannot be closed').toHaveCount(0);
    await expect(slot(page).locator(LIVE_REGIONS), 'no banner is a live region').toHaveCount(0);
    await expect(slot(page), 'and the slot is not one').not.toHaveAttribute('aria-live', /.*/);
    await expect(one, 'a banner takes focus but is not in the tab order').toHaveAttribute('tabindex', '-1');

    await expect(page.getByRole('heading', { level: 2 }), 'no banner adds a heading').toHaveText(['Status', 'Chat']);
    await page.waitForTimeout(1500);
    expect(await announcements(page, NO_KEY), 'the banner of the first snapshot is not announced').toBe(0);

    const row = rail(page).locator('li.row').filter({ hasText: stamp });
    await expect(row.locator('app-fallback-flag'), 'the decision shows the fallback flag').toHaveText('Fallback');
    await expect(row.locator('.reason'), 'and says that no model key is set').toHaveText('No model key is set.');
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** B2: a stalled heartbeat shows the warning and the "(late)" marks within one live update, announced once, and both leave when it clears. */
test('B2: a stalled heartbeat shows its banner and the late marks, announced once, and they leave when it clears', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const refs: string[] = [];
  try {
    const stamp = unique('B2');
    refs.push(await seedCheck(user, { displayName: stamp, lastRunAt: today('10:00:00'), result: 'passed', finding: '' }));
    await page.clock.setFixedTime(PAGE_NOON());
    await recordAnnouncements(page);
    await open(page);
    const row = rail(page).locator('li.row').filter({ hasText: stamp });
    await expect(row.locator('.meta'), 'before the stall the check reads Last run 15:30').toHaveText(`Last run 15:30${DOT}Passed`);
    await expect(banner(page, 'heartbeatStalled')).toHaveCount(0);

    await turn(page, user, 'heartbeatStalled', true, { time: today('11:00:00') });
    const one = banner(page, 'heartbeatStalled');
    await expect(one, 'the banner appears within one live update').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(one.locator('.text'), 'its text has the page time of the last tick').toHaveText(STALLED);
    await expectLook(page, one, 'warning', 'the heartbeat banner');
    await expect(one.locator(TRIANGLE)).toHaveCount(1);
    await expect(one.getByRole('link'), 'it has no action').toHaveCount(0);
    await expect(one.getByRole('button'), 'and cannot be closed').toHaveCount(0);
    await expect(row.locator('.meta'), 'the check row reads Last run 15:30 (late)').toHaveText(`Last run 15:30 (late)${DOT}Passed`, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, STALLED), { message: 'it is announced', timeout: 5000 }).toBe(1);
    await page.waitForTimeout(2500);
    expect(await announcements(page, STALLED), 'and announced once').toBe(1);

    const heard = await announcementCount(page);
    await turn(page, user, 'heartbeatStalled', false);
    await expect(banner(page, 'heartbeatStalled'), 'clearing it removes the banner within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(row.locator('.meta'), 'and the late mark').toHaveText(`Last run 15:30${DOT}Passed`, { timeout: ONE_UPDATE_MS });
    await page.waitForTimeout(1500);
    expect(await announcementCount(page), 'clearing announces nothing, about any banner').toBe(heard);
  } finally {
    await clear(user, ['heartbeatStalled']);
    await cleanFixtureRows(refs);
  }
});

/** B3: the local cost cap shows the warning with the cap and no action, the composer stays usable, and a daily_cap decision reads its sentence. */
test('B3: the local cost limit shows the warning with the cap and no action, and the composer stays usable', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const refs: string[] = [];
  try {
    const stamp = unique('B3');
    refs.push(await seedDecision(user, fallbackDecision(stamp, 'daily_cap')));
    await open(page);
    // noModelKey comes from this case, so the order below holds whatever the stack's key state is.
    await turn(page, user, 'noModelKey', true);
    await turn(page, user, 'dailyCap', true, { cap: 20, time: T });

    const one = banner(page, 'costCap');
    await expect(one, 'the warning appears within one live update').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(banner(page, 'dailyCap'), 'and not the online demo\'s banner').toHaveCount(0);
    await expect(one.locator('.text')).toHaveText("OcuTalon has reached today's cost limit of $20.00. Decisions use fixed rules until 17:30.");
    await expectLook(page, one, 'warning', 'the cost-limit banner');
    await expect(one.locator(TRIANGLE)).toHaveCount(1);
    await expect(one.getByRole('link'), 'it has no action').toHaveCount(0);
    await expect(one, 'and no Budgets').not.toContainText('Budgets');
    await expect(one.getByRole('button'), 'and cannot be closed').toHaveCount(0);
    await expect(banner(page, 'noModelKey'), 'the no-key banner is still there, after it').toHaveCount(1);
    expect(await stack(page), 'in the catalog order').toEqual(['noModelKey', 'costCap']);

    const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
    const send = page.getByRole('button', { name: 'Send', exact: true });
    await field.fill('zz text for the composer');
    await expect(field, 'the composer takes text').toHaveValue('zz text for the composer');
    await expect(field).toBeEnabled();
    await expect(send, 'and Send is not disabled').not.toHaveAttribute('aria-disabled', 'true');
    await expect(send).toBeEnabled();
    await field.fill('');

    const row = rail(page).locator('li.row').filter({ hasText: stamp });
    await expect(row.locator('app-fallback-flag'), 'a decision with the daily_cap reason shows the flag').toHaveText('Fallback');
    await expect(row.locator('.reason'), 'and says that the cost limit has been reached').toHaveText("Today's cost limit has been reached.");

    await turn(page, user, 'dailyCap', false);
    await expect(banner(page, 'costCap'), 'lifting the cap removes the banner').toHaveCount(0, { timeout: ONE_UPDATE_MS });
  } finally {
    await clear(user, ['dailyCap', 'noModelKey']);
    await cleanFixtureRows(refs);
  }
});

/** B4: the online demo's cap, from the snapshot, is the danger banner with "Install it yourself" and a page time without a zone name (DW-29). */
test('B4: the online demo cap shows the danger banner with a page time and Install it yourself', async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['onlineDemo'] = true;
    snapshot['status'] = [{ condition: 'dailyCap', active: true, slots: { cap: 20, time: T } }];
  });
  await open(page);

  const one = banner(page, 'dailyCap');
  await expect(one, "the online demo's daily cap shows on load").toHaveCount(1);
  await expect(banner(page, 'costCap'), 'and not the local warning').toHaveCount(0);
  await expect(one.locator('.text')).toHaveText("The online demo has used today's model allowance. Decisions use fixed rules until 17:30.");
  const text = plain(await one.locator('.text').textContent());
  expect(text, 'the time is the browser\'s, with no zone name and no ET').not.toMatch(/ ET\b|IST|GMT|UTC|Asia|India/);
  await expectLook(page, one, 'danger', 'the online demo banner');
  await expect(one.locator(CIRCLE_ALERT), 'with the circle-alert icon').toHaveCount(1);
  await expectAction(one, 'Install it yourself', README, 'the online demo banner');
  await expect(one.getByRole('button'), 'it cannot be closed').toHaveCount(0);
  expect(await stack(page), 'it is the only banner').toEqual(['dailyCap']);

  const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
  const send = page.getByRole('button', { name: 'Send', exact: true });
  await field.fill('zz text for the composer');
  await expect(field, 'on the online demo the composer takes text too').toHaveValue('zz text for the composer');
  await expect(send, 'and Send is not disabled').not.toHaveAttribute('aria-disabled', 'true');
  await expect(send).toBeEnabled();
  await field.fill('');
});

/** B5: the stack in the catalog's order, with its variants and actions; only Reset soon closes; focus moves when a focused banner leaves. */
test('B5: the stack orders its banners, only Reset soon closes, and focus follows a banner that leaves', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const ALL = ['allowance', 'dailyCap', 'noModelKey', 'heartbeatStalled', 'telegramPaused', 'resetSoon'];
  try {
    await recordAnnouncements(page);
    await open(page);
    // The conditions come in another order than the catalog's, and noModelKey from this case, whatever the stack's key state is.
    await turn(page, user, 'resetSoon', true);
    await turn(page, user, 'telegramPaused', true, { time: T });
    await turn(page, user, 'heartbeatStalled', true, { time: today('11:00:00') });
    await turn(page, user, 'noModelKey', true);
    await turn(page, user, 'dailyCap', true, { cap: 20, time: T });
    await turn(page, user, 'allowance', true, { limit: 20, time: T });
    await expect
      .poll(() => stack(page), { message: 'the local order of the catalog', timeout: ONE_UPDATE_MS })
      .toEqual(['allowance', 'noModelKey', 'costCap', 'heartbeatStalled', 'telegramPaused', 'resetSoon']);

    const look = async (id: string, variant: 'danger' | 'warning', action?: [string, string]): Promise<void> => {
      const one = banner(page, id);
      await expect(one).toHaveAttribute('data-variant', variant);
      await expect(one.locator(variant === 'danger' ? CIRCLE_ALERT : TRIANGLE), `${id} has its icon`).toHaveCount(1);
      if (action) await expectAction(one, action[0], action[1], id);
      else await expect(one.getByRole('link'), `${id} has no action`).toHaveCount(0);
    };
    await look('allowance', 'danger', ['Install it yourself', README]);
    await look('noModelKey', 'warning', ['How to set a key', README]);
    await look('costCap', 'warning');
    await look('heartbeatStalled', 'warning');
    await look('telegramPaused', 'warning', ['Set up a bot', TELEGRAM]);
    await look('resetSoon', 'warning');
    await expect(banner(page, 'allowance').locator('.text'), 'the allowance text names the limit and the page time').toHaveText(
      "You've used this session's 20 messages for the hour (messages you send in the chat or Telegram). You can send more at 17:30.",
    );
    await expect(banner(page, 'telegramPaused').locator('.text')).toHaveText(
      'Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at 17:30. Each OcuTalon needs its own bot.',
    );
    await expect(banner(page, 'resetSoon').locator('.text')).toHaveText(RESET);

    const closes = slot(page).getByRole('button', { name: 'Close', exact: true });
    await expect(closes, 'only Reset soon has a Close').toHaveCount(1);
    await expect(banner(page, 'resetSoon').getByRole('button', { name: 'Close', exact: true })).toHaveCount(1);
    await expect.poll(() => announcements(page, RESET), { message: 'Reset soon was announced when it appeared', timeout: 5000 }).toBe(1);

    await closes.click();
    await expect(banner(page, 'resetSoon'), 'Close removes it').toHaveCount(0);
    await expect(banner(page, 'telegramPaused'), 'and focus goes to the banner before it, as nothing follows').toBeFocused();
    await turn(page, user, 'resetSoon', true);
    await page.waitForTimeout(ONE_UPDATE_MS);
    await expect(banner(page, 'resetSoon'), 'it stays closed while the condition holds with the same slots').toHaveCount(0);
    expect(await announcements(page, RESET), 'and is not announced again').toBe(1);
    await turn(page, user, 'resetSoon', false);
    await expect(banner(page, 'resetSoon'), 'it stays away when the condition clears').toHaveCount(0);
    await turn(page, user, 'resetSoon', true);
    await expect(banner(page, 'resetSoon'), 'and comes back when the condition starts again').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, RESET), { message: 'announced again', timeout: 5000 }).toBe(2);

    await banner(page, 'heartbeatStalled').focus();
    await expect(banner(page, 'heartbeatStalled')).toBeFocused();
    await turn(page, user, 'heartbeatStalled', false);
    await expect(banner(page, 'heartbeatStalled'), 'a focused banner clears').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(banner(page, 'telegramPaused'), 'and focus goes to the next banner').toBeFocused();

    await banner(page, 'telegramPaused').getByRole('link').focus();
    await turn(page, user, 'telegramPaused', false);
    await expect(banner(page, 'telegramPaused')).toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(banner(page, 'resetSoon'), 'the focus on a banner\'s action goes the same way, to the next banner').toBeFocused();

    await banner(page, 'allowance').focus();
    for (const condition of ALL) await turn(page, user, condition, false);
    await expect(banners(page), 'every condition cleared, so no banner is left').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(mainOf(page), 'and focus is on the main region').toBeFocused();
  } finally {
    await clear(user, ALL);
  }
});

/** B6: a start with no model key (FR-38): the banner from the real /state, and a reply with the fallback flag. Turns itself on with the real Decide. */
test('B6: the no-key start shows the banner from the real snapshot and replies that no model key is set', async ({ page }) => {
  test.skip(await decideIsStub(), 'Story 1.6 turns this on');
  await open(page);
  await expect(banner(page, 'noModelKey').locator('.text'), 'the banner shows on load from the real /state').toHaveText(NO_KEY);
  await expect(banner(page, 'noModelKey').getByRole('link')).toHaveAttribute('href', README);

  const text = unique('B6');
  const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
  const request = page.waitForRequest((candidate) => candidate.method() === 'POST' && new URL(candidate.url()).pathname === '/ocutalon/api/v1/messages');
  await field.fill(text);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  const clientId = ((await request).postDataJSON() as { clientId: string }).clientId;
  const reply = page.locator(`app-chat-panel [data-part="reply"][data-key="${clientId}"]`);
  await expect(reply.locator('.text'), 'the reply says that no model key is set').toHaveText("I couldn't answer that: no model key is set. Nothing was changed.", { timeout: 30_000 });
  await expect(reply.locator('app-fallback-flag'), 'with the fallback flag').toHaveText('Fallback');
});

/** The last time the heartbeat ran in the QA cases: 11:00 UTC, which a browser in Asia/Kolkata reads as 16:30 and one in New York as 7:00 AM. */
const HEARTBEAT = '2026-10-23T11:00:00Z';

/** The stack of a local install with all six conditions on, and the online demo's, where the daily cap takes the cost limit's place. */
const LOCAL_ORDER = ['allowance', 'noModelKey', 'costCap', 'heartbeatStalled', 'telegramPaused', 'resetSoon'];
const ONLINE_ORDER = ['allowance', 'dailyCap', 'noModelKey', 'heartbeatStalled', 'telegramPaused', 'resetSoon'];

/** The six conditions as a snapshot can hold them, in an order other than the catalog's. */
const sixConditions = (): Array<Record<string, unknown>> => [
  { condition: 'resetSoon', active: true },
  { condition: 'telegramPaused', active: true, slots: { time: T } },
  { condition: 'heartbeatStalled', active: true, slots: { time: HEARTBEAT } },
  { condition: 'noModelKey', active: true },
  { condition: 'dailyCap', active: true, slots: { cap: 20, time: T } },
  { condition: 'allowance', active: true, slots: { limit: 20, time: T } },
];

/** B7 (QA): a stalled heartbeat that the snapshot holds shows its banner and the late marks on load, silently; a clear takes both away. */
test('B7: a heartbeat stalled in the snapshot shows its banner and the late marks on load without an announcement, and a clear removes both', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const refs: string[] = [];
  try {
    const ran = unique('B7 ran');
    const never = unique('B7 never');
    const production = `Zz.Banners.${Date.now().toString(36)}`;
    refs.push(await seedCheck(user, { production: `${production}.A`, displayName: ran, lastRunAt: today('10:00:00'), result: 'passed', finding: '' }));
    refs.push(await seedCheck(user, { production: `${production}.B`, displayName: never }));
    await page.clock.setFixedTime(PAGE_NOON());
    await changeSnapshot(page, (snapshot) => {
      snapshot['status'] = [...(snapshot['status'] as unknown[]), { condition: 'heartbeatStalled', active: true, slots: { time: today('11:00:00') } }];
    });
    await recordAnnouncements(page);
    await open(page);

    const row = (name: string): Locator => rail(page).locator('li.row').filter({ hasText: name });
    const one = banner(page, 'heartbeatStalled');
    await expect(one, 'the snapshot\'s banner is there on load').toHaveCount(1);
    await expect(one.locator('.text'), 'with the page time of the last tick').toHaveText(STALLED);
    await expect(one.getByRole('link'), 'and no action').toHaveCount(0);
    await expect(row(ran).locator('.meta'), 'the check that has run reads (late) on load').toHaveText(`Last run 15:30 (late)${DOT}Passed`);
    await expect(row(never), 'a check that has not run is listed').toHaveCount(1);
    await expect(row(never), 'and has no last run to mark').not.toContainText('Last run');
    await expect(row(never)).not.toContainText('(late)');
    await page.waitForTimeout(2000);
    expect(await announcements(page, STALLED), 'the banner of the first snapshot is not announced').toBe(0);

    await applied(page, await publishCheck(user, { ref: refs[0]!, production: `${production}.A`, displayName: ran, lastRunAt: today('10:30:00'), result: 'passed', finding: '' }));
    await expect(row(ran).locator('.meta'), 'a check event while the heartbeat is stalled keeps the mark').toHaveText(`Last run 16:00 (late)${DOT}Passed`, { timeout: ONE_UPDATE_MS });

    const heard = await announcementCount(page);
    await turn(page, user, 'heartbeatStalled', false);
    await expect(banner(page, 'heartbeatStalled'), 'a clear removes the snapshot\'s banner within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(row(ran).locator('.meta'), 'and the late mark').toHaveText(`Last run 16:00${DOT}Passed`, { timeout: ONE_UPDATE_MS });
    await page.waitForTimeout(1500);
    expect(await announcementCount(page), 'a clear announces nothing, about any banner').toBe(heard);
  } finally {
    await clear(user, ['heartbeatStalled']);
    await cleanFixtureRows(refs);
  }
});

/**
 * B8 (QA): the online demo in a 12-hour browser outside the instance's zone (DW-29): all six conditions come from the snapshot, in an
 * order other than the catalog's; the stack has the daily cap second, the times are the browser's with AM or PM and no zone name,
 * and nothing is announced.
 */
test.describe('B8: a 12-hour browser in New York', () => {
  test.use({ timezoneId: 'America/New_York', locale: 'en-US' });

  test('B8: the online demo\'s stack from the snapshot has the daily cap second, the browser\'s own times and no announcement', async ({ page }) => {
    await recordAnnouncements(page);
    await changeSnapshot(page, (snapshot) => {
      snapshot['onlineDemo'] = true;
      snapshot['status'] = sixConditions();
    });
    await open(page);
    await expect.poll(() => stack(page), { message: 'the online demo\'s order of the catalog', timeout: ONE_UPDATE_MS }).toEqual(ONLINE_ORDER);

    const textOf = async (id: string): Promise<string> => plain(await banner(page, id).locator('.text').textContent());
    const texts = {
      allowance: "You've used this session's 20 messages for the hour (messages you send in the chat or Telegram). You can send more at 8:00 AM.",
      dailyCap: "The online demo has used today's model allowance. Decisions use fixed rules until 8:00 AM.",
      noModelKey: NO_KEY,
      heartbeatStalled: 'Background checks have paused: the heartbeat last ran at 7:00 AM. Watches and reminders may be late until it recovers.',
      telegramPaused: 'Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at 8:00 AM. Each OcuTalon needs its own bot.',
      resetSoon: RESET,
    };
    for (const id of ONLINE_ORDER) {
      expect(await textOf(id), `${id} reads as the catalog words it, with the browser's 12-hour time`).toBe(texts[id as keyof typeof texts]);
      expect(await textOf(id), `${id} names no zone`).not.toMatch(/\b(ET|EDT|EST|UTC|GMT)\b|New York|America/);
    }
    await expect(banner(page, 'allowance')).toHaveAttribute('data-variant', 'danger');
    await expect(banner(page, 'dailyCap')).toHaveAttribute('data-variant', 'danger');
    for (const id of ['noModelKey', 'heartbeatStalled', 'telegramPaused', 'resetSoon']) await expect(banner(page, id)).toHaveAttribute('data-variant', 'warning');
    await expect(banner(page, 'costCap'), 'and the local cost limit is not there').toHaveCount(0);
    await expect(slot(page).getByRole('button', { name: 'Close', exact: true }), 'only Reset soon has a Close').toHaveCount(1);
    await expect(banner(page, 'resetSoon').getByRole('button', { name: 'Close', exact: true })).toHaveCount(1);

    await page.waitForTimeout(2500);
    for (const id of ONLINE_ORDER) expect(await announcements(page, texts[id as keyof typeof texts]), `${id} came with the first snapshot, so it is not announced`).toBe(0);
  });
});

/** B9 (QA): a closed banner stays away while its condition holds with the same slots and returns, announced, when the slots change (it got worse). */
test('B9: a closed Reset soon stays away on the same slots and comes back, announced, when its slots change', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  try {
    await recordAnnouncements(page);
    await open(page);
    const one = banner(page, 'resetSoon');
    const close = one.getByRole('button', { name: 'Close', exact: true });

    await turn(page, user, 'resetSoon', true);
    await expect(one, 'Reset soon appears').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, RESET), { message: 'and is announced', timeout: 5000 }).toBe(1);
    await close.click();
    await expect(one, 'Close removes it').toHaveCount(0);

    await turn(page, user, 'resetSoon', true, { time: T });
    await expect(one, 'the same condition with a slot it did not have is worse, so it comes back within one live update').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, RESET), { message: 'announced again', timeout: 5000 }).toBe(2);

    await close.click();
    await expect(one, 'closed again').toHaveCount(0);
    await turn(page, user, 'resetSoon', true, { time: T });
    await page.waitForTimeout(ONE_UPDATE_MS);
    await expect(one, 'the same slots again: it stays closed').toHaveCount(0);
    expect(await announcements(page, RESET), 'and nothing is announced').toBe(2);

    await turn(page, user, 'resetSoon', true, { time: '2026-10-23T12:05:00Z' });
    await expect(one, 'other slots: it comes back').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, RESET), { message: 'announced a third time', timeout: 5000 }).toBe(3);
    await expect(close, 'with its Close').toHaveCount(1);
  } finally {
    await clear(user, ['resetSoon']);
  }
});

/**
 * B10 (QA): a banner that appears, or leaves without holding focus, never moves focus; the keyboard reaches a banner's action and Close
 * (the banners themselves are not Tab stops), Close works with Enter, and the focus then goes to the banner before it.
 */
test('B10: banners that appear or leave do not move focus, the keyboard reaches their action and Close, and Enter closes', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const ON = ['noModelKey', 'heartbeatStalled', 'telegramPaused', 'resetSoon'];
  try {
    await open(page);
    await turn(page, user, 'noModelKey', true);
    const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
    await field.focus();
    await expect(field).toBeFocused();

    await turn(page, user, 'heartbeatStalled', true, { time: HEARTBEAT });
    await expect(banner(page, 'heartbeatStalled'), 'a banner appears').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(field, 'and takes no focus').toBeFocused();
    await turn(page, user, 'telegramPaused', true, { time: T });
    await expect(banner(page, 'telegramPaused')).toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(field).toBeFocused();
    await turn(page, user, 'heartbeatStalled', false);
    await expect(banner(page, 'heartbeatStalled'), 'a banner that does not hold focus leaves').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(field, 'and focus stays where it was').toBeFocused();

    await turn(page, user, 'resetSoon', true);
    await expect(banner(page, 'resetSoon')).toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(field).toBeFocused();

    await page.locator('app-header button.header-button').last().focus();
    await page.keyboard.press('Tab');
    await expect(banner(page, 'noModelKey').getByRole('link'), 'Tab from the header reaches the first banner\'s action, not the banner').toBeFocused();
    await page.keyboard.press('Tab');
    await expect(banner(page, 'telegramPaused').getByRole('link'), 'then the next banner\'s action').toBeFocused();
    await page.keyboard.press('Tab');
    const close = banner(page, 'resetSoon').getByRole('button', { name: 'Close', exact: true });
    await expect(close, 'then Reset soon\'s Close').toBeFocused();
    await page.keyboard.press('Enter');
    await expect(banner(page, 'resetSoon'), 'Enter on Close closes the banner').toHaveCount(0);
    await expect(banner(page, 'telegramPaused'), 'and focus goes to the banner before it').toBeFocused();
  } finally {
    await clear(user, ON);
  }
});

/** B11 (QA): a banner that a reloaded snapshot brings (the poll names another epoch) is announced once; the banner it already showed is not announced. */
test('B11: a banner that a reloaded snapshot brings is announced once, and the one it already showed is not', async ({ page }) => {
  let loads = 0;
  await page.route(`**${STATE}`, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    loads += 1;
    // Both snapshots hold noModelKey, whatever the stack's key state is; only the second adds the heartbeat.
    const status = (body['status'] as Array<{ condition?: unknown }>).filter((entry) => entry.condition !== 'noModelKey');
    body['status'] = [
      ...status,
      { condition: 'noModelKey', active: true },
      ...(loads > 1 ? [{ condition: 'heartbeatStalled', active: true, slots: { time: today('11:00:00') } }] : []),
    ];
    await route.fulfill({ response, json: body });
  });
  let changed = false;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    if (changed) {
      await route.fulfill({ response });
      return;
    }
    changed = true;
    const body = (await response.json()) as Record<string, unknown>;
    body['epoch'] = 'ZzE2EBannerEpoch';
    await route.fulfill({ response, json: body });
  });
  await recordAnnouncements(page);
  await open(page);
  await expect(banner(page, 'noModelKey'), 'the first snapshot shows the no-key banner').toHaveCount(1);
  await expect(banner(page, 'heartbeatStalled'), 'the first snapshot has no heartbeat banner').toHaveCount(0);

  await expect(banner(page, 'heartbeatStalled'), 'the reloaded snapshot brings it').toHaveCount(1, { timeout: 15_000 });
  expect(loads, 'after the snapshot was loaded again, once').toBe(2);
  await expect.poll(() => announcements(page, STALLED), { message: 'it is announced', timeout: 5000 }).toBe(1);
  await page.waitForTimeout(2500);
  expect(await announcements(page, STALLED), 'once').toBe(1);
  await expect(banner(page, 'noModelKey'), 'the no-key banner is still shown').toHaveCount(1);
  expect(await announcements(page, NO_KEY), 'the no-key banner was in both snapshots, so it is never announced').toBe(0);
});

/** The size of the page and of each banner, as the page lays them out now. */
const measure = (page: Page): Promise<{ width: number; scrolls: number; banners: Array<{ id: string | null; height: number; left: number; width: number; sideways: number }> }> =>
  page.evaluate(() => {
    const root = document.documentElement;
    return {
      width: root.clientWidth,
      scrolls: root.scrollHeight - root.clientHeight,
      banners: Array.from(document.querySelectorAll('.banner-slot [data-banner]')).map((node) => {
        const box = node.getBoundingClientRect();
        return { id: node.getAttribute('data-banner'), height: box.height, left: box.left, width: box.width, sideways: node.scrollWidth - node.clientWidth };
      }),
    };
  });

/** B12 (QA): the full stack at the reference viewport leaves the page unscrolled and the composer in view; below 1024px every banner still spans the page and keeps 44px. */
test('B12: six banners at 1280x720 leave the page unscrolled and the composer in view, and every banner keeps its width and height below 1024px', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await changeSnapshot(page, (snapshot) => {
    snapshot['status'] = sixConditions();
  });
  await open(page);
  await expect.poll(() => stack(page), { message: 'the local order of the catalog', timeout: ONE_UPDATE_MS }).toEqual(LOCAL_ORDER);

  const expectSpan = (size: Awaited<ReturnType<typeof measure>>, what: string): void => {
    for (const one of size.banners) {
      expect(one.height, `${what}: ${one.id} is at least 44px tall`).toBeGreaterThanOrEqual(44);
      expect(Math.abs(one.width - size.width), `${what}: ${one.id} spans the page`).toBeLessThanOrEqual(1);
      expect(one.left, `${what}: ${one.id} starts at the left edge`).toBeLessThanOrEqual(1);
      expect(one.sideways, `${what}: ${one.id}'s text wraps and does not overflow`).toBeLessThanOrEqual(0);
    }
  };
  const wide = await measure(page);
  expect(wide.width).toBe(1280);
  expect(wide.scrolls, 'six banners do not make the page scroll at 1280x720: the routed page shrinks').toBeLessThanOrEqual(1);
  const send = page.getByRole('button', { name: 'Send', exact: true });
  await expect(send, 'and the composer is still in view').toBeInViewport();
  expect(await send.evaluate((node) => {
    const box = node.getBoundingClientRect();
    const top = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
    return top !== null && node.contains(top);
  }), 'with no banner over it').toBe(true);
  const slotBottom = await slot(page).evaluate((node) => node.getBoundingClientRect().bottom);
  const main = (await mainOf(page).boundingBox())!;
  const railBox = (await page.locator('section.rail').boundingBox())!;
  expect(main.y, 'the main region starts under the banners: they shrink the routed page and do not cover it').toBeGreaterThanOrEqual(slotBottom - 1);
  expect(railBox.y, 'and so does the Status region').toBeGreaterThanOrEqual(slotBottom - 1);
  expect(main.y + main.height, 'the main region ends inside the viewport').toBeLessThanOrEqual(721);
  expectSpan(wide, '1280x720');

  await page.setViewportSize({ width: 800, height: 900 });
  await expect.poll(async () => (await measure(page)).width, { message: 'the stacked layout is laid out' }).toBe(800);
  expectSpan(await measure(page), '800px');
});

/**
 * Story 2.11, the connection tests (B13 to B16). "The server is unreachable" is every request of the page to the API refused in the
 * browser (page.route); the case lifts that for the recovery. IRIS and its web server are never stopped. The page's clock is Playwright's
 * (page.clock): install() runs before sign-in, so time flows on its own, as it does for L6, and runFor() steps it. Time keeps flowing
 * between two steps, so a check leaves at least 1.5 s either side of a threshold: the page counts its 10 s and its 30 s from its last
 * answer, which came one poll delay (1 s) or a little more before the first request that was refused. A check that a banner has come
 * waits ONE_UPDATE_MS, not the default, because the page's clock would run on while it waited. contact-watch.test.mjs pins the exact
 * thresholds.
 */

/** The texts of the two banners that the page raises for itself. */
const RECONNECTING = 'Reconnecting\u2026 New messages may be delayed.';
const UNREACHABLE = "Can't reach OcuTalon. Retrying every 10 seconds.";

/** The Lucide path that only the info icon has. */
const INFO = 'svg path[d="M12 16v-4"]';

/** The title of the sign-in page. */
const SIGN_IN_TITLE = 'Sign in \u00b7 OcuTalon';

/** Every request of the page to the API, the page's /events polls, and the call that ends the session. */
const API_REQUESTS = /\/ocutalon\/api\/v1\//;
const EVENT_REQUESTS = /\/ocutalon\/api\/v1\/events\?/;
const STATE_REQUESTS = /\/ocutalon\/api\/v1\/state(?:\?|$)/;
const END = '/ocutalon/api/v1/session/end';

/** The page's own banners that hold now. */
const ownBanners = (page: Page): Locator => slot(page).locator('[data-banner="reconnecting"], [data-banner="unreachable"]');

/** The server is unreachable: every request of the page to the API is refused. attempts() counts the /events requests; lift() ends it. */
async function refuseApi(page: Page): Promise<{ attempts: () => number; lift: () => Promise<void> }> {
  let attempts = 0;
  const refuse = async (route: Route): Promise<void> => {
    if (new URL(route.request().url()).pathname === EVENTS) attempts += 1;
    await route.abort('connectionrefused').catch(() => undefined);
  };
  await page.route(API_REQUESTS, refuse);
  return { attempts: () => attempts, lift: () => page.unroute(API_REQUESTS, refuse) };
}

/** Waits until the page has asked once and been refused, so that its last answer is behind it. */
async function refused(outage: { attempts: () => number }): Promise<void> {
  await expect.poll(() => outage.attempts(), { message: 'the page asks again and is refused', intervals: [50] }).toBeGreaterThanOrEqual(1);
}

/** Moves the page's clock on by this many seconds, a second at a time, so that the page handles each answer or refusal between two steps. */
async function runSteps(page: Page, seconds: number): Promise<void> {
  for (let second = 0; second < seconds; second += 1) await page.clock.runFor(1000);
}

/**
 * Before the page's scripts run: records the ids of the banners that the slot holds, in order, after each change of the page that changes
 * them, as window.stacks, so a test can tell that two banners left and came in the same update.
 */
async function recordStacks(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const stacks: string[][] = [];
    (window as unknown as { stacks: string[][] }).stacks = stacks;
    new MutationObserver(() => {
      const now = Array.from(document.querySelectorAll('.banner-slot [data-banner]')).map((node) => node.getAttribute('data-banner') ?? '');
      if (JSON.stringify(now) !== JSON.stringify(stacks[stacks.length - 1] ?? [])) stacks.push(now);
    }).observe(document, { subtree: true, childList: true });
  });
}

/** The stacks that recordStacks has seen, in order. */
const stacksSeen = (page: Page): Promise<string[][]> => page.evaluate(() => (window as unknown as { stacks: string[][] }).stacks);

/**
 * B13: with the server unreachable, Reconnecting shows after 10 s with no answer (closable, info, last) and is announced once; at 30 s
 * Unreachable replaces it (danger, before the warnings, no Close), is announced once and takes the focus that Reconnecting held; from then
 * on the page asks every 10 s.
 */
test('B13: with the server unreachable the page shows Reconnecting at 10 s and Unreachable at 30 s, and then asks every 10 s', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  try {
    await recordAnnouncements(page);
    await page.clock.install();
    await open(page);
    // noModelKey comes from this case, so the order below holds whatever the stack's key state is.
    await turn(page, user, 'noModelKey', true);
    await expect(ownBanners(page), 'a page that is being answered has no banner of its own').toHaveCount(0);

    const outage = await refuseApi(page);
    await refused(outage);
    await runSteps(page, 4);
    await expect(ownBanners(page), 'before 10 s with no answer there is no banner of its own').toHaveCount(0);

    await runSteps(page, 7);
    const reconnecting = banner(page, 'reconnecting');
    await expect(reconnecting, 'after 10 s Reconnecting shows').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(reconnecting.locator('.text'), 'with the catalog\'s words').toHaveText(RECONNECTING);
    await expectLook(page, reconnecting, 'info', 'the Reconnecting banner');
    await expect(reconnecting.locator(INFO), 'with the info icon').toHaveCount(1);
    await expect(reconnecting.getByRole('link'), 'it has no action').toHaveCount(0);
    const close = reconnecting.getByRole('button', { name: 'Close', exact: true });
    await expect(close, 'and can be closed').toHaveCount(1);
    expect(await stack(page), 'it is last in the stack').toEqual(['noModelKey', 'reconnecting']);
    await expect.poll(() => announcements(page, RECONNECTING), { message: 'it is announced', timeout: 5000 }).toBe(1);
    await close.focus();
    await expect(close, 'focus is on its Close').toBeFocused();

    await runSteps(page, 10);
    await expect(reconnecting, 'before 30 s Reconnecting is still there').toHaveCount(1);
    await expect(banner(page, 'unreachable'), 'and Unreachable is not').toHaveCount(0);

    await runSteps(page, 11);
    const unreachable = banner(page, 'unreachable');
    await expect(unreachable, 'after 30 s Unreachable shows').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(reconnecting, 'in the place of Reconnecting').toHaveCount(0);
    await expect(unreachable.locator('.text'), 'with the catalog\'s words').toHaveText(UNREACHABLE);
    await expectLook(page, unreachable, 'danger', 'the Unreachable banner');
    await expect(unreachable.locator(CIRCLE_ALERT), 'with the circle-alert icon').toHaveCount(1);
    await expect(unreachable.getByRole('button'), 'it cannot be closed').toHaveCount(0);
    await expect(unreachable.getByRole('link'), 'and has no action').toHaveCount(0);
    expect(await stack(page), 'it sits before the warnings').toEqual(['unreachable', 'noModelKey']);
    await expect(unreachable, 'focus moved to the banner that replaced the one that held it').toBeFocused();
    await expect.poll(() => announcements(page, UNREACHABLE), { message: 'it is announced', timeout: 5000 }).toBe(1);
    expect(await announcements(page, RECONNECTING), 'Reconnecting was announced once and is not announced again').toBe(1);

    const before = outage.attempts();
    await runSteps(page, 20);
    const made = outage.attempts() - before;
    expect(made, 'from then on the page asks every 10 s, twice or three times in 20 s (a second apart it would be about 20)').toBeGreaterThanOrEqual(2);
    expect(made, 'twice or three times in 20 s').toBeLessThanOrEqual(3);
    await expect(unreachable, 'and the banner stays').toHaveCount(1);
    expect(await announcements(page, UNREACHABLE), 'announced once').toBe(1);
  } finally {
    await clear(user, ['noModelKey']);
  }
});

/**
 * B14: the first answer after an outage brings the events missed and both banners leave in that same update without a word; a Reconnecting
 * that was closed stays away for the rest of its outage and shows, announced, in the next one.
 */
test('B14: after the outage the first answer brings the missed event and clears the banners silently, and a closed Reconnecting returns at the next outage', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  try {
    await recordAnnouncements(page);
    await recordStacks(page);
    await page.clock.install();
    await open(page);
    await turn(page, user, 'noModelKey', true);

    const outage = await refuseApi(page);
    await refused(outage);
    await runSteps(page, 13);
    const reconnecting = banner(page, 'reconnecting');
    await expect(reconnecting, 'at about 15 s Reconnecting shows').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, RECONNECTING), { message: 'it is announced', timeout: 5000 }).toBe(1);
    await reconnecting.getByRole('button', { name: 'Close', exact: true }).click();
    await expect(reconnecting, 'Close removes it').toHaveCount(0);
    await expect(banner(page, 'noModelKey'), 'focus goes to the banner before it, as no banner replaces Reconnecting yet').toBeFocused();

    await runSteps(page, 10);
    await expect(ownBanners(page), 'at about 25 s it is still away, and Unreachable is not there yet').toHaveCount(0);
    await runSteps(page, 8);
    await expect(banner(page, 'unreachable'), 'at 30 s Unreachable shows, though Reconnecting was closed').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    expect(await stack(page)).toEqual(['unreachable', 'noModelKey']);

    // The server publishes while the page cannot hear it.
    await publishStatus(user, { condition: 'heartbeatStalled', active: true, slots: { time: today('11:00:00') } });
    await expect(banner(page, 'heartbeatStalled'), 'the page has not heard of it').toHaveCount(0);

    const heard = await announcementCount(page);
    await outage.lift();
    await page.clock.runFor(10_000);
    await expect(banner(page, 'heartbeatStalled'), 'the first answer brings the event').toHaveCount(1, { timeout: APPLIED_MS });
    await expect(ownBanners(page), 'and Unreachable has left').toHaveCount(0);
    const seen = await stacksSeen(page);
    const arrived = seen.findIndex((one) => one.includes('heartbeatStalled'));
    expect(seen[arrived - 1], 'the stack before that update has Unreachable').toEqual(['unreachable', 'noModelKey']);
    expect(seen[arrived], 'the heartbeat banner came and Unreachable left in the same update').toEqual(['noModelKey', 'heartbeatStalled']);
    await expect.poll(() => announcements(page, STALLED), { message: 'the new banner is announced', timeout: 5000 }).toBe(1);
    await page.waitForTimeout(1500);
    expect(await announcementCount(page), 'and nothing else is: the clear of Unreachable is silent').toBe(heard + 1);

    const second = await refuseApi(page);
    await refused(second);
    await runSteps(page, 13);
    await expect(banner(page, 'reconnecting'), 'in the next outage Reconnecting shows again').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, RECONNECTING), { message: 'and is announced again', timeout: 5000 }).toBe(2);
    expect(await stack(page), 'last, after the heartbeat banner').toEqual(['noModelKey', 'heartbeatStalled', 'reconnecting']);
  } finally {
    await clear(user, ['heartbeatStalled', 'noModelKey']);
  }
});

/**
 * B15: the first answer after an outage skips a Seq, so the page loads the snapshot again, once; the row made during the outage shows,
 * and both banners are gone with it, not at the next poll (which would be up to 10 s on).
 */
test('B15: a skipped Seq after the outage loads the snapshot again, once, and the banners clear with it', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const refs: string[] = [];
  try {
    const stamp = unique('B15');
    let states = 0;
    page.on('request', (request) => {
      if (new URL(request.url()).pathname === STATE) states += 1;
    });
    await page.clock.install();
    await open(page);
    // A poll has been answered before the outage begins, so the page has more than its snapshot to count from.
    await turn(page, user, 'noModelKey', true);
    expect(states, 'the page loaded its snapshot once').toBe(1);

    const outage = await refuseApi(page);
    await refused(outage);
    await runSteps(page, 33);
    await expect(banner(page, 'unreachable'), 'after 30 s Unreachable shows').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    refs.push(await seedCheck(user, { displayName: stamp, lastRunAt: today('10:00:00'), result: 'passed', finding: '' }));
    const row = rail(page).locator('li.row').filter({ hasText: stamp });
    await expect(row, 'the page has not heard of the check').toHaveCount(0);

    // The first poll that is answered carries a Seq two past the cursor, as L3's does.
    let skipped = false;
    await page.route(EVENT_REQUESTS, async (route) => {
      const response = await route.fetch();
      if (skipped) {
        await route.fulfill({ response });
        return;
      }
      skipped = true;
      const body = (await response.json()) as { events: Array<Record<string, unknown>> };
      const after = Number(new URL(route.request().url()).searchParams.get('after'));
      body.events.push({ seq: after + 2, stream: 'session', ts: '2030-01-01T00:00:00Z', type: 'reminder', payload: { ref: 'ZzE2EBannerSkip', state: 'pending' } });
      await route.fulfill({ response, json: body });
    });
    await outage.lift();
    await page.clock.runFor(10_000);

    await expect.poll(() => states, { message: 'the skipped Seq loads the snapshot again', timeout: APPLIED_MS }).toBe(2);
    await expect(row, 'the check made during the outage shows').toHaveCount(1, { timeout: APPLIED_MS });
    await expect(ownBanners(page), 'and both banners are gone within one live update of that').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(mainOf(page), 'the page stayed loaded').toHaveAttribute('data-snapshot', 'loaded');
    await page.waitForTimeout(2500);
    expect(states, 'and the snapshot was loaded once more, not again').toBe(2);
  } finally {
    await clear(user, ['noModelKey']);
    await cleanFixtureRows(refs);
  }
});

/**
 * B16: what is not lost contact. A 503 is an answer (the busy state is the server speaking): 40 s of 503s show no banner and the page keeps
 * asking every second or two. A 500 is not (the contrast): Reconnecting shows after 10 s. A poll that finds a skipped Seq is not an answer
 * until the snapshot it reloads has been taken in: while that reload is out Reconnecting stays, and a 503 of the reload is the answer that
 * clears it. A page that stopped on purpose claims no lost contact: Sign out takes the banner away at once, and 35 s on, nothing is asked
 * and nothing shows.
 */
test('B16: a 503 is not lost contact, a 500 is, and a page that signed out claims none', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  await page.clock.install();
  await open(page);

  let attempts = 0;
  let answer: 'busy' | 'error' | 'skip' = 'busy';
  await page.route(EVENT_REQUESTS, async (route) => {
    attempts += 1;
    if (answer === 'skip') {
      answer = 'error';
      const response = await route.fetch();
      const body = (await response.json()) as { events: Array<Record<string, unknown>> };
      const after = Number(new URL(route.request().url()).searchParams.get('after'));
      body.events.push({ seq: after + 2, stream: 'session', ts: '2030-01-01T00:00:00Z', type: 'reminder', payload: { ref: 'ZzE2EBannerSkip', state: 'pending' } });
      await route.fulfill({ response, json: body });
      return;
    }
    await route.fulfill({
      status: answer === 'busy' ? 503 : 500,
      json: { error: { code: answer === 'busy' ? 'busy' : 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } },
    });
  });
  await runSteps(page, 40);
  expect(attempts, 'for 40 s of 503s the page keeps asking every second or two (the unreachable page would ask about 4 times)').toBeGreaterThanOrEqual(15);
  await expect(ownBanners(page), 'a 503 is an answer: no banner of its own').toHaveCount(0);

  answer = 'error';
  await runSteps(page, 12);
  await expect(banner(page, 'reconnecting'), 'the same route answering 500: after 10 s Reconnecting shows').toHaveCount(1, { timeout: ONE_UPDATE_MS });

  let reloads = 0;
  let answerReload: () => void = () => undefined;
  const reloadHeld = new Promise<void>((resolve) => {
    answerReload = resolve;
  });
  await page.route(STATE_REQUESTS, async (route) => {
    reloads += 1;
    await reloadHeld;
    await route.fulfill({ status: 503, json: { error: { code: 'busy', message: 'Something went wrong inside OcuTalon. Try again.' } } }).catch(() => undefined);
  });
  try {
    answer = 'skip';
    await expect.poll(() => reloads, { message: 'the poll with the skipped Seq makes the page load the snapshot again', timeout: APPLIED_MS }).toBe(1);
    await runSteps(page, 3);
    expect(await banner(page, 'reconnecting').count(), 'while the reload is out nothing has answered: Reconnecting stays').toBe(1);
    answerReload();
    await expect(ownBanners(page), 'a 503 of the reload is an answer: Reconnecting leaves').toHaveCount(0, { timeout: ONE_UPDATE_MS });
  } finally {
    answerReload();
  }
  await page.unroute(STATE_REQUESTS);
  await runSteps(page, 12);
  await expect(banner(page, 'reconnecting'), 'with the 500s going on, it comes back after 10 s').toHaveCount(1, { timeout: ONE_UPDATE_MS });

  let ending = 0;
  let release: () => void = () => undefined;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route(`**${END}`, async (route) => {
    ending += 1;
    await held;
    await route.continue().catch(() => undefined);
  });
  try {
    await page.getByRole('button', { name: user, exact: true }).click();
    await page.getByRole('menuitem', { name: 'Sign out' }).click();
    await expect.poll(() => ending, { message: 'Sign out asked the server to end the session, which is held' }).toBe(1);
    await expect(ownBanners(page), 'a stopped page claims no lost contact: Reconnecting leaves at once').toHaveCount(0, { timeout: ONE_UPDATE_MS });

    const asked = attempts;
    await runSteps(page, 35);
    expect(attempts, 'a stopped page asks nothing').toBe(asked);
    await expect(ownBanners(page), 'and shows no banner however long nothing answers').toHaveCount(0);
  } finally {
    release();
  }
  await expect(page, 'when the server answers, the sign-in page shows').toHaveTitle(SIGN_IN_TITLE);
});
