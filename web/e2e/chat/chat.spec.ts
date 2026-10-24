import { expect, test, type Locator, type Page, type Request, type Route } from '@playwright/test';

import { signIn, signInReadme, watchViolations } from '../sign-in/helpers';
import { fixtureUser, seedTurns, type SeedTurn } from '../support/iris';
import { announcements, clock, fromBottom, plain, recordAnnouncements, scrollListTo, tokenColor } from '../support/page';

/**
 * Story 2.5, the chat panel (C1 to C14), and Story 2.6's C15 (the fallback strip of a reply through the stub Decide; the rest of
 * Story 2.6 is decision.spec.ts), in a real browser against a real stack. C1 reads the README account and sends nothing;
 * every other case signs in as the panel fixture user that test-sign-in.sh created (OCUTALON_PANEL_USER) and sends or seeds on
 * its own session, so that no spec publishes on the README session or the instance stream (api.spec pins their counts) or
 * touches the chat user's chat. Each case asserts only on the clientIds and refs it made. The browser runs in Asia/Kolkata with
 * the en-US locale (C14 in Europe/Berlin with en-GB), so a time is the same wherever the specs run.
 *
 * /state's chat holds only the session's newest 100 entries, so every seeded turn is dated in the past (2020 to 2025): a turn
 * that a case sends (dated now) is always among the newest, and the cases that reload to read their own seeded turns (C5, C12,
 * C14) seed the newest of the past dates. That holds in any order of the cases and on a stack that ran them before.
 */
const STATE = '/ocutalon/api/v1/state';
const EVENTS = /\/ocutalon\/api\/v1\/events\?/;
const MESSAGES = '/ocutalon/api/v1/messages';

test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US' });

/** A poll that a routed /events handler is still answering when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

type Json = Record<string, unknown>;
interface Posted {
  clientId: string;
  text: string;
  fromGuide: boolean;
}

/** The sentence of a fallback for reason unusable, which the stack's stub model answers every turn with. */
const FALLBACK = "I couldn't answer that: the model's reply couldn't be used. Nothing was changed.";
const LIVE_REGIONS = '[aria-live], [role="log"], [role="status"], [role="alert"]';
const DECIDING = 'Deciding\u2026';
const WORKING = 'Working\u2026';

const isPath = (url: string, path: string): boolean => new URL(url).pathname === path;

/** The bodies of the page's POST /messages requests, in order, as they are made. */
function watchPosts(page: Page): () => Posted[] {
  const posted: Posted[] = [];
  page.on('request', (request: Request) => {
    if (request.method() === 'POST' && isPath(request.url(), MESSAGES)) posted.push(request.postDataJSON() as Posted);
  });
  return () => posted;
}

/** Signs the panel user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<Locator> {
  const { user, password } = fixtureUser('PANEL');
  await signIn(page, user, password);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
  await expect(field).toBeVisible();
  return field;
}

/** A text that no other case sends. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** Types the text, sends it by the given action and returns the POST that it made, with the server's answer. */
async function sendBy(page: Page, field: Locator, text: string, send: () => Promise<void>): Promise<{ posted: Posted; status: number }> {
  const request = page.waitForRequest((candidate) => candidate.method() === 'POST' && isPath(candidate.url(), MESSAGES));
  await field.fill(text);
  await send();
  const made = await request;
  const response = await made.response();
  return { posted: made.postDataJSON() as Posted, status: response ? response.status() : 0 };
}

/** Types the text, presses Enter and returns the POST that it made, with the server's answer. */
const sendWithEnter = (page: Page, field: Locator, text: string): Promise<{ posted: Posted; status: number }> =>
  sendBy(page, field, text, () => field.press('Enter'));

/** Types the text, clicks Send and returns the POST that it made, with the server's answer. */
const sendWithClick = (page: Page, field: Locator, text: string): Promise<{ posted: Posted; status: number }> =>
  sendBy(page, field, text, () => page.getByRole('button', { name: 'Send', exact: true }).click());

const userOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="user"][data-key="${key}"]`);
const replyOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="reply"][data-key="${key}"]`);

/** Answers each /events poll with the real answer cut to its first event, so that a turn's stages arrive one poll apart. */
async function oneEventPerPoll(page: Page): Promise<void> {
  await page.route(EVENTS, async (route: Route) => {
    const response = await route.fetch();
    const body = (await response.json()) as { events: Json[] };
    await route.fulfill({ response, json: { ...body, events: body.events.slice(0, 1) } });
  });
}

/** Answers each /events poll with the real answer without its events until release() is called. */
async function holdEvents(page: Page): Promise<{ release: () => void }> {
  let held = true;
  await page.route(EVENTS, async (route: Route) => {
    const response = await route.fetch();
    if (!held) {
      await route.fulfill({ response });
      return;
    }
    const body = (await response.json()) as { events: Json[] };
    await route.fulfill({ response, json: { ...body, events: [] } });
  });
  return {
    release: () => {
      held = false;
    },
  };
}

/** The turns of the user's session that carry the clientId, as /state holds them. */
async function turnsWith(page: Page, clientId: string): Promise<Json[]> {
  const state = (await (await page.request.get(STATE)).json()) as { chat: Array<{ type: string; payload: Json }> };
  return state.chat.filter((item) => item.type === 'chat.message' && item.payload['clientId'] === clientId).map((item) => item.payload);
}

