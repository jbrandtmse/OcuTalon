import { expect, test, type Locator, type Page, type Request } from '@playwright/test';
import qrcode from 'qrcode-generator';

import { changeSnapshot } from '../support/api';
import { composerOf, inMs, signInReadmeLoaded } from '../support/floor';
import { chk, irisScript, quoted, setTelegramIncluded } from '../support/iris';
import { announcedTexts, plain, recordAnnouncements, tokenColor } from '../support/page';
import { notBuilt } from './not-built';

/**
 * UJ-1 step 1, the Telegram part: the page's Telegram card, shown only once a release includes Telegram. Lane A owns this file from Epic 12
 * (AD-29). It holds:
 * - Story 12.8's two tests: the card's paused state, from a real 409 of TelegramIn against the CI mock (T1: the banner and the card, a reload,
 *   the resume and the clear, and the search of the page for the bot token) and from a changed snapshot (T2: the card's states);
 * - Story 12.3's two tests and its extension of T1: the card's unpaired state with a fresh pairing code as a QR code. T1 also records the
 *   page's code requests: one before the pause, none while it lasts, a new one after the clear. T3 drives the real chain (TelegramIn against
 *   the CI mock with a queued getMe name, the real code route and the page) and then has the IRIS side check the server's code row and search
 *   the production's stores for every code, and checks that the page keeps the codes to the card; T4 shows the off and the paired cards
 *   from changed snapshots, and the card's failure, countdown and ten-minute rules from answers the route makes up;
 * - Story 12.4's pairing, still a part that no story has built: Story 12.4 replaces the declaration at the end of this file with the real
 *   test. web/scripts/demo-path-summary.mjs counts the file as a part of step 1 (the `page` in the file name), skipped with the story that
 *   owns it.
 *
 * The browser runs in Asia/Kolkata with the en-GB locale, so a UTC time reads five and a half hours later, with an unpadded 24-hour hour:
 * 12:00 UTC is 17:30. The oracle for a time is `kolkata`, written here from the UTC clock and not from the page's own format.
 * All tests are tagged @floor, like step 1's other tests: they need a stack and a browser, so the no-stack run of the real specs
 * (scripts/demo-path-summary.test.mjs) leaves them out, and in the demo-path unit a failure of any fails the unit.
 * The tests run on fresh throwaway stacks and in CI only, against the CI mock and its dummy token (Rule 21): no real bot, no call to the
 * public Telegram API. The token is compared only as a boolean, and no text of this file holds it. No test waits ten minutes: T3 stands
 * in for elapsed time by changing the expiry of a code on its way to the page, and keeps the server's real answer for its oracles.
 */

/** How long the page may take to apply an event after the server published it: the live poll (1 to 2 s) and the render. */
const APPLIED_MS = 15_000;

/** The bound of "within one live update", counted from the page having applied the event. */
const ONE_UPDATE_MS = 1000;

/** How long a case waits for a card or a banner that a reloaded snapshot brings. */
const LOADED_MS = 10_000;

const TELEGRAM_README = 'https://github.com/jbrandtmse/OcuTalon#telegram';

/** The time of a snapshot's pause: 12:00 UTC, which the page shows as 17:30. */
const SNAPSHOT_TIME = '2026-10-23T12:00:00Z';

const mainOf = (page: Page): Locator => page.locator('main.main');
const railOf = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
const cardOf = (page: Page): Locator => railOf(page).locator('app-telegram-card');
const bannerOf = (page: Page): Locator => page.locator('.banner-slot [data-banner="telegramPaused"]');

/** A UTC ISO time as the Asia/Kolkata page shows it in en-GB: UTC plus 5 h 30 min, an unpadded hour and two-digit minutes. */
function kolkata(iso: string): string {
  const shifted = new Date(Date.parse(iso) + 330 * 60_000);
  return `${shifted.getUTCHours()}:${String(shifted.getUTCMinutes()).padStart(2, '0')}`;
}

/** The text of the banner for a pause that ends at that page time. */
const bannerText = (time: string): string =>
  `Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at ${time}. Each OcuTalon needs its own bot.`;

/** Asserts the paused banner: its text, and its one link to the README's Telegram section in a new tab. */
async function expectBanner(page: Page, time: string, bound: number): Promise<void> {
  const one = bannerOf(page);
  await expect(one, 'the paused banner shows').toHaveCount(1, { timeout: bound });
  await expect(one.locator('.text'), 'with the pause and its time').toHaveText(bannerText(time), { timeout: bound });
  const link = one.getByRole('link');
  await expect(link, 'with one link').toHaveCount(1);
  await expect(link, 'named Set up a bot, with the new-tab words').toHaveAccessibleName('Set up a bot (opens in a new tab)');
  await expect(link, 'to the README\'s Telegram section').toHaveAttribute('href', TELEGRAM_README);
  await expect(link).toHaveAttribute('target', '_blank');
}

