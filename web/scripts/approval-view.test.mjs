// Tests of the approval request card's view model (web/src/app/approvals/approval-view.ts, Story 6.2): every row of the story's
// I/O matrix that the page decides, with the texts written out: the pending card and its parts in order, the dry run and its
// count-of-one forms, the answered statuses (approved, rejected, expired, and the fix's later states), the label, bar and what goes
// when a request is answered, the named answerer, the late press, the reading of each reply of the answer endpoint, and the
// requests of an incident in the order raised; Story 6.4: resultView, every row of the Result mapping (the first matching row wins) with
// the catalog's texts, the count-of-one forms, the tones and icons, the audit line, and undefined with no result. The view reads the catalog's page texts (msg/catalog.ts), the rail's title of a
// request and the page's time formats through its context, so these tests pass the real ones.
// Story 23.5: a partner delay notice's title, its To line, notice and note, and its four result bands.
// Story 7.8: the dry run's either-way row, as the notice's line (many and one form, day first, the slots, the places it is absent, answered).
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { APPROVAL_TEXTS, answerOutcomeOf, approvalView, latePressText, refusalText, requestsOf, resultView } = await import(app('approvals', 'approval-view.ts'));
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

describe('the fixes the user asks for in the chat (Story 23.2)', () => {
  const suspend = (over = {}) => pending({ fixKind: 'suspend_item', dryRun: { item: 'OrdersToWarehouse', before: 'enabled', after: 'disabled' }, ...over });
  const reroute = (over = {}) =>
    pending({
      fixKind: 'reroute',
      dryRun: { affected: 50, resend: 50, leftOut: 0, itemNoun: { one: 'order', other: 'orders' }, from: 'OrdersFromPartner', to: 'OrdersForReview', example: '1234' },
      ...over,
    });

  it('titles a suspend, a resume and a reroute by the rail\'s title, and names the buttons by it', () => {
    const view = approvalView(suspend(), ctx());
    assert.equal(view.action, 'Suspend OrdersToWarehouse.');
    assert.equal(view.approveName, 'Approve: suspend OrdersToWarehouse');
    assert.equal(view.rejectName, 'Reject: suspend OrdersToWarehouse');
    assert.equal(approvalView(suspend({ fixKind: 'resume_item', dryRun: { item: 'OrdersToWarehouse', before: 'disabled', after: 'enabled' } }), ctx()).action, 'Resume OrdersToWarehouse.');
    const rerouted = approvalView(reroute(), ctx());
    assert.equal(rerouted.action, 'Reroute 50 orders to OrdersForReview.');
    assert.equal(rerouted.approveName, 'Approve: reroute 50 orders to OrdersForReview');
    assert.equal(approvalView(reroute({ dryRun: { ...reroute().dryRun, affected: 1, resend: 1 } }), ctx()).action, 'Reroute 1 order to OrdersForReview.');
  });

  it('shows the item\'s state before and after for a suspend, swapped for a resume, with no count and no fixed-targets line', () => {
    const view = approvalView(suspend(), ctx());
    assert.deepEqual(view.dryRun, { countLine: '', field: '', before: 'OrdersToWarehouse: enabled', after: 'OrdersToWarehouse: disabled', eitherWay: '', resendLine: '', nothingYet: 'Nothing has changed yet.' });
    assert.equal(view.fixedTargets, '');
    const resume = approvalView(suspend({ fixKind: 'resume_item', dryRun: { item: 'OrdersToWarehouse', before: 'disabled', after: 'enabled' } }), ctx());
    assert.equal(resume.dryRun.before, 'OrdersToWarehouse: disabled');
    assert.equal(resume.dryRun.after, 'OrdersToWarehouse: enabled');
    assert.equal(approvalView(suspend({ dryRun: {} }), ctx()).dryRun, undefined, 'a dry run with no item has no block');
  });

  it('shows the example where it is and where it would go, and the copies, for a reroute (one form too)', () => {
    const view = approvalView(reroute(), ctx());
    assert.deepEqual(view.dryRun, {
      countLine: '50 orders affected',
      field: '',
      before: 'Message 1234: OrdersFromPartner',
      after: 'Message 1234: OrdersForReview',
      eitherWay: '',
      resendLine: '50 copies to OrdersForReview; the originals stay unchanged.',
      nothingYet: 'Nothing has changed yet.',
    });
    const one = approvalView(reroute({ dryRun: { ...reroute().dryRun, affected: 1, resend: 1 } }), ctx());
    assert.equal(one.dryRun.resendLine, '1 copy to OrdersForReview; the original stays unchanged.');
    assert.equal(approvalView(reroute({ state: 'approved' }), ctx()).dryRun.nothingYet, '', 'an answered request keeps the record without the note');
  });

  it('reads a refusal as the server\'s sentence, whatever the kind of the request, and the fallback sentence when it gave none (Story 25.5)', () => {
    const body = { error: { code: 'not_allowed', message: 'Only an approver for suspending and resuming items can answer this request.' } };
    assert.deepEqual(answerOutcomeOf(403, body), { kind: 'notAllowed', message: 'Only an approver for suspending and resuming items can answer this request.' });
    assert.deepEqual(answerOutcomeOf(403, undefined), { kind: 'notAllowed', message: 'Only an approver can answer this request.' });
  });
});

