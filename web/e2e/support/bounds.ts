import { AsyncLocalStorage } from 'node:async_hooks';
import { spawn } from 'node:child_process';
import { appendFileSync, mkdirSync } from 'node:fs';
import { basename, dirname, isAbsolute, relative, sep } from 'node:path';

import { test } from '@playwright/test';

/**
 * The bounds of the online units' waits (the five online projects of playwright.config.ts: online-demo, online-session, online-allowance,
 * online-demo-path and online-visitors). A wait that never answers fails on its bound and names its step, instead of running to the test
 * timeout of 120 to 300 s. The web/e2e projects set none: the shared test gives their pages a default wait of a share of the test's own timeout
 * (waitsFor), and their fixtures keep the 240 s they wait on purpose, within the test's deadline (capToDeadline). Every number lives here only.
 * Story 32.6 (DW-550, DW-774) adds the one logged retry of a live page's snapshot wait: RETRY_MIN_ATTEMPT_MS and firstAttemptMs split the
 * snapshot bound, retryLine and reportRetry print `RETRY <spec>:<line> <step>` and append it to the file that OCUTALON_E2E_RETRY_LOG names
 * (ci/iris.sh counts those lines per unit and per group), and diagnosedAtBound runs a diagnosis when a bounded step passes its bound.
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
 * The time a test keeps back for its clean-ups (the calls in a spec's `finally`, marked with asCleanup), in ms: a main step never runs
 * into the last cleanupReserve(timeout) of its test. The reserve is a quarter of the test timeout (CLEANUP_RESERVE_SHARE), at least
 * DEADLINE_MARGIN_MS and at most CLEANUP_RESERVE_MS: a 45 s test keeps 11.25 s, a 120 s test 30 s, a test of 240 s or more 60 s.
 */
export const CLEANUP_RESERVE_MS = 60_000;

/** The share of the test timeout that the clean-up reserve takes, below CLEANUP_RESERVE_MS. */
export const CLEANUP_RESERVE_SHARE = 1 / 4;

/** The least reserve a main step leaves before the test timeout, in ms: the reserve of a short test, and of a cap outside a known timeout. */
export const DEADLINE_MARGIN_MS = 10_000;

/** How long before the test timeout a clean-up step must fail, in ms, so that its failure names it and not the test timeout. */
export const CLEANUP_MARGIN_MS = 2_000;

/** The least a main step is given when the test is nearly out of its main time, in ms (and never more than the time left less a second). */
export const DEADLINE_FLOOR_MS = 5_000;

/** The clean-up reserve of a test whose timeout is testMs (see CLEANUP_RESERVE_MS); DEADLINE_MARGIN_MS when the timeout is not known. */
export function cleanupReserve(testMs: number | undefined): number {
  if (testMs === undefined || !Number.isFinite(testMs) || testMs <= 0) return DEADLINE_MARGIN_MS;
  return Math.min(CLEANUP_RESERVE_MS, Math.max(DEADLINE_MARGIN_MS, Math.floor(testMs * CLEANUP_RESERVE_SHARE)));
}

/** A bound in seconds, as the messages write it: whole seconds, or one decimal. */
export function secs(ms: number): string {
  return String(Math.round(ms / 100) / 10);
}

/** A bounded wait that ends after at least this many ms prints one `SLOW <step> <s> s` line, so that a log shows where a slow test spent its time. */
export const SLOW_STEP_MS = 10_000;

const testStarts = new WeakMap<object, number>();

const cleanupScope = new AsyncLocalStorage<boolean>();

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

/** The running test's timeout in ms, or undefined outside a test. */
function testTimeoutMs(): number | undefined {
  try {
    return test.info().timeout;
  } catch {
    return undefined;
  }
}

/**
 * Runs work as a clean-up: every bounded wait it starts (boundedStep, runBounded and so irisScript, gotoSettled, a page's close) may use
 * the test's clean-up reserve, up to CLEANUP_MARGIN_MS before the test timeout, instead of stopping where the main steps stop. The shared
 * clean-up helpers that the specs call in `finally` (finishTelegram, unpairChat, removeSession, signOutGroup, cleanPopulated and
 * removeCounterRows; leaveVisitor through signOutGroup and removeSession) run their body through it.
 */
export function asCleanup<T>(work: () => Promise<T>): Promise<T> {
  return cleanupScope.run(true, work);
}

/** True inside asCleanup. */
export function inCleanup(): boolean {
  return cleanupScope.getStore() === true;
}

/**
 * The bound a wait with its own bound ownMs (Infinity for none) runs under, given leftMs before the test timeout of timeoutMs:
 * - a main step: the smaller of ownMs and leftMs less the clean-up reserve (cleanupReserve), so that the last step of a slow chain fails
 *   naming itself and the clean-ups keep their reserve; when that leaves less than DEADLINE_FLOOR_MS, the floor, or the time left less a
 *   second if that is shorter (at least 1 s);
 * - a clean-up (asCleanup): the smaller of ownMs and leftMs less CLEANUP_MARGIN_MS (at least 1 s).
 * With no test running (leftMs undefined) it is ownMs. note is empty unless the deadline shortened the bound.
 */
