import { expect, test, type APIRequestContext } from '@playwright/test';

import { STATE } from '../support/api';
import { chk, fixtureUser, irisScript, setTraceSettings, type TraceSettings } from '../support/iris';
import { TRACE_PAGE, ceil, drawnMessages, expectDrawn, newestTurn, openTrace, postTurn, type Cursor } from '../support/trace';
import { signInOverHttp } from '../sign-in/helpers';

/**
 * Story 2.9, Visual Trace opened on a turn (T1 to T4), in a real browser against a real stack and the real Visual Trace pages. Every
 * case signs in as the thread fixture user that test-sign-in.sh created (OCUTALON_THREAD_USER; the user role and the trace role),
 * whose session no other spec reads. The set-up posts messages through the API, one turn at a time, until the newest
 * turn sits beyond the 45th item of its trace session (at least one turn after the seed, at most 15 turns in all, so a thread that a
 * run before left longer is no different), after seeding the session with event-log, rule-log and
 * I/O-log rows: the first turn's session gets, before the later turns exist, an event and a rule row whose host first appears on a
 * later header (which Visual Trace does not draw before it), the same for a host that has appeared (which it draws), and two I/O rows
 * (which the page of the trace role does not draw at all: the role may not select from the I/O log).
 * Each case asks /state for the link of the newest turn, opens it in the browser and reads the message elements that the page's
 * embedded SVG draws (the g elements with a numeric id), which must hold the turn's header with the label [n] that the page prints on
 * its row, the position the server gave the turn (traceItemIndex, or traceItemIndexNoEvents with Show events off). The cases that change the user's Visual
 * Trace settings (the page size and "Show events") also try the sizes at which the turn is the first item of the second page and the
 * last item of the first, so that a position that is one item off lands on the wrong page; they put the settings back in finally.
 * The seeded rows are removed after the last case.
 */
test.describe.configure({ mode: 'serial' });

/** The tag of every row the cases seed. */
const TAG = 'zz e2e trace';

/** The most turns the set-up posts. */
const MOST_TURNS = 15;

/** The position beyond which the newest turn must sit. */
const BEYOND = 45;

let api: APIRequestContext;
const cursor: Cursor = { seq: 0 };
/** The trace session of the user's day: the ID of its first Item header. */
let thread = '';
/** The Item header of the first turn that the set-up posted. */
let firstHeader = 0;

/**
 * Seeds the trace session with log rows around its first headers, as one script: for the first header (h1) and the first headers
 * that target WebChatOut (w) and Notify (y), an event row or rule row logged at the header's own time with the header's own ID as its
 * MessageId sorts just after that header. So WebChatOut's event and Notify's rule row at h1 are drawn nowhere before the header
 * that makes the host appear, Conversation's event at h1 is drawn, and the rows at w and y are drawn once the host is on the diagram.
 * The I/O rows are received before h1 for the request h1, and before h2 for the request h2. The script first waits (up to 30
 * seconds) until the session holds a header to Notify and one to WebChatOut, which the turn sends after its done event.
 */
