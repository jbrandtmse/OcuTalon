import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { cleanFixtureRows, finishTurn, fixtureUser, seedTurns, sinkEvent, turnRows, type SeedDecision, type SeedTurn, type SeedUsage } from '../support/iris';
import { clock, plain, tokenColor } from '../support/page';

/**
 * Story 2.6, the decision strip under every reply (D1 to D14), in a real browser against a real stack. Every case signs in as the
 * decision fixture user that test-sign-in.sh created (OCUTALON_DECISION_USER) and seeds turns, decisions, usage rows and check
 * rows into its own session, so that nothing here publishes on the README session or the instance stream (api.spec pins their
 * counts), sends a message or touches another spec's chat; C15 of chat.spec is the one case that sends, as the panel user.
 * Each case asserts only on the refs it made. The browser runs in Asia/Kolkata with the en-US locale, so a time is the same
 * wherever the specs run.
 *
 * /state's chat holds only the session's newest 100 entries, so every seeded turn is dated in the past (2024 and 2025), except
 * D2's two, dated 2099: the strip of the newest turn of the chat shows three reason lines and the others one, and D2 needs its
 * turns to be the newest on a stack that ran the cases before, in any order of the cases.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-US' });

/** A poll that a routed /events handler is still answering when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const EVENTS = /\/ocutalon\/api\/v1\/events\?/;
const LIVE_REGIONS = '[aria-live], [role="log"], [role="status"], [role="alert"]';

/** The middle dot between the items of a line, with its spaces. */
const DOT = ' \u00B7 ';

/** One stroke that only that Lucide icon draws, as a selector inside the icon's svg. */
const ICON = {
  zap: 'path[d^="M4 14a1 1 0 0 1-.78-1.63"]',
  bellRing: 'path[d="M10.268 21a2 2 0 0 0 3.464 0"]',
  lifeBuoy: 'path[d="m4.93 4.93 4.24 4.24"]',
  circleCheck: 'path[d="m9 12 2 2 4-4"]',
  circleX: 'path[d="m15 9-6 6"]',
  circleDashed: 'path[d="M10.1 2.182a10 10 0 0 1 3.8 0"]',
  chevronDown: 'path[d="m6 9 6 6 6-6"]',
  chevronUp: 'path[d="m18 15-6-6-6 6"]',
} as const;

/** The attention decision of most turns: Act, four reason lines, 0.92 confidence, $0.0003, 1,084 input and 312 output tokens. */
const ACT: SeedDecision = {
  outcome: 'act',
  summary: 'zz seeded summary',
  reasons: 'Reason one.\nReason two.\nReason three.\nReason four.',
  confidence: 0.92,
  inputTokens: 1084,
  outputTokens: 312,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
  agentStepCount: 2,
  durationMs: 3400,
  costUSD: 0.0003,
  model: 'claude-haiku-5-5',
  traceSessionId: 4512,
};

/** The reply decision of most turns: its usage is $0.0005, so that the turn costs $0.0008 with the attention decision. */
const REPLY: SeedDecision = { outcome: 'tellnow', reasons: 'Reply reason.', costUSD: 0.0005, inputTokens: 40, outputTokens: 9 };

/** The usage rows of those two decisions. */
const USAGE: SeedUsage[] = [
  { of: 'triage', inputTokens: 1084, outputTokens: 312, costUSD: 0.0003 },
  { of: 'turn', inputTokens: 40, outputTokens: 9, costUSD: 0.0005 },
];

/** The tokens line that ACT's details show. */
const TOKENS = `Input 1,084${DOT}Output (includes thinking) 312${DOT}Cache read 0${DOT}Cache write 0`;

/** A done turn with a reply decision: the defaults a case changes. */
const turn = (label: string, over: Partial<SeedTurn> = {}): SeedTurn => ({
  createdAt: '2025-03-01T10:00:00Z',
  text: `zz ${label}`,
  replyText: `zz reply to ${label}`,
  triage: ACT,
  turn: REPLY,
  usage: USAGE,
  ...over,
});

/** A seeded fallback reply, with the turn decision that fell back. */
const FALLBACK: Partial<SeedTurn> = {
  replyText: '',
  catalogKey: 'conversation.turnFallback',
  fallbackReason: 'timeout',
  turn: { outcome: 'tellnow', fallback: true, fallbackReason: 'timeout', reasons: 'Fixed rules chose this.', confidence: 0.5, costUSD: 0.0005 },
};

const replyOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="reply"][data-key="${key}"]`);
const stripOf = (page: Page, key: string): Locator => replyOf(page, key).locator('app-decision-strip');

/** Signs the decision user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<Locator> {
  const { user, password } = fixtureUser('DECISION');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const field = page.getByRole('textbox', { name: 'Message OcuTalon' });
  await expect(field).toBeVisible();
  return field;
}

/** Seeds turns into the decision user's session, without publishing. */
const seed = (turns: SeedTurn[], publish = false): ReturnType<typeof seedTurns> => seedTurns(fixtureUser('DECISION').user, turns, publish);

/** D1: the strip under a reply: the chip, the cost of the turn, a reason, its place, its name and description. */
test('D1: a reply shows its decision strip', async ({ page }) => {
  const { refs } = await seed([turn('D1')]);
  await open(page);
  const reply = replyOf(page, refs[0]!);
  const strip = stripOf(page, refs[0]!);
  await expect(strip).toHaveCount(1);

  const chip = strip.locator('app-outcome-chip .chip');
  await expect(chip).toHaveText('Act');
  await expect(chip.locator(ICON.zap), 'with its zap icon').toHaveCount(1);
  await expect(strip.locator('app-fallback-flag'), 'no Fallback flag').toHaveCount(0);
  const meta = strip.locator('.line1 .meta');
  await expect(meta, 'the confidence and the cost of the whole turn, not of the decision').toHaveText(`Confidence 0.92${DOT}$0.0008`);
  await expect(meta.locator('[aria-hidden="true"]'), 'the middle dot is decorative').toHaveText(['\u00B7']);
  await expect(meta.locator('[aria-hidden="true"]')).toHaveCount(1);
  await expect(strip.locator('.reason').first(), 'the first reason line').toHaveText('Reason one.');

  const textBox = (await reply.locator('.text').boundingBox())!;
  const stripBox = (await strip.boundingBox())!;
  expect(stripBox.y, 'the strip comes after the reply text').toBeGreaterThanOrEqual(textBox.y + textBox.height - 1);
  expect(Math.abs(stripBox.x - textBox.x), 'under the text, left-aligned with it').toBeLessThanOrEqual(1);
  const line2Box = (await strip.locator('.line2').boundingBox())!;
  expect(stripBox.y + stripBox.height, 'a closed strip ends with its reason line, with no gap below').toBeLessThanOrEqual(line2Box.y + line2Box.height + 1);

  const group = reply.getByRole('group', { name: 'Act', exact: true });
  await expect(group, 'the strip is a group named by its chip').toHaveCount(1);
  await expect(group).toHaveAccessibleDescription(/OcuTalon took or requested an action/);
  await expect(strip.locator(LIVE_REGIONS), 'nothing in it is a live region').toHaveCount(0);
  expect(await strip.evaluate((el, selector) => el.closest(selector) !== null, LIVE_REGIONS), 'and it is in none').toBe(false);
  await expect(strip.locator('.line1 .meta'), 'the figures are tabular').toHaveCSS('font-variant-numeric', 'tabular-nums');
});

/** D2: the newest strip of the chat shows three reason lines and the others the first, on one line with an ellipsis. */
test('D2: the newest reply shows three reasons and older replies one', async ({ page }) => {
  const long = `A first reason line that is far longer than the chat column is wide, so that it has to be cut with an ellipsis: ${'long words '.repeat(20)}`;
  const reasons = [long, 'Reason two.', 'Reason three.', 'Reason four.'].join('\n');
  const { refs } = await seed([
    turn('D2 older', { createdAt: '2099-01-01T10:00:00Z', triage: { ...ACT, reasons } }),
    turn('D2 newer', { createdAt: '2099-01-01T10:05:00Z', triage: { ...ACT, reasons } }),
  ]);
  await open(page);
  const older = stripOf(page, refs[0]!);
  const newer = stripOf(page, refs[1]!);
  await expect(newer.locator('.reason'), 'the newest strip shows three lines').toHaveCount(3);
  await expect(newer.locator('.reason').nth(1)).toHaveText('Reason two.');
  await expect(older.locator('.reason'), 'an older strip shows its first line only').toHaveCount(1);
  const line = older.locator('.reason');
  await expect(line).toHaveCSS('text-overflow', 'ellipsis');
  await expect(line).toHaveCSS('white-space', 'nowrap');
  await expect(line).toHaveCSS('overflow', 'hidden');
  expect(await line.evaluate((el) => el.scrollWidth > el.clientWidth), 'the long line is cut').toBe(true);
  expect(await line.evaluate((el) => el.getBoundingClientRect().height), 'on one line').toBeLessThan(24);

  const lastReason = (await newer.locator('.reason').last().boundingBox())!;
  const newerButton = (await newer.getByRole('button', { name: 'Decision details' }).boundingBox())!;
  expect(newerButton.y, 'Decision details comes after the last reason line of the newest strip').toBeGreaterThanOrEqual(lastReason.y + lastReason.height - 1);
  const olderReason = (await line.boundingBox())!;
  const olderButton = (await older.getByRole('button', { name: 'Decision details' }).boundingBox())!;
  expect(olderButton.x, 'and after the one line of an older strip').toBeGreaterThanOrEqual(olderReason.x + olderReason.width - 1);
});

/** D3: a fallback reply: Tell now, the Fallback flag, no confidence, and the reason as a sentence on the first line, in warning-ink. */
test('D3: a fallback reply shows Tell now, the Fallback flag and its reason first', async ({ page }) => {
  const { refs, decisions } = await seed([turn('D3', FALLBACK)]);
  await open(page);
  const strip = stripOf(page, refs[0]!);
  const chip = strip.locator('app-outcome-chip .chip');
  await expect(chip).toHaveText('Tell now');
  await expect(chip.locator(ICON.bellRing)).toHaveCount(1);
  const flag = strip.locator('app-fallback-flag .flag');
  await expect(flag).toHaveText('Fallback');
  await expect(flag.locator('svg[aria-hidden="true"]'), 'with its life-buoy icon, hidden from assistive technology').toHaveCount(1);
  await expect(flag.locator(ICON.lifeBuoy)).toHaveCount(1);
  await expect(flag).toHaveCSS('background-color', await tokenColor(page, '--fallback-flag-background'));
  await expect(flag).toHaveCSS('color', await tokenColor(page, '--fallback-flag-foreground'));
  await expect(strip, 'no confidence on a fallback').not.toContainText('Confidence');
  await expect(strip.locator('.line1 .meta'), 'the turn\'s cost is still shown').toHaveText('$0.0008');
  const first = strip.locator('.reason').first();
  await expect(first, 'the reason is the first line, as a sentence').toHaveText("The model didn't answer within 60 seconds.");
  await expect(first).toHaveCSS('color', await tokenColor(page, '--warning-ink'));
  await expect(replyOf(page, refs[0]!).locator('.text'), 'above the catalog sentence of the fallback').toContainText("I couldn't answer that: the model didn't answer within 60 seconds.");
  await expect(replyOf(page, refs[0]!).getByRole('group', { name: 'Tell now', exact: true }), 'the group is described by the meaning of Tell now').toHaveAccessibleDescription('Needs you now');
  await strip.getByRole('button', { name: 'Decision details' }).click();
  const message = strip.locator('dl.details dd', { hasText: decisions[0]!.turn });
  await expect(message, 'the strip shows the reply decision, the one that fell back, not the attention decision').toHaveCount(1);
  await expect(strip.locator('dl.details'), 'and its details are that decision\'s').not.toContainText(decisions[0]!.triage);
});

/** D4: Decision details opens inline with the six rows; Esc collapses it with focus on the button; equal costs show once. */
test('D4: Decision details opens inline with its figures', async ({ page }) => {
  const { refs, decisions } = await seed([
    turn('D4', { createdAt: '2025-03-01T10:00:00Z' }),
    turn('D4 equal', { createdAt: '2025-03-01T10:01:00Z', turn: undefined, usage: [USAGE[0]!] }),
  ]);
  await open(page);
  const strip = stripOf(page, refs[0]!);
  const button = strip.getByRole('button', { name: 'Decision details' });
  await expect(button).toHaveText('Details');
  await expect(button).toHaveAttribute('aria-expanded', 'false');
  await expect(button.locator(ICON.chevronDown)).toHaveCount(1);
  await expect(strip.locator('dl.details')).toHaveCount(0);

  await button.click();
  await expect(button).toHaveAttribute('aria-expanded', 'true');
  await expect(button.locator(ICON.chevronUp)).toHaveCount(1);
  const controls = await button.getAttribute('aria-controls');
  await expect(strip.locator(`#${controls}`), 'the button controls the panel').toBeVisible();
  const details = strip.locator('dl.details');
  await expect(details, 'the details open inline').toBeVisible();
  await expect(page.locator('[role="dialog"], .app-popover'), 'never a dialog or a popover').toHaveCount(0);
  // The figures are soft assertions, so that one run reports every wrong figure of the panel, not the first.
  await expect.soft(details.locator('dt')).toHaveText(['Tokens', 'Model', 'Agent steps', 'Duration', 'Decision message', 'Cost']);
  await expect.soft(details.locator('dd')).toHaveText([TOKENS, 'Claude Haiku 5.5', '2', '3.4 s', decisions[0]!.triage, `Decision $0.0003${DOT}Turn $0.0008`]);
  await expect(details.locator('dd').nth(0), 'the tokens are in the monospace type').toHaveCSS('font-family', /JetBrains Mono/);
  await expect(details.locator('dd').nth(4), 'and so is the reference').toHaveCSS('font-family', /JetBrains Mono/);
  await expect(details.locator('dd').nth(1)).not.toHaveCSS('font-family', /JetBrains Mono/);

  await button.press('Escape');
  await expect(button, 'Esc collapses the details').toHaveAttribute('aria-expanded', 'false');
  await expect(strip.locator('dl.details')).toHaveCount(0);
  await expect(button, 'and focus stays on the button').toBeFocused();

  const equal = stripOf(page, refs[1]!);
  await equal.getByRole('button', { name: 'Decision details' }).click();
  await expect.soft(equal.locator('dl.details dd').last(), 'a turn that cost what its decision cost shows the cost once').toHaveText('$0.0003');
});

