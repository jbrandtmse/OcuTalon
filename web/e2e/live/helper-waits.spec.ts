import { readFileSync } from 'node:fs';
import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { STATE, holdState } from '../support/api';
import {
  PROBE_BOUND_MS,
  closeDiagnosis,
  describeDiagnosis,
  describeGateway,
  describeInFlight,
  describeProbe,
  describeStateRequests,
  gatewayScript,
  printDiagnosis,
  probePage,
  redactLine,
  stateDiagnosis,
  watchRequests,
  type RequestRecord,
  type RequestWatch,
} from '../support/diagnose';
import { loadedAfter } from '../support/floor';
import { boundedClose, expect, test, type Browser, type Page } from '../support/fixtures';
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
 *
 * Story 32.6 (DW-550, DW-774) adds three describes. `the page-side DIAG lines` pins the describers of the request, in-flight and probe lines
 * (no browser). `page.close: the close diagnosis` shows that a close past its bound prints the page, request, renderer, browser and host lines.
 * `loadedAfter: one reload of the page` holds the first GET of /state of a /retry page: with a 20 s bound the page reloads once at 10 s
 * (R1: the reload's GET is answered; R2: it is not, and the call fails as it always did, with the diagnosis once). A /retry page's `mode`
 * says how its GETs of /state are answered (once, hold, fail, ok, reset, and late: the first GET is answered as the reload's document is
 * asked for, which follows 300 ms later, and the reloaded page's GET 2.5 s after it is issued), and `delay` how long the page waits after
 * the answer before it shows its snapshot. Every page-side line of the diagnosis cases below is matched by pattern, because it holds seconds
 * and milliseconds.
 */

let server: Server;
let origin = '';
const held: ServerResponse[] = [];
/** The GETs of /state that the stand-in has seen for each id of a /retry page (loadedAfter's reload cases). */
const stateSeen = new Map<string, number>();
/** The documents of a /retry page that the stand-in has served for each id, and the held first GET of /state of each `mode=late` id. */
const documentsSeen = new Map<string, number>();
const lateHeld = new Map<string, ServerResponse>();

test.beforeAll(async () => {
  server = createServer((request, response) => {
    const url = new URL(request.url ?? '/', 'http://127.0.0.1');
    if (url.pathname === '/retry') {
      const id = url.searchParams.get('id') ?? '';
      const documents = (documentsSeen.get(id) ?? 0) + 1;
      documentsSeen.set(id, documents);
      const send = (): void => {
        response.writeHead(200, { 'content-type': 'text/html' });
        response.end(
          '<!doctype html><title>retry</title><main class="main"></main>' +
            `<script>fetch(${JSON.stringify(STATE)} + location.search).then(function (r) { if (r.ok) setTimeout(function () { document.querySelector('main.main').setAttribute('data-snapshot', 'loaded'); }, Number(new URLSearchParams(location.search).get('delay')) || 0); }).catch(function () {});</script>`,
        );
      };
      const first = lateHeld.get(id);
      if (url.searchParams.get('mode') === 'late' && documents === 2 && first !== undefined) {
        // The reload's document: the first document's held GET of /state is answered first, and the document follows 300 ms later.
        lateHeld.delete(id);
        first.writeHead(200, { 'content-type': 'application/json' });
        first.end('{}');
        setTimeout(send, 300);
        return;
      }
      send();
      return;
    }
    const mode = url.pathname === STATE ? url.searchParams.get('mode') : null;
    if (mode !== null) {
      const id = url.searchParams.get('id') ?? '';
      const seen = (stateSeen.get(id) ?? 0) + 1;
      stateSeen.set(id, seen);
      if (mode === 'reset') {
        request.socket.destroy();
        return;
      }
      if (mode === 'late') {
        if (seen === 1) lateHeld.set(id, response);
        else setTimeout(() => response.writeHead(200, { 'content-type': 'application/json' }).end('{}'), 2_500);
        return;
      }
      if (mode === 'hold' || (mode === 'once' && seen === 1)) held.push(response);
      else {
        response.writeHead(mode === 'fail' ? 500 : 200, { 'content-type': 'application/json' });
        response.end('{}');
      }
      return;
    }
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
 * DW-550 (Stories 11.22 and 11.27): when loadedAfter's snapshot GET passes its bound, diagnose.ts prints `DIAG /state` lines from two reads of
 * the stack's IRIS (the licence, CSP processes and locks, then the web gateway) before the same named error is thrown; each read is best
 * effort and its failure is one `DIAG /state unavailable` or `DIAG /state gateway unavailable` line. Every printed line is also in
 * state-diagnosis.txt of the test's output folder. The session is the OCUTALON_E2E_IRIS_EXEC stand-in, a shell command that prints the CHK
 * lines a real read would; it branches on the script text, because the two reads are told apart by it (the gateway script names
 * GetGatewayRegistry).
 */
/** A stand-in session that answers the gateway script with the gateway lines and any other script with the first lines (a command line of printf arguments). */
function standIn(first: string, gateway: string): string {
  return `s=$(cat); case $s in *GetGatewayRegistry*) ${gateway};; *) ${first};; esac`;
}

const printing = (...lines: string[]): string => `printf '%s\\n' ${lines.map((line) => `'${line}'`).join(' ')}`;

/**
 * The page-side lines (Story 32.6) that follow 11.27's lines when the snapshot GET of a page that issued it once is still unanswered: the one
 * request, the one fetch in flight, the answer of the page's renderer and the worker host's line. Matched by pattern, because the seconds and
 * the milliseconds vary (and the host line holds the host's own readings or `not measured`).
 */
function expectPageLines(lines: string[]): void {
  expect(lines, 'the four page-side lines').toHaveLength(4);
  expect(lines[0]).toMatch(/^DIAG \/state request 1 of 1: issued \d+(\.\d)? s after the sign-in began, no answer yet$/);
  expect(lines[1]).toMatch(/^DIAG \/state page: 1 request in flight \(fetch=1\), the oldest issued \d+(\.\d)? s ago$/);
  expect(lines[2]).toMatch(/^DIAG \/state page: the page answered in \d+ ms \(readyState complete\)$/);
  expect(lines[3]).toMatch(/^DIAG \/state host: /);
}

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

  test('the dump runs, shows the licence, the CSP processes, the lock and the gateway, keeps the lines in a file, and the error text is unchanged', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(
      printing('CHK|licence|LUAvailable=7|LUConsumed=1|KeyEnforcedUnits=8|CSPUsers=0|InstanceConnections=1', 'CHK|csp|3248|EVTW|%SYS.cspServer3', 'CHK|lock|3222|X|1|uLFv', 'CHK|done|1'),
      printing('CHK|gw|1', 'CHK|gwserver|1|1|6|1|0|0', 'CHK|gwconn|1|Free|4', 'CHK|gwconn|1|InUse|1', 'CHK|done|1'),
    );
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    const expected = [
      'DIAG /state licence: LUAvailable=7, LUConsumed=1, KeyEnforcedUnits=8, CSPUsers=0, InstanceConnections=1',
      'DIAG /state csp process: pid=3248 state=EVTW routine=%SYS.cspServer3',
      'DIAG /state session lock: held by pid 3222 (mode X, count 1) on session uLFv...',
      'DIAG /state gateway 1 server 1: TotalConnections=6, ConnectionsInUse=1, PrivateConnections=0, QueuedRequests=0',
      'DIAG /state gateway 1 connections: Free=4, InUse=1',
    ];
    expect(logged.slice(0, expected.length)).toEqual(expected);
    expectPageLines(logged.slice(expected.length));
    expect(readFileSync(test.info().outputPath('state-diagnosis.txt'), 'utf8')).toBe(`${logged.join('\n')}\n`);
    const attached = test.info().attachments.filter((attachment) => attachment.name === 'state-diagnosis');
    expect(attached, 'one state-diagnosis attachment').toHaveLength(1);
    expect(attached[0]?.path).toBe(test.info().outputPath('state-diagnosis.txt'));
    expect(attached[0]?.contentType).toBe('text/plain');
  });

  test('a session with no lock says so', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(printing('CHK|licence|LUAvailable=7|LUConsumed=1', 'CHK|done|1'), printing('CHK|gw|0', 'CHK|done|1'));
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged.slice(0, 3)).toEqual(['DIAG /state licence: LUAvailable=7, LUConsumed=1', 'DIAG /state session lock: none held', 'DIAG /state gateway: none registered']);
    expectPageLines(logged.slice(3));
  });

  test('a dump that cannot run prints one unavailable line per read, and the error text is unchanged', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toHaveLength(6);
    expect(logged[0]).toMatch(/^DIAG \/state unavailable: OCUTALON_URL must be set/);
    expect(logged[1]).toMatch(/^DIAG \/state gateway unavailable: OCUTALON_URL must be set/);
    expectPageLines(logged.slice(2));
  });

  test('a gateway read that hangs past its bound costs none of the first read\'s lines, and the test still ends in time', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(printing('CHK|licence|LUAvailable=7', 'CHK|done|1'), 'exec sleep 60');
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toHaveLength(7);
    expect(logged.slice(0, 2)).toEqual(['DIAG /state licence: LUAvailable=7', 'DIAG /state session lock: none held']);
    expect(logged[2]).toMatch(/^DIAG \/state gateway unavailable: .*no answer within \d+(\.\d+)? s/);
    expectPageLines(logged.slice(3));
  });

  test('the two reads run at once: two reads of 2 s each end in well under 4 s, with the lines of both', async () => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(`sleep 2; ${printing('CHK|licence|LUAvailable=7', 'CHK|done|1')}`, `sleep 2; ${printing('CHK|gw|0', 'CHK|done|1')}`);
    const started = Date.now();
    await stateDiagnosis();
    const elapsed = Date.now() - started;
    expect(logged).toEqual(['DIAG /state licence: LUAvailable=7', 'DIAG /state session lock: none held', 'DIAG /state gateway: none registered']);
    expect(elapsed, 'two sequential reads would take 4 s or more').toBeLessThan(3_600);
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

  /**
   * Values that the redaction must keep out of the printed lines and the file. They are built from parts at run time, so that no key-shaped
   * literal sits in the repository, and they hold no single quote and no pipe (the stand-in prints them inside single quotes, in CHK lines).
   */
  const planted = {
    cookie: ['PLANTED', 'COOKIE', 'VALUE', '0123'].join(''),
    header: ['PLANTED', 'HEADER', 'COOKIE', '4567'].join(''),
    bearer: ['PLANTED', 'BEARER', 'TOKEN', '89ab'].join(''),
    opaque: ['PLANTED', 'OPAQUE', 'TOKEN', 'cdef', '0123'].join(''),
    body: ['PLANTED', 'BODY', 'TEXT'].join(''),
    session: ['PLANTED', 'SESSION', 'REST', '4567'].join(''),
    anthropic: ['sk-', 'ant-', 'PLANTED', 'KEY', '0123'].join(''),
    openai: ['sk-', 'PLANTED', 'KEY', '4567'].join(''),
    github: ['gh', 'p_', 'PLANTED', 'KEY', '0123456789'].join(''),
    aws: ['AK', 'IA', 'PLANTED', '0123456789'].join(''),
  } as const;
  const cookiePair = `${['CSPSESSIONID', '-SP-52773-UP-csp-'].join('')}=${planted.cookie}`;
  const jsonBody = `{"user":"${planted.body}","n":1}`;

  async function runPlanted(browser: Browser, first: string[], gateway: string[]): Promise<{ file: string; shown: string }> {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(printing(...first, 'CHK|done|1'), printing(...gateway, 'CHK|done|1'));
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    const file = readFileSync(test.info().outputPath('state-diagnosis.txt'), 'utf8');
    expect(file, 'the file equals the printed lines').toBe(`${logged.join('\n')}\n`);
    expectPageLines(logged.slice(-4));
    return { file, shown: logged.join('\n') };
  }

  function expectNoPlanted(text: string): void {
    for (const [name, value] of Object.entries(planted)) expect.soft(text, `the planted ${name} value`).not.toContain(value);
    expect.soft(text).not.toContain(cookiePair);
  }

  test('a cookie, token, body, key or full session id that the first read prints reaches neither the file nor stdout, and the counts and states do', async ({ browser }) => {
    const { file, shown } = await runPlanted(
      browser,
      [
        `CHK|licence|LUAvailable=7|LUConsumed=1|Session=${cookiePair}|Auth=Bearer ${planted.bearer}`,
        `CHK|csp|3248|EVTW|%SYS.cspServer3 key=${planted.anthropic} alt=${planted.openai} gh=${planted.github} aws=${planted.aws} opaque=${planted.opaque}`,
        `CHK|csp|3249|READ|Cookie: other=1; ${['CSPSESSIONID', '-x'].join('')}=${planted.header}`,
        `CHK|error|csp|failed with ${jsonBody}`,
        `CHK|lock|3222|X|1|uLFv${planted.session}`,
      ],
      ['CHK|gw|1', 'CHK|gwserver|1|1|6|1|0|0', 'CHK|gwconn|1|Free|4', 'CHK|gwconn|1|InUse|1'],
    );
    expectNoPlanted(file);
    expectNoPlanted(shown);
    expect(logged).toContain('DIAG /state licence: LUAvailable=7, LUConsumed=1, Session=cookie=[redacted], Auth=Bearer [redacted]');
    expect(logged).toContain('DIAG /state csp process: pid=3249 state=READ routine=Cookie: [redacted]');
    expect(logged).toContain('DIAG /state session lock: held by pid 3222 (mode X, count 1) on session uLFv...');
    expect(logged).toContain('DIAG /state csp process: pid=3248 state=EVTW routine=%SYS.cspServer3 key=[redacted] alt=[redacted] gh=[redacted] aws=[redacted] opaque=[redacted]');
    expect(logged).toContain('DIAG /state csp unavailable: failed with [redacted]');
    expect(logged).toContain('DIAG /state gateway 1 server 1: TotalConnections=6, ConnectionsInUse=1, PrivateConnections=0, QueuedRequests=0');
    expect(logged).toContain('DIAG /state gateway 1 connections: Free=4, InUse=1');
  });

  test('a cookie, token, body or key that the gateway read\'s error text carries reaches neither the file nor stdout', async ({ browser }) => {
    const { file, shown } = await runPlanted(
      browser,
      ['CHK|licence|LUAvailable=7|LUConsumed=1'],
      [`CHK|error|gateway|<PROTECT> refused for ${planted.anthropic} and ${cookiePair} and Bearer ${planted.bearer} and ${planted.opaque} with ${jsonBody}`],
    );
    expectNoPlanted(file);
    expectNoPlanted(shown);
    expect(logged).toContain('DIAG /state licence: LUAvailable=7, LUConsumed=1');
    const gateway = logged.filter((line) => line.startsWith('DIAG /state gateway unavailable: <PROTECT> refused for '));
    expect(gateway, 'the gateway line keeps its reason').toHaveLength(1);
  });

  /**
   * One planted value per alternative of the redaction. A key value holds no digit, so that the rule for long opaque tokens cannot take it in
   * place of its own rule.
   */
  test('each kind of cookie, header, token, body and key that the redaction names is removed, and a session id is cut to four characters', async () => {
    const value = ['PLANTED', 'KEY', 'LETTERS', 'ONLY', 'ABCDEF'].join('');
    const cases: Array<[string, string]> = [
      ['a CSPCHD pair', `routine=${['CSP', 'CHD'].join('')}=${value} end`],
      ['a CSPWSERVERID pair', `routine=${['CSPWSERVER', 'ID'].join('')}=${value} end`],
      ['a name: value pair', `routine=${['CSPSESSION', 'ID'].join('')}: ${value} end`],
      ['a glued, lower-case pair', `routine=x${['cspsession', 'id'].join('')}=${value} end`],
      ['a Set-Cookie header', `routine=${['Set-', 'Cookie'].join('')}: a=${value}; Path=/`],
      ['a Cookie header', `routine=${['Coo', 'kie'].join('')}: a=${value}`],
      ['a lower-case cookie header', `routine=${['coo', 'kie'].join('')}: a=${value}`],
      ['a header whose name ends in Cookie', `routine=HTTP_${['COO', 'KIE'].join('')}: a=${value}`],
      ['a Cookie header with a carriage return', `routine=${['Coo', 'kie'].join('')}: a=1\r${value}`],
      ['a pair with a space before its sign', `routine=${['CSPSESSION', 'ID'].join('')} = ${value} end`],
      ['two pairs on one line', `routine=${['CSP', 'CHD'].join('')}=x, ${['CSPWSERVER', 'ID'].join('')}=${value} end`],
      ['a bearer token', `Auth=${['Bea', 'rer'].join('')} ${value}`],
      ['a lower-case bearer token', `Auth=${['bea', 'rer'].join('')} ${value}`],
      ['two bearer tokens on one line', `Auth=${['Bea', 'rer'].join('')} x, Proxy=${['Bea', 'rer'].join('')} ${value}`],
      ['two long tokens on one line', `a=x${'1'.repeat(24)} b=${value}1`],
      ['a JSON object with a carriage return', `failed with {"a":"1\r${value}"}`],
      ['a JSON object', `failed with {"a":"${value}"}`],
      ['a JSON array of objects', `failed with [{"a":"${value}"}]`],
      ['a JSON object with escaped quotes', `failed with {\\"a\\":\\"${value}\\"}`],
      ['a github_pat_ key', `key ${['github', '_pat_'].join('')}${value}`],
      ['a ghp_ key', `key ${['gh', 'p_'].join('')}${value}`],
      ['an ASIA key', `key ${['AS', 'IA'].join('')}${value.toUpperCase()}`],
      ['an AKIA key', `key ${['AK', 'IA'].join('')}${value.toUpperCase()}`],
      ['an AKIA key glued to a word', `key=id${['AK', 'IA'].join('')}${value.toUpperCase()}`],
      ['an xox token', `key ${['xo', 'xb-'].join('')}${value}`],
      ['an AIza key', `key ${['AI', 'za'].join('')}${value}`],
      ['an sk-ant- key', `key ${['sk-', 'ant-'].join('')}${value}`],
      ['an sk- key', `key ${['sk', '-'].join('')}${value}`],
    ];
    for (const [name, line] of cases) {
      const redacted = redactLine(line);
      expect.soft(redacted, name).not.toContain(value);
      expect.soft(redacted, name).toContain('[redacted]');
    }
    expect.soft(redactLine(`routine=${['Set-', 'Cookie'].join('')}: a=${value}`), 'a Set-Cookie header is taken whole').toBe('routine=Cookie: [redacted]');
    expect.soft(redactLine(`failed with [{"a":"${value}"}]`), 'a JSON array is taken whole').toBe('failed with [redacted]');
    const lock = 'DIAG /state session lock: held by pid 3222 (mode X, count 1) on session ';
    expect(redactLine(`${lock}uLFv${value}...`)).toBe(`${lock}uLFv...`);
    expect(redactLine(`${lock}u LF${value}...`)).toBe(`${lock}u LF...`);
    expect(redactLine(`${lock}uL...`)).toBe(`${lock}uL...`);
  });

  test('the redaction keeps the lines that carry counts and states as they are', async () => {
    for (const line of [
      'DIAG /state licence: LUAvailable=7, LUConsumed=1, KeyEnforcedUnits=8, CSPUsers=0, InstanceConnections=1',
      'DIAG /state csp process: pid=3248 state=EVTW routine=%SYS.cspServer3',
      'DIAG /state session lock: held by pid 3222 (mode X, count 1) on session uLFv...',
      'DIAG /state gateway 1 server 1: TotalConnections=6, ConnectionsInUse=1, PrivateConnections=0, QueuedRequests=0',
      'DIAG /state gateway 1 connections: Free=4, InUse=1',
      'DIAG /state gateway unavailable: <PROTECT> no use of %CSP.Mgr.GatewayMgr',
    ]) {
      expect(redactLine(line)).toBe(line);
    }
  });

  test('a read that the session refuses is named, and an unread lock is not reported as none held', async () => {
    expect(describeDiagnosis(['CHK|licence|LUAvailable=7', 'CHK|error|lock|<PROTECT> no use of %SYS.LockQuery', 'CHK|done|1'])).toEqual([
      'DIAG /state licence: LUAvailable=7',
      'DIAG /state lock unavailable: <PROTECT> no use of %SYS.LockQuery',
    ]);
  });

  test('a gateway read is described by its servers and states, and a refused or odd one is named without its value', async () => {
    expect(describeGateway(['CHK|gw|1', 'CHK|gwserver|1|1|6|1|0|0', 'CHK|gwconn|1|Free|4', 'CHK|gwconn|1|InUse|1', 'CHK|done|1'])).toEqual([
      'DIAG /state gateway 1 server 1: TotalConnections=6, ConnectionsInUse=1, PrivateConnections=0, QueuedRequests=0',
      'DIAG /state gateway 1 connections: Free=4, InUse=1',
    ]);
    expect(describeGateway(['CHK|gw|0', 'CHK|done|1'])).toEqual(['DIAG /state gateway: none registered']);
    expect(describeGateway(['CHK|gw|2', 'CHK|done|1'])).toEqual(['DIAG /state gateway: 2 registered, no server or connection reported']);
    expect(describeGateway(['CHK|gw|1', 'CHK|error|gateway|<PROTECT> no use of %CSP.Mgr.GatewayMgr', 'CHK|done|1'])).toEqual([
      'DIAG /state gateway unavailable: <PROTECT> no use of %CSP.Mgr.GatewayMgr',
    ]);
    expect(describeGateway(['CHK|gw|1', 'CHK|gwserver|1|1|6|x7|0|0', 'CHK|done|1'])).toEqual(['DIAG /state gateway unavailable: an unexpected reading']);
    expect(describeGateway(['CHK|gw|1', 'CHK|gwserver|1|1|6|1|0', 'CHK|done|1'])).toEqual(['DIAG /state gateway unavailable: an unexpected reading']);
    const cookie = describeGateway(['CHK|gw|1', 'CHK|gwserver|1|1|6|1|0|0', 'CHK|gwconn|1|CSPSESSIONID=abc|1', 'CHK|done|1']);
    expect(cookie).toEqual(['DIAG /state gateway unavailable: an unexpected reading']);
    expect(describeGateway(['CHK|done|1'])).toEqual(['DIAG /state gateway unavailable: the session printed no reading']);
    expect(describeGateway([])).toEqual(['DIAG /state gateway unavailable: the session printed no reading']);
  });

  test('the gateway script reads counts and states only: it names no PID, address, port, server name, idle time or activity', async () => {
    const script = gatewayScript();
    for (const property of ['WebServerPID', 'CacheServerPID', 'IPAddress', 'TCPPort', 'CacheServerName', 'IdleTime', 'Activity']) {
      expect(script, property).not.toContain(property);
    }
    for (const property of ['TotalConnections', 'ConnectionsInUse', 'PrivateConnections', 'QueuedRequests']) expect(script).toContain(property);
  });

  test('the gateway script parses as one session line: an argumentless Quit is followed by two spaces, so that the next command is not its argument', async () => {
    const script = gatewayScript();
    expect(script).toMatch(/Quit:\S+ {2}\S/);
    expect(script, 'a Quit with one space before the next command').not.toMatch(/Quit(?::\S+)? \S/);
  });
});

