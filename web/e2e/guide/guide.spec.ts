import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { signInReadmeLoaded } from '../support/floor';
import { changeSnapshot, MESSAGES } from '../support/api';
import { announcedTexts, plain, recordAnnouncements, tokenColor } from '../support/page';

/**
 * The demo guide and the Break the feed box on the sign-in stack, with the README account (Story 4.4, matrix rows 1 to 14). Q1 reads the real
 * blank guide of the README session (it watches nothing on this stack, api.spec.ts); every other case answers the page's /state with a
 * guide that it names (changeSnapshot), routes the page's POSTs (Q10 also adds session events to its polls, liveEvents) and writes nothing
 * to the server. The stack is in demo mode (every
 * throwaway is), so the guide shows in all of them.
 */
const BREAK_FEED = '**/ocutalon/api/v1/demo/break-feed';

const P1 = 'Watch the Orders production and only tell me if something needs me.';
const P2 = 'Remind me in 1 minute to stretch.';
const P3 = 'Press Break the feed. The partner will send 50 orders in a new date format.';
const P4 = 'Approve the fix on the simulated phone, or in the chat.';
const P5 = "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision.";
const H1 = 'Ask OcuTalon to watch the Orders production first (step 1).';
const H2 = 'Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.';
const SENT = 'Sent. OcuTalon usually notices within a minute.';
const SENDING = 'Sending 50 orders\u2026';
const STILL = 'Still waiting. The notice will appear in the chat and on the Simulated phone tab.';
const NO_NOTICE = "No notice after 3 minutes, so something went wrong with this run. Open the Orders watch's trace in Background checks, or try again.";
const LABELS = ['Watch', 'Reminder', 'Break the feed', 'Approve', 'Open the trace'];

/** A guide view whose first `done` steps are done and whose current step is the next; `over` replaces fields of it. */
function guideOf(done: number, over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    runEpoch: 1,
    step: Math.min(5, done + 1),
    finished: false,
    steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: step <= done })),
    breakFeed: { active: false, reason: 'not_watching' },
    step4Variant: 'unpaired',
    telegramRow: false,
    ...over,
  };
}

/** The accessible name of a step: "Step 3, Break the feed, current". */
const stepName = (n: number, state: 'current' | 'done' | 'upcoming'): string => `Step ${n}, ${LABELS[n - 1]}, ${state}`;

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const stepOf = (page: Page, n: number, state: 'current' | 'done' | 'upcoming'): Locator => guideRegion(page).getByRole('button', { name: stepName(n, state), exact: true });
const breakButton = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'Break the feed', exact: true });
const boxOf = (page: Page): Locator => page.locator('app-break-feed-box');
const promptOf = (page: Page): Locator => guideRegion(page).locator('.prompt');

/**
 * Answers the page's /state with the guide that `holder.guide` names when the page loads; the demo mode is the stack's. With `chat: false`
 * the chat, the approvals and the checks are empty, so Background checks holds the rail's second empty text.
 */
async function serve(page: Page, holder: { guide: Record<string, unknown>; chat?: boolean }): Promise<void> {
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = holder.guide;
    if (holder.chat === false) {
      snapshot['chat'] = [];
      const rail = snapshot['rail'] as { approvals: unknown[]; checks: unknown[] };
      rail.approvals = [];
      rail.checks = [];
    }
  });
}

/** One session event that a case adds to the page's polls. */
type QueuedEvent = { type: string; payload: Record<string, unknown> };

/**
 * Routes the page's polls: each batch that the returned function queues goes into the next real answer, after its session events and with
 * the Seqs that follow them, so the page applies it as a live update (no skip, no reload). The function resolves once that answer is served.
 */
async function liveEvents(page: Page): Promise<(events: QueuedEvent[]) => Promise<void>> {
  const queue: QueuedEvent[][] = [];
  let queued = 0;
  let served = 0;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    const batch = queue.shift();
    if (batch === undefined) {
      await route.fulfill({ response });
      return;
    }
    const body = (await response.json()) as { events: Array<Record<string, unknown>> };
    let seq = Number(new URL(route.request().url()).searchParams.get('after'));
    for (const event of body.events) {
      if (event['stream'] === 'session') seq = Math.max(seq, Number(event['seq']));
    }
    for (const event of batch) {
      seq += 1;
      body.events.push({ seq, stream: 'session', ts: iso(Date.now()), type: event.type, payload: event.payload });
    }
    await route.fulfill({ response, json: body });
    served += 1;
  });
  return async (events) => {
    queued += 1;
    const target = queued;
    queue.push(events);
    await expect.poll(() => served, { message: 'a poll carried the queued events' }).toBeGreaterThanOrEqual(target);
  };
}

