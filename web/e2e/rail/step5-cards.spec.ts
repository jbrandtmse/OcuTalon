import { expect, test, type Locator, type Page, type Response, type Route } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { incidentOf, phoneShows, raise, refOf, today } from '../support/approvals';
import { dropPhone, phoneMessage } from '../support/devices';
import { CARD_MS, MOST_STOPS, applied, composerOf, inMs, loadedAfter, mainOf, railOf } from '../support/floor';
import {
  answerHeaders,
  approvalAudit,
  askedSlots,
  auditClock,
  chk,
  cleanFixtureRows,
  dropSettingChange,
  fixtureSlots,
  fixtureUser,
  incidentState,
  irisScript,
  publishIncident,
  quoted,
  readApproval,
  seedIncident,
  seedSettingChange,
  sendNotification,
  setApprovalState,
  sinkEvent,
  type AnsweredFields,
  type ApprovalAudit,
  type SeedDryRun,
} from '../support/iris';
import { removePrecedentsOf } from '../support/memory';
import { announcedTexts, plain, recordAnnouncements, scrollListTo } from '../support/page';
import { scanContrast, scanNames } from '../support/scan';

/**
 * Story 24.4b, the step-5 requests on every surface (F1 to F4, F6 and F6b; 24.4a's F3b, F5, F5b and F7 are in step5-requests.spec.ts), in a
 * real browser against a real stack, as the rail fixture user (OCUTALON_RAIL_USER, whose session R1 to R19 of rail.spec.ts expect empty:
 * each case removes its rows, the precedents its answers recorded, its setting changes and its phone messages in finally). The page's clock is fixed at 14:30 UTC on the run's
 * date.
 *
 * - F1 to F4: a pending suspend and resume (F1), reroute (F2), rollback and undo (F3) and partner warning with two recipients (F4) show
 *   their own dry run in the request card (text-labelled Before and After rows in mono, "Nothing has changed yet.", Approve and Reject
 *   named by the rail's title), the rail row with that title, and the phone message of the server's catalog notice with the same two
 *   buttons. The phone notices are the server's own fill (askedSlots), the rollback's the catalog fixture's slots (fixtureSlots).
 * - F6: one incident with a done suspend (status, band, audit line), an expired reroute, a pending resume rejected from its phone message
 *   (the card's status within 5 s of the reply), and a done rollback with a pending undo (two request cards in the order raised).
 * - F6b: a closed incident draws a request card for an undo of a rollback that is still PENDING (AFTER_CLOSE_KINDS mirrors
 *   Fix.Kind.AskedClosed), whether it was raised before or after the close, and for no other kind; once the undo is answered, rejected,
 *   expired or done it has no request card (a done one's band is one of the compact card's bands, shown once; a rejected or expired one
 *   has no band); "Show in the chat" focuses the pending undo's card; Tab reaches Approve, Reject and Show details in that order; and
 *   Approve or Reject pressed on that card is recorded and audited as on an open card (the reply, the stored row, the trace header and
 *   the Approval audit entry equal an open-card control), is announced once through the live region with the existing answered text, moves
 *   focus to the incident's headline (DW-1426), and neither reopens the incident nor changes its state; an open card's answer is not
 *   announced by the incident card.
 */
test.describe.configure({ timeout: 150_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'RAIL';

/** The page's clock: 14:30 UTC on the run's date. */
test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(Date.parse(today('14:30:00')));
});

/** The items, the setting and the production of the fixtures. */
const ITEM = 'OrdersFromPartner';
const WAREHOUSE = 'OrdersToWarehouse';
const REVIEW = 'OrdersForReview';
const SETTING = 'TargetConfigName';
const PRODUCTION = 'OcuTalon.Demo.Orders.Production';
const OLD = 'OrdersRouter';
const NEW = 'OrdersRouterNew';

/** The incident's setting change as the payload carries it. */
const CHANGE = { item: ITEM, target: 'Host', setting: SETTING, oldValue: OLD, newValue: NEW, credential: false, detectedAt: today('14:08:00') };

/** The result of a run that changed its one target. */
const DONE_ONE = { total: 1, resent: 0, completed: 1, failedAgain: 0, skipped: 0, interrupted: 0, reason: '' };

/** The notice, the two recipients of the partner warning and how each shows. */
const NOTICE = 'Orders from your feed failed between 14:12 and 14:15. We are looking into it.';
const RECIPIENTS = [
  { name: 'Results Partner IT', address: 'it@results-partner.example' },
  { name: 'Results Partner Ops', address: 'ops@results-partner.example' },
] as const;
const SHOWN = RECIPIENTS.map((one) => `${one.name} <${one.address}>`);

/** The dry runs of the kinds. */
const SUSPEND: SeedDryRun = { item: WAREHOUSE, before: 'enabled', after: 'disabled' };
const RESUME: SeedDryRun = { item: WAREHOUSE, before: 'disabled', after: 'enabled' };
const REROUTE: SeedDryRun = { affected: 50, resend: 50, field: '', itemNoun: { one: 'order', other: 'orders' }, from: ITEM, to: REVIEW, example: '1234' };
const ROLLBACK: SeedDryRun = { item: ITEM, field: SETTING, before: NEW, after: OLD };
const UNDO: SeedDryRun = { item: ITEM, field: SETTING, before: OLD, after: NEW };
const PARTNER: SeedDryRun = { notice: NOTICE, recipients: RECIPIENTS, simulated: true };

/** The incident card of a ref, the request card of a ref (both in the chat), and the rail's row of a request. */
const incidentCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);
const rowOfRequest = (page: Page, ref: string): Locator => railOf(page).locator(`li.row[data-row-key="approvals:${ref}"]`);

/** The text with its first letter in lower case, as the buttons' names have the rail's title. */
const lowerFirst = (text: string): string => text.charAt(0).toLowerCase() + text.slice(1);

/** Opens the page with a live socket, signed in as the rail user, and waits for the loaded page; the polite announcer's texts are recorded from the start. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await recordAnnouncements(page);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** What a case holds to remove in finally. */
interface Held {
  rows: string[];
  changes: string[];
  start: string;
}

const held = (): Held => ({ rows: [], changes: [], start: inMs(-2000) });

/** Removes what a case made: its rows, the precedents its answers recorded, its setting changes and its phone messages. */
async function release(user: string, mine: Held): Promise<void> {
  await dropPhone(user, mine.start);
  await removePrecedentsOf(mine.rows);
  await cleanFixtureRows(mine.rows);
  for (const change of mine.changes) await dropSettingChange(change);
}

