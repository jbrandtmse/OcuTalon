import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { expect, requestWait, test } from '../support/fixtures';

/**
 * An APIRequestContext call that never answers fails on the action wait in force, with Playwright's call name, before the test timeout
 * (Story 11.22, DW-706): the built-in `request` fixture and a `playwright.request.newContext()` made without a timeout take the share of the
 * test's timeout that the shared test gives pages (2/3 of 9 s here, 6000 ms), a project's or a test.use actionTimeout is kept, and an
 * explicit `timeout` option is kept. The context's wait is fixed when it is made, so the timeout is set for the whole file. Needs no stack:
 * the server answers nothing on /slow. With the wrapper of fixtures.ts removed, these cases run into the 9 s test timeout instead.
 */

test.setTimeout(9_000);

let server: Server;
let origin = '';
const held: ServerResponse[] = [];
let waitInBeforeAll = 0;

test.beforeAll(async () => {
  waitInBeforeAll = requestWait();
  server = createServer((request, response) => {
    if (request.url === '/slow') {
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

/** Runs the call and returns how long it took and the message it failed with ('' when it did not fail). */
async function failure(call: () => Promise<unknown>): Promise<{ ms: number; message: string }> {
  const began = Date.now();
  try {
    await call();
    return { ms: Date.now() - began, message: '' };
  } catch (error) {
    return { ms: Date.now() - began, message: error instanceof Error ? error.message : String(error) };
  }
}

test('the request fixture fails at the action wait: 6000 ms of a 9 s test', async ({ request }) => {
  const result = await failure(() => request.get(`${origin}/slow`));
  expect(result.message).toContain('apiRequestContext.get: Timeout 6000ms exceeded');
  expect(result.ms, 'well before the test timeout').toBeLessThan(8_000);
});

test('playwright.request.newContext() with no options fails at the same wait', async ({ playwright }) => {
  const context = await playwright.request.newContext();
  try {
    const result = await failure(() => context.get(`${origin}/slow`));
    expect(result.message).toContain('apiRequestContext.get: Timeout 6000ms exceeded');
    expect(result.ms, 'well before the test timeout').toBeLessThan(8_000);
  } finally {
    await context.dispose();
  }
});

test('playwright.request.newContext() with other options and no timeout fails at the same wait', async ({ playwright }) => {
  const context = await playwright.request.newContext({ baseURL: origin, extraHTTPHeaders: { 'x-zz': '1' } });
  try {
    const result = await failure(() => context.get('/slow'));
    expect(result.message).toContain('apiRequestContext.get: Timeout 6000ms exceeded');
  } finally {
    await context.dispose();
  }
});

test('a context made with a timeout of its own keeps it', async ({ playwright }) => {
  const context = await playwright.request.newContext({ timeout: 2_000 });
  try {
    const result = await failure(() => context.get(`${origin}/slow`));
    expect(result.message).toContain('apiRequestContext.get: Timeout 2000ms exceeded');
    expect(result.ms).toBeLessThan(5_000);
  } finally {
    await context.dispose();
  }
});

test('a call that passes a timeout of its own keeps it', async ({ request }) => {
  const result = await failure(() => request.get(`${origin}/slow`, { timeout: 1_500 }));
  expect(result.message).toContain('apiRequestContext.get: Timeout 1500ms exceeded');
});

test('in a hook the wait is the action cap of the project, 60 s here', () => {
  expect(waitInBeforeAll).toBe(60_000);
});

test.describe('a test.use actionTimeout', () => {
  test.use({ actionTimeout: 4_000 });

  test('is the wait of the request fixture', async ({ request }) => {
    const result = await failure(() => request.get(`${origin}/slow`));
    expect(result.message).toContain('apiRequestContext.get: Timeout 4000ms exceeded');
    expect(result.ms).toBeLessThan(7_000);
  });
});