/** Signs in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

/** Reloads the page with the guide that the holder names now. */
async function reopen(page: Page): Promise<void> {
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

/** The page's clock now (ms). */
const now = (page: Page): Promise<number> => page.evaluate(() => Date.now());

/** An ISO time to the second, as the server writes startedAt. */
const iso = (ms: number): string => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

/** Q1: the real blank guide of the README session: the region, its first row, the prompt bar and the box. */
test('Q1: the real blank guide shows between the banners and the rail, with its first row, prompt bar and box', async ({ page }) => {
  await open(page);

  const guide = guideRegion(page);
  await expect(guide, 'the region Demo guide, labelled by its visible label').toHaveCount(1);
  await expect(guide).toHaveAccessibleName('Demo guide');
  await expect(guide.getByRole('heading'), 'it has no heading').toHaveCount(0);
  const order = await page.evaluate(() => {
    const nodes = ['.banner-slot', 'app-demo-guide', 'section.rail', 'main'].map((selector) => document.querySelector(selector));
    return nodes.map((node, i) => i === 0 || (!!node && !!nodes[i - 1] && !!(nodes[i - 1]!.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING)));
  });
  expect(order, 'between the banner slot and the rail and main').toEqual([true, true, true, true]);
  await expect(page.locator('main > app-demo-guide, main app-demo-guide'), 'and outside main').toHaveCount(0);

  const steps = guide.getByRole('list').getByRole('button');
  await expect(steps, 'five steps').toHaveCount(5);
  await expect(stepOf(page, 1, 'current'), 'step 1 is current').toHaveAttribute('aria-current', 'step');
  for (const n of [2, 3, 4, 5]) {
    await expect(stepOf(page, n, 'upcoming'), `step ${n} is upcoming`).not.toHaveAttribute('aria-current', /.*/);
  }
  await expect(guide.locator('.step.current .marker'), 'the current marker is a disc with the number').toHaveText('1');
  await expect(guide.locator('.step.upcoming .marker'), 'the others are hollow circles with theirs').toHaveText(['2', '3', '4', '5']);
  await expect(guide.locator('[aria-hidden="true"] svg').first(), 'the chevrons are decorative').toBeAttached();
  await expect(guide.locator('.chevron'), 'four chevrons join the five steps').toHaveCount(4);
  expect(await guide.locator('.chevron').evaluateAll((nodes) => nodes.every((node) => node.getAttribute('aria-hidden') === 'true')), 'and each is aria-hidden').toBe(true);
  await expect(guide.locator('.step-label'), 'with the step labels').toHaveText(LABELS);
  await expect(guide.getByText('About 2 minutes', { exact: true })).toBeVisible();
  const hide = guide.getByRole('button', { name: 'Hide guide', exact: true });
  await expect(hide, 'Hide guide is a ghost button').toHaveClass(/button-ghost/);
  await expect(hide, 'and has no aria-expanded').not.toHaveAttribute('aria-expanded', /.*/);

  const prompt = promptOf(page);
  await expect(prompt.locator('.next')).toHaveText('Next:');
  await expect(prompt.locator('.prompt-text')).toHaveText(`"${P1}"`);
  await expect(prompt.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await expect(prompt, 'the prompt bar is sunken').toHaveCSS('background-color', await tokenColor(page, '--sunken'));

  const box = boxOf(page);
  await expect(box.getByText('Demo control', { exact: true }), 'the box always shows Demo control').toBeVisible();
  const button = breakButton(page);
  await expect(button, 'the inactive button is Break the feed').toHaveAttribute('aria-disabled', 'true');
  await expect(button).not.toHaveAttribute('disabled', /.*/);
  await expect(button).toHaveClass(/button-inactive/);
  await expect(button, 'described by its hint').toHaveAccessibleDescription(H1);
  await expect(box.locator('.hint'), 'the hint under it').toHaveText(H1);
  await expect(box.getByRole('button', { name: 'Do step 1', exact: true }), 'and a Do step 1 link-styled button').toBeVisible();

  await expect(guide.locator('[aria-live], [aria-atomic], [role="log"], [role="status"], [role="alert"], [role="timer"]'), 'neither the guide nor the box is live').toHaveCount(0);
  const heights = await steps.evaluateAll((nodes) => nodes.map((node) => node.getBoundingClientRect().height));
  expect(Math.min(...heights), 'every step is at least the 32px target of DESIGN').toBeGreaterThanOrEqual(32);
});

/** Q1: the demo texts replace the old ones in the empty chat and in Background checks (the old texts outside demo mode: the demo-switch badge spec). */
test('Q1: the empty chat and Background checks point at the guide in demo mode', async ({ page }) => {
  await serve(page, { guide: guideOf(0), chat: false });
  await open(page);

  const lines = page.getByRole('main').locator('app-empty-chat .line');
  await expect(lines).toHaveText([
    'It watches your productions from inside IRIS, and every decision is a production message you can trace.',
    'Anything risky waits for your approval.',
    'Start with step 1 of the demo guide above.',
  ]);
  await expect(page.getByRole('region', { name: 'Status', exact: true }).locator('.empty').nth(1)).toHaveText('Nothing yet. Step 1 of the guide sets up a watch.');
  await expect(page.getByRole('heading', { level: 2 }), 'the guide adds no heading').toHaveText(['Status', 'Chat']);
});

/** Q2: any step can be selected in any order; steps 3 to 5 show their prompts (Story 4.7); nothing is marked done by a click. */
test('Q2: selecting steps changes the prompt and the bar under the step, and marks nothing done', async ({ page }) => {
  await serve(page, { guide: guideOf(0) });
  await recordAnnouncements(page);
  await open(page);

  const prompt = promptOf(page).locator('.prompt-text');
  await expect(prompt).toHaveText(`"${P1}"`);
  await stepOf(page, 2, 'upcoming').click();
  await expect(prompt, 'step 2 shows its prompt').toHaveText(`"${P2}"`);
  const bar = await stepOf(page, 2, 'upcoming').evaluate((el) => getComputedStyle(el, '::after').borderBottomWidth);
  expect(bar, 'the selected step has a 2px bottom bar').toBe('2px');
  const barColor = await stepOf(page, 2, 'upcoming').evaluate((el) => getComputedStyle(el, '::after').borderBottomColor);
  expect(barColor, 'in ink, never a teal ring').toBe(await tokenColor(page, '--ink'));
  await expect(stepOf(page, 1, 'current'), 'aria-current stays on the current step').toHaveAttribute('aria-current', 'step');
  await expect(stepOf(page, 2, 'upcoming')).not.toHaveAttribute('aria-current', /.*/);

  const action = (name: string): Locator => promptOf(page).getByRole('button', { name, exact: true });
  await stepOf(page, 5, 'upcoming').click();
  await expect(prompt, 'step 5 shows its prompt').toHaveText(`"${P5}"`);
  await expect(promptOf(page).getByRole('button').or(promptOf(page).getByRole('link')), 'and no action: the view has no trace').toHaveCount(0);
  await stepOf(page, 4, 'upcoming').click();
  await expect(prompt, 'step 4 shows the unpaired text').toHaveText(`"${P4}"`);
  await expect(action('Show me'), 'with Show me').toBeVisible();
  await stepOf(page, 3, 'upcoming').click();
  await expect(prompt, 'step 3 shows its prompt').toHaveText(`"${P3}"`);
  await expect(promptOf(page).getByRole('button'), 'with no button').toHaveCount(0);
  await stepOf(page, 1, 'current').click();
  await expect(prompt, 'back to step 1, in any order').toHaveText(`"${P1}"`);
  for (const n of [2, 3, 4, 5]) {
    await expect(stepOf(page, n, 'upcoming'), `a click marked step ${n} done: it did not`).toHaveCount(1);
  }
  await expect(guideRegion(page).locator('.step.done'), 'nothing is done').toHaveCount(0);
  expect(await announcedTexts(page), 'selecting a step announces nothing: only an advance of the view does').toEqual([]);
});

/** Q2: a step is done only from the view: the server's view with two steps done shows their check, and the current step is the view's. */
test('Q2: the markers, names and aria-current come from the guide view', async ({ page }) => {
  await serve(page, { guide: guideOf(2, { breakFeed: { active: true } }) });
  await open(page);

  await expect(stepOf(page, 1, 'done')).toHaveCount(1);
  await expect(stepOf(page, 2, 'done')).toHaveCount(1);
  await expect(stepOf(page, 3, 'current')).toHaveAttribute('aria-current', 'step');
  await expect(stepOf(page, 4, 'upcoming')).toHaveCount(1);
  await expect(stepOf(page, 5, 'upcoming')).toHaveCount(1);
  await expect(guideRegion(page).locator('.step.done .marker svg'), 'a check for each done step').toHaveCount(2);
  await expect(guideRegion(page).locator('.step.selected'), 'the selection starts on the current step').toHaveAttribute('aria-label', stepName(3, 'current'));
  await expect(promptOf(page).locator('.prompt-text'), 'which shows its prompt').toHaveText(`"${P3}"`);
  await expect(promptOf(page).getByRole('button'), 'and no button').toHaveCount(0);
});

/** Q3: Send posts the exact prompt with fromGuide, shows its caption, announces nothing, and a second press while the first is sending sends nothing. */
test('Q3: Send posts the exact prompt as the guide\'s, shows its caption and announces nothing', async ({ page }) => {
  const bodies: Array<{ clientId: string; text: string; fromGuide: boolean }> = [];
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  let holdFirst = true;
  await page.route(`**${MESSAGES}`, async (route: Route) => {
    const body = route.request().postDataJSON() as { clientId: string; text: string; fromGuide: boolean };
    bodies.push(body);
    if (holdFirst) {
      holdFirst = false;
      await gate;
    }
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  });
  await serve(page, { guide: guideOf(0), chat: false });
  await recordAnnouncements(page);
  await open(page);

  const send = promptOf(page).getByRole('button', { name: 'Send', exact: true });
  await send.dblclick();
  await expect.poll(() => bodies.length, { message: 'the first press posted' }).toBe(1);
  await page.waitForTimeout(300);
  expect(bodies, 'a second press while the first message is still sending posts nothing').toHaveLength(1);
  expect(bodies[0]!.text, 'the exact prompt of step 1').toBe(P1);
  expect(bodies[0]!.fromGuide, 'from the guide').toBe(true);
  expect(Object.keys(bodies[0]!).sort(), 'with the clientId, the text and the flag, and no session').toEqual(['clientId', 'fromGuide', 'text']);
  release();
  const message = page.getByRole('main').locator('app-user-message').filter({ hasText: P1 });
  await expect(message).toHaveCount(1);
  await expect(message.locator('.when'), 'with the caption and the time').toHaveText(/^From the demo guide \u00B7 \S+/);

  await stepOf(page, 2, 'upcoming').click();
  await promptOf(page).getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => bodies.length).toBe(2);
  expect(bodies[1]!.text, 'the exact prompt of step 2').toBe(P2);
  expect(bodies[1]!.fromGuide).toBe(true);
  await expect(page.getByRole('main').locator('app-user-message').filter({ hasText: P2 }).locator('.when')).toHaveText(/^From the demo guide/);
  await page.waitForTimeout(1500);
  expect(await announcedTexts(page), 'the guide sends are not announced').toEqual([]);
});

/** Q4: the Telegram row shows before the prompt when the view says so. */
test('Q4: the Telegram row follows the view and has no button', async ({ page }) => {
  const holder = { guide: guideOf(0, { telegramRow: true }) };
  await serve(page, holder);
  await open(page);

  const line = promptOf(page).locator('.telegram');
  await expect(line).toHaveText('Optional: scan the QR code in the Telegram card to get the notice on your own phone.');
  await expect(promptOf(page).getByRole('button'), 'the row has no button of its own: Send is the prompt\'s').toHaveCount(1);
  const order = await promptOf(page).evaluate((el) => [...el.children].map((child) => child.className));
  expect(order, 'it comes before the prompt line').toEqual(['telegram', 'prompt-line']);

  holder.guide = guideOf(0);
  await reopen(page);
  await expect(promptOf(page).locator('.telegram'), 'false: absent').toHaveCount(0);
});

/** Q5: the box's look follows the view: inactive with the reason's hint, the attention style, the tag and bar on step 3, secondary on step 5. */
test('Q5: the box shows the hints, the styles, the tag and Do step 1 as the view says', async ({ page }) => {
  const holder = { guide: guideOf(0), chat: false };
  await serve(page, holder);
  await open(page);

  // Not watching: Do step 1 selects step 1.
  await stepOf(page, 3, 'upcoming').click();
  await expect(promptOf(page).locator('.prompt-text')).toHaveText(`"${P3}"`);
  await expect(breakButton(page)).toHaveAccessibleDescription(H1);
  await expect(boxOf(page), 'no 4px bar while inactive: the box has its 1px divider').toHaveCSS('border-left-width', '1px');
  await boxOf(page).getByRole('button', { name: 'Do step 1', exact: true }).click();
  await expect(promptOf(page).locator('.prompt-text'), 'Do step 1 selects step 1').toHaveText(`"${P1}"`);
  await expect(page.getByRole('main').locator('app-user-message'), 'and sends nothing').toHaveCount(0);

  // Incident in progress: the other hint, and no Do step 1.
  holder.guide = guideOf(3, { breakFeed: { active: false, reason: 'incident_in_progress', stage: 'notice_arrived', startedAt: iso(Date.now() - 30_000) } });
  await reopen(page);
  await expect(breakButton(page)).toHaveAttribute('aria-disabled', 'true');
  await expect(breakButton(page)).toHaveAccessibleDescription(H2);
  await expect(boxOf(page).locator('.hint')).toHaveText(H2);
  await expect(boxOf(page).getByRole('button', { name: 'Do step 1', exact: true }), 'no Do step 1').toHaveCount(0);
  await expect(boxOf(page).locator('.line'), 'and no status line after the notice').toHaveCount(0);

  // Active on step 3: attention, zap, the tag and the 4px bar.
  holder.guide = guideOf(2, { breakFeed: { active: true } });
  await reopen(page);
  const button = breakButton(page);
  await expect(button).toHaveClass(/button-attention/);
  await expect(button).not.toHaveAttribute('aria-disabled', /.*/);
  await expect(button.locator('svg'), 'with the zap icon').toHaveCount(1);
  await expect(boxOf(page).getByText('Next step', { exact: true }), 'the tag shows on step 3').toBeVisible();
  await expect(boxOf(page), 'the 4px action bar on its left').toHaveCSS('border-left-width', '4px');
  await expect(boxOf(page)).toHaveCSS('border-left-color', await tokenColor(page, '--action'));
  await expect(button, 'an active button has no description').not.toHaveAttribute('aria-describedby', /.*/);

  // Active on another step: attention, no tag; on step 5: secondary, no tag.
  holder.guide = guideOf(0, { breakFeed: { active: true } });
  await reopen(page);
  await expect(breakButton(page)).toHaveClass(/button-attention/);
  await expect(boxOf(page).getByText('Next step', { exact: true })).toHaveCount(0);
  await expect(boxOf(page), 'and no 4px bar without the tag').toHaveCSS('border-left-width', '1px');
  holder.guide = guideOf(4, { breakFeed: { active: true } });
  await reopen(page);
  await expect(breakButton(page)).toHaveClass(/button-secondary/);
  await expect(boxOf(page).getByText('Next step', { exact: true })).toHaveCount(0);
  await expect(boxOf(page), 'nor on step 5').toHaveCSS('border-left-width', '1px');

  // A press on an inactive button sends nothing.
  holder.guide = guideOf(0);
  let pressed = 0;
  await page.route(BREAK_FEED, async (route) => {
    pressed += 1;
    await route.fulfill({ status: 500, contentType: 'application/json', body: '{}' });
  });
  await reopen(page);
  await breakButton(page).click({ force: true });
  await breakButton(page).focus();
  await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  expect(pressed, 'a press on the inactive button makes no request').toBe(0);
  await expect(breakButton(page), 'and it stays focusable').toBeFocused();
});

/** Q6: a press: busy with its line, then sent and announced once with the elapsed time; a 409 shows its reason; a 500 adds no text. */
test('Q6: a press is busy, then sent (announced once, with the elapsed time), and the 409s and the 500 are handled', async ({ page }) => {
  const holder = { guide: guideOf(2, { breakFeed: { active: true } }) };
  let answer: (route: Route) => Promise<void> = async () => undefined;
  const requests: string[] = [];
  await page.route(BREAK_FEED, async (route) => {
    requests.push(route.request().postData() ?? '');
    await answer(route);
  });
  await page.clock.install();
  await serve(page, holder);
  await recordAnnouncements(page);
  await open(page);

  // A delayed 200.
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  let startedAt = '';
  answer = async (route) => {
    await gate;
    startedAt = iso(await now(page));
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ state: 'sent', startedAt }) });
  };
  const button = breakButton(page);
  await expect(button).toHaveClass(/button-attention/);
  await button.click();
  await expect(button, 'busy while the press has no answer').toHaveAttribute('aria-busy', 'true');
  await expect(button).toHaveAttribute('aria-disabled', 'true');
  await expect(boxOf(page).locator('.line')).toHaveText(SENDING);
  await expect(button, 'described by the line').toHaveAccessibleDescription(SENDING);
  await expect(boxOf(page).getByText('Next step', { exact: true }), 'the tag leaves once it is pressed').toHaveCount(0);
  await expect(boxOf(page), 'and the 4px bar with it').toHaveCSS('border-left-width', '1px');
  await button.click({ force: true });
  await page.waitForTimeout(300);
  expect(requests, 'a press on the busy button sends nothing more').toHaveLength(1);
  expect(requests[0], 'the body is empty and names no session').toBe('{}');

  release();
  await expect(boxOf(page).locator('.line')).toContainText(SENT);
  await expect(button, 'inactive after the 200, whatever the view still says').toHaveAttribute('aria-disabled', 'true');
  await expect(button).not.toHaveAttribute('aria-busy', /.*/);
  await expect(button).toHaveClass(/button-inactive/);
  await expect(boxOf(page).locator('.line .elapsed')).toContainText(/^\d+ s/);
  await expect.poll(async () => (await announcedTexts(page)).filter((text) => text.includes(SENT)).length, { message: 'announced' }).toBe(1);
  await page.clock.fastForward(23_000);
  await expect(boxOf(page).locator('.line [aria-hidden="true"]'), 'the elapsed time ticks, as "{n} s"').toHaveText(/^2\d s$/);
  await expect(boxOf(page).locator('.line .visually-hidden'), 'and is spoken in full words').toHaveText(/^2\d seconds$/);
  await page.clock.fastForward(40_000);
  await expect(boxOf(page).locator('.line [aria-hidden="true"]'), 'a minute on, in minutes').toHaveText('1 min');
  await page.waitForTimeout(500);
  expect((await announcedTexts(page)).filter((text) => text.includes(SENT)), 'nothing more is announced for the ticking, and Sent once').toHaveLength(1);

  // 409: each code shows its reason until the next view, and announces nothing.
  for (const [code, hint] of [['not_watching', H1], ['incident_in_progress', H2]] as const) {
    holder.guide = guideOf(2, { breakFeed: { active: true } });
    await reopen(page);
    answer = async (route) => {
      await route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code, message: hint } }) });
    };
    const before = (await announcedTexts(page)).length;
    await breakButton(page).click();
    await expect(boxOf(page).locator('.hint'), `${code}: its hint`).toHaveText(hint);
    await expect(breakButton(page)).not.toHaveAttribute('aria-busy', /.*/);
    expect((await announcedTexts(page)).length, `${code}: nothing was announced`).toBe(before);
    await expect(boxOf(page).getByRole('button', { name: 'Do step 1', exact: true }), `${code}: Do step 1 only for not_watching`).toHaveCount(code === 'not_watching' ? 1 : 0);
  }

  // 500: no new text, and the box follows the view.
  holder.guide = guideOf(2, { breakFeed: { active: true } });
  await reopen(page);
  let refused = false;
  answer = async (route) => {
    await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) });
    refused = true;
  };
  await breakButton(page).click();
  await expect.poll(() => refused, { message: 'the 500 was served' }).toBe(true);
  await page.waitForTimeout(300);
  await expect(breakButton(page)).not.toHaveAttribute('aria-busy', /.*/);
  await expect(boxOf(page).locator('.line'), 'no line').toHaveCount(0);
  await expect(boxOf(page).locator('.hint'), 'no hint').toHaveCount(0);
  await expect(breakButton(page), 'the button follows the view: active').toHaveClass(/button-attention/);
});