/** Seeds the setting change and the incident row (awaiting approval, or this state) that a case's requests and phone notices name; returns the incident's Ref. */
async function seedIncidentOf(user: string, mine: Held, state = 'awaiting_approval'): Promise<string> {
  const change = await seedSettingChange({ item: ITEM, setting: SETTING, oldValue: OLD, newValue: NEW, detectedAt: today('14:08:00') });
  mine.changes.push(change);
  const incident = await seedIncident(user, { state, firstAt: today('14:12:00'), settingChangeRef: change, ...(state === 'closed' ? { closedAt: today('14:20:00') } : {}) });
  mine.rows.push(incident);
  return incident;
}

/** One kind as a case checks it on every surface. */
interface Kind {
  fixKind: string;
  dryRun: SeedDryRun;
  /** The rail's title of the request. */
  title: string;
  /** The catalog key of its phone notice. */
  key: string;
  before: string;
  after: string;
  /** The dry run's count line, when the kind has one. */
  count?: string;
  /** The notice's slots: the server's own fill (askedSlots) unless the kind has none, then the catalog fixture's. */
  slots: 'asked' | 'fixture';
}

const SUSPEND_KIND: Kind = { fixKind: 'suspend_item', dryRun: SUSPEND, title: `Suspend ${WAREHOUSE}`, key: 'incident.suspendRequest', before: `${WAREHOUSE}: enabled`, after: `${WAREHOUSE}: disabled`, slots: 'asked' };
const RESUME_KIND: Kind = { fixKind: 'resume_item', dryRun: RESUME, title: `Resume ${WAREHOUSE}`, key: 'incident.resumeRequest', before: `${WAREHOUSE}: disabled`, after: `${WAREHOUSE}: enabled`, slots: 'asked' };
const REROUTE_KIND: Kind = {
  fixKind: 'reroute',
  dryRun: REROUTE,
  title: `Reroute 50 orders to ${REVIEW}`,
  key: 'incident.rerouteRequest',
  before: `Message 1234: ${ITEM}`,
  after: `Message 1234: ${REVIEW}`,
  count: '50 orders affected',
  slots: 'asked',
};
const ROLLBACK_KIND: Kind = { fixKind: 'rollback_setting', dryRun: ROLLBACK, title: `Put ${SETTING} on ${ITEM} back`, key: 'incident.rollbackRequest', before: `${SETTING}: ${NEW}`, after: `${SETTING}: ${OLD}`, slots: 'fixture' };
const UNDO_KIND: Kind = { fixKind: 'undo_rollback', dryRun: UNDO, title: `Undo the rollback of ${SETTING} on ${ITEM}`, key: 'incident.undoRollbackRequest', before: `${SETTING}: ${OLD}`, after: `${SETTING}: ${NEW}`, slots: 'asked' };

/** The slots of a kind's phone notice. */
function slotsOf(kind: Kind, incident: string): Promise<Record<string, unknown>> {
  return kind.slots === 'fixture' ? fixtureSlots(kind.key) : askedSlots(kind.fixKind, kind.dryRun as Record<string, unknown>, incident);
}

/** The text of a message on the phone, with its whitespace collapsed. */
const messageText = async (message: Locator): Promise<string> => plain(await message.innerText());

/** Expects the phone message of a request to hold the server's stored text and the two buttons of the request's names. */
async function expectPhone(page: Page, user: string, request: string, title: string): Promise<void> {
  const { message } = await phoneShows(page, user, request);
  const stored = await phoneMessage(user, request);
  expect(stored?.text, 'the phone message holds the notice').toBeTruthy();
  expect(await messageText(message), 'the phone shows the server\'s text').toContain(plain(stored?.text ?? ''));
  await expect(message.getByRole('button', { name: `Approve: ${lowerFirst(title)}`, exact: true }), 'Approve is named for the action').toHaveCount(1);
  await expect(message.getByRole('button', { name: `Reject: ${lowerFirst(title)}`, exact: true }), 'and so is Reject').toHaveCount(1);
}

/**
 * Raises one request of the kind in the incident and checks it on the three surfaces: the card (its dry run in mono, the note, the two
 * buttons), the rail row (its title as the button that shows it in the chat) and the phone message of its notice. Returns the request's Ref.
 */
async function expectKind(page: Page, user: string, mine: Held, incident: string, requests: string[], kind: Kind): Promise<string> {
  const request = await raise(page, user, mine.rows, incident, requests, { fixKind: kind.fixKind, dryRun: kind.dryRun });
  const card = requestCard(page, request);
  await expect(card, `the ${kind.fixKind} request has a card`).toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.dry-key').nth(0), 'its first row is Before').toHaveText('Before');
  await expect(card.locator('.dry-key').nth(1), 'its second row is After').toHaveText('After');
  await expect(card.locator('.mono.before'), `${kind.fixKind}: the Before row, in mono`).toHaveText(kind.before);
  await expect(card.locator('.mono.after'), `${kind.fixKind}: the After row, in mono`).toHaveText(kind.after);
  if (kind.count !== undefined) await expect(card.locator('.dry-count'), 'the count line').toHaveText(kind.count);
  await expect(card.locator('.dry-note'), 'nothing has changed yet').toHaveText('Nothing has changed yet.');
  await expect(card.getByRole('button', { name: `Approve: ${lowerFirst(kind.title)}`, exact: true }), 'Approve is named by the title').toHaveCount(1);
  await expect(card.getByRole('button', { name: `Reject: ${lowerFirst(kind.title)}`, exact: true }), 'Reject too').toHaveCount(1);

  const jump = rowOfRequest(page, request).getByRole('button', { name: `Show in the chat: ${kind.title}`, exact: true });
  await expect(jump, 'the rail row has the title').toHaveCount(1);
  await expect(jump, 'as its text').toHaveText(kind.title);

  const slots = await slotsOf(kind, incident);
  await sendNotification(user, { kind: 'approval', catalogKey: kind.key, slots, approvalRef: request, incidentRef: incident });
  await expectPhone(page, user, request, kind.title);
  return request;
}

