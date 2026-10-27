// Tests the simulated phone's view model (src/app/phone/phone-view.ts, Story 4.5): the fixed strings are the UX's exact wording, the
// phone's list exists only in demo mode and is the snapshot's phone then the store's other messages (a ref in both takes the store's
// payload, in the snapshot's place), and an approval request is pending on screen only when a message names a pending one. The module
// is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { PHONE_TEXTS, pendingApproval, pendingRef, phoneOf } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'phone', 'phone-view.ts')).href);

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
