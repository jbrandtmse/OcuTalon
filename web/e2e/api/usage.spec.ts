import { expect, test, type APIResponse } from '../support/fixtures';

import { expectError, signInOverHttp } from '../sign-in/helpers';
import { fixtureUser } from '../support/iris';
import { sessionRefOfUser } from '../support/memory';
import { cleanUsage, seedUsage, type UsageSeed } from '../support/usage';

/**
 * Story 37.2, the Rule 3 evidence for GET /api/v1/usage over real HTTP, on the stack that test-sign-in.sh seeds. Signed out the route is 401 signed_out with no
 * challenge. As the LIVE fixture user (role OcuTalonUser only, the online demo visitors' role) the read is 200 and holds the user's seeded rows summed exactly,
 * `limit` is 100000 and `days` has 7 dates for the default range, 1 for ?days=1 and 30 for ?days=30; a row 10 days ago is in the 30-day read and not in the 7-day
 * one. A key allow-list proves the body: the top level is exactly days, limit and buckets, and every bucket is exactly the eleven keys, so that no ref, row id,
 * user name or SessionRef appears. ?days=0, 31, abc, 5 and an empty value are each 404 not_found. A second session (the PANEL fixture user, also OcuTalonUser
 * only, so another durable session) with rows of its own never sees the first session's models, and an eval-owned row seeded beside them appears in neither
 * response. The route is not admin-only, so the only 403 is no_role, which a second case pins for the trace-only fixture user. Only the test's own unique models are asserted on, so other rows change nothing; the rows are
 * removed in `finally`.
 */
const USAGE = '/ocutalon/api/v1/usage';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const TOP_KEYS = ['buckets', 'days', 'limit'];
const BUCKET_KEYS = ['agent', 'cacheReadTokens', 'cacheWriteTokens', 'channel', 'costUSD', 'day', 'estimated', 'inputTokens', 'largestRequestTokens', 'model', 'outputTokens'];

interface Bucket {
  day: string;
  agent: string;
  channel: string;
  model: string;
  estimated: boolean;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  costUSD: number;
  largestRequestTokens: number;
}
interface Body {
  days: string[];
  limit: number;
  buckets: Bucket[];
}

/** The 200 body of a read, with the key allow-list checked: the top level and every bucket hold exactly their keys. */
async function readUsage(response: APIResponse): Promise<Body> {
  expect(response.status(), await response.text()).toBe(200);
  expect(response.headers()['content-type']).toContain('application/json');
  const body = (await response.json()) as Body;
  expect(Object.keys(body).sort(), 'the top level holds exactly days, limit and buckets').toEqual(TOP_KEYS);
  for (const bucket of body.buckets) expect(Object.keys(bucket).sort(), 'a bucket holds exactly the eleven keys').toEqual(BUCKET_KEYS);
  return body;
}

/** The buckets of the test's own models. */
const ofModels = (body: Body, models: string[]): Bucket[] => body.buckets.filter((bucket) => models.includes(bucket.model));