/** F1: a suspend and a resume in one incident row. */
test('F1: a suspend and a resume request show their own dry run on the card, the rail and the phone', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const incident = await seedIncidentOf(user, mine);
    await open(page);
    const requests: string[] = [];
    await expectKind(page, user, mine, incident, requests, SUSPEND_KIND);
    await expectKind(page, user, mine, incident, requests, RESUME_KIND);
    await expect(incidentCard(page, incident).locator('[data-part="approval"]'), 'the two requests are in one incident card').toHaveCount(2);
  } finally {
    await release(user, mine);
  }
});

/** F2: a reroute. */
test('F2: a reroute request shows its count, its example before and after, and its copies on the card, the rail and the phone', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const incident = await seedIncidentOf(user, mine);
    await open(page);
    const request = await expectKind(page, user, mine, incident, [], REROUTE_KIND);
    await expect(requestCard(page, request).locator('.dry-resend'), 'the copies that would be resent').toContainText(`50 copies to ${REVIEW}; the originals stay unchanged.`);
  } finally {
    await release(user, mine);
  }
});

/** F3: a rollback and an undo, with plain values. */
test('F3: a rollback and an undo request show the setting before and after on the card, the rail and the phone', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const incident = await seedIncidentOf(user, mine);
    await open(page);
    const requests: string[] = [];
    await expectKind(page, user, mine, incident, requests, ROLLBACK_KIND);
    await expectKind(page, user, mine, incident, requests, UNDO_KIND);
  } finally {
    await release(user, mine);
  }
});

/** F4: a partner warning with two recipients. */
test('F4: a partner warning shows its notice and both recipients before the answer row, and the phone holds them as plain text', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const incident = await seedIncidentOf(user, mine);
    await open(page);
    const request = await raise(page, user, mine.rows, incident, [], { fixKind: 'partner_warning', dryRun: PARTNER });
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.partner-to'), 'the To line names both recipients').toContainText(`To: ${SHOWN.join(', ')}`);
    await expect(card.locator('.partner-notice'), 'the notice as given').toHaveText(NOTICE);
    const order = await card.evaluate((el) => {
      const position = (selector: string): Node | null => el.querySelector(selector);
      const before = (a: Node | null, b: Node | null): boolean => a !== null && b !== null && (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
      return { toBeforeAnswer: before(position('.partner-to'), position('.answer-row')), noticeBeforeAnswer: before(position('.partner-notice'), position('.answer-row')), toBeforeNotice: before(position('.partner-to'), position('.partner-notice')) };
    });
    expect(order, 'the recipients and the whole notice come before the answer row').toEqual({ toBeforeAnswer: true, noticeBeforeAnswer: true, toBeforeNotice: true });
    await expect(card.getByRole('button', { name: 'Approve: send a delay notice', exact: true })).toHaveCount(1);
    await expect(card.getByRole('button', { name: 'Reject: send a delay notice', exact: true })).toHaveCount(1);
    await expect(rowOfRequest(page, request).getByRole('button', { name: 'Show in the chat: Send a delay notice', exact: true })).toHaveCount(1);

    const slots = await askedSlots('partner_warning', PARTNER as Record<string, unknown>, incident);
    await sendNotification(user, { kind: 'approval', catalogKey: 'incident.partnerRequest', slots, approvalRef: request, incidentRef: incident });
    const { message } = await phoneShows(page, user, request);
    const text = await messageText(message);
    expect(text, 'the phone holds the whole notice').toContain(NOTICE);
    for (const shown of SHOWN) expect(text, `and the recipient ${shown}, as plain text`).toContain(shown);
    await expect(message.getByRole('button', { name: 'Approve: send a delay notice', exact: true })).toHaveCount(1);
    await expect(message.getByRole('button', { name: 'Reject: send a delay notice', exact: true })).toHaveCount(1);
  } finally {
    await release(user, mine);
  }
});

/** The request of an incident payload: its ref and state, with the kind, the item and the result of a run that has one. */
interface Entry {
  ref: string;
  state: string;
  fixKind: string;
  item?: string;
  count?: number;
  /** The value that a done setting request's dry run gives the setting (DW-1378): the band names it. */
  after?: string;
  result?: Record<string, unknown>;
}

/** The incident payload of a card in this state, with the production, the setting change and these requests. */
const payloadOf = (incident: string, state: string, requests: Entry[]): Record<string, unknown> => ({
  ...incidentOf(incident, []),
  state,
  production: PRODUCTION,
  settingChange: CHANGE,
  requests,
});

/** The press's reply of the answer route. */
function nextReply(page: Page): Promise<Response> {
  return page.waitForResponse((response) => response.request().method() === 'POST' && /\/approvals\/[^/]+\/answer$/.test(new URL(response.url()).pathname));
}

/** The answered request of a fixture: answered from the web by the user at 14:25. */
const answeredWeb = (user: string, action: 'approve' | 'reject'): Record<string, unknown> => ({ answeredAction: action, answeredChannel: 'web', answeredBy: user, answeredAt: today('14:25:00') });

/**
 * F6: one incident with the answered states of the new kinds: a done suspend (its status, its band and the audit line), an expired reroute, a
 * pending resume that is rejected from its phone message (the card's status within 5 s of the reply), and a done rollback with a pending undo,
 * the two cards in the order raised.
 */
