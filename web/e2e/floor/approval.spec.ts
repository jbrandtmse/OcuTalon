import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { changeSnapshot, post } from '../support/api';
import { CARD_MS, HEADER, applied, openFloor, unique } from '../support/floor';
import {
  answerHeaders,
  answerQuietly,
  cleanFixtureRows,
  fixtureUser,
  publishIncident,
  readApproval,
  seedApproval,
  seedOtherSession,
  sinkEvent,
} from '../support/iris';
import { announcedTexts, recordAnnouncements, tokenColor } from '../support/page';

/**
 * Story 6.2, the approval request card inside the incident card (A1 to A10), in a real browser against a real stack, as the FLOOR user
 * (the floor stack is in demo mode, its instance zone is UTC and the browser's is UTC and en-GB; the page's clock is fixed at 14:30
 * UTC on the run's date). An incident card is made as IncidentManager will make it (an `incident` event, publishIncident); a
 * request is a fixture row (seedApproval) whose `approval` event reaches the page through BridgeSink (sinkEvent), with the required
 * role OcuTalonUser that the floor user holds. A press goes through the page to AnswersIn, AnswerOps and Approval.Answer in the
 * production, which waits about 5 s for the task that a fixture row's hold would have. HH:MM is the row's AnsweredAt, read back
 * through iris, so that the expected text is exact. A case's rows are its own and are removed in finally.
 * A1 is the pending card (and runs in Firefox and WebKit too, tag @browsers), A2 an Approve, A3 two requests and a Reject, A4 the busy
 * rule (one request however often pressed, the notice after 10 s and the late answer), A5 the press that lost the race to the phone,
 * A6 the 1280x600 layout and A7 another session's request, A8 the replies that are not an answer, A9 a closed incident and A10 the
 * headline cap letting go once the reader scrolls on.
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'FLOOR';

/** The route that answers a request. */
const ANSWER = '**/ocutalon/api/v1/approvals/*/answer';

/** The run's date (UTC), taken once, so that every time of the spec and the page's clock are on the same date. */
const DAY = new Date().toISOString().slice(0, 10);

/** The run's date with the time given, as a UTC ISO time. */
const today = (time: string): string => `${DAY}T${time}Z`;

/** The day after the run's, at 14:13 UTC: the expiry of a request, which the card reads as "tomorrow at 14:13" against the clock. */
const TOMORROW_AT_1413 = new Date(Date.parse(today('14:13:00')) + 86_400_000).toISOString().replace(/\.\d{3}Z$/, 'Z');

/** The page's clock in every case: 14:30 UTC on the run's date. */
test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(Date.parse(today('14:30:00')));
});

