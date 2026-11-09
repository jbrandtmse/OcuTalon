import { randomBytes } from 'node:crypto';

import { expect, test, type APIRequestContext, type Page } from '../../e2e/support/fixtures';

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
  guideRegion,
  guideSend,
  incidentCard,
  incidentCardOf,
  incidentRefs,
  newIncidentRef,
  phoneNotes,
  readState,
  reminderThroughGuide,
  sendThroughComposer,
  WATCH_PROMPT,
  watchThroughGuide,
  type Snapshot,
} from '../../e2e/support/demo-path';
import { loadedAfter } from '../../e2e/support/floor';
import { chk, fixtureUser, irisScript, quoted, readApproval } from '../../e2e/support/iris';
import { drawnMessages, type Turn } from '../../e2e/support/trace';
import {
  BUSY_HEADER,
  cleanPopulated,
  epochOf,
  expectOpenedDirectly,
  leaveVisitor,
  openVisitor,
  opensTabStrict,
  ordersOf,
  populate,
  publicValue,
  readStatus,
  removeCounterRows,
  removeSession,
  seedIncomingMail,
  sessionRow,
  setPublic,
  signInFromSplash,
  signOutGroup,
  type Populated,
  type Visitor,
} from '../support';
import {
  CHAT_A,
  CHAT_B,
  MOCK_MS,
  buttonsOf,
  callMark,
  editsOf,
  finishTelegram,
  pairChat,
  pressAnswers,
  pressFromChat,
  sentCalls,
  sentChats,
  shareContactFromChat,
  startTelegram,
  unpairChat,
} from '../telegram';

