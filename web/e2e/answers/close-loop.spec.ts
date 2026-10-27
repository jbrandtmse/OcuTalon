import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { post } from '../support/api';
import { DRY_RUN, TOMORROW_AT_1413, incidentOf, refOf, today, type RequestFields } from '../support/approvals';
import { dropPhone, phoneMessage } from '../support/devices';
import { CARD_MS, applied, composerOf, inMs, mainOf } from '../support/floor';
import {
  cleanFixtureRows,
  doubleCommands,
  fixtureUser,
  incidentState,
  publishIncident,
  restoreIncidentManager,
  seedApproval,
  seedCheck,
  seedIncident,
  seedOtherSession,
  sendNotification,
  sinkEvent,
  useIncidentManagerDouble,
  type ApprovalFields,
} from '../support/iris';
import { announcedTexts, announcements, plain, recordAnnouncements, tokenColor } from '../support/page';

/**
 * Story 6.4, the endings of an incident (C1 to C10; FR-8, FR-24, AD-1, AD-4, AD-15, AD-16), in a real browser against a real stack, as
 * the answers user ANSWERS (OCUTALON_ANSWERS_USER, with the role OcuTalonUser; the stack is in demo mode, its instance zone is UTC and
 * the browser's is UTC and en-GB; the page's clock is the real one). The IncidentManager item of the production is the fixture double
 * (Test.Demo.IncidentManagerDouble, put there by useIncidentManagerDouble for the spec's run and put back after it): it answers the
 * dismissal that the page posts, as the real item will, by closing the incident's row and publishing its closed view. An incident card
 * is made as IncidentManager will make it (an `incident` event, publishIncident), with a row (seedIncident) where the case presses
 * Dismiss, because the route checks the row's visibility first; a request is a fixture row (seedApproval) whose `approval` event reaches
 * the page through BridgeSink (sinkEvent). A case's rows and phone messages are its own and are removed in finally.
 * C1 is a finished fix: the result band, the phone's result message and Dismiss; C2 the partial results in one band; C3 the band while
 * the fix still runs and then final; C4 two requests, a Reject and Dismiss at the end of the rejected request's row; C5 a rejection, then
 * Dismiss through the real route, with Break the feed active again; C6 an expiry; C7 a fallback incident; C8 a no-fix incident, with a
 * known and an unknown cause; C9 an incident closed by IncidentManager; C10 the failures of Dismiss (a refusal, a server error, a held
 * reply) and the cross-session dismissal (404, AD-4).
 */
