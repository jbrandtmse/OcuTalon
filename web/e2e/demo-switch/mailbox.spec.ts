import { expect, test, type Locator, type Page } from '@playwright/test';

import { STATE, changeSnapshot, post } from '../support/api';
import {
  MAILBOX_TAB,
  decisionRowsOf as decisionRows,
  dropMail,
  dropPhone,
  mailOutcome,
  mailRows,
  mailRowsOf as rowsOf,
  mailboxOf,
  pointKeys,
  publishFixtureEvent,
  publishMailbox,
  restoreKeys,
  sampleChipOf as chipOf,
  turnRows,
} from '../support/devices';
import { announcedTexts, announcements, recordAnnouncements, tokenColor } from '../support/page';
import { README_ACCOUNT } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';

/**
 * The simulated mailbox follows the demo mode of the stack (Story 4.6, matrix rows 8 to 14 and 17, on a real switch). The README account
 * signs in. With demo mode on (OCUTALON_E2E_DEMO_MODE=1) Decide answers from the CI mock (beforeAll points the runners at its key, afterAll
 * puts them back), and MB1 to MB5 hold the mailbox: its empty tab, a sample chip, the compose form, the outcomes that the mock's marker
 * scenarios pick, and untrusted markup shown as text. With demo mode off MB6 holds that there is no region, both routes answer
 * 404 not_found and no SimMessage row is made. Every assertion is relative to what the README session held before the case, and each case
 * removes what it made in finally (dropPhone: the SimMessage rows of every kind, and the phone and web Delivery rows), because
 * test-demo-switch.sh holds the README chat equal to the one it recorded at the start in the /state answers of its steps 5 and 8.
 */
function stackMode(): '0' | '1' {
  const mode = process.env['OCUTALON_E2E_DEMO_MODE'];
  if (mode !== '0' && mode !== '1') {
    throw new Error('OCUTALON_E2E_DEMO_MODE must be 1 (demo mode on) or 0 (demo mode off)');
  }
  return mode;
}

const USER = README_ACCOUNT.user;
const INCOMING = '/ocutalon/api/v1/mailbox/incoming';
const SAMPLE = '/ocutalon/api/v1/mailbox/samples/newsletter';

test.describe.configure({ timeout: 120_000 });

test.beforeAll(async () => {
  if (stackMode() === '1') {
    test.setTimeout(240_000);
    await pointKeys();
  }
});

test.afterAll(async () => {
  if (stackMode() === '1') {
    test.setTimeout(240_000);
    await restoreKeys();
  }
});

/** A stamp that no other case or run shares. */
const stampOf = (): string => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** The UTC time to the second, a little before now, as dropPhone wants it. */
const startTime = (): string => new Date(Date.now() - 2000).toISOString().replace(/\.\d{3}Z$/, 'Z');

/** Signs in, waits for the snapshot and selects the mailbox tab; the result is the mailbox. */
async function openMailbox(page: Page): Promise<Locator> {
  await recordAnnouncements(page);
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  return mailboxOf(page);
}

const simulateOf = (mailbox: Locator): Locator => mailbox.getByRole('button', { name: 'Simulate an incoming email', exact: true });
const formOf = (mailbox: Locator): Locator => mailbox.locator('.form');

/** Opens the compose form and sends the email through it; the list returns with the new row. */
async function compose(mailbox: Locator, from: string, subject: string, body: string): Promise<void> {
  await simulateOf(mailbox).click();
  await mailbox.getByRole('textbox', { name: 'From', exact: true }).fill(from);
  await mailbox.getByRole('textbox', { name: 'Subject', exact: true }).fill(subject);
  await mailbox.getByRole('textbox', { name: 'Body', exact: true }).fill(body);
  await formOf(mailbox).getByRole('button', { name: 'Send', exact: true }).click();
}

/** The phone's messages that hold the text. */
const phoneMessages = (page: Page, text: string): Locator => page.locator('app-simulated-phone .notification').filter({ hasText: text });

