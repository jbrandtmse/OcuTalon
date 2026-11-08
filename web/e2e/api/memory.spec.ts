import { expect, test } from '../support/fixtures';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { chk, irisScript, quoted } from '../support/iris';
import { sessionRef } from '../support/persona';

/**
 * Story 41.2, the Rule 3 evidence for the four memory routes over real HTTP, on the stack that test-sign-in.sh seeds (the README account's
 * session): POST /api/v1/decisions/:ref/noise, GET /api/v1/memory/precedents, DELETE /api/v1/memory/precedents/:ref and
 * GET /api/v1/memory/notes. Each route answers 401 signed_out with no session. The signed-in README account lists a precedent row that the test
 * seeded through irisScript and does not list a seeded row of owner eval; deleting the listed row is 200 and the list then holds neither row (only
 * the test's own rows are asserted on, so other rows of the account change nothing); deleting the
 * seeded row, deleting an unknown ref and marking an unknown decision as noise are 404 not_found; the notes of today are 200 with no lines
 * (the note builder arrives with Story 41.3) and an unknown day is 404. The rows the test seeds are removed in `finally`.
 */
const MEMORY = '/ocutalon/api/v1/memory';
const NOISE = (ref: string): string => `/ocutalon/api/v1/decisions/${ref}/noise`;
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const KEY = 'zz.memoryspec@example.com';

/** Saves a precedent row of the owner (a session's Ref, or eval with a run) and answers its Ref. */
async function seedRow(owner: string, answeredAt: string, run: string): Promise<string> {
  const lines = await irisScript(
    [
      'Set r=##class(OcuTalon.Data.Precedent).%New()',
      'Set r.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set r.OwnerRef=${quoted(owner)}`,
      'Set r.Channel="mailbox"',
      `Set r.MatchKey=${quoted(KEY)}`,
      'Set r.Summary="zz memory spec"',
      'Set r.Outcome="tellnow"',
      'Set r.Answer="noise"',
      `Set r.AnsweredAt=${quoted(answeredAt)}`,
      'Set r.AnsweredChannel="phone"',
      'Set r.SourceRef=r.Ref',
      `Set r.EvalRunRef=${quoted(run)}`,
      'Set sc=r.%Save()',
      'Write !,"CHK|ref|",$Select($SYSTEM.Status.IsOK(sc):r.Ref,1:"")',
    ].join('\n'),
  );
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`a precedent row could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** Deletes the row with the Ref, if it is there. */
async function removeRow(ref: string): Promise<void> {
  await irisScript(
    [`Set r=##class(OcuTalon.Data.Precedent).RefIndexOpen(${quoted(ref)})`, 'If $IsObject(r) Do ##class(OcuTalon.Data.Precedent).%DeleteId(r.%Id())', 'Write !,"CHK|removed|1"'].join('\n'),
  );
}

/** 1 when the row with the Ref is there, else 0. */
async function rowExists(ref: string): Promise<number> {
  const lines = await irisScript([`Write !,"CHK|exists|",##class(OcuTalon.Data.Precedent).RefIndexExists(${quoted(ref)})`].join('\n'));
  return Number(chk(lines, 'exists') ?? Number.NaN);
}

test('the memory routes: signed out, the list, a delete, unknown refs, and the notes', async ({ request, playwright, baseURL }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const ref = await sessionRef();
  const seeded: string[] = [];
  try {
    const anonymous = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
    try {
      const calls = [
        { method: 'GET', url: `${MEMORY}/precedents` },
        { method: 'DELETE', url: `${MEMORY}/precedents/zzunknownref` },
        { method: 'POST', url: NOISE('zzunknownref') },
        { method: 'GET', url: `${MEMORY}/notes?day=today` },
      ] as const;
      for (const call of calls) {
        const response = await anonymous.fetch(call.url, { method: call.method, headers: envelope(), data: call.method === 'POST' ? '{"channel":"phone"}' : undefined });
        await expectError(response, 401, 'signed_out', SIGNED_OUT);
        expect(response.headers()['www-authenticate'], `${call.method} ${call.url} sends no challenge`).toBeUndefined();
      }
    } finally {
      await anonymous.dispose();
    }

    const own = await seedRow(ref, '2030-01-01T10:00:00Z', '');
    seeded.push(own);
    const run = `zzmemoryrun${Date.now()}`.slice(0, 22);
    const eval_ = await seedRow('eval', '2030-01-02T10:00:00Z', run);
    seeded.push(eval_);

    const listed = await request.get(`${MEMORY}/precedents`);
    expect(listed.status(), await listed.text()).toBe(200);
    expect(listed.headers()['content-type']).toContain('application/json');
    const rows = ((await listed.json()) as { precedents: Array<Record<string, string>> }).precedents.filter((row) => seeded.includes(row['ref'] ?? ''));
    expect(rows.map((row) => row['ref']), 'of the test\'s rows, the list holds the session\'s own row and no seeded row').toEqual([own]);
    expect(Object.keys(rows[0] ?? {})).toEqual(['ref', 'answeredAt', 'channel', 'answeredChannel', 'summary', 'outcome', 'answer']);
    expect(rows[0]).toEqual({ ref: own, answeredAt: '2030-01-01T10:00:00Z', channel: 'mailbox', answeredChannel: 'phone', summary: 'zz memory spec', outcome: 'tellnow', answer: 'noise' });

    await expectError(await request.fetch(`${MEMORY}/precedents/${eval_}`, { method: 'DELETE', headers: envelope() }), 404, 'not_found', NOT_FOUND);
    expect(await rowExists(eval_), 'the seeded row is still there').toBe(1);

    const deleted = await request.fetch(`${MEMORY}/precedents/${own}`, { method: 'DELETE', headers: envelope() });
    expect(deleted.status(), await deleted.text()).toBe(200);
    expect(await deleted.json()).toEqual({ result: 'done' });
    expect(await rowExists(own), 'the row is gone').toBe(0);
    const after = await request.get(`${MEMORY}/precedents`);
    const left = ((await after.json()) as { precedents: Array<Record<string, string>> }).precedents.filter((row) => seeded.includes(row['ref'] ?? ''));
    expect(left, 'the list then holds none of the test\'s rows').toEqual([]);

    await expectError(await request.fetch(`${MEMORY}/precedents/zzunknownref`, { method: 'DELETE', headers: envelope() }), 404, 'not_found', NOT_FOUND);
    await expectError(await request.fetch(NOISE('zzunknownref'), { method: 'POST', headers: envelope(), data: '{"channel":"phone"}' }), 404, 'not_found', NOT_FOUND);

    const today = await request.get(`${MEMORY}/notes?day=today`);
    expect(today.status(), await today.text()).toBe(200);
    const note = (await today.json()) as { day: string; date: string; lines: string[] };
    expect(note.day).toBe('today');
    expect(note.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(note.lines).toEqual([]);
    const missing = await request.get(`${MEMORY}/notes?day=zz`);
    await expectError(missing, 404, 'not_found', NOT_FOUND);
  } finally {
    for (const one of seeded) await removeRow(one);
  }
});
