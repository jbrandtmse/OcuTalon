import { spawn } from 'node:child_process';

import { test } from '@playwright/test';

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

/** How long before the running test's timeout a bounded wait must fail, in ms, so that the failure names its step and the spec's `finally` still has a moment to run. */
export const DEADLINE_MARGIN_MS = 10_000;

/** The least a bounded wait is given when the test is nearly out of time, in ms (and never more than the time left less a second): the cleanup steps of a `finally` still get this much. */
export const DEADLINE_FLOOR_MS = 5_000;

/** A bounded wait that ends after at least this many ms prints one `SLOW <step> <s> s` line, so that a log shows where a slow test spent its time. */
export const SLOW_STEP_MS = 10_000;

const testStarts = new WeakMap<object, number>();

/** Records when the test of this TestInfo began (the shared test, fixtures.ts, does it for every test), which testTimeLeftMs counts from. */
export function markTestStart(info: object, at: number = Date.now()): void {
  testStarts.set(info, at);
}

/** The ms left before the running test's timeout, or undefined outside a test, in a test that was not marked, or in a test with no timeout. */
export function testTimeLeftMs(): number | undefined {
  try {
    const info = test.info();
    const began = testStarts.get(info);
    return info.timeout > 0 && began !== undefined ? info.timeout - (Date.now() - began) : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The bound a wait with its own bound ownMs runs under: the smaller of ownMs and the time left before the test timeout minus
 * DEADLINE_MARGIN_MS, so that the last step of a slow chain fails naming itself before the test does. When less than the margin and the
 * floor is left, the step gets DEADLINE_FLOOR_MS, or the time left less a second if that is shorter (at least 1 s). With no test running
 * (leftMs undefined) it is ownMs. note is empty unless the deadline shortened the bound.
 */
export function capToDeadline(ownMs: number, leftMs: number | undefined = testTimeLeftMs()): { ms: number; note: string } {
  if (leftMs === undefined) return { ms: ownMs, note: '' };
  const floor = Math.min(DEADLINE_FLOOR_MS, Math.max(leftMs - 1000, 1000));
  const ms = Math.min(ownMs, Math.max(leftMs - DEADLINE_MARGIN_MS, floor));
  return ms < ownMs ? { ms, note: ` (capped by the test timeout: ${Math.max(0, Math.round(leftMs / 1000))} s left, the own bound is ${ownMs / 1000} s)` } : { ms, note: '' };
}

/** The `SLOW <step> <s> s` line of a step that took elapsedMs, or undefined when it was not slow. */
export function slowLine(step: string, elapsedMs: number): string | undefined {
  return elapsedMs >= SLOW_STEP_MS ? `SLOW ${step} ${Math.round(elapsedMs / 1000)} s` : undefined;
}

/** Prints the SLOW line of a step that began at startedAt (Date.now()) when it was slow. */
export function reportSlow(step: string, startedAt: number): void {
  const line = slowLine(step, Date.now() - startedAt);
  if (line !== undefined) console.log(line);
}

/**
 * Settles like the work, but rejects with `<step>: no answer within <bound/1000> s` when the work has not settled by the bound: ms, or less
 * when the running test's timeout leaves less (capToDeadline, which then adds a note). The work keeps running (it has no handle to stop),
 * and its late outcome is dropped. A shared helper uses it to name the step that a hang stopped at. A step that took SLOW_STEP_MS or more
 * and settled in time prints a SLOW line.
 */
export function boundedStep<T>(work: Promise<T>, ms: number, step: string): Promise<T> {
  const { ms: bound, note } = capToDeadline(ms);
  const startedAt = Date.now();
  return new Promise<T>((resolve, reject) => {
    let over = false;
    const timer = setTimeout(() => {
      over = true;
      reject(new Error(`${step}: no answer within ${bound / 1000} s${note}`));
    }, bound);
    const settle = (): boolean => {
      clearTimeout(timer);
      if (!over) reportSlow(step, startedAt);
      return !over;
    };
    work.then(
      (value) => {
        if (settle()) resolve(value);
      },
      (error: unknown) => {
        if (settle()) reject(error);
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
 * set, a command that has not closed by then (or by the running test's timeout minus DEADLINE_MARGIN_MS, capToDeadline) is killed (SIGKILL)
 * and the promise rejects with `<step>: no answer within <bound/1000> s<detail>`. A command that took SLOW_STEP_MS or more prints a SLOW line.
 */
export function runBounded(cmd: string, args: string[], input: string, ms: number | undefined, step: string, detail = ''): Promise<string> {
  const capped = ms === undefined ? undefined : capToDeadline(ms);
  const startedAt = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'ignore'] });
    let out = '';
    let timer: ReturnType<typeof setTimeout> | undefined;
    let timedOut = false;
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk: string) => (out += chunk));
    child.stdin.on('error', () => undefined);
    child.on('error', (error) => {
      if (timer !== undefined) clearTimeout(timer);
      reject(error);
    });
    child.on('close', () => {
      if (timer !== undefined) clearTimeout(timer);
      if (!timedOut) reportSlow(`${step}${detail}`, startedAt);
      resolve(out);
    });
    if (capped !== undefined) {
      timer = setTimeout(() => {
        timedOut = true;
        child.kill('SIGKILL');
        child.stdout.destroy();
        reject(new Error(`${step}: no answer within ${capped.ms / 1000} s${detail}${capped.note}`));
      }, capped.ms);
    }
    child.stdin.end(input);
  });
}
