import { expect, test, type Locator, type Page, type Request, type Route } from '@playwright/test';

import { signIn, signInReadme, watchViolations } from '../sign-in/helpers';
import { fixtureUser, seedTurns, type SeedTurn } from '../support/iris';

/**
 * Story 2.5, the chat panel (C1 to C7), in a real browser against a real stack. C1 reads the README account and sends nothing;
 * every other case signs in as the panel fixture user that test-sign-in.sh created (OCUTALON_PANEL_USER) and sends or seeds on
 * its own session, so that no spec publishes on the README session or the instance stream (api.spec pins their counts) or
 * touches the chat user's chat. Each case asserts only on the clientIds and refs it made. The browser runs in Asia/Kolkata with
 * the en-US locale, so a time is the same wherever the specs run.
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

/** A time as the page shows it for the test's zone and locale, with the narrow no-break space read as a space. */
const clock = (iso: string): string =>
  new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Kolkata' }).format(new Date(iso)).replace(/\u202F/g, ' ');

/** A text with its whitespace collapsed and the narrow no-break space read as a space. */
const plain = (text: string | null): string => (text ?? '').replace(/\u202F/g, ' ').replace(/\s+/g, ' ').trim();

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

/** The computed colour of a token, as the page paints it. */
function tokenColor(page: Page, token: string): Promise<string> {
  return page.evaluate((name) => {
    const probe = document.createElement('span');
    probe.style.color = `var(${name})`;
    document.body.append(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  }, token);
}

/** The distance in px between the bottom of the list's content and the bottom of its view. */
const fromBottom = (list: Locator): Promise<number> => list.evaluate((el) => el.scrollHeight - el.scrollTop - el.clientHeight);

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
  for (const [i, outcome] of ['ignore', 'digest', 'tell-now', 'act'].entries()) {
    const chip = chips.nth(i).locator('.chip');
    await expect(chip.locator('svg[aria-hidden="true"]'), `${outcome} has its icon, hidden from assistive technology`).toHaveCount(1);
    expect(await chip.locator('svg path, svg polyline').count(), `${outcome}'s icon is drawn`).toBeGreaterThan(0);
    await expect(chip).toHaveCSS('background-color', await tokenColor(page, `--outcome-chip-${outcome}-background`));
    await expect(chip).toHaveCSS('color', await tokenColor(page, `--outcome-chip-${outcome}-foreground`));
    await expect(chip, `${outcome} is not focusable`).not.toHaveAttribute('tabindex', /.*/);
  }
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

  const text = unique('C2');
  const { posted, status } = await sendWithEnter(page, field, `  ${text}\nsecond line  `);
  expect(status, 'the post is accepted').toBe(202);
  expect(Object.keys(posted).sort(), 'the body names no session').toEqual(['clientId', 'fromGuide', 'text']);
  expect(posted.clientId).toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(posted.text, 'the text is trimmed at both ends and keeps its line break').toBe(`${text}\nsecond line`);
  expect(posted.fromGuide).toBe(false);
  await expect(field, 'the field is empty').toHaveValue('');
  await expect(field, 'and focused').toBeFocused();

  const bubble = userOf(page, posted.clientId).locator('.bubble');
  await expect(bubble).toHaveText(`${text}\nsecond line`);
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
  await field.dispatchEvent('keydown', { key: 'Enter', keyCode: 229, isComposing: true, bubbles: true, cancelable: true });
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
    await expect(userOf(page, clientId).locator('.failed')).toHaveCount(0);
    await expect(userOf(page, clientId).locator('.failed'), 'Not sent after the 10 s limit').toHaveText('Not sent', { timeout: 15_000 });
    expect(Date.now() - sentAt, 'and not before it').toBeGreaterThanOrEqual(9_500);
    await expect(userOf(page, clientId).locator('.bubble')).toHaveText(text);

    await retryOf(page, clientId).click();
    await expect(replyOf(page, clientId).locator('.text')).toHaveText(FALLBACK, { timeout: 20_000 });
    expect(posts().map((posted) => posted.clientId), 'the retry posts the same clientId').toEqual([clientId, clientId]);
    expect(await turnsWith(page, clientId), 'the server holds one turn').toHaveLength(1);
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
    { createdAt: '2030-01-01T10:03:00Z', text: `zz C5 ${stamp} third`, replyText: blocks },
    { createdAt: '2030-01-01T10:01:00Z', text: `zz C5 ${stamp} first`, replyText: 'Sent from Telegram.', channel: 'telegram' },
    { createdAt: '2030-01-01T10:02:00Z', text: `zz C5 ${stamp} second`, replyText: 'Sent from the guide.', fromGuide: true },
  ];
  await open(page);
  const { user } = fixtureUser('PANEL');
  const seeded = await seedTurns(user, turns);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

  const bubbles = page.locator('app-chat-panel .bubble').filter({ hasText: `zz C5 ${stamp}` });
  await expect(bubbles, 'the turns are in CreatedAt order, not the order they were written').toHaveText([`zz C5 ${stamp} first`, `zz C5 ${stamp} second`, `zz C5 ${stamp} third`]);
  const [thirdRef, firstRef, secondRef] = seeded.refs as [string, string, string];
  expect(plain(await userOf(page, firstRef).locator('.when').textContent())).toBe(`via Telegram \u00B7 ${clock('2030-01-01T10:01:00Z')}`);
  expect(plain(await userOf(page, secondRef).locator('.when').textContent())).toBe(`From the demo guide \u00B7 ${clock('2030-01-01T10:02:00Z')}`);
  expect(plain(await userOf(page, thirdRef).locator('.when').textContent()), 'a web turn has no caption').toBe(clock('2030-01-01T10:03:00Z'));

  const reply = replyOf(page, thirdRef);
  const body = reply.locator('.text');
  await expect(body.locator('p.para'), 'two paragraphs and the long one').toHaveCount(3);
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
  await expect(body.getByRole('link', { name: 'the guide (opens in a new tab)' })).toHaveCount(1);
  await expect(body.getByRole('link', { name: 'https://example.com/docs (opens in a new tab)' })).toHaveCount(1);
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
  const stamp = Date.now().toString(36);
  const many: SeedTurn[] = Array.from({ length: 30 }, (_unused, i) => ({
    createdAt: `2031-01-01T10:${String(10 + i).padStart(2, '0')}:00Z`,
    text: `zz C6 ${stamp} message ${i}`,
    replyText: `Reply ${i} to message ${i}.\nIt has a second line so that the list is tall.`,
  }));
  await seedTurns(user, many);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const list = page.locator('app-chat-panel > .list');
  await expect.poll(() => fromBottom(list), { message: 'the list starts at the bottom' }).toBeLessThanOrEqual(24);
  await expect(page.locator('app-chat-panel .bubble').filter({ hasText: `message 29` }).last()).toBeInViewport();
  await expect(page.getByRole('button', { name: 'New messages' })).toHaveCount(0);

  await list.evaluate((el) => (el.scrollTop = 0));
  await expect.poll(() => list.evaluate((el) => el.scrollTop)).toBe(0);
  const firstBubble = page.locator('app-chat-panel [data-part="user"] .bubble').first();
  const before = (await firstBubble.boundingBox())!;

  const published = await seedTurns(user, [{ createdAt: '2031-02-01T10:00:00Z', text: `zz C6 ${stamp} published`, replyText: 'A reply that lands while the list is scrolled up.' }], true);
  const ref = published.refs[0]!;
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(published.seqs[0]), { timeout: 2000 });
  await expect(userOf(page, ref), 'the turn is in the list').toHaveCount(1);
  expect(await list.evaluate((el) => el.scrollTop), 'scrollTop did not change').toBe(0);
  expect((await firstBubble.boundingBox())!, 'nor did the first visible entry move').toEqual(before);

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
  await expect(userOf(page, ref), "and focuses the new turn's element").toBeFocused();
  await expect(button).toHaveCount(0);

  const followed = await seedTurns(user, [{ createdAt: '2031-02-02T10:00:00Z', text: `zz C6 ${stamp} followed`, replyText: 'A reply that lands while the list is at the bottom.' }], true);
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

