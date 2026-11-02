// Tests what the chat announces (src/app/chat/chat-announcements.ts): the diff of the entries against the last look, the
// first sentence of a reply or a card, an incident card (new, state change, count-only change), and what stays silent (the first look, the user's own messages, Deciding, Working, the
// seconds, a card updated in place, a reply that had already landed). Story 6.4: the record of an incident card holds its state and
// the text of each request's result band; a known card gives each band text that is new or changed (once), a new card none; the change
// to closed of an incident that the page dismissed itself is recorded and not spoken. The entries come from the real chatView, and the
// format from fakes or from the real reply-text.ts. The module is imported as it is: Node strips its types, which holds only
// while it keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', 'src', 'app', 'chat', 'chat-announcements.ts');
const { chatAnnouncements, firstSentence, landed } = await import(pathToFileURL(source).href);
const { chatView } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'chat-view.ts')).href);
const { announcementOf, bandTexts } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'incidents', 'incident-view.ts')).href);
const { resultView } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'approvals', 'approval-view.ts')).href);
const { renderPageText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'msg', 'catalog.ts')).href);
const { parseReply, plainText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'reply-text.ts')).href);

const NOW = 1_000_000;

/** A format with fake reads: the reply text as it is, a fallback as "catalog <key>: <reason>". */
const FAKE = {
  announceReplied: 'OcuTalon replied:',
  announceTellNow: 'Tell now:',
  replyText: (text) => text,
  fallbackText: (key, reason) => `Catalog ${key}: ${reason}. Second sentence.`,
  // The real texts of an incident card, with a headline that carries the count so that a count change would show.
  incidentText: (previous, incident) => announcementOf(previous, incident, `H${incident.count ?? ''}`),
  // The real result bands: the catalog's texts of the Result mapping.
  bandTexts: (incident) => bandTexts(incident, { result: (request, noun) => resultView(request, noun, renderPageText) }),
  dismissed: () => false,
};

/** The format for a page that has dismissed these incidents itself. */
const dismissing = (...refs) => ({ ...FAKE, dismissed: (ref) => refs.includes(ref) });

/** A request of an incident payload that went through: 50 orders, or `completed` of them. */
const done = (ref, over = {}) => ({ ref, state: 'done', result: { total: 50, resent: 50, completed: 50, failedAgain: 0, skipped: 0, interrupted: 0, reason: '', ...over } });
const ALL = 'All 50 orders went through.';

/** A chat.message entry of the store: a done turn with a reply unless the state or the fields say otherwise. */
const turn = (ref, over = {}) => ({
  type: 'chat.message',
  payload: { ref, clientId: `c-${ref}`, channel: 'web', fromGuide: false, state: 'done', text: `text ${ref}`, replyText: `Reply ${ref}. More.`, createdAt: '2026-10-22T14:11:00Z', ...over },
});
const queued = (ref) => turn(ref, { state: 'queued', replyText: '' });
const running = (ref) => turn(ref, { state: 'running', replyText: '' });
const notice = (ref, over = {}) => ({ type: 'notification', payload: { ref, kind: 'reminder', text: 'Reminder: stretch.', createdAt: '2026-10-22T14:12:00Z', ...over } });
const tellNow = (ref, over = {}) => notice(ref, { kind: 'tellnow', text: 'zz Orders are failing. More.', whyNow: 'Why now: zz first.', ...over });
const incident = (ref, over = {}) => ({ type: 'incident', payload: { ref, state: 'awaiting_approval', count: 50, noticeCount: 50, ...over } });
const local = (clientId, status) => ({ clientId, text: `local ${clientId}`, fromGuide: false, sentAt: '2026-10-22T14:12:00Z', status });

/** The entries the chat shows for the store's chat and the page's outbox. */
const view = (chat, outbox = [], since = new Map()) => chatView(chat, outbox, since, NOW);

/** The first look at the entries, then the next look; returns the next look's texts. */
function next(before, after, format = FAKE) {
  const first = chatAnnouncements(undefined, view(...before), format);
  assert.deepEqual(first.texts, [], 'the first look is silent');
  return chatAnnouncements(first.heard, view(...after), format);
}

