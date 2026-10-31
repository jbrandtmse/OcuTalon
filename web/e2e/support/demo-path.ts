import { expect, type Locator, type Page } from '@playwright/test';

import { README_ACCOUNT } from '../sign-in/helpers';
import { STATE } from './api';
import { chk, irisScript } from './iris';
import type { Turn } from './trace';

/**
 * What the UJ-1 runs share (Story 11.1): the page's locators, the parts of /state that they read, and the newest done turn. The web
 * run (e2e/demo-path/02-watch.spec.ts to 06-trace.spec.ts) and the online run (e2e-online/demo-path/demo-path.spec.ts) import them.
 * The page's texts are written out in the specs, as the independent oracle of the page's own; the guide's watch prompt, which both
 * runs send, is written out here (WATCH_PROMPT).
 */

export const guideSend = (page: Page): Locator => page.locator('app-demo-guide [data-guide-focus="action"]');
export const composer = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
export const rail = (page: Page): Locator => page.locator('app-status-rail');
export const breakFeedButton = (page: Page): Locator => page.locator('app-break-feed-box app-server-button button');
export const approvalCard = (page: Page): Locator => page.locator('app-chat-panel [data-part="approval"]');
export const incidentCard = (page: Page): Locator => page.locator('app-chat-panel [data-part="incident"]');
export const phoneNotes = (page: Page): Locator => page.locator('app-simulated-phone .notification');
export const approvalRows = (page: Page): Locator => rail(page).locator('li.row[data-row-key^="approvals:"]');
export const approvalCount = (page: Page): Locator => rail(page).locator('[data-section="approvals"] h3 .visually-hidden');
export const checkRow = (page: Page): Locator => rail(page).locator('li.row[data-section="checks"]').filter({ hasText: 'Orders production' });

/** The parts of /state that these cases read. */
export interface Snapshot {
  epoch: string;
  streams: { session: number; instance: number };
  chat: Array<{ type: string; payload: Record<string, unknown> }>;
  rail: { approvals: Array<{ ref: string; state: string }>; checks: Array<{ ref: string; displayName: string }>; reminders: Array<{ ref: string }> };
  telegram: { displayName: string };
  phone?: Array<{ ref: string; approvalRef: string }>;
  mailbox?: Array<{ ref: string }>;
  guide?: unknown;
}

/** The page's own /state, parsed, and its text as served (for the searches of A's refs). */
export async function readState(page: Page): Promise<{ snapshot: Snapshot; text: string }> {
  const response = await page.request.get(STATE);
  expect(response.status(), 'the state is served').toBe(200);
  const text = await response.text();
  return { snapshot: JSON.parse(text) as Snapshot, text };
}

/** The session's newest chat turn, once it is done (its reply, decision and trace target are in /state then). */
export async function doneTurn(page: Page): Promise<Turn> {
  let turn: Turn | undefined;
  await expect
    .poll(
      async () => {
        const turns = (await readState(page)).snapshot.chat.filter((item) => item.type === 'chat.message');
        turn = turns.length === 0 ? undefined : (turns[turns.length - 1]!.payload as unknown as Turn);
        return turn?.state;
      },
      { message: 'the turn is done', timeout: 90_000, intervals: [1_000, 2_000] },
    )
    .toBe('done');
  return turn!;
}

/** The guide's watch prompt (step 1 of the demo guide), written out here as the oracle of the page's own. */
export const WATCH_PROMPT = 'Watch the Orders production and only tell me if something needs me.';

/**
 * The message that starts a watch of the Orders production on the CI mock: the watch prompt behind the marker of the mock scenario
 * watch-act-orders, keyed by `key` (lower-case letters and digits, new for each run). A countdown armed for `watch-act-orders:<key>` with
 * 1 (devices.ts armCountdown) gives the Triage request its first reply (Act) and the turn its watch start and its text.
 */
export function watchMessage(key: string): string {
  if (!/^[a-z0-9]+$/.test(key)) throw new Error('the marker key is lower-case letters and digits');
  return `[[mock:watch-act-orders:${key}]] ${WATCH_PROMPT}`;
}

/** The README session's Ref and TraceRef, read from the stack. */
export async function readmeSession(): Promise<{ ref: string; trace: string }> {
  const lines = await irisScript([`Set s=##class(OcuTalon.Data.Session).ForUser("${README_ACCOUNT.user}",.sc)`, 'Write !,"CHK|ref|",s.Ref', 'Write !,"CHK|trace|",s.TraceRef'].join('\n'));
  const ref = chk(lines, 'ref') ?? '';
  const trace = chk(lines, 'trace') ?? '';
  expect(ref, "the README session's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(trace, "the README session's TraceRef").toMatch(/^[A-Za-z0-9_-]{22}$/);
  return { ref, trace };
}

/** What a Break the feed press leaves behind: the session's runs ("<count>:<states>"), and the production headers that carry its TraceRef (all, and the failed ones at OrdersFromPartner). */
export interface BreakFeedLeft {
  runs: string;
  headers: string;
  failed: string;
}

/** Reads what Break the feed left for the session (readmeSession's Ref and TraceRef). */
export async function breakFeedLeft(session: { ref: string; trace: string }): Promise<BreakFeedLeft> {
  const lines = await irisScript(
    [
      `Write !,"CHK|runs|",##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs("${session.ref}")`,
      `Write !,"CHK|headers|",##class(OcuTalon.Test.Demo.Production).Headers("${session.trace}").%Size()`,
      `Write !,"CHK|failed|",##class(OcuTalon.Test.Demo.Production).Count("${session.trace}","OrdersFromPartner",8)`,
    ].join('\n'),
  );
  return { runs: chk(lines, 'runs') ?? '', headers: chk(lines, 'headers') ?? '', failed: chk(lines, 'failed') ?? '' };
}

/** The error code and message of a refused press, with its status. */
export async function refusal(response: { status(): number; text(): Promise<string> }): Promise<{ status: number; code: string; message: string }> {
  const body = JSON.parse(await response.text()) as { error: { code: string; message: string } };
  return { status: response.status(), code: body.error.code, message: body.error.message };
}

/** The route of Break the feed. */
export const BREAK_FEED = '/ocutalon/api/v1/demo/break-feed';