describe('the result band of a fix the user asked for in the chat (Story 23.2, DW-1067)', () => {
  const render = renderPageText;
  const noun = { one: 'order', other: 'orders' };
  const PRODUCTION = 'OcuTalon.Demo.Orders.Production';
  const ITEM = 'OrdersToWarehouse';
  const AUDIT = 'Recorded in the IRIS audit log.';
  const ran = (over = {}) => ({ total: 1, resent: 0, completed: 1, failedAgain: 0, skipped: 0, interrupted: 0, reason: '', ...over });
  const item = (fixKind, result, over = {}) => resultView({ ref: 'A', state: 'done', fixKind, item: ITEM, result, ...over }, undefined, render, PRODUCTION);

  it('is the success band of result.itemSuspended for a suspend that changed the item, and of result.itemResumed for a resume', () => {
    assert.deepEqual(item('suspend_item', ran()), {
      key: 'result.itemSuspended',
      text: `${ITEM} in ${PRODUCTION} is suspended: it is disabled now. To undo it while this incident is open, ask me to resume ${ITEM}. After the incident closes, enable ${ITEM} again on the production's configuration page in the Management Portal.`,
      tone: 'success',
      icon: 'circle-check',
      audit: AUDIT,
    });
    assert.deepEqual(item('resume_item', ran()), { key: 'result.itemResumed', text: `${ITEM} in ${PRODUCTION} is enabled again.`, tone: 'success', icon: 'circle-check', audit: AUDIT });
  });

  it('is the partial band of result.itemSkipped when the item had changed since the dry run, with the reason as the sentence it is, and of result.itemNotChanged when the run could not change it', () => {
    const skipped = ran({ completed: 0, skipped: 1, reason: `${ITEM} is already disabled` });
    assert.deepEqual(item('suspend_item', skipped), {
      key: 'result.itemSkipped',
      text: `${ITEM} was not changed: ${ITEM} is already disabled. It needs a new approval.`,
      tone: 'partial',
      icon: 'triangle-alert',
      audit: AUDIT,
    });
    assert.equal(item('resume_item', ran({ completed: 0, skipped: 1, reason: 'It changed.' })).text, `${ITEM} was not changed: It changed. It needs a new approval.`, 'a reason with its own full stop is not doubled');
    const failed = ran({ completed: 0, reason: "OcuTalon couldn't change the item" });
    assert.deepEqual(item('resume_item', failed, { state: 'failed' }), {
      key: 'result.itemNotChanged',
      text: "Nothing was changed: OcuTalon couldn't change the item.",
      tone: 'partial',
      icon: 'triangle-alert',
      audit: AUDIT,
    });
  });

  it('claims nothing for an item kind that is still going, was interrupted, or lacks what its text names', () => {
    assert.equal(item('suspend_item', ran(), { state: 'executing' }), undefined, 'still going');
    assert.equal(item('suspend_item', ran({ completed: 0, interrupted: 1, reason: 'x' })), undefined, 'interrupted');
    assert.equal(item('suspend_item', ran({ completed: 0 })), undefined, 'nothing changed and no reason');
    assert.equal(item('suspend_item', ran(), { item: undefined }), undefined, 'no item');
    assert.equal(resultView({ ref: 'A', state: 'done', fixKind: 'suspend_item', item: ITEM, result: ran() }, undefined, render), undefined, 'no production');
    assert.equal(item('suspend_item', ran({ completed: 0, skipped: 1, reason: 'x' }), { item: undefined }), undefined, 'a skipped item with no item');
  });

  it('is the success band of result.rerouted for a reroute whose copies all completed, with the target and the count-of-one form, and none without a target', () => {
    const all = { total: 50, resent: 50, completed: 50, failedAgain: 0, skipped: 0, interrupted: 0, reason: '' };
    assert.deepEqual(resultView({ ref: 'A', state: 'done', fixKind: 'reroute', item: 'OrdersForReview', result: all }, noun, render), {
      key: 'result.rerouted',
      text: 'All 50 orders were rerouted to OrdersForReview and completed there. The originals stay unchanged.',
      tone: 'success',
      icon: 'circle-check',
      audit: AUDIT,
    });
    assert.equal(
      resultView({ ref: 'A', state: 'done', fixKind: 'reroute', item: 'OrdersForReview', result: { ...all, total: 1, resent: 1, completed: 1 } }, noun, render).text,
      'The order was rerouted to OrdersForReview and completed there. The original stays unchanged.',
    );
    assert.equal(resultView({ ref: 'A', state: 'done', fixKind: 'reroute', result: all }, noun, render), undefined, 'no target');
    assert.equal(resultView({ ref: 'A', state: 'done', fixKind: 'repair_resend', result: all }, noun, render).key, 'result.allThrough', 'the diagnosis\'s kind is as before');
  });

  it('keeps the bands of a reroute that failed again or skipped some', () => {
    const view = resultView({ ref: 'A', state: 'done', fixKind: 'reroute', item: 'OrdersForReview', result: { total: 50, resent: 50, completed: 48, failedAgain: 2, skipped: 0, interrupted: 0, reason: 'x' } }, noun, render);
    assert.equal(view.key, 'result.failedAgain');
  });
});

