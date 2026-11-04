import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { STATE, changeSnapshot } from '../support/api';
import { raise, refOf } from '../support/approvals';
import { CARD_MS, composerOf, loadedAfter, mainOf } from '../support/floor';
import { cleanFixtureRows, fixtureUser, irisScript, quoted } from '../support/iris';

/**
 * Story 7.8 (DW-645), the either-way line on the approval request card's dry-run block (E1 to E5), in a real browser against a real
 * stack, as the cards unit's user CARDS. The request is a fixture row whose FixParameters name the source format; the page gets its
 * `approval` payload through BridgeSink, which asks the notice's own rule (Watch.Notice.Reading) for the flag and the reading, so the
 * row on the card is what the server decided. The words are the catalog's: E1 reads the same sentence out of the server's renderer
 * for the with-fix notice.
 * E1 is the many form (50 of 50, 11/04/2026 as month first) with its place in the block, the server's text and the reload's snapshot, E2 the one form
 * (day first), E3 the requests that get no row (a day above 12, the same date both ways, a source format that is not an order format),
 * E4 an answered request, which keeps the row and loses the note (at 1280 by 600 its Before and After share a line below the count line), and E5
 * the layout at 1280 by 600 under the conditions of DESIGN.md's acceptance test, as cards/approval-card.spec.ts A6 sets them (Before and After
 * share a line and the note is on the count line).
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'CARDS';

/** The sentence of the many form, with the reading and the noun of E1's request. */
const MANY = 'All 50 dates are valid whether read month first or day first. Read month first, they match the day each order arrived.';

/** The sentence of the one form, day first. */
const ONE = 'The date is valid whether read month first or day first. Read day first, it matches the day the order arrived.';

/** The run's date (UTC), taken once: the page's clock is fixed at 14:30 UTC on it. */
const DAY = new Date().toISOString().slice(0, 10);

test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(Date.parse(`${DAY}T14:30:00Z`));
});

/** The parameters of a date repair with this source format. */
const parametersOf = (sourceFormat: string): string => JSON.stringify({ sourceFormat, targetFormat: 'YYYY-MM-DD', field: 'OrderDate' });

/** A dry run of the date repair: the count affected and resent, and one example. */
const dryRunOf = (count: number, before: string, after: string): Record<string, unknown> => ({
  affected: count,
  resend: count,
  itemNoun: { one: 'order', other: 'orders' },
  field: 'OrderDate',
  before,
  after,
});

const incidentCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);

/** Signs the cards user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** The top edge and the bottom edge of an element, in page pixels. */
async function edgesOf(target: Locator): Promise<{ top: number; bottom: number }> {
  const box = await target.boundingBox();
  if (box === null) {
    throw new Error('the element has no box');
  }
  return { top: box.y, bottom: box.y + box.height };
}

/** Whether the Before row and the After row of the card's dry-run block share one line, below the count line (and, when `noteBesideCount`, with the note on the count line). */
async function beforeAndAfterShareALine(card: Locator, noteBesideCount: boolean): Promise<void> {
  const head = await edgesOf(card.locator('.dry-head'));
  const [before, after] = [await edgesOf(card.locator('.dry > .dry-row').nth(0)), await edgesOf(card.locator('.dry > .dry-row').nth(1))];
  expect(Math.abs(before.top - after.top), 'Before and After share a line').toBeLessThan(2);
  expect(before.top, 'below the count line').toBeGreaterThanOrEqual(head.bottom - 1);
  if (noteBesideCount) {
    const note = await edgesOf(card.locator('.dry-note'));
    expect(Math.abs(note.top - head.top), 'the note is on the count line').toBeLessThan(2);
  }
}

/** The class names of the children of the dry-run block, in order. */
const partsOf = (card: Locator): Promise<string[]> => card.locator('.dry > *').evaluateAll((elements) => elements.map((one) => one.className));

/**
 * Whether the server's renderer holds the sentence: Catalog.Render of the with-fix either-way key for the phone, with the slots
 * of a dry run of `count` dates read `reading`, contains it.
 */
async function serverHolds(count: number, reading: string, sentence: string): Promise<boolean> {
  const slots = {
    count,
    itemNoun: { one: 'order', other: 'orders' },
    time: `${DAY}T14:12:00Z`,
    cause: 'The partner changed its date format.',
    fixSummary: `repair and resend all ${count}`,
    field: 'OrderDate',
    before: '11/04/2026',
    after: '2026-11-04',
    resendCount: count,
    reading,
    item: 'order',
  };
  const lines = await irisScript(
    [
      `Set t=##class(OcuTalon.Msg.Catalog).Render("incident.withFixEitherWay",${quoted(JSON.stringify(slots))},"phone",.sc)`,
      `Write !,"CHK|holds|",($Find(t,${quoted(sentence)})>0)`,
    ].join('\n'),
  );
  return lines.some((line) => line === 'CHK|holds|1');
}

