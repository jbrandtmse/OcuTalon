import { expect, test, type Locator, type Page } from '@playwright/test';

import { changeSnapshot } from '../support/api';
import { signInReadmeLoaded } from '../support/floor';
import { chk, irisScript, quoted, setTelegramIncluded } from '../support/iris';
import { plain, tokenColor } from '../support/page';
import { notBuilt } from './not-built';

/**
 * UJ-1 step 1, the Telegram part: the page's Telegram card, shown only once a release includes Telegram. Lane A owns this file from Epic 12
 * (AD-29). It holds:
 * - Story 12.8's two tests: the card's paused state, from a real 409 of TelegramIn against the CI mock (T1: the banner and the card, a reload,
 *   the resume and the clear, and the search of the page for the bot token) and from a changed snapshot (T2: the card's states);
 * - Story 12.4's pairing, still a part that no story has built: Story 12.4 replaces the declaration at the end of this file with the real
 *   test. web/scripts/demo-path-summary.mjs counts the file as a part of step 1 (the `page` in the file name), skipped with the story that
 *   owns it.
 *
 * The browser runs in Asia/Kolkata with the en-GB locale, so a UTC time reads five and a half hours later, with an unpadded 24-hour hour:
 * 12:00 UTC is 17:30. The oracle for a time is `kolkata`, written here from the UTC clock and not from the page's own format.
 * Both tests are tagged @floor, like step 1's other tests: they need a stack and a browser, so the no-stack run of the real specs
 * (scripts/demo-path-summary.test.mjs) leaves them out, and in the demo-path unit a failure of either fails the unit.
 * The tests run on fresh throwaway stacks and in CI only, against the CI mock and its dummy token (Rule 21): no real bot, no call to the
 * public Telegram API. The token is compared only as a boolean, and no text of this file holds it.
 */
test.describe('the Telegram card is paused while Telegram is paused (Story 12.8)', () => {
  test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' });

  /** A poll that a routed handler is still answering when a test ends must not fail the next test. */
  test.afterEach(async ({ page }) => {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

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

  /** Waits until the page has applied the event of this Seq on the instance stream. */
  async function appliedInstance(page: Page, seq: number): Promise<void> {
    await expect
      .poll(async () => Number(await mainOf(page).getAttribute('data-instance-seq')), { message: `the page applied Seq ${seq} of the instance stream`, timeout: APPLIED_MS })
      .toBeGreaterThanOrEqual(seq);
  }

  /**
   * T1: the real pause, end to end. TelegramIn runs against the CI mock, the mock answers its poll with a 409, and the chain TelegramIn, the
   * telegramPaused mark, StatusMonitor and /state shows the banner and the paused card; a reload shows them again; the resume deletes the
   * mark and both leave; and the dummy bot token is nowhere in the page or in what the server sent it (NFR-11, AD-14).
   */
  test('T1: a 409 of TelegramIn pauses the banner and the card, a reload keeps them, the resume clears them, and the token is nowhere', { tag: '@floor' }, async ({ page }) => {
    test.setTimeout(240_000);
    const was = await setTelegramIncluded(1);
    let saved = '';
    let passed = false;
    try {
      const token = (await irisScript([`Write !,"CHK|token|",${FIXTURE}.Token()`].join('\n')).then((lines) => chk(lines, 'token'))) ?? '';
      expect(token.length > 0, 'the stack has the CI dummy token').toBe(true);
      const bodies: Array<Promise<string>> = [];
      page.on('response', (response) => {
        if (new URL(response.url()).pathname.startsWith('/ocutalon/')) bodies.push(response.text().catch(() => ''));
      });

      const started = await fixture('Start(.saved)', ['saved']);
      saved = started.values['saved'] ?? '';
      expect(started.reason, 'TelegramIn starts against the mock').toBe('');

      // The baseline: the card is in the rail, and there is no pause on the page.
      await signInReadmeLoaded(page);
      await expect(cardOf(page), 'the release includes Telegram, so its card is in the rail').toHaveCount(1);
      await expect(bannerOf(page), 'no paused banner before the 409').toHaveCount(0);
      await expectNotPausedCard(page, ONE_UPDATE_MS);

      // The onset: the 409 reaches StatusMonitor's event and then the page.
      const conflict = await fixture('Conflict(.until, .onset)', ['until', 'onset']);
      expect(conflict.reason, 'the 409 pauses TelegramIn and StatusMonitor publishes the onset').toBe('');
      const until = conflict.values['until'] ?? '';
      const time = kolkata(until);
      expect(until, 'the mark is a UTC time').toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
      await appliedInstance(page, Number(conflict.values['onset']));
      await expectBanner(page, time, ONE_UPDATE_MS);
      await expectPausedCard(page, time, ONE_UPDATE_MS);
      const pausedHtml = await page.content();

      // A reload shows the same, from /state.
      await page.reload();
      await loaded(page);
      await expectBanner(page, time, APPLIED_MS);
      await expectPausedCard(page, time, APPLIED_MS);

      // The resume and the clear.
      const resumed = await fixture(`Resume(2, ${Number(conflict.values['onset'])}, .clear)`, ['clear']);
      expect(resumed.reason, 'the first 200 deletes the mark and StatusMonitor publishes the clear').toBe('');
      await appliedInstance(page, Number(resumed.values['clear']));
      await expect(bannerOf(page), 'the banner leaves within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
      await expectNotPausedCard(page, ONE_UPDATE_MS);
      const clearedHtml = await page.content();

      // The token search: the page's HTML at the pause and after the clear, and every response under /ocutalon/ that the page received.
      expect(pausedHtml.includes(bannerText(time)), 'the HTML at the pause holds the banner text (the scan sees what the store holds)').toBe(true);
      expect(pausedHtml.includes(token), 'the HTML at the pause holds no bot token').toBe(false);
      expect(clearedHtml.includes('app-telegram-card'), 'the HTML after the clear holds the Telegram card (the scan sees what the store holds)').toBe(true);
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

notBuilt('the page pairs a Telegram chat: a code and its QR code make the chat paired, and the paired chat shows its name', '12.4');
