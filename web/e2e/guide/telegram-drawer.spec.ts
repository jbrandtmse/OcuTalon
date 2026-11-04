import { expect, test, type Locator, type Page } from '@playwright/test';

import { signInReadmeLoaded } from '../support/floor';
import { chk, irisScript, quoted, setTelegramIncluded } from '../support/iris';

/**
 * The demo guide's Telegram row in the drawer band (Story 12.10), on the sign-in stack with the README account and the real chain: the
 * fixture (TelegramPageFixture) starts TelegramIn against the CI mock and its dummy token, so the server's guide view says
 * `telegramRow` for the unpaired README session that watches nothing. The token is never printed or compared. Each test turns the
 * release's Telegram on, starts the fixture, and puts both back in `finally`.
 * - D1 (1100x720): the row names the Status button and carries a Show me; Show me opens the drawer with the rail focused and the
 *   unpaired card in view; a second press keeps it open; Esc closes it with focus on the Status button; a resize to 1400 takes the
 *   button away and focus goes to the prompt bar.
 * - D2 (1400x720): the original line, no button in the row, no Status button, and the card in the visible rail.
 * - D3 (900x720, then 1100 and 1500 wide): the stacked and the wide band keep the original line with no button in the row; the drawer
 *   band between them shows Show me, so the 1500 check can pass only on the row rendered for that width.
 */
const FIXTURE = '##class(OcuTalon.Test.Channel.TelegramPageFixture)';
const BOT = 'ocutalon_drawer_bot';

const HINT = 'Optional: press Status at the top of the page, then scan the QR code in the Telegram card to get the notice on your own phone.';
const ORIGINAL = 'Optional: scan the QR code in the Telegram card to get the notice on your own phone.';
const QR_ALT = 'QR code that opens OcuTalon in Telegram to pair this session';
const LINK_NAME = 'Open in Telegram (opens Telegram)';

const guideOf = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const rowOf = (page: Page): Locator => guideOf(page).locator('.prompt .telegram');
const barOf = (page: Page): Locator => guideOf(page).locator('.prompt');
const railOf = (page: Page): Locator => page.locator('section.rail#status-region');
const statusButton = (page: Page): Locator => page.locator('button.status-button');
const cardOf = (page: Page): Locator => railOf(page).locator('app-telegram-card [data-state="unpaired"]');

/** Calls one method of the fixture in an IRIS script and returns its reason ("" when it worked) with the values of its output variables. */
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

/** Runs the body with Telegram on through the fixture, and puts the fixture and the release's setting back afterwards. */
async function withTelegram(body: () => Promise<void>): Promise<void> {
  const was = await setTelegramIncluded(1);
  let saved = '';
  let passed = false;
  try {
    const started = await fixture(`Start(.saved, ${quoted(BOT)})`, ['saved']);
    saved = started.values['saved'] ?? '';
    expect(started.reason, 'TelegramIn starts against the mock').toBe('');
    await body();
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
}

type Box = { x: number; y: number; width: number; height: number };

const boxOf = async (locator: Locator): Promise<Box> => {
  const box = await locator.boundingBox();
  expect(box, 'the element has a box').not.toBeNull();
  return box as Box;
};

const within = (inner: Box, outer: Box): boolean =>
  inner.x >= outer.x - 0.5 && inner.y >= outer.y - 0.5 && inner.x + inner.width <= outer.x + outer.width + 0.5 && inner.y + inner.height <= outer.y + outer.height + 0.5;

/** True when the element at the centre of the locator's box is inside the Telegram card (nothing covers it). */
const hitsCard = (locator: Locator): Promise<boolean> =>
  locator.evaluate((element) => {
    const rect = element.getBoundingClientRect();
    const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2);
    const card = element.closest('app-telegram-card');
    return hit !== null && card !== null && card.contains(hit);
  });