/** Asserts the paused card: its text, its icon in the token's colour, and nothing else (no link, QR code or code). */
async function expectPausedCard(page: Page, time: string, bound: number): Promise<void> {
  const card = cardOf(page);
  await expect(card.locator('[data-state="paused"]'), 'the card is paused').toHaveCount(1, { timeout: bound });
  await expect.poll(async () => plain(await card.innerText()), { message: 'the card says it is paused and when it will try again', timeout: bound }).toBe(
    `Telegram paused Trying again at ${time}`,
  );
  const icon = card.locator('svg');
  await expect(icon, 'the icon is the only svg').toHaveCount(1);
  await expect(icon.locator('circle[cx="12"][cy="12"][r="10"]'), 'the icon is circle-pause: a circle').toHaveCount(1);
  await expect(icon.locator('line[x1="10"][x2="10"][y1="15"][y2="9"]'), 'with the left bar').toHaveCount(1);
  await expect(icon.locator('line[x1="14"][x2="14"][y1="15"][y2="9"]'), 'and the right bar').toHaveCount(1);
  await expect(icon, 'the icon is hidden from assistive technology').toHaveAttribute('aria-hidden', 'true');
  await expect(icon, 'in the paused icon token\'s colour').toHaveCSS('color', await tokenColor(page, '--telegram-card-paused-icon'));
  await expect(card.getByRole('link'), 'no link').toHaveCount(0);
  await expect(card.locator('a, img, canvas'), 'no link, image or QR code').toHaveCount(0);
}

/** Asserts that the card shows neither paused text. */
async function expectNotPausedCard(page: Page, bound: number): Promise<void> {
  const card = cardOf(page);
  await expect(card.locator('[data-state="paused"]'), 'the card is not paused').toHaveCount(0, { timeout: bound });
  expect(plain(await card.innerText()), 'and shows neither paused text').not.toMatch(/Telegram paused|Trying again at/);
}

/** Reloads (or loads) and waits for the loaded snapshot. */
async function loaded(page: Page): Promise<void> {
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
}


/** The fixture class of the IRIS side. */
const FIXTURE = '##class(OcuTalon.Test.Channel.TelegramPageFixture)';

/**
 * Calls one method of the fixture in an IRIS script and returns its reason ("" when it worked) with the values of its output variables.
 * The script prints its CHK lines on every path, because irisScript runs a session again that printed none and Start is not idempotent.
 */
async function fixture(call: string, outputs: string[] = []): Promise<{ reason: string; values: Record<string, string> }> {
  const lines = await irisScript(
    [
      ['Set r=""', ...outputs.map((name) => `${name}=""`)].join(','),
      `Try { Set r=${FIXTURE}.${call} } Catch ex { Set r="the call threw "_ex.Name }`,
      'Write !,"CHK|reason|",$Translate(r,$Char(13,10),"  ")',
      ...outputs.map((name) => `Write !,"CHK|${name}|",${name}`),
    ].join('\n'),
  );
  const reason = chk(lines, 'reason');
  if (reason === undefined) return { reason: 'the IRIS script printed no answer', values: {} };
  return { reason, values: Object.fromEntries(outputs.map((name) => [name, chk(lines, name) ?? ''])) };
}

/** Waits until the page has applied the event of this Seq on the instance stream, and returns when it saw that (Date.now()). */
async function appliedInstance(page: Page, seq: number): Promise<number> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-instance-seq')), {
      message: `the page applied Seq ${seq} of the instance stream`,
      timeout: APPLIED_MS,
      intervals: [100],
    })
    .toBeGreaterThanOrEqual(seq);
  return Date.now();
}

/**
 * What is left of the one live update that started when the page applied the event, so that the banner and the card share one window;
 * at least 250 ms, the time one check of the card takes.
 */
const leftOf = (applied: number): number => Math.max(250, ONE_UPDATE_MS - (Date.now() - applied));

/** The route of the code request, as a Playwright glob and as a path. */
const CODE_ROUTE = '**/ocutalon/api/v1/pairing/code';
const CODE_PATH = '/ocutalon/api/v1/pairing/code';

/** True for the card's request for a pairing code. */
const isCodeRequest = (request: Request): boolean => request.method() === 'POST' && new URL(request.url()).pathname === CODE_PATH;

