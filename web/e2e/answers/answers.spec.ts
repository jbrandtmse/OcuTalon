import { expect, test, type Locator, type Page, type Response, type Route } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { DRY_RUN, raise, refOf, today } from '../support/approvals';
import { dropPhone, phoneMessage } from '../support/devices';
import { CARD_MS, composerOf, inMs, mainOf, railOf, unique } from '../support/floor';
import { answerHeaders, answerQuietly, cleanFixtureRows, fixtureUser, readApproval, seedApproval, sendNotification, sinkEvent } from '../support/iris';
import { announcedTexts, clock, plain, recordAnnouncements, scrollListTo, tokenColor } from '../support/page';

/**
 * Story 6.3, answering on the simulated phone and every copy of an answer (X1 to X10; NFR-9, FR-8, FR-13), in a real browser against a
 * real stack, as the answers user ANSWERS (OCUTALON_ANSWERS_USER, with the role OcuTalonUser; the stack is in demo mode and its
 * instance zone is UTC, the browser's is UTC and en-GB; the page's clock is the real one). An incident card is made as IncidentManager
 * will make it (an `incident` event) and its request is a fixture row whose `approval` event reaches the page through BridgeSink
 * (support/approvals.ts raise); the incident notice reaches the phone through Notify and SimPhoneOut, as a producer sends it
 * (sendNotification); the `answered` notification that IncidentManager will send after an answer is sent by the case. A press goes
 * through the page to AnswersIn, AnswerOps and Approval.Answer in the production, which waits about 5 s for the task that a fixture row's
 * hold would have. HH:MM is the row's AnsweredAt, read from the reply or back through iris, so that the expected text is exact. A
 * case's rows and phone messages are its own and are removed in finally.
 * X1 is the phone's notice, X2 an Approve on the phone (the 2 s bound of NFR-9 to the card), X3 an Approve on the card and the
 * phone following within 5 s, X4 the press that lost the race, X5 the phone's busy rule and failure notices, X6 the rail row's jump,
 * X7 the phone holding its feed for a pending request and X8 an answer from elsewhere, shown within 2 s of its event and announced once by
 * the card. QA adds X9 (Reject on the phone) and X10 (a reload keeps the stored messages).
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'ANSWERS';

/** The route that answers a request. */
const ANSWER = '**/ocutalon/api/v1/approvals/*/answer';

/** The bound of NFR-9 for the page: its answered status within 2 s of the answering call's reply. */
const PAGE_MS = 2000;

/** The bound of NFR-9 for the other channels: the phone within 5 s of the answer. */
const PHONE_MS = 5000;

/** How long a row of the rail may take to leave once the page has the answer: one live update. */
const ONE_UPDATE_MS = 3000;

/** The names of the phone's buttons for the fixture request. */
const APPROVE = 'Approve: repair and resend 50 orders';
const REJECT = 'Reject: repair and resend 50 orders';

/** The HH:MM of a UTC ISO time as the server writes it: the phone's lines and the server's notices. */
const hhmm = (iso: string): string => iso.slice(11, 16);

/** The HH:MM of a UTC ISO time as the page writes it (en-GB, UTC): the card's statuses and the phone's caption, whose hour has no leading zero before ten. */
const pageHhmm = (iso: string): string => clock(iso, 'en-GB', 'UTC');

/** The incident card and the request card of a ref, in the chat. */
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);

/** The simulated phone, its feed, and the message of a Ref. */
const phoneOf = (page: Page): Locator => page.locator('app-simulated-phone');
const feedOf = (page: Page): Locator => phoneOf(page).locator('.feed');
const messageOf = (page: Page, ref: string): Locator => phoneOf(page).locator(`.notification[data-key="${ref}"]`);

/** The rail's row of a request, and its jump button. */
const rowOfRequest = (page: Page, ref: string): Locator => railOf(page).locator(`li.row[data-row-key="approvals:${ref}"]`);

/** Signs the answers user in with the announcements recorded and waits for the loaded page with the phone. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await recordAnnouncements(page);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
  await expect(phoneOf(page), 'the stack is in demo mode: the phone shows').toBeVisible();
}

/** The slots of an incident.withFix / incident.laterRequest notice for the fixture request: 50 orders since two minutes ago. */
function noticeSlots(since: string): Record<string, unknown> {
  return {
    count: 50,
    itemNoun: { one: 'order', other: 'orders' },
    time: since,
    cause: 'Data format change',
    fixSummary: 'repair the order date and resend 50 orders',
    field: 'OrderDate',
    before: '10/16/2026',
    after: '2026-10-16',
    resendCount: 50,
  };
}

/**
 * Sends the incident notice of a request through Notify, as IncidentManager will (kind incident, or approval for a later request),
 * and returns the phone message that asks for it once the page shows it. `since` is the time the notice names.
 */
