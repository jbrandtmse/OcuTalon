import { readFileSync } from 'node:fs';
import { createServer, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import { STATE } from '../support/api';
import { describeDiagnosis, describeGateway, gatewayScript, redactLine, stateDiagnosis } from '../support/diagnose';
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
    expect(logged).toEqual(expected);
    expect(readFileSync(test.info().outputPath('state-diagnosis.txt'), 'utf8')).toBe(`${expected.join('\n')}\n`);
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
    expect(logged).toEqual(['DIAG /state licence: LUAvailable=7, LUConsumed=1', 'DIAG /state session lock: none held', 'DIAG /state gateway: none registered']);
  });

  test('a dump that cannot run prints one unavailable line per read, and the error text is unchanged', async ({ browser }) => {
    test.setTimeout(12_000);
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toHaveLength(2);
    expect(logged[0]).toMatch(/^DIAG \/state unavailable: OCUTALON_URL must be set/);
    expect(logged[1]).toMatch(/^DIAG \/state gateway unavailable: OCUTALON_URL must be set/);
  });

  test('a gateway read that hangs past its bound costs none of the first read\'s lines, and the test still ends in time', async ({ browser }) => {
    test.setTimeout(12_000);
    process.env['OCUTALON_E2E_IRIS_EXEC'] = standIn(printing('CHK|licence|LUAvailable=7', 'CHK|done|1'), 'exec sleep 60');
    await withPage(browser, async (page) => {
      await expect(loadedAfter(page, async () => void (await page.goto(`${origin}/`)))).rejects.toThrow(failure);
    });
    expect(logged).toHaveLength(3);
    expect(logged.slice(0, 2)).toEqual(['DIAG /state licence: LUAvailable=7', 'DIAG /state session lock: none held']);
    expect(logged[2]).toMatch(/^DIAG \/state gateway unavailable: .*no answer within \d+(\.\d+)? s/);
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
