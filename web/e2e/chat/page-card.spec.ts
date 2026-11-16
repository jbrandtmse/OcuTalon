import { expect, test, type Locator, type Page } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { CARD_MS, loadedAfter, unique } from '../support/floor';
import { cleanFixtureRows, dropPage, fixtureUser, seedPage } from '../support/iris';

/**
 * Story 24.3a, the page card (AC5, AC6), in a real browser against a real stack. The case signs in as the notice fixture user (OCUTALON_NOTICE_USER) and makes the page of that user's
 * own session (seedPage: an incident, a Data.Page row whose person is the user, and the page Notification that the real Notify routes to the real WebChatOut). It checks that the chat
 * shows the page card with the page's text and Got it, that pressing Got it (the web route, which submits AckPage) shows "Marked as handled at {time}" in its place, and that a reload keeps that line.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** The line that an acknowledged page ends with, in the browser's zone (UTC here): "Marked as handled at 14:12". */
const HANDLED = /^Marked as handled at \d{1,2}:\d{2}/;

/** The page card whose text holds the marker. */
const cardOf = (page: Page, marker: string): Locator => page.locator('app-chat-panel app-notice-card').filter({ hasText: marker });

/** Signs the notice user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('NOTICE');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('textbox', { name: 'Message OcuTalon' })).toBeVisible();
}

/** P1: a page of the user's own session is a card with the page text and Got it; the press shows the handled line, and a reload keeps it. */
test('P1: a page card shows its text and Got it, the press marks it handled, and a reload keeps the line', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const cause = unique('P1');
  const seeded = await seedPage(user, { cause });
  try {
    const card = cardOf(page, cause);
    await expect(card, 'the page is one card in the chat').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.text'), 'its text is the page text with the cause').toContainText(`failed in the Zz.Production production since`);
    await expect(card.locator('.text'), 'and the cause').toContainText(cause);
    await expect(card.locator('.why'), 'then the page\'s Why now line').toHaveText(/^Why now: you're on call for OcuTalon\./);
    await expect(card.locator('app-decision-strip'), 'there is no decision strip').toHaveCount(0);
    await expect(card.getByRole('button', { name: 'This was noise' }), 'and no noise control').toHaveCount(0);
    const gotIt = card.getByRole('button', { name: 'Got it', exact: true });
    await expect(gotIt, 'the card has Got it').toHaveCount(1);

    const sent = page.waitForRequest((request) => request.method() === 'POST' && new URL(request.url()).pathname.endsWith(`/decisions/${seeded.page}/got-it`));
    await gotIt.click();
    expect((await sent).postDataJSON(), 'the web press sends no channel').toEqual({});
    const assertHandled = async (when: string): Promise<void> => {
      await expect(card.locator('[data-part="handled"]'), `${when}: the card says the page was handled`).toHaveText(HANDLED);
      await expect(gotIt, `${when}: the card has no Got it`).toHaveCount(0);
    };
    await assertHandled('after the press');
    await page.reload();
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    await expect(card, 'after the reload the page is still one card').toHaveCount(1);
    await assertHandled('after the reload');
  } finally {
    await dropPage(seeded.page);
    await cleanFixtureRows([seeded.incident]);
  }
});