/** E1: the many form. */
test('E1: the dry-run block shows the either-way sentence between After and Will resend, as the server renders it, and the snapshot after a reload carries its flag', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const incident = refOf('E1');
    const request = await raise(page, user, rows, incident, [], { dryRun: dryRunOf(50, '11/04/2026', '2026-11-04'), fixParameters: parametersOf('MM/DD/YYYY') });
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.dry-either'), 'the row').toHaveText(MANY);
    expect(await partsOf(card), 'between After and Will resend, and the note is still the one dry-note').toEqual(['dry-head', 'dry-row', 'dry-row', 'dry-either', 'dry-row dry-resend', 'dry-note']);
    await expect(card.locator('.dry-either .dry-key'), 'with no label').toHaveCount(0);
    await expect(card.locator('.dry-note')).toHaveText('Nothing has changed yet.');
    expect(await serverHolds(50, 'month first', MANY), "the server's with-fix notice holds the same sentence").toBe(true);

    await page.reload();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    const response = await page.request.get(STATE);
    expect(response.status(), 'the snapshot is served').toBe(200);
    const snapshot = (await response.json()) as { rail: { approvals: Array<{ ref: string; dryRun?: { eitherWay?: boolean; reading?: string } }> } };
    const held = snapshot.rail.approvals.find((one) => one.ref === request);
    expect(held?.dryRun?.eitherWay, 'a reload gets the flag from the snapshot, which the server builds with the same rule').toBe(true);
    expect(held?.dryRun?.reading).toBe('month first');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/** E2: the one form, read day first. */
test('E2: one date to resend reads in the one form, day first', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const request = await raise(page, user, rows, refOf('E2'), [], { dryRun: dryRunOf(1, '03/11/2026', '2026-11-03'), fixParameters: parametersOf('DD/MM/YYYY') });
    const card = requestCard(page, request);
    await expect(card.locator('.dry-either')).toHaveText(ONE, { timeout: CARD_MS });
    expect(await partsOf(card)).toEqual(['dry-head', 'dry-row', 'dry-row', 'dry-either', 'dry-row dry-resend', 'dry-note']);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/** E3: no row. */
test('E3: a day above 12, the same date both ways and a source format that is not an order format get no row', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const cases: Array<{ label: string; before: string; after: string; format: string }> = [
      { label: 'a day above 12', before: '10/16/2026', after: '2026-10-16', format: 'MM/DD/YYYY' },
      { label: 'the same date both ways', before: '11/11/2026', after: '2026-11-11', format: 'MM/DD/YYYY' },
      { label: 'a source format that is not an order format', before: '2026-11-04', after: '20261104', format: 'YYYY-MM-DD' },
    ];
    for (const [index, one] of cases.entries()) {
      const request = await raise(page, user, rows, refOf(`E3${index}`), [], { dryRun: dryRunOf(50, one.before, one.after), fixParameters: parametersOf(one.format) });
      const card = requestCard(page, request);
      await expect(card.locator('.dry'), `${one.label}: the dry-run block is there`).toHaveCount(1, { timeout: CARD_MS });
      await expect(card.locator('.dry-either'), `${one.label}: no row`).toHaveCount(0);
      expect(await partsOf(card), `${one.label}: the block reads as it did`).toEqual(['dry-head', 'dry-row', 'dry-row', 'dry-row dry-resend', 'dry-note']);
    }
  } finally {
    await cleanFixtureRows(rows);
  }
});

/** E4: an answered request keeps the row. */
test('E4: an answered request keeps the row and loses the note', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await open(page);
    const request = await raise(page, user, rows, refOf('E4'), [], {
      dryRun: dryRunOf(50, '11/04/2026', '2026-11-04'),
      fixParameters: parametersOf('MM/DD/YYYY'),
      state: 'rejected',
      answeredAction: 'reject',
      answeredChannel: 'web',
      answeredBy: user,
      answeredAt: `${DAY}T14:15:00Z`,
    });
    const card = requestCard(page, request);
    await expect(card.locator('.dry-either')).toHaveText(MANY, { timeout: CARD_MS });
    await expect(card.locator('.dry-note'), 'the note goes').toHaveCount(0);
    expect(await partsOf(card)).toEqual(['dry-head', 'dry-row', 'dry-row', 'dry-either', 'dry-row dry-resend']);
    await page.setViewportSize({ width: 1280, height: 600 });
    await beforeAndAfterShareALine(card, false);
  } finally {
    await cleanFixtureRows(rows);
  }
});

/**
 * E5: at 1280x600, under A6's conditions (no status banner, the guide collapsed by Hide guide) and with the row showing, the
 * headline, the cause, the dry-run count, Approve and Reject are all in the chat list's view without scrolling.
 */
test('E5: at 1280 by 600 with the row showing the headline, the cause, the dry-run count, Approve and Reject are in view', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 600 });
    await changeSnapshot(page, (snapshot) => {
      snapshot['status'] = [];
    });
    await open(page);
    await page.getByRole('button', { name: 'Hide guide', exact: true }).click();
    const incident = refOf('E5');
    const request = await raise(page, user, rows, incident, [], { dryRun: dryRunOf(50, '11/04/2026', '2026-11-04'), fixParameters: parametersOf('MM/DD/YYYY') });
    const card = requestCard(page, request);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.dry-either'), 'the row shows').toHaveText(MANY);
    const incidentView = incidentCard(page, incident);
    await expect(incidentView.getByRole('heading', { level: 3 }), 'the headline').toBeInViewport({ ratio: 1 });
    await expect(incidentView.locator('p.cause'), 'the cause').toBeInViewport({ ratio: 1 });
    await expect(card.locator('.dry-count'), 'the dry-run count').toBeInViewport({ ratio: 1 });
    await beforeAndAfterShareALine(card, true);
    await expect(card.getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true }), 'Approve').toBeInViewport({ ratio: 1 });
    await expect(card.getByRole('button', { name: 'Reject: repair and resend 50 orders', exact: true }), 'Reject').toBeInViewport({ ratio: 1 });
  } finally {
    await cleanFixtureRows(rows);
  }
});