/** C8: a turn that stays running shows "Working \u00B7 N s" after 10 seconds, with the whole spoken form, and the indicator is no live region. */
test('C8: after 10 seconds the working indicator adds the elapsed seconds, spoken in full', async ({ page }) => {
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
  const startedAt = Date.now();

  await expect(indicator.locator('[aria-hidden="true"]'), 'after 10 seconds the working time shows').toHaveText(/^Working \u00B7 \d+ s$/, { timeout: 20_000 });
  expect(Date.now() - startedAt, 'and not before 10 s since the page saw the turn running').toBeGreaterThanOrEqual(8_000);
  const shown = await indicator.evaluate((el) => ({
    visible: el.querySelector('[aria-hidden="true"]')?.textContent?.trim() ?? '',
    spoken: el.querySelector('.visually-hidden')?.textContent?.trim() ?? '',
  }));
  const seconds = /^Working \u00B7 (\d+) s$/.exec(shown.visible)?.[1];
  expect(Number(seconds), 'whole seconds, 10 or more').toBeGreaterThanOrEqual(10);
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
  const { list, stamp } = await longChat(page, 2032, 'C9');
  const button = page.getByRole('button', { name: 'New messages' });

  await list.evaluate((el) => (el.scrollTop = 0));
  await expect.poll(() => list.evaluate((el) => el.scrollTop)).toBe(0);
  const hold = await holdEvents(page);
  const sent = await sendWithEnter(page, field, unique('C9'));
  expect(sent.status).toBe(202);
  await expect.poll(() => fromBottom(list), { message: 'Send takes a list that is scrolled up to the bottom' }).toBeLessThanOrEqual(24);
  await expect(button, 'the user\u2019s own message needs no button').toHaveCount(0);

  await list.evaluate((el) => (el.scrollTop = 0));
  await expect.poll(() => list.evaluate((el) => el.scrollTop)).toBe(0);
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

  await list.evaluate((el) => (el.scrollTop = 0));
  await expect.poll(() => list.evaluate((el) => el.scrollTop)).toBe(0);
  const published = await seedTurns(user, [{ createdAt: '2032-02-01T10:00:00Z', text: `zz C9 ${stamp} published`, replyText: 'A reply that lands while the list is scrolled up.' }], true);
  await expect(page.locator('main.main')).toHaveAttribute('data-session-seq', String(published.seqs[0]), { timeout: 5000 });
  await expect(button).toBeVisible();
  await list.evaluate((el) => (el.scrollTop = el.scrollHeight));
  await expect(button, 'scrolling to the bottom by hand hides New messages').toHaveCount(0);
});

/** C10: in a long chat the list is still at the bottom after each of several sends and their replies. */
test('C10: in a long chat the list stays at the bottom through several sends and their replies', async ({ page }) => {
  const field = await open(page);
  const { list } = await longChat(page, 2033, 'C10');
  for (let i = 0; i < 8; i += 1) {
    const sent = await sendWithEnter(page, field, unique(`C10 ${i}`));
    expect(sent.status).toBe(202);
    await expect(replyOf(page, sent.posted.clientId).locator('.text'), `message ${i} gets its reply`).toHaveText(FALLBACK, { timeout: 20_000 });
    await expect.poll(() => fromBottom(list), { message: `after message ${i} the list is at the bottom` }).toBeLessThanOrEqual(24);
    await expect(replyOf(page, sent.posted.clientId), `and the reply of message ${i} is in view`).toBeInViewport();
  }
  await expect(page.getByRole('button', { name: 'New messages' }), 'the list was never left behind').toHaveCount(0);
});