test.describe.configure({ timeout: 150_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'ANSWERS';

/** The route that dismisses an incident, and its path (the cross-session case posts to it). */
const DISMISS = '**/ocutalon/api/v1/incidents/*/dismiss';
const DISMISS_PATH = (ref: string): string => `/ocutalon/api/v1/incidents/${ref}/dismiss`;

/** The Orders production that the guide's Break the feed watches (Install.Step.Demo's NAMESPACE and PRODUCTION). */
const ORDERS = { namespace: 'OCUORDERS', production: 'OcuTalon.Demo.Orders.Production' };

/** How long a thing that follows a live event may take: one live update. */
const ONE_UPDATE_MS = 3000;

/** How long a case looks on after the announcements it expects: longer than the 1 s between two texts, so a second one would show. */
const SETTLE_MS = 3000;

/** The headline of the full card for the incident of incidentOf (its first failure at 14:12 today). */
const HEADLINE = '50 orders failed since 14:12';

/** The count-of-50 result that went through, and the partial ones of the fixtures. */
const ALL_THROUGH = { total: 50, resent: 50, completed: 50, failedAgain: 0, skipped: 0, interrupted: 0, reason: '' };
const ALL_TEXT = 'All 50 orders went through.';
const REASON = "the order date still wasn't accepted";
const AUDIT = 'Recorded in the IRIS audit log.';

/** The HH:MM of a UTC ISO time. */
const hhmm = (iso: string): string => iso.slice(11, 16);

/** Once per run, the IncidentManager item takes the double; afterwards it gets its class back. */
test.beforeAll(async () => {
  test.setTimeout(240_000);
  await useIncidentManagerDouble();
});
test.afterAll(async () => {
  test.setTimeout(240_000);
  await restoreIncidentManager();
});

/** The incident card of a ref, its request cards, the card of one request, and every result band of a card. */
const cardOf = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);
const bandsOf = (card: Locator): Locator => card.locator('[data-part="result"]');
const dismissOf = (scope: Locator): Locator => scope.getByRole('button', { name: 'Dismiss', exact: true });

/** The simulated phone and its messages. */
const phoneOf = (page: Page): Locator => page.locator('app-simulated-phone');
const messageOf = (page: Page, ref: string): Locator => phoneOf(page).locator(`.notification[data-key="${ref}"]`);

/** The Break the feed button of the guide's demo control. */
const feedButton = (page: Page): Locator => page.locator('app-break-feed-box app-server-button button');

/** The path data of an icon of the page's icon module, read from its source: the icon that a case expects is the module's own. */
function iconPaths(name: string): string[] {
  const source = readFileSync(resolve('src/app/icon/icon.ts'), 'utf8');
  const start = source.indexOf(`@case ('${name}') {`);
  expect(start, `the icon module draws ${name}`).toBeGreaterThan(-1);
  const block = source.slice(start, source.indexOf('\n        }', start));
  return [...block.matchAll(/<path\s+d="([^"]+)"/g)].map((match) => match[1] ?? '');
}

/** The path data of the first icon inside a locator, as the page draws it. */
const drawn = (scope: Locator): Promise<string[]> => scope.locator('svg').first().locator('path').evaluateAll((paths) => paths.map((path) => path.getAttribute('d') ?? ''));

/** Signs the answers user in with the announcements recorded and waits for the loaded page with the phone. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await recordAnnouncements(page);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
  await expect(phoneOf(page), 'the stack is in demo mode: the phone shows').toBeVisible();
}

/** Publishes an incident and waits for the page to apply it. */
async function publish(page: Page, user: string, payload: Record<string, unknown>): Promise<void> {
  await applied(page, await publishIncident(user, payload));
}

/**
 * Seeds a request of the incident in this state (answered by the user on the web a minute ago, or unanswered and expired two minutes
 * ago), with its row in `rows`, and has BridgeSink publish it to the open page. Returns the request's Ref and the time its status names.
 */
async function request(page: Page, user: string, rows: string[], incident: string, state: 'done' | 'executing' | 'rejected' | 'expired' | 'pending'): Promise<{ ref: string; at: string }> {
  const answered = state === 'done' || state === 'executing' || state === 'rejected';
  const at = state === 'expired' ? inMs(-120_000) : inMs(-60_000);
  const fields: ApprovalFields = {
    incidentRef: incident,
    requiredRole: 'OcuTalonUser',
    state,
    raisedAt: inMs(-600_000),
    expiresAt: state === 'expired' ? at : TOMORROW_AT_1413,
    dryRun: DRY_RUN,
    ...(answered ? { answeredAction: state === 'rejected' ? 'reject' : 'approve', answeredChannel: 'web', answeredBy: user, answeredAt: at } : {}),
  };
  const ref = await seedApproval(user, fields);
  rows.push(ref);
  await applied(page, await sinkEvent(user, 'approval.raised', { ref }));
  return { ref, at };
}

/** An incident payload of incidentOf with these requests, in this state and open variant, and these fields. */
const payloadOf = (incident: string, requests: RequestFields[], state: string, over: Record<string, unknown> = {}): Record<string, unknown> => incidentOf(incident, requests, { state, ...over });

/** The failure group of the fallback and no-fix incidents of the cases: 50 failures at 14:12. */
const GROUP = { itemName: 'Order transform', count: 50, errorSummary: 'date could not be read', firstAt: today('14:12:00') };
const GROUP_LINE = "Order transform: 50, 'date could not be read', first at 14:12";

/** Expects the live region to have received exactly this many announcements that hold the text, now and after a settle. */
async function expectAnnounced(page: Page, text: string, times: number, what: string): Promise<void> {
  await expect.poll(() => announcements(page, text), { message: `${what}: announced`, timeout: CARD_MS }).toBe(times);
  await page.waitForTimeout(SETTLE_MS);
  expect(await announcements(page, text), `${what}: announced ${times} time(s), also later`).toBe(times);
}

/** Expects the band's tone: its background and foreground tokens, and the icon it draws. */
async function expectBand(page: Page, band: Locator, tone: 'success' | 'partial', icon: string, text: string, what: string): Promise<void> {
  await expect(band.locator('.text'), `${what}: the text`).toHaveText(text, { timeout: CARD_MS });
  await expect(band, `${what}: the ${tone} background`).toHaveCSS('background-color', await tokenColor(page, `--result-${tone}-background`));
  await expect(band, `${what}: and foreground`).toHaveCSS('color', await tokenColor(page, `--result-${tone}-foreground`));
  expect(await drawn(band), `${what}: the ${icon} icon`).toEqual(iconPaths(icon));
}

/**
 * C1: a finished fix. R is published fixing, then resolved with A's result: A's card gets a band in the success colours with
 * circle-check and "All 50 orders went through.", the audit line beneath it, and a ghost Dismiss at the band's right end. The text is
 * announced once. The `result` notification gives the phone a new message with the same text and no buttons, and A's request message
 * keeps its answer line. A press on Dismiss goes to the route: the card compacts in place to its headline and the band (chip Closed, the
 * border-strong bar, Show details, no Dismiss, no request card), focus is on the headline, and nothing is announced for the closing.
 */
test('C1: a finished fix shows its result band with Dismiss, the phone gets the result, and Dismiss compacts the card to the headline', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = inMs(-2000);
  try {
    await open(page);
    const incident = await seedIncident(user, { state: 'resolved', openVariant: '' });
    rows.push(incident);
    const a = await request(page, user, rows, incident, 'executing');
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'executing' }], 'fixing'));
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip'), 'the chip follows the payload: Fixing').toHaveText('Fixing', { timeout: CARD_MS });
    await expect(card.locator('p.fixing')).toHaveText('Repairing and resending 50 orders\u2026');
    await expect(bandsOf(card), 'no band before a result').toHaveCount(0);

    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: ALL_THROUGH }], 'resolved'));
    await expect(card.locator('.chip-row .chip'), 'the chip is Resolved').toHaveText('Resolved', { timeout: CARD_MS });
    const aCard = requestCard(page, a.ref);
    const band = bandsOf(aCard);
    await expect(band, 'A\'s card has one band').toHaveCount(1, { timeout: CARD_MS });
    await expectBand(page, band, 'success', 'circle-check', ALL_TEXT, 'the band');
    await expect(aCard.locator('p.status'), 'under its answered status').toHaveText(`Approved from the web chat at ${hhmm(a.at)}`);
    await expect(aCard.locator('p.audit'), 'with the audit line').toHaveText(AUDIT);
    const [bandBox, auditBox, statusBox] = await Promise.all([band.boundingBox(), aCard.locator('p.audit').boundingBox(), aCard.locator('p.status').boundingBox()]);
    expect(bandBox!.y, 'the band stands below the status').toBeGreaterThan(statusBox!.y);
    expect(auditBox!.y, 'and the audit line below the band').toBeGreaterThan(bandBox!.y + bandBox!.height - 1);

    const dismiss = dismissOf(band);
    await expect(dismiss, 'Dismiss is in the band').toHaveCount(1);
    await expect(dismiss, 'a ghost button').toHaveClass(/button-ghost/);
    const [dismissBox, bandRect] = await Promise.all([dismiss.boundingBox(), band.boundingBox()]);
    expect(bandRect!.x + bandRect!.width - (dismissBox!.x + dismissBox!.width), 'at the right end of the band').toBeLessThan(20);
    await expectAnnounced(page, ALL_TEXT, 1, 'the result');

    const since = inMs(-120_000);
    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.withFix',
      slots: { count: 50, itemNoun: { one: 'order', other: 'orders' }, time: since, cause: 'Data format change', fixSummary: 'repair the order date and resend 50 orders', field: 'OrderDate', before: '10/16/2026', after: '2026-10-16', resendCount: 50 },
      approvalRef: a.ref,
      incidentRef: incident,
    });
    let requestMessage = '';
    await expect.poll(async () => (requestMessage = (await phoneMessage(user, a.ref))?.ref ?? ''), { message: 'the request message is on the phone', timeout: CARD_MS }).not.toBe('');
    await sendNotification(user, { kind: 'answered', catalogKey: 'answered.approved', slots: { channel: 'web', time: a.at }, approvalRef: a.ref, incidentRef: incident });
    const line = messageOf(page, requestMessage).locator('p[data-part="answer"]');
    await expect(line, "A's request message has its answer line").toHaveText(`Approved from the web chat at ${hhmm(a.at)}.`, { timeout: CARD_MS });
    const messages = phoneOf(page).locator('.notification');
    const before = await messages.count();
    await sendNotification(user, { kind: 'result', catalogKey: 'result.allThrough', slots: { count: 50, itemNoun: { one: 'order', other: 'orders' } }, approvalRef: a.ref, incidentRef: incident });
    await expect(messages, 'the result is a new message').toHaveCount(before + 1, { timeout: CARD_MS });
    const result = messages.filter({ hasText: ALL_TEXT });
    await expect(result, 'with the band\'s text').toHaveCount(1);
    await expect(result.getByRole('button'), 'and no buttons').toHaveCount(0);
    await expect(line, "A's request message keeps its line").toHaveText(`Approved from the web chat at ${hhmm(a.at)}.`);

    await dismiss.click();
    await expect(card.locator('.chip-row .chip'), 'the card compacts: Closed').toHaveText('Closed', { timeout: CARD_MS });
    await expect(card).toHaveCSS('border-left-color', await tokenColor(page, '--border-strong'));
    await expect(requestCard(page, a.ref), 'no request card').toHaveCount(0);
    await expect(bandsOf(card), 'the band stays').toHaveCount(1);
    await expect(bandsOf(card).locator('.text')).toHaveText(ALL_TEXT);
    await expect(dismissOf(card), 'no Dismiss').toHaveCount(0);
    await expect(card.getByRole('button', { name: 'Show details' }), 'Show details stays').toHaveCount(1);
    await expect(card.getByRole('heading', { level: 3 }), 'focus is on the compacted headline').toBeFocused();
    await page.waitForTimeout(SETTLE_MS);
    expect((await announcedTexts(page)).filter((text) => text.includes('Closed')), 'nothing is announced for the closing').toEqual([]);

    const commands = await doubleCommands(incident);
    expect(commands.map((one) => `${one.verb}|${one.origin}`), 'IncidentManager got one dismiss from the web user').toEqual(['dismiss|web_user']);
    expect(commands[0]?.session.length, 'for a session').toBe(22);
    expect(await incidentState(incident), 'the row is closed').toBe('closed');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/**
 * C2: the partial results. A's result goes through failed again, skipped, both, interrupted and could not start, each update replacing
 * the one before in the same band: the catalog's exact text, the partial colours and triangle-alert, and one band throughout.
 */
