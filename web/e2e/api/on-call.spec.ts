import { expect, test, type APIRequestContext } from '../support/fixtures';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { readmeSession } from '../support/demo-path';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { ON_CALL_API, ON_CALL_KEYS, SETTINGS_API, auditMark, auditSince, freshValues, readOnCall, resetOnCall, restoreOnCall, type OnCallStored } from '../support/on-call';

/**
 * Story 36.4, the on-call route over real HTTP, on the stack that test-sign-in.sh seeds (a local install). The README account holds OcuTalonAdmin; the LIVE
 * fixture user holds OcuTalonUser only (the online demo visitors' role). The cases run one after the other, because the on-call values are the instance's own, and
 * each puts back the values it found.
 *   H1  the LIVE user gets 403 not_admin on GET /v1/settings and POST /v1/settings/on-call; the rows are unchanged and no audit entry names an on-call key;
 *   H2  the README admin gets 200 with the on-call section, a fresh process reads the new values through Data.Setting.Get (the read path of Stories 23.4 and
 *       24.3), and each changed key has an audit entry with from, to, the admin's user and session;
 *   H3  a bad address is 400 bad_settings naming primaryEmail, with nothing changed and nothing audited;
 *   H4  on the online demo (the flag set for the case and put back after it) the README admin's POST is 409 not_available with the off-demo text, a body that is
 *       not a JSON object included (the refusal comes before the body is read), nothing is changed or audited, and GET /v1/settings has no on-call member.
 * H2 starts from Nobody for both roles and 15 minutes (saved through the route), so that its changes do not depend on what an earlier run left.
 */
const NOT_ADMIN = 'Only OcuTalon admins can open settings.';
const OFF_ON_DEMO = "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.";

/** A unique tag for the case's addresses. */
const tag = (): string => `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

/** An admin context signed in as the README account. */
async function admin(request: APIRequestContext): Promise<APIRequestContext> {
  const response = await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  expect(response.status(), 'the README account signs in').toBeLessThan(400);
  return request;
}

/** A valid body: the README admin as the on-call person, paged by email only, and a backup by email, with the minutes. */
const bodyOf = (primaryAddress: string, backupAddress: string, minutes: number): Record<string, string | number> => ({
  primaryPerson: 'user',
  primaryUser: README_ACCOUNT.user,
  primaryEmail: primaryAddress,
  primaryChannels: 'email',
  backupPerson: 'email',
  backupUser: '',
  backupEmail: backupAddress,
  backupChannels: 'email',
  escalationMinutes: minutes,
});

test.describe.configure({ mode: 'serial' });

test('H1: the LIVE user is 403 not_admin on GET /settings and POST /settings/on-call, and nothing changes', async ({ request, playwright, baseURL }) => {
  test.setTimeout(180_000);
  await admin(request);
  const before = await freshValues();
  const mark = await auditMark();
  const live = await playwright.request.newContext({ baseURL });
  try {
    const user = fixtureUser('LIVE');
    await signInOverHttp(live, user.user, user.password);
    await expectError(await live.get(SETTINGS_API), 403, 'not_admin', NOT_ADMIN);
    const t = tag();
    await expectError(await live.post(ON_CALL_API, { headers: envelope(), data: bodyOf(`zz-h1p-${t}@example.com`, `zz-h1b-${t}@example.com`, 33) }), 403, 'not_admin', NOT_ADMIN);
    await expectError(await live.post(ON_CALL_API, { headers: envelope(), data: {} }), 403, 'not_admin', NOT_ADMIN);
    expect(await freshValues(), 'the rows are unchanged').toEqual(before);
    expect(await auditSince(mark, 0), 'and no audit entry names an on-call key').toEqual([]);
  } finally {
    await live.dispose();
  }
});

test('H2: the README admin saves, a fresh process reads the values, and each changed key has an audit entry with from, to, the admin and the session', async ({ request }) => {
  test.setTimeout(240_000);
  await admin(request);
  const before = await readOnCall(request);
  const t = tag();
  const primary = `zz-h2p-${t}@example.com`;
  const backup = `zz-h2b-${t}@example.com`;
  try {
    await resetOnCall(request);
    const start = await readOnCall(request);
    const mark = await auditMark();
    const response = await request.post(ON_CALL_API, { headers: envelope(), data: bodyOf(primary, backup, 25) });
    expect(response.status(), await response.text()).toBe(200);
    const answer = (await response.json()) as { result: string; sections: { 'on-call'?: OnCallStored } };
    expect(answer.result, 'the answer is done').toBe('done');
    const saved = answer.sections['on-call'];
    expect([saved?.primaryUser, saved?.primaryEmail, saved?.primaryChannels, saved?.backupEmail, saved?.escalationMinutes], 'with the on-call section').toEqual([
      README_ACCOUNT.user,
      primary,
      'email',
      backup,
      25,
    ]);
    expect(saved?.users.map((one) => one.user), 'which lists the OcuTalon users, the README admin included').toContain(README_ACCOUNT.user);
    const got = await readOnCall(request);
    expect([got.primaryEmail, got.backupEmail, got.escalationMinutes], 'GET shows the same').toEqual([primary, backup, 25]);

    const fresh = await freshValues();
    expect(fresh, 'a fresh process reads the new values through Data.Setting.Get').toMatchObject({
      'oncall.primary.user': README_ACCOUNT.user,
      'oncall.primary.email': primary,
      'oncall.primary.channels': 'email',
      'oncall.backup.email': backup,
      'oncall.backup.channels': 'email',
      'oncall.escalationMinutes': '25',
    });

    const wanted = ON_CALL_KEYS.flatMap(([key, member]) => (String(start[member]) === String(got[member]) ? [] : [{ setting: key, from: String(start[member]), to: String(got[member]) }]));
    expect(wanted.length, 'from Nobody and 15 minutes the case changes the user, the two addresses, both channels and the minutes').toBe(6);
    const entries = await auditSince(mark, wanted.length);
    const byKey = <T extends { setting: string }>(list: T[]): T[] => [...list].sort((a, b) => a.setting.localeCompare(b.setting));
    expect(
      byKey(entries.map((one) => ({ setting: one.setting, from: one.from, to: one.to }))),
      'each changed key has one audit entry, with its value before and now',
    ).toEqual(byKey(wanted));
    const session = await readmeSession();
    for (const entry of entries) {
      expect([entry.irisUser, entry.sessionRef, entry.channel], `${entry.setting}: the admin's user, the session and the web channel`).toEqual([README_ACCOUNT.user, session.ref, 'web']);
    }
  } finally {
    await restoreOnCall(request, before);
  }
});

