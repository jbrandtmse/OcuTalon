// Tests the sample runbook that the Documents page and the demo guide add (src/app/documents/sample-runbook-view.ts; Story 20.3): its shape (ASCII
// only, one closing newline, sections under the passage size, a `.md` name), the section that its suggested question answers, the scenario of the
// CI mock that asks that question, item 6's look-for that quotes it, and the facts it states about the demo, which are read from the code of the
// demo's own classes (src/ocutalon/cls/OcuTalon/Demo/Orders/, Demo/PartnerTrigger.cls and Install/Step/Demo.cls), so that a rename, a reworded
// error or a changed count there turns this red.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
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
    assert.match(read(...ORDERS, 'Transform.cls'), /If value\?4N1"-"2N1"-"2N \{/, 'the transform reads only a date written YYYY-MM-DD');
    assert.match(read(...ORDERS, 'Partner.cls'), /Parameter FORMATS = "YYYY-MM-DD,MM\/DD\/YYYY";/);
    assert.ok(failing.includes('YYYY-MM-DD') && failing.includes('MM/DD/YYYY'));
  });

  it('numbers its orders as the partner does, and plays out Break the feed with the 50 orders that it sends and README states', () => {
    assert.match(read(...ORDERS, 'Partner.cls'), /Set order\.OrderNumber = "PO-"_\$Translate\(\$Justify\(i, 4\), " ", "0"\)/, 'the partner numbers its orders PO-0001 and up');
    assert.ok(section('How orders flow').includes('PO-0001'));
    assert.match(read('src', 'ocutalon', 'cls', 'OcuTalon', 'Demo', 'PartnerTrigger.cls'), /Parameter COUNT = 50;/, 'Break the feed sends 50 orders');
    assert.match(read('README.md'), /makes a simulated partner send 50 orders in a changed date format/);
    assert.ok(failing.includes('Break the feed plays this out with 50 orders.'));
  });

  it('says the Orders production runs in the namespace that the Demo installer creates', () => {
    assert.match(read('src', 'ocutalon', 'cls', 'OcuTalon', 'Install', 'Step', 'Demo.cls'), /Parameter NAMESPACE = "OCUORDERS";/, 'the Demo step creates OCUORDERS');
    assert.ok(text.includes('namespace OCUORDERS'));
  });
});

describe('the sample takes the page\'s own add path (no route, request or fetch of its own)', () => {
  const page = read('web', 'src', 'app', 'documents', 'documents-page.ts');
  const addSample = /protected readonly addSample = async \(\): Promise<void> => \{[\s\S]*?\n  \};/.exec(page)?.[0] ?? '';

  it('builds a File from the bundled text and hands it to addFile, the one method that posts a document', () => {
    assert.ok(addSample.includes('new File([SAMPLE_RUNBOOK_TEXTS.text], SAMPLE_RUNBOOK_TEXTS.name'), 'a File of the bundled name and text');
    assert.ok(addSample.includes('this.addFile(file)'), 'handed to addFile');
    assert.ok(!/addDocument|HttpClient|globalThis\.fetch|\/v1\/documents/.test(addSample), 'addSample makes no request of its own');
    assert.equal(page.match(/\.addDocument\(/g)?.length, 1, 'the page has one call of api.addDocument, inside addFile');
    assert.match(/private async addFile\(file: File\)[\s\S]*?\n  \}\n/.exec(page)?.[0] ?? '', /this\.api\.addDocument\(file\.name, content\)/);
  });

  it('is the only caller of addDocument in the web app, and the guide\'s service and view post nothing', () => {
    const walk = (dir) =>
      readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
        entry.isDirectory() ? walk(join(dir, entry.name)) : entry.name.endsWith('.ts') ? [join(dir, entry.name)] : [],
      );
    const base = join(root, 'web', 'src', 'app');
    const callers = walk(base).map((file) => [file.slice(base.length + 1), readFileSync(file, 'utf8')]);
    assert.deepEqual(callers.filter(([file, source]) => /\.addDocument\(/.test(source) && !file.endsWith('.spec.ts')).map(([file]) => file).sort(), ['documents/documents-page.ts']);
    for (const file of ['sample-runbook.ts', 'sample-runbook-view.ts']) {
      const source = read('web', 'src', 'app', 'documents', file);
      assert.ok(!/addDocument|HttpClient|globalThis\.fetch|\.post\(/.test(source), `${file} posts nothing`);
    }
  });
});