test('C2: a partial result is one band in the partial colours, and each kind reads as the catalog words it', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('C2');
    const a = await request(page, user, rows, incident, 'done');
    const card = requestCard(page, a.ref);
    const kinds: Array<[string, Record<string, unknown>, string]> = [
      ['failed again', { total: 50, resent: 50, completed: 48, failedAgain: 2, skipped: 0, interrupted: 0, reason: REASON }, `48 of 50 orders went through. 2 failed again (${REASON}). I won't retry them without a new approval.`],
      ['skipped', { total: 50, resent: 50, completed: 47, failedAgain: 0, skipped: 3, interrupted: 0, reason: '' }, '47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.'],
      ['failed again and skipped', { total: 50, resent: 50, completed: 45, failedAgain: 2, skipped: 3, interrupted: 0, reason: REASON }, `45 of 50 orders went through. 2 failed again (${REASON}), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval.`],
      ['interrupted', { total: 50, resent: 50, completed: 30, failedAgain: 0, skipped: 0, interrupted: 20, reason: '' }, 'The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval.'],
      ["could not start", { total: 50, resent: 0, completed: 0, failedAgain: 0, skipped: 0, interrupted: 0, reason: "OcuTalon isn't allowed to resend messages in that production" }, "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed."],
    ];
    for (const [label, result, text] of kinds) {
      await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result }], 'resolved'));
      await expect(bandsOf(card), `${label}: one band`).toHaveCount(1, { timeout: CARD_MS });
      await expectBand(page, bandsOf(card), 'partial', 'triangle-alert', text, label);
      await expect(card.locator('p.audit'), `${label}: with the audit line`).toHaveText(AUDIT);
    }
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: ALL_THROUGH }], 'resolved'));
    await expectBand(page, bandsOf(card), 'success', 'circle-check', ALL_TEXT, 'and then all through, in the same one band');
    await expect(bandsOf(card)).toHaveCount(1);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * C3: still resending, then final. While R is fixing, A's band says "Still resending: 30 of 50 orders have gone through so far. I'll
 * tell you when it's done." in the partial colours with clock, the fixing line shows, and there is no Dismiss. The final result then
 * replaces that band's text in place and Dismiss appears. Each text is announced once.
 */
