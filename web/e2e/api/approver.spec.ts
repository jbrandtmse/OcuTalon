import { expect, test, type APIRequestContext } from '../support/fixtures';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { cleanFixtureRows, fixtureUser, readApproval, seedApproval } from '../support/iris';

/**
 * Story 25.5, the role check before an answer, over real HTTP, on the stack that test-sign-in.sh seeds (the fixture role OcuTalonApprover exists with no resources;
 * ZzRoleTarget holds OcuTalonUser only, ZzApprover holds OcuTalonUser and OcuTalonApprover, and the README account holds OcuTalonUser, OcuTalonAdmin and the trace role).
 * Each request is a fixture row (seedApproval) that needs OcuTalonApprover, owned by the session that the case names, and every row is removed in `finally`.
 *   AP1  signed out, POST /v1/approvals/:ref/answer is 401 signed_out;
 *   AP2  ZzRoleTarget, with OcuTalonUser only, on its own request: /v1/state shows it with answerable false and no approver kind, an Approve is 403 not_allowed with
 *        "Only an approver can answer this request." and the request is still pending;
 *   AP3  ZzApprover, who holds the role, on ZzRoleTarget's request: 404 not_found (the owning session comes first) and still pending; on its own request: the state shows it
 *        answerable, and the Approve is 200 done;
 *   AP4  the README account's state shows its own pending request, which needs OcuTalonUser, as answerable;
 *   AP5  an email request to another address (Story 22.7's rule): the role check comes first, so ZzRoleTarget is told the fallback sentence, and ZzApprover, who passes it but
 *        is no admin, is told "Only an OcuTalon admin can approve this email." on an Approve (still pending) and has its Reject answered.
 */
const STATE = '/ocutalon/api/v1/state';
const answerPath = (ref: string): string => `/ocutalon/api/v1/approvals/${ref}/answer`;
const FALLBACK = 'Only an approver can answer this request.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const NOT_ADMIN = 'Only an OcuTalon admin can approve this email.';
const NEEDS_APPROVER = { requiredRole: 'OcuTalonApprover' };
/** An email request to another address, as Fix.Kind.Email raises it, that needs OcuTalonApprover. */
const EMAIL_REQUEST = {
  requiredRole: 'OcuTalonApprover',
  fixKind: 'email',
  fixParameters: JSON.stringify({ recipients: ['zz-partner@example.test'], subject: 'zz subject', text: 'zz text' }),
};

interface RailApproval {
  ref: string;
  state?: string;
  answerable?: boolean;
  approverKind?: string;
}

/** The pending requests of the signed-in session's rail, as /v1/state gives them. */
async function railOf(request: APIRequestContext): Promise<RailApproval[]> {
  const response = await request.get(STATE);
  expect(response.status(), await response.text()).toBe(200);
  const body = (await response.json()) as { rail: { approvals: RailApproval[] } };
  return body.rail.approvals;
}

const approve = (request: APIRequestContext, ref: string) => request.post(answerPath(ref), { headers: envelope(), data: { action: 'approve', channel: 'web' } });

test('AP1: signed out, an answer is 401 signed_out', async ({ request }) => {
  await expectError(await approve(request, 'zzapprover1'), 401, 'signed_out', SIGNED_OUT);
});

test('AP2: a user without the role sees the request as not answerable, and an Approve is 403 not_allowed with the fallback sentence, leaving it pending', async ({ request }) => {
  const rows: string[] = [];
  const target = fixtureUser('ROLETARGET');
  try {
    const ref = await seedApproval(target.user, NEEDS_APPROVER);
    rows.push(ref);
    expect((await signInOverHttp(request, target.user, target.password)).status()).toBeLessThan(400);
    const mine = (await railOf(request)).find((one) => one.ref === ref);
    expect(mine, 'the pending request is on the rail').toBeDefined();
    expect(mine?.answerable, 'it is not answerable').toBe(false);
    expect(mine?.approverKind ?? '', 'with no approver kind until the per-kind roles').toBe('');
    await expectError(await approve(request, ref), 403, 'not_allowed', FALLBACK);
    expect(await readApproval(ref).then((row) => row.state), 'the request is still pending').toBe('pending');
  } finally {
    await cleanFixtureRows(rows);
  }
});