describe('the first look', () => {
  it('announces nothing and records every entry with whether it has landed', () => {
    const entries = view([turn('A'), running('B'), tellNow('N1'), notice('N2')], [local('x', 'sending')]);
    const { texts, heard } = chatAnnouncements(undefined, entries, FAKE);
    assert.deepEqual(texts, []);
    assert.deepEqual([...heard], [['c-A', true], ['c-B', false], ['notification:N1', true], ['notification:N2', true], ['x', false]]);
  });

  it('records an empty chat', () => {
    const { texts, heard } = chatAnnouncements(undefined, [], FAKE);
    assert.deepEqual(texts, []);
    assert.equal(heard.size, 0);
  });
});

describe('a reply', () => {
  it('is announced when it lands as text: "OcuTalon replied:" and its first sentence', () => {
    const { texts } = next([[running('A')]], [[turn('A', { replyText: 'zz A1 First sentence here. Second sentence.' })]]);
    assert.deepEqual(texts, ['OcuTalon replied: zz A1 First sentence here.']);
  });

  it('is announced when it lands as a fallback: the catalog sentence the page shows', () => {
    const { texts } = next([[running('A')]], [[turn('A', { replyText: '', catalogKey: 'conversation.turnFallback', fallbackReason: 'timeout' })]]);
    assert.deepEqual(texts, ['OcuTalon replied: Catalog conversation.turnFallback: timeout.']);
  });

  it('is announced when the turn is new and has landed already (a turn from Telegram, or after a reload)', () => {
    const { texts } = next([[turn('A')]], [[turn('A'), turn('B', { replyText: 'Fresh answer. Rest.' })]]);
    assert.deepEqual(texts, ['OcuTalon replied: Fresh answer.']);
  });

  it('is announced when it lands after the turn was queued, then running', () => {
    const first = chatAnnouncements(undefined, view([queued('A')]), FAKE);
    const second = chatAnnouncements(first.heard, view([running('A')]), FAKE);
    assert.deepEqual(second.texts, [], 'Working is silent');
    const third = chatAnnouncements(second.heard, view([turn('A', { replyText: 'Done. Yes.' })]), FAKE);
    assert.deepEqual(third.texts, ['OcuTalon replied: Done.']);
    const fourth = chatAnnouncements(third.heard, view([turn('A', { replyText: 'Done. Yes.' })]), FAKE);
    assert.deepEqual(fourth.texts, [], 'once');
  });

  it('is silent when it had already landed, even if its text changes', () => {
    assert.deepEqual(next([[turn('A')]], [[turn('A')]]).texts, []);
    assert.deepEqual(next([[turn('A')]], [[turn('A', { replyText: 'Another text. Yes.' })]]).texts, []);
  });

  it('is read once: a reply that has been heard is not read again at the next look', () => {
    let reads = 0;
    const counting = { ...FAKE, replyText: (text) => (reads += 1, text), fallbackText: (key, reason) => (reads += 1, `${key} ${reason}.`) };
    const entries = view([turn('A'), turn('B', { replyText: '', catalogKey: 'conversation.turnFallback', fallbackReason: 'timeout' }), running('C')]);
    const first = chatAnnouncements(undefined, entries, counting);
    const second = chatAnnouncements(first.heard, entries, counting);
    assert.deepEqual([first.texts, second.texts], [[], []]);
    assert.equal(reads, 0, 'neither the first look nor a look at replies already heard reads a reply');
    const third = chatAnnouncements(second.heard, view([turn('A'), turn('B', { replyText: '', catalogKey: 'conversation.turnFallback', fallbackReason: 'timeout' }), turn('C', { replyText: 'Done. Yes.' })]), counting);
    assert.deepEqual(third.texts, ['OcuTalon replied: Done.']);
    assert.equal(reads, 1, 'only the reply that landed is read');
  });

  it('is announced in its own words only up to the first sentence, with the real reads of a reply', () => {
    const real = { ...FAKE, replyText: (text) => plainText(parseReply(text)) };
    const body = 'See [the guide](https://example.com/guide) for the fix. Then restart.\n\n- one\n- two';
    assert.deepEqual(next([[running('A')]], [[turn('A', { replyText: body })]], real).texts, ['OcuTalon replied: See the guide for the fix.']);
    assert.deepEqual(next([[running('A')]], [[turn('A', { replyText: '- First item here. Yes\n- two' })]], real).texts, ['OcuTalon replied: First item here.']);
  });
});