/** D5: the chip's tooltip is for the pointer: it shows the meaning after 300 ms, Esc hides it, and the chip takes no focus. */
test('D5: the outcome chip has a pointer tooltip and takes no focus', async ({ page }) => {
  const { refs } = await seed([
    turn('D5'),
    turn('D5 digest', { createdAt: '2025-03-01T10:01:00Z', triage: { ...ACT, outcome: 'digest' } }),
  ]);
  await open(page);
  const reply = replyOf(page, refs[0]!);
  const chip = stripOf(page, refs[0]!).locator('app-outcome-chip .chip');
  const tooltip = page.locator('.cdk-overlay-container app-tooltip');
  await expect(tooltip).toHaveCount(0);
  await chip.hover();
  await expect(tooltip, 'a pointer resting on the chip shows its meaning').toHaveText('OcuTalon took or requested an action');
  await page.keyboard.press('Escape');
  await expect(tooltip, 'Esc hides it').toHaveCount(0);
  await page.mouse.move(0, 0);
  await stripOf(page, refs[1]!).locator('app-outcome-chip .chip').hover();
  await expect(tooltip, 'every outcome shows its own meaning').toHaveText('Saved for later; nobody notified now');
  await page.keyboard.press('Escape');
  await expect(tooltip).toHaveCount(0);
  await page.mouse.move(0, 0);

  await expect(chip, 'the chip has no tabindex').not.toHaveAttribute('tabindex', /.*/);
  expect(await chip.evaluate((el) => (el as HTMLElement).tabIndex), 'and cannot take focus').toBe(-1);
  await expect(chip.locator('svg[aria-hidden="true"]'), 'its icon is hidden from assistive technology').toHaveCount(1);
  await reply.focus();
  await page.keyboard.press('Tab');
  await expect(stripOf(page, refs[0]!).getByRole('button', { name: 'Decision details' }), 'Tab from the reply goes to the Details button').toBeFocused();
  await expect(chip, 'never to the chip').not.toBeFocused();
});

