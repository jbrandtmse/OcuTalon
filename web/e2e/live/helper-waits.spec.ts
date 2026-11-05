import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { STATE } from '../support/api';
import { loadedAfter } from '../support/floor';
import { expect, test, type Browser, type Page } from '../support/fixtures';
import { gotoSettled } from '../support/navigate';
import { epochOf, signInFromSplash } from '../../e2e-online/support';

/**
 * A wait of the shared helpers that never ends fails on its own bound, shorter than the test's timeout, and names its step (Story 11.21,
 * AC7; DW-690, DW-691): loadedAfter's sign-in and its snapshot GET, gotoSettled's navigation, the online sign-in helpers' POST answer and
 * state GET (signInFromSplash, epochOf), and a page wait with no timeout of its own, which the shared test (e2e/support/fixtures.ts) bounds by a share of the test's timeout (e2e/support/bounds.ts waitsFor) unless the project sets its own waits. Each case sets
 * the project's own waits of 3 s and 4 s (set on the running project, as the online projects set theirs), which are below the deadline cap of a 12 s test; with the bound removed, the case runs into its test timeout instead. The pages of
 * the helper cases come from browser.newContext(), as the online specs' second visitors do. Needs a local Chromium only: its server answers the pages at once and never answers /slow, /state or the sign-in POST.
 */

let server: Server;
let origin = '';
const held: ServerResponse[] = [];

test.beforeAll(async () => {
  server = createServer((request, response) => {
    if (request.url === '/') {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end(`<!doctype html><title>helper waits</title><script>fetch(${JSON.stringify(STATE)}).catch(function () {});</script>`);
      return;
    }
    if (request.url === '/signin') {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end(
        '<!doctype html><title>sign in</title><button id="go">Sign in and start</button>' +
          '<script>document.getElementById("go").onclick = function () { fetch("/post", { method: "POST" }).catch(function () {}); };</script>',
      );
      return;
    }
    if (request.url === '/slow' || request.url === '/post' || request.url === STATE) {
      held.push(response);
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise<void>((done) => server.listen(0, '127.0.0.1', done));
  origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

test.afterAll(async () => {
  server.closeAllConnections();
  await new Promise<void>((done) => server.close(() => done()));
});

/** Runs the step with a page of its own context and closes the context. */
async function withPage(browser: Browser, step: (page: Page) => Promise<void>): Promise<void> {
  const context = await browser.newContext();
  try {
    await step(await context.newPage());
  } finally {
    await context.close();
  }
}

test('the shared test bounds a wait that has no timeout of its own, by a share of the timeout in force', async ({ page }) => {
  test.setTimeout(9_000);
  await expect(page.waitForResponse(() => false)).rejects.toThrow(/Timeout 6000ms exceeded/);
});

test('the shared test bounds a navigation of a second page of its context', async ({ context }) => {
  test.setTimeout(9_000);
  const second = await context.newPage();
  await expect(second.goto(`${origin}/slow`)).rejects.toThrow(/page\.goto: Timeout 6000ms exceeded/);
});

test('the shared test bounds a navigation that has no timeout of its own', async ({ page }) => {
  test.setTimeout(9_000);
  await expect(page.goto(`${origin}/slow`)).rejects.toThrow(/page\.goto: Timeout 6000ms exceeded/);
});

test.describe('a project that sets its own waits', () => {
  test.use({ actionTimeout: 2_000, navigationTimeout: 3_000 });

  test('keeps them: the shared test gives the page no default of its own', async ({ page }) => {
    test.setTimeout(9_000);
    await expect(page.waitForResponse(() => false)).rejects.toThrow(/Timeout 2000ms exceeded/);
    await expect(page.goto(`${origin}/slow`)).rejects.toThrow(/page\.goto: Timeout 3000ms exceeded/);
  });
});

/** The online projects set their own waits; the helpers bound themselves by those, below the 5 s floor of the deadline cap, so the message carries no cap note. */
test.describe('the helpers, in a project that sets its own waits', () => {
  const own = { actionTimeout: 3_000, navigationTimeout: 4_000 };
  let before: { actionTimeout?: number; navigationTimeout?: number } = {};

  test.beforeEach(() => {
    const use = test.info().project.use as { actionTimeout?: number; navigationTimeout?: number };
    before = { actionTimeout: use.actionTimeout, navigationTimeout: use.navigationTimeout };
    Object.assign(use, own);
  });

  test.afterEach(() => {
    Object.assign(test.info().project.use, before);
  });

  test('loadedAfter: a sign-in that never ends fails at its bound, naming the sign-in', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, () => new Promise<void>(() => undefined))).rejects.toThrow(/^loadedAfter the sign-in: no answer within 4 s$/);
    });
  });

  test('loadedAfter: a snapshot that is never answered fails at its bound, naming the GET of /state', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(
        new RegExp(`^loadedAfter the snapshot GET ${STATE.replace(/\//g, '\\/')}: no answer within 3 s$`),
      );
    });
  });

  test('gotoSettled: a navigation that is never answered fails at its bound, naming the url', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(gotoSettled(page, `${origin}/slow`)).rejects.toThrow(new RegExp(`^gotoSettled: no answer within 4 s from ${origin.replace(/\./g, '\\.')}/slow\\n`));
    });
  });

  test('signInFromSplash: a sign-in POST that is never answered fails at its bound, naming the answer', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(signInFromSplash(page, undefined, undefined, `${origin}/signin`)).rejects.toThrow(/^signInFromSplash the answer to the sign-in POST: no answer within 3 s$/);
    });
  });

  test('epochOf: a state GET that is never answered fails at its bound, naming the GET', async ({ browser }) => {
    test.setTimeout(12_000);
    const context = await browser.newContext({ baseURL: origin });
    try {
      const page = await context.newPage();
      await expect(epochOf(page)).rejects.toThrow(new RegExp(`^epochOf the GET ${STATE.replace(/\//g, '\\/')}: no answer within 3 s$`));
    } finally {
      await context.close();
    }
  });
});
