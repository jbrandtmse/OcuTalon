// Tests of the approval request card's view model (web/src/app/approvals/approval-view.ts, Story 6.2): every row of the story's
// I/O matrix that the page decides, with the texts written out: the pending card and its parts in order, the dry run and its
// count-of-one forms, the answered statuses (approved, rejected, expired, and the fix's later states), the label, bar and what goes
// when a request is answered, the named answerer, the late press, the reading of each reply of the answer endpoint, and the
// requests of an incident in the order raised. The view reads the catalog's page texts (msg/catalog.ts), the rail's title of a
// request and the page's time formats through its context, so these tests pass the real ones.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { APPROVAL_TEXTS, answerOutcomeOf, approvalView, latePressText, requestsOf } = await import(app('approvals', 'approval-view.ts'));
const { renderPageText } = await import(app('msg', 'catalog.ts'));
const { approvalTitle } = await import(app('rail', 'rail-view.ts'));
const { pageTimeBeside, pageWhenBeside } = await import(app('chat', 'page-time.ts'));

const NOW = Date.parse('2026-10-27T14:30:00Z');

/** The page's context: UTC for the instance and the browser (en-GB), the real catalog and title, FLOOR signed in. */
const ctx = (over = {}) => ({
  nowMs: NOW,
  instanceZone: 'UTC',
  onlineDemo: false,
  user: 'FLOOR',
  timeBeside: (iso) => pageTimeBeside(iso, 'UTC', 'en-GB', 'UTC'),
  whenBeside: (iso, now) => pageWhenBeside(iso, now, 'UTC', 'en-GB', 'UTC'),
  render: renderPageText,
  title: approvalTitle,
  ...over,
});

const dry = (over = {}) => ({ affected: 50, resend: 50, field: 'OrderDate', before: '10/16/2026', after: '2026-10-16', itemNoun: { one: 'order', other: 'orders' }, ...over });

/** A pending fix request of incident R: 50 orders, expiring tomorrow at 14:13. */
const pending = (over = {}) => ({
  ref: 'A',
  kind: 'fix',
  state: 'pending',
  incidentRef: 'R',
  dryRun: dry(),
  raisedAt: '2026-10-27T14:13:00Z',
  expiresAt: '2026-10-28T14:13:00Z',
  ...over,
});

const answered = (state, over = {}) =>
  pending({ state, answeredAction: state === 'rejected' ? 'reject' : 'approve', answeredChannel: 'web', answeredBy: 'FLOOR', answeredAt: '2026-10-27T14:15:00Z', ...over });