/** C1: a fresh session shows the empty chat panel and the composer; nothing in main is a live region; the page sends script-src 'self'. */
test('C1: the empty chat panel, the composer, no live region and the page policy', async ({ page }) => {
  const violations = watchViolations(page);
  const posts = watchPosts(page);
  await signInReadme(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

  const main = page.getByRole('main');
  const empty = main.locator('app-empty-chat');
  await expect(empty.locator('p.headline')).toHaveText('For everything that arrives, OcuTalon makes one attention decision');
  await expect(main.getByRole('heading', { level: 2 }), 'the headline is not a heading').toHaveCount(1);
  await expect(main.getByRole('heading', { level: 3 })).toHaveCount(0);
  const headline = empty.locator('p.headline');
  await expect(headline).toHaveCSS('font-size', '20px');
  await expect(headline).toHaveCSS('font-weight', '700');

  const chips = empty.locator('app-outcome-chip');
  await expect(chips).toHaveText(['Ignore', 'Digest', 'Tell now', 'Act']);
  await expect(empty.locator('.meaning')).toHaveText([
    'Recorded; nobody notified',
    'Saved for later; nobody notified now',
    'Needs you now',
    'OcuTalon took or requested an action',
  ]);
  /** One stroke that only that outcome's Lucide icon draws: eye-off, inbox, bell-ring and zap. */
  const ICON_STROKE: Record<string, string> = {
    ignore: 'path[d="m2 2 20 20"]',
    digest: 'polyline[points="22 12 16 12 14 15 10 15 8 12 2 12"]',
    'tell-now': 'path[d="M10.268 21a2 2 0 0 0 3.464 0"]',
    act: 'path[d^="M4 14a1 1 0 0 1-.78-1.63"]',
  };
  for (const [i, outcome] of ['ignore', 'digest', 'tell-now', 'act'].entries()) {
    const chip = chips.nth(i).locator('.chip');
    await expect(chip.locator('svg[aria-hidden="true"]'), `${outcome} has its icon, hidden from assistive technology`).toHaveCount(1);
    expect(await chip.locator('svg path, svg polyline').count(), `${outcome}'s icon is drawn`).toBeGreaterThan(0);
    await expect(chip.locator(ICON_STROKE[outcome]!), `${outcome} has its own icon, not another outcome's`).toHaveCount(1);
    await expect(chip).toHaveCSS('background-color', await tokenColor(page, `--outcome-chip-${outcome}-background`));
    await expect(chip).toHaveCSS('color', await tokenColor(page, `--outcome-chip-${outcome}-foreground`));
    await expect(chip, `${outcome} is not focusable`).not.toHaveAttribute('tabindex', /.*/);
  }
  await chips.first().locator('.chip').hover();
  await expect(page.locator('.cdk-overlay-container app-tooltip'), 'a pointer resting on a chip shows its meaning, here too').toHaveText('Recorded; nobody notified');
  await page.keyboard.press('Escape');
  await expect(page.locator('.cdk-overlay-container app-tooltip'), 'and Esc hides it').toHaveCount(0);
  await page.mouse.move(0, 0);
  const meaning = empty.locator('.meaning').first();
  await expect(meaning).toHaveCSS('font-size', '13px');
  await expect(meaning).toHaveCSS('color', await tokenColor(page, '--ink-muted'));
  await expect(empty.locator('.line')).toHaveText([
    'It watches your productions from inside IRIS, and every decision is a production message you can trace.',
    'Anything risky waits for your approval.',
    'Ask OcuTalon to watch a production, set a reminder, or say what you need.',
  ]);
  await expect(empty.locator('.line').first()).toHaveCSS('font-size', '14px');

  const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
  await expect(field).toBeVisible();
  const viewport = page.viewportSize()!;
  expect(Math.abs((await page.locator('app-root').boundingBox())!.height - viewport.height), 'the app fills the viewport').toBeLessThanOrEqual(1);
  expect(await page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight), 'and the page itself does not scroll').toBeLessThanOrEqual(0);
  await expect(page.locator('section.rail'), 'the rail scrolls on its own').toHaveCSS('overflow-y', 'auto');
  await expect(page.locator('app-chat-panel > .list'), 'and so does the list').toHaveCSS('overflow-y', 'auto');
  await expect(field, 'no autofocus').not.toBeFocused();
  await expect(field).toHaveAttribute('placeholder', 'Message OcuTalon');
  await expect(main.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await expect(main.locator('[aria-live], [role="log"], [role="status"], [role="alert"]'), 'nothing in main is a live region').toHaveCount(0);

  const reloaded = await page.reload();
  expect(reloaded?.headers()['content-security-policy'], 'the document carries the page policy').toBe("script-src 'self'");
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(empty.locator('p.headline')).toBeVisible();
  expect(posts(), 'nothing was sent').toEqual([]);
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

/** C2: Enter sends; the bubble; the stages one poll apart, in order; the fallback reply under the mark and the name. */
test('C2: Enter sends, and the turn shows Deciding, Working and then the fallback reply', async ({ page }) => {
  await page.addInitScript(() => {
    const log: string[] = [];
    (window as unknown as { replyLog: string[] }).replyLog = log;
    new MutationObserver(() => {
      const replies = document.querySelectorAll('app-chat-panel [data-part="reply"]');
      const last = replies[replies.length - 1];
      const text = (last?.querySelector('.indicator') ?? last?.querySelector('.text'))?.textContent?.trim() ?? '';
      if (text !== '' && log[log.length - 1] !== text) log.push(text);
    }).observe(document, { subtree: true, childList: true, characterData: true });
  });
  await oneEventPerPoll(page);
  const field = await open(page);
  const mark = await page.evaluate(() => (window as unknown as { replyLog: string[] }).replyLog.length);
  const oneLine = await field.evaluate((el) => el.clientHeight);

  const text = unique('C2');
  const { posted, status } = await sendWithEnter(page, field, `  ${text}\nsecond line  `);
  expect(status, 'the post is accepted').toBe(202);
  expect(Object.keys(posted).sort(), 'the body names no session').toEqual(['clientId', 'fromGuide', 'text']);
  expect(posted.clientId).toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(posted.text, 'the text is trimmed at both ends and keeps its line break').toBe(`${text}\nsecond line`);
  expect(posted.fromGuide).toBe(false);
  await expect(field, 'the field is empty').toHaveValue('');
  await expect(field, 'and focused').toBeFocused();
  await expect.poll(() => field.evaluate((el, height) => Math.abs(el.clientHeight - height), oneLine), { message: 'and shrunk from two lines back to one' }).toBeLessThanOrEqual(1);

  const bubble = userOf(page, posted.clientId).locator('.bubble');
  await expect(bubble).toHaveText(`${text}\nsecond line`);
  // toHaveText collapses whitespace, so the line break is read as the page draws it: innerText follows white-space.
  await expect.poll(() => bubble.evaluate((el) => (el as HTMLElement).innerText), { message: 'the bubble keeps the line break of the text' }).toBe(`${text}\nsecond line`);
  await expect(bubble).toHaveCSS('background-color', await tokenColor(page, '--sunken'));
  const list = page.locator('app-chat-panel > .list');
  const bubbleBox = (await bubble.boundingBox())!;
  const listBox = (await list.boundingBox())!;
  expect(bubbleBox.width, 'at most 80% of the list').toBeLessThanOrEqual(listBox.width * 0.8 + 0.5);
  const gap = listBox.x + listBox.width - (bubbleBox.x + bubbleBox.width);
  expect(gap, 'right-aligned').toBeGreaterThanOrEqual(0);
  expect(gap, 'right-aligned').toBeLessThan(60);

  await expect.poll(() => page.evaluate((from) => (window as unknown as { replyLog: string[] }).replyLog.slice(from), mark), { timeout: 20_000 }).toEqual([DECIDING, WORKING, FALLBACK]);
  const reply = replyOf(page, posted.clientId);
  await expect(reply.locator('.text')).toHaveText(FALLBACK);
  await expect(field, 'a reply that lands takes no focus').toBeFocused();
  await expect(reply, 'the reply is unboxed: no background').toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  await expect(reply, 'and no border').toHaveCSS('border-top-width', '0px');
  const head = reply.locator('.head');
  const avatar = head.locator('img.mark');
  await expect(avatar).toHaveAttribute('alt', '');
  await expect(avatar).toHaveAttribute('src', /assets\/brand\/icon-192\.png$/);
  expect(await avatar.boundingBox()).toMatchObject({ width: 24, height: 24 });
  await expect(head.locator('.name')).toHaveText('OcuTalon');
  const headBox = (await head.boundingBox())!;
  const textBox = (await reply.locator('.text').boundingBox())!;
  expect(textBox.y, 'the reply is under the avatar and the name').toBeGreaterThanOrEqual(headBox.y + headBox.height - 1);
  expect(Math.abs(textBox.x - headBox.x), 'left-aligned').toBeLessThanOrEqual(1);

  const stored = (await turnsWith(page, posted.clientId))[0]!;
  await expect(userOf(page, posted.clientId).locator('.when')).toHaveText(clock(String(stored['createdAt'])));
  await expect(userOf(page, posted.clientId).getByText('Not sent')).toHaveCount(0);
});

/** C3: the field. Shift+Enter adds a line; empty and space-only text and Enter inside an IME composition send nothing; it grows to 5 lines; its name holds; it stays usable while a turn is deciding, and a click on Send sends and refocuses it. */
test('C3: Shift+Enter, growth to 5 lines, the name, and a second message mid-turn', async ({ page }) => {
  const field = await open(page);
  const posts = watchPosts(page);
  await expect(field).toHaveAccessibleName('Message OcuTalon');

  await field.pressSequentially('line one');
  await field.press('Shift+Enter');
  await field.pressSequentially('line two');
  expect(await field.inputValue(), 'Shift+Enter adds a line').toBe('line one\nline two');
  expect(posts(), 'and makes no request').toEqual([]);
  const twoLines = await field.evaluate((el) => el.clientHeight);
  await field.press('Shift+Enter');
  await field.pressSequentially('line three');
  const threeLines = await field.evaluate((el) => el.clientHeight);
  expect(threeLines, '3 lines make the field taller than 2').toBeGreaterThan(twoLines + 10);
  await expect(field, 'it keeps its name with text in it').toHaveAccessibleName('Message OcuTalon');
  for (let i = 4; i <= 8; i += 1) {
    await field.press('Shift+Enter');
    await field.pressSequentially(`line ${i}`);
  }
  const five = await field.evaluate((el) => {
    const style = getComputedStyle(el);
    return parseFloat(style.lineHeight) * 5 + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
  });
  const eight = await field.evaluate((el) => ({ client: el.clientHeight, scroll: el.scrollHeight }));
  expect(Math.abs(eight.client - five), '8 lines leave it at its 5-line height').toBeLessThanOrEqual(1);
  expect(eight.scroll, 'and it scrolls').toBeGreaterThan(eight.client);
  expect(posts(), 'still nothing was sent').toEqual([]);
  await field.fill('');

  await field.press('Enter');
  await field.fill('  \n \t ');
  await field.press('Enter');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await field.fill('composing');
  // The two signs of an open composition, one at a time: isComposing, and keyCode 229, which Safari's committing Enter carries alone.
  await field.dispatchEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true, cancelable: true });
  expect(posts(), 'an Enter with isComposing sends nothing').toEqual([]);
  await field.dispatchEvent('keydown', { key: 'Enter', keyCode: 229, bubbles: true, cancelable: true });
  expect(posts(), 'empty text, space-only text and Enter during an IME composition send nothing').toEqual([]);
  expect(await field.inputValue(), 'and the IME text stays in the field').toBe('composing');
  await field.fill('');

  const hold = await holdEvents(page);
  const first = await sendWithEnter(page, field, unique('C3 first'));
  expect(first.status).toBe(202);
  await expect(replyOf(page, first.posted.clientId).locator('.indicator')).toHaveText(DECIDING);
  await expect(field, 'the composer stays enabled during a turn').toBeEnabled();
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  const second = await sendWithClick(page, field, unique('C3 second'));
  expect(second.status).toBe(202);
  await expect(field, 'a click on Send leaves the field empty').toHaveValue('');
  await expect(field, 'and returns focus to it').toBeFocused();
  expect(second.posted.clientId, 'each message is its own turn').not.toBe(first.posted.clientId);
  await expect(replyOf(page, second.posted.clientId).locator('.indicator')).toHaveText(DECIDING);

  hold.release();
  for (const sent of [first, second]) {
    await expect(replyOf(page, sent.posted.clientId).locator('.text'), 'each turn gets its reply').toHaveText(FALLBACK, { timeout: 20_000 });
  }
  const order = await page.locator('app-chat-panel [data-part="reply"]').evaluateAll((els) => els.map((el) => (el as HTMLElement).dataset['key']));
  expect(order.indexOf(first.posted.clientId), 'the replies are in send order').toBeGreaterThanOrEqual(0);
  expect(order.indexOf(first.posted.clientId)).toBeLessThan(order.indexOf(second.posted.clientId));
  expect((await turnsWith(page, first.posted.clientId)).length + (await turnsWith(page, second.posted.clientId)).length, 'two turns').toBe(2);
});

/** The Retry sending button of a message. */
const retryOf = (page: Page, key: string): Locator => userOf(page, key).getByRole('button', { name: 'Retry sending' });

/** C4: a send that fails keeps the text with "Not sent" and Retry sending, which posts the same clientId. */
test.describe('C4: a failed send', () => {
  test('the first post is aborted: Retry sending posts the same clientId and one turn is made', async ({ page }) => {
    const field = await open(page);
    const posts = watchPosts(page);
    let aborted = false;
    await page.route(`**${MESSAGES}`, async (route) => {
      if (aborted) {
        await route.continue();
        return;
      }
      aborted = true;
      await route.abort('connectionfailed');
    });
    const text = unique('C4 aborted');
    await field.fill(text);
    await field.press('Enter');
    await expect.poll(() => posts().length).toBe(1);
    const clientId = posts()[0]!.clientId;
    await expect(userOf(page, clientId).locator('.bubble'), 'the bubble keeps the text').toHaveText(text);
    await expect(userOf(page, clientId).locator('.failed')).toHaveText('Not sent');
    await expect(userOf(page, clientId).locator('.failed svg[aria-hidden="true"]')).toHaveCount(1);
    await expect(replyOf(page, clientId), 'a failed message has no indicator').toHaveCount(0);
    await expect(page.getByRole('main').locator(LIVE_REGIONS), 'a failed message is no live region').toHaveCount(0);

    await retryOf(page, clientId).click();
    await expect(replyOf(page, clientId).locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
    expect(posts().map((posted) => posted.clientId), 'the retry posts the same clientId').toEqual([clientId, clientId]);
    expect(posts()[1]!.text).toBe(text);
    await expect(userOf(page, clientId).getByText('Not sent')).toHaveCount(0);
    expect(await turnsWith(page, clientId), 'the server holds one turn').toHaveLength(1);
  });

  test('the post reached the server but its answer was 503: the retry is deduped to one turn', async ({ page }) => {
    const field = await open(page);
    const posts = watchPosts(page);
    const hold = await holdEvents(page);
    let answered = false;
    await page.route(`**${MESSAGES}`, async (route) => {
      if (answered) {
        await route.continue();
        return;
      }
      answered = true;
      await route.fetch();
      await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}' });
    });
    const text = unique('C4 503');
    await field.fill(text);
    await field.press('Enter');
    await expect.poll(() => posts().length).toBe(1);
    const clientId = posts()[0]!.clientId;
    await expect(userOf(page, clientId).locator('.failed')).toHaveText('Not sent');
    await expect(userOf(page, clientId).locator('.bubble')).toHaveText(text);
    await expect.poll(async () => (await turnsWith(page, clientId)).length, { message: 'the first post did reach the server' }).toBe(1);
    await expect(userOf(page, clientId).locator('.failed'), 'the page has not seen the turn').toHaveCount(1);

    await retryOf(page, clientId).click();
    await expect(userOf(page, clientId).locator('.failed')).toHaveCount(0);
    await expect(replyOf(page, clientId).locator('.indicator'), 'the accepted retry is deciding').toHaveText(DECIDING);
    expect(posts().map((posted) => posted.clientId)).toEqual([clientId, clientId]);
    hold.release();
    await expect(replyOf(page, clientId).locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
    expect(await turnsWith(page, clientId), 'one turn only').toHaveLength(1);
    await expect(userOf(page, clientId), 'one bubble').toHaveCount(1);
  });

  test('an answer other than 202 is not an accepted message: Retry sending posts the same clientId', async ({ page }) => {
    const field = await open(page);
    const posts = watchPosts(page);
    let answered = false;
    await page.route(`**${MESSAGES}`, async (route) => {
      if (answered) {
        await route.continue();
        return;
      }
      answered = true;
      await route.fulfill({ status: 200, contentType: 'application/json', body: '{"clientId":"not-the-server"}' });
    });
    const text = unique('C4 200');
    await field.fill(text);
    await field.press('Enter');
    await expect.poll(() => posts().length).toBe(1);
    const clientId = posts()[0]!.clientId;
    await expect(userOf(page, clientId).locator('.failed'), 'a 200 is Not sent').toHaveText('Not sent');
    await expect(replyOf(page, clientId), 'and has no indicator').toHaveCount(0);

    await retryOf(page, clientId).click();
    await expect(replyOf(page, clientId).locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
    expect(posts().map((posted) => posted.clientId), 'the retry posts the same clientId').toEqual([clientId, clientId]);
    expect(await turnsWith(page, clientId), 'the server holds one turn').toHaveLength(1);
  });

  test('a post that is never answered gives Not sent after 10 seconds', async ({ page }) => {
    test.slow(); // the page's own 10 s, then the retry's turn: the 45 s of a quick host is too little for a slow one
    await recordAnnouncements(page);
    const field = await open(page);
    const posts = watchPosts(page);
    const stuck: Route[] = [];
    let first = true;
    await page.route(`**${MESSAGES}`, async (route) => {
      if (!first) {
        await route.continue();
        return;
      }
      first = false;
      stuck.push(route);
    });
    const text = unique('C4 silent');
    await field.fill(text);
    const sentAt = Date.now();
    await field.press('Enter');
    await expect.poll(() => posts().length).toBe(1);
    const clientId = posts()[0]!.clientId;
    await expect(userOf(page, clientId).locator('.bubble'), 'the bubble shows at once, before any answer').toHaveText(text);
    await expect(replyOf(page, clientId), 'a post still in flight has no indicator').toHaveCount(0);
    await expect(userOf(page, clientId).locator('.failed')).toHaveCount(0);
    await expect(userOf(page, clientId).locator('.failed'), 'Not sent after the 10 s limit').toHaveText('Not sent', { timeout: 15_000 });
    expect(Date.now() - sentAt, 'and not before it').toBeGreaterThanOrEqual(9_500);
    await expect(userOf(page, clientId).locator('.bubble')).toHaveText(text);
    await expect.poll(() => announcements(page, 'Message not sent'), { message: 'the failure is announced once' }).toBe(1);

    await retryOf(page, clientId).click();
    await expect(replyOf(page, clientId).locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
    expect(posts().map((posted) => posted.clientId), 'the retry posts the same clientId').toEqual([clientId, clientId]);
    expect(await turnsWith(page, clientId), 'the server holds one turn').toHaveLength(1);
    expect(await announcements(page, 'Message not sent'), 'and the retry that worked adds none').toBe(1);
    for (const route of stuck) await route.abort().catch(() => undefined);
  });

  test('a failed post whose turn then arrives by poll leaves no Not sent', async ({ page }) => {
    const field = await open(page);
    const posts = watchPosts(page);
    const hold = await holdEvents(page);
    await page.route(`**${MESSAGES}`, async (route) => {
      await route.fetch();
      await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}' });
    });
    const text = unique('C4 arrives');
    await field.fill(text);
    await field.press('Enter');
    await expect.poll(() => posts().length).toBe(1);
    const clientId = posts()[0]!.clientId;
    await expect(userOf(page, clientId).locator('.failed'), 'the entry failed first').toHaveText('Not sent');
    hold.release();
    await expect(replyOf(page, clientId).locator('.text'), "the server's turn arrives").toHaveText(FALLBACK, { timeout: 20_000 });
    await expect(userOf(page, clientId), 'it replaced the local message').toHaveCount(1);
    await expect(userOf(page, clientId).getByText('Not sent')).toHaveCount(0);
    await expect(retryOf(page, clientId)).toHaveCount(0);
    await expect(page.locator('app-chat-panel .bubble').filter({ hasText: text })).toHaveCount(1);
  });

  test('a post that fails after its turn arrived by poll shows no Not sent and announces nothing', async ({ page }) => {
    await recordAnnouncements(page);
    const field = await open(page);
    const posts = watchPosts(page);
    let answer = (): void => undefined;
    const late = new Promise<void>((resolve) => {
      answer = resolve;
    });
    await page.route(`**${MESSAGES}`, async (route) => {
      await route.fetch();
      await late;
      await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}' });
    });
    const text = unique('C4 late');
    await field.fill(text);
    await field.press('Enter');
    await expect.poll(() => posts().length).toBe(1);
    const clientId = posts()[0]!.clientId;
    await expect(replyOf(page, clientId), "the server's turn arrives by poll before the post is answered").toHaveCount(1, { timeout: 15_000 });
    answer();
    await page.waitForTimeout(1500);
    expect(await announcements(page, 'Message not sent'), 'a failure of a message that the page shows as sent is not announced').toBe(0);
    await expect(userOf(page, clientId).getByText('Not sent')).toHaveCount(0);
    await expect(userOf(page, clientId), 'and the page shows the message once').toHaveCount(1);
  });
});

/** C5: seeded turns after a reload: order, captions, the reply's blocks and links, text that is not HTML, and the 72ch cap. */
test('C5: seeded turns in CreatedAt order, with captions, lists, links and text that stays text', async ({ page }) => {
  const stamp = Date.now().toString(36);
  const long = Array.from({ length: 70 }, (_unused, i) => `word${i}`).join(' ');
  const blocks = [
    'First paragraph with a bare link https://example.com/docs.',
    'Second line of the same paragraph.',
    '',
    'Second paragraph with [the guide](https://example.org/guide) and [bad](javascript:window.__pwned=1) and <b>x</b><img src=x onerror="window.__pwned=1">',
    '',
    '- bullet one',
    '* bullet two',
    '',
    '1. step one',
    '2) step two',
    '',
    long,
  ].join('\n');
  const turns: SeedTurn[] = [
    { createdAt: '2025-06-01T10:03:00Z', text: `zz C5 ${stamp} third`, replyText: blocks },
    { createdAt: '2025-06-01T10:01:00Z', text: `zz C5 ${stamp} first`, replyText: 'Sent from Telegram.', channel: 'telegram' },
    { createdAt: '2025-06-01T10:02:00Z', text: `zz C5 ${stamp} second`, replyText: 'Sent from the guide.', fromGuide: true },
    { createdAt: '2025-06-01T10:04:00Z', text: `zz C5 ${stamp} long ${long}`, replyText: 'A reply to a long message.' },
  ];
  await open(page);
  const { user } = fixtureUser('PANEL');
  const seeded = await seedTurns(user, turns);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

  const bubbles = page.locator('app-chat-panel .bubble').filter({ hasText: `zz C5 ${stamp}` });
  await expect(bubbles, 'the turns are in CreatedAt order, not the order they were written').toHaveText([
    `zz C5 ${stamp} first`,
    `zz C5 ${stamp} second`,
    `zz C5 ${stamp} third`,
    `zz C5 ${stamp} long ${long}`,
  ]);
  const [thirdRef, firstRef, secondRef, longRef] = seeded.refs as [string, string, string, string];
  expect(plain(await userOf(page, firstRef).locator('.when').textContent())).toBe(`via Telegram \u00B7 ${clock('2025-06-01T10:01:00Z')}`);
  expect(plain(await userOf(page, secondRef).locator('.when').textContent())).toBe(`From the demo guide \u00B7 ${clock('2025-06-01T10:02:00Z')}`);
  expect(plain(await userOf(page, thirdRef).locator('.when').textContent()), 'a web turn has no caption').toBe(clock('2025-06-01T10:03:00Z'));
  const bubbleText = await userOf(page, longRef)
    .locator('.bubble')
    .evaluate((el) => {
      const style = getComputedStyle(el);
      const probe = document.createElement('div');
      probe.style.width = 'var(--chat-panel-text-max)';
      el.append(probe);
      const max = probe.getBoundingClientRect().width;
      probe.remove();
      return { width: el.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight), max };
    });
  expect(bubbleText.width, "a long message's lines are no wider than 72ch in the bubble's font").toBeLessThanOrEqual(bubbleText.max + 0.5);
  expect(bubbleText.width, 'and reach it').toBeGreaterThan(bubbleText.max * 0.9);

  const reply = replyOf(page, thirdRef);
  const body = reply.locator('.text');
  await expect(body.locator('p.para'), 'two paragraphs and the long one').toHaveCount(3);
  // toHaveText collapses whitespace, so the line break is read as the page draws it: innerText follows white-space.
  await expect
    .poll(() => body.locator('p.para').first().evaluate((el) => (el as HTMLElement).innerText), { message: 'a single line break inside a paragraph stays a line break' })
    .toMatch(/\.\nSecond line of the same paragraph\.$/);
  await expect(body.locator('ul > li')).toHaveText(['bullet one', 'bullet two']);
  await expect(body.locator('ol > li')).toHaveText(['step one', 'step two']);
  const links = body.locator('a.link');
  await expect(links).toHaveCount(2);
  await expect(links.first()).toHaveAttribute('href', 'https://example.com/docs');
  await expect(links.nth(1)).toHaveAttribute('href', 'https://example.org/guide');
  for (const link of await links.all()) {
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(link.locator('svg[aria-hidden="true"]')).toHaveCount(1);
  }
  await expect(body.getByRole('link', { name: /\(opens in a new tab\)$/ })).toHaveCount(2);
  await expect(body.getByRole('link', { name: 'the guide (example.org) (opens in a new tab)' })).toHaveCount(1);
  await expect(links.nth(1).locator('.host'), 'a labelled link shows the host it opens after its label').toHaveText('(example.org)');
  await expect(links.nth(1).locator('.host')).toBeVisible();
  await expect(body.getByRole('link', { name: 'https://example.com/docs (opens in a new tab)' })).toHaveCount(1);
  await expect(links.first().locator('.host'), 'a bare address names itself').toHaveCount(0);
  await expect(body, 'a javascript: link and HTML-like text show as text').toContainText('[bad](javascript:window.__pwned=1)');
  await expect(body).toContainText('<b>x</b><img src=x onerror="window.__pwned=1">');
  await expect(body.locator('b, img, script'), 'with no element made from them').toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { __pwned?: number }).__pwned), 'and nothing ran').toBeUndefined();
  await expect(page.getByRole('main').locator('[aria-live], [role="log"], [role="status"], [role="alert"]'), 'nothing in main is a live region, also with entries').toHaveCount(0);

  const longPara = body.locator('p.para').nth(2);
  const probeWidth = await body.evaluate((el) => {
    const probe = document.createElement('div');
    probe.style.width = 'var(--chat-panel-text-max)';
    probe.style.height = '1px';
    el.append(probe);
    const width = probe.getBoundingClientRect().width;
    probe.remove();
    return width;
  });
  const longWidth = (await longPara.boundingBox())!.width;
  expect(longWidth, 'a long paragraph is no wider than 72ch').toBeLessThanOrEqual(probeWidth + 0.5);
  expect(longWidth, 'and reaches it').toBeGreaterThan(probeWidth * 0.9);
});