describe('a card', () => {
  it('is announced for a new tell now: "Tell now:" and the first sentence of its text, not the Why now line', () => {
    const { texts } = next([[turn('A')]], [[turn('A'), tellNow('N1')]]);
    assert.deepEqual(texts, ['Tell now: zz Orders are failing.']);
  });

  it('is announced with its first sentence even when its text starts with a line break', () => {
    const { texts } = next([[turn('A')]], [[turn('A'), tellNow('N1', { text: '\nzz Orders are failing. More.' })]]);
    assert.deepEqual(texts, ['Tell now: zz Orders are failing.']);
  });

  it('is announced for a new reminder: its text', () => {
    const { texts } = next([[turn('A')]], [[turn('A'), notice('N1', { text: 'Reminder: zz A3 stretch.' })]]);
    assert.deepEqual(texts, ['Reminder: zz A3 stretch.']);
  });

  it('is silent when updated in place', () => {
    const before = [[tellNow('N1'), notice('N2')]];
    const after = [[tellNow('N1', { text: 'zz Changed. Entirely.', whyNow: 'Why now: other.' }), notice('N2', { text: 'Reminder: changed.' })]];
    assert.deepEqual(next(before, after).texts, []);
  });

  it('is silent when the card was there at the first look', () => {
    assert.deepEqual(next([[tellNow('N1')]], [[tellNow('N1')]]).texts, []);
  });
});

describe('an incident card', () => {
  it('is announced once when it is new: "Incident: {headline}. Approval needed." for an incident awaiting approval', () => {
    const { texts } = next([[turn('A')]], [[turn('A'), incident('I1')]]);
    assert.deepEqual(texts, ['Incident: H50. Approval needed.']);
  });

  it('is announced as "No fix proposed." when it is new and a fallback or a no-fix variant, and as its state otherwise', () => {
    const { texts } = next(
      [[]],
      [[incident('F', { state: 'open', fallback: true }), incident('N', { state: 'open', openVariant: 'no_fix' }), incident('R', { state: 'open', openVariant: 'rejected' }), incident('X', { state: 'fixing' })]],
    );
    assert.deepEqual(texts, ['Incident: H50. No fix proposed.', 'Incident: H50. No fix proposed.', 'Incident: H50. Open.', 'Incident: H50. Fixing.']);
  });

  it('announces the new state once when a known card\'s state changes, and nothing for a count-only change or an unchanged update', () => {
    const first = chatAnnouncements(undefined, view([incident('I1')]), FAKE);
    assert.deepEqual(first.texts, []);
    assert.deepEqual(first.heard.get('incident:I1'), { state: 'awaiting_approval', bands: {} }, 'the record keeps the card\'s state');
    const fixing = chatAnnouncements(first.heard, view([incident('I1', { state: 'fixing', count: 52 })]), FAKE);
    assert.deepEqual(fixing.texts, ['Incident: H52. Fixing.']);
    const again = chatAnnouncements(fixing.heard, view([incident('I1', { state: 'fixing', count: 53 })]), FAKE);
    assert.deepEqual(again.texts, [], 'a count-only change');
    const same = chatAnnouncements(again.heard, view([incident('I1', { state: 'fixing', count: 53 })]), FAKE);
    assert.deepEqual(same.texts, [], 'an unchanged update');
    const resolved = chatAnnouncements(same.heard, view([incident('I1', { state: 'resolved', count: 53 })]), FAKE);
    assert.deepEqual(resolved.texts, ['Incident: H53. Resolved.']);
    const closed = chatAnnouncements(resolved.heard, view([incident('I1', { state: 'closed', count: 53 })]), FAKE);
    assert.deepEqual(closed.texts, ['Incident: H53. Closed.']);
  });

  it('is silent at the first look, whatever the incidents say, and records each one\'s state', () => {
    const { texts, heard } = chatAnnouncements(undefined, view([incident('I1'), incident('I2', { state: 'closed' }), incident('I3', { state: undefined })]), FAKE);
    assert.deepEqual(texts, []);
    assert.deepEqual([...heard], [['incident:I1', { state: 'awaiting_approval', bands: {} }], ['incident:I2', { state: 'closed', bands: {} }], ['incident:I3', { state: '', bands: {} }]]);
  });

  it('announces a new ref after a closed one, and leaves the closed card alone', () => {
    const { texts } = next([[incident('I1', { state: 'closed' })]], [[incident('I1', { state: 'closed' }), incident('I2')]]);
    assert.deepEqual(texts, ['Incident: H50. Approval needed.']);
  });

  it('counts as landed when present, and is read in the chat\'s order with the other entries', () => {
    assert.equal(landed(view([incident('I1')])[0]), true);
    const { texts } = next([[turn('A', { state: 'running', replyText: '' })]], [[incident('I1'), turn('A'), notice('N1')]]);
    assert.deepEqual(texts, ['Incident: H50. Approval needed.', 'OcuTalon replied: Reply A.', 'Reminder: stretch.']);
  });

  it('is announced again after it was gone from the chat (the record holds the current entries only)', () => {
    const first = chatAnnouncements(undefined, view([incident('I1')]), FAKE);
    const dropped = chatAnnouncements(first.heard, view([]), FAKE);
    const back = chatAnnouncements(dropped.heard, view([incident('I1')]), FAKE);
    assert.deepEqual(back.texts, ['Incident: H50. Approval needed.']);
  });
});

