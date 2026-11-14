import { expect, test, type Locator, type Page } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { changeSnapshot } from '../support/api';
import { DRY_RUN, TOMORROW_AT_1413, incidentOf, noticeOnPhone, phoneOf, raise, refOf, today } from '../support/approvals';
import { dropPhone } from '../support/devices';
import { CARD_MS, applied, composerOf, inMs, loadedAfter, mainOf } from '../support/floor';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted, readApproval, sendNotification, sinkEvent } from '../support/iris';
import { announcedTexts, recordAnnouncements } from '../support/page';

/**
 * Story 25.5, the approval request that the signed-in user may not answer, on the page and on the simulated phone, in a real browser against the live sign-in stack
 * (the fixture roles exist with no resources, and the stack is in demo mode). ZzRoleTarget (OCUTALON_ROLETARGET_USER) holds OcuTalonUser only and ZzApprover
 * (OCUTALON_APPROVER_USER) holds OcuTalonUser and the fixture OcuTalonApprover; each request is a fixture row that needs OcuTalonApprover, owned by the signed-in user's own
 * session, whose `approval` event reaches the page through BridgeSink, which asks the real role check for that session.
 *   V1  the real path, as the user without the role: the card and the phone show no Approve or Reject and the status "Only an approver can answer this request.";
 *   V2  the real path, as the holder: both buttons show, and Approve gives "Approved from the web chat at {time}" on the card and the phone within 5 s;
 *   V3  a request that is answerable at load and loses its role afterwards: Approve is refused, and the card and the phone switch to the server's sentence with no buttons; when the role comes back and the server publishes the request again, the buttons return;
 *   V4  a mocked approver kind (`/v1/state` carries the request with `answerable` false and `approverKind` resend, as the server will answer once Story 26.4 names kinds): the sentence of
 *       that kind on the card and the phone, with no buttons; it writes nothing on the server.
 * Each case removes its rows and phone messages.
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB', viewport: { width: 1280, height: 900 } });

const FALLBACK = 'Only an approver can answer this request.';
const RESEND = 'Only an approver for resends can answer this request.';
const APPROVE = 'Approve: repair and resend 50 orders';
const REJECT = 'Reject: repair and resend 50 orders';
const NEEDS_APPROVER = { requiredRole: 'OcuTalonApprover' };
const WITHIN_MS = 5000;

/** The request card of a ref in the chat. */
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);

/** The two buttons of a card or of a phone message, by their names. */
const approveOf = (scope: Locator): Locator => scope.getByRole('button', { name: APPROVE, exact: true });
const rejectOf = (scope: Locator): Locator => scope.getByRole('button', { name: REJECT, exact: true });

/** Signs the fixture user in with the announcements recorded and waits for the loaded page with the phone. */
async function open(page: Page, kind: 'ROLETARGET' | 'APPROVER'): Promise<string> {
  const { user, password } = fixtureUser(kind);
  await recordAnnouncements(page);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
  await expect(phoneOf(page), 'the stack is in demo mode: the phone shows').toBeVisible();
  return user;
}

