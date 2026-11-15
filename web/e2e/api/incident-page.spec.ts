import { expect, test } from '../support/fixtures';

import { signInOverHttp } from '../sign-in/helpers';
import { STATE } from '../support/api';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted, seedIncident } from '../support/iris';

/**
 * Story 23.4 (AC11, Rule 3): the page of an incident in GET /api/v1/state over real HTTP, on the stack that test-sign-in.sh seeds. As the LIVE fixture user (role OcuTalonUser
 * only) who watches a seeded incident that has an on-call page and an escalated, acknowledged backup page, the state lists the incident with `page`: its state, when it was
 * paged, and when and on which channel the first acknowledgement came, and the body holds neither the paged person nor the page's Ref. A second session (the PANEL fixture
 * user, also OcuTalonUser only) lists no such incident. The incident and its page rows are removed in `finally`.
 */
const PERSON = 'zzpagedperson';

interface StatePage {
  state?: string;
  pagedAt?: string;
  acknowledgedAt?: string;
  channel?: string;
}
interface StateBody {
  chat: Array<{ type: string; payload: { ref?: string; page?: StatePage } }>;
}

/** A Data.Page row of the incident and the role (the paged person is PERSON), acknowledged on the channel when one is given; its Ref. */
async function seedPage(incident: string, role: 'oncall' | 'backup', sentAt: string, acknowledged?: { at: string; channel: string }): Promise<string> {
  const lines = await irisScript(
    [
      'Set p=##class(OcuTalon.Data.Page).%New()',
      'Set p.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set p.IncidentRef=${quoted(incident)}`,
      `Set p.Role=${quoted(role)}`,
      `Set p.Person=${quoted(PERSON)}`,
      'Set p.Channels="telegram,email"',
      `Set p.SentAt=${quoted(sentAt)}`,
      ...(acknowledged ? [`Set p.AcknowledgedAt=${quoted(acknowledged.at)}`, `Set p.AcknowledgedChannel=${quoted(acknowledged.channel)}`] : []),
      'Set sc=p.%Save()',
      'Write !,"CHK|page|",p.Ref',
    ].join('\n'),
  );
  const ref = chk(lines, 'page');
  if (!ref) throw new Error(`the page could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** Deletes the page rows of the incident. */
async function dropPages(incident: string): Promise<void> {
  await irisScript([`Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.Page WHERE IncidentRef = ?",${quoted(incident)})`, 'Write !,"CHK|dropped|1"'].join('\n'));
}

test('the incident in /api/v1/state lists its page with state and times and no person, and a second session lists no such incident', async ({ request, playwright, baseURL }) => {
  test.setTimeout(180_000);
  const live = fixtureUser('LIVE');
  const other = fixtureUser('PANEL');
  const rows: string[] = [];
  let incident = '';
  const second = await playwright.request.newContext({ baseURL, extraHTTPHeaders: { 'accept-language': 'en-US,en;q=0.9' } });
  try {
    await signInOverHttp(request, live.user, live.password);
    await signInOverHttp(second, other.user, other.password);
    incident = await seedIncident(live.user, { state: 'open', openVariant: 'no_fix' });
    rows.push(incident);

    const paged = await seedPage(incident, 'oncall', '2030-01-01T09:05:00Z');
    let body = (await (await request.get(STATE)).json()) as StateBody;
    let found = body.chat.find((item) => item.type === 'incident' && item.payload.ref === incident);
    expect(found, 'the user\'s state lists the incident').toBeDefined();
    expect(found?.payload.page, 'with its page, paged').toMatchObject({ state: 'paged', pagedAt: '2030-01-01T09:05:00Z' });
    expect(found?.payload.page?.acknowledgedAt ?? '', 'not acknowledged').toBe('');

    await seedPage(incident, 'backup', '2030-01-01T09:20:00Z', { at: '2030-01-01T09:22:00Z', channel: 'telegram' });
    body = (await (await request.get(STATE)).json()) as StateBody;
    found = body.chat.find((item) => item.type === 'incident' && item.payload.ref === incident);
    expect(found?.payload.page, 'once the backup acknowledged it, the page is acknowledged, when and where').toMatchObject({
      state: 'acknowledged',
      pagedAt: '2030-01-01T09:05:00Z',
      acknowledgedAt: '2030-01-01T09:22:00Z',
      channel: 'telegram',
    });
    const text = JSON.stringify(body);
    expect(text, 'the body holds no paged person').not.toContain(PERSON);
    expect(text, 'and no page Ref').not.toContain(paged);
    expect(Object.keys(found?.payload.page ?? {}).sort(), 'the page member holds only its four keys').toEqual(['acknowledgedAt', 'channel', 'pagedAt', 'state']);

    const theirs = (await (await second.get(STATE)).json()) as StateBody;
    expect(JSON.stringify(theirs), 'a second session lists no such incident').not.toContain(incident);
  } finally {
    await second.dispose();
    if (incident !== '') await dropPages(incident);
    await cleanFixtureRows(rows);
  }
});
