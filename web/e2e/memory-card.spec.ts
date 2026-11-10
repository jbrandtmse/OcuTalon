import { expect, test, type Locator, type Page, type Request, type Response } from './support/fixtures';

import { README_ACCOUNT, envelope, signIn } from './sign-in/helpers';
import { dropPhone, pointKeys, restoreKeys } from './support/devices';
import { loadedAfter, railOf, signInReadmeLoaded, unique } from './support/floor';
import { cleanFixtureRows, fixtureUser, sendItem, seedOtherSession } from './support/iris';
import {
  localTimeUtc,
  logMark,
  memoryExists,
  pinnedCountOf,
  precedentExists,
  removeDecisionsOf,
  removeMemory,
  removeNoteRows,
  removePrecedent,
  seedMemory,
  seedNoteTurn,
  seedPrecedent,
  sessionRefOfUser,
  setMemorySource,
  triageRequests,
  waitDecideRef,
} from './support/memory';
import { announcements, recordAnnouncements } from './support/page';
import { sessionRef } from './support/persona';
import { instanceSeq, monitorSettled, runnersReady, runnersRecorded } from './support/runners';

/**
 * Story 41.6 (MC1 to MC10; FR-71, FR-72, AD-4, AD-28, NFR-25), the Memory card in the status rail, in a real browser against the stack that test-sign-in.sh
 * seeds, signed in as the README account. The card reads `GET /api/v1/memory/notes` for today and yesterday and `GET /api/v1/memory/precedents`, and
 * Forget sends `DELETE /api/v1/memory/precedents/:ref`. Every case seeds its own rows (support/memory.ts), asserts only on them and on marked lines,
 * and removes them by Ref in `finally`, because other specs expect the account's defaults. The card's texts are written out here as the oracle:
 * EXPERIENCE's, the epics' day labels and the Contest Planner's ruling of 2026-11-08. The browser runs in UTC with the en-GB locale.
 *   MC1  the rail's eight headings in order, the tabs, their roles and the Notes intro;
 *   MC2  a done turn today and one yesterday show under Today and Yesterday, each day's lines in served order;
 *   MC3  the empty texts after a read that answered with nothing, and the intro only while a read is pending or after it fails (AD-28);
 *   MC4  three rows (noise, approval, tool), their titles, meta lines and the tool note; Forget asks, Esc cancels, confirm sends one DELETE;
 *   MC5  a failed confirm keeps the dialog and the row; a 404 removes the row;
 *   MC6  by keyboard alone: the tabs, Forget, the dialog;
 *   MC7  in the drawer band, Forget's dialog opens and Cancel and Esc give focus back to Forget with the drawer open;
 *   MC8  the demo variant: another session's and a seeded row never show, and the card keeps nothing across loads;
 *   MC9  Integration: after Forget the next decide request for the same sender carries no precedent (the CI mock's log);
 *   MC10 a served line, the cut mark "(more not shown)" included, is one list item as served.
 * Story 41.13 (FR-73, FR-74, DW-996, DW-997, DW-1030, DW-1031, DW-1040) adds the tabs Pinned and All memories and the shared confirm dialog, signed in as the unprivileged LIVE
 * fixture user (role OcuTalonUser only); every case seeds its memories through support/memory.ts and removes them in `finally`:
 *   MC11 the four tabs in order, with their roles, and the arrows cycle all four;
 *   MC12 All memories lists a told and a learned row with their chips; typing sends no search and Enter sends one; a match, and "No memories match.";
 *   MC13 Pin moves a row to Pinned with the figure (held arithmetic), and Unpin takes it off and reads the figure again (Integration: the real route, gate, MemoryOps and Memory.CoreBlock);
 *   MC14 two pins of 2,000 and 1,956 characters, then Pin on a 2-character row shows the refusal, announced and named in the button's description, and the row stays unpinned;
 *   MC15 Forget asks, then the row leaves All memories and Pinned, and a search no longer finds it;
 *   MC16 a faked 503 search_busy shows the card's own busy notice, announced and named in the search's description;
 *   MC17 the confirm dialog's faked 500 notice is announced once and named in the confirm button's description;
 *   MC18 a local install shows no demo rule line;
 *   MC19 a failed pin or unpin shows the panel's notice, announced once and named in the button's description, and a 404 takes the row off with focus on the Memory heading;
 *   MC20 a 503 search_busy on the Pinned read shows the intro only, with no figure and no empty text;
 *   MC21 with more memories than the list holds, the newest 20 and the line "Showing the newest 20 of N. Search to find the others.";
 *   MC22 Forget answered 404 closes the dialog and the row leaves All memories and Pinned;
 *   MC23 Unpin on Pinned unpins by the Pinned panel's own flag, even when All memories was read before the pin;
 *   MC24 a second submit while a search is out sends nothing, and Search is aria-disabled until the answer.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const NOTES = /\/api\/v1\/memory\/notes(\?|$)/;
const PRECEDENTS = /\/api\/v1\/memory\/precedents$/;
const FORGET_ONE = /\/api\/v1\/memory\/precedents\/[^/?]+$/;
const MEMORY = '/ocutalon/api/v1/memory';
const NOTES_INTRO = "Built by OcuTalon from today's decisions, incidents, approvals and reminders. No model writes these notes.";
const NOTES_EMPTY = 'Nothing recorded yet today.';
const YESTERDAY_EMPTY = 'Nothing recorded yesterday.';
const ANSWERS_INTRO = 'OcuTalon looks at these when it decides on similar items. Only your own answers are kept here.';
const ANSWERS_EMPTY = 'No answers yet.';
const QUESTION = 'Forget this answer? OcuTalon will stop using it.';
const FAILED = "Couldn't forget it. Nothing was changed.";
const TOOL_NOTE = 'OcuTalon keeps this answer but does not use it when it decides.';
const REGION = '.empty, .hint, [aria-live], [role="status"], [role="alert"], [role="log"]';

const card = (page: Page): Locator => railOf(page).locator('app-memory-card');
const headingOf = (page: Page): Locator => page.locator('#rail-heading-memory');
const tabOf = (page: Page, name: 'Notes' | 'Your answers' | 'Pinned' | 'All memories'): Locator => card(page).getByRole('tab', { name, exact: true });
const notesPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'Notes', exact: true });
const answersPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'Your answers', exact: true });
const pinnedPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'Pinned', exact: true });
const memoriesPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'All memories', exact: true });
const rowOf = (page: Page, summary: string): Locator => answersPanel(page).locator('li.row').filter({ hasText: summary });
const forgetOf = (page: Page, summary: string): Locator => rowOf(page, summary).getByRole('button', { name: `Forget ${summary}`, exact: true });
const dialogOf = (page: Page): Locator => page.getByRole('dialog', { name: QUESTION, exact: true });
const confirmOf = (page: Page): Locator => dialogOf(page).getByRole('button', { name: 'Forget', exact: true });
const cancelOf = (page: Page): Locator => dialogOf(page).getByRole('button', { name: 'Cancel', exact: true });
/** A row seen from behind the open dialog: the dialog hides the page from assistive technology, so a role query finds nothing there. */
const rowBehind = (page: Page, summary: string): Locator => page.locator('app-memory-card li.row').filter({ hasText: summary });
const metaOf = (row: Locator): Locator => row.locator('.meta > span:not([aria-hidden="true"])');
/** The list items under a day's label in the Notes panel. */
const linesOf = (page: Page, day: 'Today' | 'Yesterday'): Locator => notesPanel(page).locator(`h4:text-is("${day}") + ul > li`);
const dayLabels = (page: Page): Locator => notesPanel(page).locator('h4');

/** Signs the README account in and waits for the loaded page and the card. */
async function open(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  await expect(tabOf(page, 'Notes'), 'the card is drawn').toBeVisible();
}

/** Selects Your answers, which reads it again when another tab was selected, and waits for the selection. */
async function showAnswers(page: Page): Promise<void> {
  await tabOf(page, 'Your answers').click();
  await expect(tabOf(page, 'Your answers')).toHaveAttribute('aria-selected', 'true');
}

/** The next answer of a memory route that the page receives, with the method and status given. */
function answerOf(page: Page, route: RegExp, status: number, method = 'GET'): Promise<Response> {
  return page.waitForResponse((response) => route.test(response.url()) && response.request().method() === method && response.status() === status);
}

/**
 * Waits until the page has read the whole answer and has drawn what follows it (two frames), so that a check that something is absent runs
 * after the card handled the answer, not while the read was still out (a pending read and a failed one draw the same panel).
 */
async function handled(page: Page, answer: Promise<Response>): Promise<void> {
  await (await answer).finished();
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 0)))));
}