test('F6: the new kinds show their answered, expired and done states, and an undo is its own card in the same incident', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  const requests: string[] = [];
  try {
    const incident = await seedIncidentOf(user, mine);
    await open(page);
    const suspend = await raise(page, user, mine.rows, incident, requests, { fixKind: 'suspend_item', dryRun: SUSPEND, state: 'done', raisedAt: today('14:01:00'), ...answeredWeb(user, 'approve') }, false);
    const reroute = await raise(page, user, mine.rows, incident, requests, { fixKind: 'reroute', dryRun: REROUTE, state: 'expired', raisedAt: today('14:02:00'), expiresAt: today('14:20:00') }, false);
    const resume = await raise(page, user, mine.rows, incident, requests, { fixKind: 'resume_item', dryRun: RESUME, raisedAt: today('14:03:00') }, false);
    const rollback = await raise(page, user, mine.rows, incident, requests, { fixKind: 'rollback_setting', dryRun: ROLLBACK, state: 'done', raisedAt: today('14:04:00'), ...answeredWeb(user, 'approve') }, false);
    const undo = await raise(page, user, mine.rows, incident, requests, { fixKind: 'undo_rollback', dryRun: UNDO, raisedAt: today('14:05:00') }, false);
    await applied(
      page,
      await publishIncident(
        user,
        payloadOf(incident, 'awaiting_approval', [
          { ref: suspend, state: 'done', fixKind: 'suspend_item', item: WAREHOUSE, result: DONE_ONE },
          { ref: reroute, state: 'expired', fixKind: 'reroute', item: REVIEW, count: 50 },
          { ref: resume, state: 'pending', fixKind: 'resume_item', item: WAREHOUSE },
          { ref: rollback, state: 'done', fixKind: 'rollback_setting', item: ITEM, after: OLD, result: DONE_ONE },
          { ref: undo, state: 'pending', fixKind: 'undo_rollback', item: ITEM },
        ]),
      ),
    );
    const card = incidentCard(page, incident);
    await expect(card.locator('[data-part="approval"]'), 'every request has a card').toHaveCount(5, { timeout: CARD_MS });
    expect(await card.locator('[data-part="approval"]').evaluateAll((all) => all.map((one) => one.getAttribute('data-key'))), 'in the order raised, the undo after its rollback').toEqual([suspend, reroute, resume, rollback, undo]);

    const suspended = requestCard(page, suspend);
    await expect(suspended.locator('p.status'), 'the done suspend says who answered').toHaveText('Approved from the web chat at 14:25');
    await expect(suspended.locator('[data-part="result"] .text'), 'its band').toHaveText(
      `${WAREHOUSE} in ${PRODUCTION} is suspended: it is disabled now. To undo it while this incident is open, ask me to resume ${WAREHOUSE}. After the incident closes, enable ${WAREHOUSE} again on the production's configuration page in the Management Portal.`,
    );
    await expect(suspended.locator('p.audit'), 'and the audit line').toHaveText('Recorded in the IRIS audit log.');
    await expect(suspended.getByRole('button', { name: /^(Approve|Reject)/ }), 'a done request has no answer buttons').toHaveCount(0);

    const rerouted = requestCard(page, reroute);
    await expect(rerouted.locator('p.status'), 'the expired reroute').toHaveText('Expired at 14:20. Nothing was changed.');
    await expect(rerouted.getByRole('button', { name: /^(Approve|Reject)/ }), 'has no answer buttons').toHaveCount(0);

    const restored = requestCard(page, rollback);
    await expect(restored.locator('p.status'), 'the done rollback').toHaveText('Approved from the web chat at 14:25');
    await expect(restored.locator('[data-part="result"] .text'), 'has its band').toHaveText(`${SETTING} on ${ITEM} is back to ${OLD}. To undo it, ask me to undo the rollback.`);
    await expect(restored.locator('p.audit')).toHaveText('Recorded in the IRIS audit log.');
    const undoCard = requestCard(page, undo);
    await expect(undoCard.getByRole('button', { name: `Approve: ${lowerFirst(UNDO_KIND.title)}`, exact: true }), 'the undo is its own pending request card').toHaveCount(1);
    await expect(undoCard.locator('.mono.after')).toHaveText(UNDO_KIND.after);

    const resumed = requestCard(page, resume);
    await sendNotification(user, { kind: 'approval', catalogKey: RESUME_KIND.key, slots: await slotsOf(RESUME_KIND, incident), approvalRef: resume, incidentRef: incident });
    const { message } = await phoneShows(page, user, resume);
    const reply = nextReply(page);
    await message.getByRole('button', { name: `Reject: ${lowerFirst(RESUME_KIND.title)}`, exact: true }).click();
    expect((await reply).status(), 'the phone press is answered').toBe(200);
    await expect(resumed.locator('p.status'), 'the card shows the answer within 5 s of the reply').toHaveText(/^Rejected from the simulated phone at \d{1,2}:\d\d\. Nothing was changed\.$/, { timeout: 5000 });
    expect(await readApproval(resume).then((one) => [one.state, one.action, one.channel]), 'the row is rejected from the phone').toEqual(['rejected', 'reject', 'phone']);
  } finally {
    await release(user, mine);
  }
});

/** Settles a request in the store (its state and answer) and has BridgeSink publish it to the page as this event, as the bridge does when the request changes. */
async function settle(page: Page, user: string, request: string, state: string, answered: AnsweredFields, event: 'approval.answered' | 'approval.expired'): Promise<void> {
  await setApprovalState(request, state, answered);
  await applied(page, await sinkEvent(user, event, { ref: request }));
}

/** The incident of a ref as /api/v1/state holds it: its state, or undefined when the state does not list it. */
async function stateOfApi(page: Page, ref: string): Promise<string | undefined> {
  const body: unknown = await (await page.request.get('/ocutalon/api/v1/state')).json();
  const found: string[] = [];
  const walk = (node: unknown): void => {
    if (Array.isArray(node)) node.forEach(walk);
    else if (node !== null && typeof node === 'object') {
      const object = node as Record<string, unknown>;
      if (object['ref'] === ref && typeof object['state'] === 'string' && 'count' in object) found.push(object['state']);
      Object.values(object).forEach(walk);
    }
  };
  walk(body);
  return found[0];
}

/** Closes the incident's row, as IncidentManager does when an incident closes. */
async function closeRow(incident: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set i=##class(OcuTalon.Data.Incident).RefIndexOpen(${quoted(incident)})`,
      `If '$IsObject(i) { Write !,"CHK|closed|0" Halt }`,
      'Set i.State="closed"',
      `Set i.ClosedAt=${quoted(today('14:20:00'))}`,
      'Write !,"CHK|closed|",$System.Status.IsOK(i.%Save())',
    ].join('\n'),
  );
  if (chk(lines, 'closed') !== '1') throw new Error(`the incident could not be closed (${lines.join(' ')})`);
}

/** The Refs of the request cards in an incident card, in order. */
const drawnIn = (card: Locator): Promise<Array<string | null>> => card.locator('[data-part="approval"]').evaluateAll((all) => all.map((one) => one.getAttribute('data-key')));

/** What a closed incident case holds: the incident, its card, the undo's Ref and the Refs of the other requests in the order raised. */
interface Closed {
  incident: string;
  card: Locator;
  undo: string;
  others: string[];
}

/**
 * A closed incident (its row and its card, closed at 14:20) whose store holds pending requests of the other kinds (a repair, a rollback, a
 * suspend and a partner warning) and, raised after the close (14:22), an undo: the base of F6b. The card is open on the page when it returns.
 */
