import { expect, type Locator, type Page } from '@playwright/test';

import { README_ACCOUNT } from '../sign-in/helpers';
import { STATE } from './api';
import { CARD_MS, replyOf } from './floor';
import { chk, irisScript, readApproval } from './iris';
import { clock } from './page';
import type { Turn } from './trace';

/**
 * What the UJ-1 runs share (Stories 11.1 and 11.7): the page's locators, the parts of /state that they read, the newest done turn, the
 * model switch and the checks of steps 2 to 5 as functions. The web run (e2e/demo-path/02-watch.spec.ts to 06-trace.spec.ts) and the
 * online run (e2e-online/demo-path/demo-path.spec.ts) import them, so each step's checks are written once.
 * The page's texts are written out in the specs and here, as the independent oracle of the page's own; the guide's watch prompt, which
 * both runs send, is written out here (WATCH_PROMPT).
 *
 * The model switch (OCUTALON_DEMO_PATH_MODEL, REL-2 against the real model): `mock` (the default, also when unset or empty) checks the
 * outcomes and every text that the CI mock writes; `real` checks each decision with expectDecision only (a strip with an outcome, its
 * reasons and its trace link, and no Fallback flag, never which outcome) and matches the texts that a model's output fills by their
 * shape. Any other value throws when this module loads, so a run fails before its first step. On `real` the specs never point or restore
 * the runners' keys and never wait for the runners' records.
 */

/** The model the run is against: `mock` or `real`. */
export type DemoPathModel = 'mock' | 'real';

/** Parses the value of OCUTALON_DEMO_PATH_MODEL; unset or empty is `mock`, and anything but `mock` and `real` throws. */
export function parseModel(value: string | undefined): DemoPathModel {
  if (value === undefined || value === '' || value === 'mock') return 'mock';
  if (value === 'real') return 'real';
  throw new Error(`OCUTALON_DEMO_PATH_MODEL is mock or real, not "${value}"`);
}

export const MODEL: DemoPathModel = parseModel(process.env['OCUTALON_DEMO_PATH_MODEL']);
/** True on the CI mock, where the outcomes and the mock's texts are checked. */
export const ON_MOCK: boolean = MODEL === 'mock';

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

/** The ClientId of the session's newest chat turn, or "" when it has none. */
export async function newestClientId(page: Page): Promise<string> {
  const turns = (await readState(page)).snapshot.chat.filter((item) => item.type === 'chat.message');
  return turns.length === 0 ? '' : String((turns[turns.length - 1]!.payload as unknown as Turn).clientId);
}

/**
 * The session's newest chat turn, once it is done (its reply, decision and trace target are in /state then). With `after`, the ClientId
 * of the turn that was newest before the press (newestClientId), only a newer turn counts.
 */
export async function doneTurn(page: Page, after = ''): Promise<Turn> {
  let turn: Turn | undefined;
  await expect
    .poll(
      async () => {
        const turns = (await readState(page)).snapshot.chat.filter((item) => item.type === 'chat.message');
        turn = turns.length === 0 ? undefined : (turns[turns.length - 1]!.payload as unknown as Turn);
        return turn !== undefined && turn.clientId !== after ? turn.state : undefined;
      },
      { message: 'the turn is done', timeout: 90_000, intervals: [1_000, 2_000] },
    )
    .toBe('done');
  return turn!;
}

/** The guide's watch prompt (step 1 of the demo guide), written out here as the oracle of the page's own. */
export const WATCH_PROMPT = 'Watch the Orders production and only tell me if something needs me.';

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

/**
 * The decision of a strip (REL-2, the real-model rule): exactly one strip, with an outcome chip that has text, no Fallback flag, at least
 * one reason with text and one trace link. It never says which outcome; a caller that runs on the CI mock adds that.
 */
export async function expectDecision(strip: Locator, what: string): Promise<void> {
  await expect(strip, `${what}: one decision strip shows`).toHaveCount(1, { timeout: 30_000 });
  await expect(strip.locator('app-outcome-chip .chip'), `${what}: the strip has its outcome chip`).toHaveText(/\S/);
  await expect(strip.locator('app-fallback-flag'), `${what}: and no Fallback flag`).toHaveCount(0);
  await expect(strip.locator('.reason').first(), `${what}: it shows a reason`).toHaveText(/\S/);
  await expect(strip.locator('app-trace-link a'), `${what}: and one trace link`).toHaveCount(1);
}

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const reminderRows = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true }).locator('li.row[data-section="reminders"]');

