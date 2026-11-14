import { expect, test, type APIRequestContext, type APIResponse } from '../support/fixtures';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { fixtureUser } from '../support/iris';

/**
 * Story 25.4, the Roles routes and the viewer over real HTTP, on the stack that test-sign-in.sh seeds (the fixture roles OcuTalonApprover, its per-kind roles and
 * OcuTalonViewer exist, with no resources; the README account holds OcuTalonAdmin; the LIVE user holds OcuTalonUser only; ZzViewer holds OcuTalonViewer only and
 * ZzRoleTarget holds OcuTalonUser). Every case that changes the target's roles puts them back in `finally`.
 *   R1  signed out, GET and POST /v1/settings/roles are 401 signed_out;
 *   R2  the LIVE user gets 403 not_admin for GET and POST;
 *   R3  the viewer signs in (/v1/state has viewer true and admin false), and POST /v1/settings/roles and every state-changing route are 403 read_only; /v1/state's
 *       chat is the same after them; POST /v1/session/end signs the viewer out (204), and the session is then 401;
 *   R4  the README admin lists (the target is in the list), grants OcuTalonViewer (changed true, then false), sees it in the list, and removes it (changed true, then false);
 *   R5  each refused role and user of the matrix is 400 bad_settings with its field and reason, and a bad shape is 400 naming the fields; the target's roles are unchanged.
 */
const ROLES = '/ocutalon/api/v1/settings/roles';
const STATE = '/ocutalon/api/v1/state';
const READ_ONLY = 'You have the viewer role, so you can look but not change anything.';
const NOT_ADMIN = 'Only OcuTalon admins can open settings.';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
/** The name of the fixture account whose roles change: read when a case runs, because the listing of the specs has no fixture users. */
const target = (): string => fixtureUser('ROLETARGET').user;

interface Holder {
  user: string;
  roles: string[];
  managed: boolean;
}

/** A context signed in as the README admin. */
async function admin(request: APIRequestContext): Promise<APIRequestContext> {
  const response = await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  expect(response.status(), 'the README account signs in').toBeLessThan(400);
  return request;
}

const save = (request: APIRequestContext, user: string, role: string, grant: boolean | string): Promise<APIResponse> =>
  request.post(ROLES, { headers: envelope(), data: { user, role, grant } });

const list = async (request: APIRequestContext): Promise<Holder[]> => {
  const response = await request.get(ROLES);
  expect(response.status(), await response.text()).toBe(200);
  const body = (await response.json()) as { users: Holder[] };
  expect(Object.keys(body)).toEqual(['users']);
  return body.users;
};

/** The roles that the target holds now, as the admin's list shows them. */
const targetRoles = async (request: APIRequestContext): Promise<string[]> => (await list(request)).find((one) => one.user === target())?.roles ?? [];

test('R1: signed out, both Roles routes are 401 signed_out', async ({ request }) => {
  await expectError(await request.get(ROLES), 401, 'signed_out', SIGNED_OUT);
  await expectError(await request.post(ROLES, { headers: envelope(), data: { user: target(), role: 'OcuTalonViewer', grant: true } }), 401, 'signed_out', SIGNED_OUT);
});

test('R2: the LIVE user, who holds OcuTalonUser only, gets 403 not_admin on both routes', async ({ request }) => {
  const live = fixtureUser('LIVE');
  expect((await signInOverHttp(request, live.user, live.password)).status()).toBeLessThan(400);
  await expectError(await request.get(ROLES), 403, 'not_admin', NOT_ADMIN);
  await expectError(await save(request, target(), 'OcuTalonViewer', true), 403, 'not_admin', NOT_ADMIN);
});