/** Q6: a press with no answer in 10 s: ServerButton's notice shows, and the box drops the sending line and follows the view again. */
test('Q6: a press with no answer in 10 s shows ServerButton\'s notice and ends the box\'s sending line', async ({ page }) => {
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  await page.route(BREAK_FEED, async (route) => {
    await gate;
    await route.fulfill({ status: 500, contentType: 'application/json', body: '{}' });
  });
  await page.clock.install();
  await serve(page, { guide: guideOf(2, { breakFeed: { active: true } }) });
  await open(page);

  await breakButton(page).click();
  await expect(boxOf(page).locator('.line'), 'the press has no answer yet').toHaveText(SENDING);
  await page.clock.fastForward(10_000);
  await expect(boxOf(page).getByText("Couldn't reach OcuTalon. Try again. Nothing was changed.", { exact: true }), 'ServerButton\'s notice after 10 s').toBeVisible();
  await expect(breakButton(page), 'the button is no longer busy').not.toHaveAttribute('aria-busy', /.*/);
  await expect(boxOf(page).locator('.line'), 'and the box drops the sending line with it').toHaveCount(0);
  await expect(breakButton(page), 'the box follows the view again').toHaveClass(/button-attention/);
  release();
});

/** Q7: the stages come from the view and the page's clock: the lines at 90 s and 3 min, and the button follows the server only. */
test('Q7: the sent line gives way to the 90 s and 3 min lines by the page\'s clock, and the button follows the server', async ({ page }) => {
  const holder = { guide: guideOf(2) };
  await page.clock.install();
  await serve(page, holder);
  await open(page);
  const startedAt = Date.parse(iso((await now(page)) - 5_000));
  const run = (stage: string, active = false): Record<string, unknown> =>
    guideOf(2, { breakFeed: { active, reason: active ? undefined : 'incident_in_progress', stage, startedAt: iso(startedAt) } });
  const at = async (seconds: number): Promise<void> => {
    await page.clock.fastForward(Math.max(0, startedAt + seconds * 1000 - (await now(page))));
  };

  holder.guide = run('waiting');
  await reopen(page);
  const line = boxOf(page).locator('.line');
  await expect(line, 'waiting shows the sent line').toContainText(SENT);
  await at(89);
  await expect(line.locator('[aria-hidden="true"]'), 'the box has redrawn at 89 s').toHaveText('1 min');
  await expect(line, 'at 89 s still the sent line').toContainText(SENT);
  await at(90);
  await expect(line, 'at 90 s, by the page\'s clock, the 90 s line').toContainText(STILL);
  await expect(breakButton(page), 'the button is still the server\'s: inactive').toHaveAttribute('aria-disabled', 'true');

  // The server still says still_waiting at 3 min on the page's clock.
  holder.guide = run('still_waiting');
  await reopen(page);
  await expect(line).toContainText(STILL);
  await at(180);
  await expect(line, 'at 180 s the 3 min line').toHaveText(NO_NOTICE);
  await expect(line.locator('.elapsed'), 'with no elapsed time').toHaveCount(0);
  await expect(breakButton(page), 'and the button still inactive until the server says active').toHaveAttribute('aria-disabled', 'true');
  await expect(breakButton(page)).toHaveClass(/button-inactive/);

  // The server's no_notice with active: the line shows and the button is active, with the tag.
  holder.guide = run('no_notice', true);
  await reopen(page);
  await expect(line).toHaveText(NO_NOTICE);
  await expect(breakButton(page), 'the button is active when the server says so').not.toHaveAttribute('aria-disabled', /.*/);
  await expect(breakButton(page)).toHaveClass(/button-attention/);
  await expect(boxOf(page).getByText('Next step', { exact: true }), 'the tag returns on step 3').toBeVisible();

  // Sending with no press of this page: the sending line, inactive, no spinner.
  holder.guide = run('sending');
  await reopen(page);
  await expect(line).toHaveText(SENDING);
  await expect(breakButton(page)).toHaveAttribute('aria-disabled', 'true');
  await expect(breakButton(page), 'with no spinner and no busy state').not.toHaveAttribute('aria-busy', /.*/);
  await expect(breakButton(page).locator('.spinner')).toHaveCount(0);

  // The notice arrived: the lines end.
  holder.guide = guideOf(3, { breakFeed: { active: false, reason: 'incident_in_progress', stage: 'notice_arrived', startedAt: iso(startedAt) } });
  await reopen(page);
  await expect(line).toHaveCount(0);
  await expect(boxOf(page).locator('.hint')).toHaveText(H2);
});

