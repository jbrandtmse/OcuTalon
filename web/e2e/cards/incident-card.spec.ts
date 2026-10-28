import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { STATE, changeSnapshot } from '../support/api';
import { dropPhone } from '../support/devices';
import { CARD_MS, HEADER, applied, composerOf, mainOf, unique } from '../support/floor';
import { cleanFixtureRows, fixtureUser, publishIncident, seedDecision, seedIncident, sendNotification } from '../support/iris';
import { announcedTexts, fromBottom, recordAnnouncements, scrollListTo, tokenColor } from '../support/page';

/**
 * Story 6.1, the incident card in the chat (I2 to I11; I1 is in floor/incident.spec.ts, which runs it in three engines), moved here by
 * Story 6.4 (DW-315), in a real browser against a real stack, as the cards unit's user CARDS (OCUTALON_CARDS_USER; the stack is in demo
 * mode, its instance zone is UTC and the browser's is UTC and en-GB unless a case says otherwise; the page's clock is fixed at 14:30 UTC
 * on the run's date, the date of every time the spec writes). A card is made as IncidentManager will make it, an `incident` event
 * published through Live.Publish (publishIncident), or, for the snapshot, as a row (seedIncident); a case's refs, markers and decisions
 * are its own. The decision a card's footer names is seeded before the page opens, because the page reads decisions from the snapshot. A
 * case that makes rows removes them with cleanFixtureRows in finally. Published events stay on the stream, but a fresh page load replays
 * none of them.
 * I2 is the same ref through its states and a new ref after closing, I3 Show details, I4 the snapshot (a noticed row has a card, an
 * unnoticed one has none, nothing is announced), I5 the incident-kind notifications (no notice card), I6 the browser zone (Europe/Berlin),
 * I7 the focus when the card compacts and I8 the open variants, I9 the online demo (the headline's time ends " ET", in the card and in the
 * announcement) and I10 New messages (a card that lands while the list is scrolled up is focused by the press) and I11 the texts (markup in
 * them is shown as text).
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'CARDS';

/** How long a case looks on after the announcements it expects: longer than the 1 s between two texts, so a second one would show. */
const SETTLE_MS = 3000;

/** The run's date (UTC), taken once, so that every time of the spec and the page's clock are on the same date. */
const DAY = new Date().toISOString().slice(0, 10);

/** The run's date with the time given, as a UTC ISO time. */
const today = (time: string): string => `${DAY}T${time}Z`;

const FIRST = today('14:12:00');
const LAST = today('14:13:00');

/**
 * The page's clock in every case: 14:30 UTC on the run's date (15:30 or 16:30 in Europe/Berlin, the same date), so that the day words
 * of the headline and of the top time do not depend on the hour the spec runs at.
 */
test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(Date.parse(today('14:30:00')));
});

