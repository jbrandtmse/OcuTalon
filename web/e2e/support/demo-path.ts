import { expect, type BrowserContext, type Locator, type Page } from '@playwright/test';

import { README_ACCOUNT } from '../sign-in/helpers';
import { STATE } from './api';
import { CARD_MS, replyOf } from './floor';
import { chk, irisScript, quoted, readApproval } from './iris';
import { clock } from './page';
import { TRACE_PAGE, drawnMessages, signOutTrace, type Turn } from './trace';

/**
 * What the UJ-1 runs share (Stories 11.1, 11.7 and 11.10): the page's locators, the parts of /state that they read, the newest done turn,
 * the model switch and the checks of steps 2 to 5 as functions. The web run (e2e/demo-path/02-watch.spec.ts to 08-quiet-outcomes.spec.ts)
 * and the online run (e2e-online/demo-path/demo-path.spec.ts) import them, so each step's checks are written once. Story 11.10 adds what
 * the failure paths of 07 need: an incident found by its ref, a Break the feed press, the refusal seam (the test-only pause of
 * FailurePoller and the marker on the new failures' bodies), the fallback card's checks, the trace opening, Dismiss, Reject on the phone,
 * and the count of the actions an untrusted email must not cause (actionsSince).
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

/** Break the feed's refusal while an Orders incident is open (the 409 message, and the hint under the inactive button). */
export const IN_PROGRESS = 'Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.';
/** The fallback card's notice when the model refuses the diagnosis (the catalog's fallbackReason.refusal in the notice sentence). */
export const FALLBACK_NOTICE = "I couldn't work out the cause (the model declined to answer), so I'm not proposing a fix. Nothing was changed.";
/** The guide's step 4 text after a rejection. */
export const GUIDE_REJECTED = 'Rejected. Nothing was changed. Dismiss the incident in the chat, then press Break the feed again.';
/** The guide's step 4 text on a fallback incident. */
export const GUIDE_FALLBACK = "OcuTalon couldn't diagnose this run, so there's nothing to approve. Open the trace to see why, or dismiss the incident and press Break the feed again.";

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

export const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
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
 * `card` is the incident's card (default: the page's one incident card; 07 passes the card of a later incident by its ref, since the
 * chat then holds earlier ones). Returns the approval request's Ref.
 */
