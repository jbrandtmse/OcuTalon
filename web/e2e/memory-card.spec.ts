import { expect, test, type Locator, type Page, type Request } from './support/fixtures';

import { README_ACCOUNT } from './sign-in/helpers';
import { dropPhone, pointKeys, restoreKeys } from './support/devices';
import { railOf, signInReadmeLoaded, unique } from './support/floor';
import { cleanFixtureRows, sendItem, seedOtherSession } from './support/iris';
import {
  localNoonUtc,
  logMark,
  precedentExists,
  removeDecisionsOf,
  removeNoteRows,
  removePrecedent,
  seedNoteTurn,
  seedPrecedent,
  triageRequests,
  waitDecideRef,
} from './support/memory';
import { sessionRef } from './support/persona';
import { instanceSeq, monitorSettled, runnersReady, runnersRecorded } from './support/runners';

/**
 * Story 41.6 (MC1 to MC9; FR-71, FR-72, AD-4, AD-28, NFR-25), the Memory card in the status rail, in a real browser against the stack that test-sign-in.sh
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
 *   MC9  Integration: after Forget the next decide request for the same sender carries no precedent (the CI mock's log).
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
const tabOf = (page: Page, name: 'Notes' | 'Your answers'): Locator => card(page).getByRole('tab', { name, exact: true });
const notesPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'Notes', exact: true });
const answersPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'Your answers', exact: true });
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

/** Opens Your answers (a click reads it again) and waits for the rows. */
async function showAnswers(page: Page): Promise<void> {
  await tabOf(page, 'Your answers').click();
  await expect(tabOf(page, 'Your answers')).toHaveAttribute('aria-selected', 'true');
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
test('MC1: the rail has eight headings with Memory between Heartbeat checklist and Persona, and the card shows the tabs Notes and Your answers', async ({ page }) => {
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
  await expect(tabs, 'two tabs, in order').toHaveText(['Notes', 'Your answers']);
  await expect(tabOf(page, 'Notes'), 'Notes is selected').toHaveAttribute('aria-selected', 'true');
  await expect(tabOf(page, 'Notes')).toHaveAttribute('tabindex', '0');
  await expect(tabOf(page, 'Your answers')).toHaveAttribute('aria-selected', 'false');
  await expect(tabOf(page, 'Your answers')).toHaveAttribute('tabindex', '-1');
  await expect(notesPanel(page), 'the Notes panel is named by its tab').toBeVisible();
  await expect(answersPanel(page), 'the Your answers panel is hidden').toHaveCount(0);
  await expect(notesPanel(page).getByText(NOTES_INTRO, { exact: true }), 'the Notes intro, verbatim').toBeVisible();
  await expect(card(page).locator(REGION), 'the card adds no empty text, hint or live region').toHaveCount(0);
  await expect(card(page).getByRole('heading', { level: 3 }), 'and no h3 of its own').toHaveCount(0);
});

/** The UTC time one hour after the given UTC time to the second (YYYY-MM-DDTHH:MM:SSZ). */
function hourAfter(utc: string): string {
  return new Date(Date.parse(utc) + 3_600_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** MC2: two turns of today and two of yesterday, seeded latest first, show under their day in time order, which is the order the route serves. */
test('MC2: done turns of today and of yesterday show under Today and Yesterday, each day in served order', async ({ page }) => {
  const session = await sessionRef();
  const texts = {
    today: [unique('mc2 today a').replace(/ /g, 'Zz'), unique('mc2 today b').replace(/ /g, 'Zz')],
    yesterday: [unique('mc2 yesterday a').replace(/ /g, 'Zz'), unique('mc2 yesterday b').replace(/ /g, 'Zz')],
  };
  const turns: string[] = [];
  try {
    for (const [day, ago] of [['today', 0], ['yesterday', 1]] as const) {
      const early = await localNoonUtc(ago);
      const [first, second] = texts[day] as [string, string];
      turns.push(await seedNoteTurn(session, second, hourAfter(early)));
      turns.push(await seedNoteTurn(session, first, early));
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

  await page.unrouteAll({ behavior: 'ignoreErrors' });
  await page.route(NOTES, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } }));
  await page.route(PRECEDENTS, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } }));
  await tabOf(page, 'Notes').click();
  await expect(notesPanel(page).getByText(NOTES_INTRO, { exact: true }), 'after a failed read, the intro shows').toBeVisible();
  await expect(dayLabels(page), 'with no day label').toHaveCount(0);
  await expect(notesPanel(page).getByText(NOTES_EMPTY), 'and no empty text').toHaveCount(0);
  await expect(notesPanel(page).getByText(YESTERDAY_EMPTY), 'nor the yesterday text').toHaveCount(0);
  await showAnswers(page);
  await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true }), 'a failed list shows the intro').toBeVisible();
  await expect(answersPanel(page).getByText(ANSWERS_EMPTY), 'and no empty text').toHaveCount(0);

  await page.unrouteAll({ behavior: 'ignoreErrors' });
  await tabOf(page, 'Notes').click();
  await expect(dayLabels(page), 'selecting the tab again reads it again').toHaveText(['Today', 'Yesterday']);
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

