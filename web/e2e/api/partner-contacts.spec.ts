import { expect, test, type APIRequestContext } from '../support/fixtures';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { readmeSession } from '../support/demo-path';
import { fixtureUser } from '../support/iris';
import { PARTNER_API, SETTINGS_API, aProduction, auditMark, auditSince, forProduction, partnerMember, realTable, removeZzContacts } from '../support/partner-contacts';

/**
 * Story 24.2, the Partner contacts route over real HTTP, on the stack that test-sign-in.sh seeds (a local install). The README account holds OcuTalonAdmin; the LIVE
 * fixture user holds OcuTalonUser only (the online demo visitors' role). The route and the saver do not read the TABLE switch of OcuTalon.Fix.PartnerContacts, so these
 * cases run whether or not it is 1; only the member of GET /v1/settings follows it. The cases run one after the other and remove the contacts that they make (names that
 * begin zz-) in afterAll.
 *   H1  the LIVE user gets 403 not_admin on POST /settings/partner-contacts; the rows are unchanged and no audit entry names a contact;
 *   H2  the README admin's add is 200, the answer and GET carry the partner-contacts member exactly when the real TABLE is 1, ForProduction in a fresh process
 *       gives the contact, and the one audit entry names the fields and the admin and the session, with no value;
 *   H3  a bad address is 400 bad_settings naming email, holding no value that was sent, with nothing changed or audited;
 *   H4  a remove is 200, ForProduction no longer gives the contact, and its audit entry is from the field names to nothing.
 */
const NOT_ADMIN = 'Only OcuTalon admins can open settings.';

