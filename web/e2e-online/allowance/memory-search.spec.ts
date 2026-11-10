import { expect, test, type Locator, type Page } from '../../e2e/support/fixtures';

import { MESSAGES, post } from '../../e2e/support/api';
import { loadedAfter, railOf } from '../../e2e/support/floor';
import { allowanceRow, epochOf, removeSession, seedAllowance, signInFromSplash, signOutGroup, turnRowsOf } from '../support';

/**
 * Story 41.13 (DW-1031, AD-20), the Memory card's search against the message allowance (MS1). The project runs on its own online-demo throwaway with the message
 * allowance at 50. Each submitted search counts as one of the session's messages, in CommandsIn, with no Turn and no window of its own; the list and the pinned read
 * never count. The case signs out of the whole sign-in group and removes the rows it made in `finally`. The texts are written out here, as the independent oracle
 * of the page's own.
 * - MS1: a new session holds 49 current entries. One search from the card is answered 200 (or 503 search_busy, which still counts) and the count is 50; the next
 *   is answered 429 with the messages route's body (the error, retryAt, limit) and the card shows the served text; it recorded no Turn and opened no window. A chat
 *   message is then 429 too (the shared count), it is the first refusal of the window (one allowance notice card, the row's window), and the run leaves exactly one
 *   refused Turn: the chat message's.
 */
test.describe.configure({ timeout: 240_000 });

const SERVED = "You've used this session's 50 messages for the hour.";
const NOTICE = /You've used this session's 50 messages for the hour\. You can send more/;
const ITEMS = /\/api\/v1\/memory\/items(\?|$)/;

const card = (page: Page): Locator => railOf(page).locator('app-memory-card');
const memoriesTab = (page: Page): Locator => card(page).getByRole('tab', { name: 'All memories', exact: true });
const memoriesPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'All memories', exact: true });
const searchBox = (page: Page): Locator => memoriesPanel(page).getByRole('searchbox', { name: 'Search your memories', exact: true });

/** The answer of the card's next search (a request of the items route with q). */
function searchAnswer(page: Page) {
  return page.waitForResponse((response) => ITEMS.test(response.url()) && response.url().includes('q=') && response.request().method() === 'GET');
}

test('MS1: each search counts as a message, the one past the limit is a 429 with the messages body and no Turn, and the chat is refused next', async ({ page }) => {
  let epoch = '';
  try {
    await loadedAfter(page, () => signInFromSplash(page));
    epoch = await epochOf(page);
    await seedAllowance(epoch, 49, 60);
    expect((await allowanceRow(epoch)).times, 'the session holds 49 entries').toBe(49);

    const listed = page.waitForResponse((response) => ITEMS.test(response.url()) && !response.url().includes('q=') && response.request().method() === 'GET');
    await memoriesTab(page).click();
    await expect(searchBox(page)).toBeVisible();
    expect((await listed).status(), 'opening All memories reads the list').toBe(200);
    expect((await allowanceRow(epoch)).times, 'and the list counts nothing').toBe(49);

    const first = searchAnswer(page);
    await searchBox(page).fill('zz allowance one');
    await searchBox(page).press('Enter');
    const firstStatus = (await first).status();
    expect([200, 503], 'the search under the limit is answered 200 (or 503 search_busy, which still counts)').toContain(firstStatus);
    expect((await allowanceRow(epoch)).times, 'and it counted: 50 entries').toBe(50);

    const second = searchAnswer(page);
    await searchBox(page).fill('zz allowance two');
    await searchBox(page).press('Enter');
    const refused = await second;
    expect(refused.status(), 'the search past the limit is a 429').toBe(429);
    const body = (await refused.json()) as { error: { code: string; message: string }; retryAt: string; limit: number };
    expect(Object.keys(body), "with the messages route's members").toEqual(['error', 'retryAt', 'limit']);
    expect([body.error.code, body.error.message, body.limit], 'the code allowance, the served text and the limit 50').toEqual(['allowance', SERVED, 50]);
    expect(Date.parse(body.retryAt), 'retryAt is ahead').toBeGreaterThan(Date.now());
    await expect(memoriesPanel(page).getByText(SERVED, { exact: true }), 'the card shows the served text').toBeVisible();
    const row = await allowanceRow(epoch);
    expect([row.times, row.until], 'the refused search added no entry and opened no window').toEqual([50, '']);
    expect((await turnRowsOf(epoch)).filter((turn) => turn.state === 'refused'), 'and recorded no Turn').toEqual([]);

    const chat = await post(page.request, MESSAGES, { clientId: `zz-ms1-${epoch.slice(0, 6)}`, text: 'zz chat after the searches', fromGuide: false });
    expect(chat.status(), 'a chat message is then refused too: the count is shared').toBe(429);
    const chatBody = (await chat.json()) as { error: { code: string }; retryAt: string };
    expect(chatBody.error.code).toBe('allowance');
    await expect(page.locator('app-notice-card').filter({ hasText: NOTICE }), "the chat's refusal is the first of the window: its one notice card shows").toHaveCount(1, { timeout: 30_000 });
    expect((await allowanceRow(epoch)).until, "the row's window opened with the chat's refusal").toBe(chatBody.retryAt);
    const refusedTurns = (await turnRowsOf(epoch)).filter((turn) => turn.state === 'refused');
    expect(
      refusedTurns.map((turn) => turn.text),
      "the run's only refused Turn is the chat message's",
    ).toEqual(['zz chat after the searches']);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});