/** Q8: Hide guide and Show guide: the bar, its aria-expanded button, focus, the stored choice, and a storage that throws. */
test('Q8: Hide guide collapses to one bar with Show guide, keeps the box, moves focus, and is remembered', async ({ page }) => {
  const holder = { guide: guideOf(1, { breakFeed: { active: false, reason: 'not_watching' } }) };
  await serve(page, holder);
  await open(page);

  const guide = guideRegion(page);
  await guide.getByRole('button', { name: 'Hide guide', exact: true }).click();
  const show = guide.getByRole('button', { name: 'Show guide', exact: true });
  await expect(show, 'Show guide has aria-expanded false').toHaveAttribute('aria-expanded', 'false');
  await expect(show, 'and takes focus').toBeFocused();
  await expect(guide, 'one bar: the label, the step and Show guide').toContainText('Demo guide \u00B7 step 2 of 5 \u00B7');
  await expect(guide.getByRole('list'), 'no steps').toHaveCount(0);
  await expect(guide.locator('.bar-text [aria-hidden="true"]'), 'the two separators are decorative').toHaveText(['\u00B7', '\u00B7']);
  await expect(promptOf(page), 'and no prompt bar').toHaveCount(0);
  const bar = (await guide.boundingBox())!;
  expect(bar.height, 'the bar is at least 40px').toBeGreaterThanOrEqual(40);
  const box = (await boxOf(page).boundingBox())!;
  expect(box.x + box.width, 'the box keeps its place at the right end of the bar').toBeGreaterThanOrEqual(bar.x + bar.width - 1);
  await expect(boxOf(page).getByText('Demo control', { exact: true }), 'with its label inline').toBeVisible();
  await expect(breakButton(page), 'and its rules').toHaveAttribute('aria-disabled', 'true');
  expect(await page.evaluate(() => localStorage.getItem('ocutalon.guide.hidden')), 'the choice is stored').toBe('1');
  await expect(guide).toHaveAccessibleName('Demo guide');

  await reopen(page);
  await expect(show, 'it survives a reload').toBeVisible();
  await show.click();
  await expect(guide.getByRole('button', { name: 'Hide guide', exact: true }), 'Show guide restores the guide, with focus on Hide guide').toBeFocused();
  await expect(stepOf(page, 2, 'current')).toBeVisible();
  await reopen(page);
  await expect(guide.getByRole('button', { name: 'Hide guide', exact: true }), 'and that survives a reload too').toBeVisible();
});

