// Tests the live store of the page (src/app/live/live-store.ts): the snapshot intake, the apply of events in order, a repeat
// ignored, an entity replaced by its key in place and a new one added (a decision first), a skip on either stream or a changed
// epoch asking for a reload without applying anything, the two streams' independent cursors, and that every event type of
// payloads.ts has a place in COLLECTIONS. The module is imported as it is: Node strips its types, which holds only while it
// keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const live = join(here, '..', 'src', 'app', 'live');
const { COLLECTIONS, applyEvents, chatKey, fromSnapshot, withAnswer } = await import(pathToFileURL(join(live, 'live-store.ts')).href);

/** A snapshot with a little of everything. */
function snapshot(overrides = {}) {
  return {
    version: '',
    instanceZone: 'UTC',
    epoch: 'epoch-1',
    streams: { session: 5, instance: 2 },
    chat: [
      { type: 'chat.message', payload: { ref: 'turn-1', state: 'done' } },
      { type: 'incident', payload: { ref: 'inc-1', state: 'open', count: 3 } },
    ],
    rail: {
      approvals: [{ ref: 'app-1', state: 'pending' }],
      checks: [{ ref: 'chk-1', production: 'Zz.Prod' }],
      reminders: [
        { ref: 'rem-1', state: 'pending', dueAt: '2030-01-01T10:00:00Z' },
        { ref: 'rem-2', state: 'pending', dueAt: '2030-01-01T11:00:00Z' },
      ],
      decisions: [
        { ref: 'dec-2', outcome: 'notify' },
        { ref: 'dec-1', outcome: 'stay_quiet' },
      ],
    },
    user: 'someone',
    onlineDemo: false,
    demoMode: false,
    models: { triage: '', diagnosis: '', chat: '' },
    telegram: { included: true, state: 'off', botUserName: '', paired: false, displayName: '', pausedUntil: '' },
    status: [{ condition: 'noModelKey', active: true }],
    ...overrides,
  };
}

/** One event of a stream. */
function event(stream, seq, type, payload) {
  return { seq, stream, ts: '2030-01-01T10:00:00Z', type, payload };
}

/** The store of a snapshot, then a poll of the events on top of it. */
function apply(store, events, epoch = 'epoch-1') {
  return applyEvents(store, { epoch, events });
}

describe('the snapshot intake', () => {
  it('takes the cursors, the epoch, the chat, the rail, the status and the Telegram block', () => {
    const store = fromSnapshot(snapshot());
    assert.equal(store.epoch, 'epoch-1');
    assert.deepEqual(store.cursors, { session: 5, instance: 2 });
    assert.deepEqual(store.chat.map(chatKey), ['chat.message:turn-1', 'incident:inc-1']);
    assert.deepEqual(Object.keys(store.approvals), ['app-1']);
    assert.deepEqual(Object.keys(store.checks), ['chk-1']);
    assert.deepEqual(Object.keys(store.reminders), ['rem-1', 'rem-2']);
    assert.deepEqual(store.decisions.map((decision) => decision.ref), ['dec-2', 'dec-1']);
    assert.deepEqual(Object.keys(store.status), ['noModelKey']);
    assert.equal(store.telegram.included, true);
    assert.equal(store.telegram.paired, false);
  });

  it("adds the decision of an incident entry to the decisions after the rail's, and no ref twice", () => {
    const diagnose = { ref: 'dec-diag', kind: 'diagnose', outcome: 'act' };
    const repeated = { ref: 'dec-1', outcome: 'stay_quiet' };
    const source = snapshot({
      chat: [
        { type: 'chat.message', payload: { ref: 'turn-1', state: 'done' } },
        { type: 'incident', payload: { ref: 'inc-1', state: 'open', decisionRef: 'dec-diag' }, decision: diagnose },
        { type: 'incident', payload: { ref: 'inc-2', state: 'open', decisionRef: 'dec-1' }, decision: repeated },
        { type: 'incident', payload: { ref: 'inc-3', state: 'open', decisionRef: 'dec-diag' }, decision: diagnose },
        { type: 'incident', payload: { ref: 'inc-4', state: 'open' } },
      ],
    });
    const store = fromSnapshot(source);
    assert.deepEqual(
      store.decisions.map((decision) => decision.ref),
      ['dec-2', 'dec-1', 'dec-diag'],
      "the rail's decisions first, then the incident's own, once",
    );
    assert.equal(store.decisions[2], diagnose);
    assert.equal(source.rail.decisions.length, 2, 'the snapshot is not changed');
  });

  it('copies the snapshot: later events do not change it', () => {
    const source = snapshot();
    const store = fromSnapshot(source);
    const { store: next } = apply(store, [event('session', 6, 'chat.message', { ref: 'turn-2' })]);
    assert.equal(source.chat.length, 2);
    assert.equal(store.chat.length, 2);
    assert.equal(next.chat.length, 3);
  });
});

