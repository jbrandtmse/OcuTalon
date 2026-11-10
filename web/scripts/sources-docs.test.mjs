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
    assert.match(REGISTRY, new RegExp(`/\\*\\* The ${count} items, in the order the panel shows them\\. \\*/`));
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

  it('ends the documents bullet with the ruled sentence about the sample runbook (Story 20.3), without a bullet of its own', () => {
    const documents = MORE_TO_TRY_ITEMS.find((item) => item.id === 'documents');
    assert.ok(documents, 'the registry has the documents item');
    const bullet = bullets.filter((line) => line.startsWith('- **Answers from your own documents.**'));
    assert.equal(bullet.length, 1);
    assert.ok(bullet[0].endsWith(`Try it: More to try, *${documents.label}*, which adds a sample runbook if you have no file to hand.`));
    assert.equal(bullets.filter((line) => /sample runbook/i.test(line)).length, 1, 'no bullet of its own');
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
    MORE_TO_TRY_ITEMS.forEach((item, at) => {
      assert.ok(line(at + 1).includes(`Label "${item.label}".`), `Item ${at + 1} is the registry's ${item.id} entry`);
    });
    const past = `    - Item ${MORE_TO_TRY_ITEMS.length + 1}. Label `;
    assert.ok(!EXPERIENCE.split('\n').some((one) => one.startsWith(past)), 'EXPERIENCE.md has no item the registry lacks');
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

  it('says that, with no documents, items 6 and 8 are the sample button that the Documents page presses (Story 20.3)', () => {
    const control = 'While the visitor has no documents, each is instead an "Add the sample runbook" button, which opens the Documents page and presses that page\'s Add the sample runbook.';
    assert.ok(EXPERIENCE.includes(`Items 6 and 8's controls are links to the Documents page. ${control}`), 'the controls sentence');
    assert.ok(
      EXPERIENCE.includes('item 4 turns the Demo view switch off and leaves focus on it; items 6 and 8, while the visitor has no documents, open the Documents page and press its Add the sample runbook, with focus on it;'),
      'the hand-off rule',
    );
    assert.ok(
      EXPERIENCE.includes(
        '- **Sample:** an **Add the sample runbook** button beside Add documents adds a short runbook about the demo\'s Orders feed, which ships with the page, through the same upload. It shows only while the list holds no "Sample runbook.md".',
      ),
      'the Documents step',
    );
    for (const text of [control, 'items 6 and 8, while the visitor has no documents,']) {
      assert.ok(EXPERIENCE.split('\n').some((one) => one.includes(text) && /\[(?:AMENDED|ADDED) 2026-11-09, Story 20\.3, Planner ruling [^\]]*\]/.test(one)), `${text} carries its marker`);
    }
  });

  it('marks the change to item 6 and the new item 8 with the story and the ruling', () => {
    assert.match(line(6), /\[AMENDED 2026-11-09, Story 20\.2, Planner ruling [^\]]*public text 9\)/);
    assert.match(line(8), /\[ADDED 2026-11-09, Story 20\.2, Planner ruling [^\]]*public text 10 to 12\)/);
    assert.match(line(6), /\[AMENDED 2026-11-09, Story 20\.3, Planner ruling [^\]]*public text 5\)\. It read: "/);
  });
});