test('C3: the still-resending band is replaced in place by the final result, and Dismiss comes with it', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('C3');
    const a = await request(page, user, rows, incident, 'executing');
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'pending' }], 'awaiting_approval'));
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip')).toHaveText('Awaiting approval', { timeout: CARD_MS });
    // The announcer speaks no more than three texts in 2 s (the rest as "{n} new updates"), so each stage waits until it is heard.
    await expectAnnounced(page, 'Approval needed', 1, 'the new card');

    const resending = "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done.";
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'executing', result: { total: 50, resent: 30, completed: 30, failedAgain: 0, skipped: 0, interrupted: 0, reason: '' } }], 'fixing'));
    const band = bandsOf(card);
    await expect(band).toHaveCount(1, { timeout: CARD_MS });
    await expectBand(page, band, 'partial', 'clock', resending, 'while it runs');
    await expect(card.locator('.chip-row .chip')).toHaveText('Fixing');
    await expect(card.locator('p.fixing'), 'with the fixing line').toHaveText('Repairing and resending 50 orders\u2026');
    await expect(dismissOf(card), 'and no Dismiss').toHaveCount(0);
    const handle = await band.elementHandle();
    await expectAnnounced(page, resending, 1, 'the still-resending text');

    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: ALL_THROUGH }], 'resolved'));
    await expectBand(page, band, 'success', 'circle-check', ALL_TEXT, 'the final result');
    await expect(bandsOf(card), 'in the same one band').toHaveCount(1);
    expect(await handle!.evaluate((node) => node.isConnected), 'the band was replaced in place, not redrawn').toBe(true);
    await expect(dismissOf(band), 'Dismiss appears in it').toHaveCount(1);
    await expect(card.locator('p.fixing')).toHaveCount(0);
    await expectAnnounced(page, resending, 1, 'the still-resending text, not again');
    await expectAnnounced(page, ALL_TEXT, 1, 'the final text');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * C4: two requests. R awaits approval: A's band (a partial result) stays with A, B has its Approve and Reject, the chip says Awaiting
 * approval and there is no Dismiss. B is then rejected on its card (the real answer) and R is published open and rejected: B's status
 * "Rejected from the web chat at HH:MM. Nothing was changed.", Dismiss at the right end of B's status row, and A's band unchanged.
 */
