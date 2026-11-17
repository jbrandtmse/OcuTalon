import { expect, test, type APIRequestContext, type APIResponse } from '../support/fixtures';

import { README_ACCOUNT, envelope, signInOverHttp } from '../sign-in/helpers';
import { readmeSession } from '../support/demo-path';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';

/**
 * Story 27.3, the Slack settings routes over real HTTP, on the stack that test-sign-in.sh seeds (a local install with Slack off: no SLACK_* variable). The README
 * account holds OcuTalonAdmin; the LIVE fixture user holds OcuTalonUser only. The workspace that SlackIn would note from a signed event is seeded with
 * Data.SlackLink NoteWorkspace and removed after each case, and every case unlinks the members it linked.
 *   SL1  with no noted workspace a link is refused 400 bad_slack_link no_workspace, with its ruled text, no field, no audit entry and no row;
 *   SL2  the README admin lists (state off, the path, no links, the README user offered), links the README user (200, the link's Ref, user and member, the member
 *        trimmed and upper-cased), sees it listed, links the same pair again (the same Ref), is refused for each reason (a malformed member, an unknown user, a member
 *        taken by another user, a user who has another member) with the reason's text and field, is refused 400 bad_settings for a body of another shape, gets 404 for an
 *        unknown Ref, and unlinks (200, the row gone, the list empty); the link and the unlink are each one Settings entry (slackLink.<Ref>, from nothing to the user
 *        and back), the link reaches the user's one durable session, and no audit entry holds the member id or the team id;
 *   SL3  the LIVE OcuTalonUser gets 403 not_admin on GET, POST and DELETE, with the member and the Ref never read, and changes nothing.
 * Second-session isolation: not applicable (an install-wide admin setting, not session-owned data).
 */
const SLACK = '/ocutalon/api/v1/settings/channels/slack';
const TEAM = 'T0E2E0001';
const NOT_ADMIN = 'Only OcuTalon admins can open settings.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const BAD_SETTINGS = "Couldn't save. Nothing was changed.";
const LINKED = 'Linked. Their direct messages to the bot now reach OcuTalon. Recorded in the audit log.';
const UNLINKED = 'Unlinked. Their messages no longer reach OcuTalon. Recorded in the audit log.';
const BAD_MEMBER = 'Enter a Slack member ID such as U012AB3CDE: a U or W followed by letters and digits. Nothing was changed.';
const MEMBER_TAKEN = 'That Slack member is already linked to another user. Nothing was changed.';
const NO_WORKSPACE = "OcuTalon hasn't had an event from your Slack workspace yet. Ask the person to send the bot a direct message, then link them. Nothing was changed.";
const UNKNOWN_USER = 'Choose an OcuTalon user from the list. Nothing was changed.';

interface Link {
  ref: string;
  user: string;
  member: string;
}

interface Listed {
  state: string;
  path: string;
  links: Link[];
  users: string[];
}

/** A unique tag for the case's member ids: letters and digits, upper case. */
const tag = (): string => `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`.toUpperCase();

/** An admin context signed in as the README account, which has a session row afterwards. */
async function admin(request: APIRequestContext): Promise<APIRequestContext> {
  const response = await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  expect(response.status(), 'the README account signs in').toBeLessThan(400);
  expect((await request.get('/ocutalon/api/v1/state')).status(), 'and loads its state').toBe(200);
  return request;
}

/** The refusal body of a bad_slack_link answer, after checking its status. */
async function expectRefused(response: APIResponse, reason: string, fields: string[], message: string): Promise<void> {
  expect(response.status(), await response.text()).toBe(400);
  const body = (await response.json()) as { error: { code: string; message: string }; fields: string[]; reason: string };
  expect(body.error, `${reason}: the error`).toEqual({ code: 'bad_slack_link', message });
  expect(body.fields, `${reason}: the fields`).toEqual(fields);
  expect(body.reason, `${reason}: the reason`).toBe(reason);
}

async function expectPlain(response: APIResponse, status: number, code: string, message: string): Promise<void> {
  expect(response.status(), await response.text()).toBe(status);
  expect(((await response.json()) as { error: { code: string; message: string } }).error).toEqual({ code, message });
}