/** C6: scrolled up, content from elsewhere changes nothing about the list; New messages shows, and pressing it goes down and focuses; at the bottom, the list follows new content. */
test('C6: scrolled up, a new turn leaves the list where it is and New messages takes you to it', async ({ page }) => {
  const field = await open(page);
  const { user } = fixtureUser('PANEL');
  const { list, stamp } = await longChat(page, 2021, 'C6');
  await expect(page.locator('app-chat-panel [data-part="user"]').last(), 'the last message is in view').toBeInViewport();
  await expect(page.getByRole('button', { name: 'New messages' })).toHaveCount(0);
  const column = await page.locator('app-chat-panel .entries').evaluate((el) => {
    const style = getComputedStyle(el);
    return el.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
  });
  expect(Math.abs((await page.locator('app-chat-panel .turn').first().boundingBox())!.width - column), 'an entry spans the column').toBeLessThanOrEqual(1);

  await scrollListTo(list, 'top');
  expect(await list.evaluate((el) => el.scrollTop), 'the list is at the top').toBe(0);
  const firstBubble = page.locator('app-chat-panel [data-part="user"] .bubble').first();
  const before = (await firstBubble.boundingBox())!;

  const published = await seedTurns(user, [{ createdAt: '2021-02-01T10:00:00Z', text: `zz C6 ${stamp} published`, replyText: 'A reply that lands while the list is scrolled up.' }], true);
  const ref = published.refs[0]!;
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(published.seqs[0]), { timeout: 2000 });
  await expect(userOf(page, ref), 'the turn is in the list').toHaveCount(1);
  expect(await list.evaluate((el) => el.scrollTop), 'scrollTop did not change').toBe(0);
  expect((await firstBubble.boundingBox())!, 'nor did the first visible entry move').toEqual(before);
  expect(await page.evaluate(() => document.activeElement === document.body), 'a turn that lands moves no focus').toBe(true);

  // A second turn lands in a later poll: the press must still go to the first one that landed, not to the latest.
  const later = await seedTurns(user, [{ createdAt: '2021-02-01T10:01:00Z', text: `zz C6 ${stamp} later`, replyText: 'A second reply that lands while the list is scrolled up.' }], true);
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(later.seqs[0]), { timeout: 5000 });
  await expect(userOf(page, later.refs[0]!), 'the second turn is in the list').toHaveCount(1);
  expect(await list.evaluate((el) => el.scrollTop), 'still at the top').toBe(0);

  const button = page.getByRole('button', { name: 'New messages' });
  await expect(button).toBeVisible();
  await expect(page.getByRole('main').locator(LIVE_REGIONS), 'the button is no live region').toHaveCount(0);
  await expect(button.locator('svg[aria-hidden="true"]'), 'with its chevron-down icon').toHaveCount(1);
  await expect(button.locator('svg path')).toHaveAttribute('d', 'm6 9 6 6 6-6');
  const composer = (await page.locator('app-composer').boundingBox())!;
  const buttonBox = (await button.boundingBox())!;
  expect(Math.abs(buttonBox.x + buttonBox.width / 2 - (composer.x + composer.width / 2)), 'centred over the composer').toBeLessThanOrEqual(1);
  expect(buttonBox.y + buttonBox.height, 'above the composer').toBeLessThanOrEqual(composer.y);
  await field.focus();
  await page.keyboard.press('Shift+Tab');
  await expect(button, 'Shift+Tab from the composer reaches it').toBeFocused();

  await page.keyboard.press('Enter');
  await expect.poll(() => fromBottom(list), { message: 'pressing it puts the list at the bottom' }).toBeLessThanOrEqual(24);
  await expect(userOf(page, ref), "and focuses the first turn that landed, not the later one").toBeFocused();
  await expect(button).toHaveCount(0);

  const followed = await seedTurns(user, [{ createdAt: '2021-02-02T10:00:00Z', text: `zz C6 ${stamp} followed`, replyText: 'A reply that lands while the list is at the bottom.' }], true);
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(followed.seqs[0]), { timeout: 2000 });
  await expect(userOf(page, followed.refs[0]!), 'the turn is in the list').toHaveCount(1);
  await expect.poll(() => fromBottom(list), { message: 'at the bottom, the list follows new content' }).toBeLessThanOrEqual(24);
  await expect(button, 'and New messages does not show').toHaveCount(0);
});

