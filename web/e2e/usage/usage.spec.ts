import { expect, test, type Locator, type Page, type Response } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { NAV_LINKS_USER } from '../support/header-nav';
import { fixtureUser } from '../support/iris';
import { sessionRefOfUser } from '../support/memory';
import { announcements, recordAnnouncements } from '../support/page';
import { scanContrast, scanNames } from '../support/scan';
import { cleanUsage, clearUsage, seedUsage, type SeededUsage, type UsageSeed } from '../support/usage';

/**
 * Story 37.2, the Usage page (U1 to U15), in a real browser against a real stack, signed in as the LIVE fixture user (OcuTalonUser only, the online demo
 * visitors' role). Each case clears the LIVE session's Usage rows (this folder relies on workers 1 and fullyParallel off, playwright.config.ts) and seeds the
 * rows below through the product's test fixture, one to five days ago in the instance zone, plus a row of the second session (PANEL) and an eval-owned row that must
 * never show. The expected tables are written out from those rows, not computed from the page:
 *
 *   row  day  agent             channel   model  input output cacheRead cacheWrite cost      largest
 *   r1   1    TriageAgent       web       A      1000  100    400       50         0.0123    11000
 *   r2   1    TriageAgent       web       A      500   50     0         0          0.0041    7000
 *   r3   2    DiagnosisAgent    phone     B      2000  300    100       0          0.15      42000
 *   r4   3    ChatAgent         web       A      800   80     0         0          0.0006    5000
 *   r5   3    ChatAgentRetry    telegram  B      200   20     0         0          0.00005   6000
 *   r6   4    compaction (est)  web       A      3000  300    0         0          0.02      30000
 *   r7   5    ChatAgent         phone     B      40    4      0         0          (none)    900
 */
const USAGE = '/ocutalon/api/v1/usage';
const TITLE = 'Usage \u00B7 OcuTalon';
const EMPTY = 'No model use in this period.';
const stamp = Date.now().toString(36);
const MODEL_A = `zz-usage-a-${stamp}`;
const MODEL_B = `zz-usage-b-${stamp}`;
const MODEL_P = `zz-usage-p-${stamp}`;
const MODEL_E = `zz-usage-e-${stamp}`;

const ROWS: UsageSeed[] = [
  { daysAgo: 1, agent: 'TriageAgent', channel: 'web', model: MODEL_A, input: 1000, output: 100, cacheRead: 400, cacheWrite: 50, cost: 0.0123, largest: 11000 },
  { daysAgo: 1, agent: 'TriageAgent', channel: 'web', model: MODEL_A, input: 500, output: 50, cost: 0.0041, largest: 7000 },
  { daysAgo: 2, agent: 'DiagnosisAgent', channel: 'phone', model: MODEL_B, input: 2000, output: 300, cacheRead: 100, cost: 0.15, largest: 42000 },
  { daysAgo: 3, agent: 'ChatAgent', channel: 'web', model: MODEL_A, input: 800, output: 80, cost: 0.0006, largest: 5000 },
  { daysAgo: 3, agent: 'ChatAgentRetry', channel: 'telegram', model: MODEL_B, input: 200, output: 20, cost: 0.00005, largest: 6000 },
  { daysAgo: 4, agent: 'compaction', channel: 'web', model: MODEL_A, estimated: true, input: 3000, output: 300, cost: 0.02, largest: 30000 },
  { daysAgo: 5, agent: 'ChatAgent', channel: 'phone', model: MODEL_B, input: 40, output: 4, cost: null, largest: 900 },
];

/** One expected table row: the name, the marker words, the six numbers as the table writes them, and the tokens and cost as numbers (the chart's data). */
interface Expected {
  name: string;
  marker: string;
  cells: [string, string, string, string, string, string];
  tokens: number;
  cost: number;
}
const row = (name: string, marker: string, cells: Expected['cells'], tokens: number, cost: number): Expected => ({ name, marker, cells, tokens, cost });
// mutation: Usage page cost() returns formatCost(amount) for every amount -> U2 (the zero rows' "$0" cells) red.
const ZERO = (name: string): Expected => row(name, '', ['0', '0', '0', '0', '0', '$0'], 0, 0);

