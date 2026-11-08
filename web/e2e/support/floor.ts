import { expect, type Locator, type Page, type Request, type Response } from '@playwright/test';

import { signIn, signInReadme } from '../sign-in/helpers';
import { STATE } from './api';
import { WAIT_SLACK_MS, asCleanup, boundedStep, capToDeadline, diagnosedAtBound, firstAttemptMs, reportRetry, waitsFor } from './bounds';
import { PROBE_BOUND_MS, errorClass, pageSideLines, printDiagnosis, probePage, stateDiagnosis, watchRequests, type RequestWatch } from './diagnose';
import {
  cleanFixtureRows,
  fixtureUser,
  publishReminder,
  publishStatus,
  seedApproval,
  seedCheck,
  seedDecision,
  seedDecisions,
  seedIncident,
  seedTurns,
  turnRows,
} from './iris';
import { currentWaits } from './navigate';
import { tokenColor } from './page';

/**
 * What the floor specs (web/e2e/floor/) share: the floor user's page and its regions, and the one page that K5, W1 and W2 read,
 * with a row of every rail kind (each with a trace link), a done turn whose reply holds a link and whose strip
 * shows a chip and the Fallback flag, and the no-key and Reset soon banners (the stack has no model key, so the no-key banner is
 * there; Reset soon is published once the page has loaded, because a session's status events reach the page only live). Every row it
 * makes is recorded in the caller's `refs`, for cleanFixtureRows, and the condition it publishes is turned off by `clearFullPage`.
 *
 * The ring readings of Story 2.14 live here too, for K4 and the layout cases (Story 2.15): `readFocus` reads the focused element's outline,
 * halo and ring box with the viewport and every scroller around it, `expectRingInside` and `expectRing` judge it, and `seedScrollingPage`
 * seeds the page whose rail and chat list both scroll. So do the skip links' texts, the bound of a Tab walk (`MOST_STOPS`) and
 * `seedRow`, the decision row with a Trace link that K1 to K3 and the layout cases use.
 *
 * Story 2.16 adds what the three engines share: `stepKeys`, the key that steps between tab stops in the engine of a page (Tab, or
 * Option+Tab in Safari's WebKit), and the rings at tab stops: `INSIDE_RING`, the regions that draw their ring inside their own edge,
 * `expectInsideRing` for those and `expectStopRing`, which judges any stop of a walk.
 */

/** How long a card may take to reach the page after the send returns: the route, the live poll (1 to 2 s) and the render. */
export const CARD_MS = 15_000;

/** The header of a trace that no run made: a link only needs an address to open. */
export const HEADER = 4242;