/** D6: the indicator shows the current step's label; the strip comes after it; the page shows a step within 2 s. */
test('D6: the turn indicator shows the current step\'s label', async ({ page }) => {
  const { user } = fixtureUser('DECISION');
  const { refs, decisions } = await seed([turn('D6', { state: 'running', replyText: '', turn: undefined, usage: [USAGE[0]!] })]);
  try {
    await open(page);
    const reply = replyOf(page, refs[0]!);
    const indicator = reply.locator('.indicator');
    await expect(indicator, 'a running turn with no step is Working').toHaveText('Working\u2026');
    const strip = stripOf(page, refs[0]!);
    await expect(strip, 'the strip is there while the turn runs').toHaveCount(1);
    const indicatorBox = (await indicator.boundingBox())!;
    const stripBox = (await strip.boundingBox())!;
    expect(stripBox.y, 'and comes after the indicator').toBeGreaterThanOrEqual(indicatorBox.y + indicatorBox.height - 1);

    await sinkEvent(user, 'turn.step', { decisionRef: decisions[0]!.triage, label: 'Checking the Orders production' });
    const started = Date.now();
    await expect(indicator, 'the step\'s label replaces Working').toHaveText('Checking the Orders production\u2026', { timeout: 2000 });
    expect(Date.now() - started, 'within 2 s of the event').toBeLessThan(2000);
    await expect(indicator.locator('.dots'), 'with the animated ellipsis').toHaveCount(1);
    await expect(indicator.locator(LIVE_REGIONS)).toHaveCount(0);
    await expect(page.getByRole('main').locator(LIVE_REGIONS), 'the indicator is not a live region').toHaveCount(0);
  } finally {
    await finishTurn(user, refs[0]!);
  }
  await expect(replyOf(page, refs[0]!).locator('.text'), 'once the turn is done its reply replaces the indicator').toHaveText('zz finished');
});

