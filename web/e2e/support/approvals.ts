import { expect, type Locator, type Page } from '@playwright/test';

import { phoneMessage } from './devices';
import { applied, CARD_MS, HEADER } from './floor';
import { publishIncident, seedApproval, sendNotification, sinkEvent } from './iris';

/**
 * What the answers unit's specs (e2e/answers/, Stories 6.3 and 6.4) share to raise an incident and its approval
 * request on fixtures: the incident as IncidentManager publishes
 * it (an `incident` event), and a pending request whose `approval` event reaches the page through BridgeSink. incidentOf and raise are
 * the shared home of the two for those specs (cards/approval-card.spec.ts keeps its own copies). noticeSlots and noticeOnPhone put
 * the incident notice of a request on the simulated phone, and phoneOf and messageOf find the phone and a message of it; the
 * answers specs and the rail's answer spec (rail/rail-answer.spec.ts) share them. A request of the payload is `{ref, state?, result?}`: pending with
 * no result unless given, so that a case can publish the same incident again with a request answered, executing or finished (Story 6.4).
 */

/** The run's date (UTC), taken once, so that every time of a spec is on the same date. */
const DAY = new Date().toISOString().slice(0, 10);

/** The run's date with the time given, as a UTC ISO time. */
export const today = (time: string): string => `${DAY}T${time}Z`;

/** The day after the run's, at 14:13 UTC: the expiry of a request, which the card reads as "tomorrow at 14:13". */
export const TOMORROW_AT_1413 = new Date(Date.parse(today('14:13:00')) + 86_400_000).toISOString().replace(/\.\d{3}Z$/, 'Z');

/** A ref of this case's own: at most 22 characters, letters and digits. */
export const refOf = (label: string): string => `zz${label}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

/** The dry run of the matrix's first row: 50 orders, OrderDate 10/16/2026 to 2026-10-16. */
export const DRY_RUN = { affected: 50, itemNoun: { one: 'order', other: 'orders' }, field: 'OrderDate', before: '10/16/2026', after: '2026-10-16' } as const;

/** A request of an incident payload: its state (pending unless given) and its result, when it has one. */
export interface RequestFields {
  ref: string;
  state?: string;
  result?: Record<string, unknown>;
}

/** The incident payload of a card that is awaiting approval, with the parts of its evidence panel; `over` changes fields of the payload. */
export function incidentOf(ref: string, requests: ReadonlyArray<RequestFields>, over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ref,
    state: 'awaiting_approval',
    count: 50,
    noticeCount: 50,
    firstAt: today('14:12:00'),
    lastAt: today('14:13:00'),
    itemNoun: { one: 'order', other: 'orders' },
    cause: 'The partner changed its date format.',
    fixSummary: 'repair and resend all 50',
    causeCategory: 'data_format_change',
    element: 'order date',
    requests: requests.map((one) => ({ ref: one.ref, state: one.state ?? 'pending', ...(one.result === undefined ? {} : { result: one.result }) })),
    evidence: {
      sampleHeaderId: 1047,
      sampleError: 'zz Could not parse OrderDate',
      items: [{ itemName: 'Order transform', count: 50, firstAt: today('14:12:03'), lastAt: today('14:12:31') }],
    },
    traceTargets: { diagnosis: { traceHeaderId: HEADER, traceNamespace: 'OCUTALON' } },
    ...over,
  };
}

/**
 * Seeds a request of the incident (pending, required role OcuTalonUser, raised today at 14:13 and expiring tomorrow at 14:13, unless
 * `over` gives other fields), publishes the incident with all the requests named so far (unless `publish` is false, for a case that
 * publishes the incident's view itself) and the request's `approval` event, and waits until the page, which must be open and loaded,
 * applied each. The request's Ref is added to `rows` (for cleanFixtureRows) and to `requests`, and returned.
 */
export async function raise(page: Page, user: string, rows: string[], incident: string, requests: string[], over: Record<string, unknown> = {}, publish = true): Promise<string> {
  const request = await seedApproval(user, {
    incidentRef: incident,
    requiredRole: 'OcuTalonUser',
    expiresAt: TOMORROW_AT_1413,
    raisedAt: today('14:13:00'),
    dryRun: DRY_RUN,
    ...over,
  });
  rows.push(request);
  requests.push(request);
  if (publish) await applied(page, await publishIncident(user, incidentOf(incident, requests.map((one) => ({ ref: one })))));
  await applied(page, await sinkEvent(user, 'approval.raised', { ref: request }));
  return request;
}

/** The simulated phone, and the message of a Ref on it. */
export const phoneOf = (page: Page): Locator => page.locator('app-simulated-phone');
export const messageOf = (page: Page, ref: string): Locator => phoneOf(page).locator(`.notification[data-key="${ref}"]`);

/** The slots of an incident.withFix / incident.laterRequest notice for the fixture request: 50 orders since two minutes ago. */
export function noticeSlots(since: string): Record<string, unknown> {
  return {
    count: 50,
    itemNoun: { one: 'order', other: 'orders' },
    time: since,
    cause: 'Data format change',
    fixSummary: 'repair the order date and resend 50 orders',
    field: 'OrderDate',
    before: '10/16/2026',
    after: '2026-10-16',
    resendCount: 50,
  };
}

/**
 * Sends the incident notice of a request through Notify, as IncidentManager will (kind incident, or approval for a later request),
 * and returns the phone message that asks for it once the page shows it (phoneShows). `since` is the time the notice names.
 */
export async function noticeOnPhone(page: Page, user: string, request: string, incident: string, since: string, kind: 'incident' | 'approval' = 'incident'): Promise<{ ref: string; message: Locator }> {
  await sendNotification(user, {
    kind,
    catalogKey: kind === 'incident' ? 'incident.withFix' : 'incident.laterRequest',
    slots: noticeSlots(since),
    approvalRef: request,
    incidentRef: incident,
  });
  return phoneShows(page, user, request);
}

/** Waits until the phone message that asks for the request exists and the simulated phone shows it; returns its Ref and locator. */
export async function phoneShows(page: Page, user: string, request: string): Promise<{ ref: string; message: Locator }> {
  let ref = '';
  await expect
    .poll(async () => (ref = (await phoneMessage(user, request))?.ref ?? ''), { message: 'the phone message of the request exists', timeout: CARD_MS })
    .not.toBe('');
  const message = messageOf(page, ref);
  await expect(message, 'and the phone shows it').toHaveCount(1, { timeout: CARD_MS });
  return { ref, message };
}
