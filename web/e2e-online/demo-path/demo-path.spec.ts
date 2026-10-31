import { randomBytes } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import { notBuilt } from '../../e2e/demo-path/not-built';
import { EVENTS, post, type LiveEvent } from '../../e2e/support/api';
import {
  BREAK_FEED,
  approvalCard,
  approvalCount,
  approvalRows,
  approveOnPhone,
  breakFeedButton,
  checkRow,
  doneTurn,
  expectGuideMessage,
  expectIncidentAwaitingApproval,
  guideSend,
  incidentCard,
  phoneNotes,
  readState,
  reminderThroughGuide,
  WATCH_PROMPT,
  watchThroughGuide,
  type Snapshot,
} from '../../e2e/support/demo-path';
import { loadedAfter } from '../../e2e/support/floor';
import { fixtureUser, readApproval } from '../../e2e/support/iris';
import { drawnMessages, type Turn } from '../../e2e/support/trace';
import {
  cleanPopulated,
  epochOf,
  expectOpenedDirectly,
  leaveVisitor,
  openVisitor,
  opensTabStrict,
  ordersOf,
  populate,
  removeSession,
  seedIncomingMail,
  sessionRow,
  signInFromSplash,
  signOutGroup,
  type Populated,
  type Visitor,
} from '../support';

/**
 * REL-2's online run (Story 16.2, Story 29.4): the UJ-1 path as a judge walks it on the online demo, with the model keys pointed at the CI
 * mock. It has its own project and unit (online-demo-path, docker/tests/test-online-demo-path.sh) on a flag-on throwaway with the test
 * start values: a fresh browser context opens the splash and finds the published demo credentials prefilled.
 * - Step 1 is real: the button signs in without typing and the page loads.
 * - Steps 2 to 5 are one visitor's journey through the step functions of web/e2e/support/demo-path.ts, which the web run's 02 to 05 call
 *   too (Story 11.7, DW-221): the guide's own Send for the watch and for the reminder, Break the feed and the incident awaiting approval
 *   (the phone's notice and "Approval requests, 1"), and Approve on the simulated phone to "All 50 orders went through.", the audit line and
 *   Resolved. They run in order on one session, as the web run's do, and skip the heartbeat's last-run wait that the web run proves.
 * - Step 6 is real: the guide's watch prompt gets its reply, and the reply's Trace link opens Visual Trace at the turn, signed in, drawing
 *   the turn's header and its agent steps, with the steps and the cost in the decision's details.
 * - "Second visitor" is the isolation run (Story 29.4): visitors A and B each watch Orders (through the guide's Send), A presses Break the feed, and A's incident, its
 *   notice and its approval request reach only A; B's page, /state and /events get nothing, an answer of B to A's request is refused as
 *   an unknown request, and A answers on its simulated phone.
 * - The paired chat and the message search wait for Story 31.4 (a paired mock Telegram chat).
 * The unit fails when a case that must be skipped passes, or one is missing. The texts are written out here, as the independent oracle of
 * the page's own.
 */

const APPROVALS = '/ocutalon/api/v1/approvals';
const FIFTY = 50;

/** The rows of a session that the cases follow: its chat turns, reminders, checks, pairing name and mail items. */
interface OwnRows {
  turns: string[];
  reminders: string[];
  checks: string[];
  pairing: string;
  mail: string[];
}

function ownRows(snapshot: Snapshot): OwnRows {
  return {
    turns: snapshot.chat.filter((item) => item.type === 'chat.message').map((item) => String(item.payload['ref'])),
    reminders: snapshot.rail.reminders.map((item) => item.ref),
    checks: snapshot.rail.checks.map((item) => item.ref),
    pairing: snapshot.telegram.displayName,
    mail: (snapshot.mailbox ?? []).map((item) => item.ref),
  };
}

/** The cursors of the page's own streams, from /state. */
interface Cursors {
  session: number;
  instance: number;
}

/** Every event after the cursors on both streams, as the page's own /events serves them, with the bodies' text. */
async function eventsSince(page: Page, from: Cursors): Promise<{ events: LiveEvent[]; text: string }> {
  const events: LiveEvent[] = [];
  let text = '';
  const cursor = { ...from };
  for (let polls = 0; polls < 20; polls += 1) {
    const response = await page.request.get(`${EVENTS}?after=${cursor.session}&afterInstance=${cursor.instance}`);
    expect(response.status(), 'the events are served').toBe(200);
    const body = await response.text();
    const served = (JSON.parse(body) as { events: LiveEvent[] }).events;
    if (served.length === 0) break;
    text += body;
    events.push(...served);
    for (const event of served) {
      if (event.stream === 'session') cursor.session = Math.max(cursor.session, event.seq);
      else cursor.instance = Math.max(cursor.instance, event.seq);
    }
  }
  return { events, text };
}

