import { expect, test, type APIRequestContext, type BrowserContext, type Locator, type Page } from '@playwright/test';

import { STATE } from '../support/api';
import {
  chk,
  cleanFixtureRows,
  fixtureUser,
  irisScript,
  publishReminder,
  quoted,
  seedApproval,
  seedCheck,
  seedDecision,
  seedDecisions,
  seedIncident,
  sendItemDecision,
  sinkEvent,
} from '../support/iris';
import { TRACE_PAGE, drawnMessages, expectDrawn, newestTurn, postTurn, signInToTrace, type Cursor, type Turn } from '../support/trace';
import { signIn, signInOverHttp } from '../sign-in/helpers';

/**
 * Story 2.13, the Visual Trace links on the page (V1 to V8), in a real browser against a real stack and the real Visual Trace pages.
 * Every case signs in as the links fixture user that test-sign-in.sh created (OCUTALON_LINKS_USER; the user role and the trace role),
 * whose session no other spec reads. The user's chat is never assumed empty: a case that needs a turn posts one through the API and
 * waits for it to be done, or takes the newest turn of /state, and a case that seeds rows removes them in finally. Each case has a
 * fresh browser context, so the sign-in help is unseen in it unless the case marks it seen with an init script.
 * - V1: a reply's strip links to its turn, and the link opens Visual Trace on it. V2: a rail decision of a chat turn opens on its turn
 *   (DW-129), another decision on its own session. V3: check, reminder and approval rows carry their links, and a row with no target
 *   has none.
 * - V4 to V6: the sign-in help. On a local install the first press shows it, "Don't show this again" is kept for the browser, a storage
 *   that throws still gives working help and links, and the online demo opens the links directly.
 * - V7 and V8: the Visual Trace menu and its popover (DW-58), and "Open my conversation in Visual Trace", which opens the day's thread at
 *   its newest turn and follows a turn that arrives later.
 * V1, V2 and V8 open the real Visual Trace pages and read what they draw. The other cases only check which address a link opens, so
 * their tabs get a stand-in page (stubTraces): a tab that signs in to a trace application holds a licence connection of the stack
 * until its session times out, and the stack's licence allows few of them.
 * The texts and the storage keys are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 90_000 });

const KIND = 'LINKS';

/** The keys of the help's two flags: this tab's session has seen it, and this browser switched it off. */
const SEEN_KEY = 'ocutalon.traceHelp.seen';

const SIGN_IN_NAME = 'Open in Visual Trace (shows sign-in help first)';
const PLAIN_NAME = 'Trace (opens in a new tab)';
const HEADING = 'Sign in to Visual Trace';
const HELP_TEXT = 'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.';
const OPEN_NAME = 'Open Visual Trace (opens in a new tab)';
const CONVERSATION = 'Open my conversation in Visual Trace';
const CONVERSATION_NAME = `${CONVERSATION} (opens in a new tab)`;
const DONT_SHOW = "Don't show this again";

/** The middle dot between the parts of a meta line, with its spaces. */
const DOT = ' \u00B7 ';

/** How long the page may take to apply an event after the helper returned: the live poll (1 to 2 s) and the render. */
const APPLIED_MS = 15_000;

let api: APIRequestContext;
const cursor: Cursor = { seq: 0 };

/** A text no other case or run made. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const mainOf = (page: Page): Locator => page.locator('main.main');
const railOf = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
const traceMenu = (page: Page): Locator => page.getByRole('button', { name: 'Visual Trace', exact: true });
const popoverOf = (page: Page, name: string): Locator => page.getByRole('dialog', { name, exact: true });
const replyOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="reply"][data-key="${key}"]`);
const stripLink = (page: Page, key: string): Locator => replyOf(page, key).locator('app-decision-strip app-trace-link a');
const allLinks = (page: Page): Locator => page.locator('app-trace-link a');
const rowOf = (page: Page, marker: string): Locator => railOf(page).locator('li.row').filter({ hasText: marker });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(120_000);
  api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  const { user, password } = fixtureUser(KIND);
  await signInOverHttp(api, user, password);
  const state = (await (await api.get(STATE)).json()) as { streams: { session: number } };
  cursor.seq = state.streams.session;
});

test.afterAll(async () => {
  await api?.dispose();
});

/** A poll that a routed /state handler is still answering when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

/** The newest turn of the user's chat, posting one first when the chat holds none. */
async function someTurn(): Promise<Turn> {
  const state = (await (await api.get(STATE)).json()) as { chat: Array<{ type: string }> };
  return state.chat.some((item) => item.type === 'chat.message') ? newestTurn(api) : postTurn(api, cursor, 0, 'links');
}