/** Q8: a storage that throws leaves the choice to the page's life, with no console error. */
test('Q8: with a storage that throws, Hide and Show work for the page\'s life and the console stays clean', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  page.on('pageerror', (error) => errors.push(error.message));
  await serve(page, { guide: guideOf(0) });
  await open(page);
  await page.evaluate(() => {
    const fail = (): never => {
      throw new DOMException('denied', 'SecurityError');
    };
    Object.defineProperty(window, 'localStorage', { get: fail, configurable: true });
  });

  const guide = guideRegion(page);
  await guide.getByRole('button', { name: 'Hide guide', exact: true }).click();
  await expect(guide.getByRole('button', { name: 'Show guide', exact: true })).toHaveAttribute('aria-expanded', 'false');
  await guide.getByRole('button', { name: 'Show guide', exact: true }).click();
  await expect(guide.getByRole('button', { name: 'Hide guide', exact: true })).toBeFocused();
  expect(errors.filter((text) => !/Failed to load resource/.test(text)), 'no console error').toEqual([]);
  expect(plain(await guide.locator('.label').first().textContent())).toBe('Demo guide');
});

/** Row 1 of the guide at 1280x800, where the labels show, once the page's Inter faces (400 and 600, the two that row 1 uses) have loaded. */
async function openRow1(page: Page): Promise<Locator> {
  await page.setViewportSize({ width: 1280, height: 800 });
  await serve(page, { guide: guideOf(0) });
  await open(page);
  await expect(guideRegion(page).locator('.step-label').first(), 'the labels show at 1280x800').toBeVisible();
  await expect
    .poll(() => page.evaluate(() => document.fonts.check('400 14px Inter') && document.fonts.check('600 14px Inter')), { message: 'the page\'s fonts have loaded before anything is measured' })
    .toBe(true);
  return guideRegion(page).locator('.row1');
}

