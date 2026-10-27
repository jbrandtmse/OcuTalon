import { expect, test } from '@playwright/test';

import { STATE, post, sessionEvents } from '../support/api';
import { raise, refOf } from '../support/approvals';
import { dropPhone, phoneMessage } from '../support/devices';
import { CARD_MS, inMs } from '../support/floor';
import { chk, cleanFixtureRows, irisScript, sendNotification } from '../support/iris';
import { README_ACCOUNT, signInOverHttp, signInReadme } from '../sign-in/helpers';
import { notBuilt } from './not-built';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const BREAK_FEED = '/ocutalon/api/v1/demo/break-feed';
const NOT_WATCHING = 'Ask OcuTalon to watch the Orders production first (step 1).';
const IN_PROGRESS = 'Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.';

/** The error code and message of a refused press. */
async function refusal(response: { status(): number; text(): Promise<string> }): Promise<{ status: number; code: string; message: string }> {
  const body = JSON.parse(await response.text()) as { error: { code: string; message: string } };
  return { status: response.status(), code: body.error.code, message: body.error.message };
}

/**
 * UJ-1 step 4: the incident and its approval request. The first test is Break the feed over real HTTP (Story 4.3, REL-2), with the README account. The stack has no Lane A watch yet (Epic 11 turns the chat's
 * watch on), so the test seeds the README session's Orders check with the fixture that stands in for it. In order: the first press is
 * refused (409 not_watching, with its hint, and nothing is written or sent); after the watch the press is sent (200 {state, startedAt}); /events holds breakfeed.progress
 * sending and sent with that startedAt and then a guide.state, the stage waiting; a second press is refused (409 incident_in_progress);
 * and the Orders production holds 50 failed orders for the session's TraceRef, none at the warehouse. Every assertion about the stream
 * is relative to the cursor taken at the start. NFR-7's 60 s is measured in the rehearsal, not here.
 */