/** The focused element, by its aria-label, else its tag and id, else "body": a focus check that fails names where focus is. */
function focusedName(page: Page): Promise<string> {
  return page.evaluate(() => {
    const active = document.activeElement;
    if (active === null || active === document.body) return 'body';
    return active.getAttribute('aria-label') ?? `${active.tagName.toLowerCase()}#${active.id}`;
  });
}

/** The requests of the memory routes that the page sends, as "METHOD path". */
function watchMemory(page: Page): () => string[] {
  const seen: string[] = [];
  page.on('request', (request: Request) => {
    const url = new URL(request.url());
    if (url.pathname.startsWith(MEMORY)) seen.push(`${request.method()} ${url.pathname}${url.search}`);
  });
  return () => [...seen];
}

/** The lines of the notes route for a day, read with the page's own session. */
async function servedLines(page: Page, day: 'today' | 'yesterday'): Promise<string[]> {
  const response = await page.request.get(`${MEMORY}/notes?day=${day}`);
  expect(response.status(), await response.text()).toBe(200);
  return ((await response.json()) as { lines: string[] }).lines;
}

/** MC1: the section, its tabs and the Notes intro. */
test('MC1: the rail has eight headings with Memory between Heartbeat checklist and Persona, and the card shows the tabs Notes, Your answers, Pinned and All memories', async ({ page }) => {
  await open(page);
  const headings = railOf(page).getByRole('heading', { level: 3 });
  await expect(headings, 'eight sections, Telegram first and Persona last').toHaveCount(8);
  await expect(headings.nth(5), 'the Heartbeat checklist heading is sixth').toHaveAccessibleName('Heartbeat checklist');
  await expect(headings.nth(6), 'Memory follows it, with no count').toHaveAccessibleName('Memory');
  await expect(headings.nth(6).locator('[aria-hidden="true"]'), 'the Memory heading has no count').toHaveCount(0);
  await expect(headings.nth(7), 'and Persona is last').toHaveAccessibleName('Persona');
  await expect(card(page), 'the card is the body of the Memory section').toHaveCount(1);

  await expect(card(page).getByRole('tablist', { name: 'Memory', exact: true }), 'the tab list is named by the Memory heading').toHaveCount(1);
  const tabs = card(page).getByRole('tab');
  await expect(tabs, 'four tabs, in order').toHaveText(['Notes', 'Your answers', 'Pinned', 'All memories']);
  await expect(tabOf(page, 'Notes'), 'Notes is selected').toHaveAttribute('aria-selected', 'true');
  await expect(tabOf(page, 'Notes')).toHaveAttribute('tabindex', '0');
  await expect(tabOf(page, 'Your answers')).toHaveAttribute('aria-selected', 'false');
  await expect(tabOf(page, 'Your answers')).toHaveAttribute('tabindex', '-1');
  await expect(notesPanel(page), 'the Notes panel is named by its tab').toBeVisible();
  await expect(answersPanel(page), 'the Your answers panel is hidden').toHaveCount(0);
  await expect(pinnedPanel(page), 'so are the Pinned and All memories panels').toHaveCount(0);
  await expect(memoriesPanel(page)).toHaveCount(0);
  await expect(notesPanel(page).getByText(NOTES_INTRO, { exact: true }), 'the Notes intro, verbatim').toBeVisible();
  await expect(card(page).locator(REGION), 'the card adds no empty text, hint or live region').toHaveCount(0);
  await expect(card(page).getByRole('heading', { level: 3 }), 'and no h3 of its own').toHaveCount(0);
});

/**
 * MC2: two turns of today and two of yesterday, seeded latest first, show under their day in time order, which is the order the route serves.
 * They are seeded just after the local midnight, as the earliest lines of their day, which the note's cut (DailyNote MAXCHARS) never leaves
 * out, whatever the account recorded earlier in the run and whatever the hour.
 */
test('MC2: done turns of today and of yesterday show under Today and Yesterday, each day in served order', async ({ page }) => {
  const session = await sessionRef();
  const texts = {
    today: [unique('mc2 today a').replace(/ /g, 'Zz'), unique('mc2 today b').replace(/ /g, 'Zz')],
    yesterday: [unique('mc2 yesterday a').replace(/ /g, 'Zz'), unique('mc2 yesterday b').replace(/ /g, 'Zz')],
  };
  const turns: string[] = [];
  try {
    for (const [day, ago] of [['today', 0], ['yesterday', 1]] as const) {
      const [first, second] = texts[day] as [string, string];
      turns.push(await seedNoteTurn(session, second, await localTimeUtc(ago, '00:01:30')));
      turns.push(await seedNoteTurn(session, first, await localTimeUtc(ago, '00:00:30')));
    }
    await open(page);
    await expect(dayLabels(page), 'the labels Today and Yesterday').toHaveText(['Today', 'Yesterday']);
    for (const [day, label] of [['today', 'Today'], ['yesterday', 'Yesterday']] as const) {
      const [first, second] = texts[day] as [string, string];
      const other = day === 'today' ? texts.yesterday : texts.today;
      const mine = linesOf(page, label).filter({ hasText: new RegExp(`${first}|${second}`) });
      await expect(mine, `the two turns of ${day} are lines under ${label}, the earlier one first`).toHaveText([
        new RegExp(`^\\d{2}:\\d{2} message \\(web\\): ${first}$`),
        new RegExp(`^\\d{2}:\\d{2} message \\(web\\): ${second}$`),
      ]);
      await expect(linesOf(page, label).filter({ hasText: new RegExp(other.join('|')) }), `and the other day's turns are not under ${label}`).toHaveCount(0);
    }
    await expect(notesPanel(page).getByText(NOTES_EMPTY), 'a day with lines shows no empty text').toHaveCount(0);

    const today = await servedLines(page, 'today');
    const yesterday = await servedLines(page, 'yesterday');
    expect(today.some((line) => line.includes(texts.today[0] ?? '')), 'the route serves the turns of today').toBe(true);
    await expect(linesOf(page, 'Today'), "Today's lines are the route's, in its order").toHaveText(today);
    await expect(linesOf(page, 'Yesterday'), "Yesterday's lines are the route's, in its order").toHaveText(yesterday);
  } finally {
    for (const turn of turns) await removeNoteRows({ turn });
  }
});

/** MC3: the empty texts show only after a read that answered; a pending or failed read shows the intro only. */
test('MC3: the empty texts show after an answered read only, and a pending or failed read shows the intro and nothing else', async ({ page }) => {
  let release: () => void = () => undefined;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route(NOTES, async (route) => {
    await gate;
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    await route.fulfill({ response, json: { ...body, lines: [] } });
  });
  await page.route(PRECEDENTS, (route) => (route.request().method() === 'GET' ? route.fulfill({ json: { precedents: [] } }) : route.continue()));
  await open(page);
  await expect(notesPanel(page).getByText(NOTES_INTRO, { exact: true }), 'while the read is pending, the intro shows').toBeVisible();
  await expect(dayLabels(page), 'and no day label').toHaveCount(0);
  await expect(notesPanel(page).getByText(NOTES_EMPTY), 'and no empty text').toHaveCount(0);
  release();
  await expect(dayLabels(page), 'once both days answered, both labels show').toHaveText(['Today', 'Yesterday']);
  await expect(notesPanel(page).getByText(NOTES_EMPTY, { exact: true }), 'an empty today').toBeVisible();
  await expect(notesPanel(page).getByText(YESTERDAY_EMPTY, { exact: true }), 'an empty yesterday').toBeVisible();
  await showAnswers(page);
  await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true })).toBeVisible();
  await expect(answersPanel(page).getByText(ANSWERS_EMPTY, { exact: true }), 'no rows after an answered read').toBeVisible();
  await expect(card(page).locator(REGION), 'the empty texts are no .empty, .hint or live region of the rail').toHaveCount(0);

  await page.unrouteAll({ behavior: 'ignoreErrors' });
  await page.route(NOTES, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } }));
  await page.route(PRECEDENTS, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } }));
  const notesFailed = answerOf(page, NOTES, 500);
  await tabOf(page, 'Notes').click();
  await handled(page, notesFailed);
  await expect(notesPanel(page).getByText(NOTES_INTRO, { exact: true }), 'after a failed read, the intro shows').toBeVisible();
  await expect(dayLabels(page), 'with no day label').toHaveCount(0);
  await expect(notesPanel(page).getByText(NOTES_EMPTY), 'and no empty text').toHaveCount(0);
  await expect(notesPanel(page).getByText(YESTERDAY_EMPTY), 'nor the yesterday text').toHaveCount(0);
  const answersFailed = answerOf(page, PRECEDENTS, 500);
  await showAnswers(page);
  await handled(page, answersFailed);
  await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true }), 'a failed list shows the intro').toBeVisible();
  await expect(answersPanel(page).getByText(ANSWERS_EMPTY), 'and no empty text').toHaveCount(0);

  const retried = unique('mc3 retried');
  const row = { ref: 'zz-mc3-retried', answeredAt: '2031-04-01T10:00:00Z', channel: 'mailbox', answeredChannel: 'web', summary: retried, outcome: 'tellnow', answer: 'noise' };
  await page.unrouteAll({ behavior: 'ignoreErrors' });
  await page.route(PRECEDENTS, (route) => (route.request().method() === 'GET' ? route.fulfill({ json: { precedents: [row] } }) : route.continue()));
  await tabOf(page, 'Notes').click();
  await expect(dayLabels(page), 'selecting the tab again reads it again').toHaveText(['Today', 'Yesterday']);
  await showAnswers(page);
  await expect(rowOf(page, retried), 'a list whose read failed is read again when its tab is next selected').toHaveCount(1);
  await expect(answersPanel(page).getByText(ANSWERS_EMPTY), 'and shows no empty text').toHaveCount(0);
});