async function closedWithUndo(page: Page, user: string, mine: Held): Promise<Closed> {
  const incident = await seedIncidentOf(user, mine, 'closed');
  await open(page);
  const card = incidentCard(page, incident);
  await applied(page, await publishIncident(user, payloadOf(incident, 'closed', [])));
  await expect(card.locator('.chip'), 'the incident is closed').toHaveText('Closed', { timeout: CARD_MS });
  const none: string[] = [];
  const others = [
    await raise(page, user, mine.rows, incident, none, { raisedAt: today('14:13:00') }, false),
    await raise(page, user, mine.rows, incident, none, { fixKind: 'rollback_setting', dryRun: ROLLBACK, raisedAt: today('14:14:00') }, false),
    await raise(page, user, mine.rows, incident, none, { fixKind: 'suspend_item', dryRun: SUSPEND, raisedAt: today('14:15:00') }, false),
    await raise(page, user, mine.rows, incident, none, { fixKind: 'partner_warning', dryRun: PARTNER, raisedAt: today('14:16:00') }, false),
  ];
  const undo = await raise(page, user, mine.rows, incident, none, { fixKind: 'undo_rollback', dryRun: UNDO, raisedAt: today('14:22:00') }, false);
  return { incident, card, undo, others };
}

/** Publishes the closed incident with its requests as they stand, and waits until the page applied it. */
async function publishClosed(page: Page, user: string, closed: Closed, entries: Entry[]): Promise<void> {
  await applied(page, await publishIncident(user, payloadOf(closed.incident, 'closed', entries)));
}

/** The kinds of the entries of the other requests, as the incident's payload names them. */
const KINDS = ['repair_resend', 'rollback_setting', 'suspend_item', 'partner_warning'];

/** The payload entries of the other requests of a closed case. */
const othersOf = (closed: Closed): Entry[] => closed.others.map((ref, index) => ({ ref, state: 'pending', fixKind: KINDS[index] ?? 'repair_resend' }));

/**
 * F6b: a closed incident (the row and the card closed before the undo is raised) with a pending undo, a pending repair, rollback, suspend and
 * partner warning draws the undo's request card and no other, with Show details on its row and no incident-level actions row. "Show in the
 * chat" focuses the undo's card. The scans pass in both schemes and Tab reaches Approve, Reject and Show details in that order, each with a
 * focus ring. Once the undo is rejected or expired, no request card is drawn and the card has no band; once it is done with a result, no
 * request card is drawn and its band shows once among the compact bands.
 */