export function capToDeadline(ownMs: number, leftMs: number | undefined = testTimeLeftMs(), timeoutMs: number | undefined = testTimeoutMs(), cleanup: boolean = inCleanup()): { ms: number; note: string } {
  if (leftMs === undefined) return { ms: ownMs, note: '' };
  let ms: number;
  if (cleanup) ms = Math.min(ownMs, Math.max(leftMs - CLEANUP_MARGIN_MS, 1000));
  else {
    const floor = Math.min(DEADLINE_FLOOR_MS, Math.max(leftMs - 1000, 1000));
    ms = Math.min(ownMs, Math.max(leftMs - cleanupReserve(timeoutMs), floor));
  }
  if (ms >= ownMs) return { ms, note: '' };
  const own = Number.isFinite(ownMs) ? `the own bound is ${secs(ownMs)} s` : 'no own bound';
  return { ms, note: ` (capped by the test timeout: ${Math.max(0, Math.round(leftMs / 1000))} s left${cleanup ? ' for a clean-up' : ''}, ${own})` };
}

/** The `RETRY <location> <step>` line of a step that was tried a second time; the location is retryLocation()'s. */
export function retryLine(location: string, step: string): string {
  return `RETRY ${location} ${step}`;
}

/** The variable that names the file a retry line is appended to (ci/iris.sh sets it per live unit); unset, a retry is only printed. */
export const RETRY_LOG_VARIABLE = 'OCUTALON_E2E_RETRY_LOG';

/**
 * Where the running test is, as `<spec>:<line>`: the test's file relative to the folder of the Playwright config (the folder of
 * web/playwright.config.ts, not the top testDir that FullConfig.rootDir names), else to the working folder, with `/` separators. A path
 * that is absolute or starts with `..` is cut to the file's base name; outside a test it is `unknown:0`. It never throws.
 */
export function retryLocation(): string {
  try {
    const info = test.info();
    const from = info.config.configFile ? dirname(info.config.configFile) : process.cwd();
    let file = relative(from, info.file).split(sep).join('/');
    if (isAbsolute(file) || file.startsWith('..')) file = basename(info.file);
    return `${file}:${info.line}`;
  } catch {
    return 'unknown:0';
  }
}

/** Prints the `RETRY` line of a step that is tried a second time, and appends it to the file that RETRY_LOG_VARIABLE names when it is set. It never throws. */
export function reportRetry(step: string): void {
  const line = retryLine(retryLocation(), step);
  console.log(line);
  try {
    const file = process.env[RETRY_LOG_VARIABLE];
    if (file) {
      mkdirSync(dirname(file), { recursive: true });
      appendFileSync(file, `${line}\n`);
    }
  } catch {
    // Best effort: the printed line stays; only the count of ci/iris.sh misses it.
  }
}

/** The least a snapshot wait gives each of its two attempts, in ms: a bound shorter than twice this stays one wait. */
export const RETRY_MIN_ATTEMPT_MS = 10_000;

/** The first attempt of a bound split in two: half of boundMs, or undefined (no retry) when the bound is not finite or is shorter than twice RETRY_MIN_ATTEMPT_MS. */
export function firstAttemptMs(boundMs: number): number | undefined {
  return Number.isFinite(boundMs) && boundMs >= 2 * RETRY_MIN_ATTEMPT_MS ? Math.floor(boundMs / 2) : undefined;
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
 * Settles like the work, but rejects with `<step>: no answer within <bound> s` when the work has not settled by the bound: ms, or less
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
      reject(new Error(`${step}: no answer within ${secs(bound)} s${note}`));
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

/**
 * Settles like work. When work rejects with `<step>: no answer within ...` (a bound of boundedStep), it first awaits diagnose(), whose
 * failure is swallowed, and then rejects with the same error. Any other outcome is passed through without a diagnosis.
 */
export async function diagnosedAtBound<T>(work: Promise<T>, step: string, diagnose: () => Promise<unknown>): Promise<T> {
  try {
    return await work;
  } catch (error) {
    if (error instanceof Error && error.message.startsWith(`${step}: no answer within`)) {
      try {
        await diagnose();
      } catch {
        // A diagnosis never replaces the error that it describes.
      }
    }
    throw error;
  }
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
 * Runs a command with the input on its standard input and resolves with what it wrote to its standard output once it has closed. A command
 * that has not closed by its bound (ms, or none when ms is undefined, either way never later than the running test's deadline,
 * capToDeadline) is killed (SIGKILL) and the promise rejects with `<step>: no answer within <bound> s<detail>`. With no bound and no test
 * running, it waits for the command. A command that took SLOW_STEP_MS or more prints a SLOW line.
 */
export function runBounded(cmd: string, args: string[], input: string, ms: number | undefined, step: string, detail = ''): Promise<string> {
  const capped = capToDeadline(ms ?? Infinity);
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
    if (Number.isFinite(capped.ms)) {
      timer = setTimeout(() => {
        timedOut = true;
        child.kill('SIGKILL');
        child.stdout.destroy();
        reject(new Error(`${step}: no answer within ${secs(capped.ms)} s${detail}${capped.note}`));
      }, capped.ms);
    }
    child.stdin.end(input);
  });
}