test('H3: a bad address is 400 bad_settings naming primaryEmail, and nothing is changed or audited', async ({ request }) => {
  test.setTimeout(180_000);
  await admin(request);
  const before = await readOnCall(request);
  try {
    const stored = await freshValues();
    const mark = await auditMark();
    const response = await request.post(ON_CALL_API, { headers: envelope(), data: { ...bodyOf('nope', `zz-h3b-${tag()}@example.com`, 25), primaryPerson: 'email', primaryUser: '' } });
    expect(response.status(), await response.text()).toBe(400);
    const body = (await response.json()) as { error: { code: string; message: string }; fields: string[] };
    expect(body.error, 'bad_settings with the plain message').toEqual({ code: 'bad_settings', message: "Couldn't save. Nothing was changed." });
    expect(body.fields, 'naming the address').toEqual(['primaryEmail']);
    expect(JSON.stringify(body), 'and holding no value that was sent').not.toContain('nope');
    expect(await freshValues(), 'nothing was changed').toEqual(stored);
    expect(await auditSince(mark, 0), 'and nothing was audited').toEqual([]);
  } finally {
    await restoreOnCall(request, before);
  }
});

test('H4: on the online demo the admin is 409 not_available before the body is read, nothing changes, and GET has no on-call member', async ({ request }) => {
  test.setTimeout(180_000);
  await admin(request);
  const stored = await freshValues();
  const was = chk(await irisScript('Write !,"CHK|demo|",##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")'), 'demo');
  expect(was, 'the online-demo flag could be read').toBeDefined();
  try {
    const set = chk(await irisScript('Write !,"CHK|set|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo",1))'), 'set');
    expect(set, 'the online-demo flag is set for the case').toBe('1');
    const mark = await auditMark();
    const t = tag();
    await expectError(await request.post(ON_CALL_API, { headers: envelope(), data: bodyOf(`zz-h4p-${t}@example.com`, `zz-h4b-${t}@example.com`, 44) }), 409, 'not_available', OFF_ON_DEMO);
    await expectError(await request.post(ON_CALL_API, { headers: envelope(), data: 'not a JSON object' }), 409, 'not_available', OFF_ON_DEMO);
    const response = await request.get(SETTINGS_API);
    expect(response.status(), 'GET /v1/settings still answers the admin').toBe(200);
    const body = (await response.json()) as { sections: Record<string, unknown> };
    expect(Object.keys(body.sections), 'with no on-call member').not.toContain('on-call');
    expect(await freshValues(), 'the rows are unchanged').toEqual(stored);
    expect(await auditSince(mark, 0), 'and nothing was audited').toEqual([]);
  } finally {
    await irisScript(`Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo",${quoted(was ?? '')})`);
  }
});
