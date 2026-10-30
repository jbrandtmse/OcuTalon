// Tests the simulated mailbox's view model (src/app/mailbox/mailbox-view.ts, Story 4.6): the fixed strings are the UX's exact wording,
// the list exists only in demo mode and is the snapshot's mailbox merged with the store's mailbox events, newest first; an email's
// decision is joined by its itemId (the store's decide decision first, then the entry's own); the sender shows as its display name; the
// form's field errors, the opened list kept per browser and the three announcement texts follow their rules. The module is imported as
// it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { MAILBOX_TEXTS, OPENED_KEY, OPENED_MAX, SAMPLES, arrivedText, chipName, decidedText, decisionOf, emailLimitText, fieldErrors, isBlank, mailOf, openedRefs, senderName, withOpened } = await import(
  pathToFileURL(join(here, '..', 'src', 'app', 'mailbox', 'mailbox-view.ts')).href
);

const { readText } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'shared', 'stored-flag.ts')).href);
const { pageTime } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'page-time.ts')).href);

const mail = (ref, over = {}) => ({ ref, direction: 'in', itemId: `item-${ref}`, sender: `from ${ref}`, subject: `subject ${ref}`, text: `text ${ref}`, unread: true, createdAt: '2030-01-01T10:00:00Z', ...over });
const snapshot = (over = {}) => ({ demoMode: true, mailbox: [], ...over });
const decision = (itemId, over = {}) => ({ ref: `d-${itemId}`, kind: 'decide', itemId, outcome: 'digest', ...over });