/** A ref of this case's own: at most 22 characters, letters and digits. */
const refOf = (label: string): string => `zz${label}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

/** The dry run of the matrix's first row: 50 orders, OrderDate 10/16/2026 to 2026-10-16. */
const DRY_RUN = { affected: 50, itemNoun: { one: 'order', other: 'orders' }, field: 'OrderDate', before: '10/16/2026', after: '2026-10-16' } as const;

/** The incident payload of a card that is awaiting approval, with the parts of its evidence panel. */
function incidentOf(ref: string, requests: string[]): Record<string, unknown> {
  return {
    ref,
    state: 'awaiting_approval',
    count: 50,
    noticeCount: 50,
    firstAt: today('14:12:00'),
    lastAt: today('14:13:00'),
    itemNoun: { one: 'order', other: 'orders' },
    cause: 'The partner changed its date format.',
    fixSummary: 'repair and resend all 50',
    causeCategory: 'data_format_change',
    element: 'order date',
    requests: requests.map((one) => ({ ref: one, state: 'pending' })),
    evidence: {
      sampleHeaderId: 1047,
      sampleError: 'zz Could not parse OrderDate',
      items: [{ itemName: 'Order transform', count: 50, firstAt: today('14:12:03'), lastAt: today('14:12:31') }],
    },
    traceTargets: { diagnosis: { traceHeaderId: HEADER, traceNamespace: 'OCUTALON' } },
  };
}

/** The incident card of a ref, and the request card of a ref. */
const incidentCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);

/** The HH:MM of a UTC ISO time. */
const hhmm = (iso: string): string => iso.slice(11, 16);

/** The two buttons of a pending card, by their names. */
const approveOf = (card: Locator): Locator => card.getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true });
const rejectOf = (card: Locator): Locator => card.getByRole('button', { name: 'Reject: repair and resend 50 orders', exact: true });

/** Signs the floor user in with the announcements recorded, and checks the stack: demo mode on and the instance in UTC. */
async function open(page: Page): Promise<void> {
  await recordAnnouncements(page);
  await openFloor(page);
}

/**
 * Seeds a pending request of the incident (required role OcuTalonUser, expiring tomorrow at 14:13), opens the page when it is not
 * open, publishes the incident with all the requests named so far and the request's `approval` event, and waits until the page
 * applied both. Returns the request's Ref.
 */
async function raise(page: Page, user: string, rows: string[], incident: string, requests: string[], over: Record<string, unknown> = {}): Promise<string> {
  const request = await seedApproval(user, {
    incidentRef: incident,
    requiredRole: 'OcuTalonUser',
    expiresAt: TOMORROW_AT_1413,
    raisedAt: today('14:13:00'),
    dryRun: DRY_RUN,
    ...over,
  });
  rows.push(request);
  requests.push(request);
  await applied(page, await publishIncident(user, incidentOf(incident, requests)));
  await applied(page, await sinkEvent(user, 'approval.raised', { ref: request }));
  return request;
}

/** Expects the elements to stand one under the other, in this order; their tops are read in one step, so that a scroll between reads changes nothing. */
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
 * A1: the pending card with the matrix's texts in order: the label, the action, the fixed-targets line, the dry run with its mono
 * example in the danger and success inks, the row with Approve (primary), Reject (secondary) and Show details at the right end, and
 * the expiry. There is no "Why:" and no incident-level Show details row, and Show details opens the panel below the row and the expiry.
 */
test('A1: a pending request shows its card, with the texts in order, the buttons named with the object and Show details at the row\'s end', { tag: '@browsers' }, async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('A1');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card, 'one request card for the ref').toHaveCount(1, { timeout: CARD_MS });
    await expect(incidentCard(page, incident).locator('.actions'), 'the incident has no Show details row of its own').toHaveCount(0);

    const label = card.locator('.label');
    const action = card.locator('p.action');
    const fixed = card.locator('p.fixed');
    const dry = card.locator('.dry');
    const approve = approveOf(card);
    const reject = rejectOf(card);
    const details = card.getByRole('button', { name: 'Show details', exact: true });
    const expiry = card.locator('p.expiry');
    await expect(label).toHaveText('Approval needed');
    await expect(action).toHaveText('Repair and resend 50 orders.');
    await expect(fixed).toHaveText('Approving runs exactly this change on these 50 orders, without asking the model again. New failures need their own approval.');
    await expect(dry.locator('.dry-label')).toHaveText('Dry run');
    await expect(dry.locator('.dry-count')).toHaveText('50 orders affected');
    await expect(dry.locator('.dry-row').nth(0)).toHaveText('BeforeOrderDate 10/16/2026');
    await expect(dry.locator('.dry-row').nth(1)).toHaveText('AfterOrderDate 2026-10-16');
    await expect(dry.locator('.dry-row').nth(2)).toHaveText('Will resend50 repaired copies; the originals stay unchanged.');
    await expect(dry.locator('.dry-note')).toHaveText('Nothing has changed yet.');
    await expect(approve).toHaveText('Approve');
    await expect(approve, 'Approve is the primary button').toHaveClass(/button-primary/);
    await expect(reject).toHaveText('Reject');
    await expect(reject, 'Reject is the secondary button').toHaveClass(/button-secondary/);
    await expect(expiry).toHaveText('Expires tomorrow at 14:13');
    await expect(card.getByText('Why:'), 'no Why: line inside an incident card').toHaveCount(0);
    await expect(details).toHaveAttribute('aria-expanded', 'false');
    await inOrder([label, action, fixed, dry, approve, expiry], 'top to bottom');
    const xs = await Promise.all([approve, reject, details].map(async (button) => (await button.boundingBox())!.x));
    expect(xs[0]! < xs[1]! && xs[1]! < xs[2]!, `Approve, Reject and Show details stand left to right: ${xs.join(', ')}`).toBe(true);
    const row = card.locator('.answer-row');
    expect(await row.locator('button').allTextContents().then((texts) => texts.map((one) => one.trim())), 'the row holds the three buttons, Show details last').toEqual(['Approve', 'Reject', 'Show details']);
    const [approveBox, detailsBox, rowBox] = await Promise.all([approve.boundingBox(), details.boundingBox(), row.boundingBox()]);
    expect(detailsBox!.x + detailsBox!.width, 'Show details is at the right end of the row').toBeGreaterThan(rowBox!.x + rowBox!.width - 12);
    expect(approveBox!.y, 'on the same line as Approve').toBeLessThan(detailsBox!.y + detailsBox!.height);

    const before = dry.locator('.mono.before');
    const after = dry.locator('.mono.after');
    await expect(before, 'Before is in the danger ink').toHaveCSS('color', await tokenColor(page, '--danger-ink'));
    await expect(after, 'After is in the success ink').toHaveCSS('color', await tokenColor(page, '--success-ink'));
    await expect(before).toHaveCSS('font-family', /JetBrains Mono/);
    await expect(after).toHaveCSS('font-family', /JetBrains Mono/);
    await expect(card, 'the pending bar is 4px in the attention colour').toHaveCSS('border-left-width', '4px');
    await expect(card).toHaveCSS('border-left-color', await tokenColor(page, '--attention'));
    await expect(label, 'the label is in the attention ink').toHaveCSS('color', await tokenColor(page, '--attention-ink'));

    await details.click();
    await expect(details).toHaveAttribute('aria-expanded', 'true');
    const panel = card.locator('.panel[id]');
    await expect(panel.getByText('Held as an IRIS Workflow task until someone answers.')).toBeVisible();
    await expect(details).toHaveAttribute('aria-controls', (await panel.getAttribute('id')) ?? '');
    await inOrder([approve, expiry, card.locator('app-evidence-panel')], 'the panel stands below the row and the expiry');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A2: Approve. Both buttons are busy while the answer is out; then "Approved from the web chat at HH:MM" replaces them in the same row
 * with focus on it, the label reads "Approval request", the fixed-targets line, the expiry and "Nothing has changed yet." go and the
 * dry run stays. The row is approved by FLOOR on the web, and one AnswersIn to AnswerOps header carries FLOOR's TraceRef.
 */
test('A2: Approve is busy, then the status replaces the buttons with focus on it, and the request is answered from the web', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('A2');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const approve = approveOf(card);
    const reject = rejectOf(card);
    const before = (await answerHeaders(user)).count;

    await approve.click();
    for (const [name, button] of [['Approve', approve], ['Reject', reject]] as const) {
      await expect(button, `${name} is busy`).toHaveAttribute('aria-busy', 'true');
      await expect(button, `${name} is aria-disabled`).toHaveAttribute('aria-disabled', 'true');
      await expect(button.locator('app-icon.spinner'), `${name} shows the spinner`).toHaveCount(1);
      expect(await button.getAttribute('disabled'), `${name} is never disabled`).toBeNull();
    }

    const status = card.locator('p.status');
    await expect.poll(async () => readApproval(request).then((one) => one.at), { message: 'the request is answered', timeout: 30_000 }).not.toBe('');
    const answered = await readApproval(request);
    await expect(status, 'the status replaces the buttons').toHaveText(`Approved from the web chat at ${hhmm(answered.at)}`, { timeout: CARD_MS });
    await expect(card.locator('.buttons'), 'and the two buttons are gone').toHaveCount(0);
    await expect(status, 'focus is on the status line').toBeFocused();
    await expect(status).toHaveCSS('color', await tokenColor(page, '--answered-status-approved'));
    await expect(card.locator('.label')).toHaveText('Approval request');
    await expect(card.locator('p.fixed'), 'the fixed-targets line goes').toHaveCount(0);
    await expect(card.locator('p.expiry'), 'the expiry goes').toHaveCount(0);
    await expect(card.locator('.dry-note'), '"Nothing has changed yet." goes').toHaveCount(0);
    await expect(card.locator('.dry-count'), 'the dry run stays').toHaveText('50 orders affected');
    await expect(card).toHaveCSS('border-left-color', await tokenColor(page, '--success-ink'));

    expect(answered.state, 'the row is approved').toBe('approved');
    expect(answered.action).toBe('approve');
    expect(answered.channel, 'on the web').toBe('web');
    expect(answered.by.toLowerCase(), 'by the signed-in user').toBe(user.toLowerCase());
    const headers = await answerHeaders(user);
    expect(headers.count - before, 'one AnswersIn to AnswerOps header, tagged with the session\'s TraceRef').toBe(1);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A3: two requests of one incident stand in the order raised with Show details only in the first card's row. The later one's event
 * reaches the page first, so that the order is the page's sort by raisedAt and not the order of the events. The second was approved
 * by another user from the phone, and says so. Reject on the first reads "Rejected from the web chat at HH:MM. Nothing was changed.".
 */
test('A3: two requests stand in the order raised, the second names who approved it, and Reject gives its status', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('A3');
    const requests: string[] = [];
    const second = await raise(page, user, rows, incident, requests, {
      raisedAt: today('14:14:00'),
      state: 'approved',
      answeredAction: 'approve',
      answeredChannel: 'phone',
      answeredBy: 'zzsam',
      answeredAt: today('14:15:00'),
      dryRun: { ...DRY_RUN, affected: 2 },
    });
    const first = await raise(page, user, rows, incident, requests, { raisedAt: today('14:13:00') });
    const cards = incidentCard(page, incident).locator('[data-part="approval"]');
    await expect(cards, 'two request cards').toHaveCount(2, { timeout: CARD_MS });
    await expect(cards.nth(0), 'the first raised is first').toHaveAttribute('data-key', first);
    await expect(cards.nth(1)).toHaveAttribute('data-key', second);
    await expect(incidentCard(page, incident).getByRole('button', { name: 'Show details', exact: true }), 'one Show details').toHaveCount(1);
    await expect(cards.nth(0).getByRole('button', { name: 'Show details', exact: true }), 'in the first card\'s row').toHaveCount(1);
    await expect(cards.nth(1).getByRole('button', { name: 'Show details', exact: true })).toHaveCount(0);
    await expect(cards.nth(1).locator('p.status'), 'the second names who approved it, and where').toHaveText('Approved by zzsam from the simulated phone at 14:15');
    await expect(cards.nth(1).locator('.label')).toHaveText('Approval request');
    await expect(cards.nth(1).locator('p.action')).toHaveText('Repair and resend 2 orders.');

    await rejectOf(cards.nth(0)).click();
    await expect.poll(async () => readApproval(first).then((one) => one.state), { message: 'the first request is rejected', timeout: 30_000 }).toBe('rejected');
    const answered = await readApproval(first);
    await expect(cards.nth(0).locator('p.status'), 'the rejection reads with its second sentence').toHaveText(`Rejected from the web chat at ${hhmm(answered.at)}. Nothing was changed.`, { timeout: CARD_MS });
    await expect(cards.nth(0).locator('p.status')).toBeFocused();
    await expect(cards.nth(0).locator('p.status')).toHaveCSS('color', await tokenColor(page, '--answered-status-rejected'));
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A4: the answer is held by the test. Two presses make one request; both buttons are busy (a spinner, aria-busy, aria-disabled, never
 * disabled). After 10 s both are restored and the notice is shown and announced; when the answer then comes, the status shows and the
 * notice clears.
 */
test('A4: a held press is busy, makes one request however often pressed, restores after 10 s with the notice, and a late answer still shows', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const requests: string[] = [];
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  try {
    await page.route(ANSWER, async (route: Route) => {
      requests.push(route.request().postData() ?? '');
      await gate;
      await route.continue();
    });
    await open(page);
    const incident = refOf('A4');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const approve = approveOf(card);
    const reject = rejectOf(card);

    await approve.click();
    await expect(approve).toHaveAttribute('aria-busy', 'true');
    await approve.click({ force: true });
    await reject.click({ force: true });
    await page.waitForTimeout(400);
    expect(requests, 'two presses and one request').toHaveLength(1);
    expect(JSON.parse(requests[0] ?? '{}'), 'which names only the action and the channel').toEqual({ action: 'approve', channel: 'web' });
    for (const [name, button] of [['Approve', approve], ['Reject', reject]] as const) {
      await expect(button, `${name} is busy`).toHaveAttribute('aria-busy', 'true');
      await expect(button, `${name} is aria-disabled`).toHaveAttribute('aria-disabled', 'true');
      await expect(button.locator('app-icon.spinner'), `${name} has a spinner`).toHaveCount(1);
      expect(await button.getAttribute('disabled'), `${name} is never disabled`).toBeNull();
    }

    const notice = card.getByText("Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.", { exact: true });
    await expect(notice, 'after 10 s the notice shows').toBeVisible({ timeout: 15_000 });
    await expect(approve, 'and the buttons are restored').not.toHaveAttribute('aria-busy', /.*/);
    await expect(reject).not.toHaveAttribute('aria-busy', /.*/);
    await expect(approve).not.toHaveAttribute('aria-disabled', /.*/);
    await expect(approve.locator('app-icon.spinner'), 'with no spinner').toHaveCount(0);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text.includes("The request is still waiting.")).length), { message: 'the notice is announced once' }).toBe(1);
    expect(await readApproval(request).then((one) => one.state), 'the request is still waiting').toBe('pending');

    release();
    await expect(card.locator('p.status'), 'the late answer still shows').toContainText('Approved from the web chat at', { timeout: 30_000 });
    await expect(notice, 'and the notice clears').toHaveCount(0);
    expect(requests, 'still one request').toHaveLength(1);
  } finally {
    release();
    await page.unroute(ANSWER);
    await cleanFixtureRows(rows);
  }
});

/**
 * A5: the phone answers first, quietly (no event), so the page still shows the request as pending. The press then gets a 409: the
 * notice "Already answered: approved from the simulated phone at HH:MM." is announced and the status replaces the buttons.
 */
test('A5: a press that lost the race to the phone shows the late-press notice, announces it and shows the winning status', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('A5');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    expect(await answerQuietly(user, request, 'approve', 'phone'), 'the phone answers first').toBe('done');
    await expect(card.locator('.buttons'), 'the page does not know yet').toHaveCount(1);

    await approveOf(card).click();
    const answered = await readApproval(request);
    const text = `Already answered: approved from the simulated phone at ${hhmm(answered.at)}.`;
    await expect(card.getByText(text, { exact: true }), 'the page form of the late press shows under the row').toBeVisible({ timeout: 30_000 });
    await expect(card.locator('p.status'), 'and the status replaces the buttons').toHaveText(`Approved from the simulated phone at ${hhmm(answered.at)}`);
    await expect(card.locator('.buttons')).toHaveCount(0);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((one) => one === text).length), { message: 'the notice is announced once' }).toBe(1);
    expect(answered.channel, 'the phone\'s answer stands').toBe('phone');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A6: at 1280x600, with the card just landed and nothing scrolled by the test, the headline, the cause, the dry run's count, Approve
 * and Reject are all in the chat list's view. The case runs under the conditions of DESIGN.md's acceptance test: no status banner (the
 * floor stack's no-key banner is taken out of the snapshot) and the guide collapsed to its bar by Hide guide, because the banner
 * (44 px) and the open guide (139 px) leave the list 279 px, less than the card. Show details then brings its panel into view: a press
 * inside the card is not followed by a return to the headline.
 */
test('A6: at 1280 by 600 the headline, the cause, the dry-run count, Approve and Reject are in view without scrolling', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 600 });
    await changeSnapshot(page, (snapshot) => {
      snapshot['status'] = [];
    });
    await open(page);
    await page.getByRole('button', { name: 'Hide guide', exact: true }).click();
    const incident = refOf('A6');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const incidentView = incidentCard(page, incident);
    await expect(incidentView.getByRole('heading', { level: 3 }), 'the headline').toBeInViewport({ ratio: 1 });
    await expect(incidentView.locator('p.cause'), 'the cause').toBeInViewport({ ratio: 1 });
    await expect(card.locator('.dry-count'), 'the dry-run count').toBeInViewport({ ratio: 1 });
    await expect(approveOf(card), 'Approve').toBeInViewport({ ratio: 1 });
    await expect(rejectOf(card), 'Reject').toBeInViewport({ ratio: 1 });

    await card.getByRole('button', { name: 'Show details', exact: true }).click();
    await expect(card.locator('app-evidence-panel'), 'Show details brings its panel into view').toBeInViewport();
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A7: another session's request. The page's own context posts an answer to it: 404 not_found, as for a ref that does not exist, and
 * the request stays pending.
 */
test('A7: another session\'s request answers 404 from the page\'s context and stays pending', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const other = await seedOtherSession(`zzother${Date.now().toString(36)}`);
    rows.push(other);
    const theirs = await seedApproval(user, { requiredRole: 'OcuTalonUser', expiresAt: TOMORROW_AT_1413, dryRun: DRY_RUN }, { sessionRef: other });
    rows.push(theirs);
    const missing = unique('missing').replace(/[^A-Za-z0-9]/g, '').slice(0, 22);
    const unknown = await post(page.request, `/ocutalon/api/v1/approvals/${missing}/answer`, { action: 'approve', channel: 'web' });
    expect(unknown.status(), 'control: an unknown ref is 404').toBe(404);
    const response = await post(page.request, `/ocutalon/api/v1/approvals/${theirs}/answer`, { action: 'approve', channel: 'web' });
    expect(response.status(), 'another session\'s request is 404').toBe(404);
    expect(await response.text(), 'with the body of an unknown ref').toBe(await unknown.text());
    expect(JSON.parse(await response.text()).error.code).toBe('not_found');
    expect(await readApproval(theirs).then((one) => one.state), 'and stays pending').toBe('pending');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A8: the replies that are not an answer. Each reply of the answer route is fulfilled by the test: a 500 shows its own message, a
 * 403 its approver sentence, a 404 "That request is no longer available." and a network failure the busy notice at once (not after
 * 10 s). Each time both buttons are restored and the notice is announced once. A fifth press, whose reply the test holds, clears
 * the notice before while its call is out.
 */
test('A8: a reply that is not an answer shows its notice, restores both buttons and is announced', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const errorBody = (code: string, message: string): string => JSON.stringify({ error: { code, message } });
  const replies: Array<{ label: string; reply: (route: Route) => Promise<void>; text: string }> = [
    {
      label: '500',
      reply: (route) => route.fulfill({ status: 500, contentType: 'application/json', body: errorBody('server_error', 'Something went wrong inside OcuTalon. Try again.') }),
      text: 'Something went wrong inside OcuTalon. Try again.',
    },
    {
      label: '403',
      reply: (route) => route.fulfill({ status: 403, contentType: 'application/json', body: errorBody('not_allowed', 'Only an approver for resends can answer this request.') }),
      text: 'Only an approver for resends can answer this request.',
    },
    {
      label: '404',
      reply: (route) => route.fulfill({ status: 404, contentType: 'application/json', body: errorBody('not_found', 'OcuTalon has nothing at this address.') }),
      text: 'That request is no longer available.',
    },
    {
      label: 'network failure',
      reply: (route) => route.abort('failed'),
      text: "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
    },
  ];
  let next = 0;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  try {
    await page.route(ANSWER, async (route: Route) => {
      const one = replies[next++];
      if (one === undefined) {
        await gate;
        await replies[2]!.reply(route).catch(() => undefined);
        return;
      }
      await one.reply(route);
    });
    await open(page);
    const incident = refOf('A8');
    const request = await raise(page, user, rows, incident, []);
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const approve = approveOf(card);
    const reject = rejectOf(card);
    let previous: Locator | undefined;
    for (const one of replies) {
      await approve.click();
      const notice = card.getByText(one.text, { exact: true });
      await expect(notice, `${one.label}: the notice shows`).toBeVisible({ timeout: 5_000 });
      await expect(approve, `${one.label}: Approve is restored`).not.toHaveAttribute('aria-busy', /.*/);
      await expect(reject, `${one.label}: Reject is restored`).not.toHaveAttribute('aria-busy', /.*/);
      await expect(card.locator('.buttons'), `${one.label}: the request is still pending on the page`).toHaveCount(1);
      await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text === one.text).length), { message: `${one.label}: announced once` }).toBe(1);
      previous = notice;
    }
    await approve.click();
    await expect(approve, 'a fifth press is out').toHaveAttribute('aria-busy', 'true');
    await expect(previous!, 'and it cleared the notice before while its call is out').toHaveCount(0);
    release();
    await expect(card.getByText('That request is no longer available.', { exact: true }), 'then its reply shows its own notice').toBeVisible({ timeout: 5_000 });
    expect(await readApproval(request).then((row) => row.state), 'nothing reached the request').toBe('pending');
  } finally {
    release();
    await page.unroute(ANSWER);
    await cleanFixtureRows(rows);
  }
});

/**
 * A9: a closed incident card is compact and draws no request card, even though its request is in the store: the incident-level Show
 * details row comes back.
 */
test('A9: a closed incident draws no request card and keeps its own Show details row', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('A9');
    const requests: string[] = [];
    const request = await raise(page, user, rows, incident, requests);
    const card = incidentCard(page, incident);
    await expect(requestCard(page, request)).toHaveCount(1, { timeout: CARD_MS });
    await applied(page, await publishIncident(user, { ...incidentOf(incident, requests), state: 'closed' }));
    await expect(card.locator('.chip'), 'the incident is closed').toHaveText('Closed', { timeout: CARD_MS });
    await expect(requestCard(page, request), 'the closed card draws no request card').toHaveCount(0, { timeout: CARD_MS });
    await expect(card.locator('.actions').getByRole('button', { name: 'Show details', exact: true }), 'and has its own Show details row').toHaveCount(1);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * A10: the headline cap lets go once the reader scrolls on. At 1280 by 600, as in A6, the newest incident card follows to its
 * headline; after the user's own wheel scrolls the list further, the card's next change follows to the bottom and does not pull
 * the list back up to the headline.
 */
test('A10: after the reader scrolls on with the wheel, the card\'s next change follows to the bottom, not back to the headline', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 600 });
    await changeSnapshot(page, (snapshot) => {
      snapshot['status'] = [];
    });
    await open(page);
    await page.getByRole('button', { name: 'Hide guide', exact: true }).click();
    const incident = refOf('A10');
    const requests: string[] = [];
    const request = await raise(page, user, rows, incident, requests);
    await expect(requestCard(page, request)).toHaveCount(1, { timeout: CARD_MS });
    const card = incidentCard(page, incident);
    await expect(card.getByRole('heading', { level: 3 }), 'control: the list follows to the headline').toBeInViewport({ ratio: 1 });
    const list = page.locator('app-chat-panel .list');
    const gap = (): Promise<number> => list.evaluate((element) => element.scrollHeight - element.clientHeight - element.scrollTop);
    await expect.poll(gap, { message: 'control: and not to its bottom' }).toBeGreaterThan(64);
    const capped = await list.evaluate((element) => element.scrollTop);

    await list.hover();
    await page.mouse.wheel(0, 24);
    await expect.poll(() => list.evaluate((element) => element.scrollTop), { message: 'the wheel scrolls the list on' }).toBeGreaterThan(capped);
    expect(await gap(), 'and not to its bottom').toBeGreaterThan(24);

    await applied(page, await publishIncident(user, { ...incidentOf(incident, requests), count: 53 }));
    await expect(card.locator('p.more'), 'the card changes').toHaveText('3 more since the notice', { timeout: CARD_MS });
    await expect.poll(gap, { message: 'and the list follows to its bottom, not back to the headline' }).toBeLessThanOrEqual(24);
  } finally {
    await cleanFixtureRows(rows);
  }
});