test('the usage route: signed out, the read as the LIVE user with exact sums, the key allow-list, the bad ranges, and a second session sees none of it', async ({ request, playwright, baseURL }) => {
  test.setTimeout(120_000);
  const live = fixtureUser('LIVE');
  const other = fixtureUser('PANEL');
  const stamp = Date.now().toString(36);
  const modelA = `zz-usage-a-${stamp}`;
  const modelP = `zz-usage-p-${stamp}`;
  const modelE = `zz-usage-e-${stamp}`;
  const refs: string[] = [];
  const second = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  try {
    // (i) signed out: 401 signed_out, with no challenge.
    for (const url of [USAGE, `${USAGE}?days=7`, `${USAGE}?days=abc`]) {
      const response = await anonymous.get(url);
      await expectError(response, 401, 'signed_out', SIGNED_OUT);
      expect(response.headers()['www-authenticate'], `${url} sends no challenge`).toBeUndefined();
    }

    // (ii) the LIVE user.
    await signInOverHttp(request, live.user, live.password);
    const liveSession = await sessionRefOfUser(live.user);
    const rows: UsageSeed[] = [
      { daysAgo: 0, agent: 'ChatAgent', channel: 'web', model: modelA, input: 100, output: 10, cacheRead: 20, cacheWrite: 5, cost: 0.001, largest: 1500 },
      { daysAgo: 0, agent: 'ChatAgent', channel: 'web', model: modelA, input: 50, output: 5, cost: 0.0005, largest: 2500 },
      { daysAgo: 2, agent: 'compaction', channel: 'web', model: modelA, estimated: true, input: 300, output: 30, cost: 0.003, largest: 2000 },
      { daysAgo: 2, agent: 'TriageAgentRetry', channel: 'telegram', model: modelA, input: 7, output: 1, cost: null, largest: 70 },
      { daysAgo: 10, agent: 'DiagnosisAgent', channel: 'phone', model: modelA, input: 900, output: 90, cost: 0.09, largest: 9000 },
    ];
    const seeded = await seedUsage(liveSession, rows);
    refs.push(...seeded.refs);
    const [today, twoAgo, tenAgo] = [seeded.dates[0]!, seeded.dates[2]!, seeded.dates[4]!];

    const week = await readUsage(await request.get(USAGE));
    expect(week.limit, 'limit is the request-size limit').toBe(100000);
    expect(week.days, 'the default range is 7 dates, today last').toHaveLength(7);
    expect(week.days[6]).toBe(today);
    expect(week.days, 'oldest first').toEqual([...week.days].sort());
    const explicit = await readUsage(await request.get(`${USAGE}?days=7`));
    expect(explicit.days, '?days=7 is the default range').toEqual(week.days);
    expect(ofModels(explicit, [modelA]), 'and holds the same buckets of the test\'s own model').toEqual(ofModels(week, [modelA]));
    const sevenDays = ofModels(week, [modelA]).sort((a, b) => (a.day + a.agent < b.day + b.agent ? -1 : 1));
    expect(sevenDays, 'the 7-day read holds the four buckets of the last 7 days, summed exactly, and not the row of 10 days ago').toEqual([
      { day: twoAgo, agent: 'TriageAgentRetry', channel: 'telegram', model: modelA, estimated: false, inputTokens: 7, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0, costUSD: 0, largestRequestTokens: 70 },
      { day: twoAgo, agent: 'compaction', channel: 'web', model: modelA, estimated: true, inputTokens: 300, outputTokens: 30, cacheReadTokens: 0, cacheWriteTokens: 0, costUSD: 0.003, largestRequestTokens: 2000 },
      { day: today, agent: 'ChatAgent', channel: 'web', model: modelA, estimated: false, inputTokens: 150, outputTokens: 15, cacheReadTokens: 20, cacheWriteTokens: 5, costUSD: 0.0015, largestRequestTokens: 2500 },
    ]);

    const one = await readUsage(await request.get(`${USAGE}?days=1`));
    expect(one.days, 'today alone').toEqual([today]);
    expect(ofModels(one, [modelA]).map((bucket) => bucket.agent), 'the 1-day read holds only today\'s bucket').toEqual(['ChatAgent']);

    const month = await readUsage(await request.get(`${USAGE}?days=30`));
    expect(month.days, '30 dates').toHaveLength(30);
    expect(month.days[29]).toBe(today);
    expect(ofModels(month, [modelA]).map((bucket) => bucket.day), 'the 30-day read also holds the row of 10 days ago').toContain(tenAgo);
    expect(ofModels(month, [modelA])).toHaveLength(4);

    // The bad ranges are 404 not_found.
    for (const days of ['0', '31', 'abc', '5', '', '-1', '07', '7.0']) {
      await expectError(await request.get(`${USAGE}?days=${days}`), 404, 'not_found', NOT_FOUND);
    }

    // (iii) a second session with its own rows, and an eval-owned row, appear in neither response.
    await signInOverHttp(second, other.user, other.password);
    const otherSession = await sessionRefOfUser(other.user);
    expect(otherSession, 'the second account is another session').not.toBe(liveSession);
    const theirs = await seedUsage(otherSession, [{ daysAgo: 0, agent: 'TriageAgent', channel: 'web', model: modelP, input: 11, output: 2, cost: 0.1, largest: 123 }]);
    refs.push(...theirs.refs);
    const evalRows = await seedUsage('eval', [{ daysAgo: 0, agent: 'TriageAgent', channel: 'web', model: modelE, input: 22, output: 3, cost: 0.2, largest: 456 }]);
    refs.push(...evalRows.refs);

    const liveAfter = await readUsage(await request.get(`${USAGE}?days=30`));
    expect(ofModels(liveAfter, [modelP, modelE]), 'the LIVE session sees neither the other session\'s row nor the eval row').toEqual([]);
    expect(ofModels(liveAfter, [modelA]), 'and its own rows are unchanged').toHaveLength(4);
    const theirRead = await readUsage(await second.get(`${USAGE}?days=30`));
    expect(ofModels(theirRead, [modelP]), 'the second session sees its own row').toEqual([
      { day: theirs.dates[0]!, agent: 'TriageAgent', channel: 'web', model: modelP, estimated: false, inputTokens: 11, outputTokens: 2, cacheReadTokens: 0, cacheWriteTokens: 0, costUSD: 0.1, largestRequestTokens: 123 },
    ]);
    expect(ofModels(theirRead, [modelA, modelE]), 'and none of the first session\'s rows or the eval row').toEqual([]);
    const text = JSON.stringify(theirRead) + JSON.stringify(liveAfter);
    expect(text, 'no session Ref appears in a body').not.toContain(liveSession);
    expect(text).not.toContain(otherSession);
    expect(text.toLowerCase(), 'and no user name').not.toContain(live.user.toLowerCase());
  } finally {
    await anonymous.dispose();
    await second.dispose();
    await cleanUsage(refs);
  }
});

/** The 403 row of the route: an account without the OcuTalon user role is refused before the route is looked at, like every other route (api.spec.ts row 18). */
test('the usage route: a user without the OcuTalon user role gets 403 no_role', async ({ playwright, baseURL }) => {
  const user = process.env['OCUTALON_TRACEONLY_USER'];
  const password = process.env['OCUTALON_TRACEONLY_PASSWORD'];
  expect(user && password, 'the trace-only fixture user is seeded').toBeTruthy();
  const trace = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  try {
    await expectError(await trace.post('/ocutalon/api/v1/state', { form: { IRISUsername: user!, IRISPassword: password!, IRISLogin: 'Sign in' } }), 403, 'no_role', NO_ROLE);
    await expectError(await trace.get(USAGE), 403, 'no_role', NO_ROLE);
    await expectError(await trace.get(`${USAGE}?days=abc`), 403, 'no_role', NO_ROLE);
  } finally {
    await trace.dispose();
  }
});
