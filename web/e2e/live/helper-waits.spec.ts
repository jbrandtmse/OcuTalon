import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { STATE } from '../support/api';
import { describeDiagnosis } from '../support/diagnose';
import { loadedAfter } from '../support/floor';
import { expect, test, type Browser, type Page } from '../support/fixtures';
import { gotoSettled } from '../support/navigate';
import { epochOf, landedOn, signInFromSplash, signOutGroup } from '../../e2e-online/support';

/**
 * A wait of the shared helpers that never ends fails on its own bound, shorter than the test's timeout, and names its step (Story 11.21,
 * AC7; DW-690, DW-691): loadedAfter's sign-in and its snapshot GET, gotoSettled's navigation, the online sign-in helpers' POST answer and
 * state GET (signInFromSplash, epochOf), and a page wait with no timeout of its own, which the shared test (e2e/support/fixtures.ts)
 * bounds by a share of the test's timeout (e2e/support/bounds.ts waitsFor) unless the project sets its own waits.
 * - The first cases pin the shared test's default waits, and that a project's own waits are kept.
 * - The helper cases set the running project's waits to 3 s and 4 s, as the online projects set theirs, below the deadline cap of a 12 s
 *   test, so each helper's own bound ends it.
 * - The default-project helper cases set no waits: the helper takes the share of the test timeout and the deadline cap ends it.
 * With a bound removed, a case runs into its test timeout instead. The helper pages come from browser.newContext(), as the online specs'
 * second visitors do. Needs a local Chromium only: its server answers the pages at once and never answers /slow, /state, the sign-in POST
 * or a sign-out (IRISLogout=end).
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
    if (request.url === '/slow' || request.url === '/post' || request.url === STATE || request.url?.includes('IRISLogout=end')) {
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
    const use = test.info().project.use as Record<string, unknown>;
    for (const [key, value] of Object.entries(before)) {
      if (value === undefined) delete use[key];
      else use[key] = value;
    }
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

  test('signOutGroup: each sign-out GET that is never answered is bounded, logged by name and skipped', async ({ browser }) => {
    test.setTimeout(30_000);
    const context = await browser.newContext({ baseURL: origin });
    const logged: string[] = [];
    const log = console.log;
    console.log = (...args: unknown[]) => void logged.push(args.join(' '));
    try {
      await signOutGroup(context);
    } finally {
      console.log = log;
      await context.close();
    }
    expect(logged).toHaveLength(3);
    for (const line of logged) expect(line).toMatch(/^signOutGroup the GET \/ocutalon\/\S*IRISLogout=end: no answer within 3 s$/);
  });
});

/** A project that sets no waits (the web/e2e projects): the helpers bound themselves by the share of the test timeout, which the deadline cap of a 12 s test shortens to 5 s. */
test.describe('the helpers, in a project that sets no waits', () => {
  test('loadedAfter: a snapshot that is never answered fails at the capped share, naming the GET of /state', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(
        new RegExp(`^loadedAfter the snapshot GET ${STATE.replace(/\//g, '\\/')}: no answer within 5 s \\(capped by the test timeout: \\d+ s left, the own bound is 8 s\\)$`),
      );
    });
  });

  test('landedOn: a wait for an address that never comes is capped by the test deadline', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(landedOn(page, /never/, 60_000)).rejects.toThrow(/page\.waitForURL: Timeout 5000ms exceeded/);
    });
  });

  test('epochOf: a state GET that is never answered fails at the capped share, naming the GET', async ({ browser }) => {
    test.setTimeout(12_000);
    const context = await browser.newContext({ baseURL: origin });
    try {
      const page = await context.newPage();
      await expect(epochOf(page)).rejects.toThrow(new RegExp(`^epochOf the GET ${STATE.replace(/\//g, '\\/')}: no answer within 5 s \\(capped by the test timeout: \\d+ s left, the own bound is 8 s\\)$`));
    } finally {
      await context.close();
    }
  });
});

/**
 * DW-550 (Story 11.22): when loadedAfter's snapshot GET passes its bound, diagnose.ts prints `DIAG /state` lines from one read of the stack's
 * IRIS before the same named error is thrown; the read is best effort and its failure is one `DIAG /state unavailable` line. The session is
 * the OCUTALON_E2E_IRIS_EXEC stand-in, a shell command that prints the CHK lines a real read would.
 */
