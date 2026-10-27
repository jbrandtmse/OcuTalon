import { expect, test, type Locator, type Page } from '@playwright/test';

import { CARD_MS, HEADER, applied, openFloor } from '../support/floor';
import { cleanFixtureRows, fixtureUser, publishIncident, seedApproval, sinkEvent } from '../support/iris';
import { recordAnnouncements, tokenColor } from '../support/page';

/**
 * Story 6.2, the approval request card inside the incident card (A1; the other nine cases, A2 to A10, are in answers/approval-card.spec.ts
 * since Story 6.4), in a real browser against a real stack, as the FLOOR user (the floor stack is in demo mode, its instance zone is UTC and
 * the browser's is UTC and en-GB; the page's clock is fixed at 14:30 UTC on the run's date). An incident card is made as IncidentManager
 * will make it (an `incident` event, publishIncident); a request is a fixture row (seedApproval) whose `approval` event reaches the page
 * through BridgeSink (sinkEvent), with the required role OcuTalonUser that the floor user holds. HH:MM is the row's AnsweredAt, read back
 * through iris, so that the expected text is exact. A case's rows are its own and are removed in finally.
 * A1 is the pending card, and it stays in the floor because it runs in Chromium, Firefox and WebKit (tag @browsers): the floor is the unit
 * that runs a case in all three engines. A2 to A10 moved to the answers unit (DW-315): they run in Chromium only, and the floor unit had
 * come within 13 s of its 540 s deadline.
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'FLOOR';

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
