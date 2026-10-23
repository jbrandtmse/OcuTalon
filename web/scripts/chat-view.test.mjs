// Tests the chat panel's view model (src/app/chat/chat-view.ts): the order of the entries and the merge of the page's own
// messages, every reply state of a turn, the elapsed seconds and the step label of a running one, the decision strip's inputs of
// a turn (strip, newest, fallback reason, decision, cost, check rows), what the turn indicator shows, the captions, when the chat is
// fresh, the client ids, and the fixed strings against the UX's wording. The module is imported as it is: Node strips its types, which
// holds only while it keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { CHAT_TEXTS, chatView, indicatorOf, isFreshChat, newClientId } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'chat-view.ts')).href);

const NOW = 1_000_000;
const NO_RUNNING = new Map();

/** A chat.message entry of the store. */
const turn = (ref, over = {}) => ({
  type: 'chat.message',
  payload: { ref, clientId: `c-${ref}`, channel: 'web', fromGuide: false, state: 'done', text: `text ${ref}`, replyText: `reply ${ref}`, createdAt: '2026-10-22T14:11:00Z', ...over },
});
const incident = (ref) => ({ type: 'incident', payload: { ref, state: 'open' } });
const notice = (ref) => ({ type: 'notification', payload: { ref, text: 'Reminder: stretch.' } });
/** A message of the page's outbox. */
const local = (clientId, status, over = {}) => ({ clientId, text: `local ${clientId}`, fromGuide: false, sentAt: '2026-10-22T14:12:00Z', status, ...over });

const keys = (views) => views.map((view) => view.key);

describe('the order of the entries', () => {
  it('lists the store\'s chat.message entries in store order and renders nothing for incidents and notices', () => {
    const chat = [turn('B'), incident('I1'), turn('A'), notice('N1'), turn('C')];
    assert.deepEqual(keys(chatView(chat, [], NO_RUNNING, NOW)), ['c-B', 'c-A', 'c-C']);
  });

  it('follows the store\'s entries with the page\'s own messages that the store does not hold, in send order', () => {
    const views = chatView([turn('A'), turn('B')], [local('x1', 'sent'), local('x2', 'sending')], NO_RUNNING, NOW);
    assert.deepEqual(keys(views), ['c-A', 'c-B', 'x1', 'x2']);
    assert.deepEqual(views.map((view) => view.send), ['stored', 'stored', 'sent', 'sending']);
  });

  it('drops a local message as soon as the store holds a chat.message with its clientId, even after it failed', () => {
    for (const status of ['sending', 'sent', 'failed']) {
      const views = chatView([turn('A')], [local('c-A', status), local('other', 'failed')], NO_RUNNING, NOW);
      assert.deepEqual(keys(views), ['c-A', 'other'], status);
      assert.equal(views[0].send, 'stored', `${status}: the stored turn stands for it`);
      assert.equal(views[0].text, 'text A', `${status}: with the server's text`);
    }
  });

  it('keys a turn by its clientId, else by its ref', () => {
    const views = chatView([turn('T', { clientId: '' }), turn('U', { clientId: undefined })], [], NO_RUNNING, NOW);
    assert.deepEqual(keys(views), ['T', 'U']);
  });

  it('shows an empty list for an empty chat and outbox', () => {
    assert.deepEqual(chatView([], [], NO_RUNNING, NOW), []);
  });
});

describe('what a turn shows', () => {
  it('gives the text and the server\'s time of a stored turn, and the local text and sentAt of a local one', () => {
    const [stored, own] = chatView([turn('A', { createdAt: '2026-10-22T14:11:09Z' })], [local('x', 'failed')], NO_RUNNING, NOW);
    assert.deepEqual([stored.text, stored.time], ['text A', '2026-10-22T14:11:09Z']);
    assert.deepEqual([own.text, own.time], ['local x', '2026-10-22T14:12:00Z']);
  });

  it('captions a Telegram turn "via Telegram" and a guide message "From the demo guide"', () => {
    const [web, telegram, guide, both] = chatView(
      [turn('W'), turn('T', { channel: 'telegram' }), turn('G', { fromGuide: true }), turn('B', { channel: 'telegram', fromGuide: true })],
      [],
      NO_RUNNING,
      NOW,
    );
    assert.deepEqual([web.caption, telegram.caption, guide.caption, both.caption], ['', 'via Telegram', 'From the demo guide', 'via Telegram']);
    assert.equal(chatView([], [local('g', 'sent', { fromGuide: true })], NO_RUNNING, NOW)[0].caption, 'From the demo guide');
    assert.equal(chatView([], [local('p', 'sent')], NO_RUNNING, NOW)[0].caption, '');
  });
});

