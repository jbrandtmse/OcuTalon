import { expect, test, type Locator, type Page, type Response, type Route } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { holdPolls } from '../support/api';
import { noticeOnPhone, phoneOf, raise, refOf } from '../support/approvals';
import { dropPhone } from '../support/devices';
import { CARD_MS, composerOf, inMs, loadedAfter, mainOf, railOf } from '../support/floor';
import { cleanFixtureRows, fixtureUser, readApproval } from '../support/iris';
import { blockLiveSocket } from '../support/socket';

/**
 * Story 23.12 (RA1 and RA2; DW-1159), a rejected request leaves the status rail at the answer's reply, in a real browser against a
 * real stack, as the rail fixture user (OCUTALON_RAIL_USER, whose session R1 to R19 of rail.spec.ts expect empty: each case removes its
 * rows and its phone messages in finally). Each case raises two requests, R1 and R2, in one incident, and presses Reject on R1 with the
 * page's polls held (holdPolls) and the live socket closed (blockLiveSocket), so that the polls are the only live path and none of them
 * can bring R1's `approval` event: only the press's reply can take R1 off the rail. A fixture row has no hold, so Approval.Answer waits
 * about 5 s before it replies; the bound is counted from the reply, as NFR-9's are (answers.spec.ts). The case then releases the polls
 * and checks that the event, when the page applies it, does not bring R1 back.
 * RA1 presses Reject on R1's chat card (channel web) and first checks that a failed press (the 500 stand-in of answers.spec.ts X5) leaves
 * R1 listed with its notice; RA2 presses Reject on R1's message on the simulated phone (channel phone).
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'RAIL';

/** The route that answers a request. */
const ANSWER = '**/ocutalon/api/v1/approvals/*/answer';

/** The bound of NFR-9 for the page: its change within 2 s of the answering call's reply. */
const PAGE_MS = 2000;

/** The name of the Reject button for the fixture request. */
const REJECT = 'Reject: repair and resend 50 orders';

/** The notice of the 500 stand-in. */
const FAILED = 'OcuTalon could not answer. Nothing was changed.';

/** The rail's row of a request. */
const rowOfRequest = (page: Page, ref: string): Locator => railOf(page).locator(`li.row[data-row-key="approvals:${ref}"]`);

/** The heading of the rail's approval requests, named with the count. */
const approvals = (page: Page, count: number): Locator => railOf(page).getByRole('heading', { level: 3, name: `Approval requests, ${count}`, exact: true });

/** The request card of a ref, in the chat. */
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);

/** The Seq of the session's stream that the page has applied. */
const seqOf = async (page: Page): Promise<number> => Number(await mainOf(page).getAttribute('data-session-seq'));

/** Starts to wait for the answering call's reply. */
function nextReply(page: Page): Promise<Response> {
  return page.waitForResponse((response) => response.request().method() === 'POST' && /\/approvals\/[^/]+\/answer$/.test(new URL(response.url()).pathname));
}

/** Signs the rail user in with the live socket closed, and waits for the loaded page with the phone. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await blockLiveSocket(page);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
  await expect(phoneOf(page), 'the stack is in demo mode: the phone shows').toBeVisible();
}

/** Raises R1 and R2 in one incident and checks that the rail lists both. */
async function raiseTwo(page: Page, user: string, rows: string[], label: string): Promise<{ first: string; second: string; incident: string }> {
  const incident = refOf(label);
  const requests: string[] = [];
  const first = await raise(page, user, rows, incident, requests);
  const second = await raise(page, user, rows, incident, requests);
  await expect(rowOfRequest(page, first), 'R1 is listed').toHaveCount(1);
  await expect(rowOfRequest(page, second), 'R2 is listed').toHaveCount(1);
  await expect(approvals(page, 2), 'the heading counts both').toBeVisible();
  return { first, second, incident };
}

/**
 * Presses Reject on `first` with the polls held (press runs the click) and checks the matrix's row: the 200 reply takes R1 off the
 * rail and out of the heading's count within 2 s, no poll has answered, R2 stays listed; then the polls are released and R1 does not
 * come back when its event is applied.
 */