async function noticeOnPhone(page: Page, user: string, request: string, incident: string, since: string, kind: 'incident' | 'approval' = 'incident'): Promise<{ ref: string; message: Locator }> {
  await sendNotification(user, {
    kind,
    catalogKey: kind === 'incident' ? 'incident.withFix' : 'incident.laterRequest',
    slots: noticeSlots(since),
    approvalRef: request,
    incidentRef: incident,
  });
  let ref = '';
  await expect
    .poll(async () => (ref = (await phoneMessage(user, request))?.ref ?? ''), { message: 'the phone message of the request exists', timeout: CARD_MS })
    .not.toBe('');
  const message = messageOf(page, ref);
  await expect(message, 'and the phone shows it').toHaveCount(1, { timeout: CARD_MS });
  return { ref, message };
}

/** The two buttons of a phone message, by their names. */
const approveOf = (message: Locator): Locator => message.getByRole('button', { name: APPROVE, exact: true });
const rejectOf = (message: Locator): Locator => message.getByRole('button', { name: REJECT, exact: true });

/** The answer line of a phone message. */
const lineOf = (message: Locator): Locator => message.locator('p[data-part="answer"]');

/** The body of the reply to the answer call, with its status. */
async function replyBody(response: Response): Promise<{ status: number; body: { approval?: { answeredAt?: string } } }> {
  return { status: response.status(), body: (await response.json()) as { approval?: { answeredAt?: string } } };
}

/** Starts to wait for the answering call's reply: the promise resolves when the reply reaches the browser. */
function nextReply(page: Page): Promise<Response> {
  return page.waitForResponse((response) => response.request().method() === 'POST' && /\/approvals\/[^/]+\/answer$/.test(new URL(response.url()).pathname));
}

/** The start of the case's rows on the phone and in the chat, for dropPhone. */
const startOf = (): string => inMs(-2000);

/**
 * X1: the phone's notice. An incident notice with its request is one message with the catalog's phone text in three paragraphs, the
 * dry run's paragraph as an inset on the surface colour with the example's values in mono-sm (danger ink before, success ink after),
 * Approve (left, primary) and Reject (secondary) side by side in two halves, each 40 px tall and named with the object, and the caption
 * time. The web chat gets no notice card. A later request is a message of its own with its own buttons, and a fallback notice, which
 * names no request, has none.
 */