describe('the reply of a turn', () => {
  const replyOf = (over, since = NO_RUNNING, now = NOW) => chatView([turn('A', over)], [], since, now)[0].reply;

  it('is Deciding for a queued turn and Working for a running one, which a done turn replaces', () => {
    assert.deepEqual(replyOf({ state: 'queued', replyText: '' }), { kind: 'deciding' });
    assert.deepEqual(replyOf({ state: 'running', replyText: '' }), { kind: 'working' });
    assert.deepEqual(replyOf({ state: 'done' }), { kind: 'text', replyText: 'reply A' });
  });

  it('adds the whole seconds once the page has seen the turn running for 10 s', () => {
    const since = new Map([['c-A', NOW - 9_999]]);
    assert.deepEqual(replyOf({ state: 'running' }, since), { kind: 'working' }, 'at 9.999 s');
    assert.deepEqual(replyOf({ state: 'running' }, new Map([['c-A', NOW - 9_000]])), { kind: 'working' }, 'at 9 s');
    assert.deepEqual(replyOf({ state: 'running' }, new Map([['c-A', NOW - 10_000]])), { kind: 'working', seconds: 10 }, 'at 10 s');
    assert.deepEqual(replyOf({ state: 'running' }, new Map([['c-A', NOW - 12_900]])), { kind: 'working', seconds: 12 }, 'at 12.9 s is 12 whole seconds');
    assert.deepEqual(replyOf({ state: 'running' }, new Map([['other', NOW - 60_000]])), { kind: 'working' }, 'a turn the page has not noted has no seconds');
  });

  it('is a fallback by its catalog key and reason, and the key wins over any reply text', () => {
    assert.deepEqual(replyOf({ catalogKey: 'conversation.turnFallback', fallbackReason: 'timeout', replyText: '' }), {
      kind: 'fallback',
      catalogKey: 'conversation.turnFallback',
      fallbackReason: 'timeout',
    });
    assert.equal(replyOf({ catalogKey: 'conversation.turnFallback', replyText: 'x' }).kind, 'fallback');
  });

  it('is none for a done turn with no reply and for a state the page does not know', () => {
    assert.deepEqual(replyOf({ state: 'done', replyText: '' }), { kind: 'none' });
    assert.deepEqual(replyOf({ state: 'paused' }), { kind: 'none' });
    assert.deepEqual(replyOf({ state: undefined }), { kind: 'none' });
  });

  it('is none while a local message is sending or failed, and Deciding once the server accepted it', () => {
    const replies = chatView([], [local('a', 'sending'), local('b', 'failed'), local('c', 'sent')], NO_RUNNING, NOW).map((view) => view.reply.kind);
    assert.deepEqual(replies, ['none', 'none', 'deciding']);
  });
});