/** C7: the dots of the turn indicator are static under reduced motion and animate otherwise. */
test('C7: the indicator\'s dots have no animation under reduced motion', async ({ page }) => {
  const field = await open(page);
  const hold = await holdEvents(page);
  const sent = await sendWithEnter(page, field, unique('C7'));
  expect(sent.status).toBe(202);
  const dots = replyOf(page, sent.posted.clientId).locator('.indicator .dots');
  await expect(dots).toHaveText('\u2026');
  await expect(replyOf(page, sent.posted.clientId).locator('.indicator')).toHaveText(DECIDING);
  await expect(page.getByRole('main').locator(LIVE_REGIONS), 'the indicator is no live region').toHaveCount(0);

  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(dots).toHaveCSS('animation-name', 'none');
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await expect(dots).not.toHaveCSS('animation-name', 'none');
  hold.release();
  await expect(replyOf(page, sent.posted.clientId).locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
});

/**
 * C8: a turn that stays running shows "Working \u00B7 N s" after 10 seconds, with the whole spoken form, and the indicator is no
 * live region. The 10 s are the page's own, counted from when it first saw the turn running, so the test waits for the text and
 * reads N from it: a threshold that is too low shows N under 10, one that is too high misses the 20 s wait. It measures no
 * wall-clock interval of its own, which a slow host would stretch between the page's clock and the test's first look.
 */
test('C8: after 10 seconds the working indicator adds the elapsed seconds, spoken in full', async ({ page }) => {
  test.slow(); // the turn's own stages, then the page's 10 s: the 45 s of a quick host is too little for a slow one
  await page.route(EVENTS, async (route: Route) => {
    const response = await route.fetch();
    const body = (await response.json()) as { events: Array<{ type: string; payload?: { state?: string } }> };
    const events = body.events.filter((event) => !(event.type === 'chat.message' && event.payload?.state === 'done'));
    await route.fulfill({ response, json: { ...body, events } });
  });
  const field = await open(page);
  const sent = await sendWithEnter(page, field, unique('C8'));
  expect(sent.status).toBe(202);
  const indicator = replyOf(page, sent.posted.clientId).locator('.indicator');
  await expect(indicator, 'the running turn shows Working').toHaveText(WORKING, { timeout: 20_000 });
  await expect(indicator.locator('[aria-hidden="true"]'), 'before 10 seconds there is no working time').toHaveCount(0);

  await expect(indicator.locator('[aria-hidden="true"]'), 'after 10 seconds the working time shows').toHaveText(/^Working \u00B7 \d+ s$/, { timeout: 20_000 });
  const shown = await indicator.evaluate((el) => ({
    visible: el.querySelector('[aria-hidden="true"]')?.textContent?.trim() ?? '',
    spoken: el.querySelector('.visually-hidden')?.textContent?.trim() ?? '',
  }));
  const seconds = /^Working \u00B7 (\d+) s$/.exec(shown.visible)?.[1];
  expect(Number(seconds), 'whole seconds, 10 or more since the page first saw the turn running').toBeGreaterThanOrEqual(10);
  expect(shown.spoken, 'spoken as seconds').toBe(`Working \u00B7 ${seconds} seconds`);
  await expect(page.getByRole('main').locator(LIVE_REGIONS), 'the working time is no live region').toHaveCount(0);
});

/** Seeds 30 done turns for the user at the given year and reloads, leaving the list at its bottom. */
async function longChat(page: Page, year: number, label: string): Promise<{ list: Locator; stamp: string }> {
  const { user } = fixtureUser('PANEL');
  const stamp = Date.now().toString(36);
  const many: SeedTurn[] = Array.from({ length: 30 }, (_unused, i) => ({
    createdAt: `${year}-01-01T10:${String(10 + i).padStart(2, '0')}:00Z`,
    text: `zz ${label} ${stamp} message ${i}`,
    replyText: `Reply ${i} to message ${i}.\nIt has a second line so that the list is tall.`,
  }));
  await seedTurns(user, many);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const list = page.locator('app-chat-panel > .list');
  await expect.poll(() => fromBottom(list), { message: 'the list starts at the bottom' }).toBeLessThanOrEqual(24);
  return { list, stamp };
}

/** C9: scrolled up, Send takes the list to the bottom; a reply that lands shows New messages and the press focuses that reply; scrolling down by hand hides the button. */
test('C9: scrolled up, a reply that lands shows New messages, Send goes to the bottom and scrolling down hides the button', async ({ page }) => {
  const field = await open(page);
  const { user } = fixtureUser('PANEL');
  const { list, stamp } = await longChat(page, 2022, 'C9');
  const button = page.getByRole('button', { name: 'New messages' });

  await scrollListTo(list, 'top');
  const hold = await holdEvents(page);
  const sent = await sendWithEnter(page, field, unique('C9'));
  expect(sent.status).toBe(202);
  await expect.poll(() => fromBottom(list), { message: 'Send takes a list that is scrolled up to the bottom' }).toBeLessThanOrEqual(24);
  await expect(button, 'the user\u2019s own message needs no button').toHaveCount(0);

  await scrollListTo(list, 'top');
  const firstBubble = page.locator('app-chat-panel [data-part="user"] .bubble').first();
  const before = (await firstBubble.boundingBox())!;
  hold.release();
  await expect(button, 'a reply that lands while the list is scrolled up shows New messages').toBeVisible({ timeout: 20_000 });
  await expect(replyOf(page, sent.posted.clientId).locator('.text')).toHaveText(FALLBACK);
  expect(await list.evaluate((el) => el.scrollTop), 'scrollTop did not change').toBe(0);
  expect((await firstBubble.boundingBox())!, 'nor did the first visible entry move').toEqual(before);

  await button.click();
  await expect.poll(() => fromBottom(list)).toBeLessThanOrEqual(24);
  await expect(replyOf(page, sent.posted.clientId), 'the press focuses the reply that landed').toBeFocused();
  await expect(button).toHaveCount(0);

  await scrollListTo(list, 'top');
  const published = await seedTurns(user, [{ createdAt: '2022-02-01T10:00:00Z', text: `zz C9 ${stamp} published`, replyText: 'A reply that lands while the list is scrolled up.' }], true);
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(published.seqs[0]), { timeout: 5000 });
  await expect(button).toBeVisible();
  await scrollListTo(list, 'bottom');
  await expect(button, 'scrolling to the bottom by hand hides New messages').toHaveCount(0);
});