test('R3: the viewer is refused every state-changing route with 403 read_only, and signs out', async ({ request }) => {
  const viewer = fixtureUser('VIEWER');
  expect((await signInOverHttp(request, viewer.user, viewer.password)).status()).toBeLessThan(400);
  const stateBefore = await request.get(STATE);
  expect(stateBefore.status(), await stateBefore.text()).toBe(200);
  const before = (await stateBefore.json()) as Record<string, unknown>;
  expect(before['viewer'], 'viewer is true').toBe(true);
  expect(before['admin'], 'and admin false').toBe(false);
  expect(before['rolesAssignable'], 'the roles cannot be assigned on this branch').toBe(false);

  const api = '/ocutalon/api/v1';
  const writes: Array<[string, string, unknown]> = [
    ['POST', '/settings/roles', { user: target(), role: 'OcuTalonViewer', grant: true }],
    ['POST', '/messages', { clientId: 'zz-viewer-1', text: 'zz viewer message' }],
    ['POST', '/approvals/zzref/answer', { action: 'approve', channel: 'web' }],
    ['POST', '/incidents/zzref/dismiss', {}],
    ['POST', '/decisions/zzref/got-it', {}],
    ['POST', '/decisions/zzref/noise', {}],
    ['POST', '/demo/break-feed', {}],
    ['POST', '/mailbox/incoming', { subject: 'zz', body: 'zz' }],
    ['POST', '/mailbox/samples/newsletter', {}],
    ['POST', '/guide/markers', { marker: 'run_again' }],
    ['POST', '/pairing/code', {}],
    ['DELETE', '/pairing', undefined],
    ['PUT', '/persona', { preset: 'plain' }],
    ['PUT', '/heartbeat', { on: false }],
    ['POST', '/heartbeat/run', {}],
    ['DELETE', '/memory/precedents/zzref', undefined],
    ['POST', '/memory/zzref/pin', {}],
    ['DELETE', '/memory/zzref/pin', undefined],
    ['DELETE', '/memory/items/zzref', undefined],
    ['POST', '/settings/budgets', { DecisionTokenBudget: '1', DailyCostCapUSD: '1' }],
    ['POST', '/settings/models', {}],
    ['POST', '/settings/channels', {}],
    ['POST', '/settings/daily-digest', {}],
    ['POST', '/settings/demo-mode', { demoMode: false }],
    ['POST', '/settings/channels/webhooks', { name: 'zz', secret: 'zz-viewer-secret-0123456789' }],
    ['POST', '/documents', { name: 'zz.txt', content: 'zz' }],
    ['DELETE', '/documents/zzref', undefined],
    ['POST', '/files', { clientId: 'zz-viewer-2', name: 'zz.pdf', content: 'zz' }],
  ];
  for (const [method, path, data] of writes) {
    const response = await request.fetch(`${api}${path}`, { method, headers: envelope(), data: data === undefined ? undefined : JSON.stringify(data) });
    await expectError(response, 403, 'read_only', READ_ONLY);
  }
  for (const path of ['/memory/items', '/memory/items?q=zz', '/memory/pinned']) {
    await expectError(await request.get(`${api}${path}`), 403, 'read_only', READ_ONLY);
  }
  for (const path of ['/state', '/events?after=0&afterInstance=0', '/history/decisions', '/history/incidents', '/usage', '/documents']) {
    const response = await request.get(`${api}${path}`);
    expect(response.status(), `GET ${path}: ${await response.text()}`).toBe(200);
  }
  const after = (await (await request.get(STATE)).json()) as { chat: unknown[] };
  expect(after.chat, 'nothing the viewer sent changed the chat').toEqual((before as { chat: unknown[] }).chat);

  const signOut = await request.post(`${api}/session/end`, { headers: envelope(), data: '{}' });
  expect(signOut.status(), 'POST /v1/session/end signs the viewer out').toBe(204);
  await expectError(await request.get(STATE), 401, 'signed_out', SIGNED_OUT);
});