describe('a partner delay notice (Story 23.5)', () => {
  const NOTICE = 'Orders from the partner failed between 14:12 and 14:13.\nWe are working on it.';
  const warning = (over = {}) =>
    pending({
      fixKind: 'partner_warning',
      dryRun: { notice: NOTICE, recipients: ['Results Partner IT <it@results-partner.example>'], simulated: true },
      ...over,
    });
  const render = renderPageText;
  const result = (over = {}) => ({ total: 1, resent: 0, completed: 1, failedAgain: 0, skipped: 0, interrupted: 0, unreached: 0, reason: '', ...over });

  it('is titled "Send a delay notice", with the buttons named by it', () => {
    const view = approvalView(warning(), ctx());
    assert.equal(view.action, 'Send a delay notice.');
    assert.equal(view.approveName, 'Approve: send a delay notice');
    assert.equal(view.rejectName, 'Reject: send a delay notice');
  });

  it('shows the recipients, the exact notice and, while pending, the note, with no dry run block and no fixed-targets line', () => {
    const view = approvalView(warning(), ctx());
    assert.equal(view.dryRun, undefined);
    assert.equal(view.fixedTargets, '');
    assert.deepEqual(view.partner, {
      to: 'To: Results Partner IT <it@results-partner.example>',
      notice: NOTICE,
      simulated: true,
      note: 'Nothing is sent unless you approve. It goes to the Simulated mailbox, not to a real inbox.',
    });
    assert.equal(approvalView(warning({ state: 'approved' }), ctx()).partner.note, '', 'an answered request keeps the record without the note');
    assert.equal(approvalView(warning(), ctx()).setting, undefined);
  });

  it('lists every recipient, and leaves out the Simulated label when the payload does not say simulated', () => {
    const two = warning({ dryRun: { notice: 'A.', recipients: ['A <a@x.example>', 'B <b@x.example>'], simulated: false } });
    assert.equal(approvalView(two, ctx()).partner.to, 'To: A <a@x.example>, B <b@x.example>');
    assert.equal(approvalView(two, ctx()).partner.simulated, false);
    assert.equal(approvalView(warning({ dryRun: {} }), ctx()).partner, undefined, 'a dry run with neither notice nor recipient has no block');
  });

  it('gives the other kinds no partner block', () => {
    assert.equal(approvalView(pending(), ctx()).partner, undefined);
  });

  it('reads the result bands of the request, each naming the Simulated mailbox or the draft', () => {
    const request = (fields) => ({ ref: 'A', state: 'done', fixKind: 'partner_warning', ...fields });
    const sent = resultView(request({ result: result() }), undefined, render);
    assert.deepEqual({ key: sent.key, text: sent.text, tone: sent.tone, icon: sent.icon }, { key: 'result.partnerSent', text: 'Sent to the Simulated mailbox.', tone: 'success', icon: 'circle-check' });
    assert.equal(sent.audit, 'Recorded in the IRIS audit log.');
    const some = resultView(request({ result: result({ total: 3, completed: 2, skipped: 1, reason: 'Contact 3 is no longer a partner contact of Orders.' }) }), undefined, render);
    assert.deepEqual({ key: some.key, text: some.text, tone: some.tone }, { key: 'result.partnerSentSome', text: 'Sent to the Simulated mailbox for 2 of 3 contacts.', tone: 'partial' });
    const kept = resultView(request({ state: 'failed', result: result({ completed: 0, reason: "email delivery isn't set up yet" }) }), undefined, render);
    assert.deepEqual({ key: kept.key, text: kept.text, tone: kept.tone }, { key: 'result.partnerKept', text: "Approved and kept as a draft: email delivery isn't set up yet.", tone: 'partial' });
    const not = resultView(request({ result: result({ completed: 0, skipped: 1, reason: 'Results Partner IT is no longer a partner contact of Orders.' }) }), undefined, render);
    assert.deepEqual({ key: not.key, text: not.text }, { key: 'result.partnerNotSent', text: 'Not sent: Results Partner IT is no longer a partner contact of Orders.' });
    assert.equal(resultView(request({ state: 'executing', result: result() }), undefined, render), undefined, 'a run still going has no band');
    assert.equal(resultView(request({ result: result({ completed: 0 }) }), undefined, render), undefined, 'a result with no reason to give claims nothing');
  });

  it('never says or implies that a real email was sent', () => {
    for (const key of ['partnerNote', 'partnerSent', 'partnerSentSome', 'partnerKept', 'partnerNotSent']) {
      assert.doesNotMatch(APPROVAL_TEXTS[key], /\bemailed\b|\bby email\b|email was sent/i, key);
    }
    for (const key of ['partnerSent', 'partnerSentSome']) {
      assert.match(APPROVAL_TEXTS[key], /Simulated mailbox/, key);
    }
    assert.match(APPROVAL_TEXTS.partnerKept, /kept as a draft/);
  });
});

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
      eitherWay: '',
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

