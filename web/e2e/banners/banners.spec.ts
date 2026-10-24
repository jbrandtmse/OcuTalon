import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { changeSnapshot } from '../support/api';
import {
  cleanFixtureRows,
  decideIsStub,
  fixtureUser,
  publishStatus,
  seedCheck,
  seedDecision,
  type StatusSlots,
} from '../support/iris';
import { announcements, plain, recordAnnouncements, tokenColor } from '../support/page';

/**
 * Story 2.10, the status banners (B1 to B6), in a real browser against a real stack. Every case signs in as the banners fixture user
 * that test-sign-in.sh created (OCUTALON_BANNERS_USER), whose session holds nothing but what the case seeds. A case turns a condition on
 * and off by publishing a status event on that user's own session stream through Live.Publish, which the page applies exactly as it
 * applies StatusMonitor's events on the instance stream (no spec publishes on the instance stream, whose counts api.spec pins), and
 * clears every condition it turned on in finally; its fixture rows are removed there too. A case that checks a live update waits until
 * the page has applied the Seq that the helper returned (the page's data-session-seq) and then asserts within one second. Every
 * stack of this build shows the no-key banner from its snapshot (the model key is not set in CI, and the Keys stub answers 0), so a
 * case never assumes an empty banner slot beyond that one banner. The browser runs in Asia/Kolkata with the en-GB locale, so a page
 * time (instance zone UTC) reads differently from the instance's: 12:00 UTC is 17:30.
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

    await turn(page, user, 'heartbeatStalled', false);
    await expect(banner(page, 'heartbeatStalled'), 'clearing it removes the banner within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(row.locator('.meta'), 'and the late mark').toHaveText(`Last run 15:30${DOT}Passed`, { timeout: ONE_UPDATE_MS });
    expect(await announcements(page, STALLED), 'clearing announces nothing').toBe(1);
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
    await clear(user, ['dailyCap']);
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
});

/** B5: the stack in the catalog's order, with its variants and actions; only Reset soon closes; focus moves when a focused banner leaves. */
test('B5: the stack orders its banners, only Reset soon closes, and focus follows a banner that leaves', async ({ page }) => {
  const { user } = fixtureUser('BANNERS');
  const ALL = ['allowance', 'dailyCap', 'noModelKey', 'heartbeatStalled', 'telegramPaused', 'resetSoon'];
  const RESET = 'The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.';
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