test('R4: the README admin lists, grants and removes a role of the target', async ({ request }) => {
  await admin(request);
  try {
    const holders = await list(request);
    const found = holders.find((one) => one.user === target());
    expect(found, 'the target holds OcuTalonUser, so it is listed').toBeDefined();
    expect(Object.keys(found!).sort()).toEqual(['managed', 'roles', 'user']);
    expect(found!.roles).toEqual(['OcuTalonUser']);
    expect(found!.managed).toBe(false);
    expect(holders.map((one) => one.user.toLowerCase()), 'sorted without regard to case').toEqual([...holders.map((one) => one.user.toLowerCase())].sort());
    const readme = holders.find((one) => one.user === README_ACCOUNT.user);
    expect(readme?.managed, 'the README account is not managed').toBe(false);

    const granted = await save(request, target(), 'OcuTalonViewer', true);
    expect(granted.status(), await granted.text()).toBe(200);
    expect(await granted.json()).toEqual({ result: 'done', changed: true });
    expect(await (await save(request, target(), 'OcuTalonViewer', true)).json(), 'the same grant again').toEqual({ result: 'done', changed: false });
    expect(await targetRoles(request)).toEqual(['OcuTalonUser', 'OcuTalonViewer']);

    expect(await (await save(request, target(), 'OcuTalonViewer', false)).json(), 'a removal').toEqual({ result: 'done', changed: true });
    expect(await (await save(request, target(), 'OcuTalonViewer', false)).json(), 'a removal of a role that is not held').toEqual({ result: 'done', changed: false });
    expect(await targetRoles(request)).toEqual(['OcuTalonUser']);
  } finally {
    await save(request, target(), 'OcuTalonViewer', false);
    await save(request, target(), 'OcuTalonApprover', false);
  }
});

test('R5: each refused role and user, and each bad shape, is 400 and changes nothing', async ({ request }) => {
  await admin(request);
  const before = await targetRoles(request);
  const refusals: Array<[string, string, string, string]> = [
    ...['OcuTalonAdmin', 'OcuTalonUser', 'OcuTalonTraceViewer', 'OcuTalonWebhook', 'OcuTalonApprover_resend', '%All', '%Manager', 'ZzNoSuchRole'].map((role): [string, string, string, string] => [target(), role, 'role', 'role']),
    ...['OcuTalonService', 'OcuTalonWorkflow', 'OcuTalonSqlReader'].map((user): [string, string, string, string] => [user, 'OcuTalonViewer', 'user', 'user_managed']),
    ...['UnknownUser', '_SYSTEM', 'SuperUser', '%zz'].map((user): [string, string, string, string] => [user, 'OcuTalonViewer', 'user', 'user_system']),
    ...['ZzNoSuchUser', '', 'z'.repeat(161)].map((user): [string, string, string, string] => [user, 'OcuTalonViewer', 'user', 'user_unknown']),
  ];
  for (const [user, role, field, reason] of refusals) {
    const response = await save(request, user, role, true);
    expect(response.status(), `${user} ${role}: ${await response.text()}`).toBe(400);
    const body = (await response.json()) as { error: { code: string; message: string }; fields: string[]; reason: string };
    expect(body.error.code).toBe('bad_settings');
    expect(body.fields, `${user} ${role}: the field`).toEqual([field]);
    expect(body.reason, `${user} ${role}: the reason`).toBe(reason);
  }
  const shapes: Array<[unknown, string[]]> = [
    [{}, ['user', 'role', 'grant']],
    [{ user: target(), role: 'OcuTalonViewer' }, ['grant']],
    [{ user: target(), role: 'OcuTalonViewer', grant: 'yes' }, ['grant']],
    [{ user: 5, role: 'OcuTalonViewer', grant: true }, ['user']],
    [{ user: target(), role: 'OcuTalonViewer', grant: true, extra: 1 }, ['extra']],
  ];
  for (const [data, fields] of shapes) {
    const response = await request.post(ROLES, { headers: envelope(), data });
    expect(response.status(), JSON.stringify(data)).toBe(400);
    const body = (await response.json()) as { error: { code: string }; fields: string[] };
    expect(body.error.code).toBe('bad_settings');
    expect(body.fields).toEqual(fields);
  }
  expect(await targetRoles(request), 'the target\'s roles are unchanged').toEqual(before);
});