test.describe('the guide\'s Telegram row and the status drawer', () => {
  test('D1: at 1100px the row names Status and Show me opens the drawer with the Telegram card in view', async ({ page }) => {
    test.setTimeout(180_000);
    await withTelegram(async () => {
      await page.setViewportSize({ width: 1100, height: 720 });
      await signInReadmeLoaded(page);
      const row = rowOf(page);
      await expect(row, 'the row shows for the unpaired session that watches nothing').toHaveCount(1);
      await expect(railOf(page), 'the rail is a closed drawer').toBeHidden();
      await expect(statusButton(page)).toHaveAttribute('aria-expanded', 'false');
      await expect(row.locator('span').first(), 'the row reads the hint').toHaveText(HINT);
      const showMe = row.getByRole('button', { name: 'Show me' });
      await expect(showMe, 'with one Show me').toHaveCount(1);
      await expect(showMe, 'described by the hint').toHaveAccessibleDescription(HINT);
      expect(within(await boxOf(showMe), await boxOf(guideOf(page))), 'the button is not clipped by the guide').toBe(true);
      expect(await row.evaluate((element) => element.scrollWidth <= element.clientWidth + 1), 'the row does not overflow').toBe(true);

      await showMe.click();
      await expect(statusButton(page)).toHaveAttribute('aria-expanded', 'true');
      await expect(railOf(page)).toBeVisible();
      await expect(railOf(page), 'the rail takes focus').toBeFocused();
      const card = cardOf(page);
      await expect(card, 'the card is unpaired').toHaveCount(1);
      const qr = card.getByRole('img', { name: QR_ALT });
      const link = card.getByRole('link', { name: LINK_NAME });
      await expect(qr, 'the QR code shows').toBeVisible();
      await expect(link, 'and the link').toBeVisible();
      await expect(link).toBeEnabled();
      await expect
        .poll(async () => {
          const viewport = page.viewportSize() as { width: number; height: number };
          const box = await boxOf(card);
          return within(box, { x: 0, y: 0, width: viewport.width, height: viewport.height }) && within(box, await boxOf(railOf(page)));
        }, { message: 'the card lies within the viewport and the rail' })
        .toBe(true);
      expect(await hitsCard(qr), 'nothing covers the QR code').toBe(true);
      expect(await hitsCard(link), 'nothing covers the link').toBe(true);

      await showMe.click();
      await expect(statusButton(page), 'a second press keeps the drawer open').toHaveAttribute('aria-expanded', 'true');
      await expect(railOf(page)).toBeVisible();
      await expect(railOf(page), 'and focuses the rail again').toBeFocused();

      await page.keyboard.press('Escape');
      await expect(statusButton(page)).toHaveAttribute('aria-expanded', 'false');
      await expect(railOf(page)).toBeHidden();
      await expect(statusButton(page), 'focus goes to the Status button').toBeFocused();
      await expect(showMe, 'Show me stays').toBeVisible();

      await showMe.focus();
      await expect(showMe).toBeFocused();
      await page.setViewportSize({ width: 1400, height: 720 });
      await expect(row.getByRole('button'), 'Show me is gone in the wider band').toHaveCount(0);
      await expect(barOf(page), 'focus goes to the prompt bar').toBeFocused();
    });
  });

  test('D2: at 1400px the row is the original line, with no button and no Status button, and the card is in the rail', async ({ page }) => {
    test.setTimeout(180_000);
    await withTelegram(async () => {
      await page.setViewportSize({ width: 1400, height: 720 });
      await signInReadmeLoaded(page);
      const row = rowOf(page);
      await expect(row, 'the row shows').toHaveCount(1);
      await expect(row).toHaveText(ORIGINAL);
      await expect(row.getByRole('button'), 'with no button').toHaveCount(0);
      await expect(statusButton(page), 'no Status button').toHaveCount(0);
      await expect(railOf(page), 'the rail shows').toBeVisible();
      await expect(cardOf(page), 'with the unpaired card').toBeVisible();
    });
  });

  test('D3: below 1024px and at 1440px and wider the row is the original line with no button', async ({ page }) => {
    test.setTimeout(180_000);
    await withTelegram(async () => {
      await page.setViewportSize({ width: 900, height: 720 });
      await signInReadmeLoaded(page);
      const row = rowOf(page);
      await expect(row, 'the row shows').toHaveCount(1);
      await expect(row, 'the stacked band reads the original line').toHaveText(ORIGINAL);
      await expect(row.getByRole('button'), 'with no button').toHaveCount(0);
      await page.setViewportSize({ width: 1100, height: 720 });
      await expect(row.getByRole('button'), 'the drawer band between them has Show me, so the next check reads a re-rendered row').toHaveCount(1);
      await page.setViewportSize({ width: 1500, height: 720 });
      await expect(row, 'the wide band reads the original line').toHaveText(ORIGINAL);
      await expect(row.getByRole('button'), 'with no button').toHaveCount(0);
    });
  });
});