const BY_AGENT: Expected[] = [
  row('Chat agent', '', ['1,040', '104', '0', '0', '1,144', '$0.0007'], 1144, 0.00065),
  row('Chat summaries', 'estimated', ['3,000', '300', '0', '0', '3,300', '$0.020'], 3300, 0.02),
  row('Diagnosis agent', '', ['2,000', '300', '100', '0', '2,300', '$0.150'], 2300, 0.15),
  row('Triage agent', '', ['1,500', '150', '400', '50', '1,650', '$0.016'], 1650, 0.0164),
];
const BY_CHANNEL: Expected[] = [
  row('Simulated phone', '', ['2,040', '304', '100', '0', '2,344', '$0.150'], 2344, 0.15),
  row('Telegram', '', ['200', '20', '0', '0', '220', '<$0.0001'], 220, 0.00005),
  row('Web chat', 'includes estimates', ['5,300', '530', '400', '50', '5,830', '$0.037'], 5830, 0.037),
];
const BY_MODEL: Expected[] = [
  row(MODEL_A, 'includes estimates', ['5,300', '530', '400', '50', '5,830', '$0.037'], 5830, 0.037),
  row(MODEL_B, '', ['2,240', '324', '100', '0', '2,564', '$0.150'], 2564, 0.15005),
];
const TOTAL_TOKENS = 8394;
const TOTAL_COST = 0.18705;

/** The day grouping's rows, oldest first, for the seven dates (index 0 is six days ago, index 6 is today). */
const BY_DAY = (labels: string[]): Expected[] => [
  ZERO(labels[0]!),
  row(labels[1]!, '', ['40', '4', '0', '0', '44', '$0'], 44, 0),
  row(labels[2]!, 'estimated', ['3,000', '300', '0', '0', '3,300', '$0.020'], 3300, 0.02),
  row(labels[3]!, '', ['1,000', '100', '0', '0', '1,100', '$0.0007'], 1100, 0.00065),
  row(labels[4]!, '', ['2,000', '300', '100', '0', '2,300', '$0.150'], 2300, 0.15),
  row(labels[5]!, '', ['1,500', '150', '400', '50', '1,650', '$0.016'], 1650, 0.0164),
  ZERO(labels[6]!),
];

/** The largest request of each day with use, oldest first: the day's offset and the cell. */
const LARGEST: Array<[number, string]> = [
  [5, '900 of 100,000 tokens'],
  [4, '30,000 of 100,000 tokens'],
  [3, '6,000 of 100,000 tokens'],
  [2, '42,000 of 100,000 tokens'],
  [1, '11,000 of 100,000 tokens'],
];

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** A local date as the UX's short date: "Nov 9", with the year when it is not today's year. */
const short = (date: string, today: string): string => {
  const [year, month, day] = date.split('-');
  return `${MONTHS[Number(month) - 1]} ${Number(day)}${year === today.slice(0, 4) ? '' : `, ${year}`}`;
};

/** The fixture users, read when a case runs (the unit's script sets them). */
const live = (): { user: string; password: string } => fixtureUser('LIVE');
const panel = (): { user: string; password: string } => fixtureUser('PANEL');
let mine: SeededUsage;
const made: string[] = [];

test.beforeEach(async () => {
  await clearUsage(live().user);
  mine = await seedUsage(await sessionRefOfUser(live().user), ROWS);
  made.push(...mine.refs);
  const theirs = await seedUsage(await sessionRefOfUser(panel().user), [{ daysAgo: 1, agent: 'TriageAgent', channel: 'web', model: MODEL_P, input: 777, output: 7, cost: 0.7, largest: 99000 }]);
  const evals = await seedUsage('eval', [{ daysAgo: 1, agent: 'TriageAgent', channel: 'web', model: MODEL_E, input: 888, output: 8, cost: 0.8, largest: 98000 }]);
  made.push(...theirs.refs, ...evals.refs);
});