/** The cards of the web chat that hold the text. */
const cards = (page: Page, text: string): Locator => page.locator('app-chat-panel app-notice-card').filter({ hasText: text });

test('MB1: the empty mailbox tab has its header, the three chips with their caption and the secondary button', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  await dropMail(USER);
  const mailbox = await openMailbox(page);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await page.getByRole('region', { name: 'Simulated devices' }).getByRole('tab', { name: MAILBOX_TAB }).click();
  const panel = page.locator('#device-panel-mailbox');
  await expect(panel.locator('.mailbox-title'), 'the header').toHaveText('Simulated mailbox');
  await expect(panel.locator('app-simulated-label'), 'and the Simulated label').toBeVisible();
  await expect(mailbox.locator('.empty'), 'no email: the empty text').toHaveText('No emails yet. Simulate an incoming email, or send a sample.');
  for (const label of ['Sample: newsletter', 'Sample: partner notice', 'Sample: suspicious request']) {
    await expect(chipOf(mailbox, label), `${label} is a chip with the longer name`).toBeVisible();
    await expect(chipOf(mailbox, label).locator('app-icon'), 'and the mail icon').toHaveCount(1);
  }
  await expect(mailbox.locator('.caption'), 'the caption never promises an outcome').toHaveText('Send one and see what OcuTalon decides.');
  await expect(simulateOf(mailbox), 'the secondary button').toHaveClass(/button-secondary/);
  await expect(panel, 'the panel is no tab stop').not.toHaveAttribute('tabindex', /.*/);
});

test('MB2: a sample chip keeps focus and delivers a row that is decided live, opens in place, and is read for good', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const start = startTime();
  await dropMail(USER);
  try {
    const mailbox = await openMailbox(page);
    const chip = chipOf(mailbox, 'Sample: partner notice');
    await chip.click();
    await expect(chip, 'focus stays on the chip').toBeFocused();
    const row = rowsOf(mailbox, 'Certificate change on Friday');
    await expect(row, 'the row is in the list').toHaveCount(1, { timeout: 30_000 });
    await expect(row.locator('.visually-hidden'), 'unread, for assistive technology').toHaveText('Unread');
    await expect(row.locator('.from'), 'the sender is its display name').toContainText('Results Partner IT');
    await expect(row.locator('.from'), 'without the address').not.toContainText('it@results-partner.example');
    await expect(row.locator('.time'), 'with a time').toHaveText(/\d{1,2}:\d{2}/);
    await expect(row.locator('app-outcome-chip'), 'decided live by the mock: Digest').toHaveText('Digest', { timeout: 60_000 });
    await expect
      .poll(() => announcements(page, "Email 'Certificate change on Friday': Digest"), { message: 'the decision is announced once' })
      .toBe(1);
    await page.waitForTimeout(1500);
    expect(await announcements(page, "Email 'Certificate change on Friday': Digest"), 'and not again').toBe(1);
    await expect(chip, 'focus stays on the chip after the row arrived and was decided').toBeFocused();
    expect(await mailRows(USER), 'one row on the server').toBe(1);

    await row.click();
    const heading = mailbox.getByRole('heading', { level: 3, name: 'Certificate change on Friday' });
    await expect(heading, 'the email opens in place with focus on its subject').toBeFocused();
    await expect(heading).toHaveAttribute('tabindex', '-1');
    await expect(mailbox.locator('.meta'), 'the full From').toContainText('Results Partner IT <it@results-partner.example>');
    await expect(mailbox.locator('.text'), 'the exact body').toHaveText(
      'Hello, the TLS certificate on our results endpoint changes this Friday at 18:00. Please load the new certificate before then so results keep flowing. Thanks, Results Partner IT',
    );
    await expect(mailbox.locator('.strip app-outcome-chip'), 'its outcome').toHaveText('Digest');
    await expect(mailbox.locator('.strip .reason').first(), 'its reason').toContainText('The CI mock keeps this item for the digest.');
    const trace = mailbox.locator('.strip app-trace-link').getByRole('link');
    await expect(trace, 'and the trace link').toHaveAccessibleName(/Trace/);
    await expect(trace, 'which opens in a new tab').toHaveAttribute('target', '_blank');
    await mailbox.getByRole('button', { name: 'Back', exact: true }).click();
    await expect(rowsOf(mailbox, 'Certificate change on Friday'), 'Back focuses the row').toBeFocused();
    await expect(rowsOf(mailbox, 'Certificate change on Friday').locator('.visually-hidden'), 'the email is read: the dot is gone').toHaveCount(0);

    await page.reload();
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    await page.getByRole('region', { name: 'Simulated devices' }).getByRole('tab', { name: MAILBOX_TAB }).click();
    const again = rowsOf(page.locator('app-simulated-mailbox'), 'Certificate change on Friday');
    await expect(again, 'after a reload the row is there').toHaveCount(1);
    await expect(again.locator('.visually-hidden'), 'still read').toHaveCount(0);
    await expect(again.locator('app-outcome-chip'), 'and still decided: Digest').toHaveText('Digest');
    await page.waitForTimeout(1500);
    expect(await announcements(page, "Email 'Certificate change on Friday': Digest"), 'a decision present at the reload is not announced').toBe(0);
  } finally {
    await dropPhone(USER, start);
    await dropMail(USER);
  }
});