/** MC10: a line that the notes route serves is one list item, as served, the cut mark "(more not shown)" included. */
test('MC10: the Notes panel shows each served line as it was served, including the cut mark', async ({ page }) => {
  const lines = ['09:15 message (web): Zz mc10 first', '09:20 message (web): Zz mc10 second', '(more not shown)'];
  await page.route(NOTES, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    const yesterday = new URL(route.request().url()).searchParams.get('day') === 'yesterday';
    await route.fulfill({ response, json: { ...body, lines: yesterday ? [] : lines } });
  });
  await open(page);
  await expect(linesOf(page, 'Today'), "Today's list items are the served lines, the cut mark last").toHaveText(lines);
  await expect(notesPanel(page).getByText(YESTERDAY_EMPTY, { exact: true }), "and an empty Yesterday keeps its own text").toBeVisible();
});

/** The three rows that MC4 to MC6 and MC8 seed: a noise row, an approval row and a tool row of the session. */
interface Seeded {
  noise: { ref: string; summary: string };
  approval: { ref: string; summary: string };
  tool: { ref: string; summary: string };
}

async function seedThree(session: string, label: string): Promise<Seeded> {
  const noise = unique(`${label} noise`);
  const approval = unique(`${label} approval`);
  const tool = unique(`${label} tool`);
  const refs: Seeded = {
    noise: { ref: '', summary: noise },
    approval: { ref: '', summary: approval },
    tool: { ref: '', summary: tool },
  };
  try {
    refs.noise.ref = await seedPrecedent(session, { channel: 'mailbox', outcome: 'tellnow', answer: 'noise', answeredAt: '2031-01-03T10:00:00Z', summary: noise, matchKey: `zz.${label}@example.com` });
    refs.approval.ref = await seedPrecedent(session, { channel: 'system', outcome: '', answer: 'approved', answeredAt: '2031-01-02T11:30:00Z', answeredChannel: 'web', summary: approval, matchKey: `production:zz/${label}` });
    refs.tool.ref = await seedPrecedent(session, { channel: '', outcome: '', answer: 'rejected', answeredAt: '2031-01-01T14:15:00Z', answeredChannel: 'web', summary: tool, matchKey: `tool:zz_${label}` });
  } catch (error) {
    await removeAll(refs);
    throw error;
  }
  return refs;
}

async function removeAll(rows: Seeded): Promise<void> {
  for (const one of [rows.noise, rows.approval, rows.tool]) if (one.ref) await removePrecedent(one.ref);
}

/** MC4: the rows, the dialog and the delete. */
test('MC4: Your answers lists the rows with their meta lines and the tool note, and Forget asks, Esc cancels and the confirm sends one DELETE', async ({ page }) => {
  const session = await sessionRef();
  const rows = await seedThree(session, 'mc4');
  try {
    const memory = watchMemory(page);
    await open(page);
    await showAnswers(page);
    await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true }), 'the intro').toBeVisible();

    await expect(metaOf(rowOf(page, rows.noise.summary)), 'the noise row: when, channel as served, answer word').toHaveText(['Jan 3, 2031 at 10:00', 'mailbox', 'This was noise']);
    await expect(metaOf(rowOf(page, rows.approval.summary)), 'the approval row').toHaveText(['Jan 2, 2031 at 11:30', 'system', 'Approved']);
    await expect(metaOf(rowOf(page, rows.tool.summary)), 'the tool row has no channel').toHaveText(['Jan 1, 2031 at 14:15', 'Rejected']);
    await expect(rowOf(page, rows.noise.summary).locator('.meta > span[aria-hidden="true"]'), 'three parts are joined by two rail separators (a middle dot)').toHaveText(['\u00b7', '\u00b7']);
    await expect(rowOf(page, rows.tool.summary).locator('.meta > span[aria-hidden="true"]'), 'and two parts by one').toHaveText(['\u00b7']);
    await expect(rowOf(page, rows.noise.summary).locator('.title'), 'the title is the summary').toHaveText(rows.noise.summary);
    await expect(rowOf(page, rows.tool.summary).getByText(TOOL_NOTE, { exact: true }), 'the tool row carries the tool note').toBeVisible();
    await expect(rowOf(page, rows.noise.summary).locator('.detail'), 'and a row of a channel has none').toHaveCount(0);
    await expect(rowOf(page, rows.approval.summary).locator('.detail')).toHaveCount(0);
    await expect(forgetOf(page, rows.noise.summary), 'Forget shows the word Forget').toHaveText('Forget');
    await expect(forgetOf(page, rows.tool.summary), 'a tool row is forgettable').toBeVisible();
    const order = await answersPanel(page).locator('li.row .title').allTextContents();
    expect(order.filter((title) => [rows.noise.summary, rows.approval.summary, rows.tool.summary].includes(title)), 'in served order, newest first').toEqual([
      rows.noise.summary,
      rows.approval.summary,
      rows.tool.summary,
    ]);

    await forgetOf(page, rows.noise.summary).click();
    await expect(dialogOf(page), 'Forget opens the dialog named by the question').toBeVisible();
    await expect(dialogOf(page).getByRole('heading', { name: QUESTION, exact: true }), 'focus starts on the question').toBeFocused();
    await page.keyboard.press('Escape');
    await expect(dialogOf(page), 'Esc closes it').toHaveCount(0);
    await expect(forgetOf(page, rows.noise.summary), 'and focus returns to Forget').toBeFocused();
    expect(memory().filter((one) => one.startsWith('DELETE')), 'nothing was sent').toEqual([]);
    expect(await precedentExists(rows.noise.ref)).toBe(1);

    await forgetOf(page, rows.noise.summary).click();
    await cancelOf(page).click();
    await expect(dialogOf(page), 'Cancel closes it').toHaveCount(0);
    await expect(forgetOf(page, rows.noise.summary), 'and focus returns to Forget').toBeFocused();
    expect(memory().filter((one) => one.startsWith('DELETE')), 'nothing was sent').toEqual([]);

    await forgetOf(page, rows.noise.summary).click();
    await expect(dialogOf(page)).toBeVisible();
    await page.locator('.cdk-overlay-backdrop').click({ position: { x: 4, y: 4 } });
    await expect(dialogOf(page), 'a press on the backdrop closes it').toHaveCount(0);
    await expect(forgetOf(page, rows.noise.summary), 'and focus returns to Forget').toBeFocused();
    expect(memory().filter((one) => one.startsWith('DELETE')), 'nothing was sent').toEqual([]);
    expect(await precedentExists(rows.noise.ref), 'and the row is still in the table').toBe(1);

    await forgetOf(page, rows.noise.summary).click();
    const before = memory().length;
    const deleted = page.waitForResponse((response) => response.request().method() === 'DELETE' && FORGET_ONE.test(new URL(response.url()).pathname));
    await confirmOf(page).click();
    expect((await deleted).status(), 'the confirm is answered 200').toBe(200);
    await expect(dialogOf(page), 'the dialog closes').toHaveCount(0);
    await expect(rowOf(page, rows.noise.summary), 'and the row leaves at once').toHaveCount(0);
    await expect(headingOf(page), 'focus goes to the Memory heading').toBeFocused();
    expect(memory().slice(before), 'one DELETE to the row\'s address, and no re-read').toEqual([`DELETE ${MEMORY}/precedents/${rows.noise.ref}`]);
    expect(await precedentExists(rows.noise.ref), 'the table row is gone').toBe(0);
    await expect(rowOf(page, rows.approval.summary), 'the other rows stay').toHaveCount(1);

    await page.reload();
    await showAnswers(page);
    await expect(rowOf(page, rows.approval.summary), 'after a reload the others are still listed').toHaveCount(1);
    await expect(rowOf(page, rows.noise.summary), 'and the forgotten one is not').toHaveCount(0);
  } finally {
    await removeAll(rows);
  }
});