describe('applying events in order', () => {
  it('applies the event after the cursor and advances that cursor only', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' })]);
    assert.equal(result.reload, false);
    assert.deepEqual(result.store.cursors, { session: 6, instance: 2 });
    assert.deepEqual(Object.keys(result.store.reminders), ['rem-1', 'rem-2', 'rem-3']);
    assert.deepEqual(store.cursors, { session: 5, instance: 2 }, 'the old store is unchanged');
  });

  it('applies several events of a stream, one after the other', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' }),
      event('session', 7, 'reminder', { ref: 'rem-3', state: 'fired' }),
      event('session', 8, 'reminder', { ref: 'rem-4', state: 'pending' }),
    ]);
    assert.equal(result.reload, false);
    assert.equal(result.store.cursors.session, 8);
    assert.equal(result.store.reminders['rem-3'].state, 'fired');
    assert.deepEqual(Object.keys(result.store.reminders), ['rem-1', 'rem-2', 'rem-3', 'rem-4']);
  });

  it('keeps the two streams apart: each has its own cursor and a skip on one is not the other\'s', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' }),
      event('instance', 3, 'status', { condition: 'dailyCap', active: true }),
    ]);
    assert.equal(result.reload, false);
    assert.deepEqual(result.store.cursors, { session: 6, instance: 3 });
    assert.deepEqual(Object.keys(result.store.status), ['noModelKey', 'dailyCap']);
    const instanceOnly = apply(store, [event('instance', 3, 'status', { condition: 'noModelKey', active: false })]);
    assert.deepEqual(instanceOnly.store.cursors, { session: 5, instance: 3 });
    assert.equal(instanceOnly.store.status['noModelKey'].active, false);
  });

  it('returns the same store for an empty poll', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, []);
    assert.equal(result.store, store);
    assert.equal(result.reload, false);
  });
});

describe('a repeat is ignored', () => {
  it('ignores an event at the cursor and below it, on either stream', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 5, 'reminder', { ref: 'rem-1', state: 'fired' }),
      event('session', 3, 'reminder', { ref: 'rem-9', state: 'pending' }),
      event('instance', 2, 'status', { condition: 'dailyCap', active: true }),
    ]);
    assert.equal(result.reload, false);
    assert.equal(result.store, store, 'nothing changes');
    assert.equal(result.store.reminders['rem-1'].state, 'pending');
  });

  it('applies a poll twice with the same result', () => {
    const store = fromSnapshot(snapshot());
    const events = [event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' })];
    const once = apply(store, events);
    const twice = apply(once.store, events);
    assert.equal(twice.reload, false);
    assert.equal(twice.store, once.store);
  });
});