/** D7: check rows under a reply: the sentence only from the key (naming what failed from the rows that did not pass), one row per result, and Not checked for what is not known. */
test('D7: check rows show under a reply, never an all-clear from the rows', async ({ page }) => {
  const passed = [
    { result: 'passed', entry: 'Orders production', finding: '', checkedAt: '2025-03-01T10:00:00Z' },
    { result: 'passed', entry: 'Warehouse queue', finding: '', checkedAt: '2025-03-01T10:01:00Z' },
  ];
  const mixed = [
    { result: 'passed', entry: 'Orders production', finding: '', checkedAt: '2025-03-01T10:00:00Z' },
    { result: 'failed', entry: 'Warehouse queue', finding: '12 messages are waiting', checkedAt: '2025-03-01T10:01:00Z' },
    { result: 'zz_unknown', entry: 'Partner feed', finding: 'The check did not run', checkedAt: '2025-03-01T10:02:00Z' },
  ];
  const failing = [
    { result: 'failed', entry: 'Warehouse queue', finding: '12 messages are waiting', checkedAt: '2025-03-01T10:01:00Z' },
    { result: 'not_checked', entry: 'Partner feed', finding: 'Not run yet', checkedAt: '' },
  ];
  const { refs } = await seed([
    turn('D7 all', { createdAt: '2025-03-01T10:00:00Z', checkKey: 'checks.allPassed', checks: passed }),
    turn('D7 mixed', { createdAt: '2025-03-01T10:05:00Z', checkKey: 'checks.notEverythingRestPassed', checks: mixed }),
    turn('D7 bare', { createdAt: '2025-03-01T10:10:00Z', checks: passed }),
    turn('D7 key only', { createdAt: '2025-03-01T10:15:00Z', checkKey: 'checks.nothingWatched' }),
    turn('D7 failing', { createdAt: '2025-03-01T10:20:00Z', checkKey: 'checks.notEverything', checks: failing }),
  ]);
  await open(page);

  const all = replyOf(page, refs[0]!).locator('app-check-rows');
  await expect(all.locator('.sentence')).toHaveText('Everything I checked passed.');
  const rows = all.locator('li.row');
  await expect(rows).toHaveCount(2);
  await expect(rows.locator('.word')).toHaveText(['Passed', 'Passed']);
  await expect(rows.locator('.entry')).toHaveText(['Orders production', 'Warehouse queue']);
  await expect(rows.locator('.time')).toHaveText([clock('2025-03-01T10:00:00Z'), clock('2025-03-01T10:01:00Z')]);
  await expect(rows.first().locator('svg[aria-hidden="true"]')).toHaveCount(1);
  await expect(rows.first().locator(ICON.circleCheck), 'passed has the circle-check icon').toHaveCount(1);
  await expect(rows.first().locator('.result')).toHaveCSS('color', await tokenColor(page, '--check-result-passed-foreground'));
  const textBox = (await replyOf(page, refs[0]!).locator('.text').boundingBox())!;
  const rowsBox = (await all.boundingBox())!;
  const stripBox = (await stripOf(page, refs[0]!).boundingBox())!;
  expect(rowsBox.y, 'the rows come after the reply text').toBeGreaterThanOrEqual(textBox.y + textBox.height - 1);
  expect(stripBox.y, 'and before the strip').toBeGreaterThanOrEqual(rowsBox.y + rowsBox.height - 1);

  const some = replyOf(page, refs[1]!).locator('app-check-rows');
  await expect(some.locator('.sentence'), 'what failed comes from the rows that did not pass, and the passed row is not named').toHaveText(
    `Not everything: Warehouse queue (12 messages are waiting, at ${clock('2025-03-01T10:01:00Z')}); Partner feed (the check did not run, at ${clock('2025-03-01T10:02:00Z')}). Everything else I checked passed.`,
  );
  const results = some.locator('li.row');
  await expect(results.locator('.word')).toHaveText(['Passed', 'Failed', 'Not checked']);
  await expect(results.nth(1).locator(ICON.circleX), 'failed has the circle-x icon').toHaveCount(1);
  await expect(results.nth(1).locator('.result')).toHaveCSS('color', await tokenColor(page, '--check-result-failed-foreground'));
  await expect(results.nth(1).locator('.finding')).toHaveText('12 messages are waiting');
  await expect(results.nth(2).locator(ICON.circleDashed), 'an unknown result has the circle-dashed icon').toHaveCount(1);
  await expect(results.nth(2).locator('.result')).toHaveCSS('color', await tokenColor(page, '--check-result-not-checked-foreground'));
  await expect(results.nth(2).locator('.finding'), 'with its reason').toHaveText('The check did not run');
  await expect(results.nth(2).locator('.time')).toHaveText(clock('2025-03-01T10:02:00Z'));
  await expect(replyOf(page, refs[1]!), 'no all-clear anywhere in the reply').not.toContainText('Everything I checked passed');

  const bare = replyOf(page, refs[2]!).locator('app-check-rows');
  await expect(bare.locator('li.row'), 'rows with no key still show').toHaveCount(2);
  await expect(bare.locator('.sentence'), 'but every row passing is no all-clear without the key').toHaveCount(0);
  await expect(replyOf(page, refs[2]!)).not.toContainText('Everything I checked passed');

  const keyOnly = replyOf(page, refs[3]!).locator('app-check-rows');
  await expect(keyOnly.locator('.sentence'), 'a key with no rows shows its sentence').toHaveText("I'm not watching any productions yet, so I can't say. Ask me to watch one.");
  await expect(keyOnly.locator('li.row'), 'and no row').toHaveCount(0);

  const failingRows = replyOf(page, refs[4]!).locator('app-check-rows');
  await expect(failingRows.locator('.sentence'), 'a row that was not run has no time in the sentence').toHaveText(
    `Not everything: Warehouse queue (12 messages are waiting, at ${clock('2025-03-01T10:01:00Z')}); Partner feed (not run yet).`,
  );
  await expect(failingRows.locator('li.row')).toHaveCount(2);
});