/** MC5: a failed confirm (500, 501, no answer at all) and a 404. */
test('MC5: a failed confirm keeps the dialog open with the notice and the row, and a 404 removes the row', async ({ page }) => {
  const session = await sessionRef();
  const summary = unique('mc5');
  const ref = await seedPrecedent(session, { summary, answeredAt: '2031-02-01T10:00:00Z', matchKey: 'zz.mc5@example.com' });
  try {
    let answer: 'fail' | 'unimplemented' | 'offline' | 'gone' = 'fail';
    let sent = 0;
    await page.route(FORGET_ONE, (route) => {
      if (route.request().method() !== 'DELETE') return route.continue();
      sent += 1;
      switch (answer) {
        case 'fail':
          return route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The forget failed.' } } });
        case 'unimplemented':
          return route.fulfill({ status: 501, json: { error: { code: 'not_implemented', message: 'zz Not available.' } } });
        case 'offline':
          return route.abort('connectionreset');
        case 'gone':
          return route.fulfill({ status: 404, json: { error: { code: 'not_found', message: 'OcuTalon has nothing at this address.' } } });
      }
    });
    await open(page);
    await showAnswers(page);
    await forgetOf(page, summary).click();
    let attempts = 0;
    for (const [how, kind] of [['fail', 'a 500'], ['unimplemented', 'a 501'], ['offline', 'a network error']] as const) {
      answer = how;
      await confirmOf(page).click();
      attempts += 1;
      await expect.poll(() => sent, `${kind}: the confirm sent its delete`).toBe(attempts);
      await expect(dialogOf(page).getByText(FAILED, { exact: true }), `${kind} shows the failure notice in the dialog`).toBeVisible();
      await expect(dialogOf(page), 'and the dialog stays open').toBeVisible();
      await expect(rowBehind(page, summary), 'and the row stays').toHaveCount(1);
      expect(await precedentExists(ref), 'and so does the table row').toBe(1);
    }
    answer = 'gone';
    await confirmOf(page).click();
    await expect(dialogOf(page), 'a 404 closes the dialog').toHaveCount(0);
    await expect(rowOf(page, summary), 'and the row leaves').toHaveCount(0);
    await expect(headingOf(page), 'with focus on the Memory heading').toBeFocused();
  } finally {
    await removePrecedent(ref);
  }
});

/** MC6: by keyboard alone. */
test('MC6: the tabs, Forget and the dialog work by keyboard alone', async ({ page }) => {
  const session = await sessionRef();
  const summary = unique('mc6');
  const ref = await seedPrecedent(session, { summary, answeredAt: '2032-01-01T10:00:00Z', matchKey: 'zz.mc6@example.com' });
  try {
    await open(page);
    await headingOf(page).focus();
    await page.keyboard.press('Tab');
    await expect(tabOf(page, 'Notes'), 'Tab reaches the selected tab').toBeFocused();
    await page.keyboard.press('ArrowRight');
    await expect(tabOf(page, 'Your answers'), 'ArrowRight focuses the next tab').toBeFocused();
    await expect(tabOf(page, 'Your answers'), 'and selects it').toHaveAttribute('aria-selected', 'true');
    await expect(tabOf(page, 'Your answers'), 'the roving tabindex follows the selection').toHaveAttribute('tabindex', '0');
    await expect(tabOf(page, 'Notes')).toHaveAttribute('aria-selected', 'false');
    await expect(tabOf(page, 'Notes')).toHaveAttribute('tabindex', '-1');
    await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true }), 'the panel changes').toBeVisible();
    await expect(notesPanel(page), 'and the Notes panel is hidden').toHaveCount(0);
    await expect(forgetOf(page, summary), 'the read that selecting it made is drawn').toBeVisible();
    await page.keyboard.press('ArrowRight');
    await expect(tabOf(page, 'Pinned'), 'ArrowRight moves on to Pinned').toBeFocused();
    const reread = answerOf(page, PRECEDENTS, 200);
    await page.keyboard.press('ArrowLeft');
    await expect(tabOf(page, 'Your answers'), 'ArrowLeft moves back').toBeFocused();
    await expect(tabOf(page, 'Your answers')).toHaveAttribute('aria-selected', 'true');
    await handled(page, reread);
    await expect(answersPanel(page).getByRole('button', { name: /^Forget / }).first(), 'the newest row is the first Forget').toHaveAccessibleName(`Forget ${summary}`);
    await expect(tabOf(page, 'Your answers'), 'and focus is still on the tab').toBeFocused();

    await page.keyboard.press('Tab');
    await expect.poll(() => focusedName(page), { message: 'Tab reaches Forget' }).toBe(`Forget ${summary}`);
    await expect(forgetOf(page, summary)).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(dialogOf(page).getByRole('heading', { name: QUESTION, exact: true }), 'Enter opens the dialog with focus on its question').toBeFocused();
    await page.keyboard.press('Tab');
    await expect(cancelOf(page), 'Tab reaches Cancel').toBeFocused();
    await page.keyboard.press('Tab');
    await expect(confirmOf(page), 'and the confirm').toBeFocused();
    await page.keyboard.press('Enter');
    await expect(dialogOf(page), 'Enter on the confirm forgets').toHaveCount(0);
    await expect(rowOf(page, summary)).toHaveCount(0);
    await expect(headingOf(page)).toBeFocused();
    expect(await precedentExists(ref)).toBe(0);
  } finally {
    await removePrecedent(ref);
  }
});

/** MC7: the drawer band. */
test('MC7: in the drawer band Forget opens its dialog over the page, and Cancel and Esc return focus to Forget with the drawer open', async ({ page }) => {
  const session = await sessionRef();
  const summary = unique('mc7');
  const ref = await seedPrecedent(session, { summary, answeredAt: '2032-02-01T10:00:00Z', matchKey: 'zz.mc7@example.com' });
  try {
    await open(page);
    await page.setViewportSize({ width: 1100, height: 800 });
    const status = page.locator('button.status-button');
    await status.click();
    await expect(status, 'the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await showAnswers(page);
    await forgetOf(page, summary).click();
    await expect(dialogOf(page), 'the dialog opens').toBeVisible();
    await cancelOf(page).click();
    await expect(dialogOf(page)).toHaveCount(0);
    await expect(forgetOf(page, summary), 'Cancel returns focus to Forget').toBeFocused();
    await expect(status, 'and the drawer is still open').toHaveAttribute('aria-expanded', 'true');
    await forgetOf(page, summary).click();
    await expect(dialogOf(page)).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(dialogOf(page)).toHaveCount(0);
    await expect(forgetOf(page, summary), 'Esc returns focus to Forget').toBeFocused();
    await expect(status, 'and the drawer is still open').toHaveAttribute('aria-expanded', 'true');
    expect(await precedentExists(ref), 'nothing was forgotten').toBe(1);
  } finally {
    await removePrecedent(ref);
  }
});

/** MC8: another session's rows and a seeded row never show, and the card keeps nothing across loads. */
test("MC8: the card lists only the session's own rows and notes, and keeps nothing across page loads", async ({ page }) => {
  const session = await sessionRef();
  const key = 'zz.mc8@example.com';
  const own = unique('mc8 own');
  const foreign = unique('mc8 foreign');
  const evaluated = unique('mc8 eval');
  const ownText = unique('mc8 own turn').replace(/ /g, 'Zz');
  const foreignText = unique('mc8 foreign turn').replace(/ /g, 'Zz');
  const rows: string[] = [];
  const turns: string[] = [];
  let other = '';
  try {
    other = await seedOtherSession(`zzmc8${Date.now().toString(36)}`);
    rows.push(await seedPrecedent(session, { summary: own, matchKey: key, answeredAt: '2032-03-01T10:00:00Z' }));
    rows.push(await seedPrecedent(other, { summary: foreign, matchKey: key, answeredAt: '2032-03-02T10:00:00Z' }));
    rows.push(await seedPrecedent('eval', { summary: evaluated, matchKey: key, answeredAt: '2032-03-03T10:00:00Z', run: `zzmc8${Date.now()}`.slice(0, 22) }));
    turns.push(await seedNoteTurn(session, ownText, await localTimeUtc(0, '00:02:30')));
    turns.push(await seedNoteTurn(other, foreignText));
    await open(page);
    await expect(linesOf(page, 'Today').filter({ hasText: ownText }), 'the session\'s own line shows').toHaveCount(1);
    await expect(notesPanel(page).getByText(foreignText), "another session's line does not").toHaveCount(0);
    await showAnswers(page);
    await expect(rowOf(page, own), 'its own row is listed').toHaveCount(1);
    await expect(answersPanel(page).getByText(foreign), "another session's row is not").toHaveCount(0);
    await expect(answersPanel(page).getByText(evaluated), 'and no seeded row').toHaveCount(0);

    await removePrecedent(rows[0] ?? '');
    await removeNoteRows({ turn: turns[0] ?? '' });
    let release: () => void = () => undefined;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    await page.route(PRECEDENTS, async (route) => {
      await gate;
      await route.continue().catch(() => undefined);
    });
    await page.reload();
    await expect(tabOf(page, 'Notes')).toBeVisible();
    await showAnswers(page);
    await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true }), 'while the read is out, the panel shows the intro').toBeVisible();
    await expect(answersPanel(page).locator('li.row'), 'and no row: nothing is kept from the page before the reload').toHaveCount(0);
    const held = answerOf(page, PRECEDENTS, 200);
    release();
    await handled(page, held);
    await tabOf(page, 'Notes').click();
    await expect(dayLabels(page), 'after the reload the notes are read again').toHaveText(['Today', 'Yesterday']);
    await expect(notesPanel(page).getByText(ownText), 'the removed turn does not show').toHaveCount(0);
    const listed = answerOf(page, PRECEDENTS, 200);
    await showAnswers(page);
    await handled(page, listed);
    await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true })).toBeVisible();
    await expect(answersPanel(page).getByText(own), 'the removed row does not show').toHaveCount(0);
    await expect(answersPanel(page).getByText(foreign)).toHaveCount(0);
    await expect(answersPanel(page).getByText(evaluated)).toHaveCount(0);
  } finally {
    for (const ref of rows) await removePrecedent(ref);
    for (const turn of turns) await removeNoteRows({ turn });
    if (other) await cleanFixtureRows([other]);
  }
});

