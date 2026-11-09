import { expect, test, type Locator, type Page } from './support/fixtures';

import { signIn } from './sign-in/helpers';
import { post } from './support/api';
import { dropMail, dropPhone } from './support/devices';
import { phoneNotes } from './support/demo-path';
import { CARD_MS, loadedAfter, unique } from './support/floor';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted, seedDecision, sendItemDecision, sendNotification } from './support/iris';
import { announcements, recordAnnouncements } from './support/page';

/**
 * Story 41.5, the "This was noise" control (NZ1 to NZ8; FR-72, NFR-25), in a real browser against a real stack. Every case signs in as the notice fixture user
 * that test-sign-in.sh created (OCUTALON_NOTICE_USER), so the README session and api.spec's counts are untouched. A tell-now comes from a real email
 * (POST /v1/mailbox/incoming with `[[mock:mail-tell-now]]`): it reaches a tell-now decide Decision whose Item is kept, from the mock's decision or from the
 * no-key fallback, and both can be marked. The card is found by the email's unique subject, its Decision's Ref is the `data-noise` of the control's
 * container, and the Precedent row is read through irisScript. The browser runs in UTC with the en-GB locale, the stack's own zone.
 *   NZ1  a web mark by the keyboard: the body, the 200, the status line in place of the button, focus in the card, one row (channel web);
 *   NZ2  the same Decision pressed on the simulated phone: the first mark's time, still one row (channel web);
 *   NZ3  a mark on the phone first: one row with channel phone;
 *   NZ4  the route over HTTP: a body that is not exactly {"channel":"phone"} is web, a repeat answers the first time;
 *   NZ5  a tell-now whose Item is no longer kept: 409 too_old, the server's text beside the button, no row (DW-923);
 *   NZ6  a reminder and a tell-now with no decision show no control, in the chat or on the phone;
 *   NZ7  Tab reaches the button from the card, and Space presses it (NFR-25);
 *   NZ8  an error reply shows its message beside the button, a reply that never came shows the busy notice, the button stays, and a later press marks.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const INCOMING = '/ocutalon/api/v1/mailbox/incoming';
const noisePath = (ref: string): string => `/ocutalon/api/v1/decisions/${ref}/noise`;
const LABEL = 'This was noise';
const TOO_OLD = 'This notice is too old to mark as noise. Nothing was changed.';
/**
 * The status line as the page writes it: the fixed words around the mark's time, which the page shows as the browser formats an hour and a minute
 * (page-time.ts pageTime: the locale and zone of the page, here en-GB in UTC, so "1:10" before ten o'clock and "13:10" after). The time is
 * formatted by the page's own engine from the markedAt that the route answered, never copied from the page's text.
 */
async function markedText(page: Page, markedAt: string): Promise<string> {
  const time = await page.evaluate((iso) => new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(iso)), markedAt);
  return `Marked as noise at ${time}. Similar items will take this into account.`;
}

/** How long a mailed item may take to be decided and to reach the page. */
const MAIL_MS = 60_000;

/** The notice fixture user's name, read when a case needs it (listing the specs sets no OCUTALON_ variable). */
const userName = (): string => fixtureUser('NOTICE').user;

/** The UTC time to the second, a little before now, as dropPhone wants it. */
const startTime = (): string => new Date(Date.now() - 2000).toISOString().replace(/\.\d{3}Z$/, 'Z');

let since = startTime();
let seeded: string[] = [];

test.beforeEach(() => {
  since = startTime();
  seeded = [];
});

/** Removes what the case made: the session's Precedent rows, its phone and mail rows since the case began, and the fixture Decisions. */
async function clean(): Promise<void> {
  await irisScript(
    [`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(userName())},.sc)`, 'Do ##class(OcuTalon.Data.Precedent).DropSession(s.Ref)', 'Write !,"CHK|dropped|1"'].join('\n'),
  );
  await dropPhone(userName(), since);
  await dropMail(userName());
  await cleanFixtureRows(seeded);
}

test.afterEach(clean);
test.afterAll(clean);

/** The notice card whose text holds the marker. */
const cardOf = (page: Page, marker: string): Locator => page.locator('app-chat-panel app-notice-card').filter({ hasText: marker });