describe('the pending card', () => {
  it('has the label, the action, the fixed-targets line, the dry run, the buttons\' names and the expiry, as the matrix writes them', () => {
    const view = approvalView(pending(), ctx());
    assert.equal(view.key, 'approval:A');
    assert.equal(view.ref, 'A');
    assert.equal(view.pending, true);
    assert.equal(view.label, 'Approval needed');
    assert.equal(view.bar, 'pending');
    assert.equal(view.action, 'Repair and resend 50 orders.');
    assert.equal(view.approveName, 'Approve: repair and resend 50 orders');
    assert.equal(view.rejectName, 'Reject: repair and resend 50 orders');
    assert.equal(view.fixedTargets, 'Approving runs exactly this change on these 50 orders, without asking the model again. New failures need their own approval.');
    assert.deepEqual(view.dryRun, {
      countLine: '50 orders affected',
      field: 'OrderDate',
      before: 'OrderDate 10/16/2026',
      after: 'OrderDate 2026-10-16',
      resendLine: '50 repaired copies; the originals stay unchanged.',
      nothingYet: 'Nothing has changed yet.',
    });
    assert.equal(view.expiry, 'Expires tomorrow at 14:13');
    assert.equal(view.status, undefined);
  });

  it('reads the expiry as a page time with its day, and names the zone when the browser\'s differs from the instance\'s', () => {
    const view = approvalView(pending(), ctx({ whenBeside: (iso, now) => pageWhenBeside(iso, now, 'UTC', 'en-GB', 'Europe/Berlin') }));
    assert.equal(view.expiry, 'Expires tomorrow at 15:13 CET');
    assert.equal(approvalView(pending({ expiresAt: '2026-10-27T18:00:00Z' }), ctx()).expiry, 'Expires 18:00', 'today: the clock alone');
    assert.equal(approvalView(pending({ expiresAt: 'soon' }), ctx()).expiry, '', 'an unreadable time has no expiry line');
    assert.equal(approvalView(pending({ expiresAt: undefined }), ctx()).expiry, '');
  });

  it('draws a count of one in the singular: the line, the count, the noun and the copies', () => {
    const view = approvalView(pending({ dryRun: dry({ affected: 1, resend: 1 }) }), ctx());
    assert.equal(view.action, 'Repair and resend 1 order.');
    assert.equal(view.approveName, 'Approve: repair and resend 1 order');
    assert.equal(view.fixedTargets, 'Approving runs exactly this change on this order, without asking the model again. New failures need their own approval.');
    assert.equal(view.dryRun.countLine, '1 order affected');
    assert.equal(view.dryRun.resendLine, '1 repaired copy; the original stays unchanged.');
    assert.equal(approvalView(pending({ dryRun: dry({ affected: 2, resend: 2 }) }), ctx()).dryRun.resendLine, '2 repaired copies; the originals stay unchanged.');
  });

  it('keeps the copies of the dry run apart from the count: 50 affected and 48 to resend', () => {
    const view = approvalView(pending({ dryRun: dry({ affected: 50, resend: 48 }) }), ctx());
    assert.equal(view.dryRun.countLine, '50 orders affected');
    assert.equal(view.dryRun.resendLine, '48 repaired copies; the originals stay unchanged.');
  });

  it('leaves out the fixed-targets line and the dry run when the dry run is not an object or has no numeric count', () => {
    for (const dryRun of [undefined, null, 'x', 5, [], {}, { affected: '50' }, { resend: 3, field: 'OrderDate' }]) {
      const view = approvalView(pending({ dryRun }), ctx());
      assert.equal(view.action, 'Repair and resend.', JSON.stringify(dryRun));
      assert.equal(view.approveName, 'Approve: repair and resend', JSON.stringify(dryRun));
      assert.equal(view.rejectName, 'Reject: repair and resend', JSON.stringify(dryRun));
      assert.equal(view.fixedTargets, '', JSON.stringify(dryRun));
      assert.equal(view.dryRun, undefined, JSON.stringify(dryRun));
      assert.equal(view.expiry, 'Expires tomorrow at 14:13', 'the rest of the card is as it was');
    }
  });

  it('shows the example rows only when there is an example, and the field as it is published', () => {
    const view = approvalView(pending({ dryRun: dry({ field: 'order_date', before: '', after: undefined }) }), ctx());
    assert.equal(view.dryRun.before, '');
    assert.equal(view.dryRun.after, '');
    assert.equal(view.dryRun.field, 'order_date');
    const bare = approvalView(pending({ dryRun: dry({ field: '' }) }), ctx());
    assert.equal(bare.dryRun.before, '10/16/2026', 'with no field the value stands alone');
    assert.equal(approvalView(pending({ dryRun: dry({ resend: undefined }) }), ctx()).dryRun.resendLine, '', 'with no count of copies the Will resend row is left out');
  });

  it('puts a noun-less dry run in words without a stray space', () => {
    const view = approvalView(pending({ dryRun: dry({ itemNoun: undefined }) }), ctx());
    assert.equal(view.dryRun.countLine, '50 affected');
    assert.equal(view.fixedTargets, 'Approving runs exactly this change on these 50, without asking the model again. New failures need their own approval.');
  });

  it('draws the title of a tool call request as the rail does', () => {
    const view = approvalView({ ref: 'T', kind: 'tool_call', state: 'pending', toolName: 'zz_tool', expiresAt: '2026-10-28T14:13:00Z' }, ctx());
    assert.equal(view.action, 'Run zz_tool.');
    assert.equal(view.approveName, 'Approve: run zz_tool');
    assert.equal(view.fixedTargets, '');
    assert.equal(view.dryRun, undefined);
  });
});

