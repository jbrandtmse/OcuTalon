import { expect, test, type APIRequestContext, type APIResponse } from '../support/fixtures';

import { expectError, signInOverHttp } from '../sign-in/helpers';
import { cleanFixtureRows, fixtureUser, seedIncident } from '../support/iris';
import { localDate, seedHistoryDecisions, type HistoryDecisionSeed } from '../support/history';
import { sessionRefOfUser } from '../support/memory';

/**
 * Story 25.2, GET /api/v1/history/decisions and /incidents over real HTTP, on the stack that test-sign-in.sh seeds. Signed out both routes are 401 signed_out with
 * no challenge. As the LIVE fixture user (role OcuTalonUser only, the online demo visitors' role) both are 200: the decisions of the user's own session, each
 * filter alone and two combined, newest first, 25 to a page (a second page of 26 rows), a page past the last a 200 with an empty list, and the incidents the
 * session sees with the stored summary as text. A key allow-list proves the bodies: the top levels and every item hold only their keys, so that no row id, owner,
 * session Ref, user name, ItemId or trace header id appears. Every bad value of a known parameter is 404 not_found. A second session (the PANEL fixture user,
 * also OcuTalonUser only, so another durable session) with rows of its own never sees the first session's, and an eval row, an instance row, an un-noticed incident
 * and an incident of the other session appear in neither response. The only 403 is no_role, which a second case pins for the trace-only fixture user. Each case
 * reads its own rows by a local day that no other case uses (40 to 42 days ago), so other rows change nothing; the rows are removed in `finally`.
 */
const DECISIONS = '/ocutalon/api/v1/history/decisions';
const INCIDENTS = '/ocutalon/api/v1/history/incidents';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const DECISION_KEYS = ['channel', 'confidence', 'costUSD', 'fallback', 'fallbackReason', 'itemSummary', 'outcome', 'reasons', 'recordedAt', 'ref', 'traceUrl'];
const INCIDENT_KEYS = ['closedAt', 'count', 'fallback', 'firstAt', 'itemNoun', 'noticedAt', 'ref', 'state', 'summary', 'traceUrl'];

interface Decision {
  ref: string;
  outcome: string;
  reasons: string;
  fallback: boolean;
  fallbackReason: string;
  itemSummary: string;
  recordedAt: string;
  channel: string;
  traceUrl?: string;
  confidence?: number;
  costUSD?: number;
}
interface Incident {
  ref: string;
  state: string;
  fallback: boolean;
  count: number;
  itemNoun?: { one: string; other: string };
  firstAt: string;
  noticedAt: string;
  closedAt: string;
  summary: string;
  traceUrl?: string;
}
interface Page<T> {
  page: number;
  pages: number;
  items: T[];
}

/** The 200 body of a read, with the key allow-list checked: the top level and every item hold only their keys. */
async function read<T>(response: APIResponse, list: 'decisions' | 'incidents'): Promise<Page<T>> {
  expect(response.status(), await response.text()).toBe(200);
  expect(response.headers()['content-type']).toContain('application/json');
  const body = (await response.json()) as Record<string, unknown>;
  expect(Object.keys(body).sort(), `the top level holds exactly page, pages and ${list}`).toEqual(['page', 'pages', list].sort());
  const items = body[list] as Array<Record<string, unknown>>;
  const allowed = list === 'decisions' ? DECISION_KEYS : INCIDENT_KEYS;
  for (const item of items) {
    for (const key of Object.keys(item)) expect(allowed, `${list} item key ${key} is in the allow-list`).toContain(key);
  }
  return { page: body['page'] as number, pages: body['pages'] as number, items: items as T[] };
}

/** The decisions of a query, as their summaries, newest first. */
async function summaries(request: APIRequestContext, query: string): Promise<string[]> {
  const body = await read<Decision>(await request.get(`${DECISIONS}?${query}`), 'decisions');
  return body.items.map((one) => one.itemSummary);
}

/** The incidents of every page of the route. */
async function allIncidents(request: APIRequestContext): Promise<Incident[]> {
  const first = await read<Incident>(await request.get(INCIDENTS), 'incidents');
  const all = [...first.items];
  for (let page = 2; page <= first.pages; page += 1) all.push(...(await read<Incident>(await request.get(`${INCIDENTS}?page=${page}`), 'incidents')).items);
  return all;
}

