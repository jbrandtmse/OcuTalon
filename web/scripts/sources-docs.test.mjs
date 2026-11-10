// Tests that the written counts and texts of Story 20.2 follow the More to try registry (src/app/guide/more-to-try-view.ts): the README's
// "more things to try" count, its "New since 1.0.0" line about the chips, EXPERIENCE.md's item count and its items 6 and 8, and the
// registry's own header comments, and that EXPERIENCE.md numbers the items in the registry's order. The registry is the source of the
// count; the words are written out here so that an item another story adds fails these tests until every place that counts says the new
// number.
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
const REGISTRY = readFileSync(join(here, '..', 'src', 'app', 'guide', 'more-to-try-view.ts'), 'utf8');

const WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
const count = WORDS[MORE_TO_TRY_ITEMS.length];

/** The Planner-ruled README bullet (Story 20.2, public text 14), word for word. */
const BULLET =
  '- **Where an answer came from.** An answer from your documents ends with a chip for each source that names the document and section: press it to read the passage, or open the whole document on the Documents page. An answer that recalls a memory carries a From memory chip that shows what was remembered and when. Try it: More to try, *See where an answer came from*.';

/** The text between a heading line and the next heading of the same or a higher level. */
const section = (text, heading) => {
  const start = text.indexOf(`\n${heading}\n`);
  assert.ok(start >= 0, `${heading} is in the README`);
  const rest = text.slice(start + heading.length + 2);
  const end = rest.search(/\n#{1,3} /);
  return end < 0 ? rest : rest.slice(0, end);
};

describe('the registry names a count the documents can say', () => {
  it('has a count that has a word here', () => {
    assert.ok(count !== undefined, `${MORE_TO_TRY_ITEMS.length} items need a word in WORDS`);
  });
});

describe('every written count follows the registry', () => {
  it('README says how many more things to try there are', () => {
    assert.match(README, new RegExp(`its More to try panel has ${count} more things to try`));
  });

  it('EXPERIENCE.md says how many items there are', () => {
    assert.match(EXPERIENCE, new RegExp(`There are ${count} items, in this order`));
  });

  it('the registry\'s comments say how many items there are', () => {
    assert.match(REGISTRY, new RegExp(`the registry of\\s+\\*\\s+its ${count} items`));
    // the comment above the array carries no number (Story 23.6): it says that the registry's length is the count the documents give
    assert.match(REGISTRY, /\/\*\* The items, in the order the panel shows them: the registry's length is the count that the README and EXPERIENCE give\. \*\//);
  });
});

describe('README, "New since 1.0.0"', () => {
  const bullets = section(README, '### New since 1.0.0')
    .split('\n')
    .filter((line) => line.startsWith('- '));

  it('holds the ruled line about the chips, word for word, once', () => {
    assert.equal(bullets.filter((line) => line === BULLET).length, 1);
  });

  it('names the item it points to as the registry does', () => {
    const sources = MORE_TO_TRY_ITEMS.find((item) => item.id === 'sources');
    assert.ok(sources, 'the registry has the sources item');
    assert.ok(BULLET.includes(`*${sources.label}*`));
  });
});

describe('EXPERIENCE.md, More to try', () => {
  const entry = (id) => {
    const item = MORE_TO_TRY_ITEMS.find((one) => one.id === id);
    assert.ok(item, `the registry has ${id}`);
    return item;
  };
  const line = (n) => {
    const found = EXPERIENCE.split('\n').find((one) => one.startsWith(`    - Item ${n}. Label `));
    assert.ok(found, `EXPERIENCE.md has an Item ${n} entry`);
    return found;
  };

  it('lists the registry\'s items in the order of its entries, and no item past them', () => {
    // The entries sit in the order of the panel, whatever their numbers: 23.6's first item comes before Item 1 and 23.2's Item 9 after Item 3 ("the numbers of the other items stay as they are").
    const labels = EXPERIENCE.split('\n')
      .filter((one) => /^    - (Item \d+|First item)\b/.test(one))
      .map((one) => /Label "([^"]+)"/.exec(one)?.[1]);
    assert.deepEqual(labels, MORE_TO_TRY_ITEMS.map((item) => item.label), 'EXPERIENCE.md lists the registry\'s items, in the registry\'s order, and no other');
  });

  for (const [n, id] of [
    [6, 'documents'],
    [8, 'sources'],
  ]) {
    it(`Item ${n} is the ${id} entry of the registry: label, look-for and control`, () => {
      const item = entry(id);
      const text = line(n);
      assert.ok(text.includes(`Label "${item.label}". Look for: "${item.lookFor}"`), `Item ${n} label and look-for`);
      assert.ok(text.includes(`Control: "${item.button}".`), `Item ${n} control`);
    });
  }

  it('names the items whose controls are links to the Documents page', () => {
    assert.ok(EXPERIENCE.includes("Items 6 and 8's controls are links to the Documents page."));
  });

  it('marks the change to item 6 and the new item 8 with the story and the ruling', () => {
    assert.match(line(6), /\[AMENDED 2026-11-09, Story 20\.2, Planner ruling [^\]]*public text 9\)/);
    assert.match(line(8), /\[ADDED 2026-11-09, Story 20\.2, Planner ruling [^\]]*public text 10 to 12\)/);
  });
});