/** A text no other case or run made. */
export const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** An ISO time to the second, the given number of milliseconds from now. */
export const inMs = (ms: number): string => new Date(Date.now() + ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

export const mainOf = (page: Page): Locator => page.locator('main.main');
export const railOf = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
export const composerOf = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
export const rowOf = (page: Page, marker: string): Locator => railOf(page).locator('li.row').filter({ hasText: marker });
export const replyOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="reply"][data-key="${key}"]`);
export const banner = (page: Page, id: string): Locator => page.locator(`app-banner-stack [data-banner="${id}"]`);

/** The skip links' texts, written out here as the independent oracle of the page's own. */
export const SKIP_CHAT = 'Skip to chat';
export const SKIP_DEVICES = 'Skip to simulated devices';
export const SKIP_STATUS = 'Skip to status';
export const skipLink = (page: Page, name: string): Locator => page.getByRole('link', { name, exact: true });

/** The most tab stops a walk of the page takes before it gives up. */
export const MOST_STOPS = 150;

/** The keys that step to the next and the previous tab stop. */
export interface StepKeys {
  next: string;
  back: string;
}

/** The step keys found for each engine, by the name of its browser type: a page needs the probe once per engine. */
const stepKeysOf = new Map<string, Promise<StepKeys>>();

/**
 * The keys that step between tab stops in the page's engine. They are found once per engine, in a scratch context of its own that holds a
 * link and a button: `Tab` when Tab reaches the link and then the button, else `Alt+Tab` (Option+Tab) when that does, else this throws.
 * WebKit's Tab on macOS skips links and buttons, and Option+Tab reaches them. The engine is detected, not read from its name, because
 * the Tab key of WebKit on Linux is not known to be the same.
 */
export function stepKeys(page: Page): Promise<StepKeys> {
  const browser = page.context().browser();
  if (browser === null) {
    throw new Error('stepKeys needs a page of a launched browser');
  }
  const engine = browser.browserType().name();
  let found = stepKeysOf.get(engine);
  if (found === undefined) {
    found = (async (): Promise<StepKeys> => {
      const scratch = await browser.newContext();
      try {
        const probe = await scratch.newPage();
        for (const next of ['Tab', 'Alt+Tab']) {
          await probe.setContent('<a href="#probe">link</a> <button type="button">button</button>');
          await probe.keyboard.press(next);
          const first = await probe.evaluate(() => document.activeElement?.tagName ?? '');
          await probe.keyboard.press(next);
          const second = await probe.evaluate(() => document.activeElement?.tagName ?? '');
          if (first === 'A' && second === 'BUTTON') {
            return { next, back: `Shift+${next}` };
          }
        }
      } finally {
        await scratch.close();
      }
      throw new Error(`neither Tab nor Alt+Tab reaches a link and a button in ${engine}`);
    })();
    stepKeysOf.set(engine, found);
    found.catch(() => stepKeysOf.delete(engine));
  }
  return found;
}

/**
 * The regions that a walk or a skip link reaches and that draw their ring inside their own edge (the class ring-inside of
 * styles/base.css, which a banner also carries; a banner is no stop of a walk).
 */
export const INSIDE_RING = ['section.rail', 'main.main', 'app-chat-panel .list', 'app-device-panel section', 'app-simulated-phone .feed'] as const;

/** Seeds one attention decision with a trace link, whose row is a disclosure with a Trace link beside it, and returns its summary. */
export async function seedRow(user: string, refs: string[], label: string): Promise<string> {
  const summary = unique(label);
  refs.push(await seedDecision(user, { outcome: 'act', summary, reasons: 'zz first reason.\nzz second reason.', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4242 }));
  return summary;
}

/**
 * Returns once the page has rendered what a key press changed: after two animation frames and a task. A page that handles a key
 * changes its state at once but draws it a moment later, so a case that expects a key to change nothing looks after this wait, not
 * before it.
 */
export function settled(page: Page): Promise<void> {
  return page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 0)))));
}

/**
 * The snapshot wait of loadedAfter, with at most one reload (Story 32.6, DW-550, DW-774). `asked` is the page's wait for the snapshot GET,
 * armed before the sign-in. The wait that this returns starts when begin() is called, once the sign-in has ended, and settles like `asked`
 * unless the bound whole (the snapshot bound that boundedStep computes at that moment) is at least twice RETRY_MIN_ATTEMPT_MS and `asked`
 * has not settled by half of it. Then, unless `asked` settles, the call ends or the page closes before the page-side probe is done, it prints
 * the `RETRY` line and the page-side lines, arms a new wait for a snapshot GET that the page issues from then on, reloads the page once
 * (`waitUntil: 'commit'`, so that the reloaded document's own GET of /state is the one waited for; an answer to the first document's GET is
 * not) and settles with the new wait, which has the rest of the bound (a late outcome of `asked` is then ignored). A reload that fails prints
 * `DIAG /state reload failed: <class>` and the bound decides.
 * cancel() stops a retry that has not reloaded yet. Nothing here changes the bound or the error: the outer boundedStep owns both.
 */
function withOneReload(
  page: Page,
  asked: Promise<Response>,
  answers: (response: Response) => boolean,
  actionMs: number,
  watch: RequestWatch,
  began: number,
): { wait: Promise<Response>; begin: () => void; cancel: () => void } {
  let begin: () => void = () => undefined;
  let cancelled = false;
  const started = new Promise<void>((resolve) => {
    begin = resolve;
  });
  const wait = started.then(() => {
    const whole = capToDeadline(actionMs).ms;
    const firstMs = firstAttemptMs(whole);
    if (firstMs === undefined) return asked;
    return new Promise<Response>((resolve, reject) => {
      let retried = false;
      let settled = false;
      const retry = async (): Promise<Response> => {
        if (settled || cancelled || page.isClosed()) return asked;
        const probe = await probePage(page, PROBE_BOUND_MS);
        // While the page was probed, the first GET may have been answered or have failed, the call may have ended, or the page closed.
        if (settled || cancelled || page.isClosed()) return asked;
        retried = true;
        reportRetry(`loadedAfter the snapshot GET ${STATE}`);
        printDiagnosis(pageSideLines(watch, began, probe), 'state-diagnosis');
        // Only a GET that the reloaded page issues counts: the first document's GET can still be answered before the reload commits.
        const issued = new WeakSet<Request>();
        const mark = (request: Request): void => void issued.add(request);
        page.on('request', mark);
        const second = page.waitForResponse((response) => issued.has(response.request()) && answers(response), { timeout: whole + WAIT_SLACK_MS });
        const unmark = (): void => void page.off('request', mark);
        second.then(unmark, unmark);
        await page.reload({ waitUntil: 'commit', timeout: whole + WAIT_SLACK_MS }).catch((error: unknown) => {
          printDiagnosis([`DIAG /state reload failed: ${errorClass(error instanceof Error ? error.name : undefined)}`], 'state-diagnosis');
        });
        return second;
      };
      const timer = setTimeout(() => retry().then(resolve, reject), firstMs);
      asked.then(
        (response) => {
          if (retried) return;
          settled = true;
          clearTimeout(timer);
          resolve(response);
        },
        (error: unknown) => {
          if (retried) return;
          settled = true;
          clearTimeout(timer);
          reject(error);
        },
      );
    });
  });
  return { wait, begin: () => begin(), cancel: () => void (cancelled = true) };
}

/**
 * Runs the sign-in action and waits until the page has loaded its snapshot (DW-333). The wait is on the answer: the GET of /state is armed
 * before the action and awaited with its status, and only then does the page get its time to show the snapshot, so a /state that a loaded
 * host answers late is waited for and a failed one is named. The action may be any sign-in that ends at the application's page.
 * Both steps have a bound of their own, shorter than the test's timeout (currentWaits: the navigation wait for the sign-in, the action wait
 * for the snapshot), and a step that does not end in time fails naming itself: `loadedAfter the sign-in` or
 * `loadedAfter the snapshot GET /ocutalon/api/v1/state`, with the bound.
 * DW-550 and DW-774 (D2, D4 and W3 go through it): a snapshot GET with no answer by half of its bound, when that bound is 20 s or more,
 * gets one logged retry inside the same bound (withOneReload): a `RETRY <spec>:<line> loadedAfter the snapshot GET ...` line, which ci/iris.sh
 * counts, and one reload of the page, whose own GET has the rest of the bound. A sign-in that fails, a closed page and an answer that is not
 * 200 are not retried. When the snapshot GET passes its bound, diagnose.ts prints `DIAG /state` lines (the licence units, the CSP processes
 * and the session locks, then the web gateway's servers and connections, counts and states only; then what the page did, whether its
 * renderer answers, and the worker host's load) before the same error is thrown. The same lines are appended to state-diagnosis.txt in the
 * test's output folder, attached as `state-diagnosis`, so that the failure artifact holds them (DW-756).
 */
export async function loadedAfter(page: Page, signInAction: () => Promise<unknown>): Promise<void> {
  const began = Date.now();
  const watch = watchRequests(page);
  const waits = currentWaits() ?? { action: waitsFor(0).actionTimeout, navigation: waitsFor(0).navigationTimeout };
  const answers = (response: Response): boolean => response.request().method() === 'GET' && new URL(response.url()).pathname === STATE;
  const asked = page.waitForResponse(answers, { timeout: waits.navigation + waits.action + WAIT_SLACK_MS });
  // The wait is awaited below; a sign-in that fails first must not leave its timeout unhandled.
  asked.catch(() => undefined);
  const retrying = withOneReload(page, asked, answers, waits.action, watch, began);
  const state = retrying.wait;
  try {
    await boundedStep(signInAction(), waits.navigation, 'loadedAfter the sign-in');
    retrying.begin();
    const answered = await diagnosedAtBound(boundedStep(state, waits.action, `loadedAfter the snapshot GET ${STATE}`), `loadedAfter the snapshot GET ${STATE}`, async () => {
      // A GET that passed its bound: read what could hold it (diagnose.ts) while it still waits, then fail as before.
      const [, probe] = await Promise.all([stateDiagnosis(), asCleanup(() => probePage(page, PROBE_BOUND_MS))]);
      printDiagnosis(pageSideLines(watch, began, probe), 'state-diagnosis');
    });
    expect(answered.status(), 'the snapshot is served').toBe(200);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  } finally {
    retrying.cancel();
    watch.stop();
  }
}

/** Signs the README account in (signInReadme) and waits until the page has loaded its snapshot (loadedAfter, DW-333). */
export async function signInReadmeLoaded(page: Page): Promise<void> {
  await loadedAfter(page, () => signInReadme(page));
}

/** Signs the floor user in and waits for the loaded page with its composer. */
export async function openFloor(page: Page): Promise<void> {
  const { user, password } = fixtureUser('FLOOR');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(composerOf(page)).toBeVisible();
}

/** Waits until the page has applied the event of this Seq on the session's stream. */
export async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-session-seq')), { message: `the page applied Seq ${seq}`, timeout: CARD_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** What seedFullPage made: the marker of its texts, and the reply's key. */
export interface FullPage {
  stamp: string;
  /** The Ref of the done turn; its reply is `replyOf(page, turn)`. */
  turn: string;
  /** The summary of the rail's decision row. */
  summary: string;
  /** The Ref of the approval request, whose rail row carries no text of the case: its row is `li.row[data-row-key="approvals:<ref>"]`. */
  approval: string;
}

/**
 * Seeds the rows of the full page into the user's own session, before the page loads: a check with its latest run's trace, an approval
 * request of an incident with a trace, a decision with a trace session, a done turn whose reply holds a markdown link and whose strip
 * shows Tell now and the Fallback flag. The turn has a reply decision only: a turn's attention decision would stay in the rail's
 * Recent decisions. The turn and its decision are recorded in `refs` too. The reminder, which only an event can give a trace target, and Reset soon come with
 * `addReminder` and `addResetSoon` once the page has loaded.
 */
export async function seedFullPage(user: string, refs: string[]): Promise<FullPage> {
  const stamp = unique('full').replace(/ /g, '-');
  refs.push(await seedCheck(user, { namespace: 'OCUTALON', production: `Zz.Floor.${stamp.slice(-8)}`, displayName: `zz check ${stamp}`, lastRunAt: inMs(-60_000), result: 'passed', finding: 'zz finding', lastRunHeaderId: HEADER }));
  const incident = await seedIncident(user, { traceHeaderId: HEADER });
  refs.push(incident);
  const approval = await seedApproval(user, { incidentRef: incident, dryRun: { affected: 3, itemNoun: { one: 'order', other: 'orders' } } });
  refs.push(approval);
  const summary = `zz decision ${stamp}`;
  refs.push(await seedDecision(user, { outcome: 'act', summary, reasons: 'zz first reason.\nzz second reason.', confidence: 0.9, costUSD: 0.0003, traceSessionId: 4242 }));
  const seeded = await seedTurns(user, [
    {
      createdAt: '2019-02-01T10:00:00Z',
      text: `zz question ${stamp}`,
      replyText: 'zz See [the guide](https://example.com/guide) here. Second sentence.',
      turn: { outcome: 'tellnow', fallback: true, fallbackReason: 'empty', reasons: 'Fixed rules chose this.', confidence: 0.5, costUSD: 0.0003 },
    },
  ]);
  refs.push(...turnRows(seeded));
  return { stamp, turn: seeded.refs[0]!, summary, approval };
}

/** Publishes a pending reminder with a trace target, once the page has loaded, and waits until the page shows its row. Returns its text. */
export async function addReminder(page: Page, user: string, stamp: string): Promise<string> {
  const text = `zz reminder ${stamp}`;
  await applied(page, await publishReminder(user, { ref: `ZzFloor${stamp.replace(/[^A-Za-z0-9]/g, '')}`, text, dueAt: inMs(3_600_000), traceHeaderId: HEADER, traceNamespace: 'OCUTALON' }));
  await expect(rowOf(page, text).locator('app-trace-link a'), 'the reminder row carries a trace link').toHaveCount(1, { timeout: CARD_MS });
  return text;
}

/** Publishes Reset soon, once the page has loaded, and waits until the page shows its banner. */
export async function addResetSoon(page: Page, user: string): Promise<void> {
  await applied(page, await publishStatus(user, { condition: 'resetSoon', active: true }));
  await expect(banner(page, 'resetSoon'), 'Reset soon shows').toHaveCount(1, { timeout: CARD_MS });
}

/** Turns Reset soon off and removes the rows of the full page. */
export async function clearFullPage(user: string, refs: string[]): Promise<void> {
  await publishStatus(user, { condition: 'resetSoon', active: false });
  await cleanFixtureRows(refs);
}

/** A box in the viewport's coordinates. */
export interface Box {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** What the focused element draws, and the boxes around it. */
export interface Reading {
  what: string;
  outlineStyle: string;
  outlineWidth: string;
  outlineColor: string;
  outlineOffset: string;
  boxShadow: string;
  clipPath: string;
  /** The border box grown by what the outline reaches beyond it: the offset plus the width, when that is positive. */
  ring: Box;
  viewport: Box;
  /** The client boxes of the ancestors that clip what lies outside them. */
  scrollers: Array<Box & { what: string }>;
  /** Whether the focused element is one of INSIDE_RING. */
  inside: boolean;
}

/** Reads the focused element: its outline and halo, its ring box, the viewport and the client box of every ancestor that clips. */
export function readFocus(page: Page): Promise<Reading | null> {
  return page.evaluate((insideSelector) => {
    const el = document.activeElement;
    if (!(el instanceof HTMLElement) || el === document.body) return null;
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    const grow = Math.max(0, parseFloat(style.outlineOffset) + parseFloat(style.outlineWidth));
    const scrollers: Array<Box & { what: string }> = [];
    for (let parent = el.parentElement; parent !== null; parent = parent.parentElement) {
      const own = getComputedStyle(parent);
      if (own.overflowX === 'visible' && own.overflowY === 'visible') continue;
      const box = parent.getBoundingClientRect();
      scrollers.push({
        what: `${parent.tagName.toLowerCase()}${parent.className ? `.${String(parent.className).split(' ')[0]}` : ''}`,
        left: box.left + parent.clientLeft,
        top: box.top + parent.clientTop,
        right: box.left + parent.clientLeft + parent.clientWidth,
        bottom: box.top + parent.clientTop + parent.clientHeight,
      });
    }
    const name = el.getAttribute('aria-label') ?? (el.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 40);
    return {
      what: `${el.tagName.toLowerCase()}${el.id ? `#${el.id}` : ''} "${name}"`,
      outlineStyle: style.outlineStyle,
      outlineWidth: style.outlineWidth,
      outlineColor: style.outlineColor,
      outlineOffset: style.outlineOffset,
      boxShadow: style.boxShadow,
      clipPath: style.clipPath,
      ring: { left: rect.left - grow, top: rect.top - grow, right: rect.right + grow, bottom: rect.bottom + grow },
      viewport: { left: 0, top: 0, right: window.innerWidth, bottom: window.innerHeight },
      scrollers,
      inside: el.matches(insideSelector),
    };
  }, INSIDE_RING.join(','));
}

/** True when the inner box lies inside the outer one, within half a pixel. */
const inside = (inner: Box, outer: Box): boolean =>
  inner.left >= outer.left - 0.5 && inner.top >= outer.top - 0.5 && inner.right <= outer.right + 0.5 && inner.bottom <= outer.bottom + 0.5;

/** Expects the ring to lie inside the viewport and inside every ancestor that clips. */
export function expectRingInside(reading: Reading, what: string): void {
  const ring = JSON.stringify(reading.ring);
  expect(inside(reading.ring, reading.viewport), `${what}: the ring ${ring} lies inside the viewport ${JSON.stringify(reading.viewport)}`).toBe(true);
  for (const scroller of reading.scrollers) {
    expect(inside(reading.ring, scroller), `${what}: the ring ${ring} lies inside ${scroller.what} ${JSON.stringify(scroller)}`).toBe(true);
  }
}

/** Expects the focused element to draw the page's ring: 2px solid in the focus colour, with the surface halo. */
export async function expectRing(page: Page, reading: Reading, what: string): Promise<void> {
  const focus = await tokenColor(page, '--focus');
  const surface = await tokenColor(page, '--surface');
  expect(reading.outlineStyle, `${what}: the ring is solid`).toBe('solid');
  expect(reading.outlineWidth, `${what}: 2px`).toBe('2px');
  expect(reading.outlineColor, `${what}: in the focus colour`).toBe(focus);
  expect(reading.boxShadow, `${what}: with the surface halo`).toContain(`${surface} 0px 0px 0px 2px`);
}

/** Expects a focus target that draws its ring inside its own edge: 2px solid in the focus colour, with the surface halo inside it. */
export async function expectInsideRing(page: Page, reading: Reading, what: string): Promise<void> {
  const focus = await tokenColor(page, '--focus');
  const surface = await tokenColor(page, '--surface');
  expect(reading.outlineStyle, `${what}: the ring is solid`).toBe('solid');
  expect(reading.outlineWidth, `${what}: 2px`).toBe('2px');
  expect(reading.outlineColor, `${what}: in the focus colour`).toBe(focus);
  expect(reading.outlineOffset, `${what}: inside its own edge`).toBe('-2px');
  expect(reading.boxShadow, `${what}: with the surface halo inside the ring`).toContain(`${surface} 0px 0px 0px 4px inset`);
  expectRingInside(reading, what);
}

/**
 * Judges the ring at one stop of a walk: the regions of INSIDE_RING draw it inside their own edge (expectInsideRing), and every other
 * stop draws the page's ring and keeps it inside the viewport and every scroller.
 */
export async function expectStopRing(page: Page, reading: Reading): Promise<void> {
  if (reading.inside) {
    await expectInsideRing(page, reading, reading.what);
    return;
  }
  await expectRing(page, reading, reading.what);
  expectRingInside(reading, reading.what);
}

/**
 * Seeds the page whose rail and chat list both scroll at 1280x720: twelve decision rows, each with a Trace link, and eight done turns.
 * Every row it makes is recorded in the caller's `refs`, for cleanFixtureRows. Call it before the page loads.
 */
export async function seedScrollingPage(user: string, refs: string[], stamp: string): Promise<void> {
  const rows = Array.from({ length: 12 }, (_unused, n) => ({
    outcome: 'act',
    summary: `${stamp} decision ${String(n).padStart(2, '0')}`,
    reasons: 'zz first reason.\nzz second reason.',
    confidence: 0.9,
    costUSD: 0.0003,
    traceSessionId: 4242,
    recordedAt: inMs(-(n + 1) * 60_000),
  }));
  refs.push(...(await seedDecisions(user, rows)));
  const turns = await seedTurns(
    user,
    Array.from({ length: 8 }, (_unused, n) => ({
      createdAt: `2019-03-0${n + 1}T10:00:00Z`,
      text: `${stamp} question ${n}`,
      replyText: `${stamp} reply ${n}. Second sentence.`,
      turn: { outcome: 'act', reasons: 'zz first reason.\nzz second reason.', confidence: 0.9, costUSD: 0.0003 },
    })),
  );
  refs.push(...turnRows(turns));
}