/** The name of the Approve button of the incident's request: the diagnosis's fix words on the mock, its shape on the real model. */
const APPROVE_NAME: string | RegExp = ON_MOCK ? 'Approve: repair and resend 50 orders' : /^Approve: /;
const REJECT_NAME: string | RegExp = ON_MOCK ? 'Reject: repair and resend 50 orders' : /^Reject: /;
/** The result band's text: the fix's count on the mock, its shape on the real model. */
const WENT_THROUGH: string | RegExp = ON_MOCK ? 'All 50 orders went through.' : /^All \d+ \S+ went through\.$/;
/** The same text inside a longer one (the phone's message holds more than the band): a filter's regular expression is not anchored. */
const WENT_THROUGH_IN: string | RegExp = ON_MOCK ? 'All 50 orders went through.' : /All \d+ \S+ went through\./;

/** Checks that the message of the guide's prompt shows as the guide's own, the exact prompt with the caption. */
export async function expectGuideMessage(page: Page, prompt: string): Promise<void> {
  const message = page.locator('main app-user-message').filter({ hasText: prompt });
  await expect(message, 'the prompt shows as a message').toHaveCount(1);
  await expect(message.locator('.bubble'), 'which is the exact prompt').toHaveText(prompt);
  await expect(message.locator('.when'), 'with the guide caption').toHaveText(/^From the demo guide/);
}

/**
 * UJ-1 step 2 (the web run's 02, the online run's step 2): on a signed-in page at step 1 of a session that watches nothing, presses the
 * guide's own Send. The prompt shows as the guide's message; the reply's strip passes expectDecision (on the mock: chip Act with the
 * mock's reason, and the reply "I'll watch the Orders production and stay quiet unless something needs you."); the "Orders production"
 * check row shows, Break the feed is active, and the guide reads step 1 done and step 2 current. It does not wait for the watch's first
 * run (02's last test does).
 */
export async function watchThroughGuide(page: Page): Promise<void> {
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(guideSend(page), "the guide's Send is usable").not.toHaveAttribute('aria-disabled', 'true');
  const before = await newestClientId(page);
  await guideSend(page).click();
  await expectGuideMessage(page, WATCH_PROMPT);

  const turn = await doneTurn(page, before);
  const reply = replyOf(page, turn.clientId);
  const strip = reply.locator('app-decision-strip');
  await expectDecision(strip, "the watch reply's decision");
  if (ON_MOCK) {
    await expect(strip.locator('app-outcome-chip .chip'), 'its chip is Act: the mock answered the Triage request with its own scenario').toHaveText('Act');
    await expect(strip.locator('.reason').first(), 'with the mock\'s reason').toHaveText('The CI mock acts on the request to watch the Orders production.');
    await expect(reply.locator('.text'), "above it the turn's own text: the mock's reply 1").toContainText("I'll watch the Orders production and stay quiet unless something needs you.");
  } else {
    await expect(reply.locator('.text'), 'the reply has its text').toHaveText(/\S/);
  }

  await expect(checkRow(page), 'the "Orders production" check row shows').toHaveCount(1, { timeout: 90_000 });
  await expect(breakFeedButton(page), 'Break the feed is active').not.toHaveAttribute('aria-disabled', 'true', { timeout: 30_000 });
  const guide = guideRegion(page);
  await expect(guide.getByRole('button', { name: 'Step 1, Watch, done', exact: true }), 'the guide marks step 1 done').toHaveCount(1);
  await expect(guide.getByRole('button', { name: 'Step 2, Reminder, current', exact: true }), 'and step 2 current').toHaveCount(1);
}

/**
 * UJ-1 step 3 (the web run's 03, the online run's step 3): on a signed-in page that watches, opens "Step 2, Reminder" (upcoming or
 * current, DW-340) and presses its Send. The prompt "Remind me in 1 minute to stretch." shows as the guide's message; the reply's strip
 * passes expectDecision (on the mock: chip Act with the mock's reason, and the reply "The CI mock set the reminder."); one Reminders
 * row shows with its countdown (on the mock it is "stretch"; on the real model the model writes its text); and the guide marks step 2
 * done.
 */