/**
 * REL-2's online run (Story 16.2, Story 29.4): the UJ-1 path as a judge walks it on the online demo, with the model keys pointed at the CI
 * mock. It has its own project and unit (online-demo-path, docker/tests/test-online-demo-path.sh) on a flag-on throwaway with the test
 * start values: a fresh browser context opens the splash and finds the published demo credentials prefilled.
 * - Step 1 is real: the button signs in without typing and the page loads.
 * - Steps 2 to 5 are one visitor's journey through the step functions of web/e2e/support/demo-path.ts, which the web run's 02 to 05 call
 *   too (Story 11.7, DW-221): the guide's own Send for the watch and for the reminder, Break the feed and the incident awaiting approval
 *   (the phone's notice and "Approval requests, 1"), and Approve on the simulated phone to "All 50 orders went through.", the audit line and
 *   Resolved. They run in order on one session, as the web run's do, and skip the heartbeat's last-run wait that the web run proves.
 * - Step 5's second press (PT-e of Story 7.9, ruled for Story 4.11's item 3): once the approved fix has gone through, the guide's "Other things to try"
 *   item "Break it again" presses Break the feed again in the same session, and the new incident's approval request on the simulated phone
 *   holds 7.9's line "Checked against the last {n} orders from the same source that went through: 0 would change.". It is asserted by pattern on
 *   the real notice text. It is the end of the step 5 case, because the second press needs the session whose fix just went through and the
 *   unit's report keeps exactly its cases (docker/tests/test-online-demo-path.sh); the project already runs this folder.
 * - Step 7 (Story 17.10, DW-874) is the same visitor's "Send my digest now." in the composer (the CI mock calls send_digest): one digest card, a
 *   plain-text notice card of the class digest, appears in that visitor's own chat, with a greeting for its first line and "Yesterday's cost: $n.nn."
 *   for its last, and the simulated phone gets no digest note. It follows step 5 in the same serial block, on the same session. The card names none of the
 *   visitor's own chat messages, "Send my digest now." included (Story 17.12, DW-979).
 * - Step 6 is real: the guide's watch prompt gets its reply, and the reply's Trace link opens Visual Trace at the turn, signed in, drawing
 *   the turn's header and its agent steps, with the steps and the cost in the decision's details.
 * - "Second visitor" is the isolation run (Story 29.4): visitors A and B each watch Orders (through the guide's Send), A presses Break the feed, and A's incident, its
 *   notice and its approval request reach only A; B's page, /state and /events get nothing, an answer of B to A's request is refused as
 *   an unknown request, and A answers on its simulated phone.
 * - "The paired chat under load" (Story 31.4) is the same isolation with the demo full and Telegram on: six proxied visitors fill the visitor cap,
 *   A and B are paired to two mock chats, and A, C and D press Break the feed at the same time. A's paired chat gets A's incident notice with its
 *   approval request and nobody else's, a press from B's chat is refused and changes nothing, A answers from its own chat, and a search of every
 *   OCUTALON and OCUORDERS message header and body of the run finds no Telegram value and no IRIS user name. It uses the CI model mock and the
 *   mock Bot API only.
 * The unit fails when a case is skipped or missing: its report holds exactly eleven passed cases (docker/tests/test-online-demo-path.sh). The
 * texts are written out here, as the independent oracle of the page's own.
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

  test('step 5: Approve on the phone ends with "All 50 orders went through.", the audit line and Resolved, and the request leaves the rail; then Break it again of Other things to try gives a new incident whose request holds the good-message line with "0 would change"', async () => {
    test.setTimeout(540_000);
    expect(request, 'step 4 found the approval request').not.toBe('');
    // The online demo's message times carry " ET" (Msg.Catalog's time slot).
    await approveOnPhone(pageOf(), request, ' ET');

    // The second press (PT-e of Story 7.9, ruled for Story 4.11's item 3), in the same case so that the unit's report keeps its cases.
    const page = pageOf();
    const known = await incidentRefs(page);
    expect(known.length, 'steps 4 and 5 left the session with its approved incident').toBeGreaterThan(0);

    // The panel is closed while the guide is at step 5; the link opens it. Item 3 presses the box's own Break the feed.
    const more = guideRegion(page).getByRole('button', { name: 'More to try', exact: true });
    if ((await more.getAttribute('aria-expanded')) !== 'true') await more.click();
    const again = guideRegion(page).getByRole('group', { name: 'Other things to try', exact: true }).getByRole('button', { name: 'Break it again', exact: true });
    await expect(again, 'item 3 is on the page').toBeVisible();
    await expect(breakFeedButton(page), 'Break the feed is active once the fix has gone through').not.toHaveAttribute('aria-disabled', 'true', { timeout: 30_000 });
    const pressed = page.waitForResponse((response) => response.url().includes(BREAK_FEED) && response.request().method() === 'POST');
    await again.click();
    expect((await pressed).status(), "item 3's press is Break the feed's own, and it answers 200").toBe(200);

    // A new incident awaits approval; its request on the simulated phone carries the ruled line (the real text, by pattern).
    const card = incidentCardOf(page, await newIncidentRef(page, known));
    await expect(card.locator('.chip-row .chip'), 'the new incident awaits approval').toHaveText('Awaiting approval', { timeout: 90_000 });
    const notice = phoneNotes(page).filter({ has: page.getByRole('button', { name: /^Approve/ }) });
    await expect(notice, "the phone has the new request's notice").toHaveCount(1, { timeout: 90_000 });
    await expect(notice, 'its dry run says what the repair did to good messages: none would change').toContainText(
      /Checked against the last [1-9]\d* orders? from the same source that went through: 0 would change\./,
    );

    // Leave the session as step 5 does: the request is approved on the phone and the incident resolves.
    const key = (await card.locator('[data-part="approval"]').getAttribute('data-key')) ?? '';
    expect(key, "the new request's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
    await approveOnPhone(page, key, ' ET', card);
  });

  test('step 7: "Send my digest now." in the chat shows the digest card in the visitor\'s own chat, and the simulated phone gets none', async () => {
    test.setTimeout(240_000);
    const page = pageOf();
    await sendThroughComposer(page, 'Send my digest now.', false);

    // The digest is composed by the Digest item and delivered to the visitor's own web chat as a plain-text notice card.
    const card = page.locator('app-chat-panel app-notice-card .notice.digest');
    await expect(card, "one digest card appears in the visitor's own chat").toHaveCount(1, { timeout: 90_000 });
    const lines = (await card.locator('.text').innerText()).split('\n');
    expect(lines[0], 'its first line is a greeting').toMatch(/^Good (morning|afternoon|evening)\.$/);
    expect(
      lines.some((line) => /^I checked /.test(line) || line === "I'm not watching any productions yet, so this digest covers the vital signs only. Ask me to watch one."),
      'it says what was checked, or that nothing is watched',
    ).toBe(true);
    expect(lines[lines.length - 1], 'its last line is the cost').toMatch(/^Yesterday's cost: \$\d+\.\d\d\.$/);
    // The visitor's own messages so far: step 7's, step 2's watch prompt and step 3's reminder prompt (reminderThroughGuide). The CI mock triages each act.
    for (const own of ['Send my digest now', WATCH_PROMPT, 'Remind me in 1 minute to stretch.']) {
      expect(lines.join('\n'), `the digest names none of the visitor's own chat messages: ${own}`).not.toContain(own);
    }
    // The phone's notes are drawn from the same notification routing, so a note that was going to arrive does so within moments of the card.
    await page.waitForTimeout(3_000);
    await expect(
      phoneNotes(page).filter({ hasText: /Good (morning|afternoon|evening)\.|I checked |Everything else I checked passed|Yesterday's cost/ }),
      'the simulated phone gets no digest note',
    ).toHaveCount(0);
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

/** The visitor cap's load: six proxied visitors, each from its own address (TEST-NET-2 addresses, which no request of the run comes from). */
const LOAD_ADDRESSES = ['198.51.100.101', '198.51.100.102', '198.51.100.103', '198.51.100.104', '198.51.100.105', '198.51.100.106'] as const;