test('MB3: the compose form prefills From, shows its field errors, and a send moves focus to the new row', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const start = startTime();
  const stamp = stampOf();
  const sender = `zz MB3 ${stamp} <mb3@example.com>`;
  await dropMail(USER);
  try {
    const mailbox = await openMailbox(page);
    const requests: string[] = [];
    page.on('request', (request) => {
      if (request.url().includes('/mailbox/')) requests.push(request.url());
    });
    await simulateOf(mailbox).click();
    const from = mailbox.getByRole('textbox', { name: 'From', exact: true });
    await expect(from, 'focus is on From').toBeFocused();
    await expect(from, 'prefilled with a sample sender').toHaveValue('Results Partner IT <it@results-partner.example>');
    const subject = mailbox.getByRole('textbox', { name: 'Subject', exact: true });
    const body = mailbox.getByRole('textbox', { name: 'Body', exact: true });
    await formOf(mailbox).getByRole('button', { name: 'Send', exact: true }).click();
    await expect(mailbox.getByText('Enter a subject.'), 'a blank subject has its error').toBeVisible();
    await expect(mailbox.getByText('Enter a body.'), 'a blank body has its error').toBeVisible();
    const danger = await tokenColor(page, '--danger-ink');
    await expect(subject, 'the subject is marked').toHaveCSS('border-top-color', danger);
    await expect(body, 'and so is the body').toHaveCSS('border-top-color', danger);
    await expect(subject, 'focus moves to the first field in error').toBeFocused();
    await expect(subject).toHaveAttribute('aria-invalid', 'true');
    expect(requests, 'no request was made').toEqual([]);
    expect(await mailRows(USER), 'and no row was made').toBe(0);

    await expect(body, 'the body holds at most 10000 characters').toHaveAttribute('maxlength', '10000');
    await from.fill(sender);
    await subject.fill(`zz MB3 subject ${stamp}`);
    await body.fill('zz MB3 body [[mock:mail-tell-now]]');
    await simulateOf(mailbox).click();
    await expect(from, 'Simulate pressed again focuses From').toBeFocused();
    await expect(subject, 'and keeps what was typed').toHaveValue(`zz MB3 subject ${stamp}`);
    await page.route(`**${INCOMING}`, (route) =>
      route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: { code: 'bad_email', message: 'zz the server refused this email' } }) }),
    );
    await formOf(mailbox).getByRole('button', { name: 'Send', exact: true }).click();
    await expect(mailbox.locator('#mailbox-send-error'), 'an error answer shows its message under Send').toContainText('zz the server refused this email');
    await expect(subject, 'and marks no field').not.toHaveAttribute('aria-invalid', 'true');
    await expect(body).not.toHaveAttribute('aria-invalid', 'true');
    await page.unroute(`**${INCOMING}`);
    await formOf(mailbox).getByRole('button', { name: 'Send', exact: true }).click();
    const row = rowsOf(mailbox, stamp);
    await expect(row, 'the list returns with the new row').toHaveCount(1, { timeout: 30_000 });
    await expect(row, 'and focus is on it').toBeFocused();
    await expect(row.locator('.deciding'), 'it is still deciding (the mock waits 2 s)').toHaveText('Deciding\u2026');
    await expect(row.locator('app-outcome-chip'), 'then Tell now').toHaveText('Tell now', { timeout: 60_000 });
    await expect(cards(page, stamp), 'a chat card').toHaveCount(1, { timeout: 30_000 });
    await expect(phoneMessages(page, stamp), 'and a phone message').toHaveCount(1, { timeout: 30_000 });

    await simulateOf(mailbox).click();
    await expect(mailbox.getByRole('textbox', { name: 'From', exact: true }), 'the form opens again with focus on From').toBeFocused();
    await formOf(mailbox).getByRole('button', { name: 'Back', exact: true }).click();
    await expect(simulateOf(mailbox), 'Back focuses the button').toBeFocused();
  } finally {
    await dropPhone(USER, start);
    await dropMail(USER);
  }
});