async function rejectWithPollsHeld(page: Page, label: string, channel: 'web' | 'phone', first: string, second: string, press: () => Promise<void>): Promise<void> {
  const polls = await holdPolls(page);
  try {
    await expect.poll(() => polls.held(), { message: 'a poll is out and held', timeout: 15_000 }).toBeGreaterThan(0);
    const seqBefore = await seqOf(page);
    const reply = nextReply(page);
    const pressedAt = Date.now();
    await press();
    const response = await reply;
    const repliedAt = Date.now();
    expect(response.status(), 'the answer is 200').toBe(200);
    await expect(rowOfRequest(page, first), 'R1 leaves the rail within 2 s of the reply').toHaveCount(0, { timeout: PAGE_MS });
    const goneAt = Date.now();
    console.log(`RAIL ${label} ${channel}: reply ${repliedAt - pressedAt} ms after the press, row gone ${goneAt - repliedAt} ms after the reply`);
    expect(await seqOf(page), 'no poll answered: only the reply took the row off').toBe(seqBefore);
    await expect(rowOfRequest(page, second), 'R2 stays listed').toHaveCount(1);
    await expect(approvals(page, 1), 'the heading counts R2 alone').toBeVisible();

    polls.release();
    await expect.poll(() => seqOf(page), { message: "the page applied R1's event", timeout: CARD_MS }).toBeGreaterThan(seqBefore);
    await expect(rowOfRequest(page, first), 'R1 is still absent when its event is applied').toHaveCount(0);
    await page.waitForTimeout(1500);
    await expect(rowOfRequest(page, first), 'and 1.5 s later').toHaveCount(0);
    await expect(rowOfRequest(page, second), 'R2 stays listed').toHaveCount(1);
  } finally {
    polls.release();
  }
}

/**
 * RA1: Reject on the chat card. A press whose reply fails (the 500 stand-in) leaves R1 listed with the notice and the row pending.
 * Then a press that is answered takes R1 off the rail and out of the count within 2 s of the 200 reply, with the polls held;
 * R2 stays listed, and the event that follows does not bring R1 back.
 */
test('RA1: Reject on the card takes the request off the rail at the reply, before any poll', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = inMs(-2000);
  try {
    await open(page);
    const { first, second } = await raiseTwo(page, user, rows, 'RA1');
    const card = requestCard(page, first);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    const reject = card.getByRole('button', { name: REJECT, exact: true });

    await page.route(ANSWER, (route: Route) =>
      route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'failed', message: FAILED } }) }),
    );
    await reject.click();
    await expect(card.getByText(FAILED, { exact: true }), 'the notice shows').toBeVisible({ timeout: CARD_MS });
    await page.waitForTimeout(1500);
    await expect(rowOfRequest(page, first), 'R1 is still listed after the failed press').toHaveCount(1);
    expect(await readApproval(first).then((one) => one.state), 'and the row is still pending').toBe('pending');
    await page.unroute(ANSWER);

    await rejectWithPollsHeld(page, 'RA1', 'web', first, second, () => reject.click());
    expect(await readApproval(first).then((one) => one.state), 'the row is rejected').toBe('rejected');
  } finally {
    await page.unroute(ANSWER).catch(() => undefined);
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

/** RA2: Reject on R1's message on the simulated phone: the same sequence as RA1's answered press. */
test('RA2: Reject on the simulated phone takes the request off the rail at the reply, before any poll', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const start = inMs(-2000);
  try {
    await open(page);
    const { first, second, incident } = await raiseTwo(page, user, rows, 'RA2');
    const { message } = await noticeOnPhone(page, user, first, incident, inMs(-120_000));

    await rejectWithPollsHeld(page, 'RA2', 'phone', first, second, () => message.getByRole('button', { name: REJECT, exact: true }).click());
    expect(await readApproval(first).then((one) => one.state), 'the row is rejected').toBe('rejected');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});