/** Marks the sign-in help as seen in the page's tab session before any script of the page runs. */
async function helpSeen(page: Page): Promise<void> {
  await page.addInitScript((key) => {
    try {
      window.sessionStorage.setItem(key, '1');
    } catch {
      /* The page copes with a storage that fails. */
    }
  }, SEEN_KEY);
}

/** Signs the links user in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
}

/** Waits until the page has applied the event of this Seq on the session's stream. */
async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-session-seq')), { message: `the page applied Seq ${seq}`, timeout: APPLIED_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** Answers the page's /state with the real server's answer, changed by `change`. Call it before signing in. */
async function changeSnapshot(page: Page, change: (snapshot: Record<string, unknown>) => void): Promise<void> {
  await page.route(`**${STATE}`, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    change(body);
    await route.fulfill({ response, json: body });
  });
}

/** The page that the action opens in a new tab, signed in to the trace application when it asks. */
async function opensTab(page: Page, action: () => Promise<unknown>): Promise<Page> {
  const [popup] = await Promise.all([page.context().waitForEvent('page'), action()]);
  await popup.waitForLoadState('domcontentloaded');
  await signInToTrace(popup, KIND);
  return popup;
}

/** Gives every trace application page of the context a stand-in answer: the tabs it opens keep the address they were opened at. */
async function stubTraces(context: BrowserContext): Promise<void> {
  await context.route('**/ocutalon/trace/**', (route) => route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Visual Trace</title>' }));
}

/** The path and query of the address the page is at. */
const addressOf = (page: Page): string => {
  const url = new URL(page.url());
  return `${url.pathname}${url.search}`;
};

/** Waits until the page is at an address that holds the text: a new tab may still be signing in to the trace application. */
async function expectAddress(page: Page, text: string, message: string): Promise<void> {
  await expect.poll(() => addressOf(page), { message, timeout: 30_000 }).toContain(text);
}

/** Collects every page that opens in the page's context from now on. */
function watchTabs(page: Page): Page[] {
  const opened: Page[] = [];
  page.context().on('page', (one) => opened.push(one));
  return opened;
}

/** A pause long enough for a tab that a press would open to have opened. */
const SETTLE_MS = 1000;

/** V1: a reply's strip links to its turn, and the link opens Visual Trace on it. */
test("V1: a reply's strip links to its turn, and the link opens Visual Trace on it", async ({ page }) => {
  const turn = await postTurn(api, cursor, 1, 'links');
  expect(turn.traceUrl, 'the turn has a trace link').toBe(`${TRACE_PAGE}${turn.traceHeaderId}&PAGE=${Math.ceil(turn.traceItemIndex / 40)}`);
  await helpSeen(page);
  await open(page);

  const strip = replyOf(page, turn.clientId).locator('app-decision-strip');
  await expect(strip, "the turn's reply has its strip").toHaveCount(1);
  const link = stripLink(page, turn.clientId);
  await expect(link).toHaveCount(1);
  await expect(link, 'the help is seen, so the link has its plain name').toHaveAccessibleName(PLAIN_NAME);
  await expect(link, "its address is the turn's own, as served").toHaveAttribute('href', turn.traceUrl);
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
  await expect(link, 'with no popup of its own').not.toHaveAttribute('aria-haspopup', /.*/);
  await expect(link.locator('svg'), 'the external-link icon, 12px').toHaveAttribute('width', '12');
  await expect(link.locator('xpath=ancestor::button'), 'the link is never inside a button').toHaveCount(0);
  await expect(link, 'always underlined').toHaveCSS('text-decoration-line', 'underline');

  // The stack's model answers with the fixed fallback, whose strip has no confidence and no cost: the link follows the flag.
  await expect(strip.locator('.line1 .meta > :last-child'), 'the link is the last item of line 1').toHaveJSProperty('tagName', 'APP-TRACE-LINK');
  await expect(strip.locator('.line1 .meta > *'), 'and the only one: no separator stands before it').toHaveCount(1);

  const popup = await opensTab(page, () => link.click());
  await expectAddress(popup, `SESSIONID=${turn.traceHeaderId}`, 'the new tab opens at the turn');
  const drawn = await drawnMessages(popup);
  expect(drawn.ids, "Visual Trace draws the turn's Item header").toContain(String(turn.traceHeaderId));
  expectDrawn(drawn, turn.traceHeaderId, turn.traceItemIndex, 'the reply strip link');
});

/** V1, continued: a notice card's strip links to its decision, after the confidence and the cost. */
test("V1: a notice card's strip links to its decision, last on line 1 after the separator", async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const summary = unique('v1 notice');
  const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary, reasons: 'zz first.\nzz second.', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4321 });
  try {
    await helpSeen(page);
    await open(page);
    await sendItemDecision(user, { outcome: 'tellnow', summary, decisionRef });
    const card = page.locator('app-chat-panel app-notice-card').filter({ hasText: summary });
    await expect(card).toHaveCount(1, { timeout: APPLIED_MS });
    const strip = card.locator('app-decision-strip');
    const link = strip.locator('app-trace-link a');
    await expect(link, "the card's link is its decision's").toHaveAttribute('href', `${TRACE_PAGE}4321`);
    await expect(link).toHaveAccessibleName(PLAIN_NAME);
    await expect(strip.locator('.line1 .meta'), 'after the confidence and the cost').toHaveText(new RegExp(`^Confidence 0\\.90${DOT}\\$0\\.0003${DOT}Trace`));
    await expect(strip.locator('.line1 .meta > :last-child'), 'last on line 1').toHaveJSProperty('tagName', 'APP-TRACE-LINK');
    await expect(strip.locator('.line1 .meta > :nth-last-child(2)'), 'after the separator').toHaveText('\u00B7');
    await expect(strip.getByRole('button', { name: 'Decision details' }).getByRole('link'), 'and never inside the Details button').toHaveCount(0);
  } finally {
    await cleanFixtureRows([decisionRef]);
  }
});

