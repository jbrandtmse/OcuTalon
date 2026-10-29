/**
 * The session's message allowance as the page holds it (Story 16.9; AD-12, AD-20): a framework-free module that imports only types
 * and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - allowanceOf(condition, refusal, nowMs) is the allowance window that holds at nowMs, or undefined. Two things can tell the page
 *   that the session's allowance is used up: the store's `allowance` status condition (computed by /state and published by
 *   StatusMonitor, with the limit and the time the session can send again), and the last 429 refusal that a post of this page got
 *   (its limit and retryAt). Each counts only while its time is later than nowMs; when both do, the later time wins, with the limit of
 *   the one that gave it (the store's on a tie). Neither holding gives undefined, which is how the banner, the composer and the
 *   guide's prompts clear at the time, on the page's own clock.
 * - refusalOf(error, code) reads the body of a 429 answer of the given code (ApiRefusal) from a failed call's error, or undefined.
 * - nextChange(condition, refusal, nowMs) is the earliest time after nowMs at which allowanceOf may change, in milliseconds on the
 *   same clock, or undefined when none is ahead: the time a timer is set to.
 */
import type { ApiRefusal } from '../api/api-types';
import type { StatusPayload } from './payloads';

/** The allowance window that holds: the limit when it is known, and the UTC ISO time when the session can send again. */
export interface AllowanceWindow {
  limit: number | undefined;
  time: string;
}

/** What a 429 refusal told the page: the limit when the server gave one, and the UTC ISO time when the session can send again. */
export interface Refusal {
  limit: number | undefined;
  retryAt: string;
}

/** The time as milliseconds, or NaN when it is not a time. */
function millis(iso: unknown): number {
  return typeof iso === 'string' ? Date.parse(iso) : Number.NaN;
}

/** The limit as a count of one or more, or undefined. */
function limitOf(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) && value >= 1 ? Math.floor(value) : undefined;
}

/** The window of the store's allowance condition when it is active and its time is later than nowMs. */
function fromCondition(condition: StatusPayload | undefined, nowMs: number): AllowanceWindow | undefined {
  const time = condition?.slots?.time;
  if (condition?.active !== true || !(millis(time) > nowMs)) {
    return undefined;
  }
  return { limit: limitOf(condition.slots?.limit), time: time as string };
}

/** The window of the last refusal when its retryAt is later than nowMs. */
function fromRefusal(refusal: Refusal | undefined, nowMs: number): AllowanceWindow | undefined {
  if (refusal === undefined || !(millis(refusal.retryAt) > nowMs)) {
    return undefined;
  }
  return { limit: limitOf(refusal.limit), time: refusal.retryAt };
}

/** The allowance window that holds at nowMs: see the module doc. */
export function allowanceOf(condition: StatusPayload | undefined, refusal: Refusal | undefined, nowMs: number): AllowanceWindow | undefined {
  const stored = fromCondition(condition, nowMs);
  const refused = fromRefusal(refusal, nowMs);
  if (stored === undefined || refused === undefined) {
    return stored ?? refused;
  }
  return millis(refused.time) > millis(stored.time) ? refused : stored;
}

/** The earliest time after nowMs at which the window may end or change, in milliseconds; undefined when no time is ahead. */
export function nextChange(condition: StatusPayload | undefined, refusal: Refusal | undefined, nowMs: number): number | undefined {
  const times = [fromCondition(condition, nowMs)?.time, fromRefusal(refusal, nowMs)?.time].map(millis).filter((time) => time > nowMs);
  return times.length === 0 ? undefined : Math.min(...times);
}

/** The body of a 429 answer with this error code, from the error of a failed call (an HttpErrorResponse); undefined for any other failure. */
export function refusalOf(error: unknown, code: 'allowance' | 'email_limit'): Refusal | undefined {
  const failure = error as { status?: unknown; error?: unknown } | null;
  if (failure === null || typeof failure !== 'object' || failure.status !== 429) {
    return undefined;
  }
  const body = failure.error as Partial<ApiRefusal> | null | undefined;
  if (body === null || typeof body !== 'object' || body.error?.code !== code || !(millis(body.retryAt) >= 0)) {
    return undefined;
  }
  return { limit: limitOf(body.limit), retryAt: body.retryAt as string };
}
