import { expect, test, type Locator, type Page } from '@playwright/test';

import { STATE, post } from '../support/api';
import { dropMail, dropPhone, mailOutcome, mailRows, pointKeys, restoreKeys, turnRows } from '../support/devices';
import { announcements, recordAnnouncements, tokenColor } from '../support/page';
import { README_ACCOUNT, signInReadme } from '../sign-in/helpers';

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

const MAILBOX_TAB = /^Simulated mailbox/;
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
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await page.getByRole('region', { name: 'Simulated devices' }).getByRole('tab', { name: MAILBOX_TAB }).click();
  const mailbox = page.locator('app-simulated-mailbox');
  await expect(mailbox).toBeVisible();
  return mailbox;
}

const rowsOf = (mailbox: Locator, text: string): Locator => mailbox.locator('.row').filter({ hasText: text });
const chipOf = (mailbox: Locator, label: string): Locator => mailbox.getByRole('button', { name: `${label}, send sample email`, exact: true });
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

/** The rail's decision rows that hold the text. */
const decisionRows = (page: Page, text: string): Locator => page.getByRole('region', { name: 'Status', exact: true }).locator('app-decision-row').filter({ hasText: text });

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

    await from.fill(sender);
    await subject.fill(`zz MB3 subject ${stamp}`);
    await body.fill('zz MB3 body [[mock:mail-tell-now]]');
    await page.route(`**${INCOMING}`, (route) =>
      route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: { code: 'bad_email', message: 'zz the server refused this email' } }) }),
    );
    await formOf(mailbox).getByRole('button', { name: 'Send', exact: true }).click();
    await expect(mailbox.locator('#mailbox-send-error'), 'an error answer shows its message under Send').toContainText('zz the server refused this email');
    await expect(subject, 'and marks no field').not.toHaveAttribute('aria-invalid', 'true');
    await expect(body).not.toHaveAttribute('aria-invalid', 'true');
    expect(await mailRows(USER), 'and no row was made').toBe(0);
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
      }
      if (one.outcome === 'ignore') {
        await expect(decisionRows(page, `zz ${one.marker}`).first(), 'ignore: a Recent decisions row').toContainText(one.reason);
      }
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
  await signInReadme(page);
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