/** Signs the notice user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<void> {
  await recordAnnouncements(page);
  const { user: name, password } = fixtureUser('NOTICE');
  await loadedAfter(page, () => signIn(page, name, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('textbox', { name: 'Message OcuTalon' })).toBeVisible();
}

/** Sends a real email with a unique subject, waits for its tell-now card and its phone message, and returns the subject and the Decision's Ref. */
async function mailed(page: Page, label: string): Promise<{ subject: string; ref: string }> {
  const subject = unique(label);
  const sent = await post(page.request, INCOMING, { from: `zz.${label.toLowerCase()}@example.com`, subject, body: 'zz body [[mock:mail-tell-now]]' });
  expect(sent.status(), 'the email is accepted').toBeLessThan(300);
  const card = cardOf(page, subject);
  await expect(card, 'the tell-now card arrives').toHaveCount(1, { timeout: MAIL_MS });
  const container = card.locator('[data-noise]');
  await expect(container, 'with the control').toHaveCount(1, { timeout: CARD_MS });
  const ref = (await container.getAttribute('data-noise')) ?? '';
  expect(ref, "the Decision's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
  return { subject, ref };
}

/** The Precedent row of the Decision, as the table holds it. */
async function rowOf(ref: string): Promise<{ count: number; answer: string; channel: string; owner: string }> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(${quoted(ref)})`,
      'Set q=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Precedent WHERE SourceRef = ?",' + quoted(ref) + ')',
      'Do q.%Next()',
      'Write !,"CHK|row|",q.%GetData(1),"|",$Select($IsObject(r):r.Answer_"|"_r.AnsweredChannel_"|"_r.OwnerRef,1:"||")',
    ].join('\n'),
  );
  const [count = '', answer = '', channel = '', owner = ''] = (chk(lines, 'row') ?? '').split('|');
  return { count: Number(count), answer, channel, owner };
}

/** Presses the control with a key and returns the request body that left and the answer. */
async function pressWith(page: Page, ref: string, press: () => Promise<void>): Promise<{ body: unknown; status: number; answer: Record<string, unknown> }> {
  const matches = (url: string): boolean => new URL(url).pathname === noisePath(ref);
  const request = page.waitForRequest((one) => one.method() === 'POST' && matches(one.url()));
  const response = page.waitForResponse((one) => one.request().method() === 'POST' && matches(one.url()));
  await press();
  const sent = await request;
  const got = await response;
  return { body: JSON.parse(sent.postData() ?? 'null') as unknown, status: got.status(), answer: (await got.json()) as Record<string, unknown> };
}

/** NZ1: a web mark by the keyboard. */
test('NZ1: Enter on "This was noise" marks the notice, shows the status line in place of the button and keeps focus in the card', async ({ page }) => {
  await open(page);
  const { subject, ref } = await mailed(page, 'NZ1');
  const card = cardOf(page, subject);
  const buttons = card.getByRole('button', { name: LABEL, exact: true });
  await expect(buttons, 'the card has one button named "This was noise"').toHaveCount(1);
  const before = Date.now() - 2000;
  await buttons.focus();
  const { body, status, answer } = await pressWith(page, ref, () => page.keyboard.press('Enter'));
  const after = Date.now() + 2000;
  expect(body, 'the body names the web').toEqual({ channel: 'web' });
  expect(status, 'the route answers 200').toBe(200);
  expect(answer['result'], 'done').toBe('done');
  const markedAt = String(answer['markedAt']);
  expect(markedAt, 'markedAt is an ISO time').toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  expect(Date.parse(markedAt), 'within the case').toBeGreaterThanOrEqual(before - 1000);
  expect(Date.parse(markedAt)).toBeLessThanOrEqual(after);
  await expect(card.locator('.marked'), 'the status line replaces the button').toHaveText(await markedText(page, markedAt));
  await expect(card.getByRole('button', { name: LABEL }), 'no button is left').toHaveCount(0);
  await expect(card.locator('[data-noise]'), 'focus moved to the control\'s container, inside the card').toBeFocused();
  expect(await page.evaluate(() => document.activeElement === document.body), 'not to the body').toBe(false);
  expect(await rowOf(ref), 'one row: noise, from the web, the session\'s').toEqual({ count: 1, answer: 'noise', channel: 'web', owner: await ownerOf() });
});

/** The signed-in user's session Ref. */
async function ownerOf(): Promise<string> {
  const lines = await irisScript([`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(userName())},.sc)`, 'Write !,"CHK|ref|",s.Ref'].join('\n'));
  return chk(lines, 'ref') ?? '';
}

/** NZ2: the same Decision pressed on the phone after a web mark shows the first time and writes no second row. */
test('NZ2: a repeat on the simulated phone shows the first mark\'s time and keeps one row', async ({ page }) => {
  await open(page);
  const { subject, ref } = await mailed(page, 'NZ2');
  const first = await post(page.request, noisePath(ref), { channel: 'web' });
  expect(first.status(), 'the first mark').toBe(200);
  const markedAt = String(((await first.json()) as Record<string, unknown>)['markedAt']);
  const note = phoneNotes(page).filter({ hasText: subject });
  await expect(note, 'the same Decision has a phone message').toHaveCount(1, { timeout: CARD_MS });
  const button = note.getByRole('button', { name: LABEL, exact: true });
  await expect(button, 'with the control').toHaveCount(1);
  const { body, status, answer } = await pressWith(page, ref, () => button.click());
  expect(body, 'the body names the phone').toEqual({ channel: 'phone' });
  expect(status, '200').toBe(200);
  expect(answer['markedAt'], "the first mark's time").toBe(markedAt);
  await expect(note.locator('.marked'), 'the phone shows that time').toHaveText(await markedText(page, markedAt));
  await expect(button, 'in place of the button').toHaveCount(0);
  expect(await rowOf(ref), 'still one row, from the web').toEqual({ count: 1, answer: 'noise', channel: 'web', owner: await ownerOf() });
});

/** NZ3: a mark on the phone first keeps the channel phone. */
test('NZ3: a mark pressed on the phone first is recorded with the channel phone', async ({ page }) => {
  await open(page);
  const { subject, ref } = await mailed(page, 'NZ3');
  const note = phoneNotes(page).filter({ hasText: subject });
  const button = note.getByRole('button', { name: LABEL, exact: true });
  await expect(button).toHaveCount(1, { timeout: CARD_MS });
  const { body, status } = await pressWith(page, ref, () => button.click());
  expect(body).toEqual({ channel: 'phone' });
  expect(status).toBe(200);
  await expect(note.locator('.marked')).toHaveCount(1);
  expect(await rowOf(ref), 'one row with the channel phone').toEqual({ count: 1, answer: 'noise', channel: 'phone', owner: await ownerOf() });
});

/** NZ4: the route over HTTP. */
test('NZ4: over HTTP a body that is not exactly {"channel":"phone"} is web, and a repeat answers the first time', async ({ page }) => {
  await open(page);
  const { ref } = await mailed(page, 'NZ4');
  const first = await post(page.request, noisePath(ref), { channel: 'Phone' });
  expect(first.status(), '200').toBe(200);
  const marked = (await first.json()) as Record<string, unknown>;
  expect(marked['result'], 'done').toBe('done');
  expect(String(marked['markedAt']), 'with the time').toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  expect((await rowOf(ref)).channel, 'the channel is web').toBe('web');
  const again = await post(page.request, noisePath(ref), { channel: 'phone' });
  expect(again.status(), 'a repeat is 200 too').toBe(200);
  expect(((await again.json()) as Record<string, unknown>)['markedAt'], 'with the same time').toBe(marked['markedAt']);
  expect(await rowOf(ref), 'and there is still one row').toMatchObject({ count: 1, channel: 'web' });
});

/** NZ5: a notice whose Item is no longer kept (DW-923). */
test('NZ5: a notice whose item is gone is 409 too_old, with the server\'s text beside the button and no row', async ({ page }) => {
  await open(page);
  const summary = unique('NZ5');
  const ref = await seedDecision(userName(), { outcome: 'tellnow', summary, reasons: 'zz first.\nzz second.', confidence: 0.9, costUSD: 0.0003 });
  seeded.push(ref);
  await sendItemDecision(userName(), { outcome: 'tellnow', summary, decisionRef: ref });
  const card = cardOf(page, summary);
  await expect(card, 'the tell-now card arrives').toHaveCount(1, { timeout: CARD_MS });
  const button = card.getByRole('button', { name: LABEL, exact: true });
  await expect(button, 'with the control').toHaveCount(1);
  const { status, answer } = await pressWith(page, ref, () => button.click());
  expect(status, '409').toBe(409);
  const error = answer['error'] as { code: string; message: string };
  expect(error.code, 'too_old').toBe('too_old');
  expect(error.message, "with the server's text").toBe(TOO_OLD);
  await expect(card.locator('app-inline-notice'), 'the card shows that text beside the button').toHaveText(TOO_OLD);
  await expect(button, 'the button is still there').toHaveCount(1);
  await expect.poll(() => announcements(page, TOO_OLD), { message: 'the text is announced once' }).toBe(1);
  expect((await rowOf(ref)).count, 'no row').toBe(0);
});

/** NZ6: the control shows on no other notice. */
test('NZ6: a reminder and a tell-now with no decision show no "This was noise" control, in the chat or on the phone', async ({ page }) => {
  await open(page);
  const text = unique('NZ6').replace(/^zz /, 'stretch ');
  const plain = unique('NZ6');
  const dueAt = `${new Date().toISOString().slice(0, 10)}T12:00:00Z`;
  await sendNotification(userName(), { kind: 'reminder', catalogKey: 'reminder.due', slots: { text, dueAt } });
  await sendNotification(userName(), { kind: 'tellnow', catalogKey: 'notice.tellNow', slots: { whatHappened: plain, reason: 'zz reason' } });
  for (const marker of [text, plain]) {
    const card = cardOf(page, marker);
    await expect(card, 'the card arrives').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.getByRole('button', { name: LABEL }), `no control on the card of ${marker}`).toHaveCount(0);
    await expect(card.locator('[data-noise]'), 'and no container').toHaveCount(0);
    const note = phoneNotes(page).filter({ hasText: marker });
    await expect(note, 'the phone message arrives').toHaveCount(1, { timeout: CARD_MS });
    await expect(note.getByRole('button', { name: LABEL }), `no control on the phone message of ${marker}`).toHaveCount(0);
  }
});

/** NZ7: the keyboard path of NFR-25 from the card to the mark. */
test('NZ7: Tab from the card reaches "This was noise", and Space presses it', async ({ page }) => {
  await open(page);
  const { subject, ref } = await mailed(page, 'NZ7');
  const card = cardOf(page, subject);
  const button = card.getByRole('button', { name: LABEL, exact: true });
  await expect(button, 'the card has one button named "This was noise"').toHaveCount(1);
  await card.locator('[data-part="notice"]').focus();
  const gotIt = card.getByRole('button', { name: 'Got it', exact: true });
  let reached = false;
  let gotItFirst = false;
  for (let step = 0; step < 8 && !reached; step += 1) {
    await page.keyboard.press('Tab');
    if ((await gotIt.count()) === 1 && (await gotIt.evaluate((one) => one === document.activeElement))) gotItFirst = true;
    reached = await button.evaluate((one) => one === document.activeElement);
  }
  expect(reached, 'Tab reaches the button within a few presses').toBe(true);
  expect(gotItFirst, 'Got it (Story 18.4) comes one Tab before "This was noise" on the same card (integrate-forward ruling)').toBe(true);
  const { body, status } = await pressWith(page, ref, () => page.keyboard.press('Space'));
  expect(body, 'the body names the web').toEqual({ channel: 'web' });
  expect(status, '200').toBe(200);
  await expect(card.locator('.marked'), 'the status line replaces the button').toHaveCount(1);
  await expect(button, 'no button is left').toHaveCount(0);
  expect((await rowOf(ref)).count, 'one row').toBe(1);
});

/** NZ8: the other refusals. */
test('NZ8: an error reply shows its message beside the button, no reply shows the busy notice, the button stays, and a later press marks', async ({ page }) => {
  await open(page);
  const { subject, ref } = await mailed(page, 'NZ8');
  const card = cardOf(page, subject);
  const button = card.getByRole('button', { name: LABEL, exact: true });
  const notice = card.locator('app-inline-notice');
  const SAID = 'zz The server said no.';
  const BUSY = "Couldn't reach OcuTalon. Try again. Nothing was changed.";
  let mode: 'refuse' | 'down' | 'live' = 'refuse';
  await page.route(
    (url) => url.pathname === noisePath(ref),
    (route) => {
      if (route.request().method() !== 'POST' || mode === 'live') return route.continue();
      if (mode === 'down') return route.abort('failed');
      return route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: SAID } }) });
    },
  );
  await expect(button).toHaveCount(1);
  await button.click();
  await expect(notice, "the reply's message is beside the button").toHaveText(SAID);
  await expect.poll(() => announcements(page, SAID), { message: 'announced once' }).toBe(1);
  await expect(button, 'the button stays').toHaveCount(1);
  mode = 'down';
  await button.click();
  await expect(notice, 'no reply: the busy notice replaces the message').toHaveText(BUSY);
  await expect.poll(() => announcements(page, BUSY), { message: 'announced once' }).toBe(1);
  await expect(button, 'the button stays').toHaveCount(1);
  expect((await rowOf(ref)).count, 'nothing was written').toBe(0);
  mode = 'live';
  await button.click();
  await expect(card.locator('.marked'), 'a later press marks').toHaveCount(1);
  await expect(notice, 'and the notice is gone').toHaveCount(0);
  await expect(button).toHaveCount(0);
  expect(await rowOf(ref), 'one row, from the web').toMatchObject({ count: 1, answer: 'noise', channel: 'web' });
});
