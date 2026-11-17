// Tests gotoSettled (e2e/support/navigate.ts, Story 11.9; DW-415): a navigation that fails with net::ERR_NETWORK_CHANGED or net::ERR_ABORTED
// (Story 11.21, DW-690) is made once more and logs `NAV retry <url> after <the first line of the first error>`; a second failure, and every other error, is thrown unchanged with no retry.
// After net::ERR_NETWORK_CHANGED the retry waits for the failed navigation's error page first (Story 0.39, DW-349, DW-555). The rows run on a fake page, so that the
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

const CHROME_ERROR = 'chrome-error://chromewebdata/';

/**
 * A fake page whose goto answers each queued outcome in turn: an Error is thrown, anything else is returned.
 * errorPage models the failed navigation's error page: 'late' commits it only once something waits for it (a goto made before is interrupted,
 * as Chromium does), 'never' never commits it (waitForURL times out), 'shown' has committed it already; the default has no error page.
 */
function fakePage(outcomes, errorPage) {
  const calls = [];
  const waits = [];
  let current = 'about:blank';
  return {
    calls,
    waits,
    url: () => current,
    async waitForURL(url, options) {
      waits.push({ url, options });
      if (errorPage === 'late') current = CHROME_ERROR;
      else if (errorPage === 'never') throw Object.assign(new Error('page.waitForURL: Timeout exceeded.'), { name: 'TimeoutError' });
    },
    async goto(url, options) {
      calls.push({ url, options });
      const outcome = outcomes[Math.min(calls.length, outcomes.length) - 1];
      if (calls.length > 1 && errorPage === 'late' && current !== CHROME_ERROR) throw new Error('page.goto: Navigation to ' + url + ' is interrupted by another navigation to ' + CHROME_ERROR);
      if (calls.length === 1 && errorPage === 'shown') current = CHROME_ERROR;
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
    assert.deepEqual(lines, [`NAV retry ${URL_} after page.goto: net::ERR_NETWORK_CHANGED at ${URL_}`]);
  });

  it('waits for the failed navigation\'s error page before its retry, so that a late commit does not interrupt it (DW-349, DW-555)', async () => {
    capture();
    const page = fakePage([changed(), { status: 200, second: true }], 'late');
    assert.deepEqual(await gotoSettled(page, URL_, { timeout: 8000 }), { status: 200, second: true });
    assert.equal(page.calls.length, 2);
    assert.equal(page.waits.length, 1);
    assert.equal(page.waits[0].url, CHROME_ERROR);
    assert.equal(page.waits[0].options.waitUntil, 'commit');
    assert.ok(page.waits[0].options.timeout > 0 && page.waits[0].options.timeout <= 8000, `the wait is within the bound: ${page.waits[0].options.timeout}`);
    assert.deepEqual(lines, [`NAV retry ${URL_} after page.goto: net::ERR_NETWORK_CHANGED at ${URL_}`]);
  });

  it('gives the error page only the time left in the bound after the failed goto', async () => {
    capture();
    const page = fakePage([changed(), { status: 200 }], 'late');
    const first = page.goto;
    page.goto = async (url, options) => {
      if (page.calls.length === 0) await new Promise((resolve) => setTimeout(resolve, 300));
      return first(url, options);
    };
    await gotoSettled(page, URL_, { timeout: 1000 });
    assert.equal(page.waits.length, 1);
    assert.ok(page.waits[0].options.timeout <= 720, `the wait gets what the failed goto left of the bound: ${page.waits[0].options.timeout}`);
  });

  it('does not wait when the error page is already there: the URL is checked first', async () => {
    capture();
    const page = fakePage([changed(), { status: 200 }], 'shown');
    assert.deepEqual(await gotoSettled(page, URL_), { status: 200 });
    assert.equal(page.waits.length, 0);
    assert.equal(page.calls.length, 2);
  });

  it('throws the named error, with the first error as its cause and no second goto, when the error page does not show (N2)', async () => {
    capture();
    const first = changed();
    const page = fakePage([first, { status: 200 }], 'never');
    await assert.rejects(gotoSettled(page, URL_, { timeout: 8000 }), (error) => {
      assert.match(error.message, new RegExp(`^gotoSettled: the failed navigation's error page did not show within [0-9.]+ s from ${URL_.replace(/\./g, '\\.')}$`));
      assert.equal(error.cause, first);
      return true;
    });
    assert.equal(page.calls.length, 1);
    assert.deepEqual(lines, []);
  });

  it('does not wait for an error page after net::ERR_ABORTED: no error page is left, and the retry is at once', async () => {
    capture();
    const page = fakePage([new Error(`page.goto: net::ERR_ABORTED at ${URL_}`), { status: 200 }], 'never');
    assert.deepEqual(await gotoSettled(page, URL_), { status: 200 });
    assert.equal(page.waits.length, 0);
    assert.equal(page.calls.length, 2);
  });

  it('names the first line of the first error in the NAV line, and only that line', async () => {
    capture();
    const page = fakePage([new Error(`page.goto: net::ERR_ABORTED at ${URL_}\nCall log:\n  - navigating to ${URL_}`), { status: 200 }]);
    await gotoSettled(page, URL_);
    assert.deepEqual(lines, [`NAV retry ${URL_} after page.goto: net::ERR_ABORTED at ${URL_}`]);
  });

  it('keeps the error-page interruption out of the retryable errors: that would be a second, hidden retry', () => {
    const source = readFileSync(join(web, 'e2e', 'support', 'navigate.ts'), 'utf8');
    assert.match(source, /^const RETRYABLE = \/net::ERR_\(\?:NETWORK_CHANGED\|ABORTED\)\\b\/;$/m);
  });

  it('throws the second error when the network changed twice, after 2 calls', async () => {
    capture();
    const second = new Error(`page.goto: net::ERR_NETWORK_CHANGED at ${URL_} (second)`);
    const page = fakePage([changed(), second]);
    await assert.rejects(gotoSettled(page, URL_), (error) => error === second);
    assert.equal(page.calls.length, 2);
  });

  it('retries once when the page aborted the navigation (net::ERR_ABORTED): the second answer and one NAV retry line', async () => {
    capture();
    const page = fakePage([new Error(`page.goto: net::ERR_ABORTED at ${URL_}`), { status: 200, second: true }]);
    assert.deepEqual(await gotoSettled(page, URL_), { status: 200, second: true });
    assert.equal(page.calls.length, 2);
    assert.deepEqual(lines, [`NAV retry ${URL_} after page.goto: net::ERR_ABORTED at ${URL_}`]);
  });

  it('throws the second error when the navigation was aborted twice, after 2 calls', async () => {
    capture();
    const second = new Error(`page.goto: net::ERR_ABORTED at ${URL_} (second)`);
    const page = fakePage([new Error(`page.goto: net::ERR_ABORTED at ${URL_}`), second]);
    await assert.rejects(gotoSettled(page, URL_), (error) => error === second);
    assert.equal(page.calls.length, 2);
  });

  for (const message of ['page.goto: net::ERR_CONNECTION_REFUSED at x', 'page.goto: Timeout 30000ms exceeded.', 'page.goto: net::ERR_NETWORK_CHANGED_LATER is not the code', 'page.goto: net::ERR_ABORTED_LATER is not the code']) {
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

describe('gotoSettled breadcrumb', () => {
  it('prints one SLOW line naming the url and the whole seconds when a navigation took 10 s or more, whether it answered or failed', async () => {
    const realNow = Date.now;
    let clock = 0;
    Date.now = () => (clock += 11_000);
    try {
      capture();
      await gotoSettled(fakePage([{ status: 200 }]), URL_);
      assert.deepEqual(lines, [`SLOW gotoSettled ${URL_} 11 s`]);
      capture();
      await assert.rejects(gotoSettled(fakePage([new Error('page.goto: net::ERR_CONNECTION_REFUSED')]), URL_), /ERR_CONNECTION_REFUSED/);
      assert.deepEqual(lines, [`SLOW gotoSettled ${URL_} 11 s`]);
    } finally {
      Date.now = realNow;
    }
  });

  it('prints none for a navigation that timed out at its bound: its error names it', async () => {
    const realNow = Date.now;
    let clock = 0;
    Date.now = () => (clock += 11_000);
    try {
      capture();
      const timedOut = Object.assign(new Error('page.goto: Timeout 5000ms exceeded.'), { name: 'TimeoutError' });
      await assert.rejects(gotoSettled(fakePage([timedOut]), URL_, { timeout: 5000 }), /^Error: gotoSettled: no answer within 5 s from http:\/\/stack\.invalid\/ocutalon\/\n/);
      assert.deepEqual(lines, []);
    } finally {
      Date.now = realNow;
    }
  });
});