test('C4: two requests keep their own bands, and after a rejection Dismiss is at the end of the rejected request\'s row', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('C4');
    const a = await request(page, user, rows, incident, 'done');
    const b = await request(page, user, rows, incident, 'pending');
    const failed = { total: 50, resent: 50, completed: 48, failedAgain: 2, skipped: 0, interrupted: 0, reason: REASON };
    const failedText = `48 of 50 orders went through. 2 failed again (${REASON}). I won't retry them without a new approval.`;
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: failed }, { ref: b.ref }], 'awaiting_approval'));
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip')).toHaveText('Awaiting approval', { timeout: CARD_MS });
    await expectBand(page, bandsOf(requestCard(page, a.ref)), 'partial', 'triangle-alert', failedText, "A's band");
    await expect(bandsOf(requestCard(page, b.ref)), "B has no band: one request's result never goes to another").toHaveCount(0);
    const reject = requestCard(page, b.ref).getByRole('button', { name: 'Reject: repair and resend 50 orders', exact: true });
    await expect(reject, "B's Reject").toHaveCount(1);
    await expect(requestCard(page, b.ref).getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true }), "and B's Approve").toHaveCount(1);
    await expect(dismissOf(card), 'there is no Dismiss while R awaits approval').toHaveCount(0);

    await reject.click();
    const status = requestCard(page, b.ref).locator('p.status');
    await expect(status, "B's status after the real answer").toHaveText(/^Rejected from the web chat at \d\d:\d\d\. Nothing was changed\.$/, { timeout: 30_000 });
    const at = ((await status.textContent()) ?? '').match(/at (\d\d:\d\d)\./)?.[1] ?? '';
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: failed }, { ref: b.ref, state: 'rejected' }], 'open', { openVariant: 'rejected' }));
    await expect(card.locator('.chip-row .chip')).toHaveText('Open', { timeout: CARD_MS });
    await expect(status).toHaveText(`Rejected from the web chat at ${at}. Nothing was changed.`);
    expect(await drawn(requestCard(page, b.ref).locator('p.status')), 'with circle-slash').toEqual(iconPaths('circle-slash'));
    const row = requestCard(page, b.ref).locator('.answer-row');
    const dismiss = dismissOf(row);
    await expect(dismiss, "Dismiss is in B's status row").toHaveCount(1);
    const [dismissBox, rowBox] = await Promise.all([dismiss.boundingBox(), row.boundingBox()]);
    expect(rowBox!.x + rowBox!.width - (dismissBox!.x + dismissBox!.width), 'at its right end').toBeLessThan(16);
    await expect(dismissOf(requestCard(page, a.ref)), "and none in A's card").toHaveCount(0);
    await expectBand(page, bandsOf(requestCard(page, a.ref)), 'partial', 'triangle-alert', failedText, "A's band is unchanged");
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * C5: a rejection, then Dismiss through the real route and the double. S watches Orders and R is an Orders incident, open and
 * rejected: the Break the feed button is aria-disabled. Focus on Dismiss and Enter: Dismiss goes busy (a spinner, aria-busy and
 * aria-disabled, never disabled), then the card compacts (chip Closed, the border-strong bar, no request card, no Dismiss) with focus
 * on the headline and no announcement of the closing. The double got one dismiss from the web user, R's row is closed, Break the feed
 * is active within one live update, and after a reload R is still compact.
 */
test('C5: Dismiss of a rejected Orders incident closes it through the route, and Break the feed is active again', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    rows.push(await seedCheck(user, { namespace: ORDERS.namespace, production: ORDERS.production, displayName: 'Orders production' }));
    const incident = await seedIncident(user, { ...ORDERS, state: 'open', openVariant: 'rejected' });
    rows.push(incident);
    await open(page);
    const a = await request(page, user, rows, incident, 'rejected');
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'rejected' }], 'open', { openVariant: 'rejected' }));
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip')).toHaveText('Open', { timeout: CARD_MS });
    await expect(requestCard(page, a.ref).locator('p.status'), "A's status").toHaveText(`Rejected from the web chat at ${hhmm(a.at)}. Nothing was changed.`);
    await expect(feedButton(page), 'Break the feed waits for the dismissal').toHaveAttribute('aria-disabled', 'true', { timeout: CARD_MS });

    await page.route(DISMISS, async (route) => {
      await new Promise((done) => setTimeout(done, 800));
      await route.continue();
    });
    const dismiss = dismissOf(card);
    await dismiss.focus();
    await expect(dismiss).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(dismiss, 'Dismiss is busy').toHaveAttribute('aria-busy', 'true');
    await expect(dismiss, 'aria-disabled').toHaveAttribute('aria-disabled', 'true');
    expect(await dismiss.getAttribute('disabled'), 'and never disabled').toBeNull();
    await expect(dismiss.locator('app-icon.spinner'), 'with the spinner').toHaveCount(1);

    await expect(card.locator('.chip-row .chip'), 'the card compacts').toHaveText('Closed', { timeout: CARD_MS });
    await expect(card).toHaveCSS('border-left-color', await tokenColor(page, '--border-strong'));
    await expect(requestCard(page, a.ref), 'no request card').toHaveCount(0);
    await expect(dismissOf(card), 'no Dismiss').toHaveCount(0);
    await expect(card.getByRole('heading', { level: 3 }), 'focus is on the headline').toBeFocused();
    await page.waitForTimeout(SETTLE_MS);
    expect((await announcedTexts(page)).filter((text) => text.includes('Closed')), 'the closing is not announced').toEqual([]);

    const commands = await doubleCommands(incident);
    expect(commands.map((one) => `${one.verb}|${one.origin}`), 'one dismiss from the web user').toEqual(['dismiss|web_user']);
    expect(await incidentState(incident), "R's row is closed").toBe('closed');
    await expect(feedButton(page), 'Break the feed is active again within one live update').not.toHaveAttribute('aria-disabled', 'true', { timeout: ONE_UPDATE_MS });

    await page.unroute(DISMISS);
    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(card.locator('.chip-row .chip'), 'a reload shows R compact').toHaveText('Closed', { timeout: CARD_MS });
    await expect(dismissOf(card)).toHaveCount(0);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * C6: an expiry. R is open and expired, A expired: "Expired at HH:MM. Nothing was changed." with clock, no Approve or Reject, the
 * attention bar, and Show details then Dismiss at the right end of the status row.
 */
