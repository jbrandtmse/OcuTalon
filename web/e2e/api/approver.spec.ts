import { expect, test, type APIRequestContext } from '../support/fixtures';

import { README_ACCOUNT, envelope, expectError, signInOverHttp } from '../sign-in/helpers';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted, readApproval, seedApproval } from '../support/iris';

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
 *   AP6  a partner warning to Settings contacts (DW-1415, Fix.Kind.Email MayApprove): the LIVE user, who holds OcuTalonUser only, is told the same email sentence on an
 *        Approve of its own warning, the request stays pending and unanswered (so nothing is sent or kept), and one Action entry records the refusal with ids only; the
 *        README admin's Approve of its own warning is 200 done and approved by the admin.
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

/** A partner warning's name, address and notice, which a refusal must never put in an audit entry. */
const PARTNER_NAME = 'Zz Partner Http Name';
const PARTNER_ADDRESS = 'zz-partner-http@example.test';
const PARTNER_NOTICE = 'Zz partner http notice text.';

/**
 * A pending partner warning to the Settings contacts 7 and 8, owned by the user's session and needing OcuTalonUser, as IncidentManager stores it: the ids in the targets and
 * the parameters, the names and addresses only in the dry run, and simulated 0.
 */
async function seedPartnerWarning(user: string): Promise<string> {
  const ref = await seedApproval(user, { requiredRole: 'OcuTalonUser', fixKind: 'partner_warning', fixParameters: JSON.stringify({ text: PARTNER_NOTICE, to: '7,8' }) });
  const dryRun = JSON.stringify({
    notice: PARTNER_NOTICE,
    recipients: [
      { id: 7, name: PARTNER_NAME, address: PARTNER_ADDRESS },
      { id: 8, name: `${PARTNER_NAME} 2`, address: `two.${PARTNER_ADDRESS}` },
    ],
    simulated: 0,
  });
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(${quoted(ref)})`,
      'If \'$IsObject(r) { Write !,"CHK|set|0" Halt }',
      'Set r.FixTargets="7,8"',
      `Set r.DryRun=${quoted(dryRun)}`,
      'Write !,"CHK|set|",$System.Status.IsOK(r.%Save())',
    ].join('\n'),
  );
  if (chk(lines, 'set') !== '1') throw new Error(`the partner warning could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** The audit clock now, in the form that refusalAudit takes. */
async function auditNow(): Promise<string> {
  const mark = chk(await irisScript('Write !,"CHK|now|",##class(OcuTalon.Test.Bridge.AuditLog).Now()'), 'now');
  expect(mark, 'the audit clock').toBeTruthy();
  return mark as string;
}

/** The Action entries that name the request, written at or after the mark (waits up to 20 s for one): each as its data's fields and its whole text. */
async function refusalAudit(mark: string, ref: string): Promise<Array<{ fields: string; text: string }>> {
  const lines = await irisScript(
    [
      `Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(${quoted(mark)},"OcuTalon","Action","Action",${quoted(ref)},"",1,20)`,
      'Write !,"CHK|n|",e.%Size()',
      'For i=0:1:e.%Size()-1 { Set d=e.%Get(i).data Write !,"CHK|f"_i_"|",d.action_"|"_d.result_"|"_d.approvalRef_"|"_d.channel_"|"_d.irisUser_"|"_d.target_"|"_d.counts.contacts Write !,"CHK|t"_i_"|",d.%ToJSON()_e.%Get(i).description }',
    ].join('\n'),
  );
  const found = Number(chk(lines, 'n') ?? '-1');
  expect(found, 'the audit entries could be read').toBeGreaterThanOrEqual(0);
  const entries: Array<{ fields: string; text: string }> = [];
  for (let i = 0; i < found; i += 1) entries.push({ fields: chk(lines, `f${i}`) ?? '', text: chk(lines, `t${i}`) ?? '' });
  return entries;
}

test('AP6: a partner warning to Settings contacts: the LIVE user is told the email sentence on an Approve and it stays pending, the refusal is audited with ids only, and the admin approves', async ({ request }) => {
  const rows: string[] = [];
  const live = fixtureUser('LIVE');
  try {
    const own = await seedPartnerWarning(live.user);
    const admins = await seedPartnerWarning(README_ACCOUNT.user);
    rows.push(own, admins);
    const mark = await auditNow();
    expect((await signInOverHttp(request, live.user, live.password)).status()).toBeLessThan(400);
    await expectError(await approve(request, own), 403, 'not_allowed', NOT_ADMIN);
    const after = await readApproval(own);
    // A request runs, sends or is kept as an approved draft only once it is approved, so pending and unanswered is what says nothing was sent or kept (a fixture row has no hold, so a
    // count of its Delivery and FixRun rows would stay 0 even if it were approved).
    expect(`${after.state}|${after.action}|${after.by}`, 'the LIVE user\'s warning is still pending and unanswered, so nothing was sent or kept').toBe('pending||');
    const entries = await refusalAudit(mark, own);
    expect(entries.length, 'one Action entry names the refused request').toBe(1);
    expect(entries[0]?.fields, 'it names the action, the outcome, the request, the channel, the user and the contact ids').toBe(`partner_warning|refused|${own}|web|${live.user}|partner contacts (7,8)|2`);
    const text = entries[0]?.text ?? '';
    expect([text.includes(PARTNER_NAME), text.includes(PARTNER_ADDRESS), text.includes(PARTNER_NOTICE)], 'and holds no name, address or notice').toEqual([false, false, false]);
    expect((await request.post('/ocutalon/api/v1/session/end', { headers: envelope(), data: '{}' })).status()).toBe(204);

    expect((await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password)).status()).toBeLessThan(400);
    const done = await approve(request, admins);
    expect(done.status(), await done.text()).toBe(200);
    expect(((await done.json()) as { result: string }).result, 'the admin\'s Approve is done').toBe('done');
    const approved = await readApproval(admins);
    expect(`${approved.state}|${approved.by}|${approved.channel}`, 'the admin\'s warning is approved by the admin on the web').toBe(`approved|${README_ACCOUNT.user}|web`);
  } finally {
    await cleanFixtureRows(rows);
  }
});