/**
 * Row 1's children: how many lines they make (their vertical centres, a gap above 8px apart), how far the widest runs past the row, the
 * row's width, the children's widths plus the row's gaps, and the steps' width.
 */
const readRow1 = (row: Locator): Promise<{ lines: number; past: number; width: number; total: number; steps: number }> =>
  row.evaluate((node) => {
    const box = node.getBoundingClientRect();
    const kids = [...node.children].map((child) => child.getBoundingClientRect());
    const centres = kids.map((kid) => kid.top + kid.height / 2).sort((a, b) => a - b);
    const lines = centres.filter((centre, i) => i === 0 || centre - centres[i - 1]! > 8).length;
    const steps = node.querySelector('.steps')!.getBoundingClientRect().width;
    return {
      lines,
      past: Math.max(...kids.map((kid) => kid.right)) - box.right,
      width: box.width,
      total: kids.reduce((sum, kid) => sum + kid.width, 0) + Number.parseFloat(getComputedStyle(node).columnGap) * (kids.length - 1),
      steps,
    };
  });

/**
 * Q11: at 1280x800 and the normal text size, row 1 (the label, the five labelled steps, "About 2 minutes" and Hide guide) fits one line,
 * measured in Inter once its faces have loaded. Linux Chromium rounds each glyph to whole pixels, so the row is wider there than on macOS;
 * the message carries the widths, so a red names the host's fit.
 */