test.describe('loadedAfter: the /state diagnosis', () => {
  const SESSION_VARIABLES = ['OCUTALON_E2E_IRIS_EXEC', 'OCUTALON_E2E_IRIS_CONTAINER', 'OCUTALON_URL'] as const;
  const saved: Partial<Record<(typeof SESSION_VARIABLES)[number], string>> = {};
  const logged: string[] = [];
  let log = console.log;
  const failure = new RegExp(`^loadedAfter the snapshot GET ${STATE.replace(/\//g, '\\/')}: no answer within 5 s \\(capped by the test timeout: \\d+ s left, the own bound is 8 s\\)$`);

  test.beforeEach(() => {
    for (const name of SESSION_VARIABLES) {
      saved[name] = process.env[name];
      delete process.env[name];
    }
    logged.length = 0;
    log = console.log;
    console.log = (...args: unknown[]) => void logged.push(args.join(' '));
  });

  test.afterEach(() => {
    console.log = log;
    for (const name of SESSION_VARIABLES) {
      const value = saved[name];
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  test('the dump runs, shows the licence, the CSP processes and the lock, and the error text is unchanged', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] =
      "cat > /dev/null; printf '%s\\n' 'CHK|licence|LUAvailable=7|LUConsumed=1|KeyEnforcedUnits=8|CSPUsers=0|InstanceConnections=1' " +
      "'CHK|csp|3248|EVTW|%SYS.cspServer3' 'CHK|lock|3222|X|1|uLFv' 'CHK|done|1'";
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toEqual([
      'DIAG /state licence: LUAvailable=7, LUConsumed=1, KeyEnforcedUnits=8, CSPUsers=0, InstanceConnections=1',
      'DIAG /state csp process: pid=3248 state=EVTW routine=%SYS.cspServer3',
      'DIAG /state session lock: held by pid 3222 (mode X, count 1) on session uLFv...',
    ]);
  });

  test('a session with no lock says so', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = "cat > /dev/null; printf '%s\\n' 'CHK|licence|LUAvailable=7|LUConsumed=1' 'CHK|done|1'";
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toEqual(['DIAG /state licence: LUAvailable=7, LUConsumed=1', 'DIAG /state session lock: none held']);
  });

  test('a dump that cannot run prints one unavailable line, and the error text is unchanged', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toHaveLength(1);
    expect(logged[0]).toMatch(/^DIAG \/state unavailable: OCUTALON_URL must be set/);
  });

  test('a sign-in that never ends is not diagnosed: only a snapshot GET that passed its bound is', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = "cat > /dev/null; printf '%s\\n' 'CHK|licence|LUAvailable=7' 'CHK|done|1'";
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, () => new Promise<void>(() => undefined))).rejects.toThrow(/^loadedAfter the sign-in: no answer within 5 s/);
    });
    expect(logged).toEqual([]);
  });

  test('a snapshot wait that fails for another reason than its bound is not diagnosed', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = "cat > /dev/null; printf '%s\\n' 'CHK|licence|LUAvailable=7' 'CHK|done|1'";
    await withPage(browser, async (page) => {
      const closing = async (): Promise<void> => {
        await page.goto(`${origin}/`);
        await page.close();
      };
      await expect(loadedAfter(page, closing)).rejects.toThrow(/closed/i);
    });
    expect(logged).toEqual([]);
  });

  test('a read that the session refuses is named, and an unread lock is not reported as none held', async () => {
    expect(describeDiagnosis(['CHK|licence|LUAvailable=7', 'CHK|error|lock|<PROTECT> no use of %SYS.LockQuery', 'CHK|done|1'])).toEqual([
      'DIAG /state licence: LUAvailable=7',
      'DIAG /state lock unavailable: <PROTECT> no use of %SYS.LockQuery',
    ]);
  });
});

/**
 * Every case of this file that lets loadedAfter's snapshot GET pass its bound runs the /state diagnosis; outside the describe above, which
 * sets a stand-in of its own, the diagnosis reads this stand-in, never the IRIS of a stack the unit may have started, so these cases stay
 * hermetic and take no time of their own for the read.
 */
let execBefore: string | undefined;

test.beforeEach(() => {
  execBefore = process.env['OCUTALON_E2E_IRIS_EXEC'];
  process.env['OCUTALON_E2E_IRIS_EXEC'] = "cat > /dev/null; printf '%s\\n' 'CHK|done|1'";
});

test.afterEach(() => {
  if (execBefore === undefined) delete process.env['OCUTALON_E2E_IRIS_EXEC'];
  else process.env['OCUTALON_E2E_IRIS_EXEC'] = execBefore;
});