test('C6: an expired request shows its status with clock, and Show details then Dismiss end the row', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('C6');
    const a = await request(page, user, rows, incident, 'expired');
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'expired' }], 'open', { openVariant: 'expired' }));
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip')).toHaveText('Open', { timeout: CARD_MS });
    const aCard = requestCard(page, a.ref);
    const status = aCard.locator('p.status');
    await expect(status).toHaveText(`Expired at ${hhmm(a.at)}. Nothing was changed.`, { timeout: CARD_MS });
    expect(await drawn(status), 'with clock').toEqual(iconPaths('clock'));
    await expect(aCard.getByRole('button', { name: /^(Approve|Reject)/ }), 'no Approve or Reject').toHaveCount(0);
    await expect(card, 'the attention bar').toHaveCSS('border-left-color', await tokenColor(page, '--attention'));
    const row = aCard.locator('.answer-row');
    const buttons = row.getByRole('button');
    expect((await buttons.allTextContents()).map((text) => text.trim()), 'Show details, then Dismiss').toEqual(['Show details', 'Dismiss']);
    const [detailsBox, dismissBox, rowBox] = await Promise.all([buttons.nth(0).boundingBox(), buttons.nth(1).boundingBox(), row.boundingBox()]);
    expect(detailsBox!.x, 'Show details stands left of Dismiss').toBeLessThan(dismissBox!.x);
    expect(rowBox!.x + rowBox!.width - (dismissBox!.x + dismissBox!.width), 'at the right end of the row').toBeLessThan(16);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * C7: a fallback incident. The chip Open with the Fallback flag, the headline, the sentence with the reason's text, "Failures:" and the
 * group line, no fix and no request card, then Show details and Dismiss; "Incident: {headline}. No fix proposed." is announced. The
 * phone's incident.fallback notice is one message with the server's exact text and no buttons.
 */
test('C7: a fallback incident shows its notice and failure groups with Show details and Dismiss, and the phone shows the notice', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const start = inMs(-2000);
  try {
    await open(page);
    const incident = refOf('C7');
    await publish(
      page,
      user,
      payloadOf(incident, [], 'open', { openVariant: 'fallback', fallback: true, fallbackReason: 'timeout', fixSummary: '', cause: '', causeCategory: '', element: '', groups: [GROUP] }),
    );
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip')).toHaveText('Open', { timeout: CARD_MS });
    await expect(card.locator('app-fallback-flag'), 'with the Fallback flag').toHaveCount(1);
    await expect(card.getByRole('heading', { level: 3 })).toHaveText(HEADLINE);
    await expect(card.locator('p.notice')).toHaveText("I couldn't work out the cause (the model didn't answer within 60 seconds), so I'm not proposing a fix. Nothing was changed.");
    await expect(card.locator('p.failures')).toHaveText('Failures:');
    await expect(card.locator('ul.groups li')).toHaveText([GROUP_LINE]);
    await expect(card.locator('p.fix'), 'no fix').toHaveCount(0);
    await expect(card.locator('[data-part="approval"]'), 'no request card').toHaveCount(0);
    const actions = card.locator('.actions').getByRole('button');
    expect((await actions.allTextContents()).map((text) => text.trim()), 'Show details, then Dismiss').toEqual(['Show details', 'Dismiss']);
    await expectAnnounced(page, `Incident: ${HEADLINE}. No fix proposed.`, 1, 'the new card');

    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.fallback',
      slots: { count: 50, itemNoun: { one: 'order', other: 'orders' }, time: today('14:12:00'), fallbackReason: 'timeout', groups: [GROUP] },
      incidentRef: incident,
    });
    const message = phoneOf(page).locator('.notification').filter({ hasText: 'Order transform' });
    await expect(message, 'the phone shows the notice').toHaveCount(1, { timeout: CARD_MS });
    expect(plain(await message.locator('p.text').textContent())).toBe(
      `${HEADLINE}. I couldn't work out the cause (the model didn't answer within 60 seconds), so I'm not proposing a fix. Nothing was changed. Failures: ${GROUP_LINE} Details and trace: on your OcuTalon page.`,
    );
    await expect(message.getByRole('button'), 'with no buttons').toHaveCount(0);
  } finally {
    await dropPhone(user, start);
  }
});