async function seed(session: string): Promise<void> {
  expect(session).toMatch(/^\d+$/);
  const event = (host: string, at: string): string =>
    `Set e=##class(Ens.Util.Log).%New() Set e.SessionId=t,e.TimeLogged=$List(h(${at}),2),e.ConfigName="${host}",e.MessageId=$List(h(${at}),1),e.Type=4,e.Text="${TAG}" Set sc=e.%Save() If $System.Status.IsError(sc) Set bad=1`;
  const rule = (host: string, at: string): string =>
    `Set r=##class(Ens.Rule.Log).%New() Set r.SessionId=t,r.TimeExecuted=$List(h(${at}),2),r.RuleName="${TAG}",r.ConfigName="${host}",r.CurrentHeaderId=$List(h(${at}),1) Set sc=r.%Save() If $System.Status.IsError(sc) Set bad=1`;
  const io = (host: string, request: string, received: string): string =>
    `Set o=##class(Ens.Util.IOLog).%New() Set o.SessionId=t,o.ConfigName="${host}",o.CorrespondingRequestId=$List(h(${request}),1),o.TimeReceived=${received},o.Annotation="${TAG}" Set sc=o.%Save() If $System.Status.IsError(sc) Set bad=1`;
  const lines = await irisScript(
    [
      `Set t=${session}`,
      'Set bad=0',
      'For k=1:1:30 { Kill h Set n=0,w=0,y=0 Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID, TimeCreated, TargetConfigName FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID",t) While rs.%Next() { Set n=n+1,h(n)=$ListBuild(rs.%Get("ID"),rs.%Get("TimeCreated")) If (w=0)&&(rs.%Get("TargetConfigName")="WebChatOut") { Set w=n } If (y=0)&&(rs.%Get("TargetConfigName")="Notify") { Set y=n } } Quit:(n>=2)&&(w>0)&&(y>0) Hang 1 }',
      'If (n<2)||(w=0)||(y=0) { Write !,"CHK|seed|missing|",n,"|",w,"|",y Halt }',
      event('WebChatOut', '1'),
      event('Conversation', '1'),
      rule('Notify', '1'),
      event('WebChatOut', 'w'),
      rule('Notify', 'y'),
      io('WebChatIn', '1', '"2000-01-01 00:00:00.000"'),
      io('Conversation', '2', '$List(h(1),2)'),
      'Write !,"CHK|seed|",bad',
    ].join('\n'),
  );
  expect(chk(lines, 'seed'), `the trace session was seeded (${lines.join(' ')})`).toBe('0');
}

/** Removes the rows that seed made. */
async function unseed(session: string): Promise<void> {
  if (!/^\d+$/.test(session)) return;
  await irisScript(
    [
      `Set t=${session}`,
      `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Ens_Util.Log WHERE SessionId = ? AND Text = ?",t,"${TAG}")`,
      `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Ens_Rule.Log WHERE SessionId = ? AND RuleName = ?",t,"${TAG}")`,
      `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Ens_Util.IOLog WHERE SessionId = ? AND Annotation = ?",t,"${TAG}")`,
      'Write !,"CHK|unseed|1"',
    ].join('\n'),
  );
}

/** Changes the thread user's Visual Trace settings, runs the body, and puts the settings back. */
async function withSettings(settings: TraceSettings, body: () => Promise<void>): Promise<void> {
  const { user } = fixtureUser('THREAD');
  const before = await setTraceSettings(user, settings);
  try {
    await body();
  } finally {
    await setTraceSettings(user, before);
  }
}

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(240_000);
  api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  const { user, password } = fixtureUser('THREAD');
  await signInOverHttp(api, user, password);
  const state = (await (await api.get(STATE)).json()) as { streams: { session: number } };
  cursor.seq = state.streams.session;

  const first = await postTurn(api, cursor, 0);
  firstHeader = first.traceHeaderId;
  const lines = await irisScript(`Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT SessionId FROM Ens.MessageHeader WHERE %ID = ?",${firstHeader})\nDo rs.%Next()\nWrite !,"CHK|thread|",rs.%Get("SessionId")`);
  thread = chk(lines, 'thread') ?? '';
  await seed(thread);
  let newest = await postTurn(api, cursor, 1);
  for (let n = 2; n < MOST_TURNS && !(newest.traceItemIndex > BEYOND); n += 1) {
    newest = await postTurn(api, cursor, n);
  }
  expect(newest.traceItemIndex, `the newest turn sits beyond item ${BEYOND} after at most ${MOST_TURNS} turns`).toBeGreaterThan(BEYOND);
});

test.afterAll(async () => {
  await unseed(thread);
  await api?.dispose();
});

