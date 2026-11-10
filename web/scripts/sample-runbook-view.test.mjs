// Tests the sample runbook that the Documents page and the demo guide add (src/app/documents/sample-runbook-view.ts; Story 20.3): its shape (ASCII
// only, one closing newline, sections under the passage size, a `.md` name), the section that its suggested question answers, the scenario of the
// CI mock that asks that question, item 6's look-for that quotes it, and the facts it states about the demo, which are read from the demo's own
// classes (src/ocutalon/cls/OcuTalon/Demo/Orders/), so that a rename or a reworded error there turns this red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { SAMPLE_RUNBOOK_TEXTS } = await import(app('documents', 'sample-runbook-view.ts'));
const { MORE_TO_TRY_ITEMS } = await import(app('guide', 'more-to-try-view.ts'));
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');

const ORDERS = ['src', 'ocutalon', 'cls', 'OcuTalon', 'Demo', 'Orders'];
const { text, name, question } = SAMPLE_RUNBOOK_TEXTS;

/** The runbook's sections as Docs.Passages sees them: a `## ` line opens one, and the lines before the first are the introduction. */
const sections = text.split(/^(?=## )/m);
const section = (title) => sections.find((one) => one.startsWith(`## ${title}\n`));

/** The passage size of Docs.Passages (its MAXPASSAGE parameter, read from the class): a passage holds at most this many characters. */
const PASSAGE = Number(/Parameter MAXPASSAGE = (\d+);/.exec(read('src', 'ocutalon', 'cls', 'OcuTalon', 'Docs', 'Passages.cls'))?.[1]);

describe('the shape of the runbook', () => {
  it('is ASCII only and ends with exactly one newline', () => {
    assert.match(text, /^[\x00-\x7f]*$/);
    assert.ok(text.endsWith('.\n') && !text.endsWith('\n\n'));
    assert.match(question, /^[\x00-\x7f]*$/);
  });

  it('is a Markdown file name, and the name that a chip shows without its extension', () => {
    assert.equal(name, 'Sample runbook.md');
    assert.ok(name.endsWith('.md'));
  });

  it('keeps every section under the passage size, so that each is one passage', () => {
    assert.ok(sections.length >= 4, 'an introduction and three sections');
    for (const one of sections) assert.ok(one.length < PASSAGE, `${JSON.stringify(one.slice(0, 40))} is ${one.length} characters`);
  });

  it('has the section that the suggested question is answered from', () => {
    assert.ok(section('When orders fail with a date error'), 'the section that the chip names');
    assert.ok(section('How orders flow') && section('When the Results partner changes its certificate'));
  });
});

describe('the suggested question', () => {
  it('is the one that the CI mock\'s scenario asks of the documents tool, so that the real search runs on it', () => {
    const scenario = JSON.parse(read('ci', 'mock', 'scenarios', 'B', 'sample-runbook.json'));
    assert.equal(scenario.name, 'sample-runbook');
    assert.deepEqual(scenario.match, { marker: 'sample-runbook' });
    assert.equal(scenario.replies[0].toolUse.name, 'documents');
    assert.equal(scenario.replies[0].toolUse.input.query, question);
  });

  it('is quoted in item 6\'s look-for, and in no other item', () => {
    const quoting = MORE_TO_TRY_ITEMS.filter((item) => item.lookFor.includes(`"${question}"`));
    assert.deepEqual(quoting.map((item) => item.id), ['documents']);
  });

  it('names the runbook, as the measured wording does, and asks about a date error', () => {
    assert.ok(question.startsWith('According to the runbook, '));
    assert.ok(question.includes('date error'));
  });
});

describe('the facts of the runbook are the demo\'s own', () => {
  const failing = section('When orders fail with a date error');

  it('quotes the error that the demo\'s order-date transform raises', () => {
    const transform = read(...ORDERS, 'Transform.cls');
    const thrown = /\$\$\$ERROR\(\$\$\$GeneralError, "([^"]*)"/.exec(transform);
    assert.ok(thrown, 'Transform.cls raises the order-date error');
    const sentence = `${thrown[1].split('. ')[0]}.`;
    assert.equal(sentence, 'The order date was not in the expected format.');
    assert.ok(failing.includes(`"${sentence}"`), 'the runbook quotes it');
  });

  it('names the items of the Orders production, and the item that runs the transform', () => {
    const production = read(...ORDERS, 'Production.cls');
    for (const item of ['PartnerOrdersIn', 'OrdersFromPartner', 'OrdersToWarehouse']) {
      assert.match(production, new RegExp(`<Item Name="${item}"`), `${item} is an item of the production`);
      assert.ok(text.includes(item), `the runbook names ${item}`);
    }
    assert.ok(section('How orders flow').includes('PartnerOrdersIn') && failing.includes('OrdersFromPartner'));
  });

  it('gives the date formats of the transform and of the partner\'s other batches', () => {
    assert.match(read(...ORDERS, 'Transform.cls'), /accepts YYYY-MM-DD/);
    assert.match(read(...ORDERS, 'Partner.cls'), /Parameter FORMATS = "YYYY-MM-DD,MM\/DD\/YYYY";/);
    assert.ok(failing.includes('YYYY-MM-DD') && failing.includes('MM/DD/YYYY'));
  });

  it('numbers its orders as the partner does, and plays out Break the feed with the 50 orders that README states', () => {
    assert.match(read(...ORDERS, 'Partner.cls'), /PO-<i as four digits>/);
    assert.ok(section('How orders flow').includes('PO-0001'));
    assert.match(read('README.md'), /makes a simulated partner send 50 orders in a changed date format/);
    assert.ok(failing.includes('Break the feed plays this out with 50 orders.'));
  });

  it('says the Orders production runs in the namespace that the Demo installer creates', () => {
    assert.match(read(...ORDERS, 'Production.cls'), /in namespace OCUORDERS/);
    assert.ok(text.includes('namespace OCUORDERS'));
  });
});