describe('the step of a running turn', () => {
  const stepsOf = (over = {}) => ({ 'A': { turnRef: 'A', decisionRef: 'D1', label: 'Checking the Orders production' }, ...over });
  const replyOf = (steps, since = NO_RUNNING, over = {}) => chatView([turn('A', { state: 'running', replyText: '', ...over })], [], since, NOW, steps)[0].reply;

  it('is the label the store holds for the running turn\'s ref, trimmed', () => {
    assert.deepEqual(replyOf(stepsOf()), { kind: 'working', step: 'Checking the Orders production' });
    assert.deepEqual(replyOf(stepsOf({ A: { turnRef: 'A', label: '  Reading the failed message \n' } })), { kind: 'working', step: 'Reading the failed message' });
  });

  it('keeps the seconds beside the step once the page has seen the turn running for 10 s', () => {
    assert.deepEqual(replyOf(stepsOf(), new Map([['c-A', NOW - 12_900]])), { kind: 'working', seconds: 12, step: 'Checking the Orders production' });
  });

  it('is none for a turn the store holds no step for, another turn\'s step, an empty label and no steps at all', () => {
    assert.deepEqual(replyOf({}), { kind: 'working' });
    assert.deepEqual(replyOf({ B: { turnRef: 'B', label: 'Looking' } }), { kind: 'working' });
    assert.deepEqual(replyOf({ A: { turnRef: 'A', label: '   ' } }), { kind: 'working' });
    assert.deepEqual(replyOf({ A: { turnRef: 'A' } }), { kind: 'working' });
    assert.deepEqual(replyOf(undefined), { kind: 'working' });
    assert.deepEqual(replyOf({}, NO_RUNNING, { ref: undefined }), { kind: 'working' });
  });

  it('is read by the turn\'s ref, not its client id, and a prototype key is no step', () => {
    assert.deepEqual(replyOf({ 'c-A': { turnRef: 'c-A', label: 'By client id' } }), { kind: 'working' });
    assert.deepEqual(replyOf({}, NO_RUNNING, { ref: 'constructor' }), { kind: 'working' });
  });

  it('shows only for a running turn: a queued turn is deciding and a done turn has its reply', () => {
    const steps = stepsOf();
    assert.deepEqual(chatView([turn('A', { state: 'queued', replyText: '' })], [], NO_RUNNING, NOW, steps)[0].reply, { kind: 'deciding' });
    assert.deepEqual(chatView([turn('A')], [], NO_RUNNING, NOW, steps)[0].reply, { kind: 'text', replyText: 'reply A' });
  });
});

describe('indicatorOf', () => {
  it('shows Deciding with the animated ellipsis, spoken with it', () => {
    assert.deepEqual(indicatorOf({ kind: 'deciding' }), { text: 'Deciding', spoken: 'Deciding\u2026', dots: true });
  });

  it('shows Working with the animated ellipsis when there is no step', () => {
    assert.deepEqual(indicatorOf({ kind: 'working' }), { text: 'Working', spoken: 'Working\u2026', dots: true });
  });

  it('shows Working \u00B7 12 s after 10 s, spoken in full, with the dots off', () => {
    assert.deepEqual(indicatorOf({ kind: 'working', seconds: 12 }), { text: 'Working \u00B7 12 s', spoken: 'Working \u00B7 12 seconds', seconds: 12, dots: false });
  });

  it('shows the step\'s label with the animated ellipsis: "{label}\u2026"', () => {
    assert.deepEqual(indicatorOf({ kind: 'working', step: 'Checking the Orders production' }), {
      text: 'Checking the Orders production',
      spoken: 'Checking the Orders production\u2026',
      dots: true,
    });
  });

  it('shows "{label} \u00B7 12 s" after 10 s, spoken "{label} \u00B7 12 seconds"', () => {
    assert.deepEqual(indicatorOf({ kind: 'working', seconds: 12, step: 'Checking the Orders production' }), {
      text: 'Checking the Orders production \u00B7 12 s',
      spoken: 'Checking the Orders production \u00B7 12 seconds',
      seconds: 12,
      dots: false,
    });
  });

  it('puts a label in whole, whatever it holds: no placeholder or replacement pattern in it is read', () => {
    const label = 'Step {n} costs $& and $1 {label}';
    assert.equal(indicatorOf({ kind: 'working', step: label }).text, label);
    assert.equal(indicatorOf({ kind: 'working', step: label }).spoken, `${label}\u2026`);
    assert.equal(indicatorOf({ kind: 'working', seconds: 12, step: label }).text, `${label} \u00B7 12 s`);
    assert.equal(indicatorOf({ kind: 'working', seconds: 12, step: label }).spoken, `${label} \u00B7 12 seconds`);
  });

  it('shows nothing for a reply that is not in progress', () => {
    for (const reply of [{ kind: 'none' }, { kind: 'text', replyText: 'x' }, { kind: 'fallback', catalogKey: 'k', fallbackReason: 'timeout' }]) {
      assert.equal(indicatorOf(reply), undefined, reply.kind);
    }
  });
});