test('the history routes: signed out, the filters, paging, the key allow-list, the bad values, and a second session sees none of it', async ({ request, playwright, baseURL }) => {
  test.setTimeout(240_000);
  const live = fixtureUser('LIVE');
  const other = fixtureUser('PANEL');
  const tag = `zz-h-${Date.now().toString(36)}`;
  const refs: string[] = [];
  const second = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  try {
    // (1) signed out: 401 signed_out, with no challenge.
    for (const url of [DECISIONS, `${DECISIONS}?outcome=act`, INCIDENTS, `${INCIDENTS}?page=2`, `${DECISIONS}?outcome=foo`]) {
      const response = await anonymous.get(url);
      await expectError(response, 401, 'signed_out', SIGNED_OUT);
      expect(response.headers()['www-authenticate'], `${url} sends no challenge`).toBeUndefined();
    }

    // (2) the LIVE user, each filter alone and two together, on the days 40 and 41 days ago.
    await signInOverHttp(request, live.user, live.password);
    const liveSession = await sessionRefOfUser(live.user);
    const [d40, d41, d42] = [await localDate(40), await localDate(41), await localDate(42)];
    const at = (n: number, time: string): HistoryDecisionSeed => ({ outcome: 'ignore', summary: '', daysAgo: n, time });
    const rows: HistoryDecisionSeed[] = [
      { ...at(40, '09:00:00'), outcome: 'ignore', summary: `${tag} A1`, channel: 'web', reasons: 'Noise.', confidence: 0.91, costUSD: 0.001 },
      { ...at(40, '10:00:00'), outcome: 'digest', summary: `${tag} A2`, channel: 'mailbox' },
      { ...at(40, '11:00:00'), outcome: 'tellnow', summary: `${tag} A3`, channel: 'phone' },
      { ...at(40, '12:00:00'), outcome: 'act', summary: `${tag} A4`, channel: 'mailbox' },
      { ...at(40, '13:00:00'), outcome: 'digest', summary: `${tag} A5`, fallback: true, fallbackReason: 'no_key' },
      { ...at(41, '09:00:00'), outcome: 'act', summary: `${tag} B1`, channel: 'web' },
    ];
    const seeded = await seedHistoryDecisions({ sessionRef: liveSession }, rows);
    refs.push(...seeded.map((one) => one.ref));
    expect(seeded.map((one) => one.date), 'the rows are on the two local days').toEqual([d40, d40, d40, d40, d40, d41]);
    const on40 = `day=${d40}`;
    const only = (names: string[]): string[] => names.map((name) => `${tag} ${name}`);

    expect(await summaries(request, on40), 'a day: newest first').toEqual(only(['A5', 'A4', 'A3', 'A2', 'A1']));
    expect(await summaries(request, `day=${d41}`), 'another day').toEqual(only(['B1']));
    expect(await summaries(request, `${on40}&outcome=ignore`)).toEqual(only(['A1']));
    expect(await summaries(request, `${on40}&outcome=digest`), 'outcome digest leaves out the fallback decision').toEqual(only(['A2']));
    expect(await summaries(request, `${on40}&outcome=tellnow`), 'outcome tellnow matches every fallback decision too, as the chip shows it').toEqual(only(['A5', 'A3']));
    expect(await summaries(request, `${on40}&outcome=act`)).toEqual(only(['A4']));
    expect(await summaries(request, `${on40}&fallback=yes`)).toEqual(only(['A5']));
    expect(await summaries(request, `${on40}&fallback=no`)).toEqual(only(['A4', 'A3', 'A2', 'A1']));
    expect(await summaries(request, `${on40}&channel=mailbox`), 'a channel is that of the decision\'s usage rows').toEqual(only(['A4', 'A2']));
    expect(await summaries(request, `${on40}&channel=web`)).toEqual(only(['A1']));
    expect(await summaries(request, `${on40}&channel=heartbeat`), 'a channel with no row').toEqual([]);
    expect(await summaries(request, `${on40}&outcome=act&channel=mailbox`), 'two filters').toEqual(only(['A4']));
    expect(await summaries(request, `day=${d41}&outcome=act&channel=web&fallback=no`), 'four filters').toEqual(only(['B1']));
    expect(await summaries(request, `${on40}&outcome=act&channel=web`), 'no match is an empty list, not an error').toEqual([]);
    expect(await summaries(request, `${on40}&foo=bar&page=1`), 'an unknown parameter is ignored').toEqual(only(['A5', 'A4', 'A3', 'A2', 'A1']));

    // The shape: the full item, the item with no usage row and the allow-list.
    const full = await read<Decision>(await request.get(`${DECISIONS}?${on40}&channel=web`), 'decisions');
    expect(full.page, 'page').toBe(1);
    expect(full.pages, 'pages').toBe(1);
    const a1 = full.items[0]!;
    expect(Object.keys(a1).sort(), 'a full decision holds exactly the eleven keys').toEqual(DECISION_KEYS);
    expect({ ref: a1.ref, outcome: a1.outcome, reasons: a1.reasons, fallback: a1.fallback, channel: a1.channel, confidence: a1.confidence, costUSD: a1.costUSD }).toEqual({
      ref: seeded[0]!.ref,
      outcome: 'ignore',
      reasons: 'Noise.',
      fallback: false,
      channel: 'web',
      confidence: 0.91,
      costUSD: 0.001,
    });
    expect(a1.traceUrl, 'the trace link is the one TraceLink builds').toContain('SESSIONID=42');
    const a5 = (await read<Decision>(await request.get(`${DECISIONS}?${on40}&fallback=yes`), 'decisions')).items[0]!;
    expect(a5.channel, 'a decision no model call served has the channel ""').toBe('');
    expect(a5.fallback, 'its fallback').toBe(true);
    expect(a5.fallbackReason).toBe('no_key');
    expect(Object.keys(a5).sort(), 'and no confidence and no cost').toEqual(DECISION_KEYS.filter((key) => key !== 'confidence' && key !== 'costUSD'));

    // Paging: 26 rows of one day and channel are two pages; a page past the last is 200 and empty.
    const many = await seedHistoryDecisions(
      { sessionRef: liveSession },
      Array.from({ length: 26 }, (_one, index) => ({ outcome: 'act', summary: `${tag} P${String(index + 1).padStart(2, '0')}`, channel: 'slack', daysAgo: 42, time: `08:${String(index).padStart(2, '0')}:00` })),
    );
    refs.push(...many.map((one) => one.ref));
    const filter = `day=${d42}&channel=slack&outcome=act`;
    const page1 = await read<Decision>(await request.get(`${DECISIONS}?${filter}`), 'decisions');
    expect(page1.items, 'page 1 holds 25').toHaveLength(25);
    expect(page1.pages, 'two pages').toBe(2);
    expect(page1.items[0]!.itemSummary, 'newest first').toBe(`${tag} P26`);
    expect(page1.items[24]!.itemSummary).toBe(`${tag} P02`);
    const page2 = await read<Decision>(await request.get(`${DECISIONS}?${filter}&page=2`), 'decisions');
    expect(page2.page, 'page 2').toBe(2);
    expect(page2.items.map((one) => one.itemSummary), 'page 2 holds the oldest').toEqual([`${tag} P01`]);
    for (const page of [3, 9999]) {
      const response = await request.get(`${DECISIONS}?${filter}&page=${page}`);
      expect(response.status(), `page ${page} is not an error`).toBe(200);
      expect(await response.json(), `page ${page}: an empty list and the page count`).toEqual({ page, pages: 2, decisions: [] });
    }

    // The bad values are 404 not_found, whatever they are on.
    const bad = [
      'outcome=foo', 'outcome=', 'outcome=Act', 'channel=x', 'channel=', 'fallback=1', 'fallback=', 'fallback=Yes', 'day=2026-13-01', 'day=2026-02-30', 'day=11/10/2026', 'day=',
      'page=0', 'page=01', 'page=abc', 'page=10000', 'page=', 'page=-1', 'page=1.5', 'outcome=act&outcome=ignore', 'page=1&page=2',
    ];
    for (const query of bad) await expectError(await request.get(`${DECISIONS}?${query}`), 404, 'not_found', NOT_FOUND);
    for (const query of ['page=0', 'page=01', 'page=abc', 'page=10000', 'page=', 'page=-1']) await expectError(await request.get(`${INCIDENTS}?${query}`), 404, 'not_found', NOT_FOUND);
    for (const path of ['/ocutalon/api/v1/history', '/ocutalon/api/v1/history/other', '/ocutalon/api/v1/historyx/decisions']) {
      await expectError(await request.get(path), 404, 'not_found', NOT_FOUND);
    }

    // (3) the incidents: a closed one with a stored summary, an open one, an un-noticed one, and the other owners' rows.
    const summary = JSON.stringify({ parts: [{ key: 'summary.noFixRan', slots: {} }], lines: [] });
    const closed = await seedIncident({ sessionRef: liveSession }, {
      state: 'closed', summary, traceHeaderId: 77, count: 4, itemNoun: { one: 'order', other: 'orders' }, firstAt: '2030-01-01T09:00:00Z', noticedAt: '2030-01-01T09:30:00Z', closedAt: '2030-01-01T11:00:00Z',
    });
    const open = await seedIncident({ sessionRef: liveSession }, { state: 'open', noticedAt: '2030-01-01T09:45:00Z' });
    const unnoticed = await seedIncident({ sessionRef: liveSession }, { noticedAt: '' });
    refs.push(closed, open, unnoticed);
    const incidents = await allIncidents(request);
    const mine = incidents.filter((one) => [closed, open, unnoticed].includes(one.ref));
    expect(mine.map((one) => one.ref).sort(), 'the noticed incidents, and not the one that was not noticed').toEqual([closed, open].sort());
    const closedRow = mine.find((one) => one.ref === closed)!;
    expect(Object.keys(closedRow).sort(), 'a closed incident with a summary holds exactly the ten keys').toEqual(INCIDENT_KEYS);
    expect(closedRow).toMatchObject({ state: 'closed', fallback: false, count: 4, itemNoun: { one: 'order', other: 'orders' }, firstAt: '2030-01-01T09:00:00Z', noticedAt: '2030-01-01T09:30:00Z', closedAt: '2030-01-01T11:00:00Z' });
    expect(closedRow.summary, 'the stored summary as text').toBe('No fix ran, so nothing was changed.');
    expect(closedRow.traceUrl, 'the diagnosis session\'s trace link').toContain('SESSIONID=77');
    const openRow = mine.find((one) => one.ref === open)!;
    expect(openRow.closedAt, 'closedAt is "" while open').toBe('');
    expect(openRow.summary, 'and so is the summary of an incident that has none').toBe('');
    expect(mine.map((one) => one.ref).indexOf(open), 'newest noticed first').toBeLessThan(mine.map((one) => one.ref).indexOf(closed));

    // (4) a second session with its own rows, and the eval and instance rows, appear in neither response.
    await signInOverHttp(second, other.user, other.password);
    const otherSession = await sessionRefOfUser(other.user);
    expect(otherSession, 'the second account is another session').not.toBe(liveSession);
    const theirs = await seedHistoryDecisions({ sessionRef: otherSession }, [{ outcome: 'act', summary: `${tag} P-theirs`, channel: 'web', daysAgo: 40, time: '14:00:00' }]);
    const evals = await seedHistoryDecisions('eval', [{ outcome: 'act', summary: `${tag} E-eval`, channel: 'web', daysAgo: 40, time: '15:00:00' }]);
    const instances = await seedHistoryDecisions('instance', [{ outcome: 'act', summary: `${tag} I-instance`, channel: 'web', daysAgo: 40, time: '16:00:00' }]);
    refs.push(...theirs.map((one) => one.ref), ...evals.map((one) => one.ref), ...instances.map((one) => one.ref));
    const theirIncident = await seedIncident({ sessionRef: otherSession }, { noticedAt: '2030-01-02T09:00:00Z' });
    const evalIncident = await seedIncident('eval', { noticedAt: '2030-01-02T09:00:00Z' });
    const instanceIncident = await seedIncident('instance', { noticedAt: '2030-01-02T09:00:00Z', namespace: 'ZZNS', production: `Zz.History.${tag}` });
    refs.push(theirIncident, evalIncident, instanceIncident);

    expect(await summaries(request, on40), 'the LIVE session sees none of the other rows').toEqual(only(['A5', 'A4', 'A3', 'A2', 'A1']));
    expect(await summaries(second, on40), 'the second session sees its own row only').toEqual(only(['P-theirs']));
    expect(await summaries(second, `${on40}&outcome=act&channel=web&fallback=no`), 'with filters too').toEqual(only(['P-theirs']));
    expect(await summaries(second, `day=${d42}&channel=slack`), 'and none of the first session\'s 26').toEqual([]);
    const liveIncidents = (await allIncidents(request)).map((one) => one.ref);
    const theirIncidents = (await allIncidents(second)).map((one) => one.ref);
    expect(liveIncidents, 'the LIVE session sees its own incidents').toEqual(expect.arrayContaining([closed, open]));
    for (const ref of [theirIncident, evalIncident, instanceIncident, unnoticed]) expect(liveIncidents, `the LIVE session does not list ${ref}`).not.toContain(ref);
    expect(theirIncidents, 'the second session sees its own incident').toContain(theirIncident);
    for (const ref of [closed, open, evalIncident, instanceIncident]) expect(theirIncidents, `the second session does not list ${ref}`).not.toContain(ref);

    const text = JSON.stringify(await (await request.get(`${DECISIONS}?${on40}`)).json()) + JSON.stringify(incidents) + JSON.stringify(await (await second.get(`${DECISIONS}?${on40}`)).json());
    expect(text, 'no session Ref appears in a body').not.toContain(liveSession);
    expect(text).not.toContain(otherSession);
    expect(text.toLowerCase(), 'and no user name').not.toContain(live.user.toLowerCase());
    for (const word of ['"id"', 'ownerRef', 'itemId', 'traceHeaderId', 'traceNamespace', '"kind"']) expect(text, `no ${word}`).not.toContain(word);
  } finally {
    await anonymous.dispose();
    await second.dispose();
    await cleanFixtureRows(refs);
  }
});