test('F6b: a closed card draws the pending undo and no other request, the rail jump focuses it, and the card passes the scans', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const closed = await closedWithUndo(page, user, mine);
    const { card, undo, others } = closed;
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: undo, state: 'pending', fixKind: 'undo_rollback', item: ITEM }]);
    const undoCard = requestCard(page, undo);
    await expect(undoCard, 'the undo has its request card on the closed incident').toHaveCount(1, { timeout: CARD_MS });
    expect(await drawnIn(card), 'and it is the only request card').toEqual([undo]);
    for (const other of others) await expect(requestCard(page, other), 'no other kind has a card').toHaveCount(0);
    await expect(card.locator('.chip'), 'the card is still closed').toHaveText('Closed');
    await expect(undoCard.locator('.mono.before')).toHaveText(UNDO_KIND.before);
    await expect(undoCard.locator('.mono.after')).toHaveText(UNDO_KIND.after);
    await expect(undoCard.locator('.dry-note'), 'a dry run with nothing changed yet').toHaveText('Nothing has changed yet.');
    await expect(undoCard.getByRole('button', { name: `Approve: ${lowerFirst(UNDO_KIND.title)}`, exact: true })).toHaveCount(1);
    await expect(undoCard.getByRole('button', { name: `Reject: ${lowerFirst(UNDO_KIND.title)}`, exact: true })).toHaveCount(1);
    await expect(undoCard.locator('p.expiry'), 'with its expiry').toHaveCount(1);
    await expect(undoCard.getByRole('button', { name: 'Show details', exact: true }), 'Show details is at its row\'s end').toHaveCount(1);
    await expect(card.getByRole('button', { name: 'Show details', exact: true }), 'and is the only one of the incident').toHaveCount(1);
    await expect(card.locator(':scope > .actions'), 'the incident-level actions row is gone').toHaveCount(0);
    for (const other of others) await expect(rowOfRequest(page, other), 'the other requests stay on the rail').toHaveCount(1);

    const jump = rowOfRequest(page, undo).getByRole('button', { name: `Show in the chat: ${UNDO_KIND.title}`, exact: true });
    await expect(jump).toHaveCount(1);
    await scrollListTo(page.locator('app-chat-panel .list'), 'top');
    await composerOf(page).click();
    await jump.click();
    await expect(undoCard, 'the rail jump focuses the undo card in the chat').toBeFocused();

    for (const scheme of ['light', 'dark'] as const) {
      await page.emulateMedia({ colorScheme: scheme });
      const what = `step 5 closed card, ${scheme}`;
      expect([...(await scanNames(page, what)), ...(await scanContrast(page, what))], what).toEqual([]);
    }

    await composerOf(page).focus();
    const stops: string[] = [];
    for (let i = 0; i < MOST_STOPS && !stops.includes('Show details'); i += 1) {
      await page.keyboard.press('Tab');
      const reading = await undoCard.evaluate((el) => {
        const active = document.activeElement;
        if (active === null || !el.contains(active)) return null;
        const style = getComputedStyle(active);
        return { name: active.getAttribute('aria-label') ?? (active.textContent ?? '').trim(), style: style.outlineStyle, width: style.outlineWidth };
      });
      if (reading !== null) {
        stops.push(reading.name);
        expect([reading.style, reading.width], `${reading.name} has a visible focus ring`).toEqual(['solid', '2px']);
      }
    }
    expect(stops, 'Tab reaches Approve, Reject and Show details in that order').toEqual([`Approve: ${lowerFirst(UNDO_KIND.title)}`, `Reject: ${lowerFirst(UNDO_KIND.title)}`, 'Show details']);

    // The incident's payload gives the still pending undo a result (the two arrive apart): its band is on its card only, never also among the compact bands.
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: undo, state: 'done', fixKind: 'undo_rollback', item: ITEM, after: NEW, result: DONE_ONE }]);
    await expect(undoCard.locator('[data-part="result"]'), 'a drawn undo\'s band is on its own card').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('[data-part="result"]'), 'and shows once in the incident card').toHaveCount(1);
    expect(await drawnIn(card), 'the pending undo is still the only request card').toEqual([undo]);

    // The undo is rejected: no request card of it is drawn, there is no band, and no other kind appears.
    await settle(page, user, undo, 'rejected', { action: 'reject', channel: 'phone', by: user, at: today('14:25:00') }, 'approval.answered');
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: undo, state: 'rejected', fixKind: 'undo_rollback', item: ITEM }]);
    await expect(undoCard, 'a rejected undo has no request card on the closed card').toHaveCount(0, { timeout: CARD_MS });
    expect(await drawnIn(card), 'and no request card is drawn at all').toEqual([]);
    await expect(card.locator('[data-part="result"]'), 'fixture check: the payload gives the rejected undo no result, so no band').toHaveCount(0);
    await expect(card.getByRole('button', { name: 'Show details', exact: true }), 'the incident-level Show details row is back').toHaveCount(1);

    // The undo expires (an expired request carries no answer): no request card of it is drawn either.
    await settle(page, user, undo, 'expired', { action: '', channel: '', by: '', at: '', expiresAt: today('14:26:00') }, 'approval.expired');
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: undo, state: 'expired', fixKind: 'undo_rollback', item: ITEM }]);
    await expect(undoCard, 'an expired undo has no request card').toHaveCount(0);
    expect(await drawnIn(card), 'no request card is drawn').toEqual([]);
    await expect(card.locator('[data-part="result"]'), 'fixture check: the payload gives the expired undo no result, so no band').toHaveCount(0);

    // The undo is done with a result: no request card, and its band shows once, among the compact bands.
    await settle(page, user, undo, 'done', { action: 'approve', channel: 'web', by: user, at: today('14:27:00') }, 'approval.answered');
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: undo, state: 'done', fixKind: 'undo_rollback', item: ITEM, after: NEW, result: DONE_ONE }]);
    await expect(card.locator('[data-part="result"]'), 'the done undo\'s band shows once in the incident card').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('[data-part="result"] .text'), 'with the catalog\'s text').toHaveText(`The rollback is undone: ${SETTING} on ${ITEM} is back to ${NEW}.`);
    await expect(card.locator('p.audit'), 'and its audit line').toHaveText('Recorded in the IRIS audit log.');
    await expect(undoCard, 'the done undo has no request card').toHaveCount(0);
    expect(await drawnIn(card), 'and no other kind is drawn').toEqual([]);

    // A done rollback is not drawn either, and its band is among the compact bands beside the done undo's; a new pending undo has its card.
    const done = await raise(page, user, mine.rows, closed.incident, [], { fixKind: 'rollback_setting', dryRun: ROLLBACK, state: 'done', raisedAt: today('14:12:00'), ...answeredWeb(user, 'approve') }, false);
    const second = await raise(page, user, mine.rows, closed.incident, [], { fixKind: 'undo_rollback', dryRun: UNDO, raisedAt: today('14:28:00') }, false);
    await publishClosed(page, user, closed, [
      ...othersOf(closed),
      { ref: done, state: 'done', fixKind: 'rollback_setting', item: ITEM, after: OLD, result: DONE_ONE },
      { ref: undo, state: 'done', fixKind: 'undo_rollback', item: ITEM, after: NEW, result: DONE_ONE },
      { ref: second, state: 'pending', fixKind: 'undo_rollback', item: ITEM },
    ]);
    await expect(requestCard(page, second), 'the pending undo has its card').toHaveCount(1, { timeout: CARD_MS });
    expect(await drawnIn(card), 'and it is the only request card').toEqual([second]);
    await expect(card.locator('[data-part="result"]:not([data-part="approval"] [data-part="result"])'), 'the rollback\'s and the done undo\'s bands are the compact bands').toHaveCount(2);
    await expect(card.locator('[data-part="result"] .text'), 'each once, in payload order').toHaveText([
      `${SETTING} on ${ITEM} is back to ${OLD}. To undo it, ask me to undo the rollback.`,
      `The rollback is undone: ${SETTING} on ${ITEM} is back to ${NEW}.`,
    ]);
    await expect(requestCard(page, done), 'the done rollback has no request card').toHaveCount(0);
  } finally {
    await release(user, mine);
  }
});

/** What an answer leaves: the answer route's reply (the approval it returns), the stored row, the number of trace headers it made, and its Approval audit entry. */
interface Answered {
  reply: { state: string; action: string; channel: string; by: string };
  row: { state: string; action: string; channel: string; by: string };
  headers: number;
  audit: ApprovalAudit[];
}

/** The reply's approval fields that an answer fixes. */
interface Reply {
  approval?: { ref?: string; state?: string; answeredAction?: string; answeredChannel?: string; answeredBy?: string };
}

/** The answer route of every request. */
const ANSWER = '**/ocutalon/api/v1/approvals/*/answer';

/**
 * Presses Approve or Reject on a request card and proves the answer from its reply (200, the approval it returns), from the stored row,
 * from the one AnswersIn to AnswerOps header it leaves and from the one Approval audit entry the answer wrote (Bridge.Approval Audited). The reply is read through a route that fetches it from the test's side and hands it
 * on: the card of an answered undo on a closed incident is not drawn any more, and the page drops the card's call with the card (the live
 * answer event can reach the page before the reply), so the page's own response event may never fire. On an open card the status shows too
 * (expectAnsweredStatus).
 */
async function answerFromCard(page: Page, user: string, card: Locator, request: string, title: string, action: 'approve' | 'reject'): Promise<Answered> {
  const before = (await answerHeaders(user)).count;
  const mark = await auditClock();
  const seen: Array<{ status: number; text: string }> = [];
  const through = async (route: Route): Promise<void> => {
    try {
      const response = await route.fetch();
      seen.push({ status: response.status(), text: await response.text() });
      await route.fulfill({ response }).catch(() => undefined);
    } catch (error) {
      seen.push({ status: -1, text: String(error) });
    }
  };
  await page.route(ANSWER, through);
  try {
    await card.getByRole('button', { name: `${action === 'approve' ? 'Approve' : 'Reject'}: ${lowerFirst(title)}`, exact: true }).click();
    await expect.poll(() => seen.length, { message: 'the answer route replied', timeout: 30_000 }).toBe(1);
  } finally {
    await page.unroute(ANSWER, through);
  }
  expect(seen[0]?.status, `the answer is 200 (${seen[0]?.status === -1 ? seen[0].text : 'replied'})`).toBe(200);
  const body = JSON.parse(seen[0]?.text ?? '{}') as Reply;
  expect(body.approval?.ref, 'the reply is the request\'s approval').toBe(request);
  await expect.poll(async () => (await answerHeaders(user)).count - before, { message: 'the answer left one AnswersIn to AnswerOps header', timeout: CARD_MS }).toBe(1);
  const row = await readApproval(request);
  return {
    reply: { state: body.approval?.state ?? '', action: body.approval?.answeredAction ?? '', channel: body.approval?.answeredChannel ?? '', by: body.approval?.answeredBy ?? '' },
    row: { state: row.state, action: row.action, channel: row.channel, by: row.by },
    headers: (await answerHeaders(user)).count - before,
    audit: await approvalAudit(mark, request),
  };
}