/** The rows of the link table of the e2e workspace, as "member|session" lines. */
async function rows(): Promise<string[]> {
  const lines = await irisScript(
    [
      `Set n=0,id="" For { Set id=$Order(^OcuTalonP.SlackLinkD(id)) Quit:id=""  Set r=##class(OcuTalon.Data.SlackLink).%OpenId(id) If $IsObject(r),r.TeamId=${quoted(TEAM)} { Set n=n+1 Write !,"CHK|r"_n_"|",r.MemberId_"|"_r.SessionRef } }`,
      'Write !,"CHK|n|",n',
    ].join('\n'),
  );
  const count = Number(chk(lines, 'n') ?? '-1');
  expect(count, 'the link rows could be read').toBeGreaterThanOrEqual(0);
  return Array.from({ length: count }, (_, i) => chk(lines, `r${i + 1}`) ?? '');
}

/** Notes the e2e workspace, or removes the noted one. */
async function workspace(on: boolean): Promise<void> {
  const lines = await irisScript(on ? `Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace(${quoted(TEAM)}) Write !,"CHK|w|",##class(OcuTalon.Data.SlackLink).Workspace()` : 'Kill ^OcuTalonP.SlackW Write !,"CHK|w|"');
  expect(chk(lines, 'w'), 'the workspace is as set').toBe(on ? TEAM : '');
}

/** Removes every link row of the e2e workspace. */
async function dropLinks(): Promise<void> {
  const lines = await irisScript(`Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId = ?",${quoted(TEAM)}) Write !,"CHK|dropped|1"`);
  expect(chk(lines, 'dropped')).toBe('1');
}

/** The audit clock now, in the form that auditSince takes. */
async function auditMark(): Promise<string> {
  const mark = chk(await irisScript('Write !,"CHK|now|",##class(OcuTalon.Test.Bridge.AuditLog).Now()'), 'now');
  expect(mark, 'the audit clock').toBeTruthy();
  return mark as string;
}

/** The Settings entries of slackLink.* written at or after the mark, oldest first, as "setting|from|to|channel" lines: waits up to `seconds` for `count` of them. */
async function slackAudit(mark: string, count: number, seconds = 30): Promise<string[]> {
  const lines = await irisScript(
    [
      `Set e=##class(OcuTalon.Test.Bridge.AuditLog).Wait(${quoted(mark)},"OcuTalon","Settings","","slackLink.","",${count},${seconds})`,
      'Write !,"CHK|n|",e.%Size()',
      'For i=0:1:e.%Size()-1 { Set d=e.%Get(i).data Write !,"CHK|e"_i_"|",d.setting_"|"_d.from_"|"_d.to_"|"_d.channel }',
    ].join('\n'),
  );
  const found = Number(chk(lines, 'n') ?? '-1');
  expect(found, 'the audit entries could be read').toBeGreaterThanOrEqual(0);
  return Array.from({ length: found }, (_, i) => chk(lines, `e${i}`) ?? '');
}

/** The number of Settings audit entries since the mark that hold the text anywhere in their data or description. */
async function auditHolding(mark: string, text: string): Promise<number> {
  const lines = await irisScript(
    [
      `Set e=##class(OcuTalon.Test.Bridge.AuditLog).Entries(${quoted(mark)},"OcuTalon","Settings","","","")`,
      `Set hits=0 For i=0:1:e.%Size()-1 { If e.%Get(i).%ToJSON()[${quoted(text)} Set hits=hits+1 }`,
      'Write !,"CHK|hits|",hits',
    ].join('\n'),
  );
  return Number(chk(lines, 'hits') ?? '-1');
}

