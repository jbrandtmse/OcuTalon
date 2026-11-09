import { readFileSync } from 'node:fs';
import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { stripTypeScriptTypes } from 'node:module';
import { dirname, join } from 'node:path';

import { expect, test, type Browser, type Page } from '../support/fixtures';

/**
 * (QA, Story 32.7, DW-774, A3) The close of leave.spec.ts L5 and L6 does not land while the page is leaving for the splash. The two cases
 * run a stand-in of what the online demo does after a group sign-out: the page polls, is answered 401, and `location.replace`s to the splash,
 * whose document the stand-in holds back (as a loaded host does); the close must wait for the splash's sign-in button and its `load`.
 * The helper under test is leave.spec.ts's own `closeSettled`, cut from that file and run as it is (the spec itself needs a throwaway stack
 * and cannot be imported): a change of the helper there changes what these cases run.
 * - C-1: the close comes after the splash document was served, with no request of the splash still held.
 * - C-2: the close comes after the splash's own subresource was served (`load`), though its button was visible before that.
 * - C-3: a page that does not leave is closed after the wait, and the helper does not throw.
 * Needs a local Chromium only. The helper pages come from browser.newContext(), as the online specs' second visitors do.
 */

const SPLASH_HOLD_MS = 1_500;
const LATE_HOLD_MS = 1_500;
const GIF = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');

let server: Server;
let origin = '';
const timers: NodeJS.Timeout[] = [];
const heldSplash = new Set<ServerResponse>();
/** When the stand-in answered the splash document and its late image, in ms since the epoch (0: not yet). */
const served = { splash: 0, late: 0 };

test.beforeAll(async () => {
  server = createServer((request, response) => {
    const url = new URL(request.url ?? '/', 'http://127.0.0.1');
    if (url.pathname === '/app') {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end(
        '<!doctype html><title>app</title><main>the page</main>' +
          `<script>setTimeout(function () { fetch('/poll').then(function (r) { if (r.status === 401) location.replace('/splash' + ${JSON.stringify(url.search)}); }); }, 150);</script>`,
      );
      return;
    }
    if (url.pathname === '/stay') {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end('<!doctype html><title>stay</title><main>the page stays</main>');
      return;
    }
    if (url.pathname === '/poll') {
      response.writeHead(401).end();
      return;
    }
    if (url.pathname === '/splash') {
      heldSplash.add(response);
      timers.push(
        setTimeout(() => {
          heldSplash.delete(response);
          served.splash = Date.now();
          response.writeHead(200, { 'content-type': 'text/html' });
          response.end('<!doctype html><title>splash</title><button>Sign in and start</button>' + (url.searchParams.has('late') ? '<img src="/late.gif" alt="">' : ''));
        }, SPLASH_HOLD_MS),
      );
      return;
    }
    if (url.pathname === '/late.gif') {
      timers.push(
        setTimeout(() => {
          served.late = Date.now();
          response.writeHead(200, { 'content-type': 'image/gif' });
          response.end(GIF);
        }, LATE_HOLD_MS),
      );
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise<void>((done) => server.listen(0, '127.0.0.1', done));
  origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

test.afterAll(async () => {
  for (const timer of timers) clearTimeout(timer);
  server.closeAllConnections();
  await new Promise<void>((done) => server.close(() => done()));
});

test.beforeEach(() => {
  served.splash = 0;
  served.late = 0;
  heldSplash.clear();
});

/** leave.spec.ts's closeSettled, as the file has it, with its types stripped. */
function closeSettledOfLeaveSpec(): (page: Page) => Promise<void> {
  const source = readFileSync(join(dirname(test.info().file), '..', '..', 'e2e-online', 'session', 'leave.spec.ts'), 'utf8');
  const start = source.indexOf('async function closeSettled(');
  expect(start, 'leave.spec.ts has closeSettled').toBeGreaterThan(-1);
  const end = source.indexOf('\n}\n', start);
  const code = stripTypeScriptTypes(source.slice(start, end + 2));
  return new Function(`${code}\nreturn closeSettled;`)() as (page: Page) => Promise<void>;
}

/** Runs the step with a page of its own context, which gets a short default wait, and closes the context. */
async function withPage(browser: Browser, step: (page: Page) => Promise<void>): Promise<void> {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    page.setDefaultTimeout(10_000);
    await step(page);
  } finally {
    await context.close();
  }
}

test.describe('closeSettled: the close of a page that is leaving for the splash', () => {
  test('C-1: waits for the splash document, and closes with no request of the splash still held', async ({ browser }) => {
    test.setTimeout(30_000);
    const closeSettled = closeSettledOfLeaveSpec();
    await withPage(browser, async (page) => {
      let closedAt = 0;
      let heldAtClose = -1;
      page.on('close', () => {
        closedAt = Date.now();
        heldAtClose = heldSplash.size;
      });
      // The wait starts before the navigation: the page asks for the splash about 150 ms after its script runs, which can be before goto returns.
      const leaving = page.waitForRequest((request) => new URL(request.url()).pathname === '/splash');
      await page.goto(`${origin}/app`);
      await leaving;
      await expect.poll(() => heldSplash.size, { message: 'the page is leaving: the splash document is asked for and held' }).toBeGreaterThan(0);
      expect(page.isClosed()).toBe(false);
      await closeSettled(page);
      expect(page.isClosed(), 'the page is closed').toBe(true);
      expect(served.splash, 'the splash document was served').toBeGreaterThan(0);
      expect(closedAt, 'the close came after the splash document was served').toBeGreaterThanOrEqual(served.splash);
      expect(heldAtClose, 'no request of the splash was held when the page closed').toBe(0);
    });
  });

  test('C-2: waits for the load of the splash, though its sign-in button shows before that', async ({ browser }) => {
    test.setTimeout(30_000);
    const closeSettled = closeSettledOfLeaveSpec();
    await withPage(browser, async (page) => {
      let closedAt = 0;
      page.on('close', () => {
        closedAt = Date.now();
      });
      // The wait starts before the navigation: the page asks for the splash about 150 ms after its script runs, which can be before goto returns.
      const leaving = page.waitForRequest((request) => new URL(request.url()).pathname === '/splash');
      await page.goto(`${origin}/app?late=1`);
      await leaving;
      await closeSettled(page);
      expect(page.isClosed()).toBe(true);
      expect(served.late, 'the splash image was served').toBeGreaterThan(0);
      expect(closedAt, 'the close came after the splash page had loaded (its image was served)').toBeGreaterThanOrEqual(served.late);
    });
  });

  test('C-3: a page that does not leave is closed after the wait, and the helper does not throw', async ({ browser }) => {
    test.setTimeout(30_000);
    const closeSettled = closeSettledOfLeaveSpec();
    await withPage(browser, async (page) => {
      page.setDefaultTimeout(600);
      await page.goto(`${origin}/stay`);
      const began = Date.now();
      await closeSettled(page);
      const took = Date.now() - began;
      expect(page.isClosed(), 'the page is closed anyway').toBe(true);
      expect(took, 'it waited for the button for the default wait before it closed').toBeGreaterThanOrEqual(500);
      expect(took, 'and no longer').toBeLessThan(8_000);
    });
  });
});