/** The event types that only A's run may give A's session. */
const A_ONLY = ['incident', 'approval', 'phone', 'breakfeed.progress', 'watch.progress'];

/** Presses the guide's own Send at step 1, which asks the chat to watch the Orders production, and waits for the check row. */
async function askToWatch(page: Page): Promise<void> {
  await expect(guideSend(page), "the guide's Send is usable").not.toHaveAttribute('aria-disabled', 'true');
  await guideSend(page).click();
  await expectGuideMessage(page, WATCH_PROMPT);
  await expect(checkRow(page), 'the "Orders production" check row shows').toHaveCount(1, { timeout: 90_000 });
}

test('step 1: the splash holds the published credentials, and Sign in and start opens the page', async ({ page }) => {
  try {
    const { user, password } = fixtureUser('DEMOACCOUNT');
    await page.goto(`/ocutalon/?probe=${Date.now()}`);
    await expect(page).toHaveTitle('Try OcuTalon');
    await expect(page.getByLabel('User name', { exact: true }), 'the user name is the published demo user').toHaveValue(user);
    await expect(page.getByLabel('Password', { exact: true }), 'the password is the published demo password').toHaveValue(password);
    await loadedAfter(page, () => page.getByRole('button', { name: 'Sign in and start', exact: true }).click());
    await expect(page).toHaveTitle('OcuTalon');
  } finally {
    await signOutGroup(page);
  }
});

test.describe('steps 2 to 5: one visitor watches Orders, sets a reminder, breaks the feed and approves the fix', () => {
  test.describe.configure({ mode: 'serial' });
  let visitor: Visitor | undefined;
  let request = '';

  test.beforeAll(async ({ browser }) => {
    test.setTimeout(120_000);
    // The page writes its times in the context's zone and locale: the same UTC and 24-hour clock as the web run, so that the texts match.
    visitor = await openVisitor(browser, undefined, { timezoneId: 'UTC', locale: 'en-GB' });
  });

  test.afterAll(async () => {
    test.setTimeout(120_000);
    if (visitor === undefined) return;
    try {
      await cleanPopulated({ session: visitor.ref, reminder: '', approval: '', pairing: '' });
    } finally {
      await leaveVisitor(visitor);
    }
  });

  const pageOf = (): Page => {
    if (visitor === undefined) throw new Error('the visitor could not be opened');
    return visitor.page;
  };

  test("step 2: the guide's Send for step 1 gets a decision with its reason and trace link, the check row shows, and Break the feed becomes active", async () => {
    test.setTimeout(180_000);
    await watchThroughGuide(pageOf());
  });

  test("step 3: the guide's Send for step 2 sets the reminder, which shows with its countdown", async () => {
    test.setTimeout(120_000);
    await reminderThroughGuide(pageOf());
  });

  test('step 4: Break the feed leads to one incident card awaiting approval, with the phone\'s notice and "Approval requests, 1"', async () => {
    test.setTimeout(180_000);
    const page = pageOf();
    const pressed = page.waitForResponse((response) => response.url().includes(BREAK_FEED) && response.request().method() === 'POST');
    await breakFeedButton(page).click();
    expect((await pressed).status(), 'Break the feed answers 200').toBe(200);
    request = await expectIncidentAwaitingApproval(page);
  });

  test('step 5: Approve on the phone ends with "All 50 orders went through.", the audit line and Resolved, and the request leaves the rail', async () => {
    test.setTimeout(240_000);
    expect(request, 'step 4 found the approval request').not.toBe('');
    await approveOnPhone(pageOf(), request);
  });
});