describe('a result band of an incident card (Story 6.4)', () => {
  const orders = { one: 'order', other: 'orders' };
  const R = (state, requests, over = {}) => incident('I1', { state, itemNoun: orders, requests, ...over });
  const look = (format, ...steps) => {
    let heard;
    const said = [];
    for (const entries of steps) {
      const result = chatAnnouncements(heard, view(entries), format);
      heard = result.heard;
      said.push(result.texts);
    }
    return { said, heard };
  };

  it('is announced once when it first appears on a card already shown, after the state\'s text, and not again', () => {
    const { said, heard } = look(FAKE, [R('fixing', [{ ref: 'A', state: 'executing' }])], [R('resolved', [done('A')])], [R('resolved', [done('A')], { count: 51 })]);
    assert.deepEqual(said, [[], ['Incident: H50. Resolved.', ALL], []]);
    assert.deepEqual(heard.get('incident:I1'), { state: 'resolved', bands: { A: ALL } });
  });

  it('is announced again when its text changes, still resending and then final, each once', () => {
    const resending = (completed) => R('fixing', [{ ref: 'A', state: 'executing', result: { total: 50, completed } }]);
    const { said } = look(FAKE, [R('awaiting_approval', [{ ref: 'A', state: 'pending' }])], [resending(30)], [resending(30)], [resending(35)], [R('resolved', [done('A')])]);
    assert.deepEqual(said, [
      [],
      ['Incident: H50. Fixing.', "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done."],
      [],
      ["Still resending: 35 of 50 orders have gone through so far. I'll tell you when it's done."],
      ['Incident: H50. Resolved.', ALL],
    ]);
  });

  it('is announced for each request by itself, and one request\'s change never repeats another\'s', () => {
    const { said } = look(FAKE, [R('awaiting_approval', [done('A'), { ref: 'B', state: 'pending' }])], [R('resolved', [done('A'), done('B', { total: 50, completed: 48, failedAgain: 2, reason: 'zz' })])]);
    assert.deepEqual(said[1], ['Incident: H50. Resolved.', '48 of 50 orders went through. 2 failed again (zz). I won\'t retry them without a new approval.']);
  });

  it('is not announced at first sight of a card, beyond 6.1\'s rule, nor at the first look', () => {
    const first = chatAnnouncements(undefined, view([R('resolved', [done('A')])]), FAKE);
    assert.deepEqual(first.texts, []);
    const sight = chatAnnouncements(first.heard, view([R('resolved', [done('A')]), incident('I2', { state: 'resolved', itemNoun: orders, requests: [done('B')] })]), FAKE);
    assert.deepEqual(sight.texts, ['Incident: H50. Resolved.'], 'the new card says its state and no band');
  });

  it('announces a closing as the state only when the bands did not change, repeating no band', () => {
    const { said } = look(FAKE, [R('resolved', [done('A')])], [R('closed', [done('A')])]);
    assert.deepEqual(said[1], ['Incident: H50. Closed.']);
  });

  it('does not repeat a closing that the page dismissed itself, and records it, while any other closing is announced', () => {
    const own = look(dismissing('I1'), [R('open', [{ ref: 'A', state: 'rejected' }], { openVariant: 'rejected' })], [R('closed', [{ ref: 'A', state: 'rejected' }])]);
    assert.deepEqual(own.said, [[], []]);
    assert.equal(own.heard.get('incident:I1').state, 'closed');
    const other = look(dismissing('I2'), [R('open', [])], [R('closed', [])]);
    assert.deepEqual(other.said[1], ['Incident: H50. Closed.']);
    const again = look(dismissing('I1'), [R('closed', [])], [R('closed', [])]);
    assert.deepEqual(again.said, [[], []]);
  });

  it('announces a state other than closed of an incident that the page dismissed', () => {
    const { said } = look(dismissing('I1'), [R('open', [])], [R('awaiting_approval', [])]);
    assert.deepEqual(said[1], ['Incident: H50. Awaiting approval.']);
  });
});