/**
 * DW-550, DW-774 (Story 32.6), the page-side `DIAG` lines are built from checked values only: the describers of diagnose.ts, with no browser.
 */
test.describe('the page-side DIAG lines', () => {
  const began = 1_000;
  const now = 5_000;
  const record = (extra: Partial<RequestRecord> = {}): RequestRecord => ({ issuedAt: 2_200, type: 'fetch', state: true, ...extra });
  const cookiePair = `${['CSPSESSIONID', '-SP-52773-UP-csp-'].join('')}=${['PLANTED', 'COOKIE', 'VALUE', '0123'].join('')}`;

  test('a page that issued no /state says so', async () => {
    expect(describeStateRequests([], began, now)).toEqual(['DIAG /state request: none issued by the page since the sign-in began']);
    expect(describeStateRequests([record({ state: false })], began, now)).toEqual(['DIAG /state request: none issued by the page since the sign-in began']);
  });

  test('a request is described by its issue time and its outcome: no answer yet, answered, or failed', async () => {
    expect(describeStateRequests([record()], began, now)).toEqual(['DIAG /state request 1 of 1: issued 1.2 s after the sign-in began, no answer yet']);
    expect(describeStateRequests([record({ status: 200, answeredAt: 2_700, endedAt: 2_800 })], began, now)).toEqual([
      'DIAG /state request 1 of 1: issued 1.2 s after the sign-in began, answered 200 at 1.7 s',
    ]);
    expect(describeStateRequests([record({ failedAt: 3_000, error: 'net::ERR_ABORTED' })], began, now)).toEqual([
      'DIAG /state request 1 of 1: issued 1.2 s after the sign-in began, failed at 2 s (net::ERR_ABORTED)',
    ]);
  });

  test('only the five newest requests are listed, numbered among all', async () => {
    const seven = Array.from({ length: 7 }, (_, i) => record({ issuedAt: 1_000 + i * 100 }));
    const lines = describeStateRequests(seven, began, now);
    expect(lines).toHaveLength(5);
    expect(lines[0]).toMatch(/^DIAG \/state request 3 of 7: /);
    expect(lines[4]).toMatch(/^DIAG \/state request 7 of 7: /);
  });

  test('an error text outside the class shape, such as a planted cookie pair, prints as another error; an odd status as other', async () => {
    const [line] = describeStateRequests([record({ failedAt: 3_000, error: `net::ERR_X ${cookiePair}` })], began, now);
    expect(line).toBe('DIAG /state request 1 of 1: issued 1.2 s after the sign-in began, failed at 2 s (another error)');
    expect(line).not.toContain('PLANTED');
    expect(describeStateRequests([record({ failedAt: 3_000, error: cookiePair })], began, now)[0]).toContain('(another error)');
    expect(describeStateRequests([record({ failedAt: 3_000 })], began, now)[0]).toContain('(another error)');
    expect(describeStateRequests([record({ status: 99_999, answeredAt: 2_700 })], began, now)[0]).toContain('answered other at 1.7 s');
  });

  test('the requests in flight are counted by type in name order, with the age of the oldest', async () => {
    const records = [
      record({ issuedAt: 3_000, type: 'xhr' }),
      record({ issuedAt: 2_000 }),
      record({ issuedAt: 2_500, type: 'document', endedAt: 2_600 }),
      record({ issuedAt: 1_500, type: 'script', failedAt: 1_600 }),
      record({ issuedAt: 4_000, type: 'fetch' }),
    ];
    expect(describeInFlight('DIAG /state page', records, now)).toBe('DIAG /state page: 3 requests in flight (fetch=2, xhr=1), the oldest issued 3 s ago');
    expect(describeInFlight('DIAG /state page', [record({ issuedAt: 4_500 })], now)).toBe('DIAG /state page: 1 request in flight (fetch=1), the oldest issued 0.5 s ago');
    expect(describeInFlight('DIAG page.close requests', [record({ endedAt: 3_000 })], now)).toBe('DIAG page.close requests: no request in flight');
    expect(describeInFlight('DIAG page.close requests', [], now)).toBe('DIAG page.close requests: no request in flight');
  });

  test('a resource type outside the shape prints as other, and is never echoed', async () => {
    const line = describeInFlight('DIAG /state page', [record({ type: `Fetch ${cookiePair}` }), record({ type: 'websocket' })], now);
    expect(line).toBe('DIAG /state page: 2 requests in flight (other=1, websocket=1), the oldest issued 2.8 s ago');
  });

  test('a probe says that the page answered, gave no answer, is closed or failed, and an odd ready state prints as other', async () => {
    const prefix = 'DIAG /state page: the page';
    expect(describeProbe(prefix, { kind: 'answered', ms: 12.4, readyState: 'complete' })).toBe(`${prefix} answered in 12 ms (readyState complete)`);
    expect(describeProbe(prefix, { kind: 'answered', ms: 3, readyState: 'interactive' })).toBe(`${prefix} answered in 3 ms (readyState interactive)`);
    expect(describeProbe(prefix, { kind: 'answered', ms: 3, readyState: 'loading' })).toBe(`${prefix} answered in 3 ms (readyState loading)`);
    expect(describeProbe(prefix, { kind: 'answered', ms: 3, readyState: cookiePair })).toBe(`${prefix} answered in 3 ms (readyState other)`);
    expect(describeProbe(prefix, { kind: 'none' })).toBe(`${prefix} gave no answer within 2 s`);
    expect(describeProbe(prefix, { kind: 'closed' })).toBe(`${prefix} is closed`);
    expect(describeProbe(prefix, { kind: 'failed', error: 'Error' })).toBe(`${prefix} failed (Error)`);
    expect(describeProbe(prefix, { kind: 'failed', error: cookiePair })).toBe(`${prefix} failed (another error)`);
  });

  test('the browser probe has no ready state, and says when the browser is not Chromium', async () => {
    const prefix = 'DIAG page.close browser:';
    expect(describeProbe(prefix, { kind: 'answered', ms: 7 })).toBe(`${prefix} answered in 7 ms`);
    expect(describeProbe(prefix, { kind: 'none' })).toBe(`${prefix} gave no answer within 2 s`);
    expect(describeProbe(prefix, { kind: 'unmeasured' })).toBe(`${prefix} not measured (not Chromium)`);
  });
});

