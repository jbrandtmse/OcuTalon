import { spawn } from 'node:child_process';

/**
 * The bounds of the online units' waits (the five online projects of playwright.config.ts: online-demo, online-session, online-allowance,
 * online-demo-path and online-visitors). A wait that never answers fails on its bound and names its step, instead of running to the test
 * timeout of 120 to 300 s. The web/e2e projects keep their waits: their fixtures wait up to 240 s on purpose. Every number lives here only.
 * Erasable TypeScript only: web/scripts/bounded-waits.test.mjs imports this file as it is.
 */

/** The project options of an online project, in ms: actionTimeout bounds a page action and the waits that follow the default timeout (waitForResponse, waitForEvent, page.request); navigationTimeout bounds goto and waitForURL. An explicit timeout wins. */
export const ONLINE_WAITS = { actionTimeout: 30_000, navigationTimeout: 60_000 };

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