test.afterEach(async () => {
  await cleanUsage(made.splice(0));
  await clearUsage(live().user);
});

const nav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const usageLink = (page: Page): Locator => nav(page).getByRole('link', { name: 'Usage', exact: true });
const isUsage = (days: number) => (response: Response): boolean => response.request().method() === 'GET' && response.url().endsWith(`${USAGE}?days=${days}`);
const tableOf = (page: Page): Locator => page.locator('table[data-part="usage-table"]');

/** Signs the LIVE user in, presses Usage in the header and waits for the answer; returns the body of the answer. */
async function openUsage(page: Page): Promise<{ days: string[]; limit: number }> {
  await loadedAfter(page, () => signIn(page, live().user, live().password));
  const answered = page.waitForResponse(isUsage(7));
  answered.catch(() => undefined);
  await usageLink(page).click();
  const response = await answered;
  expect(response.status(), 'GET /v1/usage').toBe(200);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Usage');
  await expect(tableOf(page)).toBeVisible();
  return (await response.json()) as { days: string[]; limit: number };
}

/** The table's rows as the page shows them. */
async function rowsOf(page: Page): Promise<Array<{ key: string; name: string; marker: string; cells: string[] }>> {
  return tableOf(page)
    .locator('tbody tr')
    .evaluateAll((trs) =>
      trs.map((tr) => {
        const head = tr.querySelector('th')!;
        const marker = head.querySelector('.marker')?.textContent?.trim() ?? '';
        const name = [...head.childNodes].filter((node) => node.nodeType === Node.TEXT_NODE).map((node) => node.textContent ?? '').join('').trim();
        return { key: tr.getAttribute('data-key') ?? '', name, marker, cells: [...tr.querySelectorAll('td')].map((td) => td.textContent?.trim() ?? '') };
      }),
    );
}

/** The chart's bars and points: key, tokens and cost, in the order of the marks. */
async function marksOf(page: Page, selector: 'rect.bar' | 'circle.point'): Promise<Array<{ key: string; tokens: number; cost: number }>> {
  return page
    .locator(`svg.chart ${selector}`)
    .evaluateAll((marks) => marks.map((mark) => ({ key: mark.getAttribute('data-key') ?? '', tokens: Number(mark.getAttribute('data-tokens')), cost: Number(mark.getAttribute('data-cost')) })));
}

const group = (page: Page, name: string): Locator => page.getByRole('group', { name: 'Group by', exact: true }).getByRole('radio', { name, exact: true });

/** Chooses a grouping and waits until the table's first column carries its name, so a read of the rows never sees the previous grouping. */
async function choose(page: Page, name: string): Promise<void> {
  await group(page, name).check();
  await expect(tableOf(page).locator('thead th').first(), `the first column is named ${name}`).toHaveText(name);
}

/** One grouping: the table equals the expected rows, the totals add up, and the chart's bars and points equal the table's rows. */
async function expectGrouping(page: Page, name: string, expected: Expected[]): Promise<void> {
  await choose(page, name);
  await expect(tableOf(page).locator('tbody tr'), `${name}: a row for each group`).toHaveCount(expected.length);
  const rows = await rowsOf(page);
  expect(
    rows.map((one) => ({ name: one.name, marker: one.marker, cells: one.cells })),
    `${name}: every row equals the sum of its fixture rows`,
  ).toEqual(expected.map((one) => ({ name: one.name, marker: one.marker, cells: one.cells })));
  const tokens = rows.reduce((sum, one) => sum + Number(one.cells[4]!.replaceAll(',', '')), 0);
  expect(tokens, `${name}: the tokens add up to the fixture's total`).toBe(TOTAL_TOKENS);
  const bars = await marksOf(page, 'rect.bar');
  const points = await marksOf(page, 'circle.point');
  expect(bars.map((bar) => bar.key), `${name}: one bar for each row, in the table's order`).toEqual(rows.map((one) => one.key));
  expect(points.map((point) => point.key), `${name}: one point for each row`).toEqual(rows.map((one) => one.key));
  expect(bars.map((bar) => bar.tokens), `${name}: the bars' tokens equal the table's`).toEqual(expected.map((one) => one.tokens));
  expect(points.map((point) => point.tokens)).toEqual(expected.map((one) => one.tokens));
  bars.forEach((bar, index) => expect(bar.cost, `${name}: bar ${index}'s cost`).toBeCloseTo(expected[index]!.cost, 9));
  points.forEach((point, index) => expect(point.cost, `${name}: point ${index}'s cost`).toBeCloseTo(expected[index]!.cost, 9));
  expect(
    bars.reduce((sum, bar) => sum + bar.cost, 0),
    `${name}: the costs add up to the fixture's total`,
  ).toBeCloseTo(TOTAL_COST, 9);
}