/**
 * DW-774 (Story 32.6): a page whose close passes its bound prints the close diagnosis before the same error. The page is a real one of its own
 * context, and its close is replaced by a promise that never settles.
 */
test.describe('page.close: the close diagnosis', () => {
  test('prints the page, request, renderer, browser and host lines to stdout and to close-diagnosis.txt, then fails as before', async ({ browser }) => {
    test.setTimeout(30_000);
    const logged: string[] = [];
    const log = console.log;
    const context = await browser.newContext();
    try {
      const page = await context.newPage();
      page.close = () => new Promise<void>(() => undefined);
      boundedClose(page, () => 1_000);
      await page.goto(`${origin}/`);
      console.log = (...args: unknown[]) => void logged.push(args.join(' '));
      const failure = await page.close().then(
        () => undefined,
        (error: unknown) => error,
      );
      console.log = log;
      expect(failure instanceof Error ? failure.message : String(failure)).toMatch(/^page\.close: no answer within 1 s$/);
    } finally {
      console.log = log;
      await context.close();
    }
    expect(logged, 'five lines').toHaveLength(5);
    expect(logged[0]).toBe('DIAG page.close: the page is open, 1 page in its context, the browser is connected');
    expect(logged[1]).toMatch(/^DIAG page\.close requests: 1 request in flight \(fetch=1\), the oldest issued \d+(\.\d)? s ago$/);
    expect(logged[2]).toMatch(/^DIAG page\.close renderer: answered in \d+ ms \(readyState complete\)$/);
    expect(logged[3]).toMatch(/^DIAG page\.close browser: answered in \d+ ms$/);
    expect(logged[4]).toMatch(/^DIAG page\.close host: /);
    expect(readFileSync(test.info().outputPath('close-diagnosis.txt'), 'utf8')).toBe(`${logged.join('\n')}\n`);
    const attached = test.info().attachments.filter((attachment) => attachment.name === 'close-diagnosis');
    expect(attached, 'one close-diagnosis attachment').toHaveLength(1);
    expect(attached[0]?.path).toBe(test.info().outputPath('close-diagnosis.txt'));
  });

  test('a close that ends in time prints nothing', async ({ browser }) => {
    test.setTimeout(30_000);
    const logged: string[] = [];
    const log = console.log;
    const context = await browser.newContext();
    try {
      const page = await context.newPage();
      boundedClose(page, () => 5_000);
      console.log = (...args: unknown[]) => void logged.push(args.join(' '));
      await page.close();
    } finally {
      console.log = log;
      await context.close();
    }
    expect(logged).toEqual([]);
  });
});