/** MC5: a failed confirm and a 404. */
test('MC5: a failed confirm keeps the dialog open with the notice and the row, and a 404 removes the row', async ({ page }) => {
  const session = await sessionRef();
  const summary = unique('mc5');
  const ref = await seedPrecedent(session, { summary, answeredAt: '2031-02-01T10:00:00Z', matchKey: 'zz.mc5@example.com' });
  try {
    let answer: 'fail' | 'gone' = 'fail';
    await page.route(FORGET_ONE, (route) =>
      route.request().method() !== 'DELETE'
        ? route.continue()
        : answer === 'fail'
          ? route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The forget failed.' } } })
          : route.fulfill({ status: 404, json: { error: { code: 'not_found', message: 'OcuTalon has nothing at this address.' } } }),
    );
    await open(page);
    await showAnswers(page);
    await forgetOf(page, summary).click();
    await confirmOf(page).click();
    await expect(dialogOf(page).getByText(FAILED, { exact: true }), 'a 500 shows the failure notice in the dialog').toBeVisible();
    await expect(dialogOf(page), 'and the dialog stays open').toBeVisible();
    await expect(rowBehind(page, summary), 'and the row stays').toHaveCount(1);
    expect(await precedentExists(ref)).toBe(1);
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
    await expect(tabOf(page, 'Your answers'), 'ArrowRight focuses the other tab').toBeFocused();
    await expect(tabOf(page, 'Your answers'), 'and selects it').toHaveAttribute('aria-selected', 'true');
    await expect(answersPanel(page).getByText(ANSWERS_INTRO, { exact: true }), 'the panel changes').toBeVisible();
    await expect(notesPanel(page), 'and the Notes panel is hidden').toHaveCount(0);
    await page.keyboard.press('ArrowRight');
    await expect(tabOf(page, 'Notes'), 'ArrowRight wraps').toBeFocused();
    await page.keyboard.press('ArrowLeft');
    await expect(tabOf(page, 'Your answers'), 'ArrowLeft wraps back').toBeFocused();
    await expect(tabOf(page, 'Your answers')).toHaveAttribute('aria-selected', 'true');
    await expect(forgetOf(page, summary), 'the newest row is the first Forget').toBeVisible();

    await page.keyboard.press('Tab');
    await expect(forgetOf(page, summary), 'Tab reaches Forget').toBeFocused();
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
    turns.push(await seedNoteTurn(session, ownText));
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
    release();
    await tabOf(page, 'Notes').click();
    await expect(dayLabels(page), 'after the reload the notes are read again').toHaveText(['Today', 'Yesterday']);
    await expect(notesPanel(page).getByText(ownText), 'the removed turn does not show').toHaveCount(0);
    await showAnswers(page);
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
    expect(ready.reason, 'the production is ready').toBe('');
    expect(ready.keyed, 'and the TriageAgent has its key').toBe('1');
  });

  test.afterAll(async () => {
    test.setTimeout(240_000);
    const mark = await instanceSeq();
    try {
      await restoreKeys();
    } finally {
      expect(await runnersRecorded(), 'the runners recorded the restored keys').toBe('1');
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
      await removeDecisionsOf(items);
      await dropPhone(README_ACCOUNT.user, since);
      if (ref) await removePrecedent(ref);
    }
  });
});