test('Q11: row 1 fits one line at 1280px at the normal text size', async ({ page }) => {
  const fit = await readRow1(await openRow1(page));
  expect(fit.lines, `row 1 is one line: its children take ${fit.total.toFixed(1)}px of a ${fit.width.toFixed(1)}px row`).toBe(1);
});

/**
 * Q9: at a larger text size the step row wraps onto a second line instead of running past the guide (row 1 at 1280px, where the labels
 * show). The row's children are measured at the normal size, and the text tokens are scaled by the geometric mean of the factors at which
 * "everything fits" and "the steps alone fit" (1.1 at least): the row wraps if and only if flex-wrap lets the label, the steps, the
 * duration and Hide guide share more than one line. Q9 holds whether or not the row fits one line at the normal size; Q11 pins that fit.
 */
test('Q9: the step row wraps at a larger text size and nothing runs past the row', async ({ page }) => {
  const row = await openRow1(page);
  const read = (): ReturnType<typeof readRow1> => readRow1(row);

  // At the normal size nothing runs past the row, whether it fits one line (Q11) or wraps.
  const before = await read();
  expect(Number.isFinite(before.total), 'the row has a measurable gap').toBe(true);
  expect(before.past, 'and nothing runs past it').toBeLessThanOrEqual(1);

  // A factor past "everything fits" and short of "the steps alone fit" (for a row that fits one line), so the whole row no longer fits.
  const scale = Math.max(1.1, Math.sqrt((before.width / before.total) * (before.width / before.steps)));
  await page.addStyleTag({
    content: `:root { --type-body-font-size: ${14 * scale}px; --type-label-font-size: ${12 * scale}px; --type-caption-font-size: ${12 * scale}px; --guide-step-current-typography-font-size: ${14 * scale}px; }`,
  });
  await expect.poll(async () => (await read()).lines, { message: 'the row wraps onto a second line' }).toBeGreaterThan(1);
  const after = await read();
  expect(after.past, 'and nothing runs past the row').toBeLessThanOrEqual(1);
  expect(await row.evaluate((node) => node.scrollWidth - node.clientWidth), 'the row does not scroll sideways').toBeLessThanOrEqual(0);
  await expect(stepOf(page, 1, 'current'), 'every step is still there').toBeVisible();
  await expect(guideRegion(page).getByRole('button', { name: 'Hide guide', exact: true })).toBeVisible();

  // At twice the text size the steps no longer fit one line of the row: they wrap inside it and none runs into the box.
  await page.addStyleTag({
    content: ':root { --type-body-font-size: 28px; --type-label-font-size: 24px; --type-caption-font-size: 24px; --guide-step-current-typography-font-size: 28px; }',
  });
  await expect(guideRegion(page).locator('.row1 .label'), 'the text is twice its size').toHaveCSS('font-size', '24px');
  const doubled = await read();
  expect(doubled.past, 'at twice the size nothing runs past the row').toBeLessThanOrEqual(1);
  const rightmost = await guideRegion(page).locator('.step').evaluateAll((nodes) => Math.max(...nodes.map((node) => node.getBoundingClientRect().right)));
  const boxLeft = (await boxOf(page).boundingBox())!.x;
  expect(rightmost, 'and no step reaches the box').toBeLessThanOrEqual(boxLeft + 1);
});