/** The ItemId of the turn with the Ref: the Item message that made it. */
async function itemIdOf(turnRef: string): Promise<string> {
  const lines = await irisScript(`Set t=##class(OcuTalon.Data.Turn).RefIndexOpen(${quoted(turnRef)})\nWrite !,"CHK|item|",$Select($IsObject(t):t.ItemId,1:"")`);
  const item = chk(lines, 'item');
  expect(item, 'the turn has an Item').toBeTruthy();
  return item!;
}

/** V2: a rail decision of a chat turn opens on its turn (DW-129), and any other decision on its own session. */
test('V2: a rail decision of a chat turn opens on its turn', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const turn = await someTurn();
  const itemId = await itemIdOf(turn.ref);
  // An Item has one decision of each kind: a turn that already shows its decide row (a model that answered) is the row of a chat turn,
  // and otherwise one is seeded for the turn's Item, with a TraceSessionId that is not the turn's header. BridgeSink gets its event as
  // the bridge would after its commit.
  const seeded = turn.decision === undefined ? await seedDecisions(user, [{ itemId, outcome: 'act', summary: unique('v2 turn'), reasons: 'zz reason', confidence: 0.9, costUSD: 0.0003, traceSessionId: 42 }]) : [];
  const decisionRef = turn.decision?.ref ?? seeded[0]!;
  const [other] = await seedDecisions(user, [{ outcome: 'act', summary: unique('v2 other'), reasons: 'zz reason', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4242 }]);
  try {
    await helpSeen(page);
    await open(page);
    await sinkEvent(user, 'decision.recorded', { ref: decisionRef });
    await applied(page, await sinkEvent(user, 'decision.recorded', { ref: other }));

    const ofTurn = railOf(page).locator(`li.row[data-row-key="decisions:${decisionRef}"]`);
    await expect(ofTurn, "the turn's decision is in the rail").toHaveCount(1);
    const link = ofTurn.locator('app-trace-link a');
    await expect(link).toHaveCount(1);
    await expect(link, "its link is the turn's own link, with the turn's PAGE").toHaveAttribute('href', turn.traceUrl);
    await expect(ofTurn.locator('.meta > :last-child'), 'last on line 3').toHaveJSProperty('tagName', 'APP-TRACE-LINK');
    await expect(ofTurn.locator('button a'), 'beside the button, never inside it').toHaveCount(0);
    const popup = await opensTab(page, () => link.click());
    expectDrawn(await drawnMessages(popup), turn.traceHeaderId, turn.traceItemIndex, "the rail decision of the turn's Item");
    await popup.close();

    const row = railOf(page).locator(`li.row[data-row-key="decisions:${other}"]`);
    await expect(row.locator('app-trace-link a'), 'a decision of an Item that is no turn opens its own session, with no PAGE').toHaveAttribute('href', `${TRACE_PAGE}4242`);
  } finally {
    await cleanFixtureRows([other, ...seeded]);
  }
});