/** A unique tag for the case's names and addresses. */
const tag = (): string => `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

/** An admin context signed in as the README account. */
async function admin(request: APIRequestContext): Promise<APIRequestContext> {
  const response = await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  expect(response.status(), 'the README account signs in').toBeLessThan(400);
  return request;
}

test.describe.configure({ mode: 'serial' });

test.beforeAll(async () => {
  await removeZzContacts();
});

test.afterAll(async () => {
  await removeZzContacts();
});

test('H1: the LIVE user is 403 not_admin on POST /settings/partner-contacts, and nothing changes', async ({ request, playwright, baseURL }) => {
  test.setTimeout(180_000);
  await admin(request);
  const production = await aProduction();
  const before = (await partnerMember()).contacts;
  const mark = await auditMark();
  const live = await playwright.request.newContext({ baseURL });
  try {
    const user = fixtureUser('LIVE');
    await signInOverHttp(live, user.user, user.password);
    const t = tag();
    const body = { action: 'save', ref: '', name: `zz-h1-${t}`, email: `zz-h1-${t}@example.com`, productions: [{ namespace: production.namespace, production: production.production }] };
    await expectError(await live.post(PARTNER_API, { headers: envelope(), data: body }), 403, 'not_admin', NOT_ADMIN);
    await expectError(await live.post(PARTNER_API, { headers: envelope(), data: {} }), 403, 'not_admin', NOT_ADMIN);
    expect((await partnerMember()).contacts, 'the rows are unchanged').toEqual(before);
    expect(await auditSince(mark, 0, 2), 'and no audit entry names a contact').toEqual([]);
  } finally {
    await live.dispose();
  }
});

test('H2: the admin adds a contact, the member follows the real TABLE, ForProduction gives it in a fresh process, and the audit entry names the fields only', async ({ request }) => {
  test.setTimeout(240_000);
  await admin(request);
  const production = await aProduction();
  const t = tag();
  const name = `zz-h2-${t} Partner`;
  const email = `zz-h2-${t}@example.com`;
  const mark = await auditMark();
  const response = await request.post(PARTNER_API, {
    headers: envelope(),
    data: { action: 'save', ref: '', name, email, productions: [{ namespace: production.namespace, production: production.production }] },
  });
  expect(response.status(), await response.text()).toBe(200);
  const answer = (await response.json()) as { result: string; sections: Record<string, unknown> };
  expect(answer.result, 'the answer is done').toBe('done');
  const shown = (await realTable()) === '1';
  expect(answer.sections['partner-contacts'] !== undefined, 'the answer carries the member exactly when the real TABLE is 1').toBe(shown);
  const got = await request.get(SETTINGS_API);
  const body = (await got.json()) as { sections: Record<string, unknown> };
  expect(body.sections['partner-contacts'] !== undefined, 'and so does GET /v1/settings').toBe(shown);

  const stored = (await partnerMember()).contacts.find((one) => one.name === name);
  expect(stored?.email, 'the row holds the address').toBe(email);
  const given = await forProduction(production.namespace, production.production);
  expect(given.map((one) => [one.name, one.address]), 'ForProduction in a fresh process gives the contact').toContainEqual([name, email]);
  expect(Object.keys(given[0] ?? {}).sort(), 'as {id, name, address}').toEqual(['address', 'id', 'name']);

  const entries = await auditSince(mark, 1);
  expect(entries.length, 'one audit entry').toBe(1);
  const session = await readmeSession();
  expect([entries[0].setting, entries[0].from, entries[0].to, entries[0].irisUser, entries[0].sessionRef, entries[0].channel], 'with the field names, the admin and the session').toEqual([
    `partnerContact.${stored?.ref ?? ''}`,
    '',
    'name,email,productions',
    README_ACCOUNT.user,
    session.ref,
    'web',
  ]);
  expect(JSON.stringify(entries), 'and no value').not.toContain(email);
});

test('H3: a bad address is 400 bad_settings naming email, and nothing is changed or audited', async ({ request }) => {
  test.setTimeout(180_000);
  await admin(request);
  const production = await aProduction();
  const before = (await partnerMember()).contacts;
  const mark = await auditMark();
  const name = `zz-h3-${tag()}`;
  const response = await request.post(PARTNER_API, {
    headers: envelope(),
    data: { action: 'save', ref: '', name, email: 'nope', productions: [{ namespace: production.namespace, production: production.production }] },
  });
  expect(response.status(), await response.text()).toBe(400);
  const answer = (await response.json()) as { error: { code: string; message: string }; fields: string[] };
  expect(answer.error, 'bad_settings with the plain message').toEqual({ code: 'bad_settings', message: "Couldn't save. Nothing was changed." });
  expect(answer.fields, 'naming the address').toEqual(['email']);
  expect(JSON.stringify(answer), 'and holding no value that was sent').not.toContain(name);
  expect((await partnerMember()).contacts, 'nothing was changed').toEqual(before);
  expect(await auditSince(mark, 0, 2), 'and nothing was audited').toEqual([]);
});

test('H4: a remove is 200, ForProduction no longer gives the contact, and its audit entry is from the field names to nothing', async ({ request }) => {
  test.setTimeout(240_000);
  await admin(request);
  const production = await aProduction();
  const t = tag();
  const name = `zz-h4-${t} Partner`;
  const email = `zz-h4-${t}@example.com`;
  const added = await request.post(PARTNER_API, {
    headers: envelope(),
    data: { action: 'save', ref: '', name, email, productions: [{ namespace: production.namespace, production: production.production }] },
  });
  expect(added.status(), await added.text()).toBe(200);
  const stored = (await partnerMember()).contacts.find((one) => one.name === name);
  expect(stored, 'the contact is stored').toBeTruthy();
  expect((await forProduction(production.namespace, production.production)).map((one) => one.name), 'ForProduction gives it').toContain(name);
  const mark = await auditMark();
  const removed = await request.post(PARTNER_API, { headers: envelope(), data: { action: 'remove', ref: stored?.ref ?? '' } });
  expect(removed.status(), await removed.text()).toBe(200);
  expect((await forProduction(production.namespace, production.production)).map((one) => one.name), 'ForProduction no longer gives it').not.toContain(name);
  expect((await partnerMember()).contacts.map((one) => one.name), 'and the row is gone').not.toContain(name);
  const entries = await auditSince(mark, 1);
  expect(entries.map((one) => [one.setting, one.from, one.to]), 'its audit entry is from the field names to nothing').toEqual([[`partnerContact.${stored?.ref ?? ''}`, 'name,email,productions', '']]);
});
