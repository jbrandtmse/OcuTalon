import { expect, test, type Locator, type Page } from '../support/fixtures';

import { changeSnapshot } from '../support/api';
import { signInReadmeLoaded } from '../support/floor';

/**
 * The matrix rows of Story 12.10 that need a controlled guide view (QA gaps beside telegram-drawer.spec.ts, which drives the real
 * chain). The page's /state answers a guide that each case names, and the case pushes a later `guide.state` through the page's own poll,
 * so no Telegram bot, no fixture and no server write is involved; the stack is the sign-in unit's, with the README account.
 * - V1 (1100x720): the user closes the drawer with the Status button, and with Esc; each time focus goes to the Status button, the hint
 *   and Show me stay, and Show me opens the drawer again with the rail focused.
 * - V2 (1100x720): Show me holds focus and the server's view drops `telegramRow` (the row leaves): focus goes to the prompt bar.
 * - V3: the band edges. Show me is there at 1024 and 1279 and gone at 1023 and 1280. Each resize changes what the row shows, so each
 *   check can pass only on the row rendered for its width.
 * - V4: a view with `telegramRow` false shows no Telegram row at 900, 1024, 1100, 1279, 1400 and 1500, which is what the online demo's
 *   Telegram-off view is (Test.Demo.Guide pins the server side).
 */
const HINT = 'Optional: press Status at the top of the page, then scan the QR code in the Telegram card to get the notice on your own phone.';
const ORIGINAL = 'Optional: scan the QR code in the Telegram card to get the notice on your own phone.';

/** A blank guide view (no step done); `over` replaces fields of it. */
const guideOf = (over: Record<string, unknown> = {}): Record<string, unknown> => ({
  runEpoch: 1,
  step: 1,
  finished: false,
  steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: false })),
  breakFeed: { active: false, reason: 'not_watching' },
  step4Variant: 'unpaired',
  telegramRow: false,
  ...over,
});

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const barOf = (page: Page): Locator => guideRegion(page).locator('.prompt');
const rowOf = (page: Page): Locator => barOf(page).locator('.telegram');
const showMeOf = (page: Page): Locator => rowOf(page).getByRole('button', { name: 'Show me' });
const railOf = (page: Page): Locator => page.locator('section.rail#status-region');
const statusButton = (page: Page): Locator => page.locator('button.status-button');

/** Answers the page's /state with the guide that `holder.guide` names, and returns a function that adds a `guide.state` to the next real poll. */
async function serve(page: Page, holder: { guide: Record<string, unknown> }): Promise<(guide: Record<string, unknown>) => Promise<void>> {
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = holder.guide;
  });
  const queue: Array<Record<string, unknown>> = [];
  let queued = 0;
  let served = 0;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    const next = queue.shift();
    if (next === undefined) {
      await route.fulfill({ response });
      return;
    }
    const body = (await response.json()) as { events: Array<Record<string, unknown>> };
    let seq = Number(new URL(route.request().url()).searchParams.get('after'));
    for (const event of body.events) {
      if (event['stream'] === 'session') seq = Math.max(seq, Number(event['seq']));
    }
    body.events.push({ seq: seq + 1, stream: 'session', ts: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), type: 'guide.state', payload: next });
    await route.fulfill({ response, json: body });
    served += 1;
  });
  return async (guide) => {
    queued += 1;
    const target = queued;
    queue.push(guide);
    await expect.poll(() => served, { message: 'a poll carried the guide.state' }).toBeGreaterThanOrEqual(target);
  };
}

/** Opens the page at the width with the guide that the holder names. */
async function openAt(page: Page, width: number, holder: { guide: Record<string, unknown> }): Promise<(guide: Record<string, unknown>) => Promise<void>> {
  const push = await serve(page, holder);
  await page.setViewportSize({ width, height: 720 });
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  return push;
}

test.describe('the guide\'s Telegram row and the status drawer, with a controlled view', () => {
  test('V1: closing the drawer by the Status button or Esc keeps the hint and Show me, and Show me opens it again', async ({ page }) => {
    await openAt(page, 1100, { guide: guideOf({ telegramRow: true }) });
    await expect(rowOf(page).locator('span').first()).toHaveText(HINT);
    await expect(railOf(page), 'the drawer starts closed').toBeHidden();

    await showMeOf(page).click();
    await expect(statusButton(page)).toHaveAttribute('aria-expanded', 'true');
    await expect(railOf(page)).toBeFocused();

    await statusButton(page).click();
    await expect(statusButton(page), 'the Status button closes the drawer').toHaveAttribute('aria-expanded', 'false');
    await expect(railOf(page)).toBeHidden();
    await expect(statusButton(page), 'and keeps focus').toBeFocused();
    await expect(rowOf(page).locator('span').first(), 'the hint stays').toHaveText(HINT);
    await expect(showMeOf(page), 'Show me stays').toBeVisible();

    await showMeOf(page).click();
    await expect(statusButton(page), 'Show me opens it again').toHaveAttribute('aria-expanded', 'true');
    await expect(railOf(page)).toBeVisible();
    await expect(railOf(page)).toBeFocused();

    await page.keyboard.press('Escape');
    await expect(statusButton(page)).toHaveAttribute('aria-expanded', 'false');
    await expect(statusButton(page), 'Esc puts focus on the Status button').toBeFocused();
    await expect(showMeOf(page), 'Show me stays after Esc').toBeVisible();

    await showMeOf(page).click();
    await expect(statusButton(page), 'and opens it a third time').toHaveAttribute('aria-expanded', 'true');
    await expect(railOf(page)).toBeFocused();
  });

  test('V2: when the row leaves while Show me holds focus, focus goes to the prompt bar', async ({ page }) => {
    const push = await openAt(page, 1100, { guide: guideOf({ telegramRow: true }) });
    await expect(showMeOf(page)).toHaveCount(1);
    await showMeOf(page).focus();
    await expect(showMeOf(page)).toBeFocused();

    await push(guideOf({ telegramRow: false }));
    await expect(rowOf(page), 'the row left').toHaveCount(0);
    await expect(barOf(page), 'focus went to the prompt bar').toBeFocused();
  });

  test('V3: the drawer band is 1024 to 1279px: Show me at its edges, none just outside', async ({ page }) => {
    await openAt(page, 1024, { guide: guideOf({ telegramRow: true }) });
    await expect(showMeOf(page), '1024px').toHaveCount(1);
    await expect(rowOf(page).locator('span').first()).toHaveText(HINT);
    await page.setViewportSize({ width: 1023, height: 720 });
    await expect(rowOf(page), '1023px reads the original line').toHaveText(ORIGINAL);
    await expect(showMeOf(page), 'with no button').toHaveCount(0);
    await page.setViewportSize({ width: 1279, height: 720 });
    await expect(showMeOf(page), '1279px').toHaveCount(1);
    await expect(rowOf(page).locator('span').first()).toHaveText(HINT);
    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(rowOf(page), '1280px reads the original line').toHaveText(ORIGINAL);
    await expect(showMeOf(page), 'with no button').toHaveCount(0);
  });

  test('V4: a view without telegramRow shows no Telegram row at any band', async ({ page }) => {
    await openAt(page, 900, { guide: guideOf({ telegramRow: false }) });
    await expect(barOf(page), 'the prompt bar shows').toHaveCount(1);
    for (const width of [900, 1024, 1100, 1279, 1400, 1500]) {
      await page.setViewportSize({ width, height: 720 });
      await expect(rowOf(page), `${width}px: no row`).toHaveCount(0);
      await expect(guideRegion(page).getByText('Telegram card'), `${width}px: no hint`).toHaveCount(0);
    }
  });
});
