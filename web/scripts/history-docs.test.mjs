// Tests that the written texts of Story 25.2 follow the More to try registry (src/app/guide/more-to-try-view.ts) and the code: the README's History bullet in
// "New since 1.0.0" (the Planner-ruled text, word for word, once, after the Usage bullet), EXPERIENCE.md's history item line (label, look-for and control as the
// registry has them, the marker, right after the usage item under the "Usage and history" heading) and its sentence that the item's control is a link to the History
// page, and the three rows of the architecture spine (AD-33: the ownership API, the header entry and page, the REST surface), the REST row naming exactly the routes
// that OcuTalon.Web.History's URL map serves. The counts follow the registry and are pinned by sources-docs.test.mjs; usage-docs.test.mjs pins the Usage item.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const { MORE_TO_TRY_ITEMS } = await import(pathToFileURL(join(here, '..', 'src', 'app', 'guide', 'more-to-try-view.ts')).href);

const README = readFileSync(join(root, 'README.md'), 'utf8');
const EXPERIENCE = readFileSync(join(root, '_bmad-output', 'planning-artifacts', 'ux-designs', 'ux-OcuTalon-2026-10-16', 'EXPERIENCE.md'), 'utf8');
const SPINE = readFileSync(join(root, '_bmad-output', 'planning-artifacts', 'architecture', 'architecture-OcuTalon-2026-10-16', 'ARCHITECTURE-SPINE.md'), 'utf8');
const HISTORY_CLASS = readFileSync(join(root, 'src', 'ocutalon', 'cls', 'OcuTalon', 'Web', 'History.cls'), 'utf8');

/** The Planner-ruled README bullet (Story 25.2, public text 31), word for word. */
const BULLET =
  '- **A History page.** Open History in the header to look back at the decisions OcuTalon made on your messages, filtered by outcome, channel, date and fallback, each with its reasons and a link to its trace, and at your incidents with their state and, once closed, their summary. On the online demo you see only your own session\'s decisions and incidents. Try it: More to try, *Look back at past decisions*.';

const history = MORE_TO_TRY_ITEMS.find((item) => item.id === 'history');
const STORY = /\[ADDED \d{4}-\d{2}-\d{2}, Story 25\.2[^\]]*\]/;