/**
 * C8: a no-fix incident. The cause, the evidence line, "None of my fixes applies to this, so I'm not proposing one. Nothing was changed.",
 * the groups, Show details then Dismiss. A second card whose cause category is unknown has the unknown sentence in place of the cause and
 * the no-fix sentence. The phone's incident.noFix message has no buttons.
 */
test('C8: a no-fix incident shows its cause, evidence and sentence, an unknown cause its own sentence, and the phone has no buttons', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const start = inMs(-2000);
  try {
    await open(page);
    const known = refOf('C8a');
    const unknown = refOf('C8b');
    const over = { openVariant: 'no_fix', fixSummary: '', groups: [GROUP] };
    await publish(page, user, payloadOf(known, [], 'open', { ...over, cause: 'The partner now requires a signed header.', causeCategory: 'other' }));
    await publish(page, user, payloadOf(unknown, [], 'open', { ...over, cause: 'zz this must not show', causeCategory: 'unknown' }));
    const card = cardOf(page, known);
    await expect(card.locator('.chip-row .chip')).toHaveText('Open', { timeout: CARD_MS });
    await expect(card.locator('app-fallback-flag'), 'no Fallback flag').toHaveCount(0);
    await expect(card.locator('p.cause')).toHaveText('The partner now requires a signed header.');
    await expect(card.locator('p.evidence-line')).toHaveText('Other \u00B7 order date \u00B7 50 failures grouped into this incident');
    await expect(card.locator('p.notice')).toHaveText("None of my fixes applies to this, so I'm not proposing one. Nothing was changed.");
    await expect(card.locator('ul.groups li')).toHaveText([GROUP_LINE]);
    expect((await card.locator('.actions').getByRole('button').allTextContents()).map((text) => text.trim()), 'Show details, then Dismiss').toEqual(['Show details', 'Dismiss']);

    const second = cardOf(page, unknown);
    await expect(second.locator('.chip-row .chip')).toHaveText('Open', { timeout: CARD_MS });
    await expect(second.locator('p.cause'), 'an unknown cause has no cause sentence').toHaveCount(0);
    await expect(second.locator('p.notice')).toHaveText("I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.");
    await expect(second.locator('ul.groups li')).toHaveText([GROUP_LINE]);
    await expect(second.getByText('zz this must not show')).toHaveCount(0);

    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.noFix',
      slots: { count: 50, itemNoun: { one: 'order', other: 'orders' }, time: today('14:12:00'), cause: 'The partner now requires a signed header', groups: [GROUP] },
      incidentRef: known,
    });
    const message = phoneOf(page).locator('.notification').filter({ hasText: "None of my fixes applies to this" });
    await expect(message, 'the phone shows the no-fix message').toHaveCount(1, { timeout: CARD_MS });
    await expect(message.getByRole('button'), 'with no buttons').toHaveCount(0);
  } finally {
    await dropPhone(user, start);
  }
});

/**
 * C9: closed by IncidentManager. R is published closed with A's result, with no press of this page: the card compacts in place to its
 * headline and the band, with Show details and no Dismiss, and the chat announces "Incident: {headline}. Closed.". A later incident with
 * a new Ref gets a card of its own.
 */
