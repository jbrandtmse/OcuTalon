import { readFileSync } from 'node:fs';

import { expect, test } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { holdState, STATE } from '../support/api';
import { loadedAfter } from '../support/floor';
import { fixtureUser } from '../support/iris';

/**
 * DW-550, DW-756 (Story 11.27), the /state diagnosis against a real stack: with the page's /state held at the browser, loadedAfter's snapshot
 * GET passes its bound and diagnose.ts reads the stack's real IRIS. The log must hold the licence line and the web gateway's server and
 * connection lines with whole-number counts and no unavailable line, state-diagnosis.txt of the test's output folder must hold exactly those
 * lines, and no line may hold the session cookie's name or the value of any cookie of the page's context. The hermetic cases of
 * helper-waits.spec.ts pin the same contract against a stand-in; only this case shows that the real gateway answers the read.
 */
test('the /state diagnosis reads the real licence and gateway, keeps its lines in a file, and prints no cookie', async ({ page }) => {
  const logged: string[] = [];
  const log = console.log;
  const use = test.info().project.use;
  const before = use.actionTimeout;
  const hold = await holdState(page);
  let failure: unknown;
  try {
    console.log = (...args: unknown[]) => void logged.push(args.join(' '));
    // loadedAfter reads the project's action wait at entry for the snapshot bound; the sign-in keeps the shared navigation bound.
    use.actionTimeout = 3_000;
    const { user, password } = fixtureUser('LIVE');
    failure = await loadedAfter(page, () => signIn(page, user, password)).then(
      () => undefined,
      (error: unknown) => error,
    );
  } finally {
    console.log = log;
    use.actionTimeout = before;
    hold.release();
  }

  expect(failure instanceof Error ? failure.message : String(failure)).toMatch(new RegExp(`^loadedAfter the snapshot GET ${STATE.replace(/\//g, '\\/')}: no answer within 3 s`));

  const diag = logged.filter((line) => line.startsWith('DIAG /state'));
  expect(diag.filter((line) => line.startsWith('DIAG /state licence:')).length, 'the licence line').toBeGreaterThanOrEqual(1);
  expect(
    diag.filter((line) => /^DIAG \/state gateway \d+ server \d+: TotalConnections=\d+, ConnectionsInUse=\d+, PrivateConnections=\d+, QueuedRequests=\d+$/.test(line)).length,
    'a gateway server line with whole-number counts',
  ).toBeGreaterThanOrEqual(1);
  expect(diag.filter((line) => /^DIAG \/state gateway \d+ connections: /.test(line)).length, 'a gateway connections line').toBeGreaterThanOrEqual(1);
  expect(diag.filter((line) => line.includes('unavailable')), 'no unavailable line').toEqual([]);

  expect(readFileSync(test.info().outputPath('state-diagnosis.txt'), 'utf8'), 'the file holds the logged DIAG lines').toBe(`${diag.join('\n')}\n`);
  expect(test.info().attachments.map((attachment) => attachment.name)).toContain('state-diagnosis');

  // A value of fewer than eight characters (a flag such as "1") would match ordinary words; a session cookie's value is long.
  const secrets = ['CSPSESSIONID', ...(await page.context().cookies()).map((cookie) => cookie.value).filter((value) => value.length >= 8)];
  for (const line of diag) {
    for (const secret of secrets) expect(line, 'no line holds a cookie name or value').not.toContain(secret);
  }
});