describe('what stays silent', () => {
  it('is the user\'s own message in every state, whether sending, sent or failed', () => {
    const { texts } = next([[]], [[], [local('a', 'sending'), local('b', 'sent'), local('c', 'failed')]]);
    assert.deepEqual(texts, []);
  });

  it('is the user\'s message stored from the page, Telegram or the guide, while the reply has not landed', () => {
    const stored = [turn('A', { state: 'queued', replyText: '' }), turn('B', { channel: 'telegram', state: 'running', replyText: '' }), turn('C', { fromGuide: true, state: 'queued', replyText: '' })];
    assert.deepEqual(next([[]], [stored]).texts, []);
  });

  it('is the outbox entry that the stored turn takes over, until its reply lands', () => {
    const first = chatAnnouncements(undefined, view([], [local('c-A', 'sent')]), FAKE);
    const second = chatAnnouncements(first.heard, view([queued('A')]), FAKE);
    assert.deepEqual(second.texts, []);
    const third = chatAnnouncements(second.heard, view([turn('A', { replyText: 'Answer. Ok.' })]), FAKE);
    assert.deepEqual(third.texts, ['OcuTalon replied: Answer.']);
  });

  it('is Working and its seconds, which change every second', () => {
    const since = new Map([['c-A', NOW - 11_000]]);
    const first = chatAnnouncements(undefined, view([running('A')], [], since), FAKE);
    const second = chatAnnouncements(first.heard, chatView([running('A')], [], since, NOW + 5000), FAKE);
    assert.equal(second.texts.length, 0);
    assert.equal(chatView([running('A')], [], since, NOW)[0].reply.seconds, 11, 'the view does carry seconds');
  });
});