/** C10: in a long chat the list is still at the bottom after each of several sends and their replies. */
test('C10: in a long chat the list stays at the bottom through several sends and their replies', async ({ page }) => {
  test.slow(); // eight turns one after the other: the 45 s of a quick host is too little for a slow one
  const field = await open(page);
  const { list } = await longChat(page, 2023, 'C10');
  for (let i = 0; i < 8; i += 1) {
    const sent = await sendWithEnter(page, field, unique(`C10 ${i}`));
    expect(sent.status).toBe(202);
    await expect(replyOf(page, sent.posted.clientId).locator('.text'), `message ${i} gets its reply`).toHaveText(FALLBACK, { timeout: 20_000 });
    await expect.poll(() => fromBottom(list), { message: `after message ${i} the list is at the bottom` }).toBeLessThanOrEqual(24);
    await expect(replyOf(page, sent.posted.clientId), `and the reply of message ${i} is in view`).toBeInViewport();
  }
  await expect(page.getByRole('button', { name: 'New messages' }), 'the list was never left behind').toHaveCount(0);
});

/** C11: in a fresh chat the first message replaces the empty chat panel at once, before the server has answered its post. */
test('C11: the first message replaces the empty chat panel at once, before the server answers', async ({ page }) => {
  // The snapshot is cut to an empty chat, so the case does not depend on what other cases left on the panel user's session.
  await page.route(`**${STATE}`, async (route: Route) => {
    const response = await route.fetch();
    const body = (await response.json()) as Json;
    await route.fulfill({ response, json: { ...body, chat: [] } });
  });
  const stuck: Route[] = [];
  await page.route(`**${MESSAGES}`, async (route: Route) => {
    stuck.push(route);
  });
  const field = await open(page);
  const posts = watchPosts(page);
  const empty = page.locator('app-chat-panel app-empty-chat');
  await expect(empty, 'a snapshot with no chat shows the empty chat panel').toHaveCount(1);
  await expect(page.locator('app-chat-panel [data-part="user"]')).toHaveCount(0);

  const text = unique('C11');
  await field.fill(text);
  await field.press('Enter');
  await expect.poll(() => posts().length).toBe(1);
  const clientId = posts()[0]!.clientId;
  await expect(userOf(page, clientId).locator('.bubble'), 'the bubble shows while the post has no answer').toHaveText(text);
  await expect(empty, 'and has replaced the empty chat panel').toHaveCount(0);
  await expect(replyOf(page, clientId), 'a post in flight has no indicator').toHaveCount(0);
  await expect(userOf(page, clientId).locator('.failed')).toHaveCount(0);

  expect(stuck, 'the post is held, not answered').toHaveLength(1);
  await stuck[0]!.continue();
  await expect(replyOf(page, clientId).locator('.text'), 'the answered post gets its turn and reply').toHaveText(FALLBACK, { timeout: 20_000 });
  await expect(empty, 'the empty chat panel does not come back').toHaveCount(0);
  await expect(userOf(page, clientId), 'one bubble').toHaveCount(1);
});