/**
 * MC9: Integration. The card over the real routes and the real Decide over the precedent table, with the CI mock as the model. The describe block
 * points the runners at the CI mock and puts them back (HC4's pattern), and waits for the status monitor's noModelKey event of the restored keys.
 */
test.describe('MC9 (Integration)', () => {
  test.beforeAll(async () => {
    test.setTimeout(240_000);
    await pointKeys();
    const ready = await runnersReady();
    expect(ready.reason, `the production is ready (${ready.output})`).toBe('');
    expect(ready.keyed, 'and the TriageAgent has its key').toBe('1');
  });

  test.afterAll(async () => {
    test.setTimeout(240_000);
    const mark = await instanceSeq();
    try {
      await restoreKeys();
    } finally {
      const recorded = await runnersRecorded();
      expect(recorded.records, `the runners recorded the restored keys (${recorded.output})`).toBe('1');
      await monitorSettled(mark);
    }
  });

  test('MC9: after Forget, the next decide request for the same sender no longer carries the precedent', async ({ page }) => {
    test.setTimeout(240_000);
    const session = await sessionRef();
    const n = `${Date.now()}`;
    const address = `zz.memcard.${n}@example.com`;
    const sender = `Zz Card <${address}>`;
    const summary = unique('mc9');
    const since = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    const items: string[] = [];
    let ref = '';
    try {
      ref = await seedPrecedent(session, { channel: 'mailbox', matchKey: address, summary, outcome: 'tellnow', answer: 'noise', answeredAt: since });
      await open(page);
      await showAnswers(page);
      await expect(rowOf(page, summary), 'the card lists the precedent').toHaveCount(1);

      const markerA = `memory-precedent:${n}a`;
      const markA = await logMark();
      const itemA = await sendItem(README_ACCOUNT.user, { sender, subject: 'Invoice', text: `[[mock:${markerA}]] Zz card a` });
      items.push(itemA);
      expect(await waitDecideRef(itemA), 'Decide recorded the decision of the first email').not.toBe('');
      const control = await triageRequests(markA, markerA, summary);
      expect(control.count, 'a Triage request of the first email was logged').toBeGreaterThan(0);
      expect(control.withOpening, 'control: it carries the precedents opening').toBe(control.count);
      expect(control.withText, "and the row's summary").toBe(control.count);

      await forgetOf(page, summary).click();
      const deleted = page.waitForResponse((response) => response.request().method() === 'DELETE' && FORGET_ONE.test(new URL(response.url()).pathname));
      await confirmOf(page).click();
      expect((await deleted).status()).toBe(200);
      await expect(rowOf(page, summary), 'Forget removes the row').toHaveCount(0);
      expect(await precedentExists(ref), 'and the table row').toBe(0);

      const markerB = `memory-precedent:${n}b`;
      const markB = await logMark();
      const itemB = await sendItem(README_ACCOUNT.user, { sender, subject: 'Invoice', text: `[[mock:${markerB}]] Zz card b` });
      items.push(itemB);
      expect(await waitDecideRef(itemB), 'Decide recorded the decision of the second email').not.toBe('');
      const after = await triageRequests(markB, markerB, summary);
      expect(after.count, 'a Triage request of the second email was logged').toBeGreaterThan(0);
      expect(after.withOpening, 'it carries no precedents opening').toBe(0);
      expect(after.withText, "and not the row's summary").toBe(0);
    } finally {
      if (ref) await removePrecedent(ref);
      await removeDecisionsOf(items);
      await dropPhone(README_ACCOUNT.user, since);
    }
  });
});

// --- Story 41.13: the tabs Pinned and All memories, as the unprivileged LIVE fixture user ---

const ITEMS = /\/api\/v1\/memory\/items(\?|$)/;
const ITEM_FORGET = /\/api\/v1\/memory\/items\/[^/?]+$/;
const PINNED = /\/api\/v1\/memory\/pinned$/;
const PINNED_INTRO = 'Pinned facts are read at the start of each conversation.';
const PINNED_EMPTY = 'Nothing pinned yet. Pin a memory from All memories.';
const MEMORIES_EMPTY = 'No memories yet. Say "Remember that ..." in the chat.';
const NO_MATCH = 'No memories match.';
const SEARCH_BUSY = 'Search is busy right now. Try again in a moment.';
const OVER_CAP = 'That would go over the 1,000-token limit. Unpin something first.';
const MEMORY_QUESTION = 'Forget this memory? OcuTalon will stop using it.';
const DEMO_RULE = 'On the online demo, your memories and pins belong to this visit';

const searchBox = (page: Page): Locator => memoriesPanel(page).getByRole('searchbox', { name: 'Search your memories', exact: true });
const searchButton = (page: Page): Locator => memoriesPanel(page).getByRole('button', { name: 'Search', exact: true });
/** The row of a memory in a panel, found by its text, which is the row's title. */
const memoryRow = (panel: Locator, text: string): Locator => panel.locator('li.row').filter({ has: panel.page().locator('.title', { hasText: text }) });
const memoryDialog = (page: Page): Locator => page.getByRole('dialog', { name: MEMORY_QUESTION, exact: true });
/** The tokens a block of single-line pins uses, worked out here: the opening is 36 characters, each pin adds 3 and its length, and the closing blank line adds 2. */
const tokensOf = (lengths: number[]): number => Math.ceil((36 + lengths.reduce((sum, length) => sum + 3 + length, 0) + 2) / 4);

/** Signs the LIVE fixture user in (role OcuTalonUser only) and waits for the card; answers the user's session Ref and checks that it holds no pin. */
async function openLive(page: Page): Promise<string> {
  const live = fixtureUser('LIVE');
  await loadedAfter(page, () => signIn(page, live.user, live.password));
  await expect(tabOf(page, 'Notes'), 'the card is drawn').toBeVisible();
  const session = await sessionRefOfUser(live.user);
  expect(await pinnedCountOf(session), 'the LIVE session holds no pinned memory before the case').toBe(0);
  return session;
}

/** Selects All memories and waits for the list that selecting it reads. */
async function showMemories(page: Page): Promise<void> {
  const listed = answerOf(page, ITEMS, 200);
  await tabOf(page, 'All memories').click();
  await expect(tabOf(page, 'All memories')).toHaveAttribute('aria-selected', 'true');
  await handled(page, listed);
}

/** Selects Pinned and waits for the read that selecting it makes. */
async function showPinned(page: Page): Promise<void> {
  const read = answerOf(page, PINNED, 200);
  await tabOf(page, 'Pinned').click();
  await expect(tabOf(page, 'Pinned')).toHaveAttribute('aria-selected', 'true');
  await handled(page, read);
}

/** Removes the memories of a case, if they are there. */
async function removeAllMemories(refs: string[]): Promise<void> {
  for (const ref of refs) await removeMemory(ref);
}