/**
 * DW-550 (Story 32.6): a snapshot GET with no answer by half of its bound (20 s here, so 10 s) gets one logged retry inside the same bound: the
 * page reloads once and its own GET gets the rest. The stand-in's /retry page fetches /state with its own query; mode=once holds the first
 * GET of an id and answers the later ones, mode=hold holds them all. The project's waits are 20 s and 10 s, as an online project sets its own.
 */
test.describe('loadedAfter: one reload of the page', () => {
  const own = { actionTimeout: 20_000, navigationTimeout: 10_000 };
  const step = `loadedAfter the snapshot GET ${STATE}`;
  let before: { actionTimeout?: number; navigationTimeout?: number } = {};
  let retryFileBefore: string | undefined;
  let execBefore: string | undefined;
  const logged: string[] = [];
  let log = console.log;

  test.beforeEach(() => {
    const use = test.info().project.use as { actionTimeout?: number; navigationTimeout?: number };
    before = { actionTimeout: use.actionTimeout, navigationTimeout: use.navigationTimeout };
    Object.assign(use, own);
    retryFileBefore = process.env['OCUTALON_E2E_RETRY_LOG'];
    process.env['OCUTALON_E2E_RETRY_LOG'] = test.info().outputPath('retries.txt');
    execBefore = process.env['OCUTALON_E2E_IRIS_EXEC'];
    logged.length = 0;
    log = console.log;
    console.log = (...args: unknown[]) => void logged.push(args.join(' '));
  });

  test.afterEach(() => {
    console.log = log;
    const use = test.info().project.use as Record<string, unknown>;
    for (const [key, value] of Object.entries(before)) {
      if (value === undefined) delete use[key];
      else use[key] = value;
    }
    if (retryFileBefore === undefined) delete process.env['OCUTALON_E2E_RETRY_LOG'];
    else process.env['OCUTALON_E2E_RETRY_LOG'] = retryFileBefore;
    if (execBefore === undefined) delete process.env['OCUTALON_E2E_IRIS_EXEC'];
    else process.env['OCUTALON_E2E_IRIS_EXEC'] = execBefore;
  });

  const retryLine = (): string => `RETRY e2e/live/helper-waits.spec.ts:${test.info().line} ${step}`;

  test('R1: the reload\'s GET is answered: one RETRY line, one reload, the page loaded within the bound', async ({ browser }) => {
    test.setTimeout(60_000);
    const id = `r1-${Date.now()}`;
    let elapsed = 0;
    await withPage(browser, async (page) => {
      const began = Date.now();
      await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=once&id=${id}`)));
      elapsed = Date.now() - began;
      await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    });
    expect(elapsed, 'the first attempt waited half of the bound').toBeGreaterThanOrEqual(10_000);
    expect(elapsed, 'the call resolved within the bound').toBeLessThan(20_000);
    expect(logged, 'RETRY, the four page-side lines, SLOW').toHaveLength(6);
    expect(logged[0]).toBe(retryLine());
    expectPageLines(logged.slice(1, 5));
    expect(logged[5]).toMatch(/^SLOW loadedAfter the snapshot GET \/ocutalon\/api\/v1\/state \d+ s$/);
    expect(readFileSync(test.info().outputPath('retries.txt'), 'utf8'), 'the RETRY line, then the retry-time page lines').toBe(`${logged.slice(0, 5).join('\n')}\n`);
    expect(stateSeen.get(id), 'the server saw two GETs of /state').toBe(2);
  });

  test('R2: the reload\'s GET is not answered either: one RETRY line, the same error at the bound, the diagnosis once', async ({ browser }) => {
    test.setTimeout(60_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(printing('CHK|licence|LUAvailable=7', 'CHK|done|1'), printing('CHK|gw|0', 'CHK|done|1'));
    const id = `r2-${Date.now()}`;
    const began = Date.now();
    let failure: unknown;
    await withPage(browser, async (page) => {
      failure = await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=hold&id=${id}`))).then(
        () => undefined,
        (error: unknown) => error,
      );
    });
    const elapsed = Date.now() - began;
    expect(failure instanceof Error ? failure.message : String(failure)).toMatch(/^loadedAfter the snapshot GET \/ocutalon\/api\/v1\/state: no answer within 20 s$/);
    expect(elapsed).toBeGreaterThanOrEqual(20_000);
    expect(elapsed).toBeLessThan(37_000);
    expect(logged.filter((line) => line.startsWith('RETRY ')), 'one RETRY line').toEqual([retryLine()]);
    expect(logged.filter((line) => line.startsWith('DIAG /state licence:')), "11.27's lines appear once").toEqual(['DIAG /state licence: LUAvailable=7']);
    expect(logged.filter((line) => line.startsWith('DIAG /state gateway:')), "11.27's gateway line appears once").toEqual(['DIAG /state gateway: none registered']);
    const requests = logged.filter((line) => line.startsWith('DIAG /state request '));
    expect(requests.some((line) => line.startsWith('DIAG /state request 1 of 1: '))).toBe(true);
    expect(requests.some((line) => /^DIAG \/state request 1 of 2: /.test(line))).toBe(true);
    expect(requests.some((line) => /^DIAG \/state request 2 of 2: issued .* no answer yet$/.test(line))).toBe(true);
    expectPageLines(logged.slice(1, 5));
    expect(readFileSync(test.info().outputPath('retries.txt'), 'utf8'), 'the RETRY line, then the retry-time page lines').toBe(`${logged.slice(0, 5).join('\n')}\n`);
    expect(stateSeen.get(id), 'the server saw two GETs of /state').toBe(2);
  });

  test('a reload that throws is logged by its class, and the bound decides', async ({ browser }) => {
    test.setTimeout(60_000);
    const id = `r5-${Date.now()}`;
    let failure: unknown;
    await withPage(browser, async (page) => {
      page.reload = () => Promise.reject(new Error(`the reload was refused ${['CSPSESSIONID', '-x'].join('')}=PLANTEDCOOKIEVALUE0123`));
      failure = await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=once&id=${id}`))).then(
        () => undefined,
        (error: unknown) => error,
      );
    });
    expect(failure instanceof Error ? failure.message : String(failure)).toMatch(/^loadedAfter the snapshot GET \/ocutalon\/api\/v1\/state: no answer within 20 s$/);
    expect(logged.filter((line) => line.startsWith('RETRY ')), 'one RETRY line').toEqual([retryLine()]);
    expect(logged.filter((line) => line.startsWith('DIAG /state reload failed')), 'the class only').toEqual(['DIAG /state reload failed: Error']);
    expect(logged.join('\n')).not.toContain('PLANTED');
    expect(stateSeen.get(id), 'the page was not reloaded').toBe(1);
  });

  test('a bound under 20 s stays one wait: no RETRY, no reload, the diagnosis once', async ({ browser }) => {
    test.setTimeout(60_000);
    (test.info().project.use as { actionTimeout?: number }).actionTimeout = 6_000;
    const id = `r3-${Date.now()}`;
    let failure: unknown;
    await withPage(browser, async (page) => {
      failure = await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=once&id=${id}`))).then(
        () => undefined,
        (error: unknown) => error,
      );
    });
    expect(failure instanceof Error ? failure.message : String(failure)).toMatch(/^loadedAfter the snapshot GET \/ocutalon\/api\/v1\/state: no answer within 6 s$/);
    expect(logged.filter((line) => line.startsWith('RETRY '))).toEqual([]);
    expect(stateSeen.get(id), 'the page was not reloaded').toBe(1);
    expectPageLines(logged.slice(-4));
  });

  test('a bound that the test deadline shortens is split at half of the shortened bound', async ({ browser }) => {
    // Own wait 40 s, a 36 s test: the bound is 36 s less the 10 s reserve and the time used, about 25 s, so the retry comes at about 13 s, not at 20 s.
    test.setTimeout(36_000);
    (test.info().project.use as { actionTimeout?: number }).actionTimeout = 40_000;
    const id = `r6-${Date.now()}`;
    let elapsed = 0;
    await withPage(browser, async (page) => {
      const began = Date.now();
      await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=once&id=${id}`)));
      elapsed = Date.now() - began;
    });
    expect(elapsed, 'the retry came at half of the shortened bound').toBeGreaterThanOrEqual(10_000);
    expect(elapsed, 'not at half of the own bound').toBeLessThan(17_000);
    expect(logged.filter((line) => line.startsWith('RETRY ')), 'one RETRY line').toEqual([retryLine()]);
    expect(stateSeen.get(id), 'the server saw two GETs of /state').toBe(2);
  });

  test('a first GET that is answered while the page is probed is kept: no RETRY, no reload; the first attempt counts from the end of the sign-in', async ({ browser }) => {
    test.setTimeout(60_000);
    const id = `r8-${Date.now()}`;
    let probedAfter = 0;
    await withPage(browser, async (page) => {
      const evaluate = page.evaluate.bind(page);
      const began = Date.now();
      let probed = false;
      // The probe of the page is the first evaluate of the call: the held GET is answered, and its answer has reached the test, before the
      // probe runs. The page shows its snapshot 1.5 s after the answer, so the call is still waiting on the page when the probe ends.
      page.evaluate = (async (...args: Parameters<Page['evaluate']>) => {
        if (!probed) {
          probed = true;
          probedAfter = Date.now() - began;
          const answered = page.waitForResponse((response) => new URL(response.url()).pathname === STATE);
          for (const response of held.splice(0)) {
            try {
              response.writeHead(200, { 'content-type': 'application/json' });
              response.end('{}');
            } catch {
              // A response of an earlier case that is gone.
            }
          }
          await answered;
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
        return evaluate(...args);
      }) as Page['evaluate'];
      // The sign-in goes on for 2.5 s after the page has issued its GET: a first attempt counted from the call's start would end 2.5 s early.
      await loadedAfter(page, async () => {
        await page.goto(`${origin}/retry?mode=once&delay=1500&id=${id}`);
        await new Promise((resolve) => setTimeout(resolve, 2_500));
      });
      await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
      // A reload that was wrongly going on would reach the server within this time.
      await new Promise((resolve) => setTimeout(resolve, 1_500));
    });
    expect(probedAfter, 'the first attempt began when the sign-in ended').toBeGreaterThanOrEqual(12_000);
    expect(logged.filter((line) => line.startsWith('RETRY ')), 'no RETRY line').toEqual([]);
    expect(logged.filter((line) => line.startsWith('DIAG ')), 'no page-side lines').toEqual([]);
    expect(stateSeen.get(id), 'the page was not reloaded').toBe(1);
  });

  test('an answer to the first document\'s GET during the reload does not end the wait: the reloaded page\'s own GET is the one waited for', async ({ browser }) => {
    test.setTimeout(60_000);
    const id = `r9-${Date.now()}`;
    await withPage(browser, async (page) => {
      // mode=late: the first GET is answered as the reload's document is asked for, and the reloaded page's GET 2.5 s after it is issued.
      await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=late&id=${id}`)));
      await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    });
    expect(logged.filter((line) => line.startsWith('RETRY ')), 'one RETRY line').toEqual([retryLine()]);
    const slow = logged.find((line) => line.startsWith(`SLOW ${step} `)) ?? '';
    expect(Number(/ (\d+) s$/.exec(slow)?.[1]), 'the snapshot step ended with the answer to the reloaded page\'s GET, not to the first').toBeGreaterThanOrEqual(12);
    expect(stateSeen.get(id), 'the server saw two GETs of /state').toBe(2);
  });

  test('a page that closes while the snapshot is awaited is not retried and not reloaded', async ({ browser }) => {
    test.setTimeout(60_000);
    const id = `r7-${Date.now()}`;
    let failure: unknown;
    const began = Date.now();
    await withPage(browser, async (page) => {
      setTimeout(() => void page.close().catch(() => undefined), 1_000);
      failure = await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=hold&id=${id}`))).then(
        () => undefined,
        (error: unknown) => error,
      );
    });
    expect(failure instanceof Error ? failure.message : String(failure)).toMatch(/closed/i);
    expect(Date.now() - began, 'it failed when the page closed, not at the bound').toBeLessThan(8_000);
    expect(logged.filter((line) => line.startsWith('RETRY '))).toEqual([]);
    expect(stateSeen.get(id), 'the page was not reloaded').toBe(1);
  });

  test('a request watch records the answer and the failure of a GET of /state, keeps the requests in flight past 200 records, and stops', async ({ browser }) => {
    test.setTimeout(60_000);
    const ok = `w1-${Date.now()}`;
    const reset = `w2-${Date.now()}`;
    await withPage(browser, async (page) => {
      const began = Date.now();
      const watch = watchRequests(page);
      await page.goto(`${origin}/retry?mode=ok&id=${ok}`);
      // The page's GET of /state has ended before the next document replaces the page.
      await expect.poll(() => watch.records().some((record) => record.state && record.endedAt !== undefined)).toBe(true);
      await page.goto(`${origin}/retry?mode=reset&id=${reset}`);
      await expect
        .poll(() => watch.records().filter((record) => record.state && (record.status !== undefined || record.failedAt !== undefined)).length)
        .toBe(2);
      const lines = describeStateRequests(watch.records(), began, Date.now());
      expect(lines[0]).toMatch(/^DIAG \/state request 1 of 2: issued \d+(\.\d)? s after the sign-in began, answered 200 at \d+(\.\d)? s$/);
      expect(lines[1]).toMatch(/^DIAG \/state request 2 of 2: issued \d+(\.\d)? s after the sign-in began, failed at \d+(\.\d)? s \(net::ERR_[A-Z_]+\)$/);

      // One GET of /state stays in flight while 230 finished requests follow: the finished ones are dropped first.
      await page.evaluate((url) => void fetch(url).catch(() => undefined), `${origin}${STATE}?mode=hold&id=w3-${Date.now()}`);
      await page.evaluate(async (url) => void (await Promise.all(Array.from({ length: 230 }, () => fetch(url).then((r) => r.text())))), `${origin}/`);
      const kept = watch.records();
      expect(kept.length, 'at most 200 records').toBeLessThanOrEqual(200);
      expect(kept.filter((record) => record.state && record.status === undefined && record.failedAt === undefined), 'the unanswered GET of /state is kept').toHaveLength(1);

      watch.stop();
      const stoppedAt = Date.now();
      const count = watch.records().length;
      await page.evaluate((url) => fetch(url).then((r) => r.text()), `${origin}/`);
      expect(watch.records().length, 'a stopped watch records nothing').toBe(count);
      expect(watch.records().filter((record) => record.issuedAt > stoppedAt), 'no request issued after the stop is recorded').toEqual([]);
    });
  });

  test('a /state answered with 500 is not retried: the snapshot is not served', async ({ browser }) => {
    test.setTimeout(60_000);
    const id = `r4-${Date.now()}`;
    let failure: unknown;
    await withPage(browser, async (page) => {
      failure = await loadedAfter(page, async () => void (await page.goto(`${origin}/retry?mode=fail&id=${id}`))).then(
        () => undefined,
        (error: unknown) => error,
      );
    });
    expect(failure instanceof Error ? failure.message : String(failure)).toMatch(/the snapshot is served/);
    expect(logged).toEqual([]);
    expect(stateSeen.get(id)).toBe(1);
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
  process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(printing('CHK|done|1'), printing('CHK|gw|0', 'CHK|done|1'));
});

test.afterEach(() => {
  if (execBefore === undefined) delete process.env['OCUTALON_E2E_IRIS_EXEC'];
  else process.env['OCUTALON_E2E_IRIS_EXEC'] = execBefore;
});

// --- Stand-in pages (QA, Story 32.6): the probes, the close diagnosis's wiring and holdState's first-N hold, with no stack ---

/** A page that is only as real as the probes and the close diagnosis read it: evaluate, isClosed, and a context with its pages and browser. */
function stubPage(options: { closed?: boolean; pages?: number; browser?: unknown; evaluate?: () => Promise<unknown> } = {}): Page {
  return {
    isClosed: () => options.closed === true,
    evaluate: options.evaluate ?? (() => Promise.resolve('complete')),
    context: () => ({ pages: () => Array.from({ length: options.pages ?? 1 }), browser: () => options.browser ?? null }),
  } as unknown as Page;
}

/** A browser whose CDP session is the given one (or cannot be opened when it is undefined). */
function stubBrowser(session?: { send: () => Promise<unknown> }, connected = true): unknown {
  return {
    isConnected: () => connected,
    newBrowserCDPSession: () => (session === undefined ? Promise.reject(new Error('no CDP here')) : Promise.resolve({ send: session.send, detach: () => Promise.resolve() })),
  };
}

const quietWatch = { records: () => [], host: () => ({ load1: 0.5, cpus: 4 }), stop: () => undefined } as RequestWatch;
const never = (): Promise<never> => new Promise<never>(() => undefined);
const named = (name: string): Error => Object.assign(new Error('refused'), { name });

/** Runs the step with console.log captured, and returns what it printed. */
async function captured(step: () => Promise<unknown> | unknown): Promise<string[]> {
  const logged: string[] = [];
  const log = console.log;
  console.log = (...args: unknown[]) => void logged.push(args.join(' '));
  try {
    await step();
  } finally {
    console.log = log;
  }
  return logged;
}

test.describe('the page-side DIAG lines: probePage on stand-in pages', () => {
  test('the probe is bounded at 2 s, as the matrix says', () => {
    expect(PROBE_BOUND_MS).toBe(2_000);
  });

  test('a closed page is closed, and the renderer is not asked', async () => {
    let asked = 0;
    const probe = await probePage(stubPage({ closed: true, evaluate: () => (asked += 1, Promise.resolve('complete')) }), 500);
    expect(probe).toEqual({ kind: 'closed' });
    expect(asked).toBe(0);
  });

  test('a renderer that answers gives its ready state and the time it took', async () => {
    const probe = await probePage(stubPage({ evaluate: () => Promise.resolve('interactive') }), 500);
    expect(probe).toMatchObject({ kind: 'answered', readyState: 'interactive' });
    expect(describeProbe('p:', probe)).toMatch(/^p: answered in \d+ ms \(readyState interactive\)$/);
  });

  test('a failed ask keeps an error class, prints another error for an odd one, and is closed when the page closed meanwhile', async () => {
    const odd = `Cookie: ${['CSPSESSIONID', '-x'].join('')}=PLANTEDCOOKIEVALUE0123`;
    const kept = await probePage(stubPage({ evaluate: () => Promise.reject(named('TargetClosedError')) }), 500);
    expect(describeProbe('p:', kept)).toBe('p: failed (TargetClosedError)');
    const hidden = await probePage(stubPage({ evaluate: () => Promise.reject(named(odd)) }), 500);
    expect(describeProbe('p:', hidden)).toBe('p: failed (another error)');
    expect(JSON.stringify(hidden)).not.toContain('PLANTED');
    let closed = false;
    const page = { ...stubPage({ evaluate: () => (closed = true, Promise.reject(named('TargetClosedError'))) }), isClosed: () => closed } as unknown as Page;
    expect(await probePage(page, 500)).toEqual({ kind: 'closed' });
  });

  test('a renderer that gives no answer ends the probe at its bound, and a page that throws is a failed probe, never a throw', async () => {
    const began = Date.now();
    expect(await probePage(stubPage({ evaluate: never }), 150)).toEqual({ kind: 'none' });
    expect(Date.now() - began, 'the bound, not the test timeout').toBeLessThan(2_000);
    const broken = { isClosed: () => { throw new Error('gone'); } } as unknown as Page;
    expect(await probePage(broken, 150)).toEqual({ kind: 'failed', error: 'another error' });
  });
});

test.describe('page.close: the close diagnosis, on stand-in pages', () => {
  const fileLines = (): string => readFileSync(test.info().outputPath('close-diagnosis.txt'), 'utf8');

  test('a closed page with no browser says so in each line, and the lines go to stdout, the file and one attachment', async () => {
    const logged = await captured(() => closeDiagnosis(stubPage({ closed: true, pages: 0 }), quietWatch));
    expect(logged.slice(0, 4)).toEqual([
      'DIAG page.close: the page is closed, 0 pages in its context, the browser is not connected',
      'DIAG page.close requests: no request in flight',
      'DIAG page.close renderer: is closed',
      'DIAG page.close browser: not measured (not Chromium)',
    ]);
    expect(logged).toHaveLength(5);
    expect(logged[4]).toMatch(/^DIAG page\.close host: /);
    expect(fileLines()).toBe(`${logged.join('\n')}\n`);
    expect(test.info().attachments.filter((attachment) => attachment.name === 'close-diagnosis')).toHaveLength(1);
  });

  test('an open page of a connected browser whose CDP session cannot be opened is not measured, not failed', async () => {
    const logged = await captured(() =>
      closeDiagnosis(stubPage({ pages: 2, browser: stubBrowser(undefined, true), evaluate: () => Promise.resolve('interactive') }), quietWatch),
    );
    expect(logged[0]).toBe('DIAG page.close: the page is open, 2 pages in its context, the browser is connected');
    expect(logged[2]).toMatch(/^DIAG page\.close renderer: answered in \d+ ms \(readyState interactive\)$/);
    expect(logged[3]).toBe('DIAG page.close browser: not measured (not Chromium)');
  });

  test('a browser that answers prints its time only; one that fails prints an error class, or another error for an odd one', async () => {
    const answered = await captured(() => closeDiagnosis(stubPage({ browser: stubBrowser({ send: () => Promise.resolve({ product: 'Chrome' }) }) }), quietWatch));
    expect(answered[3]).toMatch(/^DIAG page\.close browser: answered in \d+ ms$/);
    expect(answered.join('\n')).not.toContain('Chrome');
    const failed = await captured(() => closeDiagnosis(stubPage({ browser: stubBrowser({ send: () => Promise.reject(named('TargetClosedError')) }) }), quietWatch));
    expect(failed[3]).toBe('DIAG page.close browser: failed (TargetClosedError)');
    const odd = await captured(() => closeDiagnosis(stubPage({ browser: stubBrowser({ send: () => Promise.reject(named('Cookie: x=1')) }) }), quietWatch));
    expect(odd[3]).toBe('DIAG page.close browser: failed (another error)');
  });

  test('a renderer and a browser that give no answer cost one probe bound together, not two', async () => {
    test.setTimeout(30_000);
    const began = Date.now();
    const logged = await captured(() => closeDiagnosis(stubPage({ evaluate: never, browser: stubBrowser({ send: never }) }), quietWatch));
    const elapsed = Date.now() - began;
    expect(logged[2]).toBe('DIAG page.close renderer: gave no answer within 2 s');
    expect(logged[3]).toBe('DIAG page.close browser: gave no answer within 2 s');
    expect(elapsed, 'the probes ran at once').toBeGreaterThanOrEqual(1_900);
    expect(elapsed, 'one bound, not two').toBeLessThan(3_500);
  });

  test('a page that throws on every read ends the diagnosis without a throw and without a line', async () => {
    const broken = {
      isClosed: () => { throw new Error('gone'); },
      evaluate: () => Promise.reject(new Error('gone')),
      context: () => { throw new Error('gone'); },
    } as unknown as Page;
    const logged = await captured(() => expect(closeDiagnosis(broken, quietWatch), 'the diagnosis resolves').resolves.toBeUndefined());
    expect(logged).toEqual([]);
  });

  test('printDiagnosis redacts a secret-shaped value before it reaches stdout or the file, under any name', async () => {
    const planted = `DIAG page.close requests: ${['CSPSESSIONID', '-x'].join('')}=PLANTEDCOOKIEVALUE0123 and Bearer PLANTEDTOKENVALUE0123456789abc`;
    const logged = await captured(() => printDiagnosis([planted, 'DIAG page.close requests: no request in flight'], 'close-diagnosis'));
    expect(logged).toHaveLength(2);
    expect(logged.join('\n')).not.toContain('PLANTED');
    expect(fileLines()).not.toContain('PLANTED');
    expect(fileLines()).toBe(`${logged.join('\n')}\n`);
  });
});

test.describe('loadedAfter: one reload of the page, the first requests held by holdState', () => {
  let plain: Server;
  let plainOrigin = '';
  let plainSeen = 0;

  test.beforeAll(async () => {
    plain = createServer((request, response) => {
      if (request.url === STATE) {
        plainSeen += 1;
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end('{}');
        return;
      }
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end('<!doctype html><title>plain</title>');
    });
    await new Promise<void>((done) => plain.listen(0, '127.0.0.1', done));
    plainOrigin = `http://127.0.0.1:${(plain.address() as AddressInfo).port}`;
  });

  test.afterAll(async () => {
    plain.closeAllConnections();
    await new Promise<void>((done) => plain.close(() => done()));
  });

  /** Starts `count` GETs of /state in the page and gives the promise of their statuses. */
  const startGets = (page: Page, count: number): Promise<number[]> =>
    page.evaluate((args) => {
      const w = window as unknown as { gets?: Promise<number[]> };
      w.gets = Promise.all(Array.from({ length: args.count }, () => fetch(args.url).then((r) => r.status)));
      return Promise.resolve([] as number[]);
    }, { count, url: STATE });

  test('holdState(page, 2) holds the first two GETs of /state, lets the third and later ones through, and release lets the held ones through', async ({ browser }) => {
    test.setTimeout(30_000);
    plainSeen = 0;
    await withPage(browser, async (page) => {
      await page.goto(plainOrigin);
      const hold = await holdState(page, 2);
      await startGets(page, 3);
      await expect.poll(() => plainSeen, { message: 'the third GET went straight to the server' }).toBe(1);
      expect(hold.held(), 'two GETs wait').toBe(2);
      hold.release();
      expect(hold.held(), 'release empties the waiting list').toBe(0);
      const statuses = await page.evaluate(() => (window as unknown as { gets: Promise<number[]> }).gets);
      expect(statuses).toEqual([200, 200, 200]);
      expect(plainSeen).toBe(3);
      await startGets(page, 1);
      expect(await page.evaluate(() => (window as unknown as { gets: Promise<number[]> }).gets), 'after the release nothing is held').toEqual([200]);
    });
  });

  test('holdState(page) without a count holds every GET of /state, as it always did', async ({ browser }) => {
    test.setTimeout(30_000);
    plainSeen = 0;
    await withPage(browser, async (page) => {
      await page.goto(plainOrigin);
      const hold = await holdState(page);
      await startGets(page, 3);
      await expect.poll(() => hold.held()).toBe(3);
      expect(plainSeen, 'none reached the server').toBe(0);
      hold.release();
      expect(await page.evaluate(() => (window as unknown as { gets: Promise<number[]> }).gets)).toEqual([200, 200, 200]);
    });
  });
});