describe('an answered card', () => {
  it('reads "Approval request", puts the status in the buttons\' place and drops the fixed-targets line, the expiry and "Nothing has changed yet.", keeping the dry run', () => {
    const view = approvalView(answered('approved'), ctx());
    assert.equal(view.pending, false);
    assert.equal(view.label, 'Approval request');
    assert.deepEqual(view.status, { text: 'Approved from the web chat at 14:15', tone: 'approved', icon: 'circle-check' });
    assert.equal(view.fixedTargets, '');
    assert.equal(view.expiry, '');
    assert.equal(view.dryRun.nothingYet, '');
    assert.equal(view.dryRun.countLine, '50 orders affected');
    assert.equal(view.dryRun.before, 'OrderDate 10/16/2026');
    assert.equal(view.dryRun.resendLine, '50 repaired copies; the originals stay unchanged.');
    assert.equal(view.action, 'Repair and resend 50 orders.', 'the action stays as a record');
    assert.equal(view.bar, 'approved');
  });

  it('reads a rejection with its second sentence and the circle-slash, and an expiry at the row\'s expiry time with the clock', () => {
    assert.deepEqual(approvalView(answered('rejected'), ctx()).status, { text: 'Rejected from the web chat at 14:15. Nothing was changed.', tone: 'rejected', icon: 'circle-slash' });
    assert.deepEqual(approvalView(answered('expired', { answeredAction: undefined, answeredChannel: undefined, answeredBy: undefined, answeredAt: undefined }), ctx()).status, {
      text: 'Expired at 14:13. Nothing was changed.',
      tone: 'expired',
      icon: 'clock',
    });
  });

  it('reads the channel by its name, and the time as a page time that names the zone when the browser\'s differs', () => {
    assert.equal(approvalView(answered('approved', { answeredChannel: 'phone' }), ctx()).status.text, 'Approved from the simulated phone at 14:15');
    assert.equal(approvalView(answered('approved', { answeredChannel: 'telegram' }), ctx()).status.text, 'Approved from Telegram at 14:15');
    const berlin = ctx({ timeBeside: (iso) => pageTimeBeside(iso, 'UTC', 'en-GB', 'Europe/Berlin') });
    assert.equal(approvalView(answered('approved', { answeredChannel: 'telegram' }), berlin).status.text, 'Approved from Telegram at 15:15 CET');
  });

  it('gives the later states of an approved fix the approved status, with the bar of the fix: approved while it runs, closed when it failed', () => {
    for (const [state, bar] of [['approved', 'approved'], ['executing', 'approved'], ['done', 'approved'], ['failed', 'closed'], ['rejected', 'closed'], ['expired', 'closed']]) {
      const view = approvalView(answered(state), ctx());
      assert.equal(view.bar, bar, state);
      assert.ok(view.status !== undefined, state);
      assert.equal(view.status.tone, state === 'rejected' ? 'rejected' : state === 'expired' ? 'expired' : 'approved', state);
    }
  });

  it('has no status for a state the page does not know, and no buttons', () => {
    const view = approvalView(answered('mystery'), ctx());
    assert.equal(view.status, undefined);
    assert.equal(view.pending, false);
    assert.equal(view.bar, 'closed');
  });

  it('names the answerer on a local install when it is not the signed-in user, compared without case, and never on the online demo', () => {
    assert.equal(approvalView(answered('approved', { answeredBy: 'zzsam', answeredChannel: 'phone' }), ctx()).status.text, 'Approved by zzsam from the simulated phone at 14:15');
    assert.equal(approvalView(answered('rejected', { answeredBy: 'zzsam' }), ctx()).status.text, 'Rejected by zzsam from the web chat at 14:15. Nothing was changed.');
    assert.equal(approvalView(answered('approved', { answeredBy: 'floor' }), ctx()).status.text, 'Approved from the web chat at 14:15', 'the signed-in user, in another case');
    assert.equal(approvalView(answered('approved', { answeredBy: 'zzsam' }), ctx({ onlineDemo: true })).status.text, 'Approved from the web chat at 14:15', 'the online demo');
    assert.equal(approvalView(answered('approved', { answeredBy: '' }), ctx()).status.text, 'Approved from the web chat at 14:15', 'nobody known');
    assert.equal(approvalView(answered('approved', { answeredBy: undefined }), ctx()).status.text, 'Approved from the web chat at 14:15');
  });

  it('reads every text through the context\'s renderer and times, so that nothing is copied into the view', () => {
    const seen = [];
    const view = approvalView(answered('approved', { answeredBy: 'zzsam' }), ctx({ render: (key, slots) => (seen.push([key, slots]), `<${key}>`), timeBeside: (iso) => `T(${iso})` }));
    assert.equal(view.status.text, '<answered.approvedBy>');
    assert.deepEqual(seen, [['answered.approvedBy', { user: 'zzsam', channel: 'web', time: 'T(2026-10-27T14:15:00Z)' }]]);
  });
});