/** MC11: the four tabs, their roles and the arrow keys. */
test('MC11: the card has the tabs Notes, Your answers, Pinned and All memories in order, and the arrows cycle all four', async ({ page }) => {
  await openLive(page);
  await expect(card(page).getByRole('tablist', { name: 'Memory', exact: true }), 'the tab list is named by the Memory heading').toHaveCount(1);
  await expect(card(page).getByRole('tab'), 'four tabs, in order').toHaveText(['Notes', 'Your answers', 'Pinned', 'All memories']);
  await expect(tabOf(page, 'Notes'), 'Notes is selected at first').toHaveAttribute('aria-selected', 'true');
  for (const name of ['Your answers', 'Pinned', 'All memories'] as const) {
    await expect(tabOf(page, name)).toHaveAttribute('aria-selected', 'false');
    await expect(tabOf(page, name)).toHaveAttribute('tabindex', '-1');
  }

  await tabOf(page, 'Notes').focus();
  for (const name of ['Your answers', 'Pinned', 'All memories', 'Notes'] as const) {
    await page.keyboard.press('ArrowRight');
    await expect(tabOf(page, name), `ArrowRight focuses ${name}`).toBeFocused();
    await expect(tabOf(page, name), 'and selects it').toHaveAttribute('aria-selected', 'true');
    await expect(tabOf(page, name), 'the roving tabindex follows').toHaveAttribute('tabindex', '0');
  }
  for (const name of ['All memories', 'Pinned', 'Your answers', 'Notes'] as const) {
    await page.keyboard.press('ArrowLeft');
    await expect(tabOf(page, name), `ArrowLeft focuses ${name}`).toBeFocused();
    await expect(tabOf(page, name)).toHaveAttribute('aria-selected', 'true');
  }
  await expect(pinnedPanel(page), 'the Pinned panel is hidden while Notes is selected').toHaveCount(0);
  await tabOf(page, 'Pinned').click();
  await expect(pinnedPanel(page).getByText(PINNED_INTRO, { exact: true }), 'the Pinned panel is named by its tab and opens with its intro').toBeVisible();
  await tabOf(page, 'All memories').click();
  await expect(memoriesPanel(page).getByText('Search your memories', { exact: true }), 'the All memories panel opens with its search label').toBeVisible();
});