describe('a tool call\'s request text', () => {
  const REQUEST = 'Run zz_send on ops-mcp\nInputs: {"to":"ops"}\nNo dry run is available for this tool. Approving runs exactly this call once.';
  const tool = { ref: 'T', kind: 'tool_call', state: 'pending', toolName: 'zz_send', expiresAt: '2026-10-28T14:13:00Z' };

  it('is the action, and its first line names both buttons, while pending', () => {
    const view = approvalView(tool, ctx(), REQUEST);
    assert.equal(view.action, REQUEST);
    assert.equal(view.approveName, 'Approve: run zz_send on ops-mcp');
    assert.equal(view.rejectName, 'Reject: run zz_send on ops-mcp');
  });

  it('keeps the action and the names once answered', () => {
    const view = approvalView({ ...tool, state: 'approved', answeredBy: 'dana', answeredChannel: 'web', answeredAt: '2026-10-28T14:00:00Z' }, ctx(), REQUEST);
    assert.equal(view.action, REQUEST);
    assert.equal(view.approveName, 'Approve: run zz_send on ops-mcp');
    assert.deepEqual(view.status, { text: 'Approved by dana from the web chat at 14:00', tone: 'approved', icon: 'circle-check' });
    assert.equal(view.pending, false);
  });

  it('is ignored when empty: the title of the rail', () => {
    assert.equal(approvalView(tool, ctx(), '').action, 'Run zz_send.');
  });
});

