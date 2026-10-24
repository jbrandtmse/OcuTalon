import { expect, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import {
  cleanFixtureRows,
  fixtureUser,
  publishReminder,
  publishStatus,
  seedApproval,
  seedCheck,
  seedDecision,
  seedIncident,
  seedTurns,
  turnRows,
} from './iris';

/**
 * What the floor specs (web/e2e/floor/) share: the floor user's page and its regions, and the one page that K5, W1 and W2 read,
 * with a row of every rail kind (each with a trace link), a done turn whose reply holds a link and whose strip
 * shows a chip and the Fallback flag, and the no-key and Reset soon banners (the stack has no model key, so the no-key banner is
 * there; Reset soon is published once the page has loaded, because a session's status events reach the page only live). Every row it
 * makes is recorded in the caller's `refs`, for cleanFixtureRows, and the condition it publishes is turned off by `clearFullPage`.
 */

/** How long a card may take to reach the page after the send returns: the route, the live poll (1 to 2 s) and the render. */
export const CARD_MS = 15_000;

/** The header of a trace that no run made: a link only needs an address to open. */
export const HEADER = 4242;

/** A text no other case or run made. */
export const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** An ISO time to the second, the given number of milliseconds from now. */
export const inMs = (ms: number): string => new Date(Date.now() + ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

export const mainOf = (page: Page): Locator => page.locator('main.main');
export const railOf = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
export const composerOf = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
export const rowOf = (page: Page, marker: string): Locator => railOf(page).locator('li.row').filter({ hasText: marker });
export const replyOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="reply"][data-key="${key}"]`);
export const banner = (page: Page, id: string): Locator => page.locator(`app-banner-stack [data-banner="${id}"]`);

/**
 * Returns once the page has rendered what a key press changed: after two animation frames and a task. A page that handles a key
 * changes its state at once but draws it a moment later, so a case that expects a key to change nothing looks after this wait, not
 * before it.
 */
export function settled(page: Page): Promise<void> {
  return page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 0)))));
}

/** Signs the floor user in and waits for the loaded page with its composer. */
export async function openFloor(page: Page): Promise<void> {
  const { user, password } = fixtureUser('FLOOR');
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** Waits until the page has applied the event of this Seq on the session's stream. */
export async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-session-seq')), { message: `the page applied Seq ${seq}`, timeout: CARD_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** What seedFullPage made: the marker of its texts, and the reply's key. */
export interface FullPage {
  stamp: string;
  /** The Ref of the done turn; its reply is `replyOf(page, turn)`. */
  turn: string;
  /** The summary of the rail's decision row. */
  summary: string;
  /** The Ref of the approval request, whose rail row carries no text of the case: its row is `li.row[data-row-key="approvals:<ref>"]`. */
  approval: string;
}

/**
 * Seeds the rows of the full page into the user's own session, before the page loads: a check with its latest run's trace, an approval
 * request of an incident with a trace, a decision with a trace session, a done turn whose reply holds a markdown link and whose strip
 * shows Tell now and the Fallback flag. The turn has a reply decision only: a turn's attention decision would stay in the rail's
 * Recent decisions. The turn and its decision are recorded in `refs` too. The reminder, which only an event can give a trace target, and Reset soon come with
 * `addReminder` and `addResetSoon` once the page has loaded.
 */
export async function seedFullPage(user: string, refs: string[]): Promise<FullPage> {
  const stamp = unique('full').replace(/ /g, '-');
  refs.push(await seedCheck(user, { namespace: 'OCUTALON', production: `Zz.Floor.${stamp.slice(-8)}`, displayName: `zz check ${stamp}`, lastRunAt: inMs(-60_000), result: 'passed', finding: 'zz finding', lastRunHeaderId: HEADER }));
  const incident = await seedIncident(user, { traceHeaderId: HEADER });
  refs.push(incident);
  const approval = await seedApproval(user, { incidentRef: incident, dryRun: { affected: 3, itemNoun: { one: 'order', other: 'orders' } } });
  refs.push(approval);
  const summary = `zz decision ${stamp}`;
  refs.push(await seedDecision(user, { outcome: 'act', summary, reasons: 'zz first reason.\nzz second reason.', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4242 }));
  const seeded = await seedTurns(user, [
    {
      createdAt: '2019-02-01T10:00:00Z',
      text: `zz question ${stamp}`,
      replyText: 'zz See [the guide](https://example.com/guide) here. Second sentence.',
      turn: { outcome: 'tellnow', fallback: true, fallbackReason: 'empty', reasons: 'Fixed rules chose this.', confidence: 0.5, costUSD: 0.0003 },
    },
  ]);
  refs.push(...turnRows(seeded));
  return { stamp, turn: seeded.refs[0]!, summary, approval };
}

/** Publishes a pending reminder with a trace target, once the page has loaded, and waits until the page shows its row. Returns its text. */
export async function addReminder(page: Page, user: string, stamp: string): Promise<string> {
  const text = `zz reminder ${stamp}`;
  await applied(page, await publishReminder(user, { ref: `ZzFloor${stamp.replace(/[^A-Za-z0-9]/g, '')}`, text, dueAt: inMs(3_600_000), traceHeaderId: HEADER, traceNamespace: 'OCUTALON' }));
  await expect(rowOf(page, text).locator('app-trace-link a'), 'the reminder row carries a trace link').toHaveCount(1, { timeout: CARD_MS });
  return text;
}

/** Publishes Reset soon, once the page has loaded, and waits until the page shows its banner. */
export async function addResetSoon(page: Page, user: string): Promise<void> {
  await applied(page, await publishStatus(user, { condition: 'resetSoon', active: true }));
  await expect(banner(page, 'resetSoon'), 'Reset soon shows').toHaveCount(1, { timeout: CARD_MS });
}

/** Turns Reset soon off and removes the rows of the full page. */
export async function clearFullPage(user: string, refs: string[]): Promise<void> {
  await publishStatus(user, { condition: 'resetSoon', active: false });
  await cleanFixtureRows(refs);
}