test('MB4: Ignore and Digest notify nobody, and Tell now and Act do, and Act raises no approval and makes no turn', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const start = startTime();
  const stamp = stampOf();
  await dropMail(USER);
  try {
    const mailbox = await openMailbox(page);
    const turns = await turnRows(USER);
    const approvals = async (): Promise<number> => ((await (await page.request.get(STATE)).json()) as { rail: { approvals: unknown[] } }).rail.approvals.length;
    const approvalsBefore = await approvals();
    const outcomes = [
      { marker: 'mail-ignore', chip: 'Ignore', outcome: 'ignore', reason: 'The CI mock ignores this email.' },
      { marker: 'mail-digest', chip: 'Digest', outcome: 'digest', reason: 'The CI mock keeps this email for the digest.' },
      { marker: 'mail-act', chip: 'Act', outcome: 'act', reason: 'The CI mock asks for an action on this email.' },
    ];
    const quiet: string[] = [];
    for (const one of outcomes) {
      const sender = `zz ${one.marker} ${stamp} <mb4@example.com>`;
      await compose(mailbox, sender, `zz ${one.marker}`, `zz body [[mock:${one.marker}]]`);
      const row = rowsOf(mailbox, `zz ${one.marker}`);
      await expect(row.first().locator('app-outcome-chip'), `${one.marker}: the chip`).toHaveText(one.chip, { timeout: 60_000 });
      const read = await mailOutcome(USER, sender);
      expect(read.outcome, `${one.marker}: the server's outcome`).toBe(one.outcome);
      if (one.outcome === 'act') {
        await expect.poll(async () => (await mailOutcome(USER, sender)).deliveries, { message: 'act notifies', timeout: 30_000 }).toBeGreaterThan(0);
        await expect(cards(page, sender), 'act: a chat card').toHaveCount(1, { timeout: 30_000 });
        await expect(phoneMessages(page, sender), 'and a phone message').toHaveCount(1, { timeout: 30_000 });
      } else {
        await page.waitForTimeout(1500);
        expect((await mailOutcome(USER, sender)).deliveries, `${one.marker}: no Delivery row for its decision`).toBe(0);
        await expect(phoneMessages(page, sender), `${one.marker}: no phone message`).toHaveCount(0);
        await expect(cards(page, sender), `${one.marker}: no chat card`).toHaveCount(0);
        quiet.push(sender);
      }
      if (one.outcome === 'ignore') {
        await expect(decisionRows(page, `zz ${one.marker} ${stamp}`).first(), 'ignore: a Recent decisions row of this run').toContainText(one.reason);
      }
    }
    for (const sender of quiet) {
      expect((await mailOutcome(USER, sender)).deliveries, `${sender}: still no Delivery row once Act, decided later, has notified`).toBe(0);
    }
    expect(await turnRows(USER), 'no Turn was made').toBe(turns);
    expect(await approvals(), 'and no approval request was raised').toBe(approvalsBefore);
  } finally {
    await dropPhone(USER, start);
    await dropMail(USER);
  }
});