describe('the decision strip of a turn', () => {
  const decision = (over = {}) => ({ ref: 'D1', kind: 'decide', outcome: 'act', reasons: 'one\ntwo', confidence: 0.92, costUSD: 0.0003, ...over });
  const cost = { inputTokens: 1084, outputTokens: 312, costUSD: 0.0008 };
  const fallback = { catalogKey: 'conversation.turnFallback', fallbackReason: 'timeout', replyText: '' };
  const strips = (chat) => chatView(chat, [], NO_RUNNING, NOW).map((view) => [view.strip, view.newest]);

  it('has a strip when its chat.message carries a decision or its reply is a fallback', () => {
    const views = chatView([turn('A'), turn('B', { decision: decision() }), turn('C', fallback), turn('D', { state: 'running', replyText: '', decision: decision() }), turn('E', { state: 'queued', replyText: '' })], [], NO_RUNNING, NOW);
    assert.deepEqual(views.map((view) => view.strip), [false, true, true, true, false]);
  });

  it('marks the last turn that has a strip as the newest, and no other', () => {
    assert.deepEqual(strips([turn('A', { decision: decision() }), turn('B', { decision: decision() }), turn('C')]), [[true, false], [true, true], [false, false]]);
    assert.deepEqual(strips([turn('A', { decision: decision() })]), [[true, true]]);
    assert.deepEqual(strips([turn('A'), turn('B')]), [[false, false], [false, false]]);
    assert.deepEqual(strips([turn('A', fallback), turn('B', { decision: decision() }), turn('C', fallback)]), [[true, false], [true, false], [true, true]]);
  });

  it('keeps a strip that is not on the newest turn off the page\'s own messages', () => {
    const views = chatView([turn('A', { decision: decision() })], [local('x', 'sent')], NO_RUNNING, NOW);
    assert.deepEqual(views.map((view) => [view.strip, view.newest]), [[true, true], [false, false]]);
  });

  it('carries the decision, the turn\'s cost, the check key and the check rows of the chat.message', () => {
    const checks = [{ result: 'passed', entry: 'Orders', checkedAt: '2026-10-22T14:11:00Z' }];
    const [view] = chatView([turn('A', { decision: decision(), turnCost: cost, checkKey: 'checks.allPassed', checks })], [], NO_RUNNING, NOW);
    assert.equal(view.decision.ref, 'D1');
    assert.deepEqual(view.turnCost, cost);
    assert.equal(view.checkKey, 'checks.allPassed');
    assert.deepEqual(view.checks, checks);
  });

  it('leaves them out when the chat.message has none', () => {
    const [view] = chatView([turn('A')], [], NO_RUNNING, NOW);
    for (const field of ['decision', 'turnCost', 'fallbackReason', 'checkKey', 'checks']) {
      assert.equal(view[field], undefined, field);
    }
    const [empty] = chatView([turn('A', { checkKey: '', checks: [] })], [], NO_RUNNING, NOW);
    assert.equal(empty.checkKey, undefined);
    assert.equal(empty.checks, undefined);
  });

  it('keeps the turn\'s cost only with a decision', () => {
    const [view] = chatView([turn('A', { turnCost: cost })], [], NO_RUNNING, NOW);
    assert.equal(view.turnCost, undefined);
  });

  it('is a fallback strip when the reply is a fallback, with the turn\'s own reason', () => {
    const [view] = chatView([turn('A', { ...fallback, fallbackReason: 'rate_limited', decision: decision({ fallback: true, fallbackReason: 'timeout' }) })], [], NO_RUNNING, NOW);
    assert.equal(view.fallbackReason, 'rate_limited');
    const [bare] = chatView([turn('B', fallback)], [], NO_RUNNING, NOW);
    assert.equal(bare.fallbackReason, 'timeout', 'a fallback with no decision');
    assert.equal(bare.decision, undefined);
  });

  it('is a fallback strip when the decision is a fallback, with the decision\'s reason, though the reply is the model\'s', () => {
    const [view] = chatView([turn('A', { decision: decision({ fallback: true, fallbackReason: 'budget' }) })], [], NO_RUNNING, NOW);
    assert.equal(view.fallbackReason, 'budget');
    const [noReason] = chatView([turn('B', { decision: decision({ fallback: true }) })], [], NO_RUNNING, NOW);
    assert.equal(noReason.fallbackReason, '');
  });

  it('is not a fallback strip for a decision that is not a fallback', () => {
    const [view] = chatView([turn('A', { decision: decision({ fallback: false, fallbackReason: 'timeout' }) })], [], NO_RUNNING, NOW);
    assert.equal(view.fallbackReason, undefined);
  });
});

