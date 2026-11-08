// Tests the Documents page's view model (src/app/documents/documents-view.ts; Story 34.2): the fixed strings, the reason texts and the unknown
// code, the size format, the file picker's accept list, and the rows: the server's list overlaid by the live payloads by ref, a removed payload
// dropping its row, the page's own pending and refused rows first, a removed document hidden, and the order. The module is imported as it is: Node
// strips its types, which holds only while it keeps to erasable syntax and imports nothing.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { ACCEPT, DOCUMENTS_TEXTS, REASON_TEXTS, formatSize, reasonText, refusedText, rows } = await import(
  pathToFileURL(join(here, '..', 'src', 'app', 'documents', 'documents-view.ts')).href
);

const doc = (ref, over = {}) => ({ ref, name: `${ref}.md`, addedAt: '2030-01-01T10:00:00Z', size: 100, state: 'indexing', reason: '', removed: false, ...over });

describe('the strings', () => {
  it('has the texts of the UX and of the lead\'s rulings, word for word', () => {
    assert.equal(DOCUMENTS_TEXTS.title, 'Documents \u00B7 OcuTalon');
    assert.equal(DOCUMENTS_TEXTS.heading, 'Documents');
    assert.equal(DOCUMENTS_TEXTS.add, 'Add documents');
    assert.equal(DOCUMENTS_TEXTS.empty, 'No documents yet. Add a runbook to get cited answers.');
    assert.equal(DOCUMENTS_TEXTS.indexing, 'Indexing\u2026');
    assert.equal(DOCUMENTS_TEXTS.ready, 'Ready');
    assert.equal(DOCUMENTS_TEXTS.refused, "Couldn't read it: {reason}");
    assert.equal(DOCUMENTS_TEXTS.question, "Remove '{name}'? Answers will stop citing it.");
    assert.equal(DOCUMENTS_TEXTS.removeFailed, "Couldn't remove it. Nothing was changed.");
    assert.equal(DOCUMENTS_TEXTS.removeName, 'Remove {name}');
    assert.equal(ACCEPT, '.md,.markdown,.txt,.pdf,.docx');
  });

  it('has the ruled reason texts, both of the size ruling (U-284, U-285) among them', () => {
    assert.deepEqual(REASON_TEXTS, {
      wrong_type: "it isn't a Markdown, plain-text, PDF or Word (.docx) file.",
      too_large: 'that file is {size}; the limit is 10 MB.',
      empty: 'the file is empty.',
      unreadable: 'OcuTalon found no text in it.',
      not_built: "this part of OcuTalon isn't built yet.",
      failed: 'something went wrong inside OcuTalon.',
      contents_too_large: 'its text is too long to read.',
      encrypted: "it's protected with a password.",
      damaged: "it's damaged or incomplete.",
      no_text: 'it has no text to read, for example a scanned PDF without a text layer.',
      legacy_doc: "it's an old Word file (.doc); save it as .docx and try again.",
      timed_out: 'reading it took too long.',
    });
  });

  it('writes only ASCII, the ellipsis and the middle dot (as escapes in the source)', () => {
    for (const text of [...Object.values(DOCUMENTS_TEXTS), ...Object.values(REASON_TEXTS)]) {
      assert.match(text.replace(/[\u2026\u00B7]/g, ''), /^[\x20-\x7e]*$/, text);
    }
  });
});

describe('the reason of a refused row', () => {
  it('reads each known code and any other as failed', () => {
    for (const code of Object.keys(REASON_TEXTS)) {
      assert.equal(refusedText(code, 5), `Couldn't read it: ${REASON_TEXTS[code].replace('{size}', formatSize(5))}`, code);
    }
    for (const code of ['zz', '', undefined, 'constructor', '__proto__', 'toString']) {
      assert.equal(reasonText(code, 5), REASON_TEXTS.failed, String(code));
    }
  });

  it('says the size of a too large file', () => {
    assert.equal(refusedText('too_large', 14 * 1048576), "Couldn't read it: that file is 14 MB; the limit is 10 MB.");
    assert.equal(refusedText('too_large', 10485761), "Couldn't read it: that file is 10.1 MB; the limit is 10 MB.");
  });
});

describe('the size', () => {
  it('is whole KB under 1 MB, rounded up', () => {
    assert.equal(formatSize(0), '0 KB');
    assert.equal(formatSize(1), '1 KB');
    assert.equal(formatSize(1024), '1 KB');
    assert.equal(formatSize(1025), '2 KB');
    assert.equal(formatSize(1048575), '1024 KB');
  });

  it('is MB with one decimal from 1 MB, rounded up, and without ".0"', () => {
    assert.equal(formatSize(1048576), '1 MB');
    assert.equal(formatSize(1048577), '1.1 MB');
    assert.equal(formatSize(10485760), '10 MB');
    assert.equal(formatSize(10485761), '10.1 MB');
    assert.equal(formatSize(11 * 1048576), '11 MB');
  });

  it('reads no number as 0 KB', () => {
    for (const bad of [NaN, -5, Infinity, undefined]) {
      assert.equal(formatSize(bad), '0 KB', String(bad));
    }
  });
});