test('MB5: markup in From, Subject and Body is shown as text, and nothing runs', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const start = startTime();
  const stamp = stampOf();
  const markup = '<img src=x onerror="window.zzMail=1"><b>b</b>';
  await dropMail(USER);
  try {
    const mailbox = await openMailbox(page);
    await compose(mailbox, `${markup} ${stamp}`, `${markup} ${stamp}`, `${markup} ${stamp}`);
    const row = rowsOf(mailbox, stamp);
    await expect(row, 'the row is in the list').toHaveCount(1, { timeout: 30_000 });
    await expect(row.locator('.subject'), 'the subject shows the markup literally').toHaveText(`${markup} ${stamp}`);
    await expect(row.locator('.from'), 'so does the sender').toContainText(`${markup} ${stamp}`);
    await row.click();
    await expect(mailbox.locator('.text'), 'and the open email\'s body').toHaveText(`${markup} ${stamp}`);
    await expect(mailbox.locator('img, b'), 'no element was made').toHaveCount(0);
    expect(await page.evaluate(() => (window as unknown as { zzMail?: number }).zzMail), 'and no script ran').toBeUndefined();
  } finally {
    await dropPhone(USER, start);
    await dropMail(USER);
  }
});

test('MB6: with demo mode off there is no mailbox, both routes answer 404 not_found and no row is made', async ({ page }) => {
  test.skip(stackMode() !== '0', 'demo mode off only');
  const before = await mailRows(USER);
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('region', { name: 'Simulated devices' }), 'no region').toHaveCount(0);
  await expect(page.locator('app-simulated-mailbox'), 'and no mailbox').toHaveCount(0);
  const state = await page.request.get(STATE);
  expect(Object.keys((await state.json()) as Record<string, unknown>), '/state has no mailbox key').not.toContain('mailbox');
  for (const [path, data] of [
    [INCOMING, { from: 'zz', subject: 'zz s', body: 'zz b' }],
    [SAMPLE, {}],
  ] as const) {
    const response = await post(page.request, path, data);
    expect(response.status(), `${path}: ${await response.text()}`).toBe(404);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe('not_found');
  }
  expect(await mailRows(USER), 'no SimMessage row was made').toBe(before);
});

/** A fixture email of the snapshot's mailbox: an incoming one by default, with the ref and the item that the tag makes unique. */
const fixtureMail = (tag: string, n: number, over: Record<string, unknown> = {}): Record<string, unknown> => ({
  ref: `zzq${tag}m${n}`,
  direction: 'in',
  itemId: `zzq${tag}i${n}`,
  sender: `Zz Sender ${n} <zz${n}@example.com>`,
  subject: `zz MBQ ${tag} subject ${n}`,
  text: `zz MBQ body ${n}`,
  unread: true,
  createdAt: new Date(Date.now() - (10 - n) * 60_000).toISOString().replace(/\.\d{3}Z$/, 'Z'),
  ...over,
});

/** A fixture decide decision of the snapshot entry's item. */
const fixtureDecision = (mail: Record<string, unknown>, over: Record<string, unknown> = {}): Record<string, unknown> => ({
  ref: `zzqd${String(mail['ref'])}`,
  kind: 'decide',
  itemId: mail['itemId'],
  outcome: 'digest',
  reasons: 'zz reason',
  confidence: 0.8,
  fallback: false,
  recordedAt: String(mail['createdAt']),
  ...over,
});