test('AP3: the holder of the role gets 404 for another session\'s request, which stays pending, and answers its own', async ({ request }) => {
  const rows: string[] = [];
  const target = fixtureUser('ROLETARGET');
  const approver = fixtureUser('APPROVER');
  try {
    const theirs = await seedApproval(target.user, NEEDS_APPROVER);
    const own = await seedApproval(approver.user, NEEDS_APPROVER);
    rows.push(theirs, own);
    expect((await signInOverHttp(request, approver.user, approver.password)).status()).toBeLessThan(400);
    const rail = await railOf(request);
    expect(rail.find((one) => one.ref === own)?.answerable, 'its own request is answerable').toBe(true);
    expect(rail.find((one) => one.ref === theirs), 'the other session\'s request is not on its rail').toBeUndefined();
    await expectError(await approve(request, theirs), 404, 'not_found', NOT_FOUND);
    expect(await readApproval(theirs).then((row) => row.state), 'the other session\'s request is still pending').toBe('pending');
    const done = await approve(request, own);
    expect(done.status(), await done.text()).toBe(200);
    expect(((await done.json()) as { result: string }).result).toBe('done');
    expect(await readApproval(own).then((row) => row.state), 'its own request is approved').toBe('approved');
  } finally {
    await cleanFixtureRows(rows);
  }
});

test('AP4: the README account\'s own pending request, which needs OcuTalonUser, is answerable in its state', async ({ request }) => {
  const rows: string[] = [];
  try {
    const ref = await seedApproval(README_ACCOUNT.user, { requiredRole: 'OcuTalonUser' });
    rows.push(ref);
    expect((await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password)).status()).toBeLessThan(400);
    const mine = (await railOf(request)).find((one) => one.ref === ref);
    expect(mine, 'the pending request is on the rail').toBeDefined();
    expect(mine?.answerable, 'it is answerable').toBe(true);
    expect(mine?.approverKind ?? '', 'with no approver kind').toBe('');
  } finally {
    await cleanFixtureRows(rows);
  }
});

test('AP5: an email to another address: the role check comes first, and a holder who is no admin is told so on an Approve and answered on a Reject', async ({ request }) => {
  const rows: string[] = [];
  const target = fixtureUser('ROLETARGET');
  const approver = fixtureUser('APPROVER');
  try {
    const lacking = await seedApproval(target.user, EMAIL_REQUEST);
    const held = await seedApproval(approver.user, EMAIL_REQUEST);
    rows.push(lacking, held);
    expect((await signInOverHttp(request, target.user, target.password)).status()).toBeLessThan(400);
    await expectError(await approve(request, lacking), 403, 'not_allowed', FALLBACK);
    expect(await readApproval(lacking).then((row) => row.state), 'the request of the user without the role is still pending').toBe('pending');
    expect((await request.post('/ocutalon/api/v1/session/end', { headers: envelope(), data: '{}' })).status()).toBe(204);

    expect((await signInOverHttp(request, approver.user, approver.password)).status()).toBeLessThan(400);
    await expectError(await approve(request, held), 403, 'not_allowed', NOT_ADMIN);
    expect(await readApproval(held).then((row) => row.state), 'the request of the holder who is no admin is still pending').toBe('pending');
    const rejected = await request.post(answerPath(held), { headers: envelope(), data: { action: 'reject', channel: 'web' } });
    expect(rejected.status(), await rejected.text()).toBe(200);
    expect(await readApproval(held).then((row) => row.state), 'its Reject is answered').toBe('rejected');
  } finally {
    await cleanFixtureRows(rows);
  }
});