/** U1: the header link, the address, the title, the current mark, the h1, and no History link inside the page itself (the header holds one). */
test('U1: a user who is not an admin opens Usage from the header navigation', async ({ page }) => {
  await loadedAfter(page, () => signIn(page, live().user, live().password));
  await expect(nav(page).getByRole('link'), 'the header navigation holds the links of a user who is not an admin, and no Settings').toHaveText(NAV_LINKS_USER);
  await usageLink(page).click();
  await expect(page, 'at the address #/usage').toHaveURL(/#\/usage$/);
  await expect(page, 'titled Usage \u00B7 OcuTalon').toHaveTitle(TITLE);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Usage');
  await expect(usageLink(page), 'the current page is marked').toHaveAttribute('aria-current', 'page');
  await expect(nav(page).getByRole('link', { name: 'Chat', exact: true })).not.toHaveAttribute('aria-current', 'page');
  await expect(page.getByLabel('Range', { exact: true }), 'the Range control').toBeVisible();
  await expect(page.getByRole('group', { name: 'Group by', exact: true }), 'the Group by control').toBeVisible();
  await expect(page.getByRole('heading', { level: 2 }), 'the two regions').toHaveText(['Tokens and cost', 'Largest request per day']);
  await expect(page.locator('svg.chart'), 'the chart').toHaveCount(1);
  await expect(page.locator('main.usage'), 'the page the link check is scoped to').toHaveCount(1);
  await expect(page.locator('main.usage').getByRole('link', { name: /history/i }), 'no History link inside the page').toHaveCount(0);
});

/** U2: for each grouping, the table equals the fixture sums, the totals add up, and the chart agrees with the table. */
test('U2: each grouping\'s table equals the fixture sums and the chart\'s bars and points equal the table\'s rows', async ({ page }) => {
  const { days } = await openUsage(page);
  expect(days, 'seven dates, today last').toHaveLength(7);
  expect(days[5], 'the dates are the seeded rows\' local dates').toBe(mine.dates[0]);
  expect(days[4]).toBe(mine.dates[2]);
  expect(days[3]).toBe(mine.dates[3]);
  expect(days[2]).toBe(mine.dates[5]);
  expect(days[1]).toBe(mine.dates[6]);
  const today = days[6]!;
  await expectGrouping(page, 'Day', BY_DAY(days.map((day) => short(day, today))));
  await expectGrouping(page, 'Agent', BY_AGENT);
  await expectGrouping(page, 'Channel', BY_CHANNEL);
  await expectGrouping(page, 'Model', BY_MODEL);
  await expect(page.getByText('Tokens', { exact: true }).first(), 'the series are named').toBeVisible();
});

/** U3: the compaction rows are Chat summaries, marked estimated; the retry rows count under Chat agent; a group that includes an estimate says so. */
test('U3: Chat summaries is marked estimated, the retry rows sit under Chat agent, and a group that includes an estimate is marked', async ({ page }) => {
  await openUsage(page);
  await choose(page, 'Agent');
  const agents = await rowsOf(page);
  const summaries = agents.find((one) => one.name === 'Chat summaries');
  expect(summaries?.marker, 'Chat summaries carries the word estimated').toBe('estimated');
  expect(summaries?.cells[4], 'its tokens are the compaction row\'s').toBe('3,300');
  expect(agents.map((one) => one.name), 'the agents, sorted; no Compaction and no retry row of its own').toEqual(['Chat agent', 'Chat summaries', 'Diagnosis agent', 'Triage agent']);
  expect(agents.find((one) => one.name === 'Chat agent')?.cells[4], 'the retry runner\'s 220 tokens count under Chat agent (800 + 80 + 220 + 44)').toBe('1,144');
  expect(agents.filter((one) => one.marker !== '').map((one) => one.name), 'only Chat summaries is an estimate').toEqual(['Chat summaries']);
  await choose(page, 'Channel');
  expect((await rowsOf(page)).filter((one) => one.marker !== '').map((one) => `${one.name}: ${one.marker}`), 'Web chat includes the estimate').toEqual(['Web chat: includes estimates']);
  await choose(page, 'Day');
  const days = await rowsOf(page);
  expect(days.filter((one) => one.marker !== '').map((one) => one.marker), 'one day is the estimate alone').toEqual(['estimated']);
});

/** U4: each day with use lists its largest request as "n of 100,000 tokens". */
test('U4: the largest request of each day is listed against the limit', async ({ page }) => {
  const { days, limit } = await openUsage(page);
  expect(limit).toBe(100000);
  const today = days[6]!;
  const table = page.getByRole('region', { name: 'Largest request per day', exact: true }).getByRole('table');
  await expect(table.locator('thead th')).toHaveText(['Day', 'Largest request (estimated)']);
  const rows = await table.locator('tbody tr').evaluateAll((trs) => trs.map((tr) => [tr.querySelector('th')?.textContent?.trim() ?? '', tr.querySelector('td')?.textContent?.trim() ?? '']));
  expect(rows, 'the days with use, oldest first, each with its largest request').toEqual(LARGEST.map(([offset, cell]) => [short(days[6 - offset]!, today), cell]));
});

/** U5: a range with no use says so and shows no chart and no table. */
test('U5: Today has no use: the empty text and no chart or table', async ({ page }) => {
  await openUsage(page);
  const answered = page.waitForResponse(isUsage(1));
  await page.getByLabel('Range', { exact: true }).selectOption('1');
  expect((await answered).status()).toBe(200);
  await expect(page.getByText(EMPTY, { exact: true })).toBeVisible();
  await expect(page.locator('svg.chart'), 'no chart').toHaveCount(0);
  await expect(page.locator('table'), 'no table').toHaveCount(0);
  await expect(page.getByRole('heading', { level: 2 }), 'and no region heading').toHaveCount(0);
  await page.getByLabel('Range', { exact: true }).selectOption('30');
  await expect(tableOf(page), 'the 30-day range has the table again').toBeVisible();
});

/** U6: by keyboard alone, every control is reachable, labelled and operable; the legend and markers are words and shapes. */
test('U6: the page works by keyboard, every control has a label, and nothing relies on colour', async ({ page }) => {
  await openUsage(page);
  const range = page.getByLabel('Range', { exact: true });
  await expect(range, 'getByLabel finds the Range select').toHaveCount(1);
  for (const name of ['Day', 'Agent', 'Channel', 'Model']) await expect(page.getByLabel(name, { exact: true }), `getByLabel finds ${name}`).toHaveCount(1);

  await page.locator('app-header a.home').focus();
  let reached = '';
  for (let tabs = 0; tabs < 14 && !reached.includes('range'); tabs += 1) {
    await page.keyboard.press('Tab');
    if (await usageLink(page).evaluate((el) => el === document.activeElement)) reached += 'nav ';
    if (await range.evaluate((el) => el === document.activeElement)) reached += 'range';
  }
  expect(reached, 'Tab reaches the Usage item and then the Range select').toBe('nav range');
  await page.keyboard.press('Tab');
  await expect(group(page, 'Day'), 'then the checked Group by radio').toBeFocused();

  await page.keyboard.press('ArrowRight');
  await expect(group(page, 'Agent'), 'the arrow key chooses Agent').toBeChecked();
  await expect(tableOf(page).locator('thead th').first()).toHaveText('Agent');
  await page.keyboard.press('ArrowRight');
  await expect(group(page, 'Channel')).toBeChecked();

  await range.focus();
  const month = page.waitForResponse(isUsage(30));
  // Type-ahead picks 'Last 30 days' on every platform's select; ArrowDown only opens the list on macOS.
  await page.keyboard.type('Last 3');
  expect((await month).status(), 'the Range select changes by keyboard').toBe(200);
  await expect(range).toHaveValue('30');

  await expect(page.locator('figure .legend'), 'the legend names both series in words').toHaveText(/Tokens\s+Cost/);
  await expect(page.locator('figure .legend svg.swatch-bar rect'), 'the tokens swatch is a square').toHaveCount(1);
  await expect(page.locator('figure .legend svg.swatch-line line'), 'the cost swatch is a line').toHaveCount(1);
  await expect(page.locator('figure .legend svg.swatch-line circle'), 'with a dot').toHaveCount(1);
  await expect(page.locator('svg.chart rect.bar').first(), 'the tokens are bars').toBeAttached();
  await expect(page.locator('svg.chart polyline.cost-line'), 'the cost is a line').toHaveCount(1);
  await expect(page.locator('svg.chart circle.point').first(), 'with point markers').toBeAttached();
  await choose(page, 'Agent');
  await expect(tableOf(page).locator('tbody tr').filter({ hasText: 'Chat summaries' }), 'the estimate is a word in the row').toContainText('estimated');
  await expect(page.locator('svg.chart'), 'the chart is hidden from assistive technology').toHaveAttribute('aria-hidden', 'true');
});

/** U7: no unnamed control and no contrast finding, in the light theme and the dark one. */
test('U7: the page passes the names and contrast scans in light and dark', async ({ page }) => {
  await openUsage(page);
  for (const scheme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: scheme });
    for (const name of ['Day', 'Agent']) {
      await choose(page, name);
      const what = `usage ${scheme} ${name}`;
      expect([...(await scanNames(page, what)), ...(await scanContrast(page, what))], what).toEqual([]);
    }
  }
});

