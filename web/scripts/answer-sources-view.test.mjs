// Tests the view model of the sources under an answer (src/app/chat/answer-sources-view.ts, Story 20.2; FR-41, FR-42, U-280, DW-721) and the
// source of the component that draws it (src/app/chat/answer-sources.ts): the ruled strings word for word, the chips that the server's citations
// and memories make (grouping, order, the bounds, the accessible names), the rule that a chip never comes from a reply's text, and the
// component's contract in its source (native buttons, aria-haspopup, plain-text passages with a six-line clamp, the popover service).
// The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const chat = (name) => join(here, '..', 'src', 'app', 'chat', name);
const { ANSWER_SOURCES_TEXTS, MAX_CHIPS, NAME_CUT, citationChips, citationLabel, citationName, memoryChips, memoryExcerpt, memoryName, savedLine } = await import(
  pathToFileURL(chat('answer-sources-view.ts')).href
);
const viewSource = readFileSync(chat('answer-sources-view.ts'), 'utf8');
const componentSource = readFileSync(chat('answer-sources.ts'), 'utf8');
const template = /template: `([^`]*)`/.exec(componentSource)[1];

const cite = (documentRef, section, passage, over = {}) => ({ documentRef, document: 'Results runbook', section, passage, chunkIndex: 0, ...over });
const memory = (text, over = {}) => ({ memoryRef: 'M1', text, savedAt: '2026-10-22T14:11:00Z', ...over });

describe('the strings', () => {
  it('are the ruled texts, word for word', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(ANSWER_SOURCES_TEXTS)), {
      citationLabel: '{document} \u00A7 {section}',
      citationName: '{document}, section {section}',
      group: 'Sources',
      openDocument: 'Open document',
      fromMemory: 'From memory',
      memoryName: 'From memory: {memory}',
      saved: 'Saved {when}',
    });
  });

  it('state provenance and never reliance (U-280): no "used", "relied on" or "based on"', () => {
    for (const text of Object.values(ANSWER_SOURCES_TEXTS)) {
      assert.doesNotMatch(text, /\bused\b|relied on|based on/i, text);
    }
  });

  it('write only ASCII and the section sign, as an escape in the source', () => {
    for (const text of Object.values(ANSWER_SOURCES_TEXTS)) {
      assert.deepEqual([...text].filter((char) => char.charCodeAt(0) > 127 && char !== '\u00A7'), [], text);
    }
    assert.ok(/^[\x00-\x7f]*$/.test(viewSource), 'the view module is written in ASCII, with escapes');
  });
});

describe('a citation chip', () => {
  it('reads "{document} \u00A7 {section}" and is named "{document}, section {section}", with no section sign in the name', () => {
    const [chip] = citationChips([cite('D1', 'Rotating the certificate', 'Rotate it.')]);
    assert.equal(chip.label, 'Results runbook \u00A7 Rotating the certificate');
    assert.equal(chip.name, 'Results runbook, section Rotating the certificate');
    assert.ok(!chip.name.includes('\u00A7'), 'the accessible name holds no section sign');
    assert.equal(citationLabel('Results runbook', 'Rotating the certificate'), chip.label);
    assert.equal(citationName('Results runbook', 'Rotating the certificate'), chip.name);
  });

  it('is the document alone, in its label and its name, when the passage sits under no heading', () => {
    const [chip] = citationChips([cite('D1', '', 'Intro.')]);
    assert.equal(chip.label, 'Results runbook');
    assert.equal(chip.name, 'Results runbook');
    assert.equal(chip.section, '');
  });

  it('keeps a "$" or a "{section}" in a name as it is', () => {
    const [chip] = citationChips([cite('D1', 'Costs $& {document}', 'x', { document: 'A {section} $1' })]);
    assert.equal(chip.label, 'A {section} $1 \u00A7 Costs $& {document}');
    assert.equal(chip.name, 'A {section} $1, section Costs $& {document}');
  });

  it('is one chip for one document and section, with every passage of the group in the order it came', () => {
    const chips = citationChips([cite('D1', 'A', 'first', { chunkIndex: 4 }), cite('D1', 'B', 'other'), cite('D1', 'A', 'second', { chunkIndex: 5 })]);
    assert.deepEqual(chips.map((chip) => [chip.label, chip.passages]), [
      ['Results runbook \u00A7 A', ['first', 'second']],
      ['Results runbook \u00A7 B', ['other']],
    ]);
  });

  it('is a chip of its own for the same section of another document, and orders the chips by first appearance', () => {
    const chips = citationChips([cite('D2', 'A', 'x', { document: 'Other file' }), cite('D1', 'A', 'y'), cite('D2', 'A', 'z', { document: 'Other file' })]);
    assert.deepEqual(chips.map((chip) => [chip.documentRef, chip.passages]), [['D2', ['x', 'z']], ['D1', ['y']]]);
    assert.equal(new Set(chips.map((chip) => chip.key)).size, chips.length, 'unique keys');
  });

  it('is at most 5, and a passage of a chip that is shown still joins it', () => {
    const many = Array.from({ length: 7 }, (_, i) => cite('D1', `Section ${i}`, `p${i}`));
    assert.equal(MAX_CHIPS, 5);
    assert.deepEqual(citationChips(many).map((chip) => chip.section), ['Section 0', 'Section 1', 'Section 2', 'Section 3', 'Section 4']);
    assert.deepEqual(citationChips([...many, cite('D1', 'Section 0', 'late')])[0].passages, ['p0', 'late']);
  });

  it('is none for a citation with no document ref or no document name, and for no citations', () => {
    assert.deepEqual(citationChips([cite('', 'A', 'x'), cite('D1', 'A', 'x', { document: '' }), {}]), []);
    assert.deepEqual(citationChips(undefined), []);
    assert.deepEqual(citationChips([]), []);
  });

  it('carries a passage as the text it is: markup, Markdown and line breaks stay characters', () => {
    const raw = '<b>bold</b> <script>window.__x=1</script> **md** # Heading\nsecond line';
    const [chip] = citationChips([cite('D1', 'A', raw)]);
    assert.deepEqual(chip.passages, [raw]);
  });
});

describe('a memory chip', () => {
  it('says "From memory" and is named "From memory: {text}"', () => {
    const [chip] = memoryChips([memory("Lee is the Results partner's contact.")]);
    assert.equal(chip.label, 'From memory');
    assert.equal(chip.name, "From memory: Lee is the Results partner's contact.");
    assert.equal(chip.text, "Lee is the Results partner's contact.");
    assert.equal(chip.savedAt, '2026-10-22T14:11:00Z');
  });

  it('cuts the text of the name to 80 characters with the ellipsis, and only when it is longer', () => {
    assert.equal(NAME_CUT, 80);
    const exactly = 'a'.repeat(80);
    assert.equal(memoryExcerpt(exactly), exactly);
    assert.equal(memoryExcerpt(`${exactly}b`), `${exactly}\u2026`);
    assert.equal(memoryName(`${exactly}b`), `From memory: ${exactly}\u2026`);
    assert.equal(memoryChips([memory(`${exactly}b`)])[0].text, `${exactly}b`, 'the popover keeps the whole text');
  });

  it('cuts whole characters, not half of a surrogate pair, and reads white space as single spaces', () => {
    const pairs = '\u{1F600}'.repeat(81);
    assert.equal(memoryExcerpt(pairs), `${'\u{1F600}'.repeat(80)}\u2026`);
    assert.equal(memoryExcerpt('  one\n\ntwo\tthree  '), 'one two three');
  });

  it('is one chip for each memory, at most 5, in order, and none for a memory with no text', () => {
    const seven = Array.from({ length: 7 }, (_, i) => memory(`m${i}`, { memoryRef: `M${i}` }));
    assert.deepEqual(memoryChips(seven).map((chip) => chip.text), ['m0', 'm1', 'm2', 'm3', 'm4']);
    assert.deepEqual(memoryChips([memory(''), {}, memory('kept')]).map((chip) => chip.text), ['kept']);
    assert.deepEqual(memoryChips(undefined), []);
  });

  it('writes the saved line from the time as the page wrote it, and none without a time', () => {
    assert.equal(savedLine('Monday at 14:13'), 'Saved Monday at 14:13');
    assert.equal(savedLine(''), '');
  });
});

describe('a chip never comes from the reply text (DW-721, U-280)', () => {
  it('shows no chip for a reply that says the none-line when the server sent no citations', () => {
    assert.deepEqual(citationChips(undefined), []);
    assert.deepEqual(memoryChips(undefined), []);
  });

  it('has no function of the view that reads a reply text, and the none-line is nowhere in the view or the component', () => {
    for (const source of [viewSource, componentSource]) {
      assert.ok(!source.includes('None of your documents'), 'the none-line');
      assert.doesNotMatch(source, /replyText|parseReply/, 'a reply text');
    }
    assert.ok(!/^export function \w+\([^)]*(reply|text)\b[^)]*\)/im.test(viewSource.replace(/memoryExcerpt|memoryName/g, '')), 'no exported function takes a reply');
  });
});

describe('the component', () => {
  it('makes each chip a native button with aria-haspopup="dialog", named by the chip\'s accessible name', () => {
    assert.equal((template.match(/<button/g) ?? []).length, 2, 'a citation chip and a memory chip');
    assert.equal((template.match(/aria-haspopup="dialog"/g) ?? []).length, 2);
    assert.equal((template.match(/\[attr\.aria-label\]="chip\.name"/g) ?? []).length, 2);
    assert.equal((template.match(/type="button"/g) ?? []).length, 2);
    assert.match(componentSource, /<div class="sources" role="group" \[attr\.aria-label\]="texts\.group"/);
  });

  it('shows the visible label, with the file-text icon on a citation chip only', () => {
    assert.equal((componentSource.match(/<app-icon name="file-text"/g) ?? []).length, 1);
    assert.match(componentSource, /<app-icon name="file-text" \[size\]="12" \/><span>\{\{ chip\.label \}\}<\/span>/);
    assert.match(componentSource, /data-source="memory"[\s\S]*?<span>\{\{ chip\.label \}\}<\/span>/);
  });

  it('opens popovers through the shared service, named by their heading, and links to the Documents page with the document ref', () => {
    assert.match(componentSource, /this\.popovers\.show\(\{ trigger, content: this\.panel\(\), viewContainerRef: this\.container, labelledBy: this\.headingId \}\)/);
    assert.match(componentSource, /routerLink="\/documents"\s+\[queryParams\]="\{ doc: chip\.documentRef \}"/);
    assert.match(componentSource, /\{\{ texts\.openDocument \}\}/);
    assert.equal((componentSource.match(/<h2 class="heading" \[id\]="headingId">/g) ?? []).length, 2, 'both popovers are named by their heading');
  });

  it('binds every passage, memory and label by interpolation: no innerHTML, no [innerHTML], no sanitizer bypass', () => {
    assert.doesNotMatch(componentSource, /innerHTML|bypassSecurityTrust|outerHTML|DomSanitizer|\[outerHTML\]/);
    assert.match(componentSource, /<p class="passage" data-part="passage">\{\{ passage \}\}<\/p>/);
    assert.match(componentSource, /<div class="memory" tabindex="0" data-part="memory">\{\{ chip\.text \}\}<\/div>/);
  });

  it('shows a passage in at most 6 lines with a line clamp, not a fixed height, and keeps its line breaks', () => {
    const rule = /\.passage \{([^}]*)\}/.exec(componentSource);
    assert.ok(rule, 'a .passage rule');
    assert.match(rule[1], /-webkit-line-clamp: 6;/);
    assert.match(rule[1], /line-clamp: 6;/);
    assert.match(rule[1], /overflow: hidden;/);
    assert.doesNotMatch(rule[1], /\bheight\s*:/, 'no fixed height');
    assert.match(componentSource, /\.passage,\s*\.memory,\s*\.saved \{[^}]*white-space: pre-wrap;/);
  });

  it('styles the chip from the citation-chip tokens, not from colour alone: the border and the icon or the label carry it', () => {
    for (const token of ['background', 'foreground', 'border', 'radius', 'typography-font-size', 'typography-font-weight', 'typography-line-height']) {
      assert.match(componentSource, new RegExp(`var\\(--citation-chip-${token}\\)`), token);
    }
    assert.match(componentSource, /min-height: 24px;/, 'a target of at least 24px');
  });

  it('closes the popover when the component goes, and toggles it on a second press of the same chip', () => {
    assert.match(componentSource, /onDestroy\(\(\) => this\.popover\?\.close\(\)\)/);
    assert.match(componentSource, /if \(this\.popover\?\.isOpen && this\.openKey\(\) === key\) \{\s*this\.popover\.close\(\);\s*return;\s*\}/);
  });
});