test('SL1: with no noted workspace a link is refused no_workspace, with no audit entry and no row', async ({ request }) => {
  test.setTimeout(120_000);
  const member = `U0E2E${tag()}`;
  try {
    await admin(request);
    await workspace(false);
    const mark = await auditMark();
    const list = (await (await request.get(SLACK)).json()) as Listed;
    expect(list.state, 'a stack with no SLACK_* variable has Slack off').toBe('off');
    expect(list.path).toBe('/ocutalon/hook/slack/events');
    const response = await request.post(SLACK, { headers: envelope(), data: { user: README_ACCOUNT.user, member } });
    await expectRefused(response, 'no_workspace', [], NO_WORKSPACE);
    expect(await rows(), 'no row was made').toEqual([]);
    expect(await slackAudit(mark, 0, 1), 'and no audit entry was written').toEqual([]);
  } finally {
    await dropLinks();
    await workspace(false);
  }
});

test('SL2: the README admin lists, links, is refused for each reason, and unlinks', async ({ request, playwright, baseURL }) => {
  test.setTimeout(240_000);
  const member = `U0E2E${tag()}`;
  const other = `W0E2E${tag()}`;
  const live = fixtureUser('LIVE');
  const liveContext = await playwright.request.newContext({ baseURL });
  try {
    await admin(request);
    const signedIn = await signInOverHttp(liveContext, live.user, live.password);
    expect(signedIn.status(), 'the LIVE user signs in').toBeLessThan(400);
    expect((await liveContext.get('/ocutalon/api/v1/state')).status(), 'and has a session').toBe(200);
    await dropLinks();
    await workspace(true);
    const mark = await auditMark();
    const session = await readmeSession();

    const empty = (await (await request.get(SLACK)).json()) as Listed;
    expect(empty.links.filter((one) => one.member === member), 'the member is not listed yet').toEqual([]);
    expect(empty.users, 'the README user and the LIVE user are offered').toEqual(expect.arrayContaining([README_ACCOUNT.user, live.user]));
    expect(Object.keys(empty).sort(), 'the list holds the state, the path, the links and the users').toEqual(['links', 'path', 'state', 'users']);

    // The link: the member typed with spaces and in lower case is stored trimmed and upper-cased.
    const linked = await request.post(SLACK, { headers: envelope(), data: { user: README_ACCOUNT.user, member: ` ${member.toLowerCase()} ` } });
    expect(linked.status(), await linked.text()).toBe(200);
    const answer = (await linked.json()) as { result: string; message: string; link: Link };
    expect(answer.result).toBe('done');
    expect(answer.message).toBe(LINKED);
    expect(answer.link.member).toBe(member);
    expect(answer.link.user).toBe(README_ACCOUNT.user);
    expect(answer.link.ref).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(Object.keys(answer.link).sort(), 'only ref, user and member').toEqual(['member', 'ref', 'user']);
    expect(await rows(), 'one row, in the README account\'s own session').toEqual([`${member}|${session.ref}`]);
    const afterLink = (await (await request.get(SLACK)).json()) as Listed;
    expect(afterLink.links, 'the list shows it').toEqual([answer.link]);

    // The same pair again is the same link.
    const again = await request.post(SLACK, { headers: envelope(), data: { user: README_ACCOUNT.user, member } });
    expect(again.status(), await again.text()).toBe(200);
    expect(((await again.json()) as { link: Link }).link.ref, 'the same Ref').toBe(answer.link.ref);
    expect(await rows(), 'and still one row').toHaveLength(1);

    // Each refusal reason.
    await expectRefused(await request.post(SLACK, { headers: envelope(), data: { user: live.user, member } }), 'member_taken', ['member'], MEMBER_TAKEN);
    await expectRefused(
      await request.post(SLACK, { headers: envelope(), data: { user: README_ACCOUNT.user, member: other } }),
      'user_taken',
      ['user'],
      `${README_ACCOUNT.user} already has a linked Slack member. Unlink it first. Nothing was changed.`,
    );
    await expectRefused(await request.post(SLACK, { headers: envelope(), data: { user: live.user, member: 'X1' } }), 'bad_member', ['member'], BAD_MEMBER);
    await expectRefused(await request.post(SLACK, { headers: envelope(), data: { user: `zz-nobody-${member}`, member: other } }), 'user_unknown', ['user'], UNKNOWN_USER);
    expect(await rows(), 'no refusal made or changed a row').toEqual([`${member}|${session.ref}`]);

    // The shapes of a body, and an unknown Ref.
    for (const data of [{ user: README_ACCOUNT.user }, { member }, { user: README_ACCOUNT.user, member, team: TEAM }, { user: 5, member }]) {
      const bad = await request.post(SLACK, { headers: envelope(), data });
      await expectPlain(bad, 400, 'bad_settings', BAD_SETTINGS);
    }
    await expectPlain(await request.delete(`${SLACK}/AAAAAAAAAAAAAAAAAAAAAA`, { headers: envelope(), data: {} }), 404, 'not_found', NOT_FOUND);
    await expectPlain(await request.delete(`${SLACK}/${'A'.repeat(40)}`, { headers: envelope(), data: {} }), 404, 'not_found', NOT_FOUND);
    expect(await rows(), 'nor did they').toHaveLength(1);

    // The unlink.
    const removed = await request.delete(`${SLACK}/${answer.link.ref}`, { headers: envelope(), data: {} });
    expect(removed.status(), await removed.text()).toBe(200);
    expect(await removed.json()).toEqual({ result: 'done', message: UNLINKED });
    expect(await rows(), 'the row is gone').toEqual([]);
    const afterUnlink = (await (await request.get(SLACK)).json()) as Listed;
    expect(afterUnlink.links.filter((one) => one.member === member), 'and the list no longer shows it').toEqual([]);
    await expectPlain(await request.delete(`${SLACK}/${answer.link.ref}`, { headers: envelope(), data: {} }), 404, 'not_found', NOT_FOUND);

    // The audit: the link twice (the repeat is audited as a link) and the unlink once, each naming the user and never an id.
    const entries = await slackAudit(mark, 3);
    expect(entries, 'three Settings entries: two links and one unlink').toEqual([
      `slackLink.${answer.link.ref}||${README_ACCOUNT.user}|web`,
      `slackLink.${answer.link.ref}||${README_ACCOUNT.user}|web`,
      `slackLink.${answer.link.ref}|${README_ACCOUNT.user}||web`,
    ]);
    for (const id of [member, other, TEAM]) {
      expect(await auditHolding(mark, id), `no audit entry holds ${id}`).toBe(0);
    }
  } finally {
    await liveContext.dispose();
    await dropLinks();
    await workspace(false);
  }
});