export async function expectIncidentAwaitingApproval(page: Page, card: Locator = incidentCard(page)): Promise<string> {
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

/** The simulated phone's notice that asks for the incident's request (the one that still has its buttons), once it shows. */
async function requestNotice(page: Page): Promise<{ notice: Locator; phone: Locator }> {
  const notice = phoneNotes(page).filter({ has: page.getByRole('button', { name: APPROVE_NAME, exact: true }) });
  await expect(notice, 'the simulated phone has the notice').toHaveCount(1, { timeout: CARD_MS });
  const noticeKey = (await notice.getAttribute('data-key')) ?? '';
  expect(noticeKey, "the notice's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
  return { notice, phone: page.locator(`app-simulated-phone .notification[data-key="${noticeKey}"]`) };
}

/**
 * Presses the notice's Approve or Reject for the request `key` on the simulated phone and waits until the request is answered. Returns
 * the answered row, the notice (found again by its Ref, since its buttons are replaced by the answer line) and the answer's HH:MM
 * (the row's AnsweredAt, in the instance zone: UTC on a stack).
 */
async function pressOnPhone(page: Page, key: string, action: 'approve' | 'reject'): Promise<{ answered: Awaited<ReturnType<typeof readApproval>>; phone: Locator; time: string }> {
  const { notice, phone } = await requestNotice(page);
  await notice.getByRole('button', { name: action === 'approve' ? APPROVE_NAME : REJECT_NAME, exact: true }).click();
  await expect.poll(async () => readApproval(key).then((one) => one.at), { message: 'the request is answered', timeout: 30_000 }).not.toBe('');
  const answered = await readApproval(key);
  expect(answered.channel, 'from the simulated phone').toBe('phone');
  return { answered, phone, time: answered.at.slice(11, 16) };
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
  const { answered, phone, time } = await pressOnPhone(page, key, 'approve');
  // The phone's line is the server's text (HH:MM in the instance zone, UTC on a stack, then the zone suffix the caller names); the card writes the time in the page's en-GB locale and UTC zone (no leading zero before ten), which the run's browser context sets.
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

/**
 * The rejection (Story 11.10; FR-8, FR-24, UX-DR104): presses Reject on the simulated phone's notice for the request `key` of the
 * incident card `card`. The request is rejected from the phone (the row: state rejected, channel phone); the phone then reads "Rejected
 * from the simulated phone at HH:MM. Nothing was changed." (with `zone` after the time) and the card's status line the same time in en-GB
 * and UTC; the card has neither button, the chip stays Open, the rail counts no request and the guide stays at step 4 with its rejected
 * text.
 */
export async function rejectOnPhone(page: Page, key: string, card: Locator, zone = ''): Promise<void> {
  const request = card.locator('[data-part="approval"]');
  const { answered, phone, time } = await pressOnPhone(page, key, 'reject');
  expect(answered.state, 'the request is rejected').toBe('rejected');
  await expect(phone.locator('p[data-part="answer"]'), 'the phone says so').toHaveText(`Rejected from the simulated phone at ${time}${zone}. Nothing was changed.`, { timeout: CARD_MS });
  await expect(request.locator('p.status'), 'so does the card').toHaveText(`Rejected from the simulated phone at ${clock(answered.at, 'en-GB', 'UTC')}. Nothing was changed.`, { timeout: CARD_MS });
  await expect(request.getByRole('button', { name: APPROVE_NAME, exact: true }), 'the card has no Approve').toHaveCount(0);
  await expect(request.getByRole('button', { name: REJECT_NAME, exact: true }), 'and no Reject').toHaveCount(0);
  await expect(card.locator('.chip-row .chip'), 'the incident is Open again').toHaveText('Open', { timeout: CARD_MS });
  await expect(approvalCount(page), 'the rail counts no request (spoken)').toHaveText('Approval requests, 0', { timeout: CARD_MS });
  const guide = guideRegion(page);
  await expect(guide.getByRole('button', { name: 'Step 4, Approve, current', exact: true }), 'the guide stays at step 4').toHaveCount(1, { timeout: CARD_MS });
  await expect(guide.locator('.prompt-text'), 'with its rejected text').toHaveText(`"${GUIDE_REJECTED}"`, { timeout: CARD_MS });
}

/** What /state holds of one chat incident (the parts these cases read). */
export interface IncidentRow {
  ref: string;
  state: string;
  openVariant: string;
  fallbackReason: string;
  requests: Array<{ ref: string; state: string }>;
  diagnosisHeader: number;
}

/** The chat incidents of the page's /state, newest last, as the rows these cases read. */
export async function incidentRows(page: Page): Promise<IncidentRow[]> {
  const { snapshot } = await readState(page);
  return snapshot.chat
    .filter((item) => item.type === 'incident')
    .map((item) => {
      const payload = item.payload as {
        ref?: string;
        state?: string;
        openVariant?: string;
        fallbackReason?: string;
        requests?: Array<{ ref: string; state: string }>;
        traceTargets?: { diagnosis?: { traceHeaderId?: number } };
      };
      return {
        ref: payload.ref ?? '',
        state: payload.state ?? '',
        openVariant: payload.openVariant ?? '',
        fallbackReason: payload.fallbackReason ?? '',
        requests: payload.requests ?? [],
        diagnosisHeader: payload.traceTargets?.diagnosis?.traceHeaderId ?? 0,
      };
    });
}

/** The refs of the chat incidents of /state. */
export async function incidentRefs(page: Page): Promise<string[]> {
  return (await incidentRows(page)).map((row) => row.ref);
}

/** The /state row of the incident with the ref; the test fails when the chat holds none. */
export async function incidentRow(page: Page, ref: string): Promise<IncidentRow> {
  const row = (await incidentRows(page)).find((one) => one.ref === ref);
  expect(row, `/state holds the incident ${ref}`).toBeDefined();
  return row!;
}

/** The card of the incident with the ref in the chat. */
export const incidentCardOf = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);

/** Polls /state for 90 s until the chat holds an incident whose ref is not among `known`, and returns its ref. */
export async function newIncidentRef(page: Page, known: readonly string[]): Promise<string> {
  let found = '';
  await expect
    .poll(
      async () => {
        found = (await incidentRefs(page)).find((ref) => !known.includes(ref)) ?? '';
        return found;
      },
      { message: 'a new incident shows in /state', timeout: 90_000, intervals: [1_000, 2_000] },
    )
    .not.toBe('');
  return found;
}

/** The page's own Break the feed: the button is active within CARD_MS, then the click, and the POST answers 200 with state `sent`. */
export async function pressBreakFeed(page: Page): Promise<void> {
  await expect(breakFeedButton(page), 'Break the feed is active').not.toHaveAttribute('aria-disabled', 'true', { timeout: CARD_MS });
  const answer = page.waitForResponse((response) => response.request().method() === 'POST' && new URL(response.url()).pathname === BREAK_FEED);
  await breakFeedButton(page).click();
  const sent = await answer;
  expect(sent.status(), await sent.text()).toBe(200);
  expect(((await sent.json()) as { state: string }).state, 'the press is sent').toBe('sent');
}

/** Runs one line of the test seam in OCUTALON and returns its CHK value. */
async function seam(name: string, line: string): Promise<string> {
  const lines = await irisScript(line);
  return chk(lines, name) ?? `no answer (${lines.join(' ')})`;
}

/** Pauses (1) or resumes (0) FailurePoller (Test.Demo.Production.PauseReading); the call must report success. */
async function pauseReading(pause: 0 | 1): Promise<void> {
  const lines = await irisScript(['Set sc=##class(OcuTalon.Test.Demo.Production).PauseReading(' + pause + ')', 'Write !,"CHK|pause|",$System.Status.IsOK(sc)', 'If $System.Status.IsError(sc) Write !,"CHK|why|",$Translate($System.Status.GetErrorText(sc),$Char(13,10)," ")'].join('\n'));
  expect(chk(lines, 'pause'), `FailurePoller ${pause === 1 ? 'is paused' : 'reads again'} (${lines.join(' ')})`).toBe('1');
}

/**
 * The CI mock's refusal of the diagnosis (Story 11.10; the mock only, because only it can be made to refuse): presses Break the feed
 * with FailurePoller paused, waits until the run's 50 failed orders are in the production, marks their bodies' OrderNumber with
 * `[[mock:refusal]]` (the evidence pack reads its sample body from the stored message, so the marker reaches the newest user text of the
 * diagnosis request) and lets FailurePoller read again, also when a check fails. The product is unchanged.
 */
export async function breakFeedForRefusal(page: Page, session: { ref: string; trace: string }): Promise<void> {
  const failedBefore = (await breakFeedLeft(session)).failed;
  expect(failedBefore, 'the count of failed orders before the press').toMatch(/^\d+$/);
  const before = Number(failedBefore);
  try {
    await pauseReading(1);
    await pressBreakFeed(page);
    await expect
      .poll(async () => Number((await breakFeedLeft(session)).failed), { message: "OCUORDERS holds the run's 50 new failed orders", timeout: 60_000, intervals: [1_000, 2_000] })
      .toBe(before + 50);
    const marked = await seam('marked', `Write !,"CHK|marked|",##class(OcuTalon.Test.Demo.Production).MarkNewFailures(${quoted(session.trace)},50,"[[mock:refusal]]")`);
    expect(marked, 'the 50 new failed orders carry the refusal marker').toBe('50');
  } finally {
    await pauseReading(0);
  }
}

/**
 * The fallback card of a refused diagnosis (Story 11.10; FR-4, UX-DR45, UX-DR104): chip Open and the Fallback flag, the headline, the
 * notice with the refusal's reason, "Failures:" with one group line, Show details, Dismiss and one footer trace link, and no cause,
 * evidence line, fix or approval request. Elsewhere the rail counts no request, no phone notice has an Approve button and the guide is
 * at step 4 with its fallback text. The mock's words are exact (the caller runs it on the mock only).
 */
export async function expectFallbackIncident(page: Page, card: Locator): Promise<void> {
  await expect(card, 'the incident card shows').toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.chip-row .chip'), 'its chip says Open').toHaveText('Open');
  await expect(card.locator('.chip-row app-fallback-flag'), 'with the Fallback flag').toHaveCount(1);
  await expect(card.getByRole('heading', { level: 3 }), 'the headline counts the failed orders').toHaveText(/^50 orders failed since \d{1,2}:\d{2}/);
  for (const part of ['p.cause', 'p.evidence-line', 'p.fix', '[data-part="approval"]']) {
    await expect(card.locator(part), `no ${part}: the card proposes nothing`).toHaveCount(0);
  }
  await expect(card.locator('p.notice'), 'the notice says why').toHaveText(FALLBACK_NOTICE);
  await expect(card.locator('p.failures'), 'the failures are listed').toHaveText('Failures:');
  const groups = card.locator('ul.groups li');
  await expect(groups, 'in one group').toHaveCount(1);
  await expect(groups.first(), "which holds the item, the count, the error's summary and the first time").toHaveText(/: 50, '.+', first at \d{1,2}:\d{2}$/);
  await expect(card.getByRole('button', { name: 'Show details', exact: true }), 'Show details').toHaveCount(1);
  await expect(card.getByRole('button', { name: 'Dismiss', exact: true }), 'and Dismiss').toHaveCount(1);
  await expect(card.locator('.footer app-trace-link a'), 'the footer has one trace link').toHaveCount(1);

  await expect(approvalCount(page), 'the rail counts no request (spoken)').toHaveText('Approval requests, 0');
  await expect(phoneNotes(page).getByRole('button', { name: APPROVE_NAME, exact: true }), 'no phone notice asks for an approval').toHaveCount(0);
  const guide = guideRegion(page);
  await expect(guide.getByRole('button', { name: 'Step 4, Approve, current', exact: true }), 'the guide is at step 4').toHaveCount(1, { timeout: CARD_MS });
  await expect(guide.locator('.prompt-text'), 'with its fallback text').toHaveText(`"${GUIDE_FALLBACK}"`);
}

/**
 * Opens the trace through the guide's step 5 (the web run's 06, and 07 after a refusal): the guide's link has the incident's diagnosis
 * session as its address (`header`, the diagnosis trace header of /state), is named for the sign-in help it shows first, the dialog
 * "Sign in to Visual Trace" shows, its link opens a tab at the trace page, which Visual Trace draws with that session, and the tab is
 * closed. With `step` upcoming the step is selected first (as DW-340 allows). The trace application is signed out at the end, also on
 * a failure (it holds a licence connection until then).
 */
export async function openTraceFromGuide(page: Page, context: BrowserContext, header: number, step: 'current' | 'upcoming' = 'current'): Promise<void> {
  try {
    const guide = guideRegion(page);
    const button = guide.getByRole('button', { name: `Step 5, Open the trace, ${step}`, exact: true });
    await expect(button, `the guide is at step 5 (${step})`).toHaveCount(1, { timeout: CARD_MS });
    if (step === 'upcoming') await button.click();
    const link = guide.locator('.prompt app-trace-link a');
    await expect(link, "its address is the incident's diagnosis session").toHaveAttribute('href', `${TRACE_PAGE}${header}`);
    await expect(link, 'on a local install it is named for the sign-in help it shows first').toHaveAccessibleName('Open the trace (shows sign-in help first)');
    await link.click();
    const dialog = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(dialog, 'the sign-in help shows first').toBeVisible();

    const opened = context.waitForEvent('page');
    await dialog.getByRole('link', { name: 'Open Visual Trace (opens in a new tab)', exact: true }).click();
    const popup = await opened;
    await popup.waitForLoadState('domcontentloaded');
    await expect.poll(() => new URL(popup.url()).pathname + new URL(popup.url()).search, { message: 'a tab opened at the incident trace', timeout: 30_000 }).toBe(`${TRACE_PAGE}${header}`);
    const drawn = await drawnMessages(popup);
    expect(drawn.ids, `Visual Trace draws the diagnosis session (it draws ${drawn.ids.join(' ')})`).toContain(String(header));
    await popup.close();
    // The sign-out ends the page's own session too, so the finish that the open brings must have reached the page first.
    if (step === 'current') await expect(guide.locator('.finish'), 'the finish replaces the prompt bar').toBeVisible({ timeout: CARD_MS });
  } finally {
    await signOutTrace(page.request);
  }
}

/**
 * Dismisses the Open incident `ref` on its card `card` (Story 11.10; FR-24): before the press Break the feed is inactive with the hint
 * IN_PROGRESS; the press posts to the incident's dismiss route, which answers 200; the chip reads Closed and Break the feed is active,
 * with no hint.
 */
export async function dismissIncident(page: Page, card: Locator, ref: string): Promise<void> {
  await expect(breakFeedButton(page), 'before the Dismiss, Break the feed is inactive').toHaveAttribute('aria-disabled', 'true');
  await expect(page.locator('app-break-feed-box .hint'), 'with its hint').toHaveText(IN_PROGRESS);
  const route = `/ocutalon/api/v1/incidents/${ref}/dismiss`;
  const answer = page.waitForResponse((response) => response.request().method() === 'POST' && new URL(response.url()).pathname === route);
  await card.getByRole('button', { name: 'Dismiss', exact: true }).click();
  const dismissed = await answer;
  expect(dismissed.status(), 'the Dismiss answers 200').toBe(200);
  await expect(card.locator('.chip-row .chip'), 'the chip reads Closed').toHaveText('Closed', { timeout: CARD_MS });
  await expect(breakFeedButton(page), 'Break the feed is active again').not.toHaveAttribute('aria-disabled', 'true', { timeout: CARD_MS });
  await expect(page.locator('app-break-feed-box .hint'), 'with no hint').toHaveCount(0);
}

/** The stack's UTC time as Bridge.Time.NowUtc writes it (YYYY-MM-DDThh:mm:ssZ). */
export async function stackNow(): Promise<string> {
  const lines = await irisScript('Write !,"CHK|now|",##class(OcuTalon.Bridge.Time).NowUtc()');
  const now = chk(lines, 'now') ?? '';
  expect(now, "the stack's time").toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  return now;
}

/** The actions an email must not cause (NFR-14, counted instance-wide since a stack time): approval requests raised, fix runs started and settings changed. */
export interface ActionsSince {
  approvals: number;
  fixRuns: number;
  settingChanges: number;
}

/**
 * Counts every ApprovalRequest with RaisedAt, every FixRun with StartedAt and every Setting with UpdatedAt at or after `since` (a
 * stackNow time; all three write Bridge.Time.NowUtc's format), whatever their owner or session.
 */
export async function actionsSince(since: string): Promise<ActionsSince> {
  const count = (name: string, table: string, column: string): string =>
    [
      'Set a=##class(%SQL.Statement).%New()',
      `Set sc=a.%Prepare("SELECT COUNT(*) FROM ${table} WHERE ${column} >= ?")`,
      `Set r=a.%Execute(${quoted(since)}) Do r.%Next()`,
      `Write !,"CHK|${name}|",r.%GetData(1)`,
    ].join('\n');
  const lines = await irisScript(
    [count('approvals', 'OcuTalon_Bridge_Data.ApprovalRequest', 'RaisedAt'), count('fixRuns', 'OcuTalon_Data.FixRun', 'StartedAt'), count('settings', 'OcuTalon_Data.Setting', 'UpdatedAt')].join('\n'),
  );
  const read = (name: string): number => {
    const value = chk(lines, name) ?? '';
    expect(value, `the ${name} could not be counted (${lines.join(' ')})`).toMatch(/^\d+$/);
    return Number(value);
  };
  return { approvals: read('approvals'), fixRuns: read('fixRuns'), settingChanges: read('settings') };
}