/** MC12: the list, the chips, and a search that runs only on submit. */
test('MC12: All memories lists a told and a learned row with their chips, searches only on Enter, and says when nothing matches', async ({ page }) => {
  test.setTimeout(150_000);
  const stamp = Date.now().toString(36);
  const toldText = `The zzquokka${stamp} gateway is quokka.example.test`;
  const learnedText = `The zzwombat${stamp} desk is on floor nine`;
  const refs: string[] = [];
  try {
    const session = await openLive(page);
    refs.push(await seedMemory(session, toldText));
    const learned = await seedMemory(session, learnedText);
    refs.push(learned);
    await setMemorySource(learned, 'learned');
    const memory = watchMemory(page);
    await showMemories(page);
    await expect(memoryRow(memoriesPanel(page), toldText).locator('.chip'), 'the told row carries the chip Told').toHaveText('Told');
    await expect(memoryRow(memoriesPanel(page), learnedText).locator('.chip'), 'the learned row carries the chip Learned').toHaveText('Learned');
    await expect(memoryRow(memoriesPanel(page), toldText).getByRole('button', { name: `Pin ${toldText}`, exact: true }), 'Pin is named by the text').toBeVisible();
    await expect(memoryRow(memoriesPanel(page), toldText).getByRole('button', { name: `Forget ${toldText}`, exact: true }), 'and so is Forget').toBeVisible();

    await searchBox(page).pressSequentially(`zzquokka${stamp}`);
    await page.waitForTimeout(800);
    expect(
      memory().filter((one) => one.includes('/items?q=')),
      'typing sends no search',
    ).toEqual([]);

    let status = 0;
    for (let attempt = 0; attempt < 3 && status !== 200; attempt += 1) {
      const answered = page.waitForResponse((response) => ITEMS.test(response.url()) && response.url().includes('q='));
      await searchBox(page).press('Enter');
      status = (await answered).status();
    }
    expect(status, 'Enter sends one search, and it was answered').toBe(200);
    expect(memory().filter((one) => one.includes(`/items?q=zzquokka${stamp}`)).length, 'the search names the typed text').toBeGreaterThanOrEqual(1);
    await expect(memoryRow(memoriesPanel(page), toldText), 'the match is listed').toHaveCount(1);
    await expect(memoriesPanel(page).getByText(NO_MATCH), 'with no empty text').toHaveCount(0);

    await page.route(/\/api\/v1\/memory\/items\?q=zznothing/, (route) => route.fulfill({ json: { items: [], total: 0 } }));
    await searchBox(page).fill('zznothing');
    await searchBox(page).press('Enter');
    await expect(memoriesPanel(page).getByText(NO_MATCH, { exact: true }), 'a search that finds nothing says so').toBeVisible();
    await expect(memoriesPanel(page).getByText(MEMORIES_EMPTY), 'and not the empty-list text').toHaveCount(0);

    const newest = answerOf(page, ITEMS, 200);
    await searchBox(page).fill('   ');
    await searchButton(page).click();
    await handled(page, newest);
    await expect(memoryRow(memoriesPanel(page), toldText), 'a blank submit shows the newest list again').toHaveCount(1);
    await expect(memoryRow(memoriesPanel(page), learnedText)).toHaveCount(1);
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC13: Pin, the Pinned tab with its figure, and Unpin. */
test('MC13: Pin moves a row to Pinned with the figure the server counted, and Unpin takes it off and reads the figure again', async ({ page }) => {
  const text = `The zzpin${Date.now().toString(36)} number is 4242`;
  const refs: string[] = [];
  try {
    const session = await openLive(page);
    refs.push(await seedMemory(session, text));
    await showMemories(page);
    const pin = memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Pin ${text}`, exact: true });
    await pin.click();
    const unpin = memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Unpin ${text}`, exact: true });
    await expect(unpin, 'the same button now says Unpin').toBeVisible();
    await expect(unpin, 'and keeps focus').toBeFocused();
    expect(await pinnedCountOf(session), 'the memory is pinned in the table').toBe(1);

    await showPinned(page);
    await expect(pinnedPanel(page).getByText(PINNED_INTRO, { exact: true })).toBeVisible();
    await expect(pinnedPanel(page).getByText(`${tokensOf([text.length])} of 1,000 tokens (estimated).`, { exact: true }), 'the figure is worked out here from the text').toBeVisible();
    await expect(memoryRow(pinnedPanel(page), text).locator('.chip'), 'the pinned row has its chip').toHaveText('Told');
    await expect(pinnedPanel(page).getByText(PINNED_EMPTY), 'and the panel is not empty').toHaveCount(0);

    await memoryRow(pinnedPanel(page), text).getByRole('button', { name: `Unpin ${text}`, exact: true }).click();
    await expect(memoryRow(pinnedPanel(page), text), 'Unpin takes the row off Pinned').toHaveCount(0);
    await expect(pinnedPanel(page).getByText('0 of 1,000 tokens (estimated).', { exact: true }), 'and the figure is read again').toBeVisible();
    await expect(pinnedPanel(page).getByText(PINNED_EMPTY, { exact: true })).toBeVisible();
    await expect(headingOf(page), 'focus goes to the Memory heading').toBeFocused();
    expect(await pinnedCountOf(session), 'the table holds no pin').toBe(0);

    await showMemories(page);
    await expect(memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Pin ${text}`, exact: true }), 'All memories shows it unpinned again').toBeVisible();
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC14: the refused pin. */
test('MC14: a pin that would go over the cap shows the refusal, announced and named in the button\'s description, and the row stays unpinned', async ({ page }) => {
  test.setTimeout(150_000);
  const refs: string[] = [];
  try {
    await recordAnnouncements(page);
    const session = await openLive(page);
    const big = await seedMemory(session, 'a'.repeat(2000));
    const mid = await seedMemory(session, 'b'.repeat(1956));
    const short = await seedMemory(session, 'cc');
    refs.push(big, mid, short);
    for (const ref of [big, mid]) {
      const pinned = await page.request.fetch(`${MEMORY}/${ref}/pin`, { method: 'POST', headers: envelope() });
      expect(pinned.status(), await pinned.text()).toBe(200);
    }
    expect(await pinnedCountOf(session), 'two memories are pinned: the block is exactly 4,000 characters').toBe(2);

    await showMemories(page);
    const row = memoriesPanel(page).locator('li.row').filter({ has: page.locator('.title', { hasText: /^cc$/ }) });
    const pin = row.getByRole('button', { name: 'Pin cc', exact: true });
    await pin.click();
    await expect(memoriesPanel(page).getByText(OVER_CAP, { exact: true }), 'the refusal shows').toBeVisible();
    await expect(pin, 'the button is described by it').toHaveAccessibleDescription(OVER_CAP);
    await expect(row.getByRole('button', { name: 'Pin cc', exact: true }), 'the row stays unpinned').toBeVisible();
    await expect.poll(() => announcements(page, OVER_CAP), { message: 'it is announced once' }).toBe(1);
    await page.waitForTimeout(1000);
    expect(await announcements(page, OVER_CAP), 'and only once').toBe(1);
    expect(await pinnedCountOf(session), 'and nothing was pinned or unpinned').toBe(2);
    await showPinned(page);
    await expect(pinnedPanel(page).getByText(`1,000 of 1,000 tokens (estimated).`, { exact: true }), 'the figure is the cap: 1,000 of 1,000').toBeVisible();
    await expect(pinnedPanel(page).locator('li.row'), 'two pins').toHaveCount(2);
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC15: Forget, in both lists. */
test('MC15: Forget asks, then the memory leaves All memories and Pinned at once, and a search no longer finds it', async ({ page }) => {
  test.setTimeout(150_000);
  const stamp = Date.now().toString(36);
  const text = `The zzforget${stamp} contact is Lee`;
  const refs: string[] = [];
  try {
    const session = await openLive(page);
    const ref = await seedMemory(session, text);
    refs.push(ref);
    const pinned = await page.request.fetch(`${MEMORY}/${ref}/pin`, { method: 'POST', headers: envelope() });
    expect(pinned.status(), await pinned.text()).toBe(200);
    await showPinned(page);
    await expect(memoryRow(pinnedPanel(page), text), 'the memory is on Pinned').toHaveCount(1);
    await showMemories(page);
    const forget = memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Forget ${text}`, exact: true });
    await forget.click();
    await expect(memoryDialog(page), 'Forget asks').toBeVisible();
    await expect(memoryDialog(page).getByRole('heading', { name: MEMORY_QUESTION, exact: true }), 'with focus on the question').toBeFocused();
    await page.keyboard.press('Escape');
    await expect(memoryDialog(page)).toHaveCount(0);
    await expect(forget, 'Esc gives focus back to Forget').toBeFocused();
    expect(await memoryExists(ref), 'and nothing was forgotten').toBe(1);

    await forget.click();
    const deleted = page.waitForResponse((response) => response.request().method() === 'DELETE' && ITEM_FORGET.test(new URL(response.url()).pathname));
    await memoryDialog(page).getByRole('button', { name: 'Forget', exact: true }).click();
    expect((await deleted).status(), 'the confirm is answered 200').toBe(200);
    await expect(memoryDialog(page)).toHaveCount(0);
    await expect(memoryRow(memoriesPanel(page), text), 'the row leaves All memories').toHaveCount(0);
    await expect(headingOf(page), 'focus goes to the Memory heading').toBeFocused();
    expect(await memoryExists(ref), 'the table row is gone').toBe(0);
    await showPinned(page);
    await expect(memoryRow(pinnedPanel(page), text), 'and it leaves Pinned').toHaveCount(0);
    await expect(pinnedPanel(page).getByText('0 of 1,000 tokens (estimated).', { exact: true }), 'with the figure read again').toBeVisible();

    await showMemories(page);
    let status = 0;
    for (let attempt = 0; attempt < 3 && status !== 200; attempt += 1) {
      const answered = page.waitForResponse((response) => ITEMS.test(response.url()) && response.url().includes('q='));
      await searchBox(page).fill(`zzforget${stamp}`);
      await searchBox(page).press('Enter');
      status = (await answered).status();
    }
    expect(status, 'the search was answered').toBe(200);
    await expect(memoryRow(memoriesPanel(page), text), 'a later search does not find it').toHaveCount(0);
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC16: the card's own busy message (that the page does not become busy is OM2's, on the online demo, where that banner can show). */
test('MC16: a 503 search_busy shows the card\'s busy notice, announced and named in the search\'s description', async ({ page }) => {
  await recordAnnouncements(page);
  await page.route(/\/api\/v1\/memory\/items\?q=/, (route) =>
    route.fulfill({ status: 503, headers: { 'retry-after': '5' }, json: { error: { code: 'search_busy', message: SEARCH_BUSY } } }),
  );
  await openLive(page);
  await showMemories(page);
  await searchBox(page).fill('vpn');
  await searchBox(page).press('Enter');
  await expect(memoriesPanel(page).getByText(SEARCH_BUSY, { exact: true }), 'the card shows the busy message').toBeVisible();
  await expect(searchBox(page), 'the box is described by it').toHaveAccessibleDescription(SEARCH_BUSY);
  await expect(searchButton(page), 'and so is the button').toHaveAccessibleDescription(SEARCH_BUSY);
  await expect.poll(() => announcements(page, SEARCH_BUSY), { message: 'it is announced once' }).toBe(1);
  await page.waitForTimeout(1000);
  expect(await announcements(page, SEARCH_BUSY), 'and only once').toBe(1);
  await expect(memoriesPanel(page).locator('li.row'), 'no rows show after a failed search').toHaveCount(0);
});

/** MC17: the confirm dialog's failure notice. */
test('MC17: the confirm dialog\'s failure notice is announced once and named in the confirm button\'s description', async ({ page }) => {
  const text = `The zzfail${Date.now().toString(36)} rule stays`;
  const refs: string[] = [];
  try {
    await recordAnnouncements(page);
    const session = await openLive(page);
    refs.push(await seedMemory(session, text));
    await page.route(ITEM_FORGET, (route) =>
      route.request().method() === 'DELETE' ? route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The forget failed.' } } }) : route.continue(),
    );
    await showMemories(page);
    await memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Forget ${text}`, exact: true }).click();
    const confirm = memoryDialog(page).getByRole('button', { name: 'Forget', exact: true });
    await expect(confirm, 'the confirm button has no description before it fails').not.toHaveAccessibleDescription(FAILED);
    await confirm.click();
    await expect(memoryDialog(page).getByText(FAILED, { exact: true }), 'the failure notice shows in the dialog').toBeVisible();
    await expect(confirm, 'the confirm button is described by it').toHaveAccessibleDescription(FAILED);
    await expect.poll(() => announcements(page, FAILED), { message: 'it is announced once' }).toBe(1);
    await page.waitForTimeout(1000);
    expect(await announcements(page, FAILED), 'and only once').toBe(1);
    await expect(memoryDialog(page), 'the dialog stays open').toBeVisible();
    await expect(page.locator('app-memory-card li.row').filter({ hasText: text }), 'and the row stays (seen from behind the dialog)').toHaveCount(1);
    expect(await memoryExists(refs[0] ?? ''), 'and so does the table row').toBe(1);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await removeAllMemories(refs);
  }
});

/** MC19: a pin or unpin that fails says so in the panel's one notice, and a 404 means the memory is gone. */
test('MC19: a failed pin or unpin shows its notice, announced once and named in the button\'s description, and a 404 takes the row off', async ({ page }) => {
  test.setTimeout(150_000);
  const stamp = Date.now().toString(36);
  const plain = `The zzpinfail${stamp} cable is blue`;
  const held = `The zzunpinfail${stamp} cable is red`;
  const pinFailed = "Couldn't pin it. Nothing was changed.";
  const unpinFailed = "Couldn't unpin it. Nothing was changed.";
  const refs: string[] = [];
  try {
    await recordAnnouncements(page);
    const session = await openLive(page);
    refs.push(await seedMemory(session, plain), await seedMemory(session, held));
    const pinned = await page.request.fetch(`${MEMORY}/${refs[1] ?? ''}/pin`, { method: 'POST', headers: envelope() });
    expect(pinned.status(), await pinned.text()).toBe(200);
    let unpins = 0;
    await page.route(/\/api\/v1\/memory\/[^/?]+\/pin$/, (route) => {
      if (route.request().method() === 'POST') {
        return route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The pin failed.' } } });
      }
      unpins += 1;
      return unpins === 1
        ? route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The unpin failed.' } } })
        : route.fulfill({ status: 404, json: { error: { code: 'not_found', message: 'zz Gone.' } } });
    });
    await showMemories(page);

    const pin = memoryRow(memoriesPanel(page), plain).getByRole('button', { name: `Pin ${plain}`, exact: true });
    await pin.click();
    await expect(memoriesPanel(page).getByText(pinFailed, { exact: true }), 'a failed pin shows its notice').toBeVisible();
    await expect(pin, 'the button is described by it').toHaveAccessibleDescription(pinFailed);
    await expect(pin, 'and the row stays unpinned').toBeVisible();
    await expect.poll(() => announcements(page, pinFailed), { message: 'it is announced once' }).toBe(1);
    await page.waitForTimeout(1000);
    expect(await announcements(page, pinFailed), 'and only once').toBe(1);
    expect(await pinnedCountOf(session), 'and nothing else was pinned').toBe(1);

    const unpin = memoryRow(memoriesPanel(page), held).getByRole('button', { name: `Unpin ${held}`, exact: true });
    await unpin.click();
    await expect(memoriesPanel(page).getByText(unpinFailed, { exact: true }), 'a failed unpin shows its notice').toBeVisible();
    await expect(unpin, 'the button is described by it').toHaveAccessibleDescription(unpinFailed);
    await expect.poll(() => announcements(page, unpinFailed), { message: 'it is announced once' }).toBe(1);
    await page.waitForTimeout(1000);
    expect(await announcements(page, unpinFailed), 'and only once').toBe(1);
    expect(await pinnedCountOf(session), 'and the pin is still there').toBe(1);

    await unpin.click();
    await expect(memoryRow(memoriesPanel(page), held), 'a 404 takes the row off the list').toHaveCount(0);
    await expect(headingOf(page), 'and focus, which was on its button, goes to the Memory heading').toBeFocused();
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await removeAllMemories(refs);
  }
});

/** MC18: a local install has no demo rule line. */
test('MC18: a local install shows no demo rule line in the card', async ({ page }) => {
  await openLive(page);
  await expect(card(page).getByText(DEMO_RULE), 'no demo rule line under the tabs').toHaveCount(0);
  await showMemories(page);
  await expect(card(page).getByText(DEMO_RULE)).toHaveCount(0);
});

/** MC20 (QA): the Pinned read answered 503 search_busy shows the tab's intro only, no figure and no empty text (that the page does not become busy is OM2's, on the online demo, where that banner can show). */
test('MC20: a 503 search_busy on the Pinned read shows the intro only, with no figure and no empty text', async ({ page }) => {
  let answered = 0;
  await page.route(PINNED, (route) => {
    answered += 1;
    return route.fulfill({ status: 503, headers: { 'retry-after': '5' }, json: { error: { code: 'search_busy', message: SEARCH_BUSY } } });
  });
  await openLive(page);
  await tabOf(page, 'Pinned').click();
  await expect(tabOf(page, 'Pinned')).toHaveAttribute('aria-selected', 'true');
  await expect.poll(() => answered, { message: 'the Pinned read was answered with 503' }).toBeGreaterThanOrEqual(1);
  await expect(pinnedPanel(page).getByText(PINNED_INTRO), 'the tab shows its intro').toBeVisible();
  await page.waitForTimeout(1000);
  await expect(pinnedPanel(page).getByText(/of 1,000 tokens/), 'a failed read shows no figure, which would claim 0 used').toHaveCount(0);
  await expect(pinnedPanel(page).getByText(PINNED_EMPTY), 'and no empty text, which would claim nothing is pinned').toHaveCount(0);
  await expect(pinnedPanel(page).locator('li.row'), 'and no rows').toHaveCount(0);
});

/** MC21 (QA): with more memories than the 20 the list shows, the line under it says how many are shown of how many there are (the deferred 41.13 finding). */
test('MC21: with 21 new memories, All memories shows the newest 20 and the line "Showing the newest 20 of N"', async ({ page }) => {
  test.setTimeout(240_000);
  const stamp = Date.now().toString(36);
  const refs: string[] = [];
  try {
    const session = await openLive(page);
    const before = await page.request.get(`${MEMORY}/items`);
    expect(before.status(), await before.text()).toBe(200);
    const baseline = ((await before.json()) as { total: number }).total;
    for (let n = 1; n <= 21; n += 1) refs.push(await seedMemory(session, `The zzbulk${stamp} item ${String(n).padStart(2, '0')} is here`));
    await showMemories(page);
    await expect(memoriesPanel(page).locator('li.row'), 'the list holds the newest 20').toHaveCount(20);
    await expect(
      memoriesPanel(page).getByText(`Showing the newest 20 of ${baseline + 21}. Search to find the others.`, { exact: true }),
      'and the line says 20 of the count the server holds',
    ).toBeVisible();
    await expect(memoryRow(memoriesPanel(page), `item 21 is here`), 'the newest is in the list').toHaveCount(1);
    await expect(memoryRow(memoriesPanel(page), `item 01 is here`), 'the oldest of the 21 is not').toHaveCount(0);
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC22 (QA): Forget answered 404 (the memory was already gone) closes the dialog and the row leaves both lists, and Pinned is read again. */
test('MC22: Forget of a memory that is already gone is answered 404, closes the dialog and the row leaves All memories and Pinned', async ({ page }) => {
  test.setTimeout(150_000);
  const text = `The zzgone${Date.now().toString(36)} pin is stale`;
  const refs: string[] = [];
  try {
    const session = await openLive(page);
    const ref = await seedMemory(session, text);
    refs.push(ref);
    const pinned = await page.request.fetch(`${MEMORY}/${ref}/pin`, { method: 'POST', headers: envelope() });
    expect(pinned.status(), await pinned.text()).toBe(200);
    await showPinned(page);
    await expect(memoryRow(pinnedPanel(page), text), 'the memory is on Pinned').toHaveCount(1);
    await showMemories(page);
    await expect(memoryRow(memoriesPanel(page), text), 'and on All memories').toHaveCount(1);
    await removeMemory(ref);
    expect(await memoryExists(ref), 'the table row is gone behind the page').toBe(0);

    await memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Forget ${text}`, exact: true }).click();
    const deleted = page.waitForResponse((response) => response.request().method() === 'DELETE' && ITEM_FORGET.test(new URL(response.url()).pathname));
    await memoryDialog(page).getByRole('button', { name: 'Forget', exact: true }).click();
    expect((await deleted).status(), 'the confirm is answered 404').toBe(404);
    await expect(memoryDialog(page), 'the dialog closes').toHaveCount(0);
    await expect(memoryRow(memoriesPanel(page), text), 'the row leaves All memories').toHaveCount(0);
    await showPinned(page);
    await expect(memoryRow(pinnedPanel(page), text), 'and Pinned').toHaveCount(0);
    await expect(pinnedPanel(page).getByText('0 of 1,000 tokens (estimated).', { exact: true }), 'with the figure read again').toBeVisible();
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC23: Unpin on Pinned asks by the flag the Pinned panel shows, even when All memories was read before the memory was pinned. */
test('MC23: Unpin on Pinned unpins a memory that All memories still lists as unpinned', async ({ page }) => {
  test.setTimeout(150_000);
  const text = `The zzstale${Date.now().toString(36)} flag is green`;
  const refs: string[] = [];
  try {
    const session = await openLive(page);
    const ref = await seedMemory(session, text);
    refs.push(ref);
    await showMemories(page);
    await expect(memoryRow(memoriesPanel(page), text).getByRole('button', { name: `Pin ${text}`, exact: true }), 'All memories read it unpinned').toBeVisible();
    const pinned = await page.request.fetch(`${MEMORY}/${ref}/pin`, { method: 'POST', headers: envelope() });
    expect(pinned.status(), await pinned.text()).toBe(200);
    await showPinned(page);
    const sent = watchMemory(page);
    const unpinned = page.waitForResponse((response) => response.request().method() === 'DELETE' && new URL(response.url()).pathname === `${MEMORY}/${ref}/pin`, { timeout: 15_000 });
    await memoryRow(pinnedPanel(page), text).getByRole('button', { name: `Unpin ${text}`, exact: true }).click();
    expect((await unpinned).status(), 'the press sent an unpin, which is answered 200').toBe(200);
    expect(sent().filter((one) => one.startsWith('POST ')), 'and no pin').toEqual([]);
    await expect(memoryRow(pinnedPanel(page), text), 'the row leaves Pinned').toHaveCount(0);
    expect(await pinnedCountOf(session), 'and the table holds no pin').toBe(0);
  } finally {
    await removeAllMemories(refs);
  }
});

/** MC24: a submit while a search is out sends nothing. */
test('MC24: a second submit while a search is out is ignored, and Search says it is busy until the answer', async ({ page }) => {
  let searches = 0;
  let release: () => void = () => undefined;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  try {
    await page.route(/\/api\/v1\/memory\/items\?q=/, async (route) => {
      searches += 1;
      await held;
      await route.fulfill({ json: { items: [], total: 0 } });
    });
    await openLive(page);
    await showMemories(page);
    await searchBox(page).fill('zzonce');
    await searchBox(page).press('Enter');
    await expect.poll(() => searches, { message: 'the first submit sent its search' }).toBe(1);
    await expect(searchButton(page), 'Search says it is busy while the search is out').toHaveAttribute('aria-disabled', 'true');
    await searchBox(page).press('Enter');
    await searchBox(page).fill('zztwice');
    await searchBox(page).press('Enter');
    await page.waitForTimeout(800);
    expect(searches, 'the submits while it was out sent nothing').toBe(1);
    release();
    await expect(memoriesPanel(page).getByText(NO_MATCH, { exact: true }), 'the first search is answered').toBeVisible();
    await expect(searchButton(page), 'and Search is no longer busy').not.toHaveAttribute('aria-disabled', 'true');
  } finally {
    release();
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  }
});