describe('a setting request (Story 40.6: a proposed persona)', () => {
  const NOTICE = 'OcuTalon suggests a new persona for you. Now: Professional (default). Proposed: Pirate. Nothing changes unless you approve.';
  const setting = (over = {}) => ({
    ref: 'S',
    kind: 'setting',
    state: 'pending',
    dryRun: { before: 'Professional (default)', after: 'Pirate' },
    raisedAt: '2026-10-27T14:13:00Z',
    expiresAt: '2026-10-28T14:13:00Z',
    ...over,
  });

  it('is titled by the context and shows Now, Proposed and the note, with both buttons named by the title, while pending', () => {
    for (const request of ['', NOTICE]) {
      const view = approvalView(setting(), ctx(), request);
      assert.equal(view.pending, true);
      assert.equal(view.action, 'Change how OcuTalon talks to you', 'the title with no period, the notice text never the card text');
      assert.equal(view.approveName, 'Approve: change how OcuTalon talks to you');
      assert.equal(view.rejectName, 'Reject: change how OcuTalon talks to you');
      assert.deepEqual(view.setting, { now: 'Now: Professional (default)', proposed: 'Proposed: Pirate', note: 'Nothing changes unless you approve.' });
      assert.equal(view.dryRun, undefined, 'no dry run block');
      assert.equal(view.fixedTargets, '', 'and no fixed-targets line');
      assert.equal(view.label, 'Approval needed');
      assert.equal(view.expiry, 'Expires tomorrow at 14:13');
    }
  });

  it('loses the note once answered and keeps the status line every request has', () => {
    const view = approvalView(setting({ state: 'done', answeredAction: 'approve', answeredChannel: 'web', answeredBy: 'FLOOR', answeredAt: '2026-10-27T14:15:00Z' }), ctx(), NOTICE);
    assert.equal(view.pending, false);
    assert.deepEqual(view.setting, { now: 'Now: Professional (default)', proposed: 'Proposed: Pirate', note: '' });
    assert.deepEqual(view.status, { text: 'Approved from the web chat at 14:15', tone: 'approved', icon: 'circle-check' });
    assert.equal(view.action, 'Change how OcuTalon talks to you');
    const rejected = approvalView(setting({ state: 'rejected', answeredAction: 'reject', answeredChannel: 'web', answeredBy: 'FLOOR', answeredAt: '2026-10-27T14:15:00Z' }), ctx());
    assert.equal(rejected.status.text, 'Rejected from the web chat at 14:15. Nothing was changed.');
    assert.equal(rejected.setting.note, '');
  });

  it('shows empty values as they are when the payload has none, and never reads a fix field', () => {
    const view = approvalView(setting({ dryRun: undefined }), ctx());
    assert.deepEqual(view.setting, { now: 'Now: ', proposed: 'Proposed: ', note: 'Nothing changes unless you approve.' });
    const withFix = approvalView(setting({ dryRun: { before: 'A', after: 'B', affected: 4, resend: 3 } }), ctx());
    assert.equal(withFix.dryRun, undefined);
    assert.equal(withFix.fixedTargets, '');
  });

  it('leaves every other kind without setting lines', () => {
    assert.equal(approvalView(pending(), ctx()).setting, undefined);
    assert.equal(approvalView({ ref: 'T', kind: 'tool_call', state: 'pending', toolName: 'zz_tool' }, ctx()).setting, undefined);
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

  it('reads a cancelled request of a removed MCP server as canceled, only with cancelledAt and server (Story 21.10)', () => {
    const tool = (over = {}) => pending({ kind: 'tool_call', state: 'cancelled', incidentRef: undefined, toolName: 'zz_t', dryRun: undefined, ...over });
    assert.deepEqual(approvalView(tool({ server: 'zzS', cancelledAt: '2026-10-27T14:20:00Z' }), ctx()).status, {
      text: 'Cancelled at 14:20: the MCP server zzS was removed. Nothing was changed.',
      tone: 'rejected',
      icon: 'circle-slash',
    });
    assert.equal(approvalView(tool({ server: 'zzS', cancelledAt: '2026-10-27T14:20:00Z' }), ctx()).pending, false);
    assert.equal(approvalView(tool({ server: 'zzS' }), ctx()).status, undefined, 'a cancel with no cancelledAt (a session end) shows no status');
    assert.equal(approvalView(tool({ cancelledAt: '2026-10-27T14:20:00Z' }), ctx()).status, undefined, 'and one with no server shows none');
    assert.equal(approvalView(tool(), ctx()).status, undefined);
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

  it('reads a 403 as not allowed, with the server\'s message, else the fallback approver sentence', () => {
    assert.deepEqual(answerOutcomeOf(403, { error: { code: 'not_allowed', message: 'Only an approver can answer this request.' } }), { kind: 'notAllowed', message: 'Only an approver can answer this request.' });
    assert.deepEqual(answerOutcomeOf(403, { error: { code: 'not_allowed', message: 'Only an OcuTalon admin can approve this email.' } }), { kind: 'notAllowed', message: 'Only an OcuTalon admin can approve this email.' });
    assert.deepEqual(answerOutcomeOf(403, { error: { code: 'not_allowed' } }), { kind: 'notAllowed', message: 'Only an approver can answer this request.' });
    assert.deepEqual(answerOutcomeOf(403, 'forbidden'), { kind: 'notAllowed', message: 'Only an approver can answer this request.' });
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

describe('the result band (Story 6.4)', () => {
  const noun = { one: 'order', other: 'orders' };
  const REASON = "the order date still wasn't accepted";
  const result = (over = {}) => ({ total: 50, resent: 50, completed: 50, failedAgain: 0, skipped: 0, interrupted: 0, reason: '', ...over });
  const band = (over = {}, state = 'done', itemNoun = noun) => resultView({ ref: 'A', state, result: result(over) }, itemNoun, renderPageText);
  const AUDIT = 'Recorded in the IRIS audit log.';

  it('is undefined for a request with no result, whatever its state, and for a result that is not an object', () => {
    for (const request of [{ ref: 'A', state: 'done' }, { ref: 'A', state: 'executing' }, { ref: 'A', state: 'rejected' }, { ref: 'A', result: null }, { ref: 'A', result: 'x' }, { ref: 'A', result: [] }, {}]) {
      assert.equal(resultView(request, noun, renderPageText), undefined, JSON.stringify(request));
    }
  });

  it('is the success band with circle-check and the audit line for all through, and "The order went through." for one', () => {
    assert.deepEqual(band(), { key: 'result.allThrough', text: 'All 50 orders went through.', tone: 'success', icon: 'circle-check', audit: AUDIT });
    assert.equal(band({ total: 1, resent: 1, completed: 1 }).text, 'The order went through.');
    assert.equal(band({ total: 2, resent: 2, completed: 2 }).text, 'All 2 orders went through.');
    assert.equal(band({ total: 50, resent: 50, completed: 50 }, 'failed').tone, 'success', 'the rows follow the fields, the state matters for executing only');
  });

  it('is a partial band with triangle-alert for failed again, skipped, both, interrupted and could not start', () => {
    const cases = [
      ['result.failedAgain', { completed: 48, failedAgain: 2, reason: REASON }, "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval."],
      ['result.failedAgain', { completed: 49, failedAgain: 1, reason: REASON }, "49 of 50 orders went through. 1 failed again (the order date still wasn't accepted). I won't retry it without a new approval."],
      ['result.skipped', { completed: 47, skipped: 3 }, '47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.'],
      ['result.skipped', { completed: 49, skipped: 1 }, '49 of 50 orders went through. 1 had changed since the dry run, so I skipped it; it needs a new approval.'],
      ['result.failedAndSkipped', { completed: 45, failedAgain: 2, skipped: 3, reason: REASON }, "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval."],
      ['result.failedAndSkipped', { completed: 47, failedAgain: 2, skipped: 1, reason: REASON }, "47 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 1 had changed since the dry run, so I skipped it. I won't retry any of them without a new approval."],
      ['result.interrupted', { completed: 30, interrupted: 20 }, 'The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval.'],
      ['result.interrupted', { completed: 49, interrupted: 1 }, 'The resend stopped when OcuTalon restarted: 49 of 50 orders went through. The other one needs a new approval.'],
      ['result.couldNotStart', { resent: 0, completed: 0, reason: "OcuTalon isn't allowed to resend messages in that production" }, "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed."],
    ];
    for (const [key, over, text] of cases) {
      assert.deepEqual(band(over), { key, text, tone: 'partial', icon: 'triangle-alert', audit: AUDIT }, text);
    }
  });

  it('is the partial band with clock for a request that is still executing, with the one form for one gone through', () => {
    assert.deepEqual(band({ completed: 30 }, 'executing'), {
      key: 'result.stillResending',
      text: "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done.",
      tone: 'partial',
      icon: 'clock',
      audit: AUDIT,
    });
    assert.equal(band({ completed: 1 }, 'executing').text, "Still resending: 1 of 50 orders has gone through so far. I'll tell you when it's done.");
    assert.equal(band({ completed: 0, resent: 0, reason: 'zz' }, 'executing').key, 'result.stillResending', 'executing wins over could not start');
  });

  it('is the partial band with triangle-alert for a run that stopped partway, and notTried is the unreached less the copy that erred', () => {
    const stopped = { total: 3, resent: 2, completed: 2, failedAgain: 0, skipped: 1, unreached: 1 };
    assert.deepEqual(band(stopped), {
      key: 'result.stoppedPartway',
      text: "The resend stopped partway: I resent 2 of the 3 orders (2 went through), the next one couldn't be resent, and 0 more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
      tone: 'partial',
      icon: 'triangle-alert',
      audit: AUDIT,
    });
    assert.equal(
      band({ ...stopped, total: 4, skipped: 2, unreached: 2 }).text,
      "The resend stopped partway: I resent 2 of the 4 orders (2 went through), the next one couldn't be resent, and 1 more wasn't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
      'the count-of-one form follows notTried',
    );
    assert.equal(
      band({ total: 5, resent: 3, completed: 2, failedAgain: 1, skipped: 1, unreached: 1 }).text,
      "The resend stopped partway: I resent 3 of the 5 orders (2 went through), the next one couldn't be resent, and 0 more weren't tried. Nothing else was changed, and I won't resend the rest without a new approval.",
      'resent and completed are their own slots',
    );
    assert.equal(band({ ...stopped, unreached: 5 }).text.includes('and 4 more weren\'t tried'), true);
    assert.equal(band({ ...stopped, total: 1, resent: 0, completed: 0, skipped: 1, unreached: 1 }).key, 'result.stoppedPartway', 'a first copy that erred without a reason is not "could not start"');
  });

  it('puts stopped partway after interrupted and could not start and before failed and skipped', () => {
    assert.equal(band({ unreached: 1, interrupted: 1, completed: 2, skipped: 1 }).key, 'result.interrupted');
    assert.equal(band({ resent: 0, completed: 0, failedAgain: 0, skipped: 0, unreached: 1, reason: 'x' }).key, 'result.couldNotStart');
    assert.equal(band({ unreached: 1, failedAgain: 1, skipped: 1, completed: 1, reason: 'x' }).key, 'result.stoppedPartway');
    assert.equal(band({ unreached: 1, failedAgain: 1, completed: 1, reason: 'x' }).key, 'result.stoppedPartway');
    assert.equal(band({ unreached: 1, skipped: 1, completed: 1 }).key, 'result.stoppedPartway');
    assert.equal(band({ unreached: 1, completed: 5 }, 'executing').key, 'result.stillResending', 'executing wins');
  });

  it('reads an absent, 0, null or non-numeric unreached as 0, so an older payload picks the keys it picked before', () => {
    const before = { completed: 47, skipped: 3 };
    for (const unreached of [undefined, 0, null, 'x', NaN, -1]) {
      assert.equal(band({ ...before, unreached }).key, 'result.skipped', String(unreached));
    }
    assert.equal(band({ ...before }).key, 'result.skipped');
    assert.equal(band({ completed: 49, failedAgain: 1, reason: REASON, unreached: null }).key, 'result.failedAgain');
    assert.equal(band({ unreached: 'x' }).key, 'result.allThrough');
  });

  it('takes the first matching row: executing, then interrupted, then could not start, then both, then failed again, then skipped', () => {
    assert.equal(band({ interrupted: 5, failedAgain: 2, skipped: 1, completed: 10 }, 'executing').key, 'result.stillResending');
    assert.equal(band({ interrupted: 5, failedAgain: 2, skipped: 1, completed: 10 }).key, 'result.interrupted');
    assert.equal(band({ resent: 0, completed: 0, failedAgain: 0, skipped: 0, reason: 'x', interrupted: 0 }).key, 'result.couldNotStart');
    assert.equal(band({ resent: 0, completed: 0, failedAgain: 1, reason: 'x' }).key, 'result.failedAgain', 'a failure is not "could not start"');
    assert.equal(band({ resent: 0, completed: 0, reason: '' }).key, 'result.allThrough', 'no reason is not "could not start"');
    assert.equal(band({ failedAgain: 1, skipped: 1, completed: 48, reason: 'x' }).key, 'result.failedAndSkipped');
    assert.equal(band({ failedAgain: 1, completed: 49, reason: 'x' }).key, 'result.failedAgain');
    assert.equal(band({ skipped: 1, completed: 49 }).key, 'result.skipped');
  });

  it('reads the noun from the incident\'s, else "message" and "messages", and copes with absent fields', () => {
    assert.equal(band({ total: 1, resent: 1, completed: 1 }, 'done', null).text, 'The message went through.');
    assert.equal(band({}, 'done', null).text, 'All 50 messages went through.');
    assert.equal(band({}, 'done', { one: 'order' }).text, 'All 50 messages went through.', 'a missing form falls back to the default');
    assert.equal(resultView({ ref: 'A', state: 'done', result: {} }, noun, renderPageText).text, 'All 0 orders went through.', 'an empty result reads as zero');
    assert.equal(band({ total: 'x', completed: null }).text, 'All 0 orders went through.', 'a field that is no number is zero');
  });

  it('passes the catalog\'s renderer the key and the slots as strings, the noun as its forms', () => {
    const seen = [];
    resultView({ ref: 'A', state: 'done', result: result({ completed: 48, failedAgain: 2, reason: REASON }) }, noun, (key, slots) => {
      seen.push([key, slots]);
      return key;
    });
    assert.deepEqual(seen, [
      ['result.failedAgain', { count: '50', itemNoun: noun, completed: '48', failedAgain: '2', failReason: REASON }],
      ['audit.recorded', {}],
    ]);
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
      itemState: '{item}: {state}',
      rerouteBefore: 'Message {example}: {from}',
      rerouteAfter: 'Message {example}: {to}',
      rerouteCopies: '{count} copies to {to}; the originals stay unchanged.',
      rerouteCopyOne: '1 copy to {to}; the original stays unchanged.',
      settingNow: 'Now: {old}',
      settingProposed: 'Proposed: {new}',
      settingNote: 'Nothing changes unless you approve.',
      partnerTo: 'To: {recipients}',
      partnerNote: 'Nothing is sent unless you approve. It goes to the Simulated mailbox, not to a real inbox.',
      partnerSent: 'Sent to the Simulated mailbox.',
      partnerSentSome: 'Sent to the Simulated mailbox for {completed} of {total} contacts.',
      partnerKept: "Approved and kept as a draft: email delivery isn't set up yet.",
      partnerNotSent: 'Not sent: {reason}.',
      expires: 'Expires {when}',
      notApprover: 'Only an approver can answer this request.',
      gone: 'That request is no longer available.',
      busyNotice: "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.",
      nounOne: 'message',
      nounOther: 'messages',
    });
  });

  it('are printable ASCII', () => {
    for (const text of Object.values(APPROVAL_TEXTS)) assert.ok(!/[^\x20-\x7e]/.test(text), text);
  });
});

describe('a request that the signed-in user may not answer (Story 25.5)', () => {
  const SENTENCES = {
    resend: 'Only an approver for resends can answer this request.',
    reroute: 'Only an approver for reroutes can answer this request.',
    suspend: 'Only an approver for suspending and resuming items can answer this request.',
    rollback: 'Only an approver for rollbacks can answer this request.',
    partner: 'Only an approver for partner notices can answer this request.',
    email: 'Only an approver for emails can answer this request.',
    tool: 'Only an approver for tool calls can answer this request.',
  };
  const FALLBACK = 'Only an approver can answer this request.';

  it('has the sentence of each of the seven kinds, and the fallback for no kind, an unknown one and a kind that is not 1 to 32 lower-case letters or _', () => {
    for (const [kind, text] of Object.entries(SENTENCES)) assert.equal(refusalText(kind, renderPageText), text, kind);
    for (const kind of [undefined, '', 'zz_new', 'Bad', 'RESEND', 'resend ', 're-send', 'setting', 'fix', '_', 'a'.repeat(33), 'a'.repeat(40)]) {
      assert.equal(refusalText(kind, renderPageText), FALLBACK, String(kind));
    }
    assert.equal(refusalText(7, renderPageText), FALLBACK, 'a kind that is no string');
  });

  it('asks the page\'s catalog for answered.notApprover and the kind with a capital first letter, and for the fallback key when that throws', () => {
    const asked = [];
    const render = (key) => {
      asked.push(key);
      if (key === 'answered.notApproverZz_new') throw new Error('no such key');
      return key;
    };
    assert.equal(refusalText('resend', render), 'answered.notApproverResend');
    assert.equal(refusalText('zz_new', render), 'answered.notApprover');
    assert.equal(refusalText(undefined, render), 'answered.notApprover');
    assert.deepEqual(asked, ['answered.notApproverResend', 'answered.notApproverZz_new', 'answered.notApprover', 'answered.notApprover']);
  });

  it('has a cannotAnswer text only while the request is pending and the payload says answerable is false (an absent answerable is answerable)', () => {
    assert.equal(approvalView(pending({ answerable: false, approverKind: 'reroute' }), ctx()).cannotAnswer, SENTENCES.reroute);
    assert.equal(approvalView(pending({ answerable: false }), ctx()).cannotAnswer, FALLBACK, 'with no kind: the fallback');
    assert.equal(approvalView(pending({ answerable: false, approverKind: 'zz_new' }), ctx()).cannotAnswer, FALLBACK, 'an unknown kind: the fallback');
    assert.equal(approvalView(pending({ answerable: true, approverKind: 'reroute' }), ctx()).cannotAnswer, '', 'answerable true');
    assert.equal(approvalView(pending(), ctx()).cannotAnswer, '', 'no answerable');
    assert.equal(approvalView(answered('approved', { answerable: false, approverKind: 'reroute' }), ctx()).cannotAnswer, '', 'an answered request');
    assert.equal(approvalView(pending({ answerable: false }), ctx()).pending, true, 'it is still a pending request');
  });
});

describe('the either-way row of the dry run (Story 7.8; DW-645)', () => {
  const MANY = 'All 50 dates are valid whether read month first or day first. Read month first, they match the day each order arrived.';
  const eitherWay = (over = {}, request = {}) => pending({ dryRun: dry({ before: '11/04/2026', after: '2026-11-04', eitherWay: true, reading: 'month first', ...over }), ...request });
  const rowOf = (approval) => approvalView(approval, ctx()).dryRun?.eitherWay;

  it('reads the notice\'s line in its many form, with the reading and the singular noun', () => {
    assert.equal(rowOf(eitherWay()), MANY);
    assert.equal(rowOf(eitherWay({ resend: 3 })), MANY.replace('50', '3'));
  });

  it('reads the one form, day first, when resend is 1 whatever affected is', () => {
    const one = 'The date is valid whether read month first or day first. Read day first, it matches the day the order arrived.';
    assert.equal(rowOf(eitherWay({ resend: 1, reading: 'day first' })), one);
    assert.equal(rowOf(eitherWay({ affected: 50, resend: 1, reading: 'day first' })), one, 'resend decides the form, not affected');
    assert.equal(rowOf(eitherWay({ affected: 1, resend: 2 })), MANY.replace('50', '2'), 'and affected of 1 does not make it the one form');
  });

  it('takes the noun from the dry run\'s singular, "message" when it has none', () => {
    assert.match(rowOf(eitherWay({ itemNoun: { one: 'message', other: 'messages' } })), /each message arrived\.$/);
    assert.match(rowOf(eitherWay({ itemNoun: { one: ' invoice ', other: 'other' } })), /each invoice arrived\.$/);
    assert.match(rowOf(eitherWay({ itemNoun: { other: 'orders' } })), /each message arrived\.$/);
    assert.match(rowOf(eitherWay({ itemNoun: undefined })), /each message arrived\.$/);
    assert.match(rowOf(eitherWay({ itemNoun: { one: '', other: '' } })), /each message arrived\.$/);
  });

  it('is absent unless the flag is true, the reading is not empty and resend is a number of at least 1', () => {
    assert.equal(rowOf(pending()), '', 'a plain dry run');
    assert.equal(rowOf(eitherWay({ eitherWay: false })), '', 'a false flag');
    assert.equal(rowOf(eitherWay({ eitherWay: false, reading: undefined })), '', 'a false flag and no reading');
    assert.equal(rowOf(eitherWay({ eitherWay: undefined })), '', 'a reading with no flag');
    assert.equal(rowOf(eitherWay({ reading: undefined })), '', 'a flag with no reading');
    assert.equal(rowOf(eitherWay({ reading: '  ' })), '', 'a blank reading');
    assert.equal(rowOf(eitherWay({ resend: undefined })), '', 'a flag with no resend');
    assert.equal(rowOf(eitherWay({ resend: 0 })), '', 'a resend of 0');
    assert.equal(rowOf(eitherWay({ resend: '3' })), '', 'a resend that is not a number');
    assert.equal(rowOf(eitherWay({ eitherWay: 'true' })), '', 'a flag that is not a boolean');
  });

  it('does not look at a date: the example does not change whether the row shows', () => {
    assert.equal(rowOf(eitherWay({ before: '10/16/2026', eitherWay: false, reading: undefined })), '');
    assert.equal(rowOf(eitherWay({ before: '10/16/2026' })), MANY, 'the flag alone decides');
  });

  it('stays on an answered request, which loses only "Nothing has changed yet."', () => {
    for (const state of ['approved', 'rejected', 'expired', 'done']) {
      const view = approvalView(answered(state, { dryRun: eitherWay().dryRun }), ctx());
      assert.equal(view.dryRun.eitherWay, MANY, state);
      assert.equal(view.dryRun.nothingYet, '', state);
    }
    assert.equal(approvalView(eitherWay(), ctx()).dryRun.nothingYet, 'Nothing has changed yet.');
  });

  it('leaves every other part of the dry run as it was', () => {
    const plain = approvalView(pending({ dryRun: dry({ before: '11/04/2026', after: '2026-11-04' }) }), ctx()).dryRun;
    const flagged = approvalView(eitherWay(), ctx()).dryRun;
    assert.deepEqual({ ...flagged, eitherWay: '' }, plain);
  });
});