/** Answers /state with this mailbox, before the sign-in; the cases that use it write nothing on the server. */
const withMailbox = (page: Page, mailbox: Array<Record<string, unknown>>): Promise<void> =>
  changeSnapshot(page, (snapshot) => {
    snapshot['mailbox'] = mailbox;
  });

test('MB7: a snapshot email shows what it carries: its own decision silently, a fallback as Tell now with its flag, a sent email no status, an undecided one Deciding', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const tag = stampOf();
  const ignored = fixtureMail(tag, 1);
  ignored['decision'] = fixtureDecision(ignored, { outcome: 'ignore', reasons: 'zz first reason\nzz second reason', traceUrl: '/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=42' });
  const fallback = fixtureMail(tag, 2);
  fallback['decision'] = fixtureDecision(fallback, { outcome: 'digest', reasons: 'zz kept reason', fallback: true, fallbackReason: 'no_key' });
  const sent = fixtureMail(tag, 3, { direction: 'out', itemId: '', sender: 'OcuTalon' });
  const pending = fixtureMail(tag, 4);
  await withMailbox(page, [ignored, fallback, sent, pending]);
  const mailbox = await openMailbox(page);
  const rowOf = (mail: Record<string, unknown>): Locator => rowsOf(mailbox, String(mail['subject']));
  await expect(mailbox.locator('.row'), 'four rows').toHaveCount(4);
  await expect(mailbox.locator('.row').first(), 'newest first: the last of the snapshot is the first row').toContainText(String(pending['subject']));
  await expect(rowOf(ignored).locator('app-outcome-chip'), 'the entry\'s own decision gives its chip').toHaveText('Ignore');
  await expect(rowOf(fallback).locator('app-outcome-chip'), 'a fallback shows Tell now whatever the outcome').toHaveText('Tell now');
  await expect(rowOf(sent).locator('.deciding, app-outcome-chip'), 'a sent email has no status').toHaveCount(0);
  await expect(rowOf(pending).locator('.deciding'), 'an undecided one is deciding').toHaveText('Deciding\u2026');
  await expect(rowOf(pending).locator('app-outcome-chip'), 'with no chip').toHaveCount(0);
  await page.waitForTimeout(1000);
  expect((await announcedTexts(page)).filter((text) => text.includes("Email '")), 'the decisions present at load are not announced').toEqual([]);

  await rowOf(ignored).click();
  await expect(mailbox.locator('.strip app-outcome-chip'), 'the open email shows its outcome').toHaveText('Ignore');
  await expect(mailbox.locator('.strip .reason'), 'and every reason line').toHaveText(['zz first reason', 'zz second reason']);
  await expect(mailbox.locator('.strip app-trace-link'), 'and the trace link of the decision').toHaveCount(1);
  await expect(mailbox.locator('.strip app-trace-link a.trace-link'), 'which goes to its traceUrl').toHaveAttribute('href', String((ignored['decision'] as Record<string, unknown>)['traceUrl']));
  await expect(mailbox.locator('.strip app-fallback-flag'), 'no flag').toHaveCount(0);
  await mailbox.getByRole('button', { name: 'Back', exact: true }).click();
  await rowOf(fallback).click();
  await expect(mailbox.locator('.strip app-outcome-chip'), 'the fallback is Tell now').toHaveText('Tell now');
  await expect(mailbox.locator('.strip app-fallback-flag'), 'with the Fallback flag').toHaveCount(1);
  await expect(mailbox.locator('.strip .reason'), 'the fallback sentence first, then the reason').toHaveCount(2);
  await expect(mailbox.locator('.strip .reason').first(), 'in the warning style').toHaveClass(/fallback/);
  await expect(mailbox.locator('.strip .reason').last()).toHaveText('zz kept reason');
  await expect(mailbox.locator('.strip app-trace-link'), 'a decision with no trace has no link').toHaveCount(0);
  await mailbox.getByRole('button', { name: 'Back', exact: true }).click();
  await rowOf(sent).click();
  await expect(mailbox.getByRole('heading', { level: 3, name: String(sent['subject']) }), 'a sent email opens too').toBeFocused();
  await expect(mailbox.locator('.text'), 'with its text').toHaveText('zz MBQ body 3');
  await expect(mailbox.locator('.strip'), 'and no decision strip').toHaveCount(0);
  await mailbox.getByRole('button', { name: 'Back', exact: true }).click();
  await rowOf(pending).click();
  await expect(mailbox.locator('.strip .deciding'), 'an undecided email opened says it is deciding').toHaveText('Deciding\u2026');
  await expect(mailbox.locator('.strip app-outcome-chip'), 'with no chip').toHaveCount(0);
});

