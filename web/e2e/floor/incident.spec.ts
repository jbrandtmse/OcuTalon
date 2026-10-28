import { expect, test, type Locator, type Page } from '@playwright/test';

import { STATE } from '../support/api';
import { CARD_MS, HEADER, applied, openFloor, unique } from '../support/floor';
import { cleanFixtureRows, fixtureUser, publishIncident, seedDecision } from '../support/iris';
import { announcedTexts, recordAnnouncements, tokenColor } from '../support/page';

/**
 * Story 6.1, the incident card in the chat (I1; the other ten cases, I2 to I11, are in cards/incident-card.spec.ts since Story 6.4), in a
 * real browser against a real stack, as the FLOOR user (the floor stack is in demo mode, its instance zone is UTC and the browser's is UTC
 * and en-GB; the page's clock is fixed at 14:30 UTC on the run's date, the date of every time the spec writes). A card is made as
 * IncidentManager will make it, an `incident` event published through Live.Publish (publishIncident); a case's refs, markers and decisions
 * are its own. The decision a card's footer names is seeded before the page opens, because the page reads decisions from the snapshot. A
 * case that makes rows removes them with cleanFixtureRows in finally.
 * I1 is the full card, and it stays in the floor because it runs in Chromium, Firefox and WebKit (tag @browsers): the floor is the unit that
 * runs a case in all three engines. I2 to I11 moved to the cards unit (DW-315): they run in Chromium only, and the floor unit had
 * come within 13 s of its 540 s deadline.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'FLOOR';

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

/**
 * Signs the floor user in, having recorded what the live region receives, and checks the stack: demo mode on (the Orders trace
 * application is served) and the instance in UTC (the headline's times are written for it), so that a changed stack fails loudly.
 */
async function open(page: Page): Promise<void> {
  await recordAnnouncements(page);
  await openFloor(page);
  const state = (await (await page.request.get(STATE)).json()) as { demoMode: boolean; instanceZone: string };
  expect(state.demoMode, 'the floor stack is in demo mode').toBe(true);
  expect(state.instanceZone, 'and its instance zone is UTC').toMatch(/^(UTC|Etc\/UTC)$/);
}

/** Seeds an act decision of the floor user (what the card's footer strip shows) and records its row; returns its ref. */
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
 * I1: the full awaiting-approval card, with the exact texts of the matrix in order. The bar is 4px in the attention colour, the chip carries
 * its state token, the footer has the chip Act and the diagnosis trace link, and the incident is announced once.
 */
test('I1: an incident event shows one full card, with its texts in order and its footer', { tag: '@browsers' }, async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    const decisionRef = await seedStrip(user, rows, 'I1');
    await open(page);
    const ref = refOf('I1');
    await publish(page, user, payloadOf(ref, decisionRef));

    const card = cardOf(page, ref);
    await expect(card, 'one card for the ref').toHaveCount(1, { timeout: CARD_MS });
    const chip = card.locator('.chip-row .chip');
    const time = card.locator('.chip-row .time');
    const headline = card.getByRole('heading', { level: 3 });
    const cause = card.locator('p.cause');
    const evidence = card.locator('p.evidence-line');
    const fix = card.locator('p.fix');
    const details = card.getByRole('button', { name: 'Show details' });
    const footer = card.locator('.footer');
    await expect(chip).toHaveText('Awaiting approval');
    await expect(time, "the time of the last failure, in the browser zone (the instance's)").toHaveText('14:13');
    await expect(headline, 'the headline has no final period').toHaveText('50 orders failed since 14:12');
    await expect(cause).toHaveText('The partner changed its date format.');
    await expect(evidence).toHaveText('Data format change \u00B7 order date \u00B7 50 failures grouped into this incident');
    await expect(fix, 'the fix has no Approve?').toHaveText('I can repair and resend all 50.');
    await expect(card.locator('p.more'), 'no more line').toHaveCount(0);
    await expect(card.locator('p.fixing'), 'no fixing line').toHaveCount(0);
    await expect(details).toHaveAttribute('aria-expanded', 'false');
    await inOrder([chip, headline, cause, evidence, fix, details, footer], 'top to bottom');

    await expectBar(page, card, '--attention', 'awaiting approval');
    await expect(chip, 'the chip has its state token').toHaveCSS('background-color', await tokenColor(page, '--incident-state-awaiting-approval-background'));
    await expect(chip).toHaveCSS('color', await tokenColor(page, '--incident-state-awaiting-approval-foreground'));
    await expect(card, 'the card is named by its headline').toHaveAccessibleName('50 orders failed since 14:12');

    await expect(footer.locator('app-outcome-chip'), "the footer's strip has the chip Act").toHaveText('Act');
    const trace = footer.locator('a[href*="/ocutalon/trace/ocutalon/"]');
    await expect(trace, 'and the diagnosis trace link').toHaveCount(1);
    await expect(trace).toHaveAttribute('href', `/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=${HEADER}`);
    await expect(footer.locator('.line1 .item'), "the strip shows the decision's confidence and its own cost").toHaveText(['Confidence 0.94', '$0.0006']);
    await expect(footer.locator('.reason'), 'and the first line of its reasons only (the card is not the newest strip)').toHaveText(['zz first reason.']);
    await expect(footer.getByRole('button', { name: 'Decision details' }), 'with its Details button').toBeVisible();

    await heard(page, [`Incident: ${headlineOf(50)}. Approval needed.`]);
  } finally {
    await cleanFixtureRows(rows);
  }
});
