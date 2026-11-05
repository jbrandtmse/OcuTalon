import { spawn } from 'node:child_process';

/**
 * The bounds of the online units' waits (the five online projects of playwright.config.ts: online-demo, online-session, online-allowance,
 * online-demo-path and online-visitors). A wait that never answers fails on its bound and names its step, instead of running to the test
 * timeout of 120 to 300 s. The web/e2e projects set none: the shared test gives their pages a default wait of a share of the test's own timeout
 * (waitsFor), and their fixtures keep the 240 s they wait on purpose. Every number lives here only.
 * Erasable TypeScript only: web/scripts/bounded-waits.test.mjs imports this file as it is.
 */

/** The project options of an online project, in ms: actionTimeout bounds a page action and the waits that follow the default timeout (waitForResponse, waitForEvent, page.request); navigationTimeout bounds goto and waitForURL. An explicit timeout wins. */
export const ONLINE_WAITS = { actionTimeout: 30_000, navigationTimeout: 60_000 };

/**
 * The default waits that the shared test (fixtures.ts) gives the page of a test whose project sets none, in ms: a share of the test's own
 * timeout, so that a wait without a timeout of its own fails before the test does, with Playwright's call name and the line of the call,
 * and not at the test timeout with no step. The caps keep a long test (120 to 240 s) from waiting a share of that long for one call.
 */
export const WAIT_CAPS = { actionTimeout: 60_000, navigationTimeout: 90_000 };

/** The share of the test timeout that a default wait may use. */
export const WAIT_SHARE = 2 / 3;

/** The default action and navigation waits for a test whose timeout is testMs; a test with no timeout (0 or not finite) gets the caps. */
export function waitsFor(testMs: number): { actionTimeout: number; navigationTimeout: number } {
  const share = Number.isFinite(testMs) && testMs > 0 ? Math.floor(testMs * WAIT_SHARE) : Infinity;
  return { actionTimeout: Math.min(WAIT_CAPS.actionTimeout, share), navigationTimeout: Math.min(WAIT_CAPS.navigationTimeout, share) };
}

/** The ms that a wait armed before its step (a response awaited while a sign-in runs) outlasts the helper's own bound by, so that the helper's message, not Playwright's, is the one that names the step. */
export const WAIT_SLACK_MS = 5_000;

/**
 * The action and navigation waits in force for a test with timeout testMs in a project whose options are use: the project's own
 * actionTimeout and navigationTimeout when it sets them (the online projects), else the shared test's defaults (waitsFor).
 */
export function effectiveWaits(testMs: number, use: { actionTimeout?: number; navigationTimeout?: number } | undefined): { action: number; navigation: number } {
  const fallback = waitsFor(testMs);
  return { action: use?.actionTimeout || fallback.actionTimeout, navigation: use?.navigationTimeout || fallback.navigationTimeout };
}

/**
 * Settles like the work, but rejects with `<step>: no answer within <ms/1000> s` when the work has not settled by ms. The work keeps running
 * (it has no handle to stop), and its late outcome is dropped. A shared helper uses it to name the step that a hang stopped at.
 */
export function boundedStep<T>(work: Promise<T>, ms: number, step: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${step}: no answer within ${ms / 1000} s`)), ms);
    work.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error: unknown) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

/** The longest an irisScript session may take in an online project, in ms: above every 60 s fixture wait that the online specs reach. */
export const ONLINE_IRIS_SCRIPT_MS = 90_000;

/** The longest a call of the Telegram fixture may take, in ms: above the fixture's own longest chain (140 s), so its reason wins when it fails. */
export const TELEGRAM_FIXTURE_MS = 150_000;

/** The irisScript bound that a project's metadata sets (irisScriptMs), or undefined when it sets none or a value that is not positive. */
export function scriptBound(metadata: unknown): number | undefined {
  const ms = (metadata as { irisScriptMs?: unknown } | null | undefined)?.irisScriptMs;
  return typeof ms === 'number' && Number.isFinite(ms) && ms > 0 ? ms : undefined;
}

/**
 * Runs a command with the input on its standard input and resolves with what it wrote to its standard output once it has closed. With ms
 * set, a command that has not closed by then is killed (SIGKILL) and the promise rejects with `<step>: no answer within <ms/1000> s<detail>`.
 */
export function runBounded(cmd: string, args: string[], input: string, ms: number | undefined, step: string, detail = ''): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'ignore'] });
    let out = '';
    let timer: ReturnType<typeof setTimeout> | undefined;
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk: string) => (out += chunk));
    child.stdin.on('error', () => undefined);
    child.on('error', (error) => {
      if (timer !== undefined) clearTimeout(timer);
      reject(error);
    });
    child.on('close', () => {
      if (timer !== undefined) clearTimeout(timer);
      resolve(out);
    });
    if (ms !== undefined) {
      timer = setTimeout(() => {
        child.kill('SIGKILL');
        child.stdout.destroy();
        reject(new Error(`${step}: no answer within ${ms / 1000} s${detail}`));
      }, ms);
    }
    child.stdin.end(input);
  });
}