/**
 * C12: a fallback reply reads in the words of its own reason. C2's stub model answers every turn with the reason that the
 * generic sentence names, so only a seeded turn can show that the page passes the turn's reason to the catalog: a reason of its
 * own reads as that reason, a catalog key the page does not render reads as the turn fallback with the turn's own reason, and a
 * reason outside the 12 reads as the generic one.
 */
test('C12: a fallback reply names its own reason, and an unknown reason reads as the generic one', async ({ page }) => {
  const stamp = Date.now().toString(36);
  const sentence = (reason: string): string => `I couldn't answer that: ${reason}. Nothing was changed.`;
  const cases = [
    { reason: 'timeout', key: 'conversation.turnFallback', words: "the model didn't answer within 60 seconds" },
    { reason: 'no_key', key: 'conversation.turnFallback', words: 'no model key is set' },
    { reason: 'rate_limited', key: 'conversation.dailyCap', words: 'the model was busy and retries ran out' },
    { reason: 'not_a_reason', key: 'conversation.turnFallback', words: "the model's reply couldn't be used" },
  ];
  const turns: SeedTurn[] = cases.map((entry, i) => ({
    createdAt: `2025-01-01T10:0${i + 1}:00Z`,
    text: `zz C12 ${stamp} ${entry.reason}`,
    replyText: '',
    catalogKey: entry.key,
    fallbackReason: entry.reason,
  }));
  await open(page);
  const { user } = fixtureUser('PANEL');
  const seeded = await seedTurns(user, turns);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  for (const [i, entry] of cases.entries()) {
    await expect(replyOf(page, seeded.refs[i]!).locator('.text'), `reason ${entry.reason}`).toHaveText(sentence(entry.words));
  }
});