describe('the rows', () => {
  it('lists the server\'s documents newest first, with their statuses', () => {
    const list = rows(
      [doc('a', { addedAt: '2030-01-01T10:00:00Z' }), doc('b', { addedAt: '2030-01-03T10:00:00Z', state: 'ready' }), doc('c', { addedAt: '2030-01-02T10:00:00Z', state: 'failed', reason: 'not_built' })],
      {},
      [],
    );
    assert.deepEqual(list.map((row) => row.ref), ['b', 'c', 'a']);
    assert.deepEqual(list.map((row) => row.status), ['Ready', "Couldn't read it: this part of OcuTalon isn't built yet.", 'Indexing\u2026']);
    assert.deepEqual(list.map((row) => row.state), ['ready', 'refused', 'indexing']);
    assert.ok(list.every((row) => row.removable && !row.local));
  });

  it('overlays the live payloads by ref: a payload changes a row, adds one, and a removed one takes the row away', () => {
    const server = [doc('a'), doc('b', { addedAt: '2030-01-02T10:00:00Z' })];
    const live = { a: doc('a', { state: 'ready' }), c: doc('c', { addedAt: '2030-01-03T10:00:00Z' }), b: { ref: 'b', removed: true } };
    const list = rows(server, live, []);
    assert.deepEqual(list.map((row) => [row.ref, row.status]), [['c', 'Indexing\u2026'], ['a', 'Ready']]);
  });

  it('puts the page\'s own pending and refused rows first, newest first, without Remove', () => {
    const local = [
      { id: 2, kind: 'refused', name: 'photo.png', size: 5, at: '2030-01-05T10:00:00Z', reason: 'wrong_type' },
      { id: 1, kind: 'pending', name: 'plan.md', size: 9, at: '2030-01-04T10:00:00Z' },
    ];
    const list = rows([doc('a', { addedAt: '2031-01-01T10:00:00Z' })], {}, local);
    assert.deepEqual(list.map((row) => row.name), ['photo.png', 'plan.md', 'a.md']);
    assert.deepEqual(list.map((row) => row.status), ["Couldn't read it: it isn't a Markdown, plain-text, PDF or Word (.docx) file.", 'Indexing\u2026', 'Indexing\u2026']);
    assert.deepEqual(list.map((row) => row.removable), [false, false, true]);
    assert.deepEqual(list.map((row) => row.local), [true, true, false]);
  });

  it('reads a refused row with no reason, or one it does not know, as failed', () => {
    const list = rows([], {}, [{ id: 1, kind: 'refused', name: 'x.md', size: 1, at: '2030-01-01T10:00:00Z', reason: '' }, { id: 2, kind: 'refused', name: 'y.md', size: 1, at: '2030-01-01T10:00:00Z', reason: 'zz' }]);
    assert.deepEqual(list.map((row) => row.status), ["Couldn't read it: something went wrong inside OcuTalon.", "Couldn't read it: something went wrong inside OcuTalon."]);
  });

  it('replaces a pending add that has a ref by the server\'s or the live row of that ref, and keeps it until then', () => {
    const pending = { id: 1, kind: 'pending', name: 'plan.md', size: 9, at: '2030-01-04T10:00:00Z', ref: 'r1' };
    assert.deepEqual(rows([], {}, [pending]).map((row) => row.key), ['local:1']);
    assert.deepEqual(rows([doc('r1')], {}, [pending]).map((row) => row.key), ['doc:r1']);
    assert.deepEqual(rows([], { r1: doc('r1', { state: 'ready' }) }, [pending]).map((row) => [row.key, row.status]), [['doc:r1', 'Ready']]);
  });

  it('hides a document the user removed, whatever the server or the live payloads still say, until nothing says it', () => {
    const removed = { id: 3, kind: 'removed', name: '', size: 0, at: '', ref: 'a' };
    assert.deepEqual(rows([doc('a'), doc('b')], { a: doc('a', { state: 'ready' }) }, [removed]).map((row) => row.ref), ['b']);
    assert.deepEqual(rows([], {}, [removed]), [], 'a removed entry is no row itself');
  });

  it('drops a pending add for good once its document is removed, by the user or by a live payload', () => {
    const pending = { id: 1, kind: 'pending', name: 'plan.md', size: 9, at: '2030-01-04T10:00:00Z', ref: 'r1' };
    const removed = { id: 2, kind: 'removed', name: '', size: 0, at: '', ref: 'r1' };
    assert.deepEqual(rows([], {}, [removed, pending]), [], 'the user removed it: no Indexing row comes back');
    assert.deepEqual(rows([], { r1: { ref: 'r1', removed: true } }, [pending]), [], 'a live payload removed it');
  });

  it('ignores a field of a payload that it does not know (the Live row of the Matrix)', () => {
    const known = rows([], { a: doc('a', { state: 'ready' }) }, []);
    const extra = rows([], { a: doc('a', { state: 'ready', zzUnknown: 'x', nested: { y: 1 } }) }, []);
    assert.deepEqual(extra, known);
    assert.deepEqual(Object.keys(extra[0]).sort(), ['addedAt', 'key', 'local', 'name', 'ref', 'removable', 'size', 'state', 'status']);
  });

  it('keeps the given order for rows of the same time', () => {
    const same = '2030-01-01T10:00:00Z';
    const list = rows([doc('a', { addedAt: same }), doc('b', { addedAt: same })], {}, []);
    assert.deepEqual(list.map((row) => row.ref), ['a', 'b']);
  });

  it('shows a document with no state as indexing and gives every row a unique key', () => {
    const list = rows([{ ref: 'a', name: 'a.md' }, { ref: 'b', name: 'b.md', state: 'zz' }], {}, [{ id: 1, kind: 'pending', name: 'c.md', size: 1, at: '2030-01-01T10:00:00Z' }]);
    assert.deepEqual(list.map((row) => row.state), ['indexing', 'indexing', 'indexing']);
    assert.equal(new Set(list.map((row) => row.key)).size, 3);
  });
});
