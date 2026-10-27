import type { Page } from '@playwright/test';

import { applied, HEADER } from './floor';
import { publishIncident, seedApproval, sinkEvent } from './iris';

/**
 * What the answers unit (e2e/answers/, Story 6.3) and the demo path's steps 4 and 5 share to raise an incident and its approval
 * request on fixtures, as Lane A's raise path will until Epic 11 turns it on end to end: the incident as IncidentManager will publish
 * it (an `incident` event), and a pending request whose `approval` event reaches the page through BridgeSink. incidentOf and raise
 * are the floor spec's (floor/approval.spec.ts), which stays as it is; this module is the shared home of the two for the new specs.
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

/** The incident payload of a card that is awaiting approval, with the parts of its evidence panel. */
export function incidentOf(ref: string, requests: string[]): Record<string, unknown> {
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
    requests: requests.map((one) => ({ ref: one, state: 'pending' })),
    evidence: {
      sampleHeaderId: 1047,
      sampleError: 'zz Could not parse OrderDate',
      items: [{ itemName: 'Order transform', count: 50, firstAt: today('14:12:03'), lastAt: today('14:12:31') }],
    },
    traceTargets: { diagnosis: { traceHeaderId: HEADER, traceNamespace: 'OCUTALON' } },
  };
}

/**
 * Seeds a pending request of the incident (required role OcuTalonUser, expiring tomorrow at 14:13), publishes the incident with all
 * the requests named so far and the request's `approval` event, and waits until the page, which must be open and loaded, applied both.
 * The request's Ref is added to `rows` (for cleanFixtureRows) and to `requests`, and returned.
 */
export async function raise(page: Page, user: string, rows: string[], incident: string, requests: string[], over: Record<string, unknown> = {}): Promise<string> {
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
  await applied(page, await publishIncident(user, incidentOf(incident, requests)));
  await applied(page, await sinkEvent(user, 'approval.raised', { ref: request }));
  return request;
}