describe('a reload', () => {
  it('announces only what is new: a reply that landed meanwhile, a new turn, a new card', () => {
    const before = [[turn('A'), running('B'), tellNow('N1')]];
    const after = [[turn('A'), turn('B', { replyText: 'B is done. Yes.' }), tellNow('N1'), turn('C', { replyText: 'C is new. Yes.' }), notice('N2')]];
    assert.deepEqual(next(before, after).texts, ['OcuTalon replied: B is done.', 'OcuTalon replied: C is new.', 'Reminder: stretch.']);
  });

  it('records the current entries only, so an entry that comes back is new', () => {
    const first = chatAnnouncements(undefined, view([turn('A'), notice('N1')]), FAKE);
    const dropped = chatAnnouncements(first.heard, view([]), FAKE);
    assert.deepEqual([...dropped.heard], []);
    const back = chatAnnouncements(dropped.heard, view([turn('A'), notice('N1')]), FAKE);
    assert.deepEqual(back.texts, ['OcuTalon replied: Reply A.', 'Reminder: stretch.']);
  });
});

describe('the order', () => {
  it('follows the chat\'s order', () => {
    const before = [[turn('A', { state: 'running', replyText: '' })]];
    const after = [[notice('N1', { text: 'Reminder: first.' }), turn('A'), tellNow('N2', { text: 'zz Second. Rest.' })]];
    assert.deepEqual(next(before, after).texts, ['Reminder: first.', 'OcuTalon replied: Reply A.', 'Tell now: zz Second.']);
  });
});

describe('the first sentence', () => {
  it('ends at the first ".", "!", "?" or ellipsis, and keeps the mark', () => {
    assert.equal(firstSentence('One. Two.'), 'One.');
    assert.equal(firstSentence('Stop! Then go.'), 'Stop!');
    assert.equal(firstSentence('Really? Yes.'), 'Really?');
    assert.equal(firstSentence('Wait\u2026 then go.'), 'Wait\u2026');
  });

  it('ends at the end of the text', () => {
    assert.equal(firstSentence('Only one.'), 'Only one.');
    assert.equal(firstSentence('Done!'), 'Done!');
  });

  it('ends at the first line break', () => {
    assert.equal(firstSentence('First line\nSecond line. Third.'), 'First line');
    assert.equal(firstSentence('First line\r\nSecond. Third.'), 'First line');
    assert.equal(firstSentence('Line one. Same line\nLine two.'), 'Line one.');
  });

  it('does not end inside an address, a number or a word', () => {
    assert.equal(firstSentence('See https://a.b/c for more'), 'See https://a.b/c for more');
    assert.equal(firstSentence('Open https://a.b/c. Then stop.'), 'Open https://a.b/c.');
    assert.equal(firstSentence('Costs 3.50 dollars. Ok.'), 'Costs 3.50 dollars.');
  });

  it('ends after "e.g." as the rule says', () => {
    assert.equal(firstSentence('Use e.g. this one. Then more.'), 'Use e.g.');
  });

  it('skips leading white space and blank lines first, so a text that starts with a line break still has a sentence', () => {
    assert.equal(firstSentence('\nFirst. Second.'), 'First.');
    assert.equal(firstSentence('  \r\n \n  Only line'), 'Only line');
    assert.equal(firstSentence('\n\nFirst line\nSecond. Third.'), 'First line');
  });

  it('returns text with no mark whole, trimmed', () => {
    assert.equal(firstSentence('  no mark at all  '), 'no mark at all');
    assert.equal(firstSentence(''), '');
    assert.equal(firstSentence('   \n  '), '');
  });
});

describe('the module', () => {
  it('imports only types, keeps to erasable syntax and is ASCII', () => {
    const text = readFileSync(source, 'utf8');
    const imports = text.match(/^\s*import\s.*$/gm) ?? [];
    assert.ok(imports.length > 0);
    assert.ok(imports.every((line) => /^\s*import type\s/.test(line)), `only type imports: ${imports.join(' | ')}`);
    assert.doesNotMatch(text, /\benum\b|\bnamespace\b/, 'no enum and no namespace');
    assert.doesNotMatch(text, /constructor\s*\([^)]*\b(?:private|public|protected|readonly)\s/, 'no parameter property');
    assert.doesNotMatch(text, /[^\x00-\x7F]/, 'non-ASCII characters are written as escapes');
  });
});