test('X1: the incident notice is a phone message with the dry run inset and Approve and Reject side by side', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const notices = page.locator('app-chat-panel app-notice-card');
    const noticesBefore = await notices.count();
    const incident = refOf('X1');
    const requests: string[] = [];
    const first = await raise(page, user, rows, incident, requests);
    // Two minutes ago, but never before today's midnight (UTC), so that the notice's time is today's and renders as HH:MM.
    const since = [inMs(-120_000), `${new Date().toISOString().slice(0, 10)}T00:00:00Z`].sort()[1]!;
    const { ref, message } = await noticeOnPhone(page, user, first, incident, since);

    const paragraphs = message.locator('app-phone-request p.text');
    await expect(paragraphs).toHaveCount(3);
    await expect(paragraphs.nth(0), 'the notice').toHaveText(`50 orders failed since ${hhmm(since)}. Data format change. I can repair the order date and resend 50 orders. Approve?`);
    await expect(paragraphs.nth(1), 'the dry run').toHaveText("Dry run: 50 orders affected. Example: OrderDate 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet.");
    await expect(paragraphs.nth(2)).toHaveText('Details and trace: on your OcuTalon page.');
    const inset = paragraphs.nth(1);
    await expect(inset, 'the dry run is the inset').toHaveClass(/inset/);
    await expect(inset, 'on the surface colour').toHaveCSS('background-color', await tokenColor(page, '--surface'));
    await expect(paragraphs.nth(0)).not.toHaveClass(/inset/);
    const before = inset.locator('.mono.before');
    const after = inset.locator('.mono.after');
    await expect(before).toHaveText('10/16/2026');
    await expect(after).toHaveText('2026-10-16');
    await expect(before, 'before is in the danger ink').toHaveCSS('color', await tokenColor(page, '--danger-ink'));
    await expect(after, 'after is in the success ink').toHaveCSS('color', await tokenColor(page, '--success-ink'));
    for (const value of [before, after]) {
      await expect(value, 'in mono-sm').toHaveCSS('font-size', '12px');
      await expect(value).toHaveCSS('font-family', /JetBrains Mono/);
    }

    const approve = approveOf(message);
    const reject = rejectOf(message);
    await expect(approve).toHaveText('Approve');
    await expect(approve, 'Approve is the primary button').toHaveClass(/button-primary/);
    await expect(reject).toHaveText('Reject');
    await expect(reject, 'Reject is the secondary button').toHaveClass(/button-secondary/);
    const [approveBox, rejectBox, rowBox] = await Promise.all([approve.boundingBox(), reject.boundingBox(), message.locator('.buttons').boundingBox()]);
    expect(approveBox!.x, 'Approve stands left of Reject').toBeLessThan(rejectBox!.x);
    expect(Math.abs(approveBox!.width - rejectBox!.width), `the two buttons are equal halves (${approveBox!.width} and ${rejectBox!.width})`).toBeLessThanOrEqual(1);
    const gap = rejectBox!.x - (approveBox!.x + approveBox!.width);
    expect(gap, 'with a gap between them').toBeGreaterThan(0);
    expect(Math.abs(approveBox!.width * 2 + gap - rowBox!.width), 'which fill the row').toBeLessThanOrEqual(1);
    expect(approveBox!.height, 'Approve is 40 px tall').toBeCloseTo(40, 0);
    expect(rejectBox!.height, 'and so is Reject').toBeCloseTo(40, 0);
    expect(Math.abs(approveBox!.y - rejectBox!.y), 'on one line').toBeLessThanOrEqual(1);
    await expect(message.locator('.time'), 'the caption time').toHaveText(/^\d{1,2}:\d\d$/);
    await inOrder([paragraphs.nth(0), paragraphs.nth(1), paragraphs.nth(2), approve, message.locator('.time')], 'top to bottom');
    expect(await notices.count(), 'the web chat gets no notice card').toBe(noticesBefore);

    const stored = await phoneMessage(user, first);
    expect(stored?.ref, 'the stored message is the one on screen').toBe(ref);
    expect(stored?.answer, 'with no answer').toBe('');

    const second = await raise(page, user, rows, incident, requests, { raisedAt: today('14:14:00') });
    const later = await noticeOnPhone(page, user, second, incident, since, 'approval');
    expect(later.ref, 'a later request is a message of its own').not.toBe(ref);
    await expect(approveOf(later.message), 'with its own buttons').toHaveCount(1);
    await expect(rejectOf(later.message)).toHaveCount(1);
    await expect(phoneOf(page).getByRole('button', { name: APPROVE, exact: true }), 'two Approve buttons on the phone').toHaveCount(2);

    const marker = unique('X1 fallback');
    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.fallback',
      slots: {
        count: 7,
        itemNoun: { one: 'order', other: 'orders' },
        time: since,
        fallbackReason: 'empty',
        groups: [{ itemName: marker.replace(/ /g, ''), count: 7, errorSummary: 'The order date was not in the expected format', firstAt: since }],
      },
    });
    const fallback = phoneOf(page).locator('.notification').filter({ hasText: marker.replace(/ /g, '') });
    await expect(fallback, 'a fallback notice shows').toHaveCount(1, { timeout: CARD_MS });
    await expect(fallback.getByRole('button'), 'with no buttons, since it names no request').toHaveCount(0);
    await expect(fallback.locator('app-phone-request'), 'and is an ordinary message, drawn as before').toHaveCount(0);
    expect(plain(await fallback.locator('p.text').first().textContent())).toContain("I couldn't work out the cause");
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/** Expects the elements to stand one under the other, in this order; their tops are read in one step. */
async function inOrder(elements: Locator[], what: string): Promise<void> {
  const handles = await Promise.all(elements.map((element) => element.elementHandle()));
  const tops = await elements[0]!.page().evaluate((nodes) => nodes.map((node) => (node as HTMLElement).getBoundingClientRect().top), handles);
  let last = -Infinity;
  for (const [i, top] of tops.entries()) {
    expect(top, `${what}: element ${i} stands below the one before`).toBeGreaterThan(last);
    last = top;
  }
}

/**
 * X2: Approve on the phone. Both buttons are busy while the answer is out, then "Approved from the simulated phone at HH:MM." replaces
 * them with focus on it. The chat's request card shows "Approved from the simulated phone at HH:MM" within 2 s of the reply (NFR-9;
 * the elapsed time is logged), and the rail row leaves within one live update. The row is approved from the phone by the signed-in
 * user, with one AnswersIn to AnswerOps header, and the card does not announce an answer that took focus on the phone.
 */