/** Changes the role that a request needs, in the row. */
async function needs(request: string, role: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(${quoted(request)})`,
      `Set r.RequiredRole=${quoted(role)}`,
      'Write !,"CHK|role|",$System.Status.IsOK(r.%Save())',
    ].join('\n'),
  );
  expect(chk(lines, 'role'), 'the row needs another role now').toBe('1');
}

test('V1: a user without the role sees no Approve or Reject on the card or the phone, and the fallback sentence', async ({ page }) => {
  const rows: string[] = [];
  const start = inMs(-2000);
  const user = fixtureUser('ROLETARGET').user;
  try {
    await open(page, 'ROLETARGET');
    const incident = refOf('V1');
    const request = await raise(page, user, rows, incident, [], NEEDS_APPROVER);
    const card = requestCard(page, request);
    await expect(card, 'the card is drawn').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.getByText(FALLBACK, { exact: true }), 'the status reads the sentence').toBeVisible({ timeout: CARD_MS });
    await expect(approveOf(card), 'no Approve on the card').toHaveCount(0);
    await expect(rejectOf(card), 'no Reject on the card').toHaveCount(0);
    await expect(card.getByRole('button', { name: /^(Approve|Reject)/ }), 'no button of the answer is on the card to reach by Tab').toHaveCount(0);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    await expect(message.getByText(FALLBACK, { exact: true }), 'the phone reads the sentence').toBeVisible({ timeout: CARD_MS });
    await expect(message.getByRole('button', { name: /^(Approve|Reject)/ }), 'and has no Approve or Reject').toHaveCount(0);
    expect(await readApproval(request).then((row) => row.state), 'the request is still pending').toBe('pending');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

test('V2: the holder of the approver role sees both buttons and answers, and every copy says so within 5 s', async ({ page }) => {
  const rows: string[] = [];
  const start = inMs(-2000);
  const user = fixtureUser('APPROVER').user;
  try {
    await open(page, 'APPROVER');
    const incident = refOf('V2');
    const request = await raise(page, user, rows, incident, [], NEEDS_APPROVER);
    const card = requestCard(page, request);
    await expect(card, 'the card is drawn').toHaveCount(1, { timeout: CARD_MS });
    await expect(approveOf(card), 'Approve shows').toHaveCount(1);
    await expect(rejectOf(card), 'and Reject').toHaveCount(1);
    const { message } = await noticeOnPhone(page, user, request, incident, inMs(-120_000));
    await expect(approveOf(message), 'the phone has Approve').toHaveCount(1);
    await expect(rejectOf(message), 'and Reject').toHaveCount(1);
    await approveOf(card).click();
    // The press waits about 5 s for the task that a fixture row's hold would have, so the card's status comes with the reply; the phone follows within 5 s of it.
    await expect(card.locator('p.status'), 'the card says it').toHaveText(/^Approved from the web chat at \d{1,2}:\d{2}$/, { timeout: 30_000 });
    const row = await readApproval(request);
    expect(row.state, 'the request is approved').not.toBe('pending');
    // The answered notification that IncidentManager sends after an answer is sent by the case, as in answers.spec X3.
    await sendNotification(user, { kind: 'answered', catalogKey: 'answered.approved', slots: { channel: 'web', time: row.at }, approvalRef: request, incidentRef: incident });
    await expect(message.locator('p[data-part="answer"]'), 'and so does the phone, within 5 s').toHaveText(/^Approved from the web chat at \d{1,2}:\d{2}\.$/, { timeout: WITHIN_MS });
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

test('V3: a request that loses its role after the page loaded it is refused on Approve, and the card and the phone switch to the server\'s sentence', async ({ page }) => {
  const rows: string[] = [];
  const start = inMs(-2000);
  const user = fixtureUser('APPROVER').user;
  try {
    await open(page, 'APPROVER');
    const incident = refOf('V3');
    const request = await raise(page, user, rows, incident, [], NEEDS_APPROVER);
    const card = requestCard(page, request);
    await expect(approveOf(card), 'it is answerable at load').toHaveCount(1, { timeout: CARD_MS });
    const second = await raise(page, user, rows, incident, [request], NEEDS_APPROVER, false);
    const { message } = await noticeOnPhone(page, user, second, incident, inMs(-120_000), 'approval');
    await expect(approveOf(message), 'the phone has Approve for the second request').toHaveCount(1);
    await needs(request, 'OcuTalonViewer');
    await needs(second, 'OcuTalonViewer');

    await approveOf(card).click();
    await expect(card.getByText(FALLBACK, { exact: true }), 'the card switches to the server\'s sentence').toHaveCount(1, { timeout: WITHIN_MS });
    await expect(card.locator('.buttons'), 'with no buttons').toHaveCount(0);
    await expect.poll(() => announcedTexts(page).then((texts) => texts.filter((text) => text === FALLBACK).length), { message: 'the sentence is announced once' }).toBe(1);

    await approveOf(message).click();
    await expect(message.getByText(FALLBACK, { exact: true }), 'the phone does the same').toHaveCount(1, { timeout: WITHIN_MS });
    await expect(message.getByRole('button', { name: /^(Approve|Reject)/ }), 'with no buttons').toHaveCount(0);
    for (const ref of [request, second]) {
      expect(await readApproval(ref).then((row) => row.state), 'nothing was answered').toBe('pending');
    }

    // The role comes back and the server publishes the requests again: its own answer decides again, so the refused state ends and Approve and Reject return on the card and the phone.
    await needs(request, 'OcuTalonApprover');
    await needs(second, 'OcuTalonApprover');
    await applied(page, await sinkEvent(user, 'approval.raised', { ref: request }));
    await applied(page, await sinkEvent(user, 'approval.raised', { ref: second }));
    await expect(approveOf(card), 'a new payload for the card ends its refused state').toHaveCount(1, { timeout: WITHIN_MS });
    await expect(rejectOf(card)).toHaveCount(1);
    await expect(approveOf(message), 'and for the phone message').toHaveCount(1, { timeout: WITHIN_MS });
    await expect(rejectOf(message)).toHaveCount(1);
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

test('V4: a request of the kind resend that the user may not answer says so with the sentence of that kind, on the card and the phone', async ({ page }) => {
  const incident = refOf('V4');
  const request = refOf('V4r');
  await changeSnapshot(page, (snapshot) => {
    const rail = snapshot['rail'] as { approvals: unknown[] };
    snapshot['demoMode'] = true;
    snapshot['chat'] = [{ type: 'incident', payload: incidentOf(incident, [{ ref: request }]) }];
    rail.approvals = [
      {
        ref: request,
        kind: 'fix',
        state: 'pending',
        incidentRef: incident,
        dryRun: DRY_RUN,
        raisedAt: today('14:13:00'),
        expiresAt: TOMORROW_AT_1413,
        answerable: false,
        approverKind: 'resend',
      },
    ];
    snapshot['phone'] = [
      {
        ref: 'zzv4phone',
        direction: 'out',
        text: '50 orders failed since 14:12. Data format change. I can repair the order date and resend 50 orders. Approve?',
        approvalRef: request,
        createdAt: today('14:13:00'),
      },
    ];
  });
  await open(page, 'APPROVER');
  const card = requestCard(page, request);
  await expect(card.getByText(RESEND, { exact: true }), 'the card reads the sentence of the kind').toBeVisible({ timeout: CARD_MS });
  await expect(card.getByRole('button', { name: /^(Approve|Reject)/ }), 'with no buttons').toHaveCount(0);
  const message = phoneOf(page).locator('.notification', { hasText: '50 orders failed' });
  await expect(message.getByText(RESEND, { exact: true }), 'and so does the phone').toBeVisible({ timeout: CARD_MS });
  await expect(message.getByRole('button', { name: /^(Approve|Reject)/ })).toHaveCount(0);
});