/** U8: the regions stack below 1024px, the page never scrolls sideways, also with the text at twice its size, and at 305px every navigation link is shown in the window. */
test('U8: below 1024px the regions stack, and the page does not scroll sideways at 200%', async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 800 });
  await openUsage(page);
  const chart = (await page.locator('section[data-part="usage-chart"]').boundingBox())!;
  const largest = (await page.locator('section[data-part="usage-largest"]').boundingBox())!;
  expect(largest.y, 'the Largest request region is below the Tokens and cost region').toBeGreaterThanOrEqual(chart.y + chart.height - 1);
  const sideways = (): Promise<boolean[]> =>
    page.evaluate(() => [document.documentElement, document.body, document.querySelector('main.usage')!].map((el) => el.scrollWidth <= el.clientWidth + 1));
  expect(await sideways(), 'no sideways scroll at 1000px').toEqual([true, true, true]);

  await page.setViewportSize({ width: 305, height: 700 });
  await expect(nav(page).getByRole('link'), 'at 305px the header navigation still holds every link').toHaveText(NAV_LINKS_USER);
  for (const link of await nav(page).getByRole('link').all()) {
    await expect(link, 'each link is shown at 305px').toBeVisible();
    const box = (await link.boundingBox())!;
    expect(box.x >= 0 && box.x + box.width <= 305.5, `${await link.textContent()} is inside the 305px window`).toBe(true);
    expect(box.y >= 0 && box.y + box.height <= 700.5, `${await link.textContent()} is inside the window's height`).toBe(true);
  }

  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addStyleTag({
    content: ':root { font-size: 200%; --type-body-font-size: 28px; --type-body-sm-font-size: 26px; --type-label-font-size: 24px; --type-caption-font-size: 24px; --type-headline-font-size: 34px; }',
  });
  await expect(tableOf(page)).toBeVisible();
  expect(await sideways(), 'no sideways scroll at 1280px with the text at 200%').toEqual([true, true, true]);
  await expect(page.locator('div.scroll').first(), 'the table scrolls in its own region').toBeVisible();
});