/** The status an open card shows after an answer, until the card is read. */
async function expectAnsweredStatus(card: Locator, action: 'approve' | 'reject'): Promise<void> {
  await expect(card.locator('p.status'), 'the open card shows the answer').toHaveText(action === 'approve' ? /^Approved from the web chat at \d{1,2}:\d\d$/ : /^Rejected from the web chat at \d{1,2}:\d\d\. Nothing was changed\.$/, { timeout: 30_000 });
}

/** Expects the incident to be closed on the card, in its row and in /api/v1/state. */
async function expectStillClosed(page: Page, card: Locator, incident: string): Promise<void> {
  await expect(card.locator('.chip'), 'the chip stays Closed').toHaveText('Closed');
  expect(await incidentState(incident), 'the incident\'s row stays closed').toBe('closed');
  expect(await stateOfApi(page, incident), 'and /api/v1/state says closed').toBe('closed');
}

/** The Refs of the session's pending approval requests in /api/v1/state (its rail): an answered request is no longer in it. */
async function pendingInState(page: Page): Promise<string[]> {
  const body = (await (await page.request.get('/ocutalon/api/v1/state')).json()) as { rail?: { approvals?: Array<{ ref?: string; state?: string }> } };
  return (body.rail?.approvals ?? []).filter((one) => one.state === 'pending').map((one) => one.ref ?? '');
}

/** The text the page announces and shows for an answered undo, from the web chat: the catalog's answered text (the page's form, as the open card's status shows it). */
const ANSWERED_TEXT = {
  approve: /^Approved from the web chat at \d{1,2}:\d\d$/,
  reject: /^Rejected from the web chat at \d{1,2}:\d\d\. Nothing was changed\.$/,
} as const;

/** The announcements of this page load that name an answer from any channel, in order, each as the one sentence it holds (the announcer joins the texts of one update). */
async function answerAnnouncements(page: Page): Promise<string[]> {
  return (await announcedTexts(page)).flatMap((entry) => entry.match(/(?:Approved|Rejected) from (?:the web chat|the simulated phone) at \d{1,2}:\d\d(?:\. Nothing was changed\.)?/g) ?? []);
}

/**
 * What an undo answered from its card leaves on a closed card: no request card of it (nor of another kind), the answered text announced
 * once through the page's live region (the existing "Approved from the web chat at {time}" or "Rejected from the web chat at {time}.
 * Nothing was changed." text, and nothing a second time, after a wait longer than the announcer's gap), focus on the incident's headline
 * (the chat's focus rule alone would leave it on the main region), the incident's own Show details row, and the incident closed.
 */
async function expectAnsweredAway(page: Page, closed: Closed, request: string, action: 'approve' | 'reject'): Promise<void> {
  await expect(requestCard(page, request), 'the answered undo is not drawn any more').toHaveCount(0, { timeout: CARD_MS });
  await expect.poll(async () => (await answerAnnouncements(page)).length, { message: 'the answer is announced', timeout: CARD_MS }).toBe(1);
  await expect(closed.card.locator('h3.headline'), 'focus is on the incident\'s headline, not the main region or the body').toBeFocused();
  await page.waitForTimeout(1500);
  const said = await answerAnnouncements(page);
  expect(said, 'the answer is announced once, with the answered text').toHaveLength(1);
  expect(said[0], 'the text is the existing answered text').toMatch(ANSWERED_TEXT[action]);
  expect(await drawnIn(closed.card), 'no request card of any kind is drawn').toEqual([]);
  await expect(closed.card.getByRole('button', { name: 'Show details', exact: true }), 'the incident-level Show details row is back').toHaveCount(1);
  expect(await pendingInState(page), 'the state no longer lists the undo as pending').not.toContain(request);
  await expectStillClosed(page, closed.card, closed.incident);
}

/**
 * F6b (b1), once with Approve and once with Reject: an undo raised before the close, then the incident is closed (the request is raised and
 * the open card published, then the row and the card are closed): the closed card shows it, and the answer pressed on it is recorded exactly
 * as the same answer on an open incident's card (the same reply, the same stored row, one trace header, the same Approval audit entry), does
 * not reopen the incident, and the card is gone once the answer lands. An approved undo's done result then has its one band among the
 * compact bands, with the audit line; a rejected one has no band.
 */
