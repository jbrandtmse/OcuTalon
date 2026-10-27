import { expect, type APIRequestContext, type Page } from '@playwright/test';

import { MESSAGES, STATE, post, sessionEvents } from './api';
import { chk, fixtureUser, irisScript, type FixtureKind } from './iris';

/**
 * What the specs that open Visual Trace share (Stories 2.9 and 2.13): the turn as /state and the live stream carry it, the newest turn of a
 * user's chat, a message posted and waited for until its turn is done, Visual Trace opened as a fixture user, and a reading of the
 * messages that the opened page draws. trace.spec.ts and links.spec.ts use them against the real Visual Trace pages.
 */

/** The page of Visual Trace in the trace application of OCUTALON, up to the session parameter. */
export const TRACE_PAGE = '/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=';

/** The sign-out address of the trace application: ends the whole sign-in group of the cookies that reach it (AD-13). */
const TRACE_SIGN_OUT = '/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?IRISLogout=end';

/**
 * Signs the trace application out for the context behind `api` (the context's own cookies: `page.request`, or a request context that
 * made the trace requests). A trace-application page holds one licence connection for its user and client address until its session
 * ends (measured in Story 4.7, DW-146), and the stack has 8, so a case that opened one signs it out when it ends. IRISLogout=end ends the
 * context's whole sign-in group, the page's own session included: call it when the case is over.
 */
export async function signOutTrace(api: APIRequestContext): Promise<void> {
  const response = await api.get(TRACE_SIGN_OUT);
  expect(response.status(), 'the trace sign-out answers').toBeLessThan(500);
}

/**
 * The number of CSP connections that the licence counts for the IRIS user (%SYSTEM.License:UserList, column CSPCon, summed over the
 * user's rows, whatever the case of the name), 0 when the user has none. It reads through irisScript, which a licence-exhausted stack
 * refuses (no terminal), and says so.
 */
export async function traceSessions(user: string): Promise<number> {
  if (!/^[A-Za-z0-9_]+$/.test(user)) throw new Error('a fixture user name is letters, digits and underscore');
  const lines = await irisScript(
    [
      'Set rs=##class(%ResultSet).%New("%SYSTEM.License:UserList")',
      'Do rs.Execute()',
      'Set n=0',
      `While rs.Next() { If $ZConvert($Piece(rs.Get("UserId"),"@",1),"U")=$ZConvert("${user}","U") Set n=n+rs.Get("CSPCon") }`,
      'Write !,"CHK|csp|",n',
    ].join('\n'),
  );
  const count = chk(lines, 'csp');
  if (count === undefined) throw new Error('the licence is exhausted: irisScript was refused');
  return Number(count);
}

/** A chat turn as /state and the live stream carry it. */
export interface Turn {
  ref: string;
  clientId: string;
  /** The decision the turn shows, with its own trace target. */
  decision?: { ref: string; traceHeaderId?: number; traceUrl?: string };
  state: string;
  traceHeaderId: number;
  traceNamespace: string;
  traceItemIndex: number;
  traceItemIndexNoEvents: number;
  traceUrl: string;
}

/** The page of a position, for a page size. */
export const ceil = (index: number, size: number): number => Math.ceil(index / size);

/** The newest turn of the user's chat, from /state. */
export async function newestTurn(api: APIRequestContext): Promise<Turn> {
  const response = await api.get(STATE);
  expect(response.status(), await response.text()).toBe(200);
  const state = (await response.json()) as { chat: Array<{ type: string; payload: Turn }> };
  const turns = state.chat.filter((item) => item.type === 'chat.message');
  expect(turns.length, 'the chat holds the turns that the set-up posted').toBeGreaterThan(0);
  return turns[turns.length - 1].payload;
}

/** The last Seq of the session stream that a spec has read: postTurn reads after it and moves it. */
export interface Cursor {
  seq: number;
}

