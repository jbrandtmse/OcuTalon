import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { expect, test, type Page, type Route } from '../support/fixtures';

/**
 * A test's route callback never outlives its test (Story 11.21; DW-640, DW-665). Each pair is a leaver followed by a follower: the
 * leaver ends while a route callback is still waiting on route.fetch to an upstream that never answers, and the follower must pass.
 * Without the shared test's unroute (e2e/support/fixtures.ts) the follower fails with `route.fetch: Test ended`, as live.spec.ts L9 and
 * socket.spec.ts W11 did. The pairs cover the callback on the fixture page (a), on the context (b) and on a second page of the context
 * (c), and a page that the test closed itself (d), which must make no error. Needs a local Chromium only: it serves its own page and
 * its own upstream, so it reads no OCUTALON_ variable and needs no stack.
 */

let server: Server;
let origin = '';
let hits = 0;
const held: ServerResponse[] = [];

test.beforeAll(async () => {
  server = createServer((request, response) => {
    if (request.url === '/hang') {
      hits += 1;
      held.push(response);
      return;
    }
    if (request.url === '/') {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end('<!doctype html><title>route cleanup</title><script>function go() { fetch("/hang").catch(function () {}); }</script>');
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

/** A callback that waits on route.fetch to the upstream that never answers. */
const hangingCallback = async (route: Route): Promise<void> => {
  await route.fetch();
};

/** Opens the page and starts the fetch that the callback holds, and returns once the upstream has the request. */
async function holdOne(page: Page): Promise<void> {
  const before = hits;
  await page.goto(`${origin}/`);
  await page.evaluate('go()');
  await expect.poll(() => hits, { message: 'the callback reached the upstream' }).toBeGreaterThan(before);
}

test.describe.serial('a: the callback on the fixture page', () => {
  test('leaver: ends with the callback in flight', async ({ page }) => {
    await page.route('**/hang', hangingCallback);
    await holdOne(page);
  });

  test('follower: passes', async ({ page }) => {
    await page.goto(`${origin}/`);
    await expect(page).toHaveTitle('route cleanup');
  });
});

test.describe.serial('b: the callback on the context', () => {
  test('leaver: ends with the callback in flight', async ({ context }) => {
    await context.route('**/hang', hangingCallback);
    await holdOne(await context.newPage());
  });

  test('follower: passes', async ({ page }) => {
    await page.goto(`${origin}/`);
    await expect(page).toHaveTitle('route cleanup');
  });
});

test.describe.serial('c: the callback on a second page of the context', () => {
  test('leaver: ends with the callback in flight', async ({ context }) => {
    const second = await context.newPage();
    await second.route('**/hang', hangingCallback);
    await holdOne(second);
  });

  test('follower: passes', async ({ page }) => {
    await page.goto(`${origin}/`);
    await expect(page).toHaveTitle('route cleanup');
  });
});

test.describe.serial('d: a page that the test closed itself', () => {
  test('leaver: closes its page after routing', async ({ page }) => {
    await page.route('**/*', (route) => route.continue());
    await page.close();
  });

  test('follower: passes', async ({ page }) => {
    await page.goto(`${origin}/`);
    await expect(page).toHaveTitle('route cleanup');
  });
});