describe('an entity is replaced by its key, or added', () => {
  it('replaces an entry of the chat in place and appends a new one', () => {
    const store = fromSnapshot(snapshot());
    const replaced = apply(store, [event('session', 6, 'incident', { ref: 'inc-1', state: 'resolved', count: 4 })]).store;
    assert.deepEqual(replaced.chat.map(chatKey), ['chat.message:turn-1', 'incident:inc-1']);
    assert.equal(replaced.chat[1].payload.state, 'resolved');
    const appended = apply(replaced, [
      event('session', 7, 'notification', { ref: 'note-1' }),
      event('session', 8, 'chat.message', { ref: 'turn-2', state: 'queued' }),
      event('session', 9, 'chat.message', { ref: 'turn-2', state: 'done' }),
    ]).store;
    assert.deepEqual(appended.chat.map(chatKey), ['chat.message:turn-1', 'incident:inc-1', 'notification:note-1', 'chat.message:turn-2']);
    assert.equal(appended.chat[3].payload.state, 'done');
  });

  it('keys the chat by type and ref: a ref of another type is another entry', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [event('session', 6, 'notification', { ref: 'turn-1' })]).store;
    assert.deepEqual(result.chat.map(chatKey), ['chat.message:turn-1', 'incident:inc-1', 'notification:turn-1']);
  });

  it('replaces a decision in place and puts a new one first', () => {
    const store = fromSnapshot(snapshot());
    const replaced = apply(store, [event('session', 6, 'decision', { ref: 'dec-1', outcome: 'notify' })]).store;
    assert.deepEqual(replaced.decisions.map((decision) => decision.ref), ['dec-2', 'dec-1']);
    assert.equal(replaced.decisions[1].outcome, 'notify');
    const added = apply(replaced, [event('session', 7, 'decision', { ref: 'dec-3', outcome: 'notify' })]).store;
    assert.deepEqual(added.decisions.map((decision) => decision.ref), ['dec-3', 'dec-2', 'dec-1']);
  });

  it('replaces by ref in the maps, and by condition and by turn ref where those are the keys', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 6, 'approval', { ref: 'app-1', state: 'answered' }),
      event('session', 7, 'check', { ref: 'chk-2', production: 'Zz.Other' }),
      event('session', 8, 'check', { ref: 'chk-1', production: 'Zz.Renamed' }),
      event('session', 9, 'turn.step', { turnRef: 'turn-3', decisionRef: 'dec-3', label: 'Looking' }),
      event('session', 10, 'turn.step', { turnRef: 'turn-3', decisionRef: 'dec-3', label: 'Writing' }),
      event('session', 11, 'turn.step', { turnRef: 'turn-4', decisionRef: 'dec-3', label: 'Reading' }),
      event('session', 12, 'phone', { ref: 'ph-1' }),
      event('session', 13, 'mailbox', { ref: 'mb-1', unread: true }),
      event('session', 14, 'watch.progress', { ref: 'chk-1', stage: 'first' }),
    ]).store;
    assert.equal(result.approvals['app-1'].state, 'answered');
    assert.deepEqual(Object.keys(result.checks), ['chk-1', 'chk-2']);
    assert.equal(result.checks['chk-1'].production, 'Zz.Renamed');
    assert.deepEqual(Object.keys(result.turnSteps), ['turn-3', 'turn-4']);
    assert.equal(result.turnSteps['turn-3'].label, 'Writing');
    assert.equal(result.turnSteps['turn-4'].label, 'Reading', 'a step of another turn with the same decision ref is its own');
    assert.deepEqual(Object.keys(result.phones), ['ph-1']);
    assert.equal(result.mailboxes['mb-1'].unread, true);
    assert.equal(result.watchProgress['chk-1'].stage, 'first');
  });

  it('merges a pairing into the Telegram block and replaces the single values', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 6, 'pairing', { paired: true, displayName: 'Ana' }),
      event('session', 7, 'guide.state', { runEpoch: 1, step: 2 }),
      event('session', 8, 'guide.state', { runEpoch: 1, step: 3 }),
      event('session', 9, 'reset', { nextReset: '2030-01-02T00:00:00Z' }),
      event('session', 10, 'breakfeed.progress', { state: 'running' }),
    ]).store;
    assert.deepEqual(result.telegram, { included: true, state: 'off', botUserName: '', paired: true, displayName: 'Ana', pausedUntil: '' });
    assert.equal(result.guideState.step, 3);
    assert.equal(result.reset.nextReset, '2030-01-02T00:00:00Z');
    assert.equal(result.breakfeedProgress.state, 'running');
  });

  it('advances the cursor past an event of a type it does not know', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [event('session', 6, 'zz.future', { ref: 'x' })]);
    assert.equal(result.reload, false);
    assert.equal(result.store.cursors.session, 6);
    assert.equal(result.store.chat.length, 2);
  });
});