test('MB8: a decide decision that lands after load joins its email by itemId, is announced once, and a turn decision of the same item is no decision of the email', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const tag = stampOf();
  const mail = fixtureMail(tag, 1);
  await withMailbox(page, [mail]);
  const mailbox = await openMailbox(page);
  const row = rowsOf(mailbox, String(mail['subject']));
  await expect(row.locator('.deciding'), 'the email is deciding').toHaveText('Deciding\u2026');
  const subject = String(mail['subject']);
  const itemId = String(mail['itemId']);
  await publishFixtureEvent(USER, 'decision', 'OcuTalon.Live.Payload.Decision', { Ref: `zzqd${tag}t`, Kind: 'turn', ItemId: itemId, Outcome: 'act', Reasons: 'zz turn reason' });
  const sentinel = `zz MBQ ${tag} sentinel`;
  await publishMailbox(USER, `zzq${tag}m9`, { Direction: 'in', ItemId: `zzq${tag}i9`, Sender: 'Zz Sentinel <zz9@example.com>', Subject: sentinel, Text: 'zz sentinel body' });
  await expect(rowsOf(mailbox, sentinel), 'a later event of the stream has landed, so the turn decision has too').toHaveCount(1, { timeout: 30_000 });
  await expect(row.locator('.deciding'), 'a turn decision of the same item is no decision of the email').toHaveText('Deciding\u2026');
  await expect(row.locator('app-outcome-chip'), 'and gives it no chip').toHaveCount(0);
  await publishFixtureEvent(USER, 'decision', 'OcuTalon.Live.Payload.Decision', { Ref: `zzqd${tag}d`, Kind: 'decide', ItemId: itemId, Outcome: 'digest', Reasons: 'zz decide reason' });
  await expect(row.locator('app-outcome-chip'), 'the decide decision gives the chip').toHaveText('Digest', { timeout: 30_000 });
  await expect
    .poll(() => announcements(page, `Email '${subject}': Digest`), { message: 'the decision is announced once' })
    .toBe(1);
  await page.waitForTimeout(1500);
  expect(await announcements(page, `Email '${subject}': Digest`), 'and not again').toBe(1);
  expect(await announcements(page, `Email '${subject}': Act`), 'the turn decision of the same item says nothing about the email').toBe(0);
  await row.click();
  await expect(mailbox.locator('.strip .reason'), 'the open email shows the decide decision\'s reason').toHaveText('zz decide reason');
});