/** What the page sent: the time of each code request, its body and its envelope header. */
interface Sent {
  at: number;
  body: string | null;
  envelope: string | undefined;
}

/** Records the card's code requests by time. */
function recordRequests(page: Page): Sent[] {
  const sent: Sent[] = [];
  page.on('request', (request) => {
    if (isCodeRequest(request)) sent.push({ at: Date.now(), body: request.postData(), envelope: request.headers()['x-ocutalon-request'] });
  });
  return sent;
}

/** The oracle for the QR symbol of a link: the side in modules, and one unit square per dark module, row by row, as the card draws it. */
function symbolOf(link: string): { size: number; path: string } {
  const symbol = qrcode(0, 'M');
  symbol.addData(link);
  symbol.make();
  const size = symbol.getModuleCount();
  let path = '';
  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) {
      if (symbol.isDark(row, col)) path += `M${col} ${row}h1v1h-1z`;
    }
  }
  return { size, path };
}

test.describe('the Telegram card is paused while Telegram is paused (Story 12.8)', () => {
  test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' });

  /** A poll that a routed handler is still answering when a test ends must not fail the next test. */
  test.afterEach(async ({ page }) => {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  /**
   * T2: the card's states from a changed snapshot: the matrix rows "Paused while off", "Paused while rejected" and "Not paused". There is no
   * seam and no IRIS state: the snapshot says the release includes Telegram and holds (or does not hold) the pause.
   */
  test('T2: the card is paused ahead of off and rejected, and not set up when there is no pause', { tag: '@floor' }, async ({ page }) => {
    await signInReadmeLoaded(page);
    const cases = [
      { label: 'off, paused', state: 'off', paused: true },
      { label: 'rejected, paused', state: 'rejected', paused: true },
      { label: 'off, not paused', state: 'off', paused: false },
    ] as const;
    for (const one of cases) {
      await page.unrouteAll({ behavior: 'ignoreErrors' });
      await changeSnapshot(page, (snapshot) => {
        snapshot['telegram'] = { ...(snapshot['telegram'] as Record<string, unknown>), included: true, state: one.state };
        const others = (snapshot['status'] as Array<{ condition?: string }>).filter((member) => member.condition !== 'telegramPaused');
        snapshot['status'] = [
          ...others,
          one.paused ? { condition: 'telegramPaused', active: true, slots: { time: SNAPSHOT_TIME } } : { condition: 'telegramPaused', active: false },
        ];
      });
      await page.reload();
      await loaded(page);
      await expect(cardOf(page), `${one.label}: the Telegram card is in the rail`).toHaveCount(1);
      if (one.paused) {
        await expectPausedCard(page, '17:30', LOADED_MS);
        await expect(railOf(page).getByRole('link', { name: 'How to set it up (opens in a new tab)' }), `${one.label}: no set-up link`).toHaveCount(0);
        await expectBanner(page, '17:30', LOADED_MS);
      } else {
        await expect(cardOf(page).locator('[data-state="not-set-up"]'), `${one.label}: the card is not set up`).toHaveCount(1);
        await expect.poll(async () => plain(await cardOf(page).innerText()), { message: `${one.label}: the card says so` }).toMatch(/^Telegram not set up How to set it up/);
        const link = railOf(page).getByRole('link', { name: 'How to set it up (opens in a new tab)', exact: true });
        await expect(link, `${one.label}: with its link`).toHaveCount(1);
        await expect(link).toHaveAttribute('href', TELEGRAM_README);
        await expectNotPausedCard(page, ONE_UPDATE_MS);
        await expect(bannerOf(page), `${one.label}: no Telegram banner`).toHaveCount(0);
      }
    }
  });

  /**
   * T1: the real pause, end to end. TelegramIn runs against the CI mock, the mock answers its poll with a 409, and the chain TelegramIn, the
   * telegramPaused mark, StatusMonitor and /state shows the banner and the paused card; a reload shows them again; the resume deletes the
   * mark and both leave; and the dummy bot token is nowhere in the page or in what the server sent it (NFR-11, AD-14). Story 12.3 adds the
   * page's code requests: the unpaired card has asked for one code before the 409, the page asks for none from its onset to its clear (the
   * reload included), and it asks again after the clear and shows the link to the bot.
   */
  test('T1: a 409 of TelegramIn pauses the banner and the card, a reload keeps them, the resume clears them, and the token is nowhere', { tag: '@floor' }, async ({ page }) => {
    test.setTimeout(240_000);
    const was = await setTelegramIncluded(1);
    let saved = '';
    let passed = false;
    try {
      const token =
        (await irisScript(['Set t=""', `Try { Set t=${FIXTURE}.Token() } Catch ex { Set t="" }`, 'Write !,"CHK|token|",t'].join('\n')).then((lines) =>
          chk(lines, 'token'),
        )) ?? '';
      expect(token.length > 0, 'the stack has the CI dummy token').toBe(true);
      const bodies: Array<Promise<string>> = [];
      page.on('response', (response) => {
        if (new URL(response.url()).pathname.startsWith('/ocutalon/')) bodies.push(response.text().catch(() => ''));
      });
      const posts = recordRequests(page);

      const started = await fixture('Start(.saved)', ['saved']);
      saved = started.values['saved'] ?? '';
      expect(started.reason, 'TelegramIn starts against the mock').toBe('');

      // The baseline: the card is in the rail, and there is no pause on the page.
      await signInReadmeLoaded(page);
      await expect(cardOf(page), 'the release includes Telegram, so its card is in the rail').toHaveCount(1);
      await expect(bannerOf(page), 'no paused banner before the 409').toHaveCount(0);
      await expectNotPausedCard(page, ONE_UPDATE_MS);
      await expect(cardOf(page).locator('[data-state="unpaired"]'), 'the card is unpaired before the 409').toHaveCount(1, { timeout: LOADED_MS });
      await expect(cardOf(page).getByRole('img'), 'and shows a QR code').toHaveCount(1);
      expect(posts.length, 'the card asked for one code').toBe(1);

      // The onset: the 409 reaches StatusMonitor's event and then the page.
      const conflict = await fixture('Conflict(.until, .onset)', ['until', 'onset']);
      expect(conflict.reason, 'the 409 pauses TelegramIn and StatusMonitor publishes the onset').toBe('');
      const until = conflict.values['until'] ?? '';
      const time = kolkata(until);
      expect(until, 'the mark is a UTC time').toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
      const onsetApplied = await appliedInstance(page, Number(conflict.values['onset']));
      await expectBanner(page, time, ONE_UPDATE_MS);
      await expectPausedCard(page, time, leftOf(onsetApplied));
      const pausedHtml = await page.content();

      // A reload shows the same, from /state.
      await page.reload();
      await loaded(page);
      await expectBanner(page, time, APPLIED_MS);
      await expectPausedCard(page, time, APPLIED_MS);

      // The resume and the clear.
      const resumeAt = Date.now();
      const resumed = await fixture(`Resume(2, ${Number(conflict.values['onset'])}, .clear)`, ['clear']);
      expect(resumed.reason, 'the first 200 deletes the mark and StatusMonitor publishes the clear').toBe('');
      const clear = Number(resumed.values['clear']);
      const clearApplied = await appliedInstance(page, clear);
      await expect(bannerOf(page), 'the banner leaves within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
      await expectNotPausedCard(page, leftOf(clearApplied));
      expect(posts.filter(({ at }) => at >= onsetApplied && at <= resumeAt).length, 'the page asked for no code from its onset to the resume, the reload included').toBe(0);
      await expect.poll(() => posts.length, { message: 'the card asks for a new code after the clear', timeout: LOADED_MS }).toBe(2);
      await expect(cardOf(page).locator('[data-state="unpaired"]'), 'and is unpaired again').toHaveCount(1, { timeout: LOADED_MS });
      await expect(cardOf(page).getByRole('link'), 'with the link to the bot of the pause').toHaveAttribute('href', /^https:\/\/t\.me\/ocutalon_ci_bot\?start=[A-Za-z0-9_-]{22}$/, {
        timeout: LOADED_MS,
      });
      await expect(cardOf(page).getByRole('img'), 'and a QR code').toHaveCount(1);
      const clearedHtml = await page.content();

      // The token search: the page's HTML at the pause and after the clear, and every response under /ocutalon/ that the page received.
      expect(pausedHtml.includes(bannerText(time)), 'the HTML at the pause holds the banner text (the scan sees what the store holds)').toBe(true);
      expect(pausedHtml.includes(token), 'the HTML at the pause holds no bot token').toBe(false);
      expect(clearedHtml.includes('app-telegram-card'), 'the HTML after the clear holds the Telegram card').toBe(true);
      expect(
        Number(/data-instance-seq="(\d+)"/.exec(clearedHtml)?.[1] ?? Number.NaN) >= clear,
        'the HTML after the clear holds the store\'s instance Seq of the clear (the scan sees what the store holds)',
      ).toBe(true);
      expect(clearedHtml.includes(token), 'the HTML after the clear holds no bot token').toBe(false);
      const texts = await Promise.all(bodies);
      expect(texts.some((text) => text.includes(token)), 'no response holds the bot token').toBe(false);
      expect(texts.length > 0, 'the page received responses under /ocutalon/').toBe(true);
      expect(texts.some((text) => text.includes(until)), 'the responses hold the mark\'s time (the scan sees what the server sent)').toBe(true);
      expect(texts.some((text) => text.includes('ocutalon_ci_bot')), 'and the bot\'s user name').toBe(true);
      passed = true;
    } finally {
      let finished = { reason: '' };
      try {
        finished = await fixture(`Finish(${quoted(saved)})`);
      } finally {
        await setTelegramIncluded(was);
      }
      if (finished.reason !== '') {
        if (passed) expect(finished.reason, 'the fixture puts everything back').toBe('');
        else test.info().annotations.push({ type: 'finish', description: finished.reason });
      }
    }
  });
});

test.describe('the Telegram card shows a fresh pairing code as a QR code (Story 12.3)', () => {
  test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' });

  /** A poll that a routed handler is still answering when a test ends must not fail the next test. */
  test.afterEach(async ({ page }) => {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  /** The bot name that the queued getMe answer gives, which the mock's default does not. */
  const BOT = 'ocutalon_qr_bot';
  const SCAN = "Scan with your phone's camera, then tap Start in Telegram.";
  const ALT = 'QR code that opens OcuTalon in Telegram to pair this session';
  const NAVY = 'rgb(16, 42, 69)';
  const WHITE = 'rgb(255, 255, 255)';
  const CODE = /^[A-Za-z0-9_-]{22}$/;

  /** What the route kept of one real answer of the code route: its status, its body as the server sent it, and the test's time. */
  interface Answer {
    status: number;
    body: { code: string; expiresAt: string };
    at: number;
  }

  /**
   * Routes the code request: every real answer is kept (status, body, the test's time), and the page gets it as the server sent it, except
   * that the first answer's expiry is moved to 10 s after it and the second's to 60 s before it. This stands in for elapsed time.
   */
  async function routeCodes(page: Page): Promise<Answer[]> {
    const answers: Answer[] = [];
    await page.route(CODE_ROUTE, async (route) => {
      const response = await route.fetch();
      const body = (await response.json()) as { code: string; expiresAt: string };
      const at = Date.now();
      answers.push({ status: response.status(), body: { ...body }, at });
      const changed = { ...body };
      if (answers.length === 1) changed.expiresAt = inMs(10_000);
      if (answers.length === 2) changed.expiresAt = inMs(-60_000);
      await route.fulfill({ response, json: changed });
    });
    return answers;
  }

  /** Asserts that the card shows this code: one link and one QR code, both for the pairing link of the code and the bot. */
  async function expectCode(page: Page, code: string, bound: number): Promise<void> {
    const card = cardOf(page);
    const href = `https://t.me/${BOT}?start=${code}`;
    const symbol = symbolOf(href);
    await expect(card.getByRole('link'), 'one link').toHaveCount(1, { timeout: bound });
    await expect(card.getByRole('link'), 'to the pairing link of the code').toHaveAttribute('href', href, { timeout: bound });
    const image = card.getByRole('img', { name: ALT, exact: true });
    await expect(image, 'one QR code, with the alt text').toHaveCount(1);
    await expect(image.locator('path'), 'drawn as one path').toHaveCount(1);
    await expect(image.locator('path'), 'which is the symbol of the same link').toHaveAttribute('d', symbol.path, { timeout: bound });
    await expect(image, 'in the symbol\'s own units').toHaveAttribute('viewBox', `0 0 ${symbol.size} ${symbol.size}`);
  }

  /** Asserts the QR block: 132 by 132 px, white, with the symbol navy. */
  async function expectNavyOnWhite(page: Page, label: string): Promise<void> {
    const image = cardOf(page).getByRole('img', { name: ALT, exact: true });
    const block = image.locator('xpath=..');
    const box = await block.boundingBox();
    expect(box?.width ?? 0, `${label}: the block is 132 px wide`).toBeCloseTo(132, 0);
    expect(box?.height ?? 0, `${label}: and 132 px high`).toBeCloseTo(132, 0);
    await expect(block, `${label}: white`).toHaveCSS('background-color', WHITE);
    await expect(image.locator('path'), `${label}: with a navy symbol`).toHaveCSS('fill', NAVY);
  }

  /** The {n} of "New code in {n} min" for an expiry, as the page's own clock reads it now. */
  async function minutesOf(page: Page, expiresAt: string): Promise<number> {
    const now = await page.evaluate(() => Date.now());
    return Math.max(1, Math.floor((Date.parse(expiresAt) - now) / 60_000));
  }

  /** Waits until the test's clock reaches a time. */
  const until = (at: number): Promise<void> => new Promise((done) => setTimeout(done, Math.max(0, at - Date.now())));

  /**
   * T3: the real chain. TelegramIn runs against the CI mock with a queued getMe answer that names ocutalon_qr_bot; the README account signs
   * in; the card asks the real code route for a code and shows it as a link and a QR code; the code runs out (the route moves its expiry)
   * while the user types and while the link has focus, and each new code lands in the same elements; no console line, storage entry,
   * address, title or announcement of the page holds a code; and the IRIS side then reads the server's code row and searches the
   * production's stores for every code the page was given. The matrix rows "A fresh code", "The code
   * runs out while the user types", "A past expiry, with focus on the link", "The server side of the codes" and "No code anywhere else".
   */
  test('T3: the card shows the real code as a link and a QR code, refreshes it in place, and no code is stored anywhere', { tag: '@floor' }, async ({ page }) => {
    test.setTimeout(180_000);
    const was = await setTelegramIncluded(1);
    let saved = '';
    let passed = false;
    try {
      const started = await fixture(`Start(.saved, ${quoted(BOT)})`, ['saved']);
      saved = started.values['saved'] ?? '';
      expect(started.reason, 'TelegramIn starts against the mock, which names the bot').toBe('');
      const marked = await fixture('CodeMark()');
      const mark = marked.reason;
      expect(mark, 'the fixture gives the marks of the stores').toMatch(/^[A-Za-z0-9+/=]+$/);

      const sent = recordRequests(page);
      const answers = await routeCodes(page);
      const consoled: string[] = [];
      page.on('console', (message) => consoled.push(message.text()));
      await recordAnnouncements(page);
      await signInReadmeLoaded(page);
      const card = cardOf(page);
      await expect(card, 'the release includes Telegram, so its card is in the rail').toHaveCount(1);

      // A fresh code.
      await expect(card.locator('[data-state="unpaired"]'), 'the card is unpaired').toHaveCount(1, { timeout: LOADED_MS });
      await expect.poll(() => answers.length, { message: 'the route kept the first answer', timeout: LOADED_MS }).toBe(1);
      const first = answers[0]!;
      expect(sent.length, 'exactly one request for a code').toBe(1);
      expect(sent[0]?.body, 'a POST of {}').toBe('{}');
      expect(sent[0]?.envelope, 'with the browser envelope').toBe('1');
      expect(first.status, 'the real answer is 200').toBe(200);
      expect(first.body.code, 'a 22-character code of base64url characters').toMatch(CODE);
      const lifetime = Date.parse(first.body.expiresAt) - first.at;
      expect(lifetime, 'valid for ten minutes (600 s, plus or minus 2 s)').toBeGreaterThanOrEqual(598_000);
      expect(lifetime).toBeLessThanOrEqual(602_000);
      await expectCode(page, first.body.code, LOADED_MS);
      const text = plain(await card.innerText());
      const order = [SCAN, 'Open in Telegram', 'New code in 1 min'].map((one) => text.indexOf(one));
      expect(order.every((at) => at >= 0), `the card holds the scan line, the link text and the countdown (${text})`).toBe(true);
      expect(order[0]! < order[1]! && order[1]! < order[2]!, 'in that order').toBe(true);
      const link = card.getByRole('link');
      await expect(link, 'the link is named with the Telegram words').toHaveAccessibleName('Open in Telegram (opens Telegram)');
      await expect(link).toHaveAttribute('target', '_blank');
      await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
      await expect(link, 'and underlined').toHaveCSS('text-decoration-line', 'underline');
      await expectNavyOnWhite(page, 'light');
      await page.emulateMedia({ colorScheme: 'dark' });
      await expectNavyOnWhite(page, 'dark');
      await page.emulateMedia({ colorScheme: 'light' });

      // The code runs out while the user types: the composer keeps focus and the draft.
      const composer = composerOf(page);
      const draft = 'zz draft in the composer';
      await composer.click();
      await composer.fill(draft);
      await expect(composer).toBeFocused();
      await expect.poll(() => sent.length, { message: 'the second request for a code', timeout: 25_000, intervals: [250] }).toBeGreaterThanOrEqual(2);
      const gap = sent[1]!.at - first.at;
      expect(gap, 'comes 9 to 16 s after the first answer').toBeGreaterThanOrEqual(9000);
      expect(gap).toBeLessThanOrEqual(16_000);
      await expect.poll(() => answers.length, { message: 'the route kept the second answer', timeout: LOADED_MS }).toBe(2);
      const second = answers[1]!;
      expect(second.body.code, 'the server issued another code').not.toBe(first.body.code);
      await expectCode(page, second.body.code, LOADED_MS);
      await expect(card.getByRole('link'), 'the old code is gone from the link').not.toHaveAttribute('href', new RegExp(first.body.code));
      await expect(composer, 'the composer still has focus').toBeFocused();
      await expect(composer, 'and the draft').toHaveValue(draft);
      await expect(card.locator('.caption'), 'the countdown reads 1 min for an expiry in the past').toHaveText('New code in 1 min');

      // A past expiry, with focus on the link: no request for 9 s after the second one (the spacing counts from a request), then one.
      await link.focus();
      await until(sent[1]!.at + 8500);
      expect(sent.length, 'no third request within 8.5 s of the second request').toBe(2);
      await expect.poll(() => sent.length, { message: 'the third request for a code', timeout: 12_000, intervals: [250] }).toBe(3);
      const gap2 = sent[2]!.at - sent[1]!.at;
      expect(gap2, 'comes 9 to 16 s after the second request').toBeGreaterThanOrEqual(9000);
      expect(gap2).toBeLessThanOrEqual(16_000);
      await expect.poll(() => answers.length, { message: 'the route kept the third answer', timeout: LOADED_MS }).toBe(3);
      const third = answers[2]!;
      await expectCode(page, third.body.code, LOADED_MS);
      await expect(card.getByRole('link'), 'the focused link keeps its focus with the new code').toBeFocused();
      expect(await page.evaluate(() => document.activeElement?.getAttribute('href') ?? ''), 'the focused element is the card\'s link with code 3').toBe(
        `https://t.me/${BOT}?start=${third.body.code}`,
      );
      await expect(composer, 'the draft is unchanged').toHaveValue(draft);
      await until(sent[1]!.at + 16_000);
      expect(sent.length, 'three requests in all').toBe(3);
      expect(answers.map((one) => one.status), 'all answered 200').toEqual([200, 200, 200]);
      const n = await minutesOf(page, third.body.expiresAt);
      expect(n, 'the third answer passes through, so about 9 min are left').toBe(9);
      await expect(card.locator('.caption'), 'and the card says so').toHaveText(`New code in ${n} min`);

      // The codes stay in the card: no console line, storage entry, address, title or announcement of the page holds one.
      const kept = await page.evaluate(() =>
        [localStorage, sessionStorage]
          .flatMap((store) => Object.keys(store).map((key) => `${key}=${store.getItem(key) ?? ''}`))
          .concat(location.href, document.title)
          .join('\n'),
      );
      const spoken = (await announcedTexts(page)).join('\n');
      for (const [i, one] of answers.entries()) {
        expect(consoled.some((line) => line.includes(one.body.code)), `no console line holds code ${i + 1}`).toBe(false);
        expect(kept.includes(one.body.code), `no storage entry, the address or the title holds code ${i + 1}`).toBe(false);
        expect(spoken.includes(one.body.code), `no announcement holds code ${i + 1}`).toBe(false);
      }

      // The server side of the codes, and the search of the production for every code.
      const codes = answers.map((one) => one.body.code).join(',');
      const searched = await fixture(`Codes(${quoted(mark)}, ${quoted('ocutalon')}, ${quoted(codes)}, ${quoted(third.body.expiresAt)})`);
      expect(searched.reason, 'the session has the last code\'s hash only, and no code is in any store').toBe('');
      passed = true;
    } finally {
      let finished = { reason: '' };
      try {
        finished = await fixture(`Finish(${quoted(saved)})`);
      } finally {
        await setTelegramIncluded(was);
      }
      if (finished.reason !== '') {
        if (passed) expect(finished.reason, 'the fixture puts everything back').toBe('');
        else test.info().annotations.push({ type: 'finish', description: finished.reason });
      }
    }
  });

  /**
   * T4: the card from changed snapshots, with the seam on and no TelegramIn (the server's state is off): "Refused while the server is off"
   * and "Paired". Each case answers /state with a changed copy and reloads once. Then the code route itself answers, with no server
   * behind it, under the on and unpaired copy: a failure (500) shows nothing rather than the off card, an expiry two minutes out counts
   * down, and an expiry an hour out is held ten minutes at most.
   */
  test('T4: a refused code shows the off card and asks no more, a paired session asks for no code, and made-up answers keep the card\'s rules', { tag: '@floor' }, async ({ page }) => {
    const was = await setTelegramIncluded(1);
    try {
      const sent = recordRequests(page);
      const statuses: number[] = [];
      page.on('response', (response) => {
        if (response.request().method() === 'POST' && new URL(response.url()).pathname === CODE_PATH) statuses.push(response.status());
      });
      await signInReadmeLoaded(page);
      await expect(cardOf(page).locator('[data-state="not-set-up"]'), 'the server\'s own state is off, as the cases need: the card is not set up').toHaveCount(1, {
        timeout: LOADED_MS,
      });
      expect(sent.length, 'and asks for no code').toBe(0);

      /** Answers /state with the on copy of the Telegram block, with no pause, paired or not. */
      const onSnapshot = (paired: boolean, displayName: string): Promise<void> =>
        changeSnapshot(page, (snapshot) => {
          snapshot['telegram'] = {
            ...(snapshot['telegram'] as Record<string, unknown>),
            included: true,
            state: 'on',
            botUserName: 'ocutalon_ci_bot',
            paired,
            displayName,
            pausedUntil: '',
          };
          const others = (snapshot['status'] as Array<{ condition?: string }>).filter((member) => member.condition !== 'telegramPaused');
          snapshot['status'] = [...others, { condition: 'telegramPaused', active: false }];
        });

      const cases = [
        { label: 'refused', paired: false, displayName: '' },
        { label: 'paired', paired: true, displayName: 'Zz' },
      ] as const;
      for (const one of cases) {
        await page.unrouteAll({ behavior: 'ignoreErrors' });
        sent.length = 0;
        statuses.length = 0;
        await onSnapshot(one.paired, one.displayName);
        await page.reload();
        await loaded(page);
        const card = cardOf(page);
        await expect(card, `${one.label}: the Telegram card is in the rail`).toHaveCount(1);
        if (!one.paired) {
          await expect(card.locator('[data-state="not-set-up"]'), `${one.label}: the card is not set up`).toHaveCount(1, { timeout: LOADED_MS });
          await expect.poll(() => statuses, { message: `${one.label}: the one request was refused`, timeout: LOADED_MS }).toEqual([409]);
          await expect.poll(async () => plain(await card.innerText()), { message: `${one.label}: the card says so` }).toMatch(/^Telegram not set up How to set it up/);
        }
        await page.waitForTimeout(3000);
        if (one.paired) await expect(card.locator('[data-state]'), `${one.label}: the card shows no state of its own yet`).toHaveCount(0);
        expect(sent.length, one.paired ? 'paired: no request for a code' : 'refused: one request, and no second within 3 s').toBe(one.paired ? 0 : 1);
        await expect(card.getByRole('img'), `${one.label}: no QR code`).toHaveCount(0);
        await expect(card.getByRole('link', { name: /Open in Telegram/ }), `${one.label}: no pairing link`).toHaveCount(0);
        expect(plain(await card.innerText()), `${one.label}: no scan line or countdown`).not.toMatch(/Scan with|Open in Telegram|New code in/);
      }

      /** Answers the code request with no server behind it, under the on and unpaired copy, and reloads once. */
      const madeUp = async (label: string, answer: () => { status: number; json: unknown }): Promise<void> => {
        await page.unrouteAll({ behavior: 'ignoreErrors' });
        sent.length = 0;
        await onSnapshot(false, '');
        await page.route(CODE_ROUTE, (route) => route.fulfill(answer()));
        await page.reload();
        await loaded(page);
        await expect.poll(() => sent.length, { message: `${label}: one request for a code`, timeout: LOADED_MS }).toBe(1);
      };
      const caption = cardOf(page).locator('.caption');

      await madeUp('failed', () => ({ status: 500, json: { error: 'internal' } }));
      await page.waitForTimeout(ONE_UPDATE_MS);
      await expect(cardOf(page).locator('[data-state]'), 'failed: the card shows nothing, not the off card').toHaveCount(0);
      expect(sent.length, 'failed: and asks again only later').toBe(1);

      await madeUp('ticking', () => ({ status: 200, json: { code: 'zzMadeUpCodeTicking000', expiresAt: inMs(122_000) } }));
      await expect(caption, 'ticking: two minutes left').toHaveText('New code in 2 min', { timeout: LOADED_MS });
      await expect(caption, 'ticking: and the countdown counts down while the page is open').toHaveText('New code in 1 min', { timeout: 5000 });

      await madeUp('capped', () => ({ status: 200, json: { code: 'zzMadeUpCodeCapped0000', expiresAt: inMs(3_600_000) } }));
      await expect(caption, 'capped: an expiry an hour out is held ten minutes at most').toHaveText('New code in 9 min', { timeout: LOADED_MS });
    } finally {
      await setTelegramIncluded(was);
    }
  });
});

notBuilt('the page pairs a Telegram chat: a code and its QR code make the chat paired, and the paired chat shows its name', '12.4');