describe('a skip or a new epoch asks for a reload', () => {
  it('reloads when an event skips a Seq of the session stream, and applies nothing', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' }),
      event('session', 8, 'reminder', { ref: 'rem-4', state: 'pending' }),
    ]);
    assert.equal(result.reload, true);
    assert.equal(result.store, store, 'the store is the one it was given');
  });

  it('reloads when an event skips a Seq of the instance stream, even after a good session event', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [
      event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' }),
      event('instance', 4, 'status', { condition: 'dailyCap', active: true }),
    ]);
    assert.equal(result.reload, true);
    assert.equal(result.store, store);
    assert.deepEqual(result.store.cursors, { session: 5, instance: 2 });
  });

  it('reloads when the first event after the cursor is missing', () => {
    const store = fromSnapshot(snapshot());
    assert.equal(apply(store, [event('session', 7, 'reminder', { ref: 'rem-3' })]).reload, true);
    assert.equal(apply(store, [event('instance', 5, 'status', { condition: 'dailyCap' })]).reload, true);
  });

  it('reloads when the epoch is not the store\'s, whatever the events are', () => {
    const store = fromSnapshot(snapshot());
    const result = apply(store, [event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' })], 'epoch-2');
    assert.equal(result.reload, true);
    assert.equal(result.store, store);
    assert.equal(apply(store, [], 'epoch-2').reload, true, 'an empty poll too');
  });

  it('says whether the reload is an epoch change (Story 16.4) or a skipped Seq', () => {
    const store = fromSnapshot(snapshot());
    assert.equal(apply(store, [event('session', 6, 'reminder', { ref: 'rem-3' })], 'epoch-2').epochChanged, true, 'another epoch');
    assert.equal(apply(store, [], 'epoch-2').epochChanged, true, 'another epoch with no event');
    assert.equal(apply(store, [event('session', 8, 'reminder', { ref: 'rem-3' })]).epochChanged, false, 'a skipped Seq');
    assert.equal(apply(store, [event('instance', 5, 'status', { condition: 'dailyCap' })]).epochChanged, false, 'a skipped instance Seq');
    const good = apply(store, [event('session', 6, 'reminder', { ref: 'rem-3', state: 'pending' })]);
    assert.equal(good.reload || good.epochChanged, false, 'a good poll is neither');
    assert.equal(apply(store, []).epochChanged, false, 'an empty poll of the same epoch is neither');
  });
});

describe('COLLECTIONS', () => {
  it('has an entry for every event type of payloads.ts', () => {
    const text = readFileSync(join(live, 'payloads.ts'), 'utf8');
    const union = /export type LiveEventType =([\s\S]*?);/.exec(text)?.[1] ?? '';
    const types = [...union.matchAll(/'([^']+)'/g)].map((match) => match[1]);
    assert.equal(types.length, 18, `the 18 event types are read: ${types.join(' ')}`);
    for (const type of types) {
      assert.ok(COLLECTIONS[type], `${type} has an entry`);
      assert.ok(COLLECTIONS[type].collection, `${type} names a collection`);
    }
    assert.deepEqual(Object.keys(COLLECTIONS).sort(), [...types].sort(), 'and nothing else is in the table');
  });

  it('keeps the latest heartbeat event (Story 39.5): the cursor advances, the payload is replaced and nothing else changes', () => {
    assert.deepEqual(COLLECTIONS['heartbeat'], { collection: 'heartbeat', key: null });
    const store = fromSnapshot(snapshot());
    assert.equal(store.heartbeat, undefined, 'the snapshot carries none');
    const first = apply(store, [event('session', 6, 'heartbeat', { on: true, interval: 30, lastBeatAt: '2030-01-01T10:00:00Z' })]);
    assert.deepEqual(first.store.heartbeat, { on: true, interval: 30, lastBeatAt: '2030-01-01T10:00:00Z' }, 'the payload is kept');
    const result = apply(first.store, [event('session', 7, 'heartbeat', { on: false, interval: 60, lastOutcome: 'ignore' })]);
    assert.equal(result.reload, false, 'no reload');
    assert.equal(result.epochChanged, false);
    assert.equal(result.store.cursors.session, 7, 'the session cursor is at the last heartbeat event');
    assert.deepEqual(result.store.heartbeat, { on: false, interval: 60, lastOutcome: 'ignore' }, 'the later payload replaces the earlier one');
    assert.deepEqual({ ...result.store, cursors: store.cursors, heartbeat: undefined }, store, 'and nothing else in the store changed');
  });

  it('keys the entities the way the design says', () => {
    assert.deepEqual(COLLECTIONS['chat.message'], { collection: 'chat', key: 'ref' });
    assert.deepEqual(COLLECTIONS['notification'], { collection: 'chat', key: 'ref' });
    assert.deepEqual(COLLECTIONS['incident'], { collection: 'chat', key: 'ref' });
    assert.deepEqual(COLLECTIONS['decision'], { collection: 'decisions', key: 'ref' });
    assert.deepEqual(COLLECTIONS['status'], { collection: 'status', key: 'condition' });
    assert.deepEqual(COLLECTIONS['turn.step'], { collection: 'turnSteps', key: 'turnRef' });
    assert.deepEqual(COLLECTIONS['pairing'], { collection: 'telegram', key: null });
    for (const type of ['guide.state', 'reset', 'breakfeed.progress']) {
      assert.equal(COLLECTIONS[type].key, null, `${type} is a single value`);
    }
  });

  it('keeps the documents by ref, a removed one included, and the snapshot starts with none (Story 34.2)', () => {
    assert.deepEqual(COLLECTIONS['document'], { collection: 'documents', key: 'ref' });
    const store = fromSnapshot(snapshot());
    assert.deepEqual(Object.keys(store.documents), [], 'a snapshot carries no documents: the page lists them from GET /v1/documents');
    const first = apply(store, [event('session', 6, 'document', { ref: 'doc-1', name: 'Results runbook.md', state: 'indexing' })]);
    assert.deepEqual(Object.keys(first.store.documents), ['doc-1']);
    const second = apply(first.store, [
      event('session', 7, 'document', { ref: 'doc-1', name: 'Results runbook.md', state: 'ready' }),
      event('session', 8, 'document', { ref: 'doc-1', removed: true }),
    ]);
    assert.deepEqual(second.store.documents['doc-1'], { ref: 'doc-1', removed: true }, 'the last event of a ref replaces the earlier ones');
    assert.equal(second.reload, false);
  });
});