/** The longest one message search (KeyProof.TraceHits over one namespace) may take, in ms. */
const SEARCH_MS = 240_000;

/** Eight random lower-case letters. */
function letters(): string {
  return Array.from(randomBytes(8), (byte) => String.fromCharCode(97 + (byte % 26))).join('');
}

/** The header id of the newest message of a namespace (0 when it has none): a mark for the message search. */
async function headerMark(namespace: 'OCUTALON' | 'OCUORDERS'): Promise<number> {
  const lines = await irisScript(`Write !,"CHK|mark|",+$Order(^|${quoted(namespace)}|Ens.MessageHeaderD(""),-1)`);
  const mark = Number(chk(lines, 'mark') ?? '');
  if (!Number.isInteger(mark) || mark < 0) throw new Error(`the ${namespace} header mark could not be read (${lines.join(' ')})`);
  return mark;
}

/**
 * The message search for one value in one namespace after a mark (SessionEvents.MessageHits: KeyProof.TraceHits, with a second reader for the
 * bodies it cannot export as XML): the hits (-1 when a message was unreadable by both readers) and, to print on a failure, its places and stats.
 */
async function traceHits(value: string, namespace: 'OCUTALON' | 'OCUORDERS', after: number): Promise<{ hits: number; detail: string; seconds: number; messages: number; fallback: number }> {
  const started = Date.now();
  const lines = await irisScript(
    [
      `Set hits=##class(OcuTalon.Test.Web.SessionEvents).MessageHits(${quoted(value)},${after},${quoted(namespace)},.places,.stats)`,
      'Write !,"CHK|hits|",hits',
      'Write !,"CHK|messages|",stats.messages',
      'Write !,"CHK|fallback|",$Select($IsObject(stats.fallback):stats.fallback.%Size(),1:0)',
      'Write !,"CHK|detail|",places.%ToJSON()," ",stats.%ToJSON()',
    ].join('\n'),
    SEARCH_MS,
  );
  const hits = Number(chk(lines, 'hits') ?? 'NaN');
  if (!Number.isInteger(hits)) throw new Error(`the ${namespace} message search gave no count (${lines.join(' ')})`);
  return { hits, detail: chk(lines, 'detail') ?? '', seconds: (Date.now() - started) / 1000, messages: Number(chk(lines, 'messages') ?? '-1'), fallback: Number(chk(lines, 'fallback') ?? '-1') };
}

/**
 * Runs a read-only wait again when one of its HTTP reads timed out (ruling R3 of Story 31.4: a stall whose cause is not isolated, an
 * occurrence of DW-550's unanswered /state, which its owner investigates), inside the wait's own budget: the attempts together never run past budgetMs, so a stall can never
 * stretch the wait. A wait that ran out of its own budget, any other error and a stall past the budget throw. Each stall is printed as a
 * "MEASURED Story 31.4: a read stalled" line, which the unit counts.
 */