test('MB9: a chip press that is refused shows the server message under the chips, which describes the chip, and an accepted one is announced as arrived and then as decided', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const tag = stampOf();
  const arrival = fixtureMail(tag, 1, { subject: `zz MBQ ${tag} arrived` });
  const ref = String(arrival['ref']);
  const subject = String(arrival['subject']);
  let accept = false;
  await page.route('**/api/v1/mailbox/samples/partner-notice', (route) =>
    accept
      ? route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ ref }) })
      : route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: { code: 'bad_email', message: 'zz the chip was refused' } }) }),
  );
  await withMailbox(page, []);
  const mailbox = await openMailbox(page);
  const chip = chipOf(mailbox, 'Sample: partner notice');
  await chip.click();
  await expect(mailbox.locator('#mailbox-chip-error'), 'a refused press shows the server\'s message under the chips').toContainText('zz the chip was refused');
  await expect(chip, 'the message describes the chip').toHaveAttribute('aria-describedby', /(^| )mailbox-chip-error( |$)/);
  await expect(mailbox.locator('.row'), 'no row was made').toHaveCount(0);
  await expect(chip, 'focus stays on the chip').toBeFocused();

  accept = true;
  const answered = page.waitForResponse((response) => response.url().includes('/mailbox/samples/partner-notice'));
  await chip.click();
  await answered;
  await expect(mailbox.locator('#mailbox-chip-error'), 'the next press clears the message').toHaveCount(0);
  await expect(chip, 'and the description').not.toHaveAttribute('aria-describedby', /mailbox-chip-error/);
  expect((await announcedTexts(page)).filter((text) => text.includes("Email '")), 'nothing about an email is announced before its row is in the list').toEqual([]);
  await publishMailbox(USER, ref, { Direction: 'in', ItemId: String(arrival['itemId']), Sender: String(arrival['sender']), Subject: subject, Text: 'zz arrival body' });
  const row = rowsOf(mailbox, subject);
  await expect(row, 'the row arrives').toHaveCount(1, { timeout: 30_000 });
  await expect
    .poll(() => announcements(page, `Email '${subject}': Deciding\u2026`), { message: 'the accepted press is announced as arrived' })
    .toBe(1);
  await expect(row.locator('.deciding'), 'still deciding').toHaveText('Deciding\u2026');
  await publishFixtureEvent(USER, 'decision', 'OcuTalon.Live.Payload.Decision', { Ref: `zzqd${tag}d`, Kind: 'decide', ItemId: String(arrival['itemId']), Outcome: 'ignore', Reasons: 'zz reason' });
  await expect(row.locator('app-outcome-chip'), 'then it is decided').toHaveText('Ignore', { timeout: 30_000 });
  await expect
    .poll(() => announcements(page, `Email '${subject}': Ignore`), { message: 'and announced as decided' })
    .toBe(1);
  expect(await announcements(page, `Email '${subject}': Deciding\u2026`), 'the arrival was announced once').toBe(1);
  await expect(chip, 'focus stayed on the chip').toBeFocused();
});

test('MB10: when the browser storage throws, an opened email is still read for the life of the page, and nothing is logged as an error', async ({ page }) => {
  test.skip(stackMode() !== '1', 'demo mode on only');
  const tag = stampOf();
  const mail = fixtureMail(tag, 1);
  mail['decision'] = fixtureDecision(mail);
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  await page.addInitScript(() => {
    const blocked = 'ocutalon.mailbox.opened';
    const getItem = Storage.prototype.getItem;
    const setItem = Storage.prototype.setItem;
    Storage.prototype.getItem = function (this: Storage, key: string): string | null {
      if (key === blocked) throw new Error('zz storage blocked');
      return getItem.call(this, key);
    };
    Storage.prototype.setItem = function (this: Storage, key: string, value: string): void {
      if (key === blocked) throw new Error('zz storage blocked');
      setItem.call(this, key, value);
    };
  });
  await withMailbox(page, [mail]);
  const mailbox = await openMailbox(page);
  expect(await page.evaluate(() => { try { localStorage.getItem('ocutalon.mailbox.opened'); return 'reads'; } catch { return 'throws'; } }), 'the storage throws for the mailbox\'s key').toBe('throws');
  const row = rowsOf(mailbox, String(mail['subject']));
  await expect(row.locator('.visually-hidden'), 'the email is unread').toHaveText('Unread');
  await row.click();
  await expect(mailbox.getByRole('heading', { level: 3, name: String(mail['subject']) }), 'it opens').toBeFocused();
  await mailbox.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(row, 'Back focuses the row').toBeFocused();
  await expect(row.locator('.visually-hidden'), 'and it is read for the life of the page').toHaveCount(0);
  expect(errors.filter((text) => text.includes('zz storage blocked')), 'no error was logged for the storage').toEqual([]);
});