/**
 * C13: at the bottom, the list keeps following new content when more content lands between the panel's own scroll to the
 * bottom and that scroll's event. A ResizeObserver of the test's own, which runs after the panel's in the same frame, adds
 * 200 px under the content once the panel has scrolled for a landed turn, so the scroll event then measures a list 200 px off
 * the bottom; that is content growing, not the user scrolling up, so the next turn must still be followed, with no button.
 */
test('C13: at the bottom, the list follows new content that grows between its own scroll and that scroll\'s event', async ({ page }) => {
  await open(page);
  const { user } = fixtureUser('PANEL');
  const { list, stamp } = await longChat(page, 2020, 'C13');
  await list.evaluate((el) => {
    const content = el.querySelector('.content') as HTMLElement;
    const height = content.getBoundingClientRect().height;
    const observer = new ResizeObserver(() => {
      if (content.getBoundingClientRect().height === height) return;
      observer.disconnect();
      const spacer = document.createElement('div');
      spacer.style.height = '200px';
      spacer.style.flex = 'none';
      el.append(spacer);
      (window as unknown as { grownAt?: number }).grownAt = el.scrollTop;
    });
    observer.observe(content);
  });
  const first = await seedTurns(user, [{ createdAt: '2020-02-01T10:00:00Z', text: `zz C13 ${stamp} first`, replyText: 'A reply that lands at the bottom.' }], true);
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(first.seqs[0]), { timeout: 5000 });
  await expect.poll(() => page.evaluate(() => (window as unknown as { grownAt?: number }).grownAt !== undefined), { message: 'the content grew right after the panel scrolled' }).toBe(true);
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));

  const second = await seedTurns(user, [{ createdAt: '2020-02-01T10:01:00Z', text: `zz C13 ${stamp} second`, replyText: 'A second reply that lands at the bottom.' }], true);
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(second.seqs[0]), { timeout: 5000 });
  await expect(userOf(page, second.refs[0]!), 'the turn is in the list').toHaveCount(1);
  await expect.poll(() => fromBottom(list), { message: 'the list still follows new content' }).toBeLessThanOrEqual(24);
  await expect(page.getByRole('button', { name: 'New messages' }), 'and New messages does not show').toHaveCount(0);
});