describe('the late press', () => {
  it('reads "Already answered: approved from the simulated phone at 14:15." for a request that the phone approved', () => {
    assert.equal(latePressText(answered('approved', { answeredChannel: 'phone' }), ctx()), 'Already answered: approved from the simulated phone at 14:15.');
  });

  it('reads the rejected form, and the forms for a request in a later state of the fix', () => {
    assert.equal(latePressText(answered('rejected', { answeredChannel: 'telegram' }), ctx()), 'Already answered: rejected from Telegram at 14:15.');
    for (const state of ['executing', 'done', 'failed']) {
      assert.equal(latePressText(answered(state, { answeredChannel: 'web' }), ctx()), 'Already answered: approved from the web chat at 14:15.', state);
    }
  });

  it('names another user on a local install, and no one on the online demo or for the signed-in user', () => {
    assert.equal(latePressText(answered('approved', { answeredBy: 'zzsam', answeredChannel: 'phone' }), ctx()), 'Already answered: approved by zzsam from the simulated phone at 14:15.');
    assert.equal(latePressText(answered('rejected', { answeredBy: 'zzsam', answeredChannel: 'phone' }), ctx()), 'Already answered: rejected by zzsam from the simulated phone at 14:15.');
    assert.equal(latePressText(answered('approved', { answeredBy: 'zzsam', answeredChannel: 'phone' }), ctx({ onlineDemo: true })), 'Already answered: approved from the simulated phone at 14:15.');
    assert.equal(latePressText(answered('approved', { answeredBy: 'FLOOR', answeredChannel: 'phone' }), ctx()), 'Already answered: approved from the simulated phone at 14:15.');
  });

  it('is not the answered status\'s text, which has no "Already answered" and no final period for an approval', () => {
    const payload = answered('approved', { answeredChannel: 'phone' });
    assert.notEqual(latePressText(payload, ctx()), approvalView(payload, ctx()).status.text);
  });

  it('says nothing for a request that is pending, expired or has no state', () => {
    for (const state of ['pending', 'expired', undefined]) {
      assert.equal(latePressText(answered(state), ctx()), '', String(state));
    }
  });
});

describe('the reading of the reply to a press', () => {
  const approved = answered('approved');

  it('reads 200 as done, with the answered request', () => {
    assert.deepEqual(answerOutcomeOf(200, { result: 'done', approval: approved }), { kind: 'done', approval: approved });
    assert.deepEqual(answerOutcomeOf(200, null), { kind: 'done', approval: undefined });
  });

  it('reads a 409 already_answered as the late press, with the request and the server\'s message, and a 409 expired as the expired request', () => {
    const body = { error: { code: 'already_answered', message: 'Already answered: approved from the simulated phone at 14:15.' }, approval: approved };
    assert.deepEqual(answerOutcomeOf(409, body), { kind: 'already', approval: approved, message: 'Already answered: approved from the simulated phone at 14:15.' });
    const expired = answered('expired');
    assert.deepEqual(answerOutcomeOf(409, { error: { code: 'expired', message: 'Expired at 14:13. Nothing was changed.' }, approval: expired }), { kind: 'expired', approval: expired });
    assert.deepEqual(answerOutcomeOf(409, { error: { code: 'already_answered', message: 'x' } }), { kind: 'already', approval: undefined, message: 'x' }, 'without a payload');
  });

  it('reads a 404 as gone, whatever the body', () => {
    assert.deepEqual(answerOutcomeOf(404, { error: { code: 'not_found', message: 'OcuTalon has nothing at this address.' } }), { kind: 'gone' });
    assert.deepEqual(answerOutcomeOf(404, undefined), { kind: 'gone' });
  });

  it('reads a 403 as not allowed, with the server\'s message for the kind, else the approver sentence', () => {
    assert.deepEqual(answerOutcomeOf(403, { error: { code: 'not_allowed', message: 'Only an approver can answer this request.' } }), { kind: 'notAllowed', message: 'Only an approver can answer this request.' });
    assert.deepEqual(answerOutcomeOf(403, { error: { code: 'not_allowed' } }), { kind: 'notAllowed', message: 'Only an approver for resends can answer this request.' });
    assert.deepEqual(answerOutcomeOf(403, 'forbidden'), { kind: 'notAllowed', message: 'Only an approver for resends can answer this request.' });
  });

  it('reads status 0 as unreachable, and any other status as the server\'s own message, else unreachable', () => {
    assert.deepEqual(answerOutcomeOf(0, undefined), { kind: 'unreachable' });
    assert.deepEqual(answerOutcomeOf(0, { error: { code: 'x', message: 'ignored' } }), { kind: 'unreachable' });
    assert.deepEqual(answerOutcomeOf(500, { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } }), { kind: 'failed', message: 'Something went wrong inside OcuTalon. Try again.' });
    assert.deepEqual(answerOutcomeOf(400, { error: { code: 'bad_answer', message: ' An answer needs an action. ' } }), { kind: 'failed', message: 'An answer needs an action.' });
    for (const body of [undefined, null, 'Bad Gateway', 5, [], {}, { error: null }, { error: { message: '' } }, { error: { message: 5 } }]) {
      assert.deepEqual(answerOutcomeOf(502, body), { kind: 'unreachable' }, JSON.stringify(body));
    }
    assert.deepEqual(answerOutcomeOf(409, { error: { code: 'other', message: 'Conflict.' } }), { kind: 'failed', message: 'Conflict.' }, 'a 409 that is neither');
  });
});