/** U9: another session's rows never show. */
test('U9: the second session\'s and eval\'s rows never show for the LIVE user', async ({ page }) => {
  await openUsage(page);
  await choose(page, 'Model');
  expect((await rowsOf(page)).map((one) => one.name), 'only the LIVE session\'s two models').toEqual([MODEL_A, MODEL_B]);
  await expect(page.locator('main'), 'no trace of the other models').not.toContainText('zz-usage-p');
  await expect(page.locator('main')).not.toContainText('zz-usage-e');
  const largest = page.getByRole('region', { name: 'Largest request per day', exact: true });
  await expect(largest, 'nor of their largest requests').not.toContainText('99,000');
  await expect(largest).not.toContainText('98,000');
});

/** U10: a failed read shows its error text and Retry, Retry reads again, and the limit of the answer is the one the page shows. */
test('U10: a failed read shows its error and Retry, and the limit shown is the answer\'s own', async ({ page }) => {
  let failing = true;
  await page.route(
    (url) => url.pathname === USAGE && url.searchParams.get('days') === '7',
    async (route) => {
      if (failing) {
        await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: 'server_error' }) });
        return;
      }
      const real = await route.fetch();
      const body = (await real.json()) as { limit: number };
      await route.fulfill({ response: real, json: { ...body, limit: 50000 } });
    },
  );
  await loadedAfter(page, () => signIn(page, live().user, live().password));
  await usageLink(page).click();
  await expect(page.locator('main').getByText("Couldn't load your usage.", { exact: true }), 'the error text').toBeVisible();
  await expect(page.locator('table'), 'no table under the error').toHaveCount(0);
  failing = false;
  await page.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(tableOf(page), 'Retry reads again and shows the table').toBeVisible();
  await expect(page.locator('main').getByText("Couldn't load your usage.", { exact: true })).toHaveCount(0);
  const cells = await page.locator('section[data-part="usage-largest"] tbody td').allTextContents();
  expect(cells.length, 'the days with use').toBeGreaterThan(0);
  for (const cell of cells) expect(cell, 'the limit is the answer\'s own').toMatch(/ of 50,000 tokens$/);
});

