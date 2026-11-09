import { readFileSync } from 'node:fs';

import { expect, test } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { STATE, holdState } from '../support/api';
import { loadedAfter } from '../support/floor';
import { fixtureUser } from '../support/iris';

/**
 * DW-550, DW-774 (Story 32.6), the one logged retry of loadedAfter's snapshot wait against a real stack: only the first GET of /state of the
 * page is held at the browser, and the project's action wait is 20 s, so the first attempt waits 10 s and then the page reloads once. The real
 * application sends /state again on every new document (AD-12), and the sign-in's 303 to a GET of the same URL (AD-13) means a reload lands on
 * the signed-in page of the same session. The call must resolve inside its 20 s with exactly one `RETRY <spec>:<line> ...` line, printed and
 * appended to the file that OCUTALON_E2E_RETRY_LOG names (ci/iris.sh counts that file), with the first miss's page-side lines, and the page must
 * show its loaded snapshot. No line may hold the name of the session cookie or the value of any cookie of the context. The hermetic cases of
 * helper-waits.spec.ts pin the same contract against a stand-in; only this case shows that the real app re-sends /state after a reload.
 */
test('a /state that is held once is retried by one reload, logged, and the page loads', async ({ page }) => {
  test.setTimeout(60_000);
  const logged: string[] = [];
  const log = console.log;
  const use = test.info().project.use;
  const before = use.actionTimeout;
  const retryFile = test.info().outputPath('retries.txt');
  const retryFileBefore = process.env['OCUTALON_E2E_RETRY_LOG'];
  const hold = await holdState(page, 1);
  try {
    console.log = (...args: unknown[]) => void logged.push(args.join(' '));
    process.env['OCUTALON_E2E_RETRY_LOG'] = retryFile;
    // loadedAfter reads the project's action wait at entry for the snapshot bound; the sign-in keeps the shared navigation bound.
    use.actionTimeout = 20_000;
    const { user, password } = fixtureUser('LIVE');
    const began = Date.now();
    await loadedAfter(page, () => signIn(page, user, password));
    const elapsed = Date.now() - began;
    console.log = log;

    const retry = `RETRY e2e/live/state-retry.spec.ts:${test.info().line} loadedAfter the snapshot GET ${STATE}`;
    expect(logged.filter((line) => line.startsWith('RETRY ')), 'exactly one RETRY line').toEqual([retry]);
    // The file holds the RETRY line (the shape that ci/iris.sh counts) and, after it, the retry-time DIAG lines; no other line may be in it.
    const fileText = readFileSync(retryFile, 'utf8');
    expect(fileText.endsWith('\n'), 'the file ends with a newline').toBe(true);
    const fileLines = fileText.slice(0, -1).split('\n');
    const isRetryLine = (line: string): boolean => /^RETRY [A-Za-z0-9._/-]+:[0-9]+ [A-Za-z0-9 ./:_-]+$/.test(line);
    expect(fileLines.filter(isRetryLine), 'the file holds that line').toEqual([retry]);
    expect(fileLines.filter((line) => !isRetryLine(line) && !/^DIAG [ -~]{1,300}$/.test(line)), 'every other line of the file is a DIAG line').toEqual([]);
    expect(logged.some((line) => /^DIAG \/state request 1 of 1: issued .* no answer yet$/.test(line)), 'the page-side line of the first miss').toBe(true);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    expect(hold.held(), 'only the first GET of /state was held').toBe(1);
    expect(elapsed, 'the first attempt waited half of the bound').toBeGreaterThanOrEqual(10_000);

    // A value of fewer than eight characters (a flag such as "1") would match ordinary words; a session cookie's value is long.
    const secrets = ['CSPSESSIONID', ...(await page.context().cookies()).map((cookie) => cookie.value).filter((value) => value.length >= 8)];
    for (const line of [...logged, ...fileLines]) {
      for (const secret of secrets) expect(line, 'no line holds a cookie name or value').not.toContain(secret);
    }
  } finally {
    console.log = log;
    use.actionTimeout = before;
    if (retryFileBefore === undefined) delete process.env['OCUTALON_E2E_RETRY_LOG'];
    else process.env['OCUTALON_E2E_RETRY_LOG'] = retryFileBefore;
    hold.release();
  }
});