test('X2: Approve on the phone is busy, then the answer replaces the buttons, and the card shows it within 2 s of the reply', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const incident = refOf('X2');
    const request = await raise(page, user, rows, incident, []);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    const card = requestCard(page, request);
    await expect(card, 'the chat shows the request card').toHaveCount(1, { timeout: CARD_MS });
    await expect(rowOfRequest(page, request), 'and the rail its row').toHaveCount(1);
    const approve = approveOf(message);
    const reject = rejectOf(message);
    const headersBefore = (await answerHeaders(user)).count;

    const reply = nextReply(page);
    await approve.click();
    for (const [name, button] of [['Approve', approve], ['Reject', reject]] as const) {
      await expect(button, `${name} is busy`).toHaveAttribute('aria-busy', 'true');
      await expect(button, `${name} is aria-disabled`).toHaveAttribute('aria-disabled', 'true');
      await expect(button.locator('app-icon.spinner'), `${name} shows the spinner`).toHaveCount(1);
      expect(await button.getAttribute('disabled'), `${name} is never disabled`).toBeNull();
    }

    const response = await reply;
    const repliedAt = Date.now();
    expect(response.status(), 'the answer is 200').toBe(200);
    const answeredAt = (await replyBody(response)).body.approval?.answeredAt ?? '';
    expect(answeredAt, "the reply carries the request's answer").toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);

    const line = lineOf(message);
    await expect(line, 'the answer replaces the buttons').toHaveText(`Approved from the simulated phone at ${hhmm(answeredAt)}.`);
    await expect(message.locator('.buttons'), 'and the two buttons are gone').toHaveCount(0);
    await expect(line, 'focus is on the answer line').toBeFocused();
    await expect(line).toHaveCSS('color', await tokenColor(page, '--answered-status-approved'));

    const status = card.locator('p.status');
    await expect(status, "the card shows the answer within 2 s of the reply").toHaveText(`Approved from the simulated phone at ${pageHhmm(answeredAt)}`, { timeout: PAGE_MS });
    const cardMs = Date.now() - repliedAt;
    console.log(`ANSWERS X2 the card showed the answer ${cardMs} ms after the reply (bound ${PAGE_MS} ms)`);
    expect(cardMs, 'counted from the reply, the card showed it within 2 s (NFR-9)').toBeLessThanOrEqual(PAGE_MS);
    await expect(rowOfRequest(page, request), 'the rail row leaves within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });

    const row = await readApproval(request);
    expect(row.state, 'the row is approved').toBe('approved');
    expect(row.action).toBe('approve');
    expect(row.channel, 'from the simulated phone').toBe('phone');
    expect(row.by.toLowerCase(), 'by the signed-in user').toBe(user.toLowerCase());
    expect((await answerHeaders(user)).count - headersBefore, 'one AnswersIn to AnswerOps header').toBe(1);

    await page.waitForTimeout(1500);
    const texts = await announcedTexts(page);
    expect(texts.filter((text) => text.includes('Approved from the simulated phone')), 'the card announced nothing: the answer took focus on the phone').toEqual([]);
    expect(await phoneMessage(user, request).then((one) => one?.answer), 'the server has not edited the message: no answered notification came').toBe('');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/**
 * X3: Approve on the card, then the stand-in for IncidentManager's answered notification. Before it the phone keeps its buttons; after
 * it the phone's line "Approved from the web chat at HH:MM." replaces them within 5 s of the answer's reply (NFR-9; the elapsed time
 * is logged), in place: the same message, no new one, and the feed does not move. The server's message holds the answer. The card
 * announces nothing of an answer that its own press made, also when focus has moved to the composer while the press is out.
 */
test('X3: an answer on the card reaches the phone within 5 s, editing its message in place', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const incident = refOf('X3');
    const request = await raise(page, user, rows, incident, []);
    const { ref, message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const notifications = phoneOf(page).locator('.notification');
    const countBefore = await notifications.count();
    const index = await notifications.evaluateAll((nodes, key) => nodes.findIndex((node) => (node as HTMLElement).dataset['key'] === key), ref);
    const top = await feedOf(page).evaluate((feed) => feed.scrollTop);
    const textBefore = await message.locator('.text').first().textContent();

    const reply = nextReply(page);
    await card.getByRole('button', { name: APPROVE, exact: true }).click();
    await composerOf(page).click();
    const response = await reply;
    const repliedAt = Date.now();
    expect(response.status()).toBe(200);
    const answeredAt = (await replyBody(response)).body.approval?.answeredAt ?? '';
    await expect(approveOf(message), 'before the answered notification, the phone keeps its buttons').toHaveCount(1);
    await expect(rejectOf(message)).toHaveCount(1);

    await sendNotification(user, {
      kind: 'answered',
      catalogKey: 'answered.approved',
      slots: { channel: 'web', time: answeredAt },
      approvalRef: request,
      incidentRef: incident,
    });
    const line = lineOf(message);
    await expect(line, 'the phone shows the answer within 5 s of the reply').toHaveText(`Approved from the web chat at ${hhmm(answeredAt)}.`, { timeout: PHONE_MS });
    const phoneMs = Date.now() - repliedAt;
    console.log(`ANSWERS X3 the phone showed the answer ${phoneMs} ms after the reply (bound ${PHONE_MS} ms)`);
    expect(phoneMs, 'counted from the reply, the stand-in send included, the phone showed it within 5 s (NFR-9)').toBeLessThanOrEqual(PHONE_MS);
    await expect(message.locator('.buttons'), 'the buttons are gone').toHaveCount(0);
    expect(await notifications.count(), 'no new message').toBe(countBefore);
    expect(await notifications.evaluateAll((nodes, key) => nodes.findIndex((node) => (node as HTMLElement).dataset['key'] === key), ref), 'the message stands where it stood').toBe(index);
    expect(await feedOf(page).evaluate((feed) => feed.scrollTop), 'the feed did not move').toBe(top);
    await expect(message.locator('.text').first(), 'and the text is the same').toHaveText(textBefore ?? '');

    const stored = await phoneMessage(user, request);
    expect(stored?.ref, 'the same message').toBe(ref);
    expect(stored?.answer, "holds the answer in the server's wording").toBe(`Approved from the web chat at ${hhmm(answeredAt)}.`);
    const row = await readApproval(request);
    expect(row.channel, 'the row says the web').toBe('web');
    expect((await announcedTexts(page)).filter((text) => text.includes('Approved from the web chat')), "the card's own press announces no answer: it made it").toEqual([]);
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/**
 * X4: the press that lost the race. The web answers first, quietly (no event and no notification), so the phone still shows its
 * buttons. Approve on the phone gets the 409: "Already answered: approved from the web chat at HH:MM." is shown and announced once,
 * the answer line from the reply replaces the buttons, and the row is unchanged (the first answer wins).
 */
test('X4: a press on stale buttons gets the late-press notice once and shows the winning answer', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const incident = refOf('X4');
    const request = await raise(page, user, rows, incident, []);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    expect(await answerQuietly(user, request, 'approve', 'web'), 'the web answers first').toBe('done');
    await expect(approveOf(message), 'the phone does not know yet').toHaveCount(1);
    const answered = await readApproval(request);

    const reply = nextReply(page);
    await approveOf(message).click();
    expect((await reply).status(), 'the second answer is refused with 409').toBe(409);
    const notice = `Already answered: approved from the web chat at ${hhmm(answered.at)}.`;
    await expect(message.getByText(notice, { exact: true }), 'the notice shows').toBeVisible({ timeout: CARD_MS });
    await expect(lineOf(message), 'and the answer line of the winner replaces the buttons').toHaveText(`Approved from the web chat at ${hhmm(answered.at)}.`);
    await expect(message.locator('.buttons')).toHaveCount(0);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text.includes(notice)).length), { message: 'the notice is announced once' }).toBe(1);
    await page.waitForTimeout(1500);
    expect((await announcedTexts(page)).filter((text) => text.includes(notice)), 'and not again').toHaveLength(1);

    const after = await readApproval(request);
    expect(after, 'the row is unchanged').toEqual(answered);
    expect(after.channel, 'the first answer stands').toBe('web');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/**
 * X5: the phone's busy rule and its failure notices. A held press makes one request however often the buttons are pressed, and the
 * request says channel phone; the buttons are busy (aria-busy and aria-disabled, never disabled); after 10 s both are restored with
 * the notice, shown and announced once; and when the answer then comes its line shows and the notice clears. Then a 404, a 403, a 500
 * and a dropped connection show their notices, each announced, and leave the buttons restored.
 */
test('X5: a held press on the phone is busy and sends one request, restores after 10 s with the notice, and a late answer still shows', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  const bodies: string[] = [];
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const busyNotice = "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.";
  try {
    await page.route(ANSWER, async (route: Route) => {
      bodies.push(route.request().postData() ?? '');
      await gate;
      await route.continue();
    });
    await open(page);
    const incident = refOf('X5');
    const request = await raise(page, user, rows, incident, []);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    const approve = approveOf(message);
    const reject = rejectOf(message);

    await approve.click();
    await expect(approve).toHaveAttribute('aria-busy', 'true');
    await approve.click({ force: true });
    await reject.click({ force: true });
    await page.waitForTimeout(400);
    expect(bodies, 'three presses and one request').toHaveLength(1);
    expect(JSON.parse(bodies[0] ?? '{}'), 'which names only the action and the channel phone').toEqual({ action: 'approve', channel: 'phone' });
    for (const [name, button] of [['Approve', approve], ['Reject', reject]] as const) {
      await expect(button, `${name} is busy`).toHaveAttribute('aria-busy', 'true');
      await expect(button, `${name} is aria-disabled`).toHaveAttribute('aria-disabled', 'true');
      await expect(button.locator('app-icon.spinner'), `${name} has a spinner`).toHaveCount(1);
      expect(await button.getAttribute('disabled'), `${name} is never disabled`).toBeNull();
    }

    const notice = message.getByText(busyNotice, { exact: true });
    await expect(notice, 'after 10 s the notice shows').toBeVisible({ timeout: 15_000 });
    await expect(approve, 'and the buttons are restored').not.toHaveAttribute('aria-busy', /.*/);
    await expect(reject).not.toHaveAttribute('aria-busy', /.*/);
    await expect(approve).not.toHaveAttribute('aria-disabled', /.*/);
    await expect(approve.locator('app-icon.spinner'), 'with no spinner').toHaveCount(0);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text.includes(busyNotice)).length), { message: 'the notice is announced once' }).toBe(1);
    expect(await readApproval(request).then((one) => one.state), 'the request is still waiting').toBe('pending');

    release();
    await expect(lineOf(message), 'the late answer still shows').toContainText('Approved from the simulated phone at', { timeout: 30_000 });
    await expect(notice, 'and the notice clears').toHaveCount(0);
    expect(bodies, 'still one request').toHaveLength(1);
  } finally {
    release();
    await page.unroute(ANSWER);
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }

  // The failures: one request, three presses, each answered by the test. The phone keeps its buttons after every failure.
  const failures = [
    { status: 404, code: 'not_found', message: 'That is not a request of yours.', shown: 'That request is no longer available.' },
    { status: 403, code: 'not_allowed', message: 'Only an approver for resends can answer this request.', shown: 'Only an approver for resends can answer this request.' },
    { status: 500, code: 'failed', message: 'OcuTalon could not answer. Nothing was changed.', shown: 'OcuTalon could not answer. Nothing was changed.' },
  ];
  const rows2: string[] = [];
  const start2 = startOf();
  let next = 0;
  try {
    await page.route(ANSWER, async (route: Route) => {
      const one = failures[next]!;
      await route.fulfill({ status: one.status, contentType: 'application/json', body: JSON.stringify({ error: { code: one.code, message: one.message } }) });
    });
    const incident = refOf('X5b');
    const request = await raise(page, user, rows2, incident, []);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    for (const [i, one] of failures.entries()) {
      next = i;
      await approveOf(message).click();
      await expect(message.getByText(one.shown, { exact: true }), `${one.status} shows its notice`).toBeVisible({ timeout: CARD_MS });
      await expect(approveOf(message), `${one.status}: the buttons are restored`).not.toHaveAttribute('aria-busy', /.*/);
      await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text.includes(one.shown)).length), { message: `${one.status}'s notice is announced once` }).toBe(1);
    }
    await expect(message.getByText(failures[0]!.shown, { exact: true }), 'a new press cleared the notice before it').toHaveCount(0);
    expect(await readApproval(request).then((one) => one.state), 'nothing was changed').toBe('pending');
    await page.unroute(ANSWER);

    const announced = (await announcedTexts(page)).filter((text) => text.includes(busyNotice)).length;
    await page.route(ANSWER, (route: Route) => route.abort('failed'));
    await approveOf(message).click();
    await expect(message.getByText(busyNotice, { exact: true }), 'no connection shows the busy notice at once').toBeVisible({ timeout: 5000 });
    await expect(approveOf(message)).not.toHaveAttribute('aria-busy', /.*/);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text.includes(busyNotice)).length), { message: 'and announces it' }).toBe(announced + 1);
    await page.unroute(ANSWER);
  } finally {
    await page.unroute(ANSWER).catch(() => undefined);
    await dropPhone(user, start2);
    await cleanFixtureRows(rows2);
  }
});

