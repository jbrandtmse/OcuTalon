import { expect, test, boundedClose, type Page } from '../support/fixtures';
import { boundedStep, markTestStart } from '../support/bounds';
import { irisScript } from '../support/iris';
import { gotoSettled, type Navigable } from '../support/navigate';

/**
 * A bounded wait never outlasts the time its test has left (Story 11.21, e2e/support/bounds.ts capToDeadline): in a test with a short
 * timeout, a step whose own bound is far longer than the test fails with its own name and the note about the test timeout, and not at the
 * test timeout with no step. Each case sets a 12 s test timeout, so the step is cut to the 5 s floor. It also pins that the shared test
 * bounds page.close(), which takes no timeout in Playwright. The spec needs no stack and no OCUTALON_ variable beyond the one the
 * irisScript case sets itself; only the last case opens a page, in a local Chromium.
 */

const CAPPED = /capped by the test timeout: \d+ s left, the own bound is 60 s\)$/;

test('boundedStep: a step with a long bound fails by name before the test timeout', async () => {
  test.setTimeout(12_000);
  const failure = await boundedStep(new Promise(() => undefined), 60_000, 'hung step').then(
    () => undefined,
    (error: unknown) => error,
  );
  expect(failure).toBeInstanceOf(Error);
  expect((failure as Error).message).toMatch(/^hung step: no answer within 5 s \(/);
  expect((failure as Error).message).toMatch(CAPPED);
});

test('irisScript: a session with a long bound is stopped by name before the test timeout', async () => {
  test.setTimeout(12_000);
  const before = process.env['OCUTALON_E2E_IRIS_EXEC'];
  process.env['OCUTALON_E2E_IRIS_EXEC'] = 'exec sleep 30';
  try {
    await expect(irisScript('  Set a=1\nWrite a', 60_000)).rejects.toThrow(/^irisScript: no answer within 5 s from the script starting "Set a=1" \(capped by the test timeout: /);
  } finally {
    if (before === undefined) delete process.env['OCUTALON_E2E_IRIS_EXEC'];
    else process.env['OCUTALON_E2E_IRIS_EXEC'] = before;
  }
});

test('gotoSettled: a navigation that never ends fails by name before the test timeout', async () => {
  test.setTimeout(12_000);
  const never: Navigable = {
    goto: (_url, options) =>
      new Promise((_resolve, reject) => {
        setTimeout(() => reject(Object.assign(new Error('page.goto: Timeout exceeded.'), { name: 'TimeoutError' })), options?.timeout ?? 0);
      }),
  };
  await expect(gotoSettled(never, 'http://example.test/')).rejects.toThrow(/^gotoSettled: no answer within 5 s from http:\/\/example\.test\/ \(capped by the test timeout: /);
});

test('the time the test has already used is counted: a step that starts late is cut to what is left', async () => {
  test.setTimeout(20_000);
  markTestStart(test.info(), Date.now() - 8_000);
  const failure = await boundedStep(new Promise(() => undefined), 60_000, 'late step').then(
    () => undefined,
    (error: unknown) => error,
  );
  expect((failure as Error).message).toMatch(/^late step: no answer within 5 s \(capped by the test timeout: 1[12] s left, the own bound is 60 s\)$/);
});

test('gotoSettled: the retry runs under the time that is left, and an explicit timeout is passed through', async () => {
  test.setTimeout(20_000);
  const timeouts: Array<number | undefined> = [];
  const aborted: Navigable = {
    goto: async (_url, options) => {
      timeouts.push(options?.timeout);
      if (timeouts.length === 1) {
        markTestStart(test.info(), Date.now() - 9_000);
        throw new Error('page.goto: net::ERR_ABORTED at http://example.test/');
      }
      return null;
    },
  };
  await gotoSettled(aborted, 'http://example.test/');
  expect(timeouts[0], 'the first attempt is cut to the 10 s the margin leaves (a little less: the test has begun)').toBeGreaterThan(9_000);
  expect(timeouts[0]).toBeLessThanOrEqual(10_000);
  expect(timeouts[1], 'the retry to the floor').toBe(5_000);
  const explicit: Navigable = {
    goto: async (_url, options) => {
      timeouts.push(options?.timeout);
      return null;
    },
  };
  await gotoSettled(explicit, 'http://example.test/', { timeout: 99_000 });
  expect(timeouts.at(-1), 'an explicit timeout is the caller\'s own').toBe(99_000);
});

test('page.close: a close that never ends fails by name, and the options reach the close', async () => {
  test.setTimeout(12_000);
  const seen: unknown[] = [];
  const stuck = {
    close: (options?: unknown) => {
      seen.push(options);
      return new Promise<void>(() => undefined);
    },
  } as unknown as Page;
  boundedClose(stuck, () => 1000);
  await expect(stuck.close({ runBeforeUnload: true })).rejects.toThrow('page.close: no answer within 1 s');
  expect(seen).toEqual([{ runBeforeUnload: true }]);
});

test('the shared test bounds the close of the fixture page and of a page of the context', async ({ page, context }) => {
  const second = await context.newPage();
  expect(Object.hasOwn(page, 'close'), 'the fixture page').toBe(true);
  expect(Object.hasOwn(second, 'close'), 'a page of the context').toBe(true);
  await second.close();
  await page.close();
});
