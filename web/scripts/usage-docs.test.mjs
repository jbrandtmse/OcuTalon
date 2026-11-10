// Tests that the written texts of Story 37.2 follow the More to try registry (src/app/guide/more-to-try-view.ts): the README's Usage bullet in "New since 1.0.0"
// (the Planner-ruled text, word for word, once, after the sources bullet), and EXPERIENCE.md's item 9 line (label, look-for and control as the registry has
// them, the marker) and its sentence that item 9's control is a link to the Usage page. The counts ("nine") are pinned by sources-docs.test.mjs. The README
// bullet is not pinned as the very last one, so that a story that merges later and appends its own line does not fail this test.
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

/** The Planner-ruled README bullet (Story 37.2, public text 12), word for word. */
const BULLET =
  "- **A Usage page.** Open Usage in the header to see your tokens and cost by day, agent, channel or model, counted per turn and per decision, with each day's largest model request (an estimate) against the 100,000-token limit. On the online demo you see only your own session's use. Try it: More to try, *See tokens and cost*.";

const usage = MORE_TO_TRY_ITEMS.find((item) => item.id === 'usage');

/** The lines of the README's "New since 1.0.0" section that are bullets, in order. */
const bullets = (() => {
  const start = README.indexOf('\n### New since 1.0.0\n');
  assert.ok(start >= 0, 'New since 1.0.0 is in the README');
  const rest = README.slice(start + '\n### New since 1.0.0\n'.length);
  const end = rest.search(/\n#{1,3} /);
  return (end < 0 ? rest : rest.slice(0, end)).split('\n').filter((line) => line.startsWith('- '));
})();

describe('README, the Usage bullet of "New since 1.0.0"', () => {
  it('is the ruled line, word for word, once', () => {
    assert.equal(bullets.filter((line) => line === BULLET).length, 1);
  });

  it('comes after the sources bullet', () => {
    const sources = bullets.findIndex((line) => line.startsWith('- **Where an answer came from.**'));
    const at = bullets.indexOf(BULLET);
    assert.ok(sources >= 0, 'the sources bullet is there');
    assert.ok(at > sources, 'the Usage bullet is after it');
  });

  it('names the item it points to as the registry does, and claims the use per turn and per decision, never per step', () => {
    assert.ok(usage, 'the registry has the usage item');
    const shown = bullets.find((line) => line.startsWith('- **A Usage page.**')) ?? '';
    assert.ok(shown.includes(`Try it: More to try, *${usage.label}*.`), 'the README bullet names the registry\'s label');
    assert.ok(shown.includes('per turn and per decision'), 'the README bullet counts per turn and per decision');
    assert.ok(!/per step/i.test(shown), 'the README bullet never says per step');
  });
});

describe('EXPERIENCE.md, More to try item 9', () => {
  const line = EXPERIENCE.split('\n').find((one) => one.startsWith('    - Item 9. Label '));

  it('is the registry\'s ninth entry, the usage item: label, look-for and control', () => {
    assert.ok(line, 'EXPERIENCE.md has an Item 9 entry');
    assert.equal(MORE_TO_TRY_ITEMS[8]?.id, 'usage', 'the registry\'s ninth entry is the usage item');
    assert.ok(line.includes(`Label "${usage.label}". Look for: "${usage.lookFor}"`), 'Item 9 label and look-for');
    assert.ok(line.includes(`Control: "${usage.button}".`), 'Item 9 control');
  });

  it('carries the story marker', () => {
    assert.match(line ?? '', /\[ADDED 2026-11-10, Story 37\.2, Contest Planner ruling [^\]]*\]/);
  });

  it('says that item 9\'s control is a link to the Usage page, with the marker', () => {
    const sentence = EXPERIENCE.split('\n').find((one) => one.includes("Item 9's control is a link to the Usage page."));
    assert.ok(sentence, 'the sentence is in EXPERIENCE.md');
    assert.match(sentence, /Item 9's control is a link to the Usage page\. \[ADDED 2026-11-10, Story 37\.2, Contest Planner ruling [^\]]*\]/);
  });
});