test('step 6: the trace link opens Visual Trace at the conversation, signed in, with the turn, its agent steps and the cost', async ({ page, context }) => {
  test.setTimeout(240_000);
  let epoch = '';
  try {
    await loadedAfter(page, () => signInFromSplash(page));
    epoch = await epochOf(page);
    await expect(guideSend(page), "the guide's prompt button is usable").not.toHaveAttribute('aria-disabled', 'true');
    await guideSend(page).click();
    const turn = await doneTurn(page);
    const decision = turn.decision as (Turn['decision'] & { agentStepCount?: number; costUSD?: number }) | undefined;
    expect(decision, "the turn shows a decision with a trace target of its own").toBeDefined();
    const agentSteps = decision?.agentStepCount ?? 0;
    expect(agentSteps, "the decision counts its agent steps (each model call is one), so the checks below are the turn's own").toBeGreaterThan(0);

    const reply = page.locator(`app-chat-panel [data-part="reply"][data-key="${turn.clientId}"]`);
    const link = reply.locator('app-decision-strip app-trace-link a');
    await expect(link, 'the turn has its Trace link').toHaveCount(1, { timeout: 30_000 });
    await expect(link).toHaveAccessibleName('Trace (opens in a new tab)');
    const opened = await opensTabStrict(context, () => link.click());
    await expectOpenedDirectly(opened, turn, 'the Trace link');
    const drawn = await drawnMessages(opened.popup);
    expect(drawn.ids.length, `Visual Trace draws the turn's header and at least its ${agentSteps} agent step message(s) (it draws ${drawn.ids.join(' ')})`).toBeGreaterThanOrEqual(1 + agentSteps);
    await opened.popup.close();

    await reply.getByRole('button', { name: 'Decision details' }).click();
    const details = reply.locator('dl.details');
    await expect(details, "the decision's details open").toBeVisible();
    await expect(details.locator('dt:has-text("Agent steps") + dd'), "the details show the decision's agent steps").toHaveText(String(agentSteps));
    await expect(details.locator('dt:has-text("Cost") + dd'), 'and its cost').toHaveText(/\$\d/);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') {
      const row = await sessionRow(epoch);
      await removeSession(epoch);
      if (row !== undefined) await cleanPopulated({ session: row.ref, reminder: '', approval: '', pairing: '' });
    }
  }
});