/** T1: the link to a late turn of a thread of more than 40 items opens Visual Trace on that turn, events shown. */
test('T1: the link to a late turn of a thread of more than 40 items opens Visual Trace on that turn', async ({ page }) => {
  const turn = await newestTurn(api);
  expect(turn.traceItemIndex, 'the turn is beyond the 40th item').toBeGreaterThan(40);
  expect(turn.traceNamespace).toBe('OCUTALON');
  expect(turn.traceUrl, 'the link names the turn and the page of its position at 40 items a page').toBe(`${TRACE_PAGE}${turn.traceHeaderId}&PAGE=${ceil(turn.traceItemIndex, 40)}`);
  expect(ceil(turn.traceItemIndex, 40), 'a page after the first').toBeGreaterThanOrEqual(2);
  await openTrace(page, turn.traceUrl, 'THREAD');
  expectDrawn(await drawnMessages(page), turn.traceHeaderId, turn.traceItemIndex, '40 items a page');

  for (const size of [turn.traceItemIndex - 1, turn.traceItemIndex]) {
    await withSettings({ itemsPerPage: size }, async () => {
      const edge = await newestTurn(api);
      expect(edge.traceUrl, `${size} items a page: the link follows`).toBe(`${TRACE_PAGE}${edge.traceHeaderId}&PAGE=${ceil(edge.traceItemIndex, size)}`);
      await openTrace(page, edge.traceUrl, 'THREAD');
      expectDrawn(await drawnMessages(page), edge.traceHeaderId, edge.traceItemIndex, `${size} items a page`);
    });
  }
});

/** T2: with the viewer's page size 10 the link's PAGE follows and still opens on the turn. */
test("T2: with the viewer's page size 10 the link's PAGE follows and still opens on the turn", async ({ page }) => {
  await withSettings({ itemsPerPage: 10 }, async () => {
    const turn = await newestTurn(api);
    expect(turn.traceUrl, 'the page follows the viewer\'s page size').toBe(`${TRACE_PAGE}${turn.traceHeaderId}&PAGE=${ceil(turn.traceItemIndex, 10)}`);
    expect(ceil(turn.traceItemIndex, 10), 'a page far beyond the fourth').toBeGreaterThanOrEqual(5);
    await openTrace(page, turn.traceUrl, 'THREAD');
    expectDrawn(await drawnMessages(page), turn.traceHeaderId, turn.traceItemIndex, '10 items a page');
  });
});

/** T3: with Show events off the link counts no event or rule rows and still opens on the turn. */
test('T3: with Show events off the link counts no event or rule rows and still opens on the turn', async ({ page }) => {
  await withSettings({ showEvents: 0 }, async () => {
    const turn = await newestTurn(api);
    expect(turn.traceItemIndexNoEvents, 'the position without event and rule rows is below the one with them').toBeLessThan(turn.traceItemIndex);
    expect(turn.traceUrl, 'the link counts the position without events').toBe(`${TRACE_PAGE}${turn.traceHeaderId}&PAGE=${ceil(turn.traceItemIndexNoEvents, 40)}`);
    await openTrace(page, turn.traceUrl, 'THREAD');
    expectDrawn(await drawnMessages(page), turn.traceHeaderId, turn.traceItemIndexNoEvents, '40 items a page, events hidden');

    for (const size of [turn.traceItemIndexNoEvents - 1, turn.traceItemIndexNoEvents]) {
      await withSettings({ itemsPerPage: size }, async () => {
        const edge = await newestTurn(api);
        expect(edge.traceUrl, `${size} items a page: the link follows`).toBe(`${TRACE_PAGE}${edge.traceHeaderId}&PAGE=${ceil(edge.traceItemIndexNoEvents, size)}`);
        await openTrace(page, edge.traceUrl, 'THREAD');
        expectDrawn(await drawnMessages(page), edge.traceHeaderId, edge.traceItemIndexNoEvents, `${size} items a page, events hidden`);
      });
    }
  });
});

/** T4: a day's turns are one Visual Trace session: the late turn's session, at page 1, draws the first turn's Item header of the day. */
test("T4: a day's turns are one Visual Trace session", async ({ page }) => {
  const turn = await newestTurn(api);
  await openTrace(page, `${TRACE_PAGE}${turn.traceHeaderId}&PAGE=1`, 'THREAD');
  const drawn = await drawnMessages(page);
  expect(drawn.ids, "page 1 of the late turn's session draws the day's first Item header").toContain(thread);
});