test('SL3: the LIVE OcuTalonUser is 403 not_admin on every route and changes nothing', async ({ request, playwright, baseURL }) => {
  test.setTimeout(120_000);
  const member = `U0E2E${tag()}`;
  const live = fixtureUser('LIVE');
  const liveContext = await playwright.request.newContext({ baseURL });
  try {
    await admin(request);
    await dropLinks();
    await workspace(true);
    const mark = await auditMark();
    const linked = await request.post(SLACK, { headers: envelope(), data: { user: README_ACCOUNT.user, member } });
    expect(linked.status(), await linked.text()).toBe(200);
    const ref = ((await linked.json()) as { link: Link }).link.ref;
    const before = await rows();
    expect(before).toHaveLength(1);

    expect((await signInOverHttp(liveContext, live.user, live.password)).status(), 'the LIVE user signs in').toBeLessThan(400);
    const wanted = { error: { code: 'not_admin', message: NOT_ADMIN } };
    const answers = [
      await liveContext.get(SLACK),
      await liveContext.post(SLACK, { headers: envelope(), data: { user: live.user, member: `W0E2E${tag()}` } }),
      await liveContext.delete(`${SLACK}/${ref}`, { headers: envelope(), data: {} }),
    ];
    for (const response of answers) {
      expect(response.status(), `${response.url()} is 403 for the LIVE user`).toBe(403);
      expect(await response.json(), 'not_admin').toEqual(wanted);
    }
    expect(await rows(), 'the LIVE user changed nothing').toEqual(before);
    expect(await slackAudit(mark, 1), 'and only the admin\'s link was audited').toHaveLength(1);
  } finally {
    await liveContext.dispose();
    await dropLinks();
    await workspace(false);
  }
});