/** C14: the time under a message follows the browser's zone and hour format: in Berlin with en-GB it is a 24-hour time. */
test.describe('C14: another zone and locale', () => {
  test.use({ timezoneId: 'Europe/Berlin', locale: 'en-GB' });

  test('C14: the time under a message is in the browser\'s zone and hour format', async ({ page }) => {
    const stamp = Date.now().toString(36);
    await open(page);
    const { user } = fixtureUser('PANEL');
    const seeded = await seedTurns(user, [{ createdAt: '2025-05-01T14:11:00Z', text: `zz C14 ${stamp}`, replyText: 'A reply.' }]);
    await page.reload();
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    await expect(userOf(page, seeded.refs[0]!).locator('.when'), '14:11 UTC is 16:11 in Berlin summer time, as a 24-hour time').toHaveText('16:11');
  });
});

/**
 * C15: a reply through the stack's stub Decide is a fallback that has no decision row, so its strip is the fallback strip alone:
 * Tell now, the Fallback flag and the reason as a sentence, with no confidence, no cost and no Details button.
 */
test('C15: a fallback reply through the stub Decide shows the fallback strip', async ({ page }) => {
  const field = await open(page);
  const { posted } = await sendWithEnter(page, field, unique('C15'));
  const reply = replyOf(page, posted.clientId);
  await expect(reply.locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
  const strip = reply.locator('app-decision-strip');
  await expect(strip, 'the reply has one strip').toHaveCount(1);
  await expect(strip.locator('app-outcome-chip')).toHaveText('Tell now');
  await expect(strip.locator('app-fallback-flag')).toHaveText('Fallback');
  await expect(strip.locator('.reason')).toHaveText(["The model's reply couldn't be used."]);
  await expect(strip, 'no confidence').not.toContainText('Confidence');
  await expect(strip, 'no cost').not.toContainText('$');
  await expect(strip.getByRole('button'), 'no Details button').toHaveCount(0);
});