/** What D8 reads of a turn. */
interface Shape {
  text: string;
  checks: string;
  line1: string;
  firstReason: string;
  details: string;
}

/**
 * D8: a reload shows the same strips, details and check rows. The page is open when the turns are published, so the strips arrive
 * as events; after the reload they come from /state, and what the page shows is the same.
 */
test('D8: a reload shows the same strips, details and rows', async ({ page }) => {
  const rows = [
    { result: 'passed', entry: 'Orders production', finding: '', checkedAt: '2025-03-01T10:00:00Z' },
    { result: 'failed', entry: 'Warehouse queue', finding: '12 messages are waiting', checkedAt: '2025-03-01T10:01:00Z' },
  ];
  await open(page);
  const { refs } = await seed(
    [
      turn('D8 reply', { createdAt: '2025-03-02T10:00:00Z' }),
      turn('D8 fallback', { createdAt: '2025-03-02T10:01:00Z', ...FALLBACK }),
      turn('D8 checks', { createdAt: '2025-03-02T10:02:00Z', checkKey: 'checks.allPassed', checks: rows }),
    ],
    true,
  );
  /** What a turn shows, apart from the lines of reasons after the first (how many show depends on which turn is the newest). */
  const seen = async (): Promise<Shape[]> => {
    const shapes: Shape[] = [];
    for (const ref of refs) {
      const reply = replyOf(page, ref);
      await expect(reply).toHaveCount(1);
      const button = reply.getByRole('button', { name: 'Decision details' });
      await expect(button).toHaveCount(1);
      if ((await button.getAttribute('aria-expanded')) === 'false') await button.click();
      await expect(button).toHaveAttribute('aria-expanded', 'true');
      const checks = reply.locator('app-check-rows');
      shapes.push({
        text: plain(await reply.locator('.text').innerText()),
        checks: (await checks.count()) > 0 ? plain(await checks.innerText()) : '',
        line1: plain(await reply.locator('.line1').innerText()),
        firstReason: plain(await reply.locator('.reason').first().innerText()),
        details: plain(await reply.locator('dl.details').innerText()),
      });
    }
    return shapes;
  };
  const before = await seen();
  expect(before[0]!.line1, 'the first strip has its chip, confidence and the cost of the turn').toBe(`Act Confidence 0.92${DOT}$0.0008`);
  expect(before[0]!.details).toContain(`Decision $0.0003${DOT}Turn $0.0008`);
  expect(before[1]!.firstReason).toBe("The model didn't answer within 60 seconds.");
  expect(before[1]!.line1).toContain('Fallback');
  expect(before[2]!.checks).toContain('Everything I checked passed.');
  expect(before[2]!.checks).toContain('12 messages are waiting');

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  expect(await seen(), 'after the reload every strip, details panel and row is the same').toEqual(before);
});