export async function reminderThroughGuide(page: Page): Promise<void> {
  const prompt = 'Remind me in 1 minute to stretch.';
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const guide = guideRegion(page);
  await guide.getByRole('button', { name: /^Step 2, Reminder, (upcoming|current)$/ }).click();
  const shown = guide.locator('.prompt');
  await expect(shown.locator('.prompt-text'), 'step 2 shows its exact prompt').toHaveText(`"${prompt}"`);
  const before = await newestClientId(page);
  await shown.getByRole('button', { name: 'Send', exact: true }).click();
  await expectGuideMessage(page, prompt);

  const turn = await doneTurn(page, before);
  const reply = replyOf(page, turn.clientId);
  const strip = reply.locator('app-decision-strip');
  await expectDecision(strip, "the reminder reply's decision");
  if (ON_MOCK) {
    await expect(strip.locator('app-outcome-chip .chip'), 'its chip is Act: the mock answered the Triage request with its own scenario').toHaveText('Act');
    await expect(strip.locator('.reason').first(), "with the mock's reason").toHaveText('The CI mock acts on the request to set a reminder.');
    await expect(reply.locator('.text'), 'the reply shows').toContainText('The CI mock set the reminder.');
  } else {
    await expect(reply.locator('.text'), 'the reply has its text').toHaveText(/\S/);
  }

  const row = reminderRows(page);
  await expect(row, 'one reminder shows under Reminders').toHaveCount(1, { timeout: 30_000 });
  await expect(row.locator('.lead'), ON_MOCK ? 'it is stretch' : 'it has its text').toHaveText(ON_MOCK ? /^stretch$/i : /\S/);
  await expect(row.locator('.countdown'), 'with its countdown').toHaveText(/^in \d+ (s|min)$/);
  await expect(guide.getByRole('button', { name: 'Step 2, Reminder, done', exact: true }), 'and the guide marks step 2 done').toHaveCount(1);
}

/**
 * UJ-1 step 4's card (the web run's 04, the online run's step 4): after Break the feed, within 90 s the chat shows one incident card
 * awaiting approval with its headline, cause, evidence line, dry run and its two buttons, the simulated phone the incident notice with
 * the same two buttons, the rail "Approval requests (1)" with one row, and the guide is at step 4. The cause, the evidence line, the
 * count and the buttons' words are the diagnosis's: exact on the mock, by shape on the real model. It does not press Break the feed.
 * Returns the approval request's Ref.
 */