test("Break the feed sends the session's 50 orders, which fail for real in the Orders production", { tag: '@floor' }, async ({ request }) => {
  test.setTimeout(120_000);
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const snapshot = await request.get(STATE);
  expect(snapshot.status(), await snapshot.text()).toBe(200);
  const cursor = ((await snapshot.json()) as { streams: { session: number } }).streams.session;

  const identity = await irisScript([`Set s=##class(OcuTalon.Data.Session).ForUser("${README_ACCOUNT.user}",.sc)`, 'Write !,"CHK|ref|",s.Ref', 'Write !,"CHK|trace|",s.TraceRef'].join('\n'));
  const ref = chk(identity, 'ref') ?? '';
  const trace = chk(identity, 'trace') ?? '';
  expect(ref, "the README session's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect(trace, "the README session's TraceRef").toMatch(/^[A-Za-z0-9_-]{22}$/);

  /** What the press left behind: the session's runs ("<count>:<states>") and the headers that carry its TraceRef in OCUORDERS (all, and the failed ones at OrdersFromPartner). */
  const left = async (): Promise<{ runs: string; headers: string; failed: string }> => {
    const lines = await irisScript(
      [
        `Write !,"CHK|runs|",##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs("${ref}")`,
        `Write !,"CHK|headers|",##class(OcuTalon.Test.Demo.Production).Headers("${trace}").%Size()`,
        `Write !,"CHK|failed|",##class(OcuTalon.Test.Demo.Production).Count("${trace}","OrdersFromPartner",8)`,
      ].join('\n'),
    );
    return { runs: chk(lines, 'runs') ?? '', headers: chk(lines, 'headers') ?? '', failed: chk(lines, 'failed') ?? '' };
  };

  const first = await refusal(await post(request, BREAK_FEED, {}));
  expect(first, 'the first press is refused: nothing is watched').toEqual({ status: 409, code: 'not_watching', message: NOT_WATCHING });
  expect(await left(), 'a refused press sends nothing: no run, no order').toEqual({ runs: '0:', headers: '0', failed: '0' });

  const seeded = await irisScript([`Do ##class(OcuTalon.Test.Data.Fixture).Check("${ref}","OCUORDERS","OcuTalon.Demo.Orders.Production")`, 'Write !,"CHK|seeded|1"'].join('\n'));
  expect(chk(seeded, 'seeded'), "the README session's Orders watch is seeded").toBe('1');

  const sent = await post(request, BREAK_FEED, {});
  expect(sent.status(), await sent.text()).toBe(200);
  const answer = (await sent.json()) as { state: string; startedAt: string };
  expect(Object.keys(answer).sort(), 'the answer is {state, startedAt}').toEqual(['startedAt', 'state']);
  expect(answer.state).toBe('sent');
  expect(answer.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);

  const events = await sessionEvents(request, cursor, (seen) => seen.some((event) => event.type === 'breakfeed.progress' && event.payload['state'] === 'sent') && seen.some((event) => event.type === 'guide.state' && (event.payload['breakFeed'] as { stage?: string }).stage === 'waiting'));
  const progress = events.filter((event) => event.type === 'breakfeed.progress');
  expect(
    progress.map((event) => event.payload['state']),
    'breakfeed.progress: sending, then sent',
  ).toEqual(['sending', 'sent']);
  expect(
    progress.map((event) => event.payload['startedAt']),
    'both carry the run start',
  ).toEqual([answer.startedAt, answer.startedAt]);
  const guides = events.filter((event) => event.type === 'guide.state' && event.seq > progress[1].seq);
  expect(guides.length, 'a guide.state follows the sent event').toBeGreaterThan(0);
  expect((guides[guides.length - 1].payload['breakFeed'] as { stage: string }).stage, 'its stage is waiting').toBe('waiting');

  const second = await refusal(await post(request, BREAK_FEED, {}));
  expect(second, 'a second press is refused: the first has no notice yet').toEqual({ status: 409, code: 'incident_in_progress', message: IN_PROGRESS });

  const counts = async (): Promise<number> => Number((await left()).failed);
  await expect.poll(counts, { message: "OCUORDERS holds the session's 50 failed orders", timeout: 60000, intervals: [1000, 2000, 3000] }).toBe(50);
  const warehouse = await irisScript(`Write !,"CHK|warehouse|",##class(OcuTalon.Test.Demo.Production).Count("${trace}","OrdersToWarehouse",9)`);
  expect(chk(warehouse, 'warehouse'), 'none of them reaches the warehouse').toBe('0');

  // The refused second press sent nothing: after a pause, still one run and one batch (50 orders, not 100).
  await new Promise((done) => setTimeout(done, 3000));
  expect(await left(), 'one run (sent) and one batch of 50 orders after the second press').toEqual({ runs: '1:sent', headers: '50', failed: '50' });
});

/**
 * The incident card and the phone's notice, on fixtures for Lane A's raise path (Story 6.3, REL-2): until Epic 11 turns the
 * real path on, the README session gets what IncidentManager will give it, an `incident` event, a pending request with its `approval`
 * event, and the incident notice that Notify delivers to the phone (kind incident, with the request). The chat shows the request's card
 * with Approve and Reject, the simulated phone the notice with its own Approve and Reject, and the rail counts the request. The rows and
 * the phone's messages are removed afterwards.
 */
test("the incident card and the phone's notice, on fixtures for Lane A's raise path", { tag: '@fixtures' }, async ({ page }) => {
  test.setTimeout(120_000);
  const user = README_ACCOUNT.user;
  const rows: string[] = [];
  const start = inMs(-2000);
  try {
    await signInReadme(page);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    // The README session's pending requests before this case's, so that the count the rail gains is this case's own.
    const pending = page.locator('app-status-rail [data-section="approvals"] h3 .visually-hidden');
    await expect(pending).toHaveText(/^Approval requests, \d+$/);
    const pendingBefore = Number(/(\d+)$/.exec((await pending.textContent()) ?? '')?.[1] ?? '0');
    const incident = refOf('D4');
    const request = await raise(page, user, rows, incident, []);
    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.withFix',
      slots: {
        count: 50,
        itemNoun: { one: 'order', other: 'orders' },
        time: inMs(-120_000),
        cause: 'Data format change',
        fixSummary: 'repair the order date and resend 50 orders',
        field: 'OrderDate',
        before: '10/16/2026',
        after: '2026-10-16',
        resendCount: 50,
      },
      approvalRef: request,
      incidentRef: incident,
    });

    const card = page.locator(`app-chat-panel [data-part="approval"][data-key="${request}"]`);
    await expect(card, "the chat shows the request's card").toHaveCount(1, { timeout: CARD_MS });
    await expect(card.getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true }), 'with Approve').toHaveCount(1);
    await expect(card.getByRole('button', { name: 'Reject: repair and resend 50 orders', exact: true }), 'and Reject').toHaveCount(1);

    let ref = '';
    await expect.poll(async () => (ref = (await phoneMessage(user, request))?.ref ?? ''), { message: 'the phone has the notice', timeout: CARD_MS }).not.toBe('');
    const message = page.locator(`app-simulated-phone .notification[data-key="${ref}"]`);
    await expect(message, 'the simulated phone shows the notice').toHaveCount(1, { timeout: CARD_MS });
    await expect(message.getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true }), 'with its Approve').toHaveCount(1);
    await expect(message.getByRole('button', { name: 'Reject: repair and resend 50 orders', exact: true }), 'and its Reject').toHaveCount(1);

    await expect(page.locator(`app-status-rail li.row[data-row-key="approvals:${request}"]`), 'the rail lists the request').toHaveCount(1);
    await expect(pending, 'and counts it').toHaveText(`Approval requests, ${pendingBefore + 1}`);
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

notBuilt("Break the feed's real failures become that incident (IncidentManager)", '11.1');
notBuilt('the rail shows "Approval requests (1)", and the reminder lands in the chat and on the phone during the wait', '11.1');