/** D9: a strip that lands is no live region and moves no focus. */
test('D9: the strip is no live region and moves no focus when it lands', async ({ page }) => {
  await page.addInitScript(() => {
    (window as unknown as { focusIns: number }).focusIns = 0;
    document.addEventListener('focusin', () => {
      (window as unknown as { focusIns: number }).focusIns += 1;
    });
  });
  const field = await open(page);
  await field.focus();
  await expect(field).toBeFocused();
  const focused = await page.evaluate(() => (window as unknown as { focusIns: number }).focusIns);
  const { refs } = await seed([turn('D9', { createdAt: '2025-03-03T10:00:00Z', checkKey: 'checks.allPassed', checks: [{ result: 'passed', entry: 'Orders production', checkedAt: '2025-03-03T10:00:00Z' }] })], true);
  await expect(stripOf(page, refs[0]!), 'the turn lands with its strip').toHaveCount(1);
  await expect(replyOf(page, refs[0]!).locator('app-check-rows li.row')).toHaveCount(1);
  expect(await page.evaluate(() => (window as unknown as { focusIns: number }).focusIns), 'nothing took focus').toBe(focused);
  await expect(field, 'the composer keeps it').toBeFocused();
  await expect(page.getByRole('main').locator(LIVE_REGIONS), 'main has no live region, no log, status or alert').toHaveCount(0);
});

/** D10: BridgeSink's decision.recorded becomes a decision event that /events serves, with every field of the decision. */
test('D10: /events serves BridgeSink\'s decision event', async ({ page }) => {
  const { user } = fixtureUser('DECISION');
  const { decisions } = await seed([turn('D10', { createdAt: '2025-03-04T10:00:00Z' })]);
  const ref = decisions[0]!.triage;
  await open(page);
  const served = page.waitForResponse(
    async (response) => {
      if (!EVENTS.test(response.url())) return false;
      try {
        const body = (await response.json()) as { events: Array<{ type: string; payload: { ref?: string } }> };
        return body.events.some((event) => event.type === 'decision' && event.payload.ref === ref);
      } catch {
        return false;
      }
    },
    { timeout: 15_000 },
  );
  await sinkEvent(user, 'decision.recorded', { ref });
  const body = (await (await served).json()) as { events: Array<{ seq: number; stream: string; type: string; payload: Record<string, unknown> }> };
  const event = body.events.find((candidate) => candidate.type === 'decision' && candidate.payload['ref'] === ref)!;
  expect(event.stream, 'on the session\'s stream').toBe('session');
  expect(event.payload).toMatchObject({
    ref,
    kind: 'decide',
    itemSummary: 'zz seeded summary',
    outcome: 'act',
    reasons: 'Reason one.\nReason two.\nReason three.\nReason four.',
    confidence: 0.92,
    inputTokens: 1084,
    outputTokens: 312,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    costUSD: 0.0003,
    model: 'Claude Haiku 5.5',
    agentStepCount: 2,
    durationMs: 3400,
    traceHeaderId: 4512,
    traceNamespace: 'OCUTALON',
  });
  expect(String(event.payload['itemId']), 'the item').toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(event.payload['fallback'] ?? false, 'not a fallback').toBe(false);
  expect(event.payload['fallbackReason'] ?? '', 'with no fallback reason').toBe('');
});

/**
 * D11: what a model or a tool wrote is text on the page, never markup: a reason line, a check's entry and its finding show as the
 * characters they are, and nothing made of them is an element or runs.
 */
test('D11: markup in a reason, a check entry and a finding shows as text', async ({ page }) => {
  const reason = '<b>zz bold reason</b> <img src="x" onerror="window.zzMarkup = 1">';
  const entry = '<i>zz entry</i>';
  const finding = '<u>zz finding</u> <img src="y" onerror="window.zzMarkup = 2">';
  const { refs } = await seed([
    turn('D11', {
      createdAt: '2025-03-05T10:00:00Z',
      triage: { ...ACT, reasons: `${reason}\nSecond reason.` },
      checks: [{ result: 'failed', entry, finding, checkedAt: '2025-03-05T10:00:00Z' }],
    }),
  ]);
  await open(page);
  const reply = replyOf(page, refs[0]!);
  await expect(stripOf(page, refs[0]!).locator('.reason').first(), 'the reason line is its own characters').toHaveText(reason);
  const row = reply.locator('app-check-rows li.row');
  await expect(row.locator('.entry'), 'so is the check\'s entry').toHaveText(entry);
  await expect(row.locator('.finding'), 'and its finding').toHaveText(finding);
  await expect(reply.locator('b, i, u, img[src="x"], img[src="y"]'), 'none of it became an element').toHaveCount(0);
  expect(await page.evaluate(() => (window as unknown as { zzMarkup?: number }).zzMarkup), 'and no handler ran').toBeUndefined();
});

