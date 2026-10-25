// Tests what the chat announces (src/app/chat/chat-announcements.ts): the diff of the entries against the last look, the
// first sentence of a reply or a card, and what stays silent (the first look, the user's own messages, Deciding, Working, the
// seconds, a card updated in place, a reply that had already landed). The entries come from the real chatView, and the
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
const { chatAnnouncements, firstSentence } = await import(pathToFileURL(source).href);
const { chatView } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'chat-view.ts')).href);
const { parseReply, plainText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'reply-text.ts')).href);

const NOW = 1_000_000;

/** A format with fake reads: the reply text as it is, a fallback as "catalog <key>: <reason>". */
const FAKE = {
  announceReplied: 'OcuTalon replied:',
  announceTellNow: 'Tell now:',
  replyText: (text) => text,
  fallbackText: (key, reason) => `Catalog ${key}: ${reason}. Second sentence.`,
};

/** A chat.message entry of the store: a done turn with a reply unless the state or the fields say otherwise. */
const turn = (ref, over = {}) => ({
  type: 'chat.message',
  payload: { ref, clientId: `c-${ref}`, channel: 'web', fromGuide: false, state: 'done', text: `text ${ref}`, replyText: `Reply ${ref}. More.`, createdAt: '2026-10-22T14:11:00Z', ...over },
});
const queued = (ref) => turn(ref, { state: 'queued', replyText: '' });
const running = (ref) => turn(ref, { state: 'running', replyText: '' });
const notice = (ref, over = {}) => ({ type: 'notification', payload: { ref, kind: 'reminder', text: 'Reminder: stretch.', createdAt: '2026-10-22T14:12:00Z', ...over } });
const tellNow = (ref, over = {}) => notice(ref, { kind: 'tellnow', text: 'zz Orders are failing. More.', whyNow: 'Why now: zz first.', ...over });
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