describe('the fixed strings', () => {
  it("are the UX's exact wording, with straight quotes and the single ellipsis", () => {
    assert.equal(MAILBOX_TEXTS.caption, 'Send one and see what OcuTalon decides.');
    assert.equal(MAILBOX_TEXTS.simulate, 'Simulate an incoming email');
    assert.equal(MAILBOX_TEXTS.empty, 'No emails yet. Simulate an incoming email, or send a sample.');
    assert.equal(MAILBOX_TEXTS.unread, 'Unread');
    assert.equal(MAILBOX_TEXTS.deciding, 'Deciding\u2026');
    assert.equal(MAILBOX_TEXTS.fromPrefill, 'Results Partner IT <it@results-partner.example>');
    assert.deepEqual([MAILBOX_TEXTS.labelFrom, MAILBOX_TEXTS.labelSubject, MAILBOX_TEXTS.labelBody, MAILBOX_TEXTS.send, MAILBOX_TEXTS.back], ['From', 'Subject', 'Body', 'Send', 'Back']);
    assert.deepEqual([MAILBOX_TEXTS.errSubject, MAILBOX_TEXTS.errBody], ['Enter a subject.', 'Enter a body.']);
    assert.equal(MAILBOX_TEXTS.emailLimit, "You've simulated 20 emails this hour. You can send more at {time}.");
  });

  it('give the email limit\'s reason with the time sending reopens as a page time (Story 16.9, EXPERIENCE.md)', () => {
    const retryAt = '2030-01-01T10:20:00Z';
    assert.equal(emailLimitText(pageTime(retryAt, 'en-GB', 'UTC')), "You've simulated 20 emails this hour. You can send more at 10:20.");
    assert.equal(emailLimitText(pageTime(retryAt, 'en-GB', 'Europe/Berlin')), "You've simulated 20 emails this hour. You can send more at 11:20.", 'in the browser\'s zone, with no zone name');
    assert.equal(emailLimitText(pageTime(retryAt, 'en-US', 'UTC')), "You've simulated 20 emails this hour. You can send more at 10:20 AM.", 'and in its hour format');
    assert.equal(emailLimitText('$&'), "You've simulated 20 emails this hour. You can send more at $&.", 'a time is inserted as text');
    assert.doesNotMatch(emailLimitText(''), /\{/, 'the slot is always filled');
  });

  it('name the three samples in order, with the server\'s names', () => {
    assert.deepEqual(SAMPLES, [
      { name: 'newsletter', label: 'Sample: newsletter' },
      { name: 'partner-notice', label: 'Sample: partner notice' },
      { name: 'suspicious-request', label: 'Sample: suspicious request' },
    ]);
  });
});

describe('mailOf', () => {
  it('is undefined before the snapshot loads and outside demo mode, whatever else the snapshot carries', () => {
    assert.equal(mailOf(undefined, { mailboxes: {} }), undefined);
    assert.equal(mailOf(snapshot({ demoMode: false, mailbox: [mail('a')] }), { mailboxes: { b: mail('b') } }), undefined);
    assert.equal(mailOf({ mailbox: [mail('a')] }, undefined), undefined);
  });

  it('is empty in demo mode with no email', () => {
    assert.deepEqual(mailOf(snapshot(), { mailboxes: {} }), []);
    assert.deepEqual(mailOf(snapshot({ mailbox: undefined }), undefined), []);
  });

  it("is the snapshot's mailbox, oldest first in the snapshot and so newest first in the list", () => {
    const list = mailOf(snapshot({ mailbox: [mail('a'), mail('b'), mail('c')] }), { mailboxes: {} });
    assert.deepEqual(list.map((one) => one.ref), ['c', 'b', 'a']);
  });

  it("adds the store's emails that the snapshot does not hold as the newest, the last to arrive first", () => {
    const list = mailOf(snapshot({ mailbox: [mail('a'), mail('b')] }), { mailboxes: { z: mail('z'), y: mail('y') } });
    assert.deepEqual(list.map((one) => one.ref), ['y', 'z', 'b', 'a']);
  });

  it("takes the store's payload for a ref that both hold, in the snapshot's place, and keeps the snapshot entry's decision", () => {
    const held = decision('item-b');
    const list = mailOf(snapshot({ mailbox: [mail('a'), mail('b', { subject: 'old', decision: held }), mail('c', { decision: decision('item-c') })] }), {
      mailboxes: { b: mail('b', { subject: 'new' }), c: mail('c', { subject: 'newer' }), d: mail('d') },
    });
    assert.deepEqual(list.map((one) => `${one.ref}:${one.subject}`), ['d:subject d', 'c:newer', 'b:new', 'a:subject a']);
    assert.equal(list[2].decision, held, 'the entry keeps its decision');
    assert.equal(list[3].decision, undefined);
  });

  it('does not change the snapshot or the store', () => {
    const entry = mail('b', { decision: decision('item-b') });
    const fresh = mail('b', { subject: 'new' });
    mailOf(snapshot({ mailbox: [entry] }), { mailboxes: { b: fresh } });
    assert.equal(fresh.decision, undefined);
    assert.equal(entry.subject, 'subject b');
  });
});

describe('decisionOf', () => {
  it("is the store's decide decision with the email's itemId", () => {
    const decisions = [decision('other'), decision('item-a', { outcome: 'ignore' })];
    assert.equal(decisionOf(mail('a'), decisions).outcome, 'ignore');
  });

  it('ignores a decision of another kind: a turn decision is no decision of the email', () => {
    assert.equal(decisionOf(mail('a'), [decision('item-a', { kind: 'turn' })]), undefined);
  });

  it("falls back to the entry's own decision when the store holds none", () => {
    const own = decision('item-a', { outcome: 'act' });
    assert.equal(decisionOf(mail('a', { decision: own }), []), own);
    assert.equal(decisionOf(mail('a', { decision: own }), undefined), own);
    assert.equal(decisionOf(mail('a'), [decision('other')]), undefined);
  });

  it("prefers the store's decision to the entry's", () => {
    const live = decision('item-a', { outcome: 'tellnow' });
    assert.equal(decisionOf(mail('a', { decision: decision('item-a', { outcome: 'ignore' }) }), [live]), live);
  });

  it('is none for a sent email and for an email with no itemId', () => {
    assert.equal(decisionOf(mail('a', { direction: 'out' }), [decision('item-a')]), undefined);
    assert.equal(decisionOf(mail('a', { direction: 'out', decision: decision('item-a') }), []), undefined);
    assert.equal(decisionOf(mail('a', { itemId: '' }), [decision('')]), undefined);
    assert.equal(decisionOf(mail('a', { itemId: undefined }), [decision(undefined)]), undefined);
  });
});

describe('senderName', () => {
  it('is the display name of "Name <address>"', () => {
    assert.equal(senderName('Results Partner IT <it@results-partner.example>'), 'Results Partner IT');
    assert.equal(senderName('  Dana  <dana@example.com> '), 'Dana');
    assert.equal(senderName('"Dana Smith" <dana@example.com>'), 'Dana Smith');
  });

  it('is the whole value when there is no display name or no address part', () => {
    assert.equal(senderName('dana@example.com'), 'dana@example.com');
    assert.equal(senderName('<dana@example.com>'), '<dana@example.com>');
    assert.equal(senderName('OcuTalon'), 'OcuTalon');
    assert.equal(senderName(''), '');
    assert.equal(senderName(undefined), '');
  });

  it('keeps markup as text: it is a string, never parsed', () => {
    assert.equal(senderName('<img src=x onerror="window.zzMail=1"><b>b</b>'), '<img src=x onerror="window.zzMail=1"><b>b</b>');
  });
});

describe('fieldErrors', () => {
  it('has no error for a subject and a body with text', () => {
    assert.deepEqual(fieldErrors('s', 'b'), {});
  });

  it('names the blank fields with the UX texts', () => {
    assert.deepEqual(fieldErrors('', 'b'), { subject: 'Enter a subject.' });
    assert.deepEqual(fieldErrors('s', ''), { body: 'Enter a body.' });
    assert.deepEqual(fieldErrors('', ''), { subject: 'Enter a subject.', body: 'Enter a body.' });
  });

  it('counts white space and control characters as blank', () => {
    assert.equal(isBlank(' \t\r\n\u0000\u001f\u007f'), true);
    assert.equal(isBlank(' a '), false);
    assert.deepEqual(fieldErrors('  \t', '\n\n'), { subject: 'Enter a subject.', body: 'Enter a body.' });
  });

  it('counts the C1 controls as blank, as the server does ($ZStrip "C" strips U+0080 to U+009F)', () => {
    assert.equal(isBlank('\u0080\u0085\u009f'), true);
    assert.equal(isBlank('\u00a1'), false);
    assert.deepEqual(fieldErrors('\u0085', 'b'), { subject: 'Enter a subject.' });
  });
});

describe('the announcement texts', () => {
  it("name the chip after its label, with ', send sample email'", () => {
    assert.equal(chipName('Sample: partner notice'), 'Sample: partner notice, send sample email');
    assert.equal(chipName(SAMPLES[0].label), 'Sample: newsletter, send sample email');
  });

  it("say an email decided as the UX's example does", () => {
    assert.equal(decidedText('Certificate change on Friday', 'Digest'), "Email 'Certificate change on Friday': Digest");
  });

  it('say an arrived email is still deciding, with the single ellipsis', () => {
    assert.equal(arrivedText('Certificate change on Friday'), "Email 'Certificate change on Friday': Deciding\u2026");
  });

  it('insert the subject as it is, even when it holds a placeholder or a replacement pattern', () => {
    assert.equal(decidedText('$& {outcome} $1', 'Act'), "Email '$& {outcome} $1': Act");
    assert.equal(arrivedText('{subject}'), "Email '{subject}': Deciding\u2026");
  });
});

describe('the opened list', () => {
  it('is kept under its key', () => {
    assert.equal(OPENED_KEY, 'ocutalon.mailbox.opened');
  });

  it('parses space-separated refs in order, dropping anything that is no ref', () => {
    assert.deepEqual(openedRefs('a b-c d_e'), ['a', 'b-c', 'd_e']);
    assert.deepEqual(openedRefs(''), []);
    assert.deepEqual(openedRefs('a  <b> "c" d'), ['a', 'd']);
    assert.deepEqual(openedRefs('{"x":1}'), []);
    assert.deepEqual(openedRefs('x'.repeat(65)), []);
  });

  it('adds a ref as the newest, once', () => {
    assert.equal(withOpened('', 'a'), 'a');
    assert.equal(withOpened('a b', 'c'), 'a b c');
    assert.equal(withOpened('a b c', 'a'), 'b c a');
  });

  it('keeps at most OPENED_MAX refs, the newest', () => {
    let text = '';
    for (let i = 0; i < OPENED_MAX + 5; i += 1) text = withOpened(text, `r${i}`);
    const refs = openedRefs(text);
    assert.equal(refs.length, OPENED_MAX);
    assert.equal(refs[0], 'r5');
    assert.equal(refs.at(-1), `r${OPENED_MAX + 4}`);
  });

  it('starts again from garbage', () => {
    assert.equal(withOpened('<script> "x"', 'a'), 'a');
  });
});

describe('readText', () => {
  it('answers the stored text, and empty for a missing key', () => {
    assert.equal(readText(() => ({ getItem: (key) => (key === 'k' ? 'a b' : null) }), 'k'), 'a b');
    assert.equal(readText(() => ({ getItem: () => null }), 'k'), '');
  });

  it('answers empty when the storage throws, on opening it or on reading', () => {
    assert.equal(readText(() => { throw new Error('blocked'); }, 'k'), '');
    assert.equal(readText(() => ({ getItem: () => { throw new Error('denied'); } }), 'k'), '');
  });
});