/** U11: a grouping change asks nothing; a range change asks once. */
test('U11: a grouping change asks the route nothing and a range change asks it once', async ({ page }) => {
  const asked: string[] = [];
  page.on('request', (request) => {
    const url = new URL(request.url());
    if (request.method() === 'GET' && url.pathname === USAGE) asked.push(url.search);
  });
  await openUsage(page);
  expect(asked, 'opening asks once').toEqual(['?days=7']);
  for (const name of ['Agent', 'Channel', 'Model', 'Day']) await choose(page, name);
  expect(asked, 'four grouping changes asked nothing').toEqual(['?days=7']);
  const month = page.waitForResponse(isUsage(30));
  await page.getByLabel('Range', { exact: true }).selectOption('30');
  expect((await month).status()).toBe(200);
  await expect(tableOf(page)).toBeVisible();
  expect(asked, 'a range change asked once').toEqual(['?days=7', '?days=30']);
});

/** U12: the chart draws what the table says: bar heights follow the tokens, and the cost line runs through the points. */
test('U12: the bars have heights that follow the tokens and the cost line runs through the points', async ({ page }) => {
  await openUsage(page);
  await choose(page, 'Agent');
  const bars = await page
    .locator('svg.chart rect.bar')
    .evaluateAll((marks) => marks.map((mark) => ({ tokens: Number(mark.getAttribute('data-tokens')), height: Number(mark.getAttribute('height')), drawn: mark.getBoundingClientRect().height })));
  expect(bars, 'one bar for each agent').toHaveLength(BY_AGENT.length);
  const tallest = bars.reduce((one, other) => (other.tokens > one.tokens ? other : one));
  expect(tallest.height, 'the tallest bar has a height').toBeGreaterThan(10);
  expect(tallest.drawn, 'and is drawn with it').toBeGreaterThan(10);
  for (const bar of bars) expect(bar.height, `a bar of ${bar.tokens} tokens is ${bar.tokens} / ${tallest.tokens} of the tallest`).toBeCloseTo((bar.tokens / tallest.tokens) * tallest.height, 1);
  const line = (await page.locator('svg.chart polyline.cost-line').getAttribute('points'))!.trim().split(/\s+/);
  const points = await page.locator('svg.chart circle.point').evaluateAll((marks) => marks.map((mark) => [Number(mark.getAttribute('cx')), Number(mark.getAttribute('cy'))]));
  expect(line, 'the line has one corner for each point').toHaveLength(points.length);
  line.forEach((corner, index) => {
    const [x, y] = corner.split(',').map(Number);
    expect(x, `corner ${index} is point ${index}'s x`).toBeCloseTo(points[index]![0]!, 1);
    expect(y, `corner ${index} is point ${index}'s y`).toBeCloseTo(points[index]![1]!, 1);
  });
});