/** The lines of the README's "New since 1.0.0" section that are bullets, in order. */
const bullets = (() => {
  const start = README.indexOf('\n### New since 1.0.0\n');
  assert.ok(start >= 0, 'New since 1.0.0 is in the README');
  const rest = README.slice(start + '\n### New since 1.0.0\n'.length);
  const end = rest.search(/\n#{1,3} /);
  return (end < 0 ? rest : rest.slice(0, end)).split('\n').filter((line) => line.startsWith('- '));
})();

/** The lines of a spine section: from its heading to the next heading of the same or a higher level. */
function sectionOf(heading) {
  const at = SPINE.indexOf(`\n${heading}\n`);
  assert.ok(at >= 0, `the spine has "${heading}"`);
  const rest = SPINE.slice(at + heading.length + 2);
  const end = rest.search(/\n#{1,3} /);
  return (end < 0 ? rest : rest.slice(0, end)).split('\n');
}

describe('README, the History bullet of "New since 1.0.0"', () => {
  it('is the ruled line, word for word, once', () => {
    assert.equal(bullets.filter((line) => line === BULLET).length, 1);
  });

  it('comes after the Usage bullet', () => {
    const usage = bullets.findIndex((line) => line.startsWith('- **A Usage page.**'));
    assert.ok(usage >= 0, 'the Usage bullet is there');
    assert.ok(bullets.indexOf(BULLET) > usage, 'the History bullet is after it');
  });

  it('names the item it points to as the registry does, and claims no more than the page does', () => {
    assert.ok(history, 'the registry has the history item');
    const shown = bullets.find((line) => line.startsWith('- **A History page.**')) ?? '';
    assert.ok(shown.includes(`Try it: More to try, *${history.label}*.`), 'the README bullet names the registry\'s label');
    assert.ok(shown.includes('On the online demo you see only your own session\'s decisions and incidents.'), 'it says the online demo shows only the visitor\'s own rows');
  });
});

describe('EXPERIENCE.md, the More to try history item', () => {
  const lines = EXPERIENCE.split('\n');
  const at = lines.findIndex((one) => /^    - Item \d+\. Label /.test(one) && one.includes('Label "Look back at past decisions".'));
  const line = at >= 0 ? lines[at] : undefined;
  const number = Number((line ?? '').match(/^    - Item (\d+)\./)?.[1] ?? NaN);
  const numbers = lines.map((one) => one.match(/^    - Item (\d+)\. /)?.[1]).filter(Boolean).map(Number);

  it('is the history item, the registry\'s last entry and the last numbered item: label, look-for and control', () => {
    assert.ok(line, 'EXPERIENCE.md has a numbered entry with the history label');
    assert.equal(MORE_TO_TRY_ITEMS.at(-1)?.id, 'history', 'the registry\'s last entry is the history item');
    assert.equal(number, Math.max(...numbers), 'the history item is the last numbered item');
    assert.ok(line.includes(`Label "${history.label}". Look for: "${history.lookFor}"`), 'its label and look-for');
    assert.ok(line.includes(`Control: "${history.button}".`), 'its control');
  });

  it('follows the usage item inside the "Usage and history" heading, with the story marker', () => {
    assert.equal(history.group, 'Usage and history', 'the registry\'s history group');
    const usage = lines.findIndex((one) => /^    - Item \d+\. Label "See tokens and cost"\./.test(one));
    assert.equal(at, usage + 1, 'the history line comes right after the usage item');
    assert.match(lines[usage - 1] ?? '', /^    - Heading "Usage and history"\./, 'the usage item sits under its heading');
    assert.match(line ?? '', STORY);
  });

  it('says that the history item\'s control is a link to the History page, with the marker', () => {
    const text = `Item ${number}'s control is a link to the History page.`;
    const sentence = lines.find((one) => one.includes(text));
    assert.ok(sentence, `the sentence "${text}" is in EXPERIENCE.md`);
    assert.match(sentence.slice(sentence.indexOf(text)), STORY, 'with the story marker after it');
  });
});

describe('ARCHITECTURE-SPINE.md, the rows of Story 25.2 (AD-33)', () => {
  const ownership = sectionOf('### Ownership tables');
  const rest = sectionOf('### REST surface (release 1)');
  const rowOf = (lines, needle) => lines.filter((one) => one.startsWith('|') && one.includes(needle));

  it('has the ownership API row, naming both methods and the four Rows kinds', () => {
    const rows = rowOf(ownership, 'OcuTalon.Data.Ownership.HistoryDecisions(');
    assert.equal(rows.length, 1, 'exactly one row');
    for (const word of ['HistoryIncidents(', '`historyDecisions`', '`historyDecisionTotal`', '`historyIncidents`', '`historyIncidentTotal`', '| B | Story 25.2 |']) {
      assert.ok(rows[0].includes(word), `the row names ${word}`);
    }
    assert.match(rows[0], STORY);
  });

  it('has the header entry and page row, between Documents and Usage, reading only the two routes', () => {
    const rows = rowOf(ownership, 'The header navigation\'s History entry');
    assert.equal(rows.length, 1, 'exactly one row');
    for (const word of ['between Documents and Usage', 'web/src/app/history/', '#/history', 'GET /api/v1/history/decisions', '/incidents', '| B | Story 25.2 |']) {
      assert.ok(rows[0].includes(word), `the row names ${word}`);
    }
    assert.match(rows[0], STORY);
  });

  it('has the REST row, naming exactly the routes that Web.History serves', () => {
    const rows = rowOf(rest, '`GET /api/v1/history/decisions?');
    assert.equal(rows.length, 1, 'exactly one row');
    const served = [...HISTORY_CLASS.matchAll(/<Route Url="([^"]+)" Method="([^"]+)"/g)].map((one) => `${one[2]} ${one[1]}`).sort();
    assert.deepEqual(served, ['GET /decisions', 'GET /incidents'], 'Web.History serves exactly these two routes');
    for (const word of ['GET /api/v1/history/incidents?page=', 'OcuTalon.Web.History', '404 `not_found`', '500 `server_error`', 'OcuTalon user role']) {
      assert.ok(rows[0].includes(word), `the row says ${word}`);
    }
    assert.match(rows[0], STORY);
  });
});