/** D12: Decision details leaves out the rows it has no figure for (the model, the duration), and shows an absent count as 0. */
test('D12: Decision details leaves out the model and the duration a decision has none of', async ({ page }) => {
  const { refs, decisions } = await seed([
    turn('D12', {
      createdAt: '2025-03-06T10:00:00Z',
      triage: { outcome: 'act', reasons: 'Bare reason.', confidence: 0.5, model: '' },
      turn: undefined,
      usage: [],
    }),
  ]);
  await open(page);
  const strip = stripOf(page, refs[0]!);
  await expect(strip.locator('.line1 .meta'), 'a turn with no usage costs less than $0.0001').toHaveText(`Confidence 0.50${DOT}<$0.0001`);
  await strip.getByRole('button', { name: 'Decision details' }).click();
  const details = strip.locator('dl.details');
  await expect(details).toBeVisible();
  await expect.soft(details.locator('dt'), 'no Model and no Duration').toHaveText(['Tokens', 'Agent steps', 'Decision message', 'Cost']);
  await expect.soft(details.locator('dd'), 'every absent count is 0').toHaveText([`Input 0${DOT}Output (includes thinking) 0${DOT}Cache read 0${DOT}Cache write 0`, '0', decisions[0]!.triage, '<$0.0001']);
});

/**
 * D13: a reply the model wrote, whose own decision fell back, still shows the fallback strip: Tell now, the Fallback flag and the
 * decision's reason first, with no confidence; the reply's text is the model's.
 */
test('D13: a reply whose decision fell back shows the fallback strip with the decision\'s reason', async ({ page }) => {
  const { refs } = await seed([
    turn('D13', {
      createdAt: '2025-03-07T10:00:00Z',
      triage: { outcome: 'tellnow', fallback: true, fallbackReason: 'empty', reasons: 'Fixed rules chose this.', confidence: 0.5, costUSD: 0.0003 },
      turn: undefined,
      usage: [USAGE[0]!],
    }),
  ]);
  await open(page);
  const reply = replyOf(page, refs[0]!);
  const strip = stripOf(page, refs[0]!);
  await expect(reply.locator('.text'), 'the reply is the model\'s own text, not the fallback sentence').toHaveText('zz reply to D13');
  await expect(strip.locator('app-outcome-chip .chip')).toHaveText('Tell now');
  await expect(strip.locator('app-fallback-flag .flag')).toHaveText('Fallback');
  await expect(strip, 'no confidence on a fallback').not.toContainText('Confidence');
  await expect(strip.locator('.reason').first(), 'the decision\'s reason, as a sentence, comes first').toHaveText("The model's reply was empty.");
});

/**
 * D14: a fallback turn that has no decision row at all (Conversation's own fallback unusable, which a stack with the real Decide
 * still gives when a request fails) shows the fallback strip alone: Tell now, the Fallback flag and the reason as a sentence, with no
 * confidence, no cost and no Details button. A reply through a keyless stack has its decision, and C15 of chat.spec pins that strip.
 */
test('D14: a fallback turn with no decision shows the fallback strip alone', async ({ page }) => {
  const seeded = await seed([
    turn('D14', {
      createdAt: '2025-03-08T10:00:00Z',
      replyText: '',
      catalogKey: 'conversation.turnFallback',
      fallbackReason: 'unusable',
      triage: undefined,
      turn: undefined,
      usage: [],
    }),
  ]);
  try {
    await open(page);
    const strip = stripOf(page, seeded.refs[0]!);
    await expect(strip, 'the reply has one strip').toHaveCount(1);
    await expect(strip.locator('app-outcome-chip')).toHaveText('Tell now');
    await expect(strip.locator('app-fallback-flag')).toHaveText('Fallback');
    await expect(strip.locator('.reason')).toHaveText(["The model's reply couldn't be used."]);
    await expect(strip, 'no confidence').not.toContainText('Confidence');
    await expect(strip, 'no cost').not.toContainText('$');
    await expect(strip.getByRole('button'), 'no Details button').toHaveCount(0);
  } finally {
    await cleanFixtureRows(turnRows(seeded));
  }
});