/** Q10: a page loaded during a run treats it as begun: a later view of the same run announces nothing. */
test('Q10: a page loaded during a run announces nothing for that run\'s later views', async ({ page }) => {
  const startedAt = iso(Date.now() - 30_000);
  const runView = (stage: string): Record<string, unknown> => guideOf(2, { breakFeed: { active: false, reason: 'incident_in_progress', stage, startedAt } });
  await serve(page, { guide: runView('waiting') });
  const push = await liveEvents(page);
  await recordAnnouncements(page);
  await open(page);

  const line = boxOf(page).locator('.line');
  await expect(line, 'the first view shows the run').toContainText(SENT);
  await push([{ type: 'guide.state', payload: runView('still_waiting') }]);
  await expect(line, 'a later view of the same run reached the box').toContainText(STILL);
  await page.waitForTimeout(1500);
  expect((await announcedTexts(page)).filter((text) => text.includes(SENT)), 'the run began before the page loaded: no Sent').toEqual([]);
});

/** Q10: a run that a live view shows first (not this page's press) is announced once, and its later views announce nothing more. */
test('Q10: a run first seen through a live view is announced once', async ({ page }) => {
  await serve(page, { guide: guideOf(2, { breakFeed: { active: true } }) });
  const push = await liveEvents(page);
  await recordAnnouncements(page);
  await open(page);
  await expect(breakButton(page)).toHaveClass(/button-attention/);

  const startedAt = iso(Date.now() - 5_000);
  const runView = (stage: string): Record<string, unknown> => guideOf(2, { breakFeed: { active: false, reason: 'incident_in_progress', stage, startedAt } });
  await push([{ type: 'guide.state', payload: runView('waiting') }]);
  await expect(boxOf(page).locator('.line'), 'the run reached the box').toContainText(SENT);
  await expect.poll(async () => (await announcedTexts(page)).filter((text) => text.includes(SENT)).length, { message: 'Sent is announced' }).toBe(1);
  await push([{ type: 'guide.state', payload: runView('still_waiting') }]);
  await expect(boxOf(page).locator('.line')).toContainText(STILL);
  await page.waitForTimeout(1500);
  expect((await announcedTexts(page)).filter((text) => text.includes(SENT)), 'once for the run').toHaveLength(1);
});

/** Q10: a `watch.progress` that the page held before a run (first seen through a live view) never shows as that run's line; the run's own does. */
test('Q10: an earlier run\'s watch.progress never shows for a run first seen through a live view', async ({ page }) => {
  await serve(page, { guide: guideOf(2, { breakFeed: { active: true } }) });
  const push = await liveEvents(page);
  await open(page);

  await push([{ type: 'watch.progress', payload: { ref: 'zzQ10earlier', stage: 'diagnosing' } }]);
  const startedAt = iso(Date.now() - 5_000);
  await push([{ type: 'guide.state', payload: guideOf(2, { breakFeed: { active: false, reason: 'incident_in_progress', stage: 'waiting', startedAt } }) }]);
  const line = boxOf(page).locator('.line');
  await expect(line, 'the run shows its sent line').toContainText(SENT);
  await page.waitForTimeout(1000);
  await expect(line, 'not the earlier run\'s progress line').not.toContainText('Working out the cause');
  await push([{ type: 'watch.progress', payload: { ref: 'zzQ10own', stage: 'noticed' } }]);
  await expect(line, 'the run\'s own progress line replaces it').toContainText('OcuTalon noticed failures in the Orders production');
});

/** Q10: when an update removes Do step 1 while it holds focus, focus goes to the Break the feed button beside it, not to the chat. */
test('Q10: when an update removes the focused Do step 1, focus goes to the Break the feed button', async ({ page }) => {
  await serve(page, { guide: guideOf(0) });
  const push = await liveEvents(page);
  await open(page);

  const step1 = boxOf(page).getByRole('button', { name: 'Do step 1', exact: true });
  await step1.focus();
  await expect(step1).toBeFocused();
  await push([{ type: 'guide.state', payload: guideOf(1, { breakFeed: { active: true } }) }]);
  await expect(stepOf(page, 2, 'current'), 'the view advanced to step 2').toHaveAttribute('aria-current', 'step');
  await expect(step1, 'Do step 1 is gone').toHaveCount(0);
  await expect(breakButton(page), 'focus is on the Break the feed button').toBeFocused();
});