/**
 * The Planner's case 7 for both routes, as the LIVE user and with no seeded row: a page past the last is a 200 with the page asked for, the page count and an empty
 * list, never an error. The incidents route has its own case here (the first test pages the decisions only); an empty day has one page whatever the page asked.
 * It reads only what its own request asks for and creates nothing, so no other case's rows or order change it. The day is 60 days ago, which no case seeds.
 */
test('the history routes: a page past the last is 200 with an empty list and the page count, on both routes', async ({ request }) => {
  const live = fixtureUser('LIVE');
  await signInOverHttp(request, live.user, live.password);
  const empty = await localDate(60);
  const cases: Array<{ url: string; list: 'decisions' | 'incidents'; query: string; pages?: number }> = [
    { url: DECISIONS, list: 'decisions', query: `day=${empty}`, pages: 1 },
    { url: DECISIONS, list: 'decisions', query: '' },
    { url: INCIDENTS, list: 'incidents', query: '' },
  ];
  for (const { url, list, query, pages } of cases) {
    const first = await read<Decision | Incident>(await request.get(`${url}?${query}`), list);
    expect(first.page, `${list} ${query}: page 1`).toBe(1);
    expect(first.pages, `${list} ${query}: at least one page`).toBeGreaterThanOrEqual(1);
    for (const page of [first.pages + 1, 9999]) {
      const response = await request.get(`${url}?${query}${query ? '&' : ''}page=${page}`);
      expect(response.status(), `${list} ${query} page ${page}: not an error: ${await response.text()}`).toBe(200);
      const body = (await response.json()) as Record<string, unknown>;
      expect(Object.keys(body).sort(), `${list} page ${page}: the top level`).toEqual(['page', 'pages', list].sort());
      expect(body['page'], `${list} page ${page}: the page asked for`).toBe(page);
      expect(body[list], `${list} page ${page}: an empty list`).toEqual([]);
      const count = body['pages'] as number;
      expect(count, `${list} page ${page}: the page count is before the page asked for`).toBeLessThan(page);
      expect(count).toBeGreaterThanOrEqual(1);
      if (pages !== undefined) expect(count, `${list} ${query}: one page`).toBe(pages);
    }
  }
});

/** The 403 row of the routes: an account without the OcuTalon user role is refused before the route is looked at, like every other route (api.spec.ts row 18). */
test('the history routes: a user without the OcuTalon user role gets 403 no_role', async ({ playwright, baseURL }) => {
  const user = process.env['OCUTALON_TRACEONLY_USER'];
  const password = process.env['OCUTALON_TRACEONLY_PASSWORD'];
  expect(user && password, 'the trace-only fixture user is seeded').toBeTruthy();
  const trace = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  try {
    await expectError(await trace.post('/ocutalon/api/v1/state', { form: { IRISUsername: user!, IRISPassword: password!, IRISLogin: 'Sign in' } }), 403, 'no_role', NO_ROLE);
    for (const url of [DECISIONS, `${DECISIONS}?outcome=act`, `${DECISIONS}?outcome=foo`, INCIDENTS, `${INCIDENTS}?page=2`]) {
      await expectError(await trace.get(url), 403, 'no_role', NO_ROLE);
    }
  } finally {
    await trace.dispose();
  }
});