async function throughStalls<T>(what: string, budgetMs: number, run: () => Promise<T>): Promise<T> {
  const until = Date.now() + budgetMs;
  for (;;) {
    const attempt = run();
    attempt.catch(() => undefined);
    let timer: ReturnType<typeof setTimeout> | undefined;
    const spent = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error(`the wait while ${what} ran out of its ${budgetMs / 1000} s budget`)), Math.max(0, until - Date.now()));
    });
    try {
      return await Promise.race([attempt, spent]);
    } catch (error) {
      const text = (error as Error).message ?? '';
      if (!/apiRequestContext\.\w+: Timeout \d+ms exceeded/.test(text) || Date.now() >= until) throw error;
      console.log(`MEASURED Story 31.4: a read stalled while ${what}; the wait goes on`);
    } finally {
      clearTimeout(timer);
    }
  }
}

test.describe('the paired chat under load', () => {
  test.describe.configure({ mode: 'serial' });

  /** One of the six visitors, named by its letter. */
  const visitors: Visitor[] = [];
  const state = {
    savedProxy: '',
    proxySet: false,
    telegram: undefined as string | undefined,
    pairings: [] as string[],
    api: undefined as APIRequestContext | undefined,
    nameA: `Zqpaired${letters()}`,
    nameB: `Zqpaired${letters()}`,
    phoneA: `+1555${String(randomBytes(4).readUInt32BE() % 10_000_000).padStart(7, '0')}`,
    phoneB: `+1555${String(randomBytes(4).readUInt32BE() % 10_000_000).padStart(7, '0')}`,
    marks: { OCUTALON: 0, OCUORDERS: 0 },
    /** The approval request of A, C and D. */
    keys: { a: '', c: '', d: '' },
    /** The call mark taken just before the presses of A, C and D. */
    driveMark: 0,
    /** The drive of the three incidents, started by the first case that needs it. */
    driven: undefined as Promise<void> | undefined,
    /** B's press and A's answer from the paired chats, started by the first case that needs them. */
    answered: undefined as Promise<void> | undefined,
  };
  const [A, B, C, D] = [0, 1, 2, 3] as const;
  const who = (index: number): Visitor => {
    const visitor = visitors[index];
    if (visitor === undefined) throw new Error(`visitor ${'ABCDEF'[index]} was not opened`);
    return visitor;
  };

  test.beforeAll(async ({ browser, playwright }) => {
    test.setTimeout(420_000);
    const host = process.env['OCUTALON_ONLINE_HOST_ADDRESS'] ?? '';
    if (host === '') throw new Error('OCUTALON_ONLINE_HOST_ADDRESS is not set: the unit passes the address that IRIS sees for the requests of this machine');
    state.savedProxy = await publicValue('proxyAddress');
    state.proxySet = true;
    await setPublic('proxyAddress', host);
    state.telegram = await startTelegram();
    state.api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });

    // The demo is full: six visitors, one after another, each from its own address.
    for (const [index, address] of LOAD_ADDRESSES.entries()) {
      try {
        const visitor = await openVisitor(browser, address);
        visitors.push(visitor);
        // E and F only fill the demo: their sessions stay counted, and their pages (each holds a live socket) are closed.
        if (index > D) await visitor.page.close();
      } catch (error) {
        throw new Error(`visitor ${'ABCDEF'[index]} (${address}) could not sign in: ${(error as Error).message}`);
      }
    }
    expect(await readStatus(state.api), 'the demo is full: the plain status reads busy, with the marker header').toEqual({ busy: true, header: '1', code: 200 });

    // The marks of the message search come before the pairing, so that whatever the pairing writes is searched.
    state.marks.OCUTALON = await headerMark('OCUTALON');
    state.marks.OCUORDERS = await headerMark('OCUORDERS');

    // A and B are paired to the two mock chats, each with its own display name, then one contact update from each chat.
    state.pairings.push(await pairChat(who(B).ref, CHAT_B, state.nameB));
    state.pairings.push(await pairChat(who(A).ref, CHAT_A, state.nameA));
    await shareContactFromChat(CHAT_A, state.nameA, state.phoneA);
    await shareContactFromChat(CHAT_B, state.nameB, state.phoneB);
  });

  test.afterAll(async () => {
    test.setTimeout(300_000);
    const problems: string[] = [];
    const step = async (what: string, run: () => Promise<unknown>): Promise<void> => {
      try {
        await run();
      } catch (error) {
        problems.push(`${what}: ${(error as Error).message}`);
      }
    };
    // The requests of C and D (and A's, when its case did not end it) are rejected with their own web answer, so that no fix runs on.
    const own: Array<[Visitor | undefined, string]> = [
      [visitors[A], state.keys.a],
      [visitors[C], state.keys.c],
      [visitors[D], state.keys.d],
    ];
    for (const [visitor, key] of own) {
      if (visitor === undefined || key === '') continue;
      await step(`rejecting ${key}`, async () => {
        if ((await readApproval(key)).state !== 'pending') return;
        await post(visitor.page.request, `${APPROVALS}/${key}/answer`, { action: 'reject', channel: 'web' });
        await expect.poll(async () => (await readApproval(key)).state, { message: `the request ${key} leaves pending`, timeout: 60_000 }).not.toBe('pending');
      });
    }
    if (state.telegram !== undefined) await step('finishing Telegram', () => finishTelegram(state.telegram ?? ''));
    for (const pairing of state.pairings) await step('unpairing a chat', () => unpairChat(pairing));
    for (const visitor of visitors) await step('leaving a visitor', () => leaveVisitor(visitor));
    for (const address of LOAD_ADDRESSES) await step(`removing the counter rows of ${address}`, () => removeCounterRows(address));
    if (state.api !== undefined) await step('closing the status client', () => state.api!.dispose());
    if (state.proxySet) {
      await step('restoring the proxy address', async () => {
        await setPublic('proxyAddress', state.savedProxy);
      });
    }
    if (problems.length > 0) throw new Error(`the clean-up left something behind: ${problems.join('; ')}`);
  });

  /**
   * A, B, C and D watch Orders, then A, C and D press Break the feed at the same moment while the demo is still full, and A's paired chat gets
   * A's notice. The first case that needs the incidents runs it; the others reuse it, so that each case passes alone (-g) as well as after the rest.
   */
  const drive = (): Promise<void> =>
    (state.driven ??= (async () => {
      const [a, b, c, d] = [who(A), who(B), who(C), who(D)];
      expect(await readStatus(state.api!), `the demo is still full: the plain status reads busy, with ${BUSY_HEADER}`).toEqual({ busy: true, header: '1', code: 200 });

      // A, B, C and D watch Orders through the guide's Send, all at once.
      await Promise.all(
        [a, b, c, d].map(async (visitor, index) => {
          await askToWatch(visitor.page);
          await throughStalls(`${'ABCD'[index]} watches`, 90_000, () => doneTurn(visitor.page));
          await expect(breakFeedButton(visitor.page), `${'ABCD'[index]}'s Break the feed is enabled`).not.toHaveAttribute('aria-disabled', 'true', { timeout: 30_000 });
        }),
      );
      expect(await readStatus(state.api!), 'the demo is full when the presses come').toEqual({ busy: true, header: '1', code: 200 });

      // A, C and D press Break the feed at the same moment.
      state.driveMark = await callMark();
      await Promise.all(
        [a, c, d].map(async (visitor, index) => {
          const pressed = visitor.page.waitForResponse((response) => response.url().includes(BREAK_FEED) && response.request().method() === 'POST');
          await breakFeedButton(visitor.page).click();
          expect((await pressed).status(), `${'ACD'[index]}'s Break the feed answers 200`).toBe(200);
        }),
      );
      const slots = ['a', 'c', 'd'] as const;
      const keys = await Promise.all(
        [a, c, d].map(async (visitor, index) => {
          await expect(approvalCard(visitor.page), `${'ACD'[index]} shows its own approval card`).toHaveCount(1, { timeout: 90_000 });
          const key = (await approvalCard(visitor.page).getAttribute('data-key')) ?? '';
          const slot = slots[index];
          if (slot === undefined) throw new Error('a driver without a slot');
          state.keys[slot] = key;
          return key;
        }),
      );
      for (const key of keys) expect(key, "the request's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
      expect(new Set(keys).size, 'three requests of their own').toBe(3);

      // A's paired chat got A's notice with A's buttons.
      await expect
        .poll(() => buttonsOf(CHAT_A), { message: "A's chat gets the notice with the buttons approve:<Ref> and reject:<Ref> of A's request", timeout: MOCK_MS, intervals: [1000] })
        .toEqual([`approve:${state.keys.a}`, `reject:${state.keys.a}`]);
    })());

  test("the paired chat: A's paired chat gets the incident and its approval request, and B's paired chat gets none", async () => {
    test.setTimeout(420_000);
    const [a, c, d] = [who(A), who(C), who(D)];
    await drive();

    // C's and D's phones show their notices, and then nothing went to any other chat.
    for (const [visitor, key, label] of [[c, state.keys.c, 'C'], [d, state.keys.d, 'D']] as const) {
      await throughStalls(`${label}'s phone is read`, 90_000, () =>
        expect
          .poll(async () => ((await readState(visitor.page)).snapshot.phone ?? []).find((item) => item.approvalRef === key)?.ref ?? '', { message: `${label}'s phone has the notice with its request`, timeout: 60_000 })
          .not.toBe(''),
      );
    }
    await a.page.waitForTimeout(5_000);
    expect(await buttonsOf(CHAT_A), "after the settle, A's chat still holds A's buttons as the newest keyboard (no notice of C or D came after)").toEqual([`approve:${state.keys.a}`, `reject:${state.keys.a}`]);
    const calls = await sentCalls(state.driveMark);
    const chats = calls.map((call) => call.chat);
    console.log(`MEASURED Story 31.4: ${chats.length} sendMessage and editMessageText calls after the mark, ${chats.filter((chat) => chat === CHAT_A).length} to CHAT_A`);
    expect(chats.length, 'at least one message went to a chat').toBeGreaterThan(0);
    expect(chats.includes(CHAT_B), "B's paired chat got no message").toBe(false);
    expect(chats.filter((chat) => chat !== CHAT_A), 'every message after the mark went to A\'s chat').toEqual([]);
    // Every keyboard that A's chat got, and not only the newest, is A's: a notice of C or D that came before A's fails here.
    const keyboards = calls.filter((call) => call.buttons.length > 0);
    expect(keyboards.length, "A's chat got a keyboard").toBeGreaterThan(0);
    expect(keyboards.flatMap((call) => call.buttons).filter((data) => data !== `approve:${state.keys.a}` && data !== `reject:${state.keys.a}`), "every button A's chat got is one of A's request").toEqual([]);
  });

  /**
   * B's paired chat presses Approve on A's request (refused, nothing changes), then A answers from its own chat (the first answer wins), with
   * the assertions of both. The first case that needs the presses runs them; the others reuse them, so that the message search covers the
   * presses' production messages (Core.Msg.Answer) also when it runs alone (-g).
   */
  const answered = (): Promise<void> =>
    (state.answered ??= (async () => {
      const [a, b] = [who(A), who(B)];
      await drive();
      const key = state.keys.a;
      expect(key, "A's approval request was found").not.toBe('');
      const card = a.page.locator(`app-chat-panel [data-part="approval"][data-key="${key}"]`);
      const aRead = await readState(a.page);
      const bRead = await readState(b.page);
      const aCursors: Cursors = { session: aRead.snapshot.streams.session, instance: aRead.snapshot.streams.instance };
      const bCursors: Cursors = { session: bRead.snapshot.streams.session, instance: bRead.snapshot.streams.instance };
      const answersBefore = (await pressAnswers()).length;
      const mark = await callMark();

      await pressFromChat(CHAT_B, `approve:${key}`, state.nameB);
      await expect.poll(async () => (await pressAnswers()).length, { message: "B's press gets its answer", timeout: MOCK_MS, intervals: [1000] }).toBe(answersBefore + 1);
      const answers = await pressAnswers();
      expect(answers[answers.length - 1], "the answer says that only the paired chat can answer, as an alert").toEqual({ text: 'Only the paired chat can answer this request.', show_alert: 1 });
      await b.page.waitForTimeout(5_000);
      expect(await sentChats(mark), 'no message and no edit follows the press: B\'s chat gets none and A\'s chat no edit').toEqual([]);
      expect((await readApproval(key)).state, "A's row stays pending").toBe('pending');
      await expect(card.getByRole('button', { name: /^Approve/ }), "A's card still offers Approve").toHaveCount(1);
      await expect(card.getByRole('button', { name: /^Reject/ }), 'and Reject').toHaveCount(1);
      expect((await eventsSince(a.page, aCursors)).events.filter((event) => event.type === 'approval'), "no approval event on A's stream since the press").toEqual([]);
      expect((await eventsSince(b.page, bCursors)).events.filter((event) => event.type === 'approval'), "and none on B's").toEqual([]);

      // A answers from its own chat; the first answer wins.
      const edits = (await editsOf(CHAT_A)).length;
      const answeredBefore = (await pressAnswers()).length;
      await pressFromChat(CHAT_A, `approve:${key}`, state.nameA);
      await expect.poll(async () => (await pressAnswers()).length, { message: "A's press gets its answer", timeout: MOCK_MS, intervals: [1000] }).toBe(answeredBefore + 1);
      const approved = (await pressAnswers()).pop();
      expect(approved?.text, 'the press answer says approved').toMatch(/^Approved\./);
      expect(approved?.show_alert, 'with no alert').toBe(0);
      await expect.poll(async () => (await readApproval(key)).state, { message: 'the row leaves pending', timeout: 30_000 }).not.toBe('pending');
      expect((await readApproval(key)).channel, 'it was answered from Telegram').toBe('telegram');
      await expect
        .poll(async () => (await editsOf(CHAT_A)).slice(edits), { message: "A's chat gets one edit with the answered line", timeout: MOCK_MS, intervals: [1000] })
        .toHaveLength(1);
      const edit = (await editsOf(CHAT_A)).slice(edits)[0] ?? '';
      expect(edit, 'the edit ends with the answered line').toMatch(/Approved from Telegram at \d{1,2}:\d{2}( [A-Z]{1,5})?\.$/);
      await expect(card.locator('p.status'), "A's card says so").toHaveText(/^Approved from Telegram at /, { timeout: 30_000 });
      let note = '';
      await expect
        .poll(async () => (note = ((await readState(a.page)).snapshot.phone ?? []).find((item) => item.approvalRef === key)?.ref ?? ''), { message: "A's phone has the request's notice", timeout: 30_000 })
        .not.toBe('');
      const message = a.page.locator(`app-simulated-phone .notification[data-key="${note}"]`);
      await expect(message.locator('p[data-part="answer"]'), "A's phone says so").toHaveText(/^Approved from Telegram at /, { timeout: 30_000 });
      await expect(message.getByRole('button', { name: /^Approve/ }), "A's phone offers no Approve any more").toHaveCount(0);
      await expect
        .poll(async () => (await readApproval(key)).state, { message: 'the fix ends (the row leaves approved and executing)', timeout: 90_000, intervals: [1_000, 2_000] })
        .not.toMatch(/^(pending|approved|executing)$/);
    })());

  test("the paired chat: a press from B's paired chat on A's request is refused and changes nothing", async () => {
    test.setTimeout(300_000);
    await answered();
  });

  test('the message search: no Telegram value or IRIS user name appears in any OCUTALON or OCUORDERS message body or header', async () => {
    test.setTimeout(900_000);
    const a = who(A);
    await drive();
    await answered();
    const values: Array<[string, string]> = [
      ["A's display name", state.nameA],
      ["B's display name", state.nameB],
      ["the from object's user name", 'zqfromuser'],
      ["A's chat id", CHAT_A],
      ["B's chat id", CHAT_B],
      ["A's phone digits", state.phoneA.slice(1)],
      ["B's phone digits", state.phoneB.slice(1)],
      ['the demo account\'s IRIS user name', fixtureUser('DEMOACCOUNT').user],
    ];
    const found: string[] = [];
    for (const namespace of ['OCUTALON', 'OCUORDERS'] as const) {
      for (const [label, value] of values) {
        const result = await traceHits(value, namespace, state.marks[namespace]);
        console.log(`MEASURED Story 31.4: the ${namespace} search for ${label} took ${result.seconds} s over ${result.messages} messages, ${result.fallback} read by the second reader (${result.hits} hits)`);
        if (result.hits !== 0) found.push(`${label} in ${namespace}: ${result.hits} (${result.detail})`);
      }
    }
    expect(found, 'no value is found in any header or body, and none is unreadable (-1)').toEqual([]);

    // The controls: the search can see what the run wrote.
    const sessionControl = await traceHits(a.ref, 'OCUTALON', state.marks.OCUTALON);
    expect(sessionControl.hits, "control: A's SessionRef is in OCUTALON's messages").toBeGreaterThan(0);
    const traceControl = await traceHits(a.trace, 'OCUORDERS', state.marks.OCUORDERS);
    expect(traceControl.hits, "control: A's TraceRef is in OCUORDERS' messages").toBeGreaterThan(0);
  });
});