/**
 * X6: a press on a rail row. Focus goes to the request's card in the chat and the card is in view, also in the drawer band (1100 px
 * wide, the rail opened from Status), where the drawer stays open. A tool call's request has no card in the chat, so its row has no
 * button. A request of an incident whose card is not in the chat keeps its button, and a press takes focus to the chat's list.
 */
test('X6: a press on a request\'s rail row focuses its card and shows it, also in the drawer band', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 520 });
    await open(page);
    const requests: string[] = [];
    for (const label of ['X6a', 'X6b', 'X6c']) {
      const incident = refOf(label);
      await raise(page, user, rows, incident, []);
    }
    const target = await raise(page, user, rows, refOf('X6'), requests);
    const card = requestCard(page, target);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const list = page.locator('app-chat-panel .list');
    await scrollListTo(list, 'top');
    await composerOf(page).click();
    await expect(card, 'the card is out of view before the press').not.toBeInViewport({ ratio: 0.5 });

    const row = rowOfRequest(page, target);
    const jump = row.getByRole('button', { name: 'Show in the chat: Repair and resend 50 orders', exact: true });
    await expect(jump, 'the row has a button named for what it does').toHaveCount(1);
    await expect(row.locator('.title .lead'), 'the title is the button, not a plain span').toHaveCount(0);
    await expect(jump).toHaveText('Repair and resend 50 orders');
    const visible = ((await jump.textContent()) ?? '').trim();
    await expect(jump, 'its accessible name contains its visible text verbatim, same case and words (WCAG 2.5.3)').toHaveAccessibleName(
      new RegExp(visible.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    );
    await jump.click();
    await expect(card, 'focus is on the request card').toBeFocused();
    await expect(card, 'which is in view').toBeInViewport();

    const tool = await seedApproval(user, { kind: 'tool_call', toolName: 'zz_tool_x6', dryRun: null, requiredRole: 'OcuTalonUser' });
    rows.push(tool);
    await sinkEvent(user, 'approval.raised', { ref: tool });
    await expect(rowOfRequest(page, tool), "a tool call's row shows").toHaveCount(1, { timeout: CARD_MS });
    await expect(rowOfRequest(page, tool).locator('button'), 'with no button').toHaveCount(0);
    await expect(rowOfRequest(page, tool)).toContainText('Run zz_tool_x6');

    // A request of an incident whose card is not in the chat: its row keeps the button, and a press takes focus to the chat's list.
    const orphan = await seedApproval(user, { incidentRef: refOf('X6d'), requiredRole: 'OcuTalonUser', dryRun: DRY_RUN });
    rows.push(orphan);
    await sinkEvent(user, 'approval.raised', { ref: orphan });
    const orphanJump = rowOfRequest(page, orphan).getByRole('button', { name: 'Show in the chat: Repair and resend 50 orders', exact: true });
    await expect(orphanJump, "a request whose card is not in the chat keeps its row's button").toHaveCount(1, { timeout: CARD_MS });
    await expect(requestCard(page, orphan), 'and has no card there').toHaveCount(0);
    await orphanJump.click();
    await expect(list, 'the press takes focus to the chat list').toBeFocused();

    // The drawer band: the rail is behind the Status button, and a press leaves the drawer open.
    await page.setViewportSize({ width: 1100, height: 520 });
    await scrollListTo(list, 'top');
    await page.locator('button.status-button').click();
    await expect(railOf(page), 'the drawer is open').toBeVisible();
    await expect(card, 'the card is out of view again').not.toBeInViewport({ ratio: 0.5 });
    await jump.click();
    await expect(card, 'focus is on the request card in the drawer band too').toBeFocused();
    await expect(card, 'which is in view').toBeInViewport();
    await expect(railOf(page), 'and the drawer stays open').toBeVisible();
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * X7: a pending request on the phone's screen holds its feed. When another notification arrives the feed does not scroll, New messages
 * shows, and Approve stays where it was.
 */
test('X7: a pending request on the phone holds the feed when a tell-now arrives', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const incident = refOf('X7');
    const request = await raise(page, user, rows, incident, []);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    const approve = approveOf(message);
    await expect(approve).toBeVisible();
    const feed = feedOf(page);
    const top = await feed.evaluate((element) => element.scrollTop);
    const box = await approve.boundingBox();

    const marker = unique('X7 tell-now');
    await sendNotification(user, { kind: 'tellnow', catalogKey: 'notice.tellNow', slots: { whatHappened: marker, reason: 'zz X7 reason' } });
    await expect(phoneOf(page).locator('.notification').filter({ hasText: marker }), 'the tell-now arrives on the phone').toHaveCount(1, { timeout: CARD_MS });
    await expect(phoneOf(page).getByRole('button', { name: 'New messages' }), 'New messages shows').toBeVisible();
    expect(await feed.evaluate((element) => element.scrollTop), 'the feed did not scroll').toBe(top);
    expect(await approve.boundingBox(), "and Approve's box is unchanged").toEqual(box);
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/**
 * X8: an answer from elsewhere. The phone answers quietly and the bridge's approval.answered event reaches the page, with focus in the
 * composer: the request card shows its status within 2 s of the event being sent (the page's poll, NFR-9; X2 counts from the reply,
 * which on a fixture row comes about 5 s after the event, so only this case pins the poll's cadence) and announces it exactly once.
 * With focus on the card's Approve instead, the status that replaces it takes focus and is not announced.
 */
test('X8: an answer from elsewhere is announced once by the card', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('X8');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await composerOf(page).click();
    await expect(composerOf(page)).toBeFocused();

    expect(await answerQuietly(user, request, 'approve', 'phone'), 'the phone answers').toBe('done');
    const answered = await readApproval(request);
    await sinkEvent(user, 'approval.answered', { ref: request });
    const sentAt = Date.now();
    const text = `Approved from the simulated phone at ${pageHhmm(answered.at)}`;
    await expect(card.locator('p.status'), 'the card shows the answer within 2 s of the event being sent').toHaveText(text, { timeout: PAGE_MS });
    console.log(`ANSWERS X8 the card showed the answer ${Date.now() - sentAt} ms after the event was sent (bound ${PAGE_MS} ms)`);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((one) => one.includes(text)).length), { message: 'the card announces it' }).toBe(1);
    await page.waitForTimeout(1500);
    expect((await announcedTexts(page)).filter((one) => one.includes(text)), 'once').toHaveLength(1);
    await expect(composerOf(page), 'and focus did not move').toBeFocused();

    // The same, with focus on the card's Approve: the status that replaces it takes focus, so it is not announced.
    const second = await raise(page, user, rows, refOf('X8b'), []);
    const secondCard = requestCard(page, second);
    await expect(secondCard).toHaveCount(1, { timeout: CARD_MS });
    await secondCard.getByRole('button', { name: APPROVE, exact: true }).focus();
    expect(await answerQuietly(user, second, 'approve', 'phone'), 'the phone answers the second').toBe('done');
    const secondText = `Approved from the simulated phone at ${pageHhmm((await readApproval(second)).at)}`;
    const announcedBefore = (await announcedTexts(page)).filter((one) => one.includes(secondText)).length;
    await sinkEvent(user, 'approval.answered', { ref: second });
    const secondStatus = secondCard.locator('p.status');
    await expect(secondStatus, 'the card shows the answer').toHaveText(secondText, { timeout: PAGE_MS });
    await expect(secondStatus, 'focus moved from Approve to the status').toBeFocused();
    await page.waitForTimeout(1500);
    expect((await announcedTexts(page)).filter((one) => one.includes(secondText)), 'which is not announced: the answer took focus').toHaveLength(announcedBefore);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * X9 (QA): Reject on the phone. The request names the channel phone and the action reject, the phone's line is "Rejected from the
 * simulated phone at HH:MM. Nothing was changed." in the rejected tone with focus on it, the card follows within 2 s of the reply and
 * the rail row leaves, and the row is rejected from the phone. X2 pins Approve; this is the other button of the same press.
 */
test('X9: Reject on the phone sends reject from the phone and nothing is changed', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const incident = refOf('X9');
    const request = await raise(page, user, rows, incident, []);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await expect(rowOfRequest(page, request)).toHaveCount(1);

    const reply = nextReply(page);
    await rejectOf(message).click();
    const response = await reply;
    const repliedAt = Date.now();
    expect(JSON.parse(response.request().postData() ?? '{}'), 'the press names the action and the channel phone only').toEqual({ action: 'reject', channel: 'phone' });
    expect(response.status(), 'the answer is 200').toBe(200);
    const answeredAt = (await replyBody(response)).body.approval?.answeredAt ?? '';
    expect(answeredAt).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);

    const line = lineOf(message);
    await expect(line, 'the line replaces the buttons').toHaveText(`Rejected from the simulated phone at ${hhmm(answeredAt)}. Nothing was changed.`);
    await expect(message.locator('.buttons')).toHaveCount(0);
    await expect(line, 'focus is on the line').toBeFocused();
    await expect(line, 'in the rejected tone').toHaveCSS('color', await tokenColor(page, '--answered-status-rejected'));
    await expect(card.locator('p.status'), 'the card follows within 2 s of the reply').toContainText(`Rejected from the simulated phone at ${pageHhmm(answeredAt)}`, { timeout: PAGE_MS });
    const cardMs = Date.now() - repliedAt;
    console.log(`ANSWERS X9 the card showed the rejection ${cardMs} ms after the reply (bound ${PAGE_MS} ms)`);
    expect(cardMs, 'counted from the reply, the card showed it within 2 s (NFR-9)').toBeLessThanOrEqual(PAGE_MS);
    await expect(rowOfRequest(page, request), 'the rail row leaves').toHaveCount(0, { timeout: ONE_UPDATE_MS });

    const row = await readApproval(request);
    expect(row.state, 'the row is rejected').toBe('rejected');
    expect(row.action).toBe('reject');
    expect(row.channel, 'from the simulated phone').toBe('phone');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/**
 * X10 (QA): a reload keeps the phone's messages as the server holds them. Of two requests, one is approved on the card and the
 * phone is told by the stand-in for IncidentManager's answered notification; after a reload the message of the first shows its stored
 * answer line and no buttons, and the message of the pending second still asks (Approve and Reject, no line). The snapshot's
 * `phone` rows carry `approvalRef` and `answer`, which X1 to X8 never read back. Before the reload, focus on the phone's Approve of
 * the first request moves to the line when the server's edit replaces the buttons (the device panel's focus rule).
 */
test('X10: after a reload the answered message keeps its line and the pending one its buttons', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = startOf();
  try {
    await open(page);
    const incident = refOf('X10');
    const requests: string[] = [];
    const first = await raise(page, user, rows, incident, requests);
    const second = await raise(page, user, rows, incident, requests, { raisedAt: today('14:14:00') });
    const since = inMs(-120_000);
    const a = await noticeOnPhone(page, user, first, incident, since);
    const b = await noticeOnPhone(page, user, second, incident, since, 'approval');
    expect(b.ref).not.toBe(a.ref);

    const reply = nextReply(page);
    await requestCard(page, first).getByRole('button', { name: APPROVE, exact: true }).click();
    const response = await reply;
    expect(response.status()).toBe(200);
    const answeredAt = (await replyBody(response)).body.approval?.answeredAt ?? '';
    await expect(requestCard(page, first).locator('p.status'), "the card's own press is done").toHaveCount(1);
    await approveOf(a.message).focus();
    await expect(approveOf(a.message), "focus is on the phone's Approve of the answered request").toBeFocused();
    await sendNotification(user, { kind: 'answered', catalogKey: 'answered.approved', slots: { channel: 'web', time: answeredAt }, approvalRef: first, incidentRef: incident });
    const expected = `Approved from the web chat at ${hhmm(answeredAt)}.`;
    await expect(lineOf(a.message), 'the phone shows the edit before the reload').toHaveText(expected, { timeout: PHONE_MS });
    await expect(lineOf(a.message), 'and focus on the Approve that the edit replaced moves to the line').toBeFocused();
    await expect.poll(() => phoneMessage(user, first).then((one) => one?.answer), { message: 'and the server holds it' }).toBe(expected);

    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(phoneOf(page)).toBeVisible();
    const answered = messageOf(page, a.ref);
    const pending = messageOf(page, b.ref);
    await expect(answered, 'the answered message is still on the phone').toHaveCount(1, { timeout: CARD_MS });
    await expect(lineOf(answered), 'with the stored answer line').toHaveText(expected);
    await expect(answered.getByRole('button'), 'and no buttons').toHaveCount(0);
    await expect(pending, 'the pending message is still on the phone').toHaveCount(1);
    await expect(pending.getByRole('button', { name: /^Approve/ }), 'and still asks').toHaveCount(1);
    await expect(pending.getByRole('button', { name: /^Reject/ })).toHaveCount(1);
    await expect(lineOf(pending), 'with no answer line').toHaveCount(0);
    expect(await phoneMessage(user, second).then((one) => one?.answer), 'the second message holds no answer').toBe('');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});
