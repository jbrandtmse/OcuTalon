// Tests gotoSettled (e2e/support/navigate.ts, Story 11.9; DW-415): a navigation that fails with net::ERR_NETWORK_CHANGED is made once more and
// logs `NAV retry <url>`; a second failure, and every other error, is thrown unchanged with no retry. The rows run on a fake page, so that the
// error is hermetic (route.abort has no such code). The source pin reads the five shared navigation sites of the browser units and holds that
// each goes through gotoSettled. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { afterEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, '..');
const { gotoSettled } = await import(pathToFileURL(join(web, 'e2e', 'support', 'navigate.ts')).href);

const URL_ = 'http://stack.invalid/ocutalon/';

/** A fake page whose goto answers each queued outcome in turn: an Error is thrown, anything else is returned. */
function fakePage(outcomes) {
  const calls = [];
  return {
    calls,
    async goto(url, options) {
      calls.push({ url, options });
      const outcome = outcomes[Math.min(calls.length, outcomes.length) - 1];
      if (outcome instanceof Error) throw outcome;
      return outcome;
    },
  };
}

const changed = () => new Error(`page.goto: net::ERR_NETWORK_CHANGED at ${URL_}`);

const realLog = console.log;
let lines = [];
const capture = () => {
  lines = [];
  console.log = (...args) => lines.push(args.join(' '));
};
afterEach(() => {
  console.log = realLog;
});

describe('gotoSettled', () => {
  it('answers the first goto when it succeeds, with one call and no line', async () => {
    capture();
    const page = fakePage([{ status: 200 }]);
    assert.deepEqual(await gotoSettled(page, URL_, { waitUntil: 'load' }), { status: 200 });
    assert.equal(page.calls.length, 1);
    assert.deepEqual(lines, []);
  });

  it('retries once when the network changed: the second answer and one NAV retry line, with the same url and options', async () => {
    capture();
    const page = fakePage([changed(), { status: 200, second: true }]);
    assert.deepEqual(await gotoSettled(page, URL_, { waitUntil: 'domcontentloaded' }), { status: 200, second: true });
    assert.equal(page.calls.length, 2);
    assert.deepEqual(page.calls, [
      { url: URL_, options: { waitUntil: 'domcontentloaded' } },
      { url: URL_, options: { waitUntil: 'domcontentloaded' } },
    ]);
    assert.deepEqual(lines, [`NAV retry ${URL_}`]);
  });

  it('throws the second error when the network changed twice, after 2 calls', async () => {
    capture();
    const second = new Error(`page.goto: net::ERR_NETWORK_CHANGED at ${URL_} (second)`);
    const page = fakePage([changed(), second]);
    await assert.rejects(gotoSettled(page, URL_), (error) => error === second);
    assert.equal(page.calls.length, 2);
  });

  for (const message of ['page.goto: net::ERR_CONNECTION_REFUSED at x', 'page.goto: Timeout 30000ms exceeded.', 'page.goto: net::ERR_NETWORK_CHANGED_LATER is not the code']) {
    it(`throws "${message}" unchanged after 1 call, with no retry`, async () => {
      capture();
      const error = new Error(message);
      const page = fakePage([error, { status: 200 }]);
      await assert.rejects(gotoSettled(page, URL_), (thrown) => thrown === error);
      assert.equal(page.calls.length, 1);
      assert.deepEqual(lines, []);
    });
  }
});

describe('the shared navigation sites', () => {
  const sites = [
    ['e2e/sign-in/helpers.ts', 'fillSignIn'],
    ['e2e/support/trace.ts', 'openTrace'],
    ['e2e-online/support.ts', 'signInFromSplash'],
    ['e2e-online/support.ts', 'openTraceTab'],
    ['e2e-online/support.ts', 'expectTraceSignIn'],
  ];

  /** The text of the exported function from its declaration to the closing brace at the start of a line. */
  const body = (source, name) => {
    const start = source.indexOf(`export async function ${name}(`);
    assert.notEqual(start, -1, `${name} is declared`);
    const end = source.indexOf('\n}\n', start);
    assert.notEqual(end, -1, `${name} ends at a closing brace`);
    return source.slice(start, end);
  };

  for (const [file, name] of sites) {
    it(`${name} (${file}) navigates through gotoSettled and never calls goto itself`, () => {
      const text = body(readFileSync(join(web, file), 'utf8'), name);
      assert.match(text, /\bgotoSettled\(/, `${name} calls gotoSettled`);
      assert.doesNotMatch(text, /\.goto\(/, `${name} does not call goto`);
    });
  }
});