describe('the requests of an incident', () => {
  const incident = { ref: 'R' };
  const store = (...payloads) => Object.fromEntries(payloads.map((one) => [one.ref, one]));

  it('are the approvals with the incident\'s ref, in raisedAt order, not the order of the store', () => {
    const later = pending({ ref: 'A2', raisedAt: '2026-10-27T14:20:00Z', dryRun: dry({ affected: 2, resend: 2 }) });
    const first = pending({ ref: 'A' });
    assert.deepEqual(requestsOf(incident, store(later, first)).map((one) => one.ref), ['A', 'A2']);
    assert.deepEqual(requestsOf(incident, store(first, later)).map((one) => one.ref), ['A', 'A2']);
  });

  it('keeps the store\'s order for requests raised at the same time', () => {
    const one = pending({ ref: 'B1' });
    const two = pending({ ref: 'B2' });
    assert.deepEqual(requestsOf(incident, store(two, one)).map((request) => request.ref), ['B2', 'B1']);
  });

  it('leave out other incidents\' requests, cancelled requests and approvals with no incident', () => {
    const mine = pending({ ref: 'A' });
    const found = requestsOf(incident, store(mine, pending({ ref: 'X', incidentRef: 'Q' }), pending({ ref: 'C', state: 'cancelled' }), pending({ ref: 'N', incidentRef: undefined })));
    assert.deepEqual(found.map((one) => one.ref), ['A']);
  });

  it('are none for an incident with no ref, and for no store', () => {
    assert.deepEqual(requestsOf({}, store(pending())), []);
    assert.deepEqual(requestsOf({ ref: '' }, store(pending({ incidentRef: '' }))), []);
    assert.deepEqual(requestsOf(incident, undefined), []);
  });

  it('give the second request its own names: "repair and resend 2 orders"', () => {
    const later = pending({ ref: 'A2', raisedAt: '2026-10-27T14:20:00Z', dryRun: dry({ affected: 2, resend: 2 }) });
    const views = requestsOf(incident, store(pending(), later)).map((one) => approvalView(one, ctx()));
    assert.deepEqual(views.map((one) => one.approveName), ['Approve: repair and resend 50 orders', 'Approve: repair and resend 2 orders']);
  });
});

describe('the texts', () => {
  it('are these, written out', () => {
    assert.deepEqual({ ...APPROVAL_TEXTS }, {
      labelPending: 'Approval needed',
      labelAnswered: 'Approval request',
      approve: 'Approve',
      reject: 'Reject',
      approveName: 'Approve: {action}',
      rejectName: 'Reject: {action}',
      action: '{title}.',
      fixedTargets: 'Approving runs exactly this change on these {count} {noun}, without asking the model again. New failures need their own approval.',
      fixedTargetsOne: 'Approving runs exactly this change on this {noun}, without asking the model again. New failures need their own approval.',
      dryRun: 'Dry run',
      countLine: '{count} {noun} affected',
      before: 'Before',
      after: 'After',
      willResend: 'Will resend',
      resendCopies: '{count} repaired copies; the originals stay unchanged.',
      resendCopyOne: '1 repaired copy; the original stays unchanged.',
      nothingYet: 'Nothing has changed yet.',
      expires: 'Expires {when}',
      notApprover: 'Only an approver for resends can answer this request.',
      gone: 'That request is no longer available.',
      busyNotice: "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
    });
  });

  it('are printable ASCII', () => {
    for (const text of Object.values(APPROVAL_TEXTS)) assert.ok(!/[^\x20-\x7e]/.test(text), text);
  });
});
