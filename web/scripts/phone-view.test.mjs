// Tests the simulated phone's view model (src/app/phone/phone-view.ts, Story 4.5): the fixed strings are the UX's exact wording, the
// phone's list exists only in demo mode and is the snapshot's phone then the store's other messages (a ref in both takes the store's
// payload, in the snapshot's place), and an approval request is pending on screen only when a message names a pending one that has
// no answer line. requestView (Story 6.3) is tested against every row of the I/O matrix that the page owns: the text's blocks and the
// inset of the dry run's example, the buttons (only for a message that names a request and has no answer, the server's or the
// phone's own), the answer line with its tone and icon, and the buttons' names. The module is imported as it is: Node strips its
// types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { PHONE_TEXTS, REQUEST_NAMES, pendingApproval, pendingRef, phoneOf, requestView } = await import(app('phone', 'phone-view.ts'));
const { approvalView } = await import(app('approvals', 'approval-view.ts'));
const { messageTime } = await import(app('chat', 'page-time.ts'));
const { renderMessageText } = await import(app('msg', 'catalog.ts'));
const { approvalTitle } = await import(app('rail', 'rail-view.ts'));

const message = (ref, text = `text ${ref}`, over = {}) => ({ ref, direction: 'out', text, approvalRef: '', createdAt: '2030-01-01T10:00:00Z', ...over });
const snapshot = (over = {}) => ({ demoMode: true, phone: [], ...over });

describe('the fixed strings', () => {
  it('are the UX\'s exact wording, with a straight apostrophe', () => {
    assert.equal(PHONE_TEXTS.name, 'OcuTalon');
    assert.equal(PHONE_TEXTS.empty, "Notifications, reminders and approval requests appear here. The simulated phone is a real channel in the production; you'll see it in the trace.");
  });
});

describe('phoneOf', () => {
  it('is undefined before the snapshot loads and outside demo mode, whatever else the snapshot carries', () => {
    assert.equal(phoneOf(undefined, { phones: {} }), undefined);
    assert.equal(phoneOf(snapshot({ demoMode: false, phone: [message('a')] }), { phones: { b: message('b') } }), undefined);
    assert.equal(phoneOf({ phone: [message('a')] }, undefined), undefined);
  });

  it('is empty in demo mode with nothing on the phone', () => {
    assert.deepEqual(phoneOf(snapshot(), { phones: {} }), []);
    assert.deepEqual(phoneOf(snapshot({ phone: undefined }), undefined), []);
  });

  it('is the snapshot\'s phone in its order', () => {
    const list = phoneOf(snapshot({ phone: [message('a'), message('b'), message('c')] }), { phones: {} });
    assert.deepEqual(list.map((one) => one.ref), ['a', 'b', 'c']);
  });

  it('adds the store\'s messages that the snapshot does not hold, in arrival order, after the snapshot\'s', () => {
    const list = phoneOf(snapshot({ phone: [message('a'), message('b')] }), { phones: { z: message('z'), y: message('y') } });
    assert.deepEqual(list.map((one) => one.ref), ['a', 'b', 'z', 'y']);
  });

  it('takes the store\'s payload for a ref that both hold, in the snapshot\'s place', () => {
    const list = phoneOf(snapshot({ phone: [message('a'), message('b', 'old'), message('c')] }), { phones: { b: message('b', 'new'), d: message('d') } });
    assert.deepEqual(list.map((one) => `${one.ref}:${one.text}`), ['a:text a', 'b:new', 'c:text c', 'd:text d']);
  });
});

describe('pendingApproval', () => {
  const approvals = { p: { state: 'pending' }, ok: { state: 'approved' } };

  it('is true when a message names a pending approval request', () => {
    assert.equal(pendingApproval([message('a'), message('b', 'x', { approvalRef: 'p' })], approvals), true);
  });

  it('is false for an approved request, an absent one, an empty ref and an empty list', () => {
    assert.equal(pendingApproval([message('a', 'x', { approvalRef: 'ok' })], approvals), false);
    assert.equal(pendingApproval([message('a', 'x', { approvalRef: 'gone' })], approvals), false);
    assert.equal(pendingApproval([message('a')], approvals), false);
    assert.equal(pendingApproval([], approvals), false);
    assert.equal(pendingApproval([message('a', 'x', { approvalRef: 'p' })], undefined), false);
  });
});