/** Posts one message and waits for its turn to be done; the done turn. The client id carries the label. */
export async function postTurn(api: APIRequestContext, cursor: Cursor, n: number, label = 'thread'): Promise<Turn> {
  const clientId = `zz-${label}-${Date.now().toString(36)}-${n}`;
  const response = await post(api, MESSAGES, { clientId, text: `zz ${label} turn ${n}`, fromGuide: false });
  expect(response.status(), await response.text()).toBe(202);
  const events = await sessionEvents(api, cursor.seq, (seen) => seen.some((event) => event.type === 'chat.message' && event.payload['clientId'] === clientId && event.payload['state'] === 'done'), 30);
  cursor.seq = Math.max(cursor.seq, ...events.map((event) => event.seq));
  const done = events.find((event) => event.type === 'chat.message' && event.payload['clientId'] === clientId && event.payload['state'] === 'done');
  expect(done, `turn ${n} is done`).toBeDefined();
  return done!.payload as unknown as Turn;
}

/** Fills in the sign-in form of the trace application as the fixture user of the kind, when the page shows it. */
export async function signInToTrace(page: Page, kind: FixtureKind): Promise<void> {
  const { user, password } = fixtureUser(kind);
  const form = page.locator('input[name=IRISUsername]');
  if ((await form.count()) > 0) {
    await form.fill(user);
    await page.locator('input[name=IRISPassword]').fill(password);
    await page.locator('input[name=IRISPassword]').press('Enter');
  }
}

/** Opens a Visual Trace URL as the fixture user of the kind: the sign-in form of the trace application first, when it is shown. */
export async function openTrace(page: Page, url: string, kind: FixtureKind): Promise<void> {
  await page.goto(url);
  await signInToTrace(page, kind);
}

/** What the page's embedded SVG draws: the IDs of its messages in order, the label [n] of each, and the address the page loaded the SVG from. */
export interface Drawn {
  ids: string[];
  labels: Record<string, string>;
  src: string;
}

/**
 * The messages that the page's embedded SVG draws, once it draws any: the g elements with an all-digit id, read from the SVG
 * document of the embed (or object) that Visual Trace's svgFrame renders, each with the label [n] that the page prints on its row,
 * which is the place of the message in Visual Trace's own list.
 */
export async function drawnMessages(page: Page): Promise<Drawn> {
  let drawn: Drawn = { ids: [], labels: {}, src: '' };
  await expect
    .poll(
      async () => {
        drawn = await page.evaluate(() => {
          const frame = document.querySelector('embed[type="image/svg+xml"], object[type="image/svg+xml"]') as ({ getSVGDocument?: () => Document | null } & Element) | null;
          const svg = frame?.getSVGDocument?.();
          const groups = svg ? Array.from(svg.querySelectorAll('g[id]')).filter((g) => /^\d+$/.test(g.id)) : [];
          const labels: Record<string, string> = {};
          for (const group of groups) {
            const label = Array.from(group.querySelectorAll('text.MsgLabel')).map((text) => text.textContent ?? '').find((text) => /^\[\d+\]$/.test(text));
            if (label) labels[group.id] = label;
          }
          return { ids: groups.map((g) => g.id), labels, src: frame?.getAttribute('src') ?? frame?.getAttribute('data') ?? '' };
        });
        return drawn.ids.length;
      },
      { message: 'the page draws messages', timeout: 30_000, intervals: [500, 1000, 2000] },
    )
    .toBeGreaterThan(0);
  return drawn;
}

/** The page draws the turn, and prints the place that Core.Trace.Position gave it on the turn's row. */
export function expectDrawn(drawn: Drawn, headerId: number, position: number, label: string): void {
  const where = `${label} (the SVG came from ${drawn.src}; it draws ${drawn.ids.map((id) => `${id}${drawn.labels[id] ?? ''}`).join(' ')})`;
  expect(drawn.ids, `${where}: the page draws the turn`).toContain(String(headerId));
  expect(drawn.labels[String(headerId)], `${where}: and prints its place`).toBe(`[${position}]`);
}