export async function expectIncidentAwaitingApproval(page: Page): Promise<string> {
  const card = incidentCard(page);
  await expect(card, 'one incident card shows').toHaveCount(1, { timeout: 90_000 });
  await expect(card.locator('.chip-row .chip'), 'its chip says Awaiting approval').toHaveText('Awaiting approval');
  await expect(card.getByRole('heading', { level: 3 }), 'the headline counts the failed orders').toHaveText(ON_MOCK ? /^50 orders failed since \d{1,2}:\d{2}/ : /^\d+ \S+ failed since \d{1,2}:\d{2}/);
  if (ON_MOCK) {
    await expect(card.locator('p.cause'), 'the cause is the model diagnosis').toHaveText('The partner now sends the order date as month, day and year with slashes, and the production expects year, month and day with dashes.');
    await expect(card.locator('p.evidence-line'), 'the evidence line groups the failures').toHaveText('Data format change \u00B7 OrderDate \u00B7 50 failures grouped into this incident');
  }

  const request = card.locator('[data-part="approval"]');
  await expect(request, 'with its approval request').toHaveCount(1, { timeout: CARD_MS });
  await expect(request.locator('.dry-label'), 'the dry run').toHaveText('Dry run');
  await expect(request.locator('.dry-count'), 'counts the orders').toHaveText(ON_MOCK ? '50 orders affected' : /\S/);
  await expect(request.locator('.dry-note'), 'and says nothing has changed').toHaveText('Nothing has changed yet.');
  await expect(request.getByRole('button', { name: APPROVE_NAME, exact: true }), 'Approve').toHaveCount(1);
  await expect(request.getByRole('button', { name: REJECT_NAME, exact: true }), 'and Reject').toHaveCount(1);
  const key = (await request.getAttribute('data-key')) ?? '';
  expect(key, "the request's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);

  const notice = phoneNotes(page).filter({ has: page.getByRole('button', { name: APPROVE_NAME, exact: true }) });
  await expect(notice, 'the simulated phone has the incident notice').toHaveCount(1, { timeout: CARD_MS });
  await expect(notice.getByRole('button', { name: REJECT_NAME, exact: true }), 'with its own Reject').toHaveCount(1);

  await expect(approvalCount(page), 'the rail counts the request (spoken)').toHaveText('Approval requests, 1');
  await expect(rail(page).locator('[data-section="approvals"] h3'), 'as "Approval requests (1)"').toContainText('Approval requests (1)');
  await expect(approvalRows(page), 'and lists one row').toHaveCount(1);
  await expect(guideRegion(page).getByRole('button', { name: 'Step 4, Approve, current', exact: true }), 'the guide is at step 4').toHaveCount(1);
  return key;
}

/**
 * UJ-1 step 5 (the web run's 05, the online run's step 5): presses Approve on the simulated phone's notice for the request `key`. The
 * request is answered from the phone; the phone then reads "Approved from the simulated phone at HH:MM." (with `zone` after the time:
 * none on a local install, " ET" on the online demo) and the card the same time in en-GB and UTC, the context the run sets. Within
 * 120 s the card's band says all orders went through ("All 50 orders went through." on the mock, its shape on the real model), its
 * audit line "Recorded in the IRIS audit log." follows and the chip says Resolved; the phone gets the result as a message with no
 * buttons, and the request's row leaves the rail.
 */
export async function approveOnPhone(page: Page, key: string, zone = ''): Promise<void> {
  const card = incidentCard(page);
  const request = card.locator('[data-part="approval"]');
  const notice = phoneNotes(page).filter({ has: page.getByRole('button', { name: APPROVE_NAME, exact: true }) });
  await expect(notice, 'the simulated phone has the notice').toHaveCount(1, { timeout: CARD_MS });
  const noticeKey = (await notice.getAttribute('data-key')) ?? '';
  expect(noticeKey, "the notice's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
  const phone = page.locator(`app-simulated-phone .notification[data-key="${noticeKey}"]`);

  await notice.getByRole('button', { name: APPROVE_NAME, exact: true }).click();
  await expect.poll(async () => readApproval(key).then((one) => one.at), { message: 'the request is answered', timeout: 30_000 }).not.toBe('');
  const answered = await readApproval(key);
  expect(answered.channel, 'from the simulated phone').toBe('phone');
  // The phone's line is the server's text (HH:MM in the instance zone, UTC on a stack, then the zone suffix the caller names); the card writes the time in the page's en-GB locale and UTC zone (no leading zero before ten), which the run's browser context sets.
  const time = answered.at.slice(11, 16);
  await expect(phone.locator('p[data-part="answer"]'), 'the phone says so').toHaveText(`Approved from the simulated phone at ${time}${zone}.`, { timeout: CARD_MS });
  await expect(request.locator('p.status'), 'so does the card').toHaveText(`Approved from the simulated phone at ${clock(answered.at, 'en-GB', 'UTC')}`, { timeout: CARD_MS });

  const band = card.locator('[data-part="result"]');
  await expect(band.locator('.text'), 'the band says all went through').toHaveText(WENT_THROUGH, { timeout: 120_000 });
  await expect(card.locator('p.audit'), 'and the audit line follows it').toHaveText('Recorded in the IRIS audit log.');
  await expect(card.locator('.chip-row .chip'), 'the chip says Resolved').toHaveText('Resolved', { timeout: CARD_MS });

  const result = phoneNotes(page).filter({ hasText: WENT_THROUGH_IN });
  await expect(result, 'the phone shows the result as a message').toHaveCount(1, { timeout: CARD_MS });
  await expect(result.getByRole('button'), 'with no buttons').toHaveCount(0);
  await expect(approvalRows(page), "the request's row left the rail").toHaveCount(0, { timeout: CARD_MS });
}