for (const action of ['approve', 'reject'] as const) {
  test(`F6b: an undo raised before the close is drawn on the closed card, and ${action === 'approve' ? 'Approve' : 'Reject'} on it is answered and audited as on an open card`, async ({ page }) => {
    const { user } = fixtureUser(KIND);
    const mine = held();
    const state = action === 'approve' ? 'approved' : 'rejected';
    try {
      const incident = await seedIncidentOf(user, mine);
      const control = await seedIncidentOf(user, mine);
      await open(page);
      const card = incidentCard(page, incident);
      const undo = await raise(page, user, mine.rows, incident, [], { fixKind: 'undo_rollback', dryRun: UNDO, raisedAt: today('14:13:00') });
      const undoCard = requestCard(page, undo);
      await expect(undoCard, 'the undo has a card while the incident is open').toHaveCount(1, { timeout: CARD_MS });
      await expect(card.locator('.chip')).toHaveText('Awaiting approval');
      await closeRow(incident);
      await applied(page, await publishIncident(user, payloadOf(incident, 'closed', [{ ref: undo, state: 'pending', fixKind: 'undo_rollback', item: ITEM }])));
      await expect(card.locator('.chip'), 'the incident is closed after the undo was raised').toHaveText('Closed', { timeout: CARD_MS });
      await expect(undoCard, 'the closed card still shows the pending undo').toHaveCount(1);
      expect(await drawnIn(card)).toEqual([undo]);
      await expect(undoCard.getByRole('button', { name: 'Show details', exact: true })).toHaveCount(1);

      const onClosed = await answerFromCard(page, user, undoCard, undo, UNDO_KIND.title, action);
      await expectAnsweredAway(page, { incident, card, undo, others: [] }, undo, action);

      const openUndo = await raise(page, user, mine.rows, control, [], { fixKind: 'undo_rollback', dryRun: UNDO, raisedAt: today('14:13:00') });
      const openCard = requestCard(page, openUndo);
      await expect(openCard).toHaveCount(1, { timeout: CARD_MS });
      const onOpen = await answerFromCard(page, user, openCard, openUndo, UNDO_KIND.title, action);
      await expectAnsweredStatus(openCard, action);
      await page.waitForTimeout(1500);
      expect(await answerAnnouncements(page), 'an open card\'s answer adds no announcement of its own: only the closed card\'s answer was announced').toHaveLength(1);
      expect(onClosed, 'the answer from the closed card is recorded and audited as the open card\'s').toEqual(onOpen);
      expect(onClosed.row, `${state} from the web by the user`).toEqual({ state, action, channel: 'web', by: user });
      expect(onClosed.reply, 'and the reply says so').toEqual({ state, action, channel: 'web', by: user });
      expect(onClosed.audit, 'with one Approval audit entry of the answer').toEqual([{ change: 'answered', from: 'pending', to: state, irisUser: user, channel: 'web', kind: 'fix' }]);

      if (action === 'approve') {
        await settle(page, user, undo, 'done', {}, 'approval.answered');
        await applied(page, await publishIncident(user, payloadOf(incident, 'closed', [{ ref: undo, state: 'done', fixKind: 'undo_rollback', item: ITEM, after: NEW, result: DONE_ONE }])));
        await expect(card.locator('[data-part="result"]'), 'the done undo has one band, among the compact bands').toHaveCount(1, { timeout: CARD_MS });
        await expect(card.locator('p.audit'), 'with the audit line, as on an open card').toHaveText('Recorded in the IRIS audit log.');
      } else {
        await expect(card.locator('[data-part="result"]'), 'fixture check: the payload gives the rejected undo no result, so no band').toHaveCount(0);
      }
      await expect(undoCard, 'and no request card').toHaveCount(0);
      await expectStillClosed(page, card, incident);
    } finally {
      await release(user, mine);
    }
  });
}

/** F6b (c): Approve on the undo of a closed card leaves the incident closed. */
test('F6b: approving an undo from a closed card does not reopen the incident or change its state', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const closed = await closedWithUndo(page, user, mine);
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: closed.undo, state: 'pending', fixKind: 'undo_rollback', item: ITEM }]);
    const undoCard = requestCard(page, closed.undo);
    await expect(undoCard).toHaveCount(1, { timeout: CARD_MS });
    expect(await stateOfApi(page, closed.incident), 'the state lists the closed incident').toBe('closed');
    const answered = await answerFromCard(page, user, undoCard, closed.undo, UNDO_KIND.title, 'approve');
    expect(answered.row, 'the undo is approved').toEqual({ state: 'approved', action: 'approve', channel: 'web', by: user });
    expect(answered.reply, 'and the reply says so').toEqual({ state: 'approved', action: 'approve', channel: 'web', by: user });
    await expectAnsweredAway(page, closed, closed.undo, 'approve');
  } finally {
    await release(user, mine);
  }
});

/** F6b (d): an undo answered from the phone while focus is outside its card is announced once and takes no focus. */
test('F6b: an undo answered elsewhere while focus is outside its card is announced once and does not move focus', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const closed = await closedWithUndo(page, user, mine);
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: closed.undo, state: 'pending', fixKind: 'undo_rollback', item: ITEM }]);
    const undoCard = requestCard(page, closed.undo);
    await expect(undoCard).toHaveCount(1, { timeout: CARD_MS });
    await page.evaluate(() => (document.activeElement instanceof HTMLElement ? document.activeElement.blur() : undefined));
    await settle(page, user, closed.undo, 'rejected', { action: 'reject', channel: 'phone', by: user, at: today('14:25:00') }, 'approval.answered');
    await publishClosed(page, user, closed, othersOf(closed));
    await expect(undoCard, 'the answered undo is not drawn any more').toHaveCount(0, { timeout: CARD_MS });
    await expect.poll(async () => (await answerAnnouncements(page)).length, { message: 'the answer is announced', timeout: CARD_MS }).toBe(1);
    await page.waitForTimeout(1500);
    const said = await answerAnnouncements(page);
    expect(said, 'the answer is announced once').toHaveLength(1);
    expect(said[0], 'with the existing answered text of the channel that answered').toMatch(/^Rejected from the simulated phone at \d{1,2}:\d\d\. Nothing was changed\.$/);
    await expect(closed.card.locator('h3.headline'), 'focus was not in the request card, so the headline does not take it').not.toBeFocused();
  } finally {
    await release(user, mine);
  }
});

/** F6b (c): Reject on the undo of a closed card leaves the incident closed. */
test('F6b: rejecting an undo from a closed card does not reopen the incident or change its state', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const mine = held();
  try {
    const closed = await closedWithUndo(page, user, mine);
    await publishClosed(page, user, closed, [...othersOf(closed), { ref: closed.undo, state: 'pending', fixKind: 'undo_rollback', item: ITEM }]);
    const undoCard = requestCard(page, closed.undo);
    await expect(undoCard).toHaveCount(1, { timeout: CARD_MS });
    expect(await stateOfApi(page, closed.incident), 'the state lists the closed incident').toBe('closed');
    const answered = await answerFromCard(page, user, undoCard, closed.undo, UNDO_KIND.title, 'reject');
    expect(answered.row, 'the undo is rejected').toEqual({ state: 'rejected', action: 'reject', channel: 'web', by: user });
    expect(answered.reply, 'and the reply says so').toEqual({ state: 'rejected', action: 'reject', channel: 'web', by: user });
    await expectAnsweredAway(page, closed, closed.undo, 'reject');
    await expect(closed.card.locator('[data-part="result"]'), 'fixture check: the payload gives the rejected undo no result, so no band').toHaveCount(0);
  } finally {
    await release(user, mine);
  }
});