/** U13: the figures of the table and of the largest-request table are tabular. */
test('U13: the figures of both tables are tabular', async ({ page }) => {
  await openUsage(page);
  await expect(tableOf(page).locator('tbody td').first(), 'the usage table\'s figures').toHaveCSS('font-variant-numeric', 'tabular-nums');
  await expect(page.locator('section[data-part="usage-largest"] tbody td').first(), 'the largest-request figures').toHaveCSS('font-variant-numeric', 'tabular-nums');
});

/** U14: a Retry that fails again keeps focus on Retry, and each failed read is announced. */
test('U14: a Retry that fails again keeps focus on Retry, and each failure is announced', async ({ page }) => {
  const failed = "Couldn't load your usage.";
  let reads = 0;
  await recordAnnouncements(page);
  await page.route(
    (url) => url.pathname === USAGE,
    async (route) => {
      reads += 1;
      await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: 'server_error' }) });
    },
  );
  await loadedAfter(page, () => signIn(page, live().user, live().password));
  await usageLink(page).click();
  const retry = page.getByRole('button', { name: 'Retry', exact: true });
  await expect(retry, 'the failed read shows Retry').toBeVisible();
  await expect.poll(() => announcements(page, failed), { message: 'the failure is announced' }).toBe(1);
  await retry.focus();
  await page.keyboard.press('Enter');
  await expect.poll(() => reads, { message: 'Retry read again' }).toBe(2);
  await expect.poll(() => announcements(page, failed), { message: 'the second failure is announced too' }).toBe(2);
  await expect(retry, 'Retry keeps focus through a read that fails again').toBeFocused();
  await expect(page.locator('main').getByText(failed, { exact: true }), 'the error text stays').toBeVisible();
});

/** U15: the answer to an earlier range that arrives after the answer to a later one is dropped, so a table never shows another range's numbers. */
test('U15: a late answer to an earlier range does not replace the current range', async ({ page }) => {
  let release: () => void = () => undefined;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route(
    (url) => url.pathname === USAGE && url.searchParams.get('days') === '7',
    async (route) => {
      const real = await route.fetch();
      const body = (await real.json()) as { limit: number };
      await held;
      await route.fulfill({ response: real, json: { ...body, limit: 50000 } });
    },
  );
  await loadedAfter(page, () => signIn(page, live().user, live().password));
  await usageLink(page).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Usage');
  const month = page.waitForResponse(isUsage(30));
  await page.getByLabel('Range', { exact: true }).selectOption('30');
  expect((await month).status()).toBe(200);
  await expect(tableOf(page), 'the 30-day answer is shown').toBeVisible();
  const late = page.waitForResponse(isUsage(7));
  release();
  await (await late).finished();
  await page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 500)));
  await expect(page.getByLabel('Range', { exact: true })).toHaveValue('30');
  const cells = await page.locator('section[data-part="usage-largest"] tbody td').allTextContents();
  expect(cells.length, 'the days with use').toBeGreaterThan(0);
  for (const cell of cells) expect(cell, 'the late 7-day answer (limit 50,000) was dropped').toMatch(/ of 100,000 tokens$/);
});