test('C9: an incident closed by IncidentManager compacts in place to the headline and its band, and a new ref gets a new card', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('C9');
    const a = await request(page, user, rows, incident, 'done');
    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: ALL_THROUGH }], 'resolved'));
    const card = cardOf(page, incident);
    await expect(card.locator('.chip-row .chip')).toHaveText('Resolved', { timeout: CARD_MS });
    await expect(requestCard(page, a.ref)).toHaveCount(1);

    await publish(page, user, payloadOf(incident, [{ ref: a.ref, state: 'done', result: ALL_THROUGH }], 'closed'));
    await expect(card.locator('.chip-row .chip')).toHaveText('Closed', { timeout: CARD_MS });
    await expect(page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${incident}"]`), 'in place: one card').toHaveCount(1);
    await expect(requestCard(page, a.ref), 'no request card').toHaveCount(0);
    await expect(bandsOf(card)).toHaveCount(1);
    await expectBand(page, bandsOf(card), 'success', 'circle-check', ALL_TEXT, 'the band stays');
    await expect(dismissOf(card), 'no Dismiss').toHaveCount(0);
    await expect(card.getByRole('button', { name: 'Show details' }), 'Show details stays').toHaveCount(1);
    await expect(card.locator('p.cause'), 'no cause on a compact card').toHaveCount(0);
    await expectAnnounced(page, `Incident: ${HEADLINE}. Closed.`, 1, 'the closing by IncidentManager');

    const next = refOf('C9n');
    await publish(page, user, payloadOf(next, [], 'open', { openVariant: 'no_fix', fixSummary: '', groups: [GROUP] }));
    await expect(cardOf(page, next), 'a new ref gets a card of its own').toHaveCount(1, { timeout: CARD_MS });
    await expect(card, 'and the closed card stays').toHaveCount(1);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * C10: the failures of Dismiss, and the cross-session dismissal (AC7, AD-4). The dismissal of another session's incident is 404 with the
 * not_found body, nothing is submitted (the double records nothing) and the row is unchanged. Then, through page.route: a 200 that the
 * route fulfills itself (so no event follows) compacts the card and focuses its headline, the page's own path; a 409 shows its message
 * beside Dismiss, announced once, and leaves the card; a 500 shows its message; and a held reply restores Dismiss after 10 s with the
 * busy notice shown and announced, and a later 200 still compacts the card.
 */
test('C10: another session\'s incident is 404, and Dismiss shows a refusal, an error and a held reply, and a 200 still compacts the card', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const other = await seedOtherSession(`zzc10${Date.now().toString(36)}`);
    rows.push(other);
    const theirs = await seedIncident({ sessionRef: other });
    rows.push(theirs);
    const refused = await post(page.request, DISMISS_PATH(theirs), {});
    expect(refused.status(), "another session's incident is 404").toBe(404);
    expect(await refused.json(), 'with the error body').toEqual({ error: { code: 'not_found', message: 'OcuTalon has nothing at this address.' } });
    expect(await incidentState(theirs), 'the row is unchanged').toBe('open');
    expect(await doubleCommands(theirs), 'and IncidentManager got nothing').toEqual([]);

    let mode: 'done' | '409' | '500' | 'held' = 'done';
    let held: Route | undefined;
    await page.route(DISMISS, async (route) => {
      if (mode === 'done') await route.fulfill({ status: 200, contentType: 'application/json', body: '{"result":"done"}' });
      else if (mode === '409') await route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_dismissible', message: 'zz refused' } }) });
      else if (mode === '500') await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'zz server error' } }) });
      else held = route;
    });

    const incident = refOf('C10');
    await publish(page, user, payloadOf(incident, [], 'open', { openVariant: 'no_fix', fixSummary: '', groups: [GROUP] }));
    const card = cardOf(page, incident);
    const dismiss = dismissOf(card);
    await expect(dismiss).toHaveCount(1, { timeout: CARD_MS });
    const notice = card.locator('app-incident-dismiss > app-inline-notice');

    mode = '409';
    await dismiss.click();
    await expect(notice, 'a refusal shows its message beside Dismiss').toHaveText('zz refused', { timeout: CARD_MS });
    await expect(dismiss, 'which describes the button').toHaveAttribute('aria-describedby', /incident-dismiss-notice-\d+/);
    await expect(card.locator('.chip-row .chip'), 'the card is unchanged').toHaveText('Open');
    await expect(dismiss, 'and Dismiss is not busy').not.toHaveAttribute('aria-busy', 'true');
    await expectAnnounced(page, 'zz refused', 1, 'the refusal');

    mode = '500';
    await dismiss.click();
    await expect(notice, 'a server error shows its message').toHaveText('zz server error', { timeout: CARD_MS });
    await expectAnnounced(page, 'zz server error', 1, 'the error');
    await expect(card.locator('.chip-row .chip')).toHaveText('Open');

    mode = 'held';
    await dismiss.click();
    await expect(dismiss, 'a held reply keeps Dismiss busy').toHaveAttribute('aria-busy', 'true');
    await expect(notice, 'the earlier notice went with the press').toHaveCount(0);
    const busy = "Couldn't reach OcuTalon. Try again. Nothing was changed.";
    await expect(dismiss, 'after 10 s Dismiss is restored').not.toHaveAttribute('aria-busy', 'true', { timeout: 14_000 });
    await expect(card.locator('app-incident-dismiss app-server-button app-inline-notice'), 'with the busy notice shown').toHaveText(busy);
    await expectAnnounced(page, busy, 1, 'the busy notice');
    expect(held, 'the held call is still out').toBeDefined();
    await expect(card.locator('.chip-row .chip'), 'the card is unchanged').toHaveText('Open');

    await held!.fulfill({ status: 200, contentType: 'application/json', body: '{"result":"done"}' });
    await expect(card.locator('.chip-row .chip'), 'a later 200 still compacts the card').toHaveText('Closed', { timeout: CARD_MS });
    await expect(card.getByRole('heading', { level: 3 }), 'with focus on the headline').toBeFocused();
    await expect(dismissOf(card)).toHaveCount(0);

    mode = 'done';
    const second = refOf('C10b');
    await publish(page, user, payloadOf(second, [], 'open', { openVariant: 'no_fix', fixSummary: '', groups: [GROUP] }));
    await dismissOf(cardOf(page, second)).click();
    await expect(cardOf(page, second).locator('.chip-row .chip'), 'a 200 that the route fulfilled itself compacts the card with no event').toHaveText('Closed', { timeout: CARD_MS });
    await expect(cardOf(page, second).getByRole('heading', { level: 3 }), 'and focuses its headline').toBeFocused();
    expect(await doubleCommands(second), 'the server never saw it').toEqual([]);
  } finally {
    await cleanFixtureRows(rows);
  }
});