describe('an answer\'s reply (withAnswer)', () => {
  /** A store that holds app-1 and app-2 as pending requests. */
  const held = (states = {}) =>
    fromSnapshot(
      snapshot({
        rail: {
          approvals: [
            { ref: 'app-1', state: states['app-1'] ?? 'pending', title: 'one' },
            { ref: 'app-2', state: states['app-2'] ?? 'pending', title: 'two' },
          ],
          checks: [],
          reminders: [],
          decisions: [],
        },
      }),
    );

  it('replaces a pending request with the reply\'s view, whatever answered state it shows (rejected, approved, executing or expired), and keeps the other pending request', () => {
    const store = held();
    for (const state of ['rejected', 'approved', 'executing', 'expired']) {
      const next = withAnswer(store, { ref: 'app-1', state, title: 'one' });
      assert.notEqual(next, store);
      assert.equal(next.approvals['app-1'].state, state);
      assert.equal(next.approvals['app-2'].state, 'pending', 'the other pending request is kept');
      assert.deepEqual(Object.keys(next.approvals), ['app-1', 'app-2']);
    }
  });

  it('moves no cursor and changes nothing it was given', () => {
    const store = held();
    const before = JSON.stringify(store);
    const next = withAnswer(store, { ref: 'app-1', state: 'rejected' });
    assert.deepEqual(next.cursors, store.cursors);
    assert.equal(next.epoch, store.epoch);
    assert.equal(JSON.stringify(store), before, 'the input store is unchanged');
    assert.equal(store.approvals['app-1'].state, 'pending');
  });

  it('gives the same store back for a request that has left pending (an executing request keeps its view)', () => {
    for (const state of ['executing', 'rejected']) {
      const store = held({ 'app-1': state });
      assert.equal(withAnswer(store, { ref: 'app-1', state: 'approved' }), store, state);
    }
  });

  it('gives the same store back for a Ref the store does not hold', () => {
    const store = held();
    assert.equal(withAnswer(store, { ref: 'app-9', state: 'rejected' }), store);
    assert.equal(Object.keys(store.approvals).includes('app-9'), false);
  });

  it('gives the same store back for a reply that is still pending or has no state', () => {
    const store = held();
    assert.equal(withAnswer(store, { ref: 'app-1', state: 'pending' }), store);
    assert.equal(withAnswer(store, { ref: 'app-1' }), store);
  });

  it('is followed by the request\'s own event: it leaves the request answered, and a later event replaces it with no step back', () => {
    const base = held();
    const answered = withAnswer(base, { ref: 'app-1', state: 'rejected', title: 'one' });
    assert.notEqual(answered, base);
    assert.equal(answered.approvals['app-1'].state, 'rejected', 'the reply answered it before any event');
    assert.deepEqual(answered.cursors, base.cursors, 'and moved no cursor');
    const same = apply(answered, [event('session', 6, 'approval', { ref: 'app-1', state: 'rejected', title: 'one' })]);
    assert.equal(same.reload, false);
    assert.equal(same.store.approvals['app-1'].state, 'rejected');
    assert.equal(same.store.cursors.session, 6);
    const later = apply(same.store, [event('session', 7, 'approval', { ref: 'app-1', state: 'executing', title: 'one' })]);
    assert.equal(later.store.approvals['app-1'].state, 'executing');
  });
});