/** V3: check, reminder and approval rows carry their links, and a row with no target has none. */
test('V3: check, reminder and approval rows carry their links; a row with no target has none', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const turn = await someTurn();
  const header = turn.traceHeaderId;
  const marker = unique('v3');
  const lastRunAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const traced = await seedCheck(user, { namespace: 'OCUTALON', production: `Zz.Links.${marker.slice(-8)}`, displayName: `${marker} traced`, lastRunAt, result: 'passed', finding: 'zz finding', lastRunHeaderId: header });
  const bare = await seedCheck(user, { namespace: 'OCUTALON', production: `Zz.Links.Bare${marker.slice(-8)}`, displayName: `${marker} bare`, lastRunAt, result: 'passed', finding: 'zz finding' });
  const incident = await seedIncident(user, { traceHeaderId: header });
  const request = await seedApproval(user, { incidentRef: incident, dryRun: { affected: 3, itemNoun: { one: 'order', other: 'orders' } } });
  const untraced = await seedApproval(user, { toolName: `${marker} tool`, kind: 'tool_call', dryRun: null });
  const refs = [traced, bare, incident, request, untraced];
  try {
    await stubTraces(page.context());
    await helpSeen(page);
    await open(page);
    const state = (await (await api.get(STATE)).json()) as {
      rail: { checks: Array<{ ref: string; traceUrl?: string }>; approvals: Array<{ ref: string; traceUrl?: string }> };
    };
    const checkUrl = state.rail.checks.find((one) => one.ref === traced)?.traceUrl;
    const approvalUrl = state.rail.approvals.find((one) => one.ref === request)?.traceUrl;
    expect(checkUrl, "the check's link is its latest run's header").toBe(`${TRACE_PAGE}${header}`);
    expect(approvalUrl, "the approval's link is its incident's trace").toBe(`${TRACE_PAGE}${header}`);

    const checkRow = rowOf(page, `${marker} traced`);
    await expect(checkRow.locator('app-trace-link a')).toHaveAttribute('href', checkUrl!);
    await expect(checkRow.locator('.meta > :last-child'), "the check's link is last on its meta line").toHaveJSProperty('tagName', 'APP-TRACE-LINK');
    await expect(checkRow.locator('.meta'), 'after the last run and the finding').toHaveText(new RegExp(`Last run .*${DOT.trim()} zz finding ${DOT.trim()} Trace`));
    await expect(rowOf(page, `${marker} bare`), 'the check with no run is in the rail').toHaveCount(1);
    await expect(rowOf(page, `${marker} bare`).locator('app-trace-link'), 'and has no link').toHaveCount(0);

    const approvalRow = railOf(page).locator(`li.row[data-section="approvals"]`).filter({ hasText: 'Repair and resend 3 orders' });
    await expect(approvalRow.locator('app-trace-link a')).toHaveAttribute('href', approvalUrl!);
    await expect(approvalRow.locator('.meta > :last-child'), "the approval's link is last on its meta line").toHaveJSProperty('tagName', 'APP-TRACE-LINK');
    await expect(rowOf(page, `${marker} tool`), 'the request with no incident is in the rail').toHaveCount(1);
    await expect(rowOf(page, `${marker} tool`).locator('app-trace-link'), 'and has no link').toHaveCount(0);

    const dueAt = new Date(Date.now() + 3_600_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    const withTarget = unique('v3 reminder');
    const without = unique('v3 reminder bare');
    await publishReminder(user, { text: without, dueAt });
    const seq = await publishReminder(user, { text: withTarget, dueAt, traceHeaderId: header, traceNamespace: 'OCUTALON' });
    await applied(page, seq);
    const reminderRow = rowOf(page, withTarget);
    await expect(reminderRow.locator('app-trace-link a'), "a reminder with a target in its payload has a link to it").toHaveAttribute('href', `${TRACE_PAGE}${header}`);
    await expect(reminderRow.locator('.meta > :last-child'), 'last on its meta line').toHaveJSProperty('tagName', 'APP-TRACE-LINK');
    await expect(rowOf(page, without), 'the reminder with no target is in the rail').toHaveCount(1);
    await expect(rowOf(page, without).locator('app-trace-link'), 'and has no link').toHaveCount(0);

    const popup = await opensTab(page, () => checkRow.locator('app-trace-link a').click());
    await expect.poll(() => addressOf(popup), { message: "the check's link opens a page at its address" }).toBe(checkUrl);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** V4: the first press on a local install shows the sign-in help, and then links open directly. */
test('V4: the first press shows the sign-in help, and then links open directly', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const turn = await someTurn();
  const decisionRef = await seedDecision(user, { outcome: 'act', summary: unique('v4'), reasons: 'zz reason', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4242 });
  try {
    await runV4(page, turn);
  } finally {
    await cleanFixtureRows([decisionRef]);
  }
});

/** The body of V4, for the turn and a seeded decision in the rail. */
async function runV4(page: Page, turn: Turn): Promise<void> {
  await stubTraces(page.context());
  await open(page);
  const link = stripLink(page, turn.clientId);
  await expect(link).toHaveCount(1);
  const links = allLinks(page);
  expect(await links.count(), 'the strip and the rail row have links').toBeGreaterThanOrEqual(2);
  for (const one of await links.all()) {
    await expect(one, 'a link is named for the help it shows first').toHaveAccessibleName(SIGN_IN_NAME);
    await expect(one).toHaveAttribute('aria-haspopup', 'dialog');
  }

  const opened = watchTabs(page);
  await link.click();
  const dialog = popoverOf(page, HEADING);
  await expect(dialog, 'a press shows the help').toBeVisible();
  await expect(dialog).not.toHaveAttribute('aria-modal', /.*/);
  await expect(dialog.locator('p'), 'with its text').toHaveText(HELP_TEXT);
  await expect(dialog.getByRole('button', { name: DONT_SHOW, exact: true })).toBeVisible();
  const openLink = dialog.getByRole('link', { name: OPEN_NAME, exact: true });
  await expect(openLink, 'focus is on Open Visual Trace').toBeFocused();
  await expect(openLink, "which opens the link's target").toHaveAttribute('href', (await link.getAttribute('href'))!);
  await page.waitForTimeout(SETTLE_MS);
  expect(opened, 'the press opened no tab').toHaveLength(0);
  for (const one of await links.all()) {
    await expect(one, 'once seen, every link has its plain name').toHaveAccessibleName(PLAIN_NAME);
    await expect(one).not.toHaveAttribute('aria-haspopup', /.*/);
  }

  const popup = await opensTab(page, () => openLink.click());
  await expectAddress(popup, `SESSIONID=${turn.traceHeaderId}`, 'Open Visual Trace opens the turn');
  await expect(dialog, 'and closes the help').toHaveCount(0);
  await popup.close();

  const row = railOf(page).locator('li.row[data-section="decisions"] app-trace-link a').first();
  const direct = await opensTab(page, () => row.click());
  await expectAddress(direct, 'SESSIONID=', 'after that a link opens directly');
  await expect(popoverOf(page, HEADING), 'with no help').toHaveCount(0);
  await direct.close();

  await page.reload();
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(stripLink(page, turn.clientId), 'a reload of the same tab keeps it seen').toHaveAccessibleName(PLAIN_NAME);
  await expect(stripLink(page, turn.clientId)).not.toHaveAttribute('aria-haspopup', /.*/);
  const again = await opensTab(page, () => stripLink(page, turn.clientId).click());
  await expectAddress(again, `SESSIONID=${turn.traceHeaderId}`, 'and opens directly');
  await expect(page.getByText(HEADING), 'with no help').toHaveCount(0);
}

/** V5: "Don't show this again" is remembered per browser, and storage failures are tolerated. */
test("V5: Don't show this again is kept for the browser; a storage that throws still gives working help and links", async ({ page, browser }) => {
  const turn = await someTurn();
  await stubTraces(page.context());
  await open(page);
  const link = stripLink(page, turn.clientId);
  await link.click();
  const dialog = popoverOf(page, HEADING);
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: DONT_SHOW, exact: true }).click();
  await expect(dialog, "Don't show this again closes the help").toHaveCount(0);
  await expect(link, 'with focus back on the link').toBeFocused();

  const second = await page.context().newPage();
  await second.goto('/ocutalon/');
  await expect(mainOf(second)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(stripLink(second, turn.clientId), 'a second page of the same browser has plain links').toHaveAccessibleName(PLAIN_NAME);
  await expect(stripLink(second, turn.clientId)).not.toHaveAttribute('aria-haspopup', /.*/);
  const direct = await opensTab(second, () => stripLink(second, turn.clientId).click());
  await expectAddress(direct, `SESSIONID=${turn.traceHeaderId}`, 'that open directly');
  await expect(second.getByText(HEADING), 'with no help').toHaveCount(0);

  const blocked = await browser.newContext({ baseURL: process.env['OCUTALON_URL'] });
  try {
    await stubTraces(blocked);
    await blocked.addInitScript(() => {
      const refuse = (): never => {
        throw new Error('storage is blocked');
      };
      Storage.prototype.getItem = refuse;
      Storage.prototype.setItem = refuse;
    });
    const stuck = await blocked.newPage();
    await open(stuck);
    const first = stripLink(stuck, turn.clientId);
    await expect(first, 'with a storage that throws the help is still to be shown').toHaveAccessibleName(SIGN_IN_NAME);
    await first.click();
    const help = popoverOf(stuck, HEADING);
    await expect(help).toBeVisible();
    await expect(stuck.getByText(HELP_TEXT), 'it shows once').toHaveCount(1);
    const opened = await opensTab(stuck, () => help.getByRole('link', { name: OPEN_NAME, exact: true }).click());
    await expectAddress(opened, `SESSIONID=${turn.traceHeaderId}`, 'and its link works');
    await expect(first, 'after it the page remembers it was seen').toHaveAccessibleName(PLAIN_NAME);
    const after = await opensTab(stuck, () => first.click());
    await expectAddress(after, `SESSIONID=${turn.traceHeaderId}`, 'and links open directly');
    await expect(popoverOf(stuck, HEADING)).toHaveCount(0);
  } finally {
    await blocked.close();
  }
});

/** V6: on the online demo, links open directly and the help never shows. */
test('V6: on the online demo links open directly and the help never shows', async ({ page }) => {
  const turn = await someTurn();
  await stubTraces(page.context());
  await changeSnapshot(page, (snapshot) => {
    snapshot['onlineDemo'] = true;
  });
  await open(page);
  const link = stripLink(page, turn.clientId);
  await expect(link).toHaveCount(1);
  for (const one of await allLinks(page).all()) {
    await expect(one, 'a link has its plain name from the start').toHaveAccessibleName(PLAIN_NAME);
    await expect(one).not.toHaveAttribute('aria-haspopup', /.*/);
  }
  const popup = await opensTab(page, () => link.click());
  await expectAddress(popup, `SESSIONID=${turn.traceHeaderId}`, 'a press opens the page');
  await popup.close();

  await traceMenu(page).click();
  const menu = popoverOf(page, 'Visual Trace');
  await expect(menu, 'the menu is headed Visual Trace').toBeVisible();
  await expect(menu.getByRole('heading', { level: 2 })).toHaveText('Visual Trace');
  await expect(page.getByText(HEADING), 'the sign-in help never shows').toHaveCount(0);
  await expect(page.getByText(HELP_TEXT)).toHaveCount(0);
  await expect(menu.getByRole('button', { name: DONT_SHOW, exact: true })).toHaveCount(0);
  expect(await page.evaluate((key) => window.sessionStorage.getItem(key), SEEN_KEY), 'opening the menu without the help records nothing').toBeNull();
});

/** V7: the Visual Trace menu and its popover (DW-58). */
test('V7: the Visual Trace menu opens a popover that closes on Esc, a press outside and Shift+Tab', async ({ page }) => {
  await someTurn();
  await open(page);
  const button = traceMenu(page);
  const box = async (locator: Locator): Promise<{ x: number; width: number }> => (await locator.boundingBox())!;
  const badge = await box(page.locator('app-header .context-badge'));
  const menuBox = await box(button);
  const theme = await box(page.getByRole('button', { name: /^Theme: / }));
  expect(badge.x + badge.width, 'the button comes after the badge').toBeLessThanOrEqual(menuBox.x);
  expect(menuBox.x + menuBox.width, 'and before the theme button').toBeLessThanOrEqual(theme.x);
  await expect(button).toHaveAttribute('aria-haspopup', 'dialog');
  await expect(button).toHaveAttribute('aria-expanded', 'false');

  await button.click();
  await expect(button).toHaveAttribute('aria-expanded', 'true');
  const dialog = popoverOf(page, HEADING);
  await expect(dialog, 'the first open is the sign-in help').toBeVisible();
  await expect(dialog, 'a dialog named by its heading').toHaveAttribute('role', 'dialog');
  const labelledBy = await dialog.getAttribute('aria-labelledby');
  await expect(page.locator(`[id="${labelledBy}"]`), 'whose aria-labelledby points at the heading').toHaveText(HEADING);
  await expect(dialog, 'not modal').not.toHaveAttribute('aria-modal', /.*/);
  await expect(dialog.locator('p')).toHaveText(HELP_TEXT);
  const conversation = dialog.getByRole('link', { name: CONVERSATION_NAME, exact: true });
  await expect(conversation).toBeVisible();
  await expect(dialog.getByRole('button', { name: DONT_SHOW, exact: true })).toBeVisible();
  await expect(conversation, 'focus is on the first control').toBeFocused();

  await page.keyboard.press('Escape');
  await expect(dialog, 'Esc closes it').toHaveCount(0);
  await expect(button, 'with focus back on the button').toBeFocused();
  await expect(button).toHaveAttribute('aria-expanded', 'false');

  await button.click();
  const later = popoverOf(page, 'Visual Trace');
  await expect(later, 'later opens are headed Visual Trace').toBeVisible();
  await expect(page.getByText(HEADING)).toHaveCount(0);
  await expect(later.getByRole('link', { name: CONVERSATION_NAME, exact: true })).toBeFocused();
  await page.locator('app-chat-panel').click({ position: { x: 4, y: 4 } });
  await expect(later, 'a press on the chat panel closes it').toHaveCount(0);
  await expect(button).toHaveAttribute('aria-expanded', 'false');

  await button.click();
  await expect(later).toBeVisible();
  await expect(later.getByRole('link', { name: CONVERSATION_NAME, exact: true })).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(later, 'Shift+Tab out of the first control closes it').toHaveCount(0);
  await expect(button, 'with focus back on the button').toBeFocused();

  await button.click();
  await expect(later).toBeVisible();
  await button.click();
  await expect(later, 'a press on the button while it is open closes it').toHaveCount(0);
  await expect(button).toHaveAttribute('aria-expanded', 'false');
});

/** V7, continued: "Don't show this again" in the menu closes it, returns focus to the button and is kept for the browser. */
test("V7: Don't show this again in the menu closes it and is kept for the browser", async ({ page }) => {
  await someTurn();
  await open(page);
  const button = traceMenu(page);
  await button.click();
  const dialog = popoverOf(page, HEADING);
  await expect(dialog, 'the first open is the sign-in help').toBeVisible();
  await dialog.getByRole('button', { name: DONT_SHOW, exact: true }).click();
  await expect(dialog, "Don't show this again closes the menu").toHaveCount(0);
  await expect(button, 'with focus back on the button').toBeFocused();
  await expect(button).toHaveAttribute('aria-expanded', 'false');

  const second = await page.context().newPage();
  await second.goto('/ocutalon/');
  await expect(mainOf(second)).toHaveAttribute('data-snapshot', 'loaded');
  await traceMenu(second).click();
  await expect(popoverOf(second, 'Visual Trace'), 'a new tab of the same browser opens the menu with no help').toBeVisible();
  await expect(second.getByText(HEADING)).toHaveCount(0);
});

/** V7, continued: with no turn in the chat, the conversation link is disabled and does nothing. */
test('V7: with no turn the conversation link is disabled and opens nothing', async ({ page }) => {
  await changeSnapshot(page, (snapshot) => {
    snapshot['chat'] = [];
  });
  await helpSeen(page);
  await open(page);
  await traceMenu(page).click();
  const dialog = popoverOf(page, 'Visual Trace');
  await expect(dialog).toBeVisible();
  const conversation = dialog.getByRole('link', { name: CONVERSATION_NAME, exact: true });
  await expect(conversation).toHaveAttribute('aria-disabled', 'true');
  await expect(conversation, 'with no href').not.toHaveAttribute('href', /.*/);
  await expect(conversation, 'it stays focusable').toBeFocused();
  const opened = watchTabs(page);
  await conversation.click({ force: true });
  await page.waitForTimeout(SETTLE_MS);
  expect(opened, 'and opens nothing').toHaveLength(0);
});

/** V8: "Open my conversation in Visual Trace" opens the current day's thread at its newest turn, and follows a later turn. */
test('V8: Open my conversation opens the newest turn, and a turn that arrives moves the link', async ({ page }) => {
  const first = await postTurn(api, cursor, 2, 'links');
  const second = await postTurn(api, cursor, 3, 'links');
  await helpSeen(page);
  await open(page);
  await traceMenu(page).click();
  const dialog = popoverOf(page, 'Visual Trace');
  await expect(dialog).toBeVisible();
  const conversation = dialog.getByRole('link', { name: CONVERSATION_NAME, exact: true });
  await expect(conversation, "the link is the newest turn's").toHaveAttribute('href', second.traceUrl);
  expect(second.traceItemIndex, 'the newest turn sits after the earlier one').toBeGreaterThan(first.traceItemIndex);

  const third = await postTurn(api, cursor, 4, 'links');
  await expect(conversation, 'a turn that arrives moves the link with no reload').toHaveAttribute('href', third.traceUrl, { timeout: APPLIED_MS });

  const popup = await opensTab(page, () => conversation.click());
  await expectAddress(popup, `SESSIONID=${third.traceHeaderId}`, 'the new tab opens the newest turn');
  const drawn = await drawnMessages(popup);
  expect(third.traceItemIndex, 'the newest turn has a higher place than the first one posted').toBeGreaterThan(first.traceItemIndex);
  expectDrawn(drawn, third.traceHeaderId, third.traceItemIndex, 'Open my conversation');
  await expect(dialog, 'pressing the link closes the popover').toHaveCount(0);
});