test('second visitor: A breaks the feed and its incident, notice and approval request reach only A; B gets nothing and cannot answer', async ({ browser }) => {
  test.setTimeout(300_000);
  const visitors: Visitor[] = [];
  const populated: Populated[] = [];
  try {
    // 1. A and B, in two contexts that sign in from the splash.
    const a = await openVisitor(browser);
    visitors.push(a);
    const b = await openVisitor(browser);
    visitors.push(b);
    expect(a.epoch, 'two sessions').not.toBe(b.epoch);

    // 2. Each session's seeded rows: a reminder, a fixture pairing and one incoming mail.
    const aRows = await populate(a.ref, { watch: false, approval: false, pairing: 'Ana' });
    populated.push(aRows);
    const bRows = await populate(b.ref, { watch: false, approval: false, pairing: 'Ben' });
    populated.push(bRows);
    await seedIncomingMail(a.epoch, 1, 60);
    await seedIncomingMail(b.epoch, 1, 60);

    // 3. Each watches Orders from its page and waits for its check row and its done turn.
    await askToWatch(a.page);
    await askToWatch(b.page);
    const aTurn = await doneTurn(a.page);
    const bTurn = await doneTurn(b.page);
    await expect(breakFeedButton(a.page), "A's Break the feed is enabled").not.toHaveAttribute('aria-disabled', 'true', { timeout: 30_000 });
    await expect(breakFeedButton(b.page), "B's Break the feed is enabled").not.toHaveAttribute('aria-disabled', 'true', { timeout: 30_000 });

    // 4. B's page, state and cursors, and A's rows, before the press.
    const aBefore = (await readState(a.page)).snapshot;
    const bBeforeRead = await readState(b.page);
    const bBefore = bBeforeRead.snapshot;
    const bCursors: Cursors = { session: bBefore.streams.session, instance: bBefore.streams.instance };
    const bNotesBefore = await phoneNotes(b.page).count();
    const aOwn: OwnRows = { turns: [aTurn.ref], reminders: [aRows.reminder], checks: aBefore.rail.checks.map((item) => item.ref), pairing: 'Ana', mail: (aBefore.mailbox ?? []).map((item) => item.ref) };
    const bOwn: OwnRows = { turns: [bTurn.ref], reminders: [bRows.reminder], checks: bBefore.rail.checks.map((item) => item.ref), pairing: 'Ben', mail: (bBefore.mailbox ?? []).map((item) => item.ref) };
    expect(ownRows(aBefore), "before the press, A's state shows exactly A's turn, reminder, check, pairing name and mail item").toEqual(aOwn);
    expect(ownRows(bBefore), "and B's exactly B's").toEqual(bOwn);
    expect([aOwn.checks.length, aOwn.mail.length, bOwn.checks.length, bOwn.mail.length], 'one check and one mail item each').toEqual([1, 1, 1, 1]);
    const aRefs = [...aOwn.turns, ...aOwn.reminders, ...aOwn.checks, ...aOwn.mail];
    const bRefs = [...bOwn.turns, ...bOwn.reminders, ...bOwn.checks, ...bOwn.mail];
    for (const ref of bRefs) expect((await readState(a.page)).text, `A's state holds none of B's rows (${ref})`).not.toContain(ref);
    for (const ref of aRefs) expect(bBeforeRead.text, `B's state holds none of A's rows (${ref})`).not.toContain(ref);

    // 5. A presses Break the feed.
    const pressed = a.page.waitForResponse((response) => response.url().includes(BREAK_FEED) && response.request().method() === 'POST');
    await breakFeedButton(a.page).click();
    expect((await pressed).status(), 'Break the feed answers 200').toBe(200);

    // 6. Row 1: A's incident card with Approve and Reject, the notification on its phone and "Approval requests (1)" in its rail, within 90 s.
    await expect(approvalCard(a.page), "A's chat shows the incident's approval card").toHaveCount(1, { timeout: 90_000 });
    const request = (await approvalCard(a.page).getAttribute('data-key')) ?? '';
    expect(request, "the request's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
    const card = a.page.locator(`app-chat-panel [data-part="approval"][data-key="${request}"]`);
    await expect(card.getByRole('button', { name: /^Approve/ }), 'the card offers Approve').toHaveCount(1);
    await expect(card.getByRole('button', { name: /^Reject/ }), 'and Reject').toHaveCount(1);
    await expect(approvalCount(a.page), 'the rail counts the request').toHaveText('Approval requests, 1');
    await expect(a.page.locator(`app-status-rail li.row[data-row-key="approvals:${request}"]`), 'and lists it').toHaveCount(1);
    let note = '';
    await expect
      .poll(async () => (note = ((await readState(a.page)).snapshot.phone ?? []).find((item) => item.approvalRef === request)?.ref ?? ''), { message: "A's phone has the notice with the request", timeout: 30_000 })
      .not.toBe('');
    const message = a.page.locator(`app-simulated-phone .notification[data-key="${note}"]`);
    await expect(message, "A's simulated phone shows the notification").toHaveCount(1, { timeout: 30_000 });
    const aAfterRead = await readState(a.page);
    const incident = aAfterRead.snapshot.chat.find((item) => item.type === 'incident')?.payload['ref'];
    expect(typeof incident === 'string' && incident !== '', "A's state holds the incident").toBe(true);
    const incidentRef = String(incident);
    await expect(incidentCard(a.page), "A's chat shows the incident card").toHaveCount(1);

    // Row 2: B untouched. B's page gets its time to poll first.
    await b.page.waitForTimeout(4_000);
    await expect(incidentCard(b.page), "B's chat has no incident card").toHaveCount(0);
    await expect(approvalCard(b.page), 'and no approval request card').toHaveCount(0);
    await expect(phoneNotes(b.page), "B's phone has no new message").toHaveCount(bNotesBefore);
    await expect(approvalRows(b.page), "B's rail has no approval row").toHaveCount(0);
    await expect(breakFeedButton(b.page), "B's Break the feed is still enabled").not.toHaveAttribute('aria-disabled', 'true');
    const bAfterRead = await readState(b.page);
    expect(bBefore.guide ?? null, "B's state serves its guide").not.toBeNull();
    expect(bAfterRead.snapshot.guide, "B's guide state is the one read before the press").toEqual(bBefore.guide);
    expect(ownRows(bAfterRead.snapshot), "B's rows are the ones read before the press").toEqual(bOwn);
    const bEvents = await eventsSince(b.page, bCursors);
    expect(
      bEvents.events.filter((event) => A_ONLY.includes(event.type)).map((event) => `${event.stream}:${event.type}`),
      `since B's cursors no B-stream event is one of ${A_ONLY.join(', ')}`,
    ).toEqual([]);
    for (const secret of [request, incidentRef, note]) {
      expect(bAfterRead.text, `B's state holds none of A's refs (${secret})`).not.toContain(secret);
      expect(bEvents.text, `B's events hold none of A's refs (${secret})`).not.toContain(secret);
    }

    // Row 3: the rows stay their own, and the orders.
    const aNow = ownRows(aAfterRead.snapshot);
    expect(aNow.turns, "A's state shows A's turn").toContain(aOwn.turns[0]);
    expect([aNow.reminders, aNow.checks, aNow.pairing], "A's reminder, check and pairing name are A's").toEqual([aOwn.reminders, aOwn.checks, 'Ana']);
    expect(aNow.mail, "A's mail item is there").toContain(aOwn.mail[0]);
    for (const ref of bRefs) expect(aAfterRead.text, `A's state holds none of B's rows (${ref})`).not.toContain(ref);
    expect(await ordersOf(a.trace), 'A has 50 orders under its TraceRef').toBe(FIFTY);
    expect(await ordersOf(b.trace), 'B has none').toBe(0);

    // Row 4: B answers A's request.
    const aCursors: Cursors = { session: aAfterRead.snapshot.streams.session, instance: aAfterRead.snapshot.streams.instance };
    const bCursorsNow: Cursors = { session: bAfterRead.snapshot.streams.session, instance: bAfterRead.snapshot.streams.instance };
    const refused = await post(b.page.request, `${APPROVALS}/${request}/answer`, { action: 'approve', channel: 'web' });
    expect(refused.status(), "B's answer to A's request is refused").toBe(404);
    const refusedBody = (await refused.json()) as { error: { code: string } };
    expect(refusedBody.error.code, 'as not found').toBe('not_found');
    const unknown = await post(b.page.request, `${APPROVALS}/${randomBytes(16).toString('base64url')}/answer`, { action: 'approve', channel: 'web' });
    expect(unknown.status(), 'a request that does not exist is refused alike').toBe(404);
    expect(await unknown.json(), "A's request is refused with the unknown-ref body").toEqual(refusedBody);
    expect((await readApproval(request)).state, "A's row stays pending").toBe('pending');
    await expect(card.getByRole('button', { name: /^Approve/ }), "A's card still offers Approve").toHaveCount(1);
    await expect(card.getByRole('button', { name: /^Reject/ }), 'and Reject').toHaveCount(1);
    await b.page.waitForTimeout(3_000);
    const aSince = await eventsSince(a.page, aCursors);
    const bSince = await eventsSince(b.page, bCursorsNow);
    expect(aSince.events.filter((event) => event.type === 'approval'), 'no approval event on either stream since the answer: A').toEqual([]);
    expect(bSince.events.filter((event) => event.type === 'approval'), 'no approval event on either stream since the answer: B').toEqual([]);
    expect((await readApproval(request)).state, "A's row is still pending after the wait").toBe('pending');

    // Row 5: A answers on its simulated phone.
    await message.getByRole('button', { name: /^Approve/ }).click();
    await expect.poll(async () => (await readApproval(request)).state, { message: 'the row leaves pending', timeout: 30_000 }).not.toBe('pending');
    const answered = await readApproval(request);
    expect(answered.channel, 'it was answered from the simulated phone').toBe('phone');
    await expect(message.locator('p[data-part="answer"]'), 'the phone says so').toHaveText(/^Approved from the simulated phone at \d{1,2}:\d{2}( [A-Z]{1,5})?\.$/, { timeout: 30_000 });
    await expect(card.locator('p.status'), 'so does the card').toHaveText(/^Approved from the simulated phone at /, { timeout: 30_000 });
    await expect
      .poll(async () => (await readApproval(request)).state, { message: 'the fix ends (the row leaves pending, approved and executing)', timeout: 90_000, intervals: [1_000, 2_000] })
      .not.toMatch(/^(pending|approved|executing)$/);
    await expect(incidentCard(b.page), 'and B still has no incident card').toHaveCount(0);
  } finally {
    for (const visitor of visitors) await leaveVisitor(visitor);
    for (const rows of populated) await cleanPopulated(rows);
  }
});

notBuilt("the paired chat: A's paired chat gets the incident and its approval request, and B's paired chat gets none", '31.4');
notBuilt("the paired chat: a press from B's paired chat on A's request is refused and changes nothing", '31.4');
notBuilt('the message search: no Telegram value or IRIS user name appears in any OCUTALON or OCUORDERS message body or header', '31.4');