describe('pendingRef (Story 4.7)', () => {
  const approvals = { p1: { state: 'pending' }, p2: { state: 'pending' }, ok: { state: 'approved' } };

  it('is the ref of the newest message that names a pending approval request', () => {
    const list = [message('a', 'x', { approvalRef: 'p1' }), message('b'), message('c', 'x', { approvalRef: 'p2' }), message('d')];
    assert.equal(pendingRef(list, approvals), 'c');
    assert.equal(pendingRef(list.slice(0, 2), approvals), 'a');
  });

  it('skips an answered or unknown request for an older pending one, and is undefined with none', () => {
    assert.equal(pendingRef([message('a', 'x', { approvalRef: 'p1' }), message('b', 'x', { approvalRef: 'ok' }), message('c', 'x', { approvalRef: 'gone' })], approvals), 'a');
    assert.equal(pendingRef([message('a', 'x', { approvalRef: 'ok' }), message('b')], approvals), undefined);
    assert.equal(pendingRef([], approvals), undefined);
    assert.equal(pendingRef([message('a', 'x', { approvalRef: 'p1' })], undefined), undefined);
  });

  it('leaves pendingApproval as it was: true exactly when a message names a pending request', () => {
    assert.equal(pendingApproval([message('a', 'x', { approvalRef: 'p1' })], approvals), true);
    assert.equal(pendingApproval([message('a', 'x', { approvalRef: 'ok' })], approvals), false);
    assert.equal(pendingApproval([message('a', 'x', { approvalRef: 'gone' }), message('b')], approvals), false);
    assert.equal(pendingApproval([], approvals), false);
  });
});

describe('pendingApproval and pendingRef (Story 6.3)', () => {
  const approvals = { p1: { state: 'pending' }, p2: { state: 'pending' } };

  it('skip a message that has an answer line, whatever the store says, and fall back to an older pending request', () => {
    const list = [message('a', 'x', { approvalRef: 'p1' }), message('b', 'x', { approvalRef: 'p2', answer: 'Approved from the web chat at 14:15.' })];
    assert.equal(pendingRef(list, approvals), 'a');
    assert.equal(pendingApproval(list, approvals), true);
    assert.equal(pendingApproval(list.slice(1), approvals), false);
    assert.equal(pendingRef(list.slice(1), approvals), undefined);
    assert.equal(pendingApproval([message('c', 'x', { approvalRef: 'p1', answer: '' })], approvals), true, 'an empty answer is no answer');
  });
});