describe('a fresh chat', () => {
  it('is a chat with no entry of any type and no message of this page pending', () => {
    assert.equal(isFreshChat([], []), true);
    assert.equal(isFreshChat([turn('A')], []), false);
    assert.equal(isFreshChat([], [local('x', 'sending')]), false);
    assert.equal(isFreshChat([], [local('x', 'failed')]), false);
  });

  it('is not fresh with an incident or a notice alone, though the page draws neither yet', () => {
    assert.equal(isFreshChat([incident('I1')], []), false);
    assert.equal(isFreshChat([notice('N1')], []), false);
  });
});

describe('newClientId', () => {
  it('is 22 base64url characters, and two calls differ', () => {
    const first = newClientId();
    const second = newClientId();
    assert.match(first, /^[A-Za-z0-9_-]{22}$/);
    assert.match(second, /^[A-Za-z0-9_-]{22}$/);
    assert.notEqual(first, second);
  });

  it('encodes the 16 bytes it is given, 6 bits to a character, without padding', () => {
    assert.equal(newClientId((bytes) => bytes.fill(0)), 'AAAAAAAAAAAAAAAAAAAAAA');
    assert.equal(newClientId((bytes) => bytes.fill(255)), '_____________________w');
    assert.equal(newClientId((bytes) => bytes.map((_byte, i) => i)), 'AAECAwQFBgcICQoLDA0ODw');
  });

  it('draws 16 bytes and no more', () => {
    let size = 0;
    newClientId((bytes) => {
      size = bytes.length;
      return bytes;
    });
    assert.equal(size, 16);
  });
});

describe('the fixed strings', () => {
  it('are the UX\'s wording, written out here', () => {
    assert.deepEqual(
      { ...CHAT_TEXTS },
      {
        composerLabel: 'Message OcuTalon',
        composerPlaceholder: 'Message OcuTalon',
        send: 'Send',
        notSent: 'Not sent',
        retrySending: 'Retry sending',
        deciding: 'Deciding\u2026',
        working: 'Working\u2026',
        workingElapsed: 'Working \u00B7 {n} s',
        workingElapsedSpoken: 'Working \u00B7 {n} seconds',
        stepWorking: '{label}\u2026',
        stepElapsed: '{label} \u00B7 {n} s',
        stepElapsedSpoken: '{label} \u00B7 {n} seconds',
        seconds: '{n} seconds',
        newMessages: 'New messages',
        name: 'OcuTalon',
        viaTelegram: 'via Telegram',
        fromGuide: 'From the demo guide',
        separator: ' \u00B7 ',
        opensInNewTab: '(opens in a new tab)',
        emptyHeadline: 'For everything that arrives, OcuTalon makes one attention decision',
        emptyWatches: 'It watches your productions from inside IRIS, and every decision is a production message you can trace.',
        emptyRisky: 'Anything risky waits for your approval.',
        emptyAsk: 'Ask OcuTalon to watch a production, set a reminder, or say what you need.',
        chipIgnore: 'Ignore',
        chipDigest: 'Digest',
        chipTellNow: 'Tell now',
        chipAct: 'Act',
        meaningIgnore: 'Recorded; nobody notified',
        meaningDigest: 'Saved for later; nobody notified now',
        meaningTellNow: 'Needs you now',
        meaningAct: 'OcuTalon took or requested an action',
      },
    );
  });

  it('write Deciding and Working with the one-character ellipsis U+2026, never three dots', () => {
    for (const text of [CHAT_TEXTS.deciding, CHAT_TEXTS.working]) {
      assert.equal(text.slice(-1), '\u2026');
      assert.ok(!text.includes('...'), text);
    }
    assert.equal(CHAT_TEXTS.deciding.length, 'Deciding'.length + 1);
    assert.equal(CHAT_TEXTS.working.length, 'Working'.length + 1);
  });

  it('say the elapsed time as "Working \u00B7 12 s" and speak it as "Working \u00B7 12 seconds"', () => {
    assert.equal(CHAT_TEXTS.workingElapsed.replace('{n}', '12'), 'Working \u00B7 12 s');
    assert.equal(CHAT_TEXTS.workingElapsedSpoken.replace('{n}', '12'), 'Working \u00B7 12 seconds');
    assert.equal(CHAT_TEXTS.seconds.replace('{n}', '12'), '12 seconds');
  });
});