/** A ref of this case's own: at most 22 characters, letters and digits. */
const refOf = (label: string): string => `zz${label}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

/** The headline of the full card, as the page writes it for FIRST in the instance zone. */
const headlineOf = (count: number): string => `${count} orders failed since 14:12`;

/** The incident payload of the matrix's first row, with every part; `over` changes fields. */
function payloadOf(ref: string, decisionRef: string | undefined, over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ref,
    state: 'awaiting_approval',
    count: 50,
    noticeCount: 50,
    firstAt: FIRST,
    lastAt: LAST,
    itemNoun: { one: 'order', other: 'orders' },
    cause: 'The partner changed its date format.',
    fixSummary: 'repair and resend all 50',
    causeCategory: 'data_format_change',
    element: 'order date',
    ...(decisionRef === undefined ? {} : { decisionRef }),
    requests: [{ ref: `${ref}r`, state: 'pending' }],
    evidence: {
      sampleHeaderId: 1047,
      sampleError: 'zz Could not parse OrderDate',
      items: [{ itemName: 'Order transform', count: 50, firstAt: today('14:12:03'), lastAt: today('14:12:31') }],
    },
    traceTargets: {
      diagnosis: { traceHeaderId: HEADER, traceNamespace: 'OCUTALON' },
      sample: { traceHeaderId: 4243, traceNamespace: 'OCUORDERS' },
      firstFailure: { traceHeaderId: 4244, traceNamespace: 'OCUORDERS' },
    },
    ...over,
  };
}

/** The card of a ref in the chat. */
const cardOf = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);

/** Every incident card of the chat. */
const cards = (page: Page): Locator => page.locator('app-chat-panel [data-part="incident"]');

/**
 * Signs the cards user in, having recorded what the live region receives, and checks the stack: demo mode on (the Orders trace
 * application is served) and the instance in UTC (the headline's times are written for it), so that a changed stack fails loudly.
 */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await recordAnnouncements(page);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
  const state = (await (await page.request.get(STATE)).json()) as { demoMode: boolean; instanceZone: string };
  expect(state.demoMode, 'the stack is in demo mode').toBe(true);
  expect(state.instanceZone, 'and its instance zone is UTC').toMatch(/^(UTC|Etc\/UTC)$/);
}

/** Seeds an act decision of the cards user (what the card's footer strip shows) and records its row; returns its ref. */
async function seedStrip(user: string, rows: string[], label: string): Promise<string> {
  const ref = await seedDecision(user, { outcome: 'act', summary: unique(label), reasons: 'zz first reason.\nzz second reason.', confidence: 0.94, costUSD: 0.0006 });
  rows.push(ref);
  return ref;
}

/** Publishes an incident and waits for the page to apply it. */
async function publish(page: Page, user: string, payload: Record<string, unknown>): Promise<void> {
  await applied(page, await publishIncident(user, payload));
}

/** Expects the live region to have received exactly these texts, in order, and nothing else later. */
async function heard(page: Page, expected: string[]): Promise<void> {
  await expect.poll(() => announcedTexts(page), { message: 'the page announces what it should', timeout: CARD_MS }).toEqual(expected);
  await page.waitForTimeout(SETTLE_MS);
  expect(await announcedTexts(page), 'and nothing else, also later').toEqual(expected);
}

/** Expects the elements to stand one under the other, in this order. */
async function inOrder(elements: Locator[], what: string): Promise<void> {
  let last = -1;
  for (const [i, element] of elements.entries()) {
    const box = await element.boundingBox();
    expect(box, `${what}: element ${i} is laid out`).not.toBeNull();
    expect(box!.y, `${what}: element ${i} stands below the one before`).toBeGreaterThan(last);
    last = box!.y;
  }
}

/** The 4px bar of a card: its width and colour. */
async function expectBar(page: Page, card: Locator, token: string, what: string): Promise<void> {
  await expect(card, `${what}: the bar is 4px`).toHaveCSS('border-left-width', '4px');
  await expect(card, `${what}: and in ${token}`).toHaveCSS('border-left-color', await tokenColor(page, token));
}
/**
 * I2: the same ref goes to count 52 and fixing, a count-only change, resolved and closed: one card throughout, with its bar, its lines,
 * its compaction and one announcement per change of state and none for the count. Then a new ref gives a second card, which is announced.
 * Its requests carry no result (since Story 6.4 a result is a band and is announced too; close-loop.spec.ts C1 to C3 and C9 cover that).
 */
test('I2: one card per ref, updated in place through its states, and a new ref after closing gives a second card', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    const decisionRef = await seedStrip(user, rows, 'I2');
    await open(page);
    const base = await cards(page).count();
    const ref = refOf('I2');
    const card = cardOf(page, ref);
    const headline = card.getByRole('heading', { level: 3 });
    const chip = card.locator('.chip-row .chip');

    await publish(page, user, payloadOf(ref, decisionRef));
    await expect(headline).toHaveText(headlineOf(50), { timeout: CARD_MS });
    await expectBar(page, card, '--attention', 'awaiting approval');
    const said = [`Incident: ${headlineOf(50)}. Approval needed.`];
    await heard(page, said);

    await publish(page, user, payloadOf(ref, decisionRef, { count: 52, state: 'fixing', requests: [{ ref: `${ref}r`, state: 'executing' }] }));
    await expect(headline, 'the second payload shows').toHaveText(headlineOf(52), { timeout: CARD_MS });
    await expect(cardOf(page, ref), 'still exactly one card for the ref').toHaveCount(1);
    await expect(cards(page), 'and no other card').toHaveCount(base + 1);
    await expect(card.locator('p.more')).toHaveText('2 more since the notice');
    await expect(chip).toHaveText('Fixing');
    await expect(chip).toHaveCSS('background-color', await tokenColor(page, '--incident-state-fixing-background'));
    await expect(card.locator('p.fixing')).toHaveText('Repairing and resending 50 orders\u2026');
    await expectBar(page, card, '--info-ink', 'fixing');
    said.push(`Incident: ${headlineOf(52)}. Fixing.`);
    await heard(page, said);

    await publish(page, user, payloadOf(ref, decisionRef, { count: 53, state: 'fixing', requests: [{ ref: `${ref}r`, state: 'executing' }] }));
    await expect(headline, 'a count-only change shows').toHaveText(headlineOf(53), { timeout: CARD_MS });
    await expect(card.locator('p.more')).toHaveText('3 more since the notice');
    await heard(page, said);

    await publish(page, user, payloadOf(ref, decisionRef, { count: 53, state: 'resolved', requests: [{ ref: `${ref}r`, state: 'executed' }] }));
    await expect(chip).toHaveText('Resolved', { timeout: CARD_MS });
    await expectBar(page, card, '--success-ink', 'resolved');
    await expect(card.locator('p.fixing'), 'the fixing line is gone').toHaveCount(0);
    said.push(`Incident: ${headlineOf(53)}. Resolved.`);
    await heard(page, said);

    await publish(page, user, payloadOf(ref, decisionRef, { count: 53, state: 'closed', requests: [{ ref: `${ref}r`, state: 'executed' }] }));
    await expect(chip).toHaveText('Closed', { timeout: CARD_MS });
    await expectBar(page, card, '--border-strong', 'closed');
    for (const gone of ['p.cause', 'p.evidence-line', 'p.fix', 'p.more', 'p.fixing', '.footer']) {
      await expect(card.locator(gone), `closed: ${gone} is gone`).toHaveCount(0);
    }
    await expect(headline, 'closed: the headline stays').toBeVisible();
    await expect(card.getByRole('button', { name: 'Show details' }), 'and Show details').toBeVisible();
    said.push(`Incident: ${headlineOf(53)}. Closed.`);
    await heard(page, said);

    const next = refOf('I2b');
    await publish(page, user, payloadOf(next, decisionRef, { count: 4 }));
    await expect(cardOf(page, next), 'a new ref gives a new card').toHaveCount(1, { timeout: CARD_MS });
    await expect(cards(page), 'and the closed one stays, compacted').toHaveCount(base + 2);
    await expect(cardOf(page, ref).locator('p.cause')).toHaveCount(0);
    await expect(cardOf(page, next).locator('p.cause')).toHaveCount(1);
    said.push(`Incident: ${headlineOf(4)}. Approval needed.`);
    await heard(page, said);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * I3: Show details. aria-expanded turns true and the panel opens inline right below the Show details row, with the rows of the matrix, the
 * raw values in mono-sm and the two trace links into the Orders trace application; the held note shows with a pending request and not
 * without one; the panel stays open when the card updates; a second press closes it. A card with no row for the panel has no Show details.
 */
test('I3: Show details opens the evidence panel inline, with its rows, mono values and trace links, and closes again', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  await open(page);
  const ref = refOf('I3');
  await publish(page, user, payloadOf(ref, undefined));
  const card = cardOf(page, ref);
  const details = card.getByRole('button', { name: 'Show details' });
  await expect(details).toBeVisible({ timeout: CARD_MS });
  await expect(details).toHaveAttribute('aria-expanded', 'false');
  await expect(card.locator('app-evidence-panel'), 'closed: no panel').toHaveCount(0);

  await details.click();
  await expect(details).toHaveAttribute('aria-expanded', 'true');
  const panel = card.locator('.actions + .panel > app-evidence-panel');
  await expect(panel, 'the panel is the next sibling of the Show details row').toBeVisible();
  await expect(details).toHaveAttribute('aria-controls', (await card.locator('.actions + .panel').getAttribute('id'))!);
  const labels = panel.locator('.label');
  await expect(labels).toHaveText(['Cause', 'Sample failed message', 'Error', 'Failures by item']);
  await expect(panel.locator('.value').nth(0), 'the cause in the UI font').toHaveText('Data format change \u00B7 order date');
  await expect(panel.locator('.value').nth(0), 'the cause is not mono').not.toHaveClass(/mono/);
  const mono = panel.locator('.value.mono');
  await expect(mono).toHaveText(['1047', 'zz Could not parse OrderDate', 'Order transform: 50 failures, first 14:12, last 14:12']);
  for (const [i, value] of (await mono.all()).entries()) {
    await expect(value, `mono value ${i} is in mono-sm`).toHaveCSS('font-size', '12px');
    expect(await value.evaluate((el) => getComputedStyle(el).fontFamily), `mono value ${i} is in the mono face`).toMatch(/mono/i);
  }
  await expect(panel.locator('.held'), 'a pending request: held as a task').toHaveText('Held as an IRIS Workflow task until someone answers.');
  await expect(panel.getByRole('link', { name: /^Sample message/ })).toHaveAttribute('href', '/ocutalon/trace/ocuorders/EnsPortal.VisualTrace.zen?SESSIONID=4243');
  await expect(panel.getByRole('link', { name: /^First failure/ })).toHaveAttribute('href', '/ocutalon/trace/ocuorders/EnsPortal.VisualTrace.zen?SESSIONID=4244');
  await inOrder([details, labels.first(), card.locator('.footer')], 'the panel is below the row and above the footer');
  await expect(card.locator('.footer app-decision-strip'), 'no decision in the store: no strip').toHaveCount(0);
  await expect(card.locator('.footer a'), 'the footer is the diagnosis trace link alone').toHaveAttribute(
    'href',
    `/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=${HEADER}`,
  );

  await publish(page, user, payloadOf(ref, undefined, { count: 51 }));
  await expect(card.getByRole('heading', { level: 3 })).toHaveText(headlineOf(51), { timeout: CARD_MS });
  await expect(details, 'the panel stays open across an update').toHaveAttribute('aria-expanded', 'true');
  await expect(panel).toBeVisible();

  await details.click();
  await expect(details).toHaveAttribute('aria-expanded', 'false');
  await expect(card.locator('app-evidence-panel'), 'a second press closes it').toHaveCount(0);

  const answered = refOf('I3b');
  await publish(page, user, payloadOf(answered, undefined, { state: 'fixing', requests: [{ ref: `${answered}r`, state: 'executing', result: { total: 50 } }] }));
  const other = cardOf(page, answered);
  await other.getByRole('button', { name: 'Show details' }).click({ timeout: CARD_MS });
  await expect(other.locator('app-evidence-panel')).toBeVisible();
  await expect(other.locator('.held'), 'no pending request: no held note').toHaveCount(0);
  await expect(other.locator('app-evidence-panel .label')).toHaveText(['Cause', 'Sample failed message', 'Error', 'Failures by item']);

  const bare = refOf('I3c');
  await publish(page, user, { ref: bare, state: 'open', count: 2, noticeCount: 2, firstAt: FIRST, lastAt: LAST, cause: 'zz bare cause' });
  await expect(cardOf(page, bare), 'a payload without parts still renders').toHaveCount(1, { timeout: CARD_MS });
  await expect(cardOf(page, bare).getByRole('button', { name: 'Show details' }), 'with no row for the panel there is no Show details').toHaveCount(0);
});

/**
 * I4: the snapshot. A noticed incident row of the session has a card, built from its row fields (no parts); an unnoticed one has none;
 * and nothing is announced at the load.
 */
test('I4: the page loads one card for the noticed row only, and announces nothing', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    const noticed = await seedIncident(user);
    rows.push(noticed);
    const unnoticed = await seedIncident(user, { noticedAt: '' });
    rows.push(unnoticed);
    await open(page);
    const card = cardOf(page, noticed);
    await expect(card, 'the noticed row has a card').toHaveCount(1, { timeout: CARD_MS });
    await expect(cardOf(page, unnoticed), 'the unnoticed row has none').toHaveCount(0);
    await expect(card.locator('.chip-row .chip')).toHaveText('Open');
    await expect(card.getByRole('heading', { level: 3 })).toHaveText('3 messages failed since Jan 1, 2030 at 09:00');
    await expect(card.locator('p.cause')).toHaveText('zz cause.');
    await expect(card.locator('p.fix'), 'no parts: no fix, no footer').toHaveCount(0);
    await expect(card.locator('.footer')).toHaveCount(0);
    await expect(card.locator('app-evidence-panel')).toHaveCount(0);
    await page.waitForTimeout(SETTLE_MS);
    expect(await announcedTexts(page), 'nothing is announced at the load').toEqual([]);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * I5: a notification of each incident kind (incident, approval, answered, result) for the session, through Notify, makes no notice card
 * in the chat; a tell-now sent after them shows its card. (The Delivery rows are pinned by Test.Core.WebChatOut.)
 */
test('I5: the incident-kind notifications make no notice card, and a tell-now after them does', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  // The notifications record Delivery rows (and the tell-now a phone message) of the shared session: the case removes what it made
  // (dropPhone), so that the later specs do not open a chat with this tell-now card in it.
  const start = new Date(Date.now() - 2000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  try {
    await open(page);
    const notices = page.locator('app-chat-panel app-notice-card');
    const before = await notices.count();
    const incidentsBefore = await cards(page).count();
    for (const [kind, catalogKey] of [
      ['incident', 'incident.fallback'],
      ['approval', 'incident.laterRequest'],
      ['answered', 'zz.answered'],
      ['result', 'result.allThrough'],
    ] as const) {
      await sendNotification(user, { kind, catalogKey, slots: {}, approvalRef: refOf('I5') });
    }
    const marker = unique('I5');
    await sendNotification(user, { kind: 'tellnow', catalogKey: 'notice.tellNow', slots: { whatHappened: marker, reason: 'zz I5 reason' } });
    await expect(notices.filter({ hasText: marker }), 'the tell-now shows its card').toHaveCount(1, { timeout: CARD_MS });
    await page.waitForTimeout(SETTLE_MS);
    await expect(notices, 'and no other notice card came').toHaveCount(before + 1);
    await expect(cards(page), 'nor an incident card').toHaveCount(incidentsBefore);
  } finally {
    await dropPhone(user, start);
  }
});

test.describe('I6', () => {
  test.use({ timezoneId: 'Europe/Berlin' });

  /** I6: in Europe/Berlin (the stack is in UTC) the top time ends with the zone's short name and the headline's time does not. */
  test('I6: the top time names the browser zone and the headline time does not', async ({ page }) => {
    const { user } = fixtureUser(KIND);
    await open(page);
    const ref = refOf('I6');
    await publish(page, user, payloadOf(ref, undefined));
    const card = cardOf(page, ref);
    const time = card.locator('.chip-row .time');
    await expect(time, "the top time is the browser's clock with its zone's name").toHaveText(/^1[5-6]:13 CES?T$/, { timeout: CARD_MS });
    await expect(card.getByRole('heading', { level: 3 }), "the headline is the instance's time, with no zone name").toHaveText(headlineOf(50));
  });
});

/**
 * I7: focus on the footer's Details button; when the incident closes and the card compacts, the button is gone and focus moves to the
 * card itself through the focus rule, not to the main region.
 */
test('I7: when the card compacts, focus moves from the removed footer button to the card', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    const decisionRef = await seedStrip(user, rows, 'I7');
    await open(page);
    const ref = refOf('I7');
    await publish(page, user, payloadOf(ref, decisionRef));
    const card = cardOf(page, ref);
    const button = card.locator('.footer').getByRole('button', { name: 'Decision details' });
    await expect(button).toBeVisible({ timeout: CARD_MS });
    await button.focus();
    await expect(button).toBeFocused();

    await publish(page, user, payloadOf(ref, decisionRef, { state: 'closed' }));
    await expect(card.locator('.chip-row .chip')).toHaveText('Closed', { timeout: CARD_MS });
    await expect(card.locator('.footer'), 'the footer is gone').toHaveCount(0);
    await expect(card, 'focus is on the card').toBeFocused();
  } finally {
    await cleanFixtureRows(rows);
  }
});

/** One open variant of I8: the payload's own fields and the text its first sight is announced with. */
interface Variant {
  label: string;
  count: number;
  over: Record<string, unknown>;
  fallback: boolean;
  text: string;
}

/**
 * I8: the open variants rejected, expired, no_fix and fallback: the attention bar and the Open chip on all, the Fallback flag and no
 * evidence line on the fallback card, and "No fix proposed." at first sight of the no-fix and the fallback (the others say Open).
 */
test('I8: the open variants keep the attention bar, and a fallback or no-fix incident is announced as having no fix', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  await open(page);
  const variants: Variant[] = [
    { label: 'I8a', count: 11, over: { openVariant: 'rejected' }, fallback: false, text: 'Open.' },
    { label: 'I8b', count: 12, over: { openVariant: 'expired' }, fallback: false, text: 'Open.' },
    { label: 'I8c', count: 13, over: { openVariant: 'no_fix', fixSummary: '' }, fallback: false, text: 'No fix proposed.' },
    {
      label: 'I8d',
      count: 14,
      over: { openVariant: 'fallback', fallback: true, fallbackReason: 'no_key', fixSummary: '', cause: '', causeCategory: '', element: '' },
      fallback: true,
      text: 'No fix proposed.',
    },
  ];
  const said: string[] = [];
  for (const variant of variants) {
    const ref = refOf(variant.label);
    await publish(page, user, payloadOf(ref, undefined, { state: 'open', count: variant.count, noticeCount: variant.count, requests: [], ...variant.over }));
    const card = cardOf(page, ref);
    await expect(card, `${variant.label}: the card`).toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.chip-row .chip'), `${variant.label}: the Open chip`).toHaveText('Open');
    await expectBar(page, card, '--attention', variant.label);
    if (variant.fallback) {
      await expect(card.locator('.chip-row app-fallback-flag'), `${variant.label}: the Fallback flag`).toHaveText('Fallback');
      await expect(card.locator('p.evidence-line'), `${variant.label}: no evidence line`).toHaveCount(0);
    } else {
      await expect(card.locator('app-fallback-flag'), `${variant.label}: no Fallback flag`).toHaveCount(0);
    }
    said.push(`Incident: ${headlineOf(variant.count)}. ${variant.text}`);
    await expect.poll(() => announcedTexts(page), { message: `${variant.label} is announced`, timeout: CARD_MS }).toEqual(said);
  }
  await heard(page, said);
});

/**
 * I9: when the snapshot says the instance is the online demo, the headline's time ends " ET" (message text, UX-DR123), in the card and in the
 * announcement, while the top time stays a page time.
 */
test('I9: on the online demo the headline time ends ET, in the card and in its announcement', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  await changeSnapshot(page, (snapshot) => {
    snapshot['onlineDemo'] = true;
  });
  await open(page);
  const ref = refOf('I9');
  await publish(page, user, payloadOf(ref, undefined));
  const card = cardOf(page, ref);
  const headline = `50 orders failed since 14:12 ET`;
  await expect(card.getByRole('heading', { level: 3 }), 'the headline names the online demo time').toHaveText(headline, { timeout: CARD_MS });
  await expect(card.locator('.chip-row .time'), 'the top time is a page time, with no ET').toHaveText('14:13');
  await heard(page, [`Incident: ${headline}. Approval needed.`]);
});

/**
 * I10: scrolled up, an incident card that lands shows New messages and changes nothing about the list; the press takes the list to the
 * bottom and focuses the card (the way a notice card does, notice.spec N12).
 */
test('I10: scrolled up, an incident card that lands shows New messages and the press focuses it', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  await open(page);
  for (let i = 0; i < 6; i += 1) {
    await publish(page, user, payloadOf(refOf(`I10${i}`), undefined));
  }
  await expect(cards(page).nth(5), 'six cards are in the chat').toBeVisible({ timeout: CARD_MS });
  const list = page.locator('app-chat-panel > .list');
  expect(await list.evaluate((el) => el.scrollHeight > el.clientHeight + 100), 'the cards make the list scroll').toBe(true);
  await scrollListTo(list, 'top');
  const button = page.getByRole('button', { name: 'New messages' });
  await expect(button, 'nothing new yet').toHaveCount(0);

  const ref = refOf('I10n');
  await publish(page, user, payloadOf(ref, undefined));
  const card = cardOf(page, ref);
  await expect(card, 'the card landed').toHaveCount(1, { timeout: CARD_MS });
  await expect(button, 'the card that landed while the list is scrolled up shows New messages').toBeVisible();
  expect(await list.evaluate((el) => el.scrollTop), 'the list did not move').toBe(0);

  await button.click();
  await expect.poll(() => fromBottom(list), { message: 'pressing it puts the list at the bottom' }).toBeLessThanOrEqual(24);
  await expect(card, 'and focuses the card').toBeFocused();
  await expect(button, 'and the button is gone').toHaveCount(0);
});

/**
 * I11 (QA): text that a model or IRIS wrote is shown as text, never as markup (AD-13): markup in the cause, the fix, the element, the
 * sample error and an item name appears character for character in the card and in the open panel, and makes no element in either.
 */
test('I11: markup in the incident texts is shown as text in the card and in its panel', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  await open(page);
  const markup = (what: string): string => `<b>zz ${what}</b><img src=x>`;
  const ref = refOf('I11');
  await publish(
    page,
    user,
    payloadOf(ref, undefined, {
      cause: markup('cause'),
      fixSummary: markup('fix'),
      element: markup('element'),
      evidence: {
        sampleHeaderId: 1047,
        sampleError: markup('error'),
        items: [{ itemName: markup('item'), count: 2, firstAt: today('14:12:03'), lastAt: today('14:12:31') }],
      },
    }),
  );
  const card = cardOf(page, ref);
  await expect(card.locator('p.cause'), 'the cause is text').toHaveText(`${markup('cause')}.`, { timeout: CARD_MS });
  await expect(card.locator('p.fix'), 'the fix is text').toHaveText(`I can ${markup('fix')}.`);
  await expect(card.locator('p.evidence-line'), 'the element is text').toContainText(markup('element'));
  await card.getByRole('button', { name: 'Show details' }).click();
  const panel = card.locator('app-evidence-panel');
  await expect(panel.locator('.value.mono').nth(1), 'the error is text').toHaveText(markup('error'));
  await expect(panel.locator('.value.mono').nth(2), 'and the item name').toContainText(markup('item'));
  expect(await card.locator('b, img').count(), 'no element came out of any of them').toBe(0);
});