describe('requestView (Story 6.3)', () => {
  const NOW = Date.parse('2026-10-16T18:20:00Z');
  const context = { viewOf: (approval) => approvalView(approval, ctx) };
  const ctx = {
    nowMs: NOW,
    instanceZone: 'UTC',
    onlineDemo: false,
    user: 'zzana',
    timeBeside: (iso) => messageTime(iso, NOW, 'UTC', false),
    whenBeside: (iso, now) => messageTime(iso, now, 'UTC', false),
    render: (key, slots) => renderMessageText(key, slots),
    title: approvalTitle,
  };
  const TEXT = [
    '50 orders failed since 18:12. Data format change. I can repair the order date and resend 50 orders. Approve?',
    "Dry run: 50 orders affected. Example: OrderDate 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet.",
    'Details and trace: on your OcuTalon page.',
  ];
  const request = (over = {}) => message('m1', TEXT.join('\n\n'), { approvalRef: 'A', ...over });
  const approval = (over = {}) => ({
    ref: 'A',
    kind: 'fix',
    state: 'pending',
    incidentRef: 'R',
    dryRun: { affected: 50, resend: 50, field: 'OrderDate', before: '10/16/2026', after: '2026-10-16', itemNoun: { one: 'order', other: 'orders' } },
    ...over,
  });
  const answered = (state, channel, over = {}) => approval({ state, answeredChannel: channel, answeredAt: '2026-10-16T18:15:00Z', answeredBy: 'zzana', ...over });

  it('splits the text at blank lines and sets the dry run\'s example as an inset, with its before and after values as parts of their own', () => {
    const view = requestView(request(), approval(), undefined, context);
    assert.deepEqual(view.blocks.map((one) => one.inset), [false, true, false]);
    assert.deepEqual(view.blocks.map((one) => one.text), TEXT);
    assert.deepEqual(view.blocks[0].parts, [{ text: TEXT[0], kind: 'plain' }]);
    assert.deepEqual(view.blocks[1].parts, [
      { text: 'Dry run: 50 orders affected. Example: OrderDate ', kind: 'plain' },
      { text: '10/16/2026', kind: 'before' },
      { text: ' becomes ', kind: 'plain' },
      { text: '2026-10-16', kind: 'after' },
      { text: ". I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet.", kind: 'plain' },
    ]);
    assert.equal(view.blocks[1].parts.map((one) => one.text).join(''), TEXT[1], 'the parts are the text, whole');
  });

  it('leaves the parts out when the example ends the block, and keeps a block of its own lines whole', () => {
    const view = requestView(request({ text: 'Example: OrderDate 10/16/2026 becomes 2026-10-16' }), approval(), undefined, context);
    assert.deepEqual(view.blocks[0].parts.map((one) => [one.text, one.kind]), [['Example: OrderDate ', 'plain'], ['10/16/2026', 'before'], [' becomes ', 'plain'], ['2026-10-16', 'after']]);
    const lines = requestView(request({ text: 'Failures:\nA: 5\nB: 2' }), undefined, undefined, context);
    assert.deepEqual(lines.blocks.map((one) => one.text), ['Failures:\nA: 5\nB: 2']);
  });

  it('shows plain paragraphs when the page has no dry run for the request, or its example is not in the text', () => {
    for (const [name, over] of [
      ['no payload', undefined],
      ['no dry run', approval({ dryRun: undefined })],
      ['another field', approval({ dryRun: { ...approval().dryRun, field: 'ShipDate' } })],
      ['another before', approval({ dryRun: { ...approval().dryRun, before: '16/10/2026' } })],
      ['an empty after', approval({ dryRun: { ...approval().dryRun, after: '' } })],
    ]) {
      const view = requestView(request(), over, undefined, context);
      assert.deepEqual(view.blocks.map((one) => one.inset), [false, false, false], name);
      assert.deepEqual(view.blocks.map((one) => one.parts.length), [1, 1, 1], name);
    }
  });

  it('names the buttons with the object from the request\'s view, else Approve and Reject', () => {
    const named = requestView(request(), approval(), undefined, context);
    assert.equal(named.approveName, 'Approve: repair and resend 50 orders');
    assert.equal(named.rejectName, 'Reject: repair and resend 50 orders');
    const plain = requestView(request(), undefined, undefined, context);
    assert.deepEqual([plain.approveName, plain.rejectName], ['Approve', 'Reject']);
    assert.deepEqual(REQUEST_NAMES, { approve: 'Approve', reject: 'Reject' });
  });

  it('has the buttons only for a message that names a request and has no answer, and never from the store', () => {
    assert.equal(requestView(request(), approval(), undefined, context).buttons, true);
    assert.equal(requestView(request(), undefined, undefined, context).buttons, true, 'the store holding nothing for the request changes nothing');
    assert.equal(requestView(request(), answered('approved', 'web'), undefined, context).buttons, true, 'nor does an answered request in the store: the phone follows only its own channel');
    assert.equal(requestView(request(), answered('approved', 'web'), undefined, context).answer, undefined);
    assert.equal(requestView(request({ approvalRef: '' }), approval(), undefined, context).buttons, false, 'a message with no request');
    assert.equal(requestView(message('m2', 'zz'), approval(), undefined, context).buttons, false);
    assert.equal(requestView(request({ answer: 'Approved from the web chat at 14:15.' }), approval(), undefined, context).buttons, false, 'a message with the server\'s answer');
    assert.equal(requestView(request(), approval(), answered('approved', 'phone'), context).buttons, false, 'and one the phone\'s own press answered');
  });

  it('shows the phone\'s own answer in message form, with the tone and icon of the outcome', () => {
    const approved = requestView(request(), approval(), answered('approved', 'phone'), context).answer;
    assert.deepEqual(approved, { text: 'Approved from the simulated phone at 18:15.', tone: 'approved', icon: 'circle-check' });
    const rejected = requestView(request(), approval(), answered('rejected', 'phone'), context).answer;
    assert.deepEqual(rejected, { text: 'Rejected from the simulated phone at 18:15. Nothing was changed.', tone: 'rejected', icon: 'circle-slash' });
    const late = requestView(request(), approval(), answered('approved', 'web'), context);
    assert.equal(late.answer.text, 'Approved from the web chat at 18:15.', 'the winner of a late press');
    const named = requestView(request(), approval(), answered('approved', 'telegram', { answeredBy: 'zzsam' }), context).answer;
    assert.equal(named.text, 'Approved by zzsam from Telegram at 18:15.');
    const dated = requestView(request(), approval(), answered('approved', 'web', { answeredAt: '2026-10-15T18:15:00Z' }), context).answer;
    assert.equal(dated.text, 'Approved from the web chat on Thursday at 18:15.', 'a dated time reads "on"');
    const executing = requestView(request(), approval(), answered('executing', 'phone'), context).answer;
    assert.equal(executing.tone, 'approved');
  });

  it('shows the server\'s answer line first, with the tone of the local view, else of the store\'s state, else neutral with no icon', () => {
    const line = 'Approved from the web chat at 14:15.';
    const sure = requestView(request({ answer: line }), approval(), answered('rejected', 'phone'), context).answer;
    assert.deepEqual(sure, { text: line, tone: 'rejected', icon: 'circle-slash' }, 'the local view\'s tone, the server\'s text');
    const fromStore = requestView(request({ answer: line }), answered('approved', 'web'), undefined, context).answer;
    assert.deepEqual(fromStore, { text: line, tone: 'approved', icon: 'circle-check' });
    const expired = requestView(request({ answer: 'Expired at 14:13. Nothing was changed.' }), answered('expired', 'web', { expiresAt: '2026-10-16T14:13:00Z' }), undefined, context).answer;
    assert.deepEqual([expired.tone, expired.icon], ['expired', 'clock']);
    assert.deepEqual(requestView(request({ answer: line }), approval(), undefined, context).answer, { text: line, tone: 'neutral', icon: undefined }, 'a request that is still pending in the store');
    assert.deepEqual(requestView(request({ answer: line }), undefined, undefined, context).answer, { text: line, tone: 'neutral', icon: undefined }, 'and one the store does not hold');
    assert.equal(requestView(request({ answer: '  ' }), approval(), undefined, context).buttons, true, 'a blank answer is no answer');
  });
});
