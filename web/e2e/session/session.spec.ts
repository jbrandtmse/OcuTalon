import { expect, test, type APIRequestContext, type Page } from '@playwright/test';

import { noRoleAccount, signIn, submitSignIn } from '../sign-in/helpers';
import { chk, fixtureUser, irisScript } from '../support/iris';

/**
 * Story 2.2, the session (S1 to S7), in a real browser and over HTTP against a real stack. The users are the fixture users
 * that test-sign-in.sh created: OCUTALON_SESSION_USER (the user role and the trace role), and OCUTALON_SIGNIN_USER, which
 * nothing signs in before S4; and the fixture user without roles, whom S6 signs in. The browser envelope of a state-changing call is the JSON content type, the header
 * X-OcuTalon-Request: 1 and the Origin of the page; an APIRequestContext sends no Origin by itself, so every POST made
 * here sets the stack's own.
 */
const STATE = '/ocutalon/api/v1/state';
const API = '/ocutalon/api/';
const END = '/ocutalon/api/v1/session/end';
const TRACE = '/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen';
const SIGN_IN_TITLE = 'Sign in \u00b7 OcuTalon';
const SIGNED_OUT = 'You were signed out. Sign in again to continue.';
const CREDENTIALS = "That user name and password didn't work.";

const isPath = (url: string, path: string): boolean => new URL(url).pathname === path;
const mainOf = (page: Page) => page.locator('main.main');

/** The origin of the stack under test, which a same-origin POST of the page carries as its Origin header. */
function stackOrigin(): string {
  const url = process.env['OCUTALON_URL'];
  if (!url) throw new Error('OCUTALON_URL must name the stack');
  return new URL(url).origin;
}

/** The whole browser envelope of a state-changing call, with the parts that a case overrides. */
function envelope(overrides: Record<string, string | undefined> = {}): Record<string, string> {
  const headers: Record<string, string | undefined> = {
    'content-type': 'application/json',
    'x-ocutalon-request': '1',
    origin: stackOrigin(),
    ...overrides,
  };
  return Object.fromEntries(Object.entries(headers).filter((entry): entry is [string, string] => entry[1] !== undefined));
}

/** Signs a user in over HTTP, the way a script does: the sign-in page of the path, then the three fields of its form. */
async function signInOverHttp(request: APIRequestContext, user: string, password: string, path = '/ocutalon/'): Promise<void> {
  await request.get(path);
  await request.post(path, { form: { IRISUsername: user, IRISPassword: password, IRISLogin: 'Sign in' } });
}

/** The fields of a snapshot that Sign out must not change. */
interface Kept {
  epoch: string;
  chat: unknown;
  rail: { approvals: unknown[]; checks: Array<{ ref: string }>; reminders: Array<{ ref: string }>; decisions: unknown[] };
}

function kept(body: Kept): Kept {
  return { epoch: body.epoch, chat: body.chat, rail: body.rail };
}

/** Deletes the durable session rows of an IRIS user, so that a case starts from a user with no session. */
async function dropSessionRows(user: string): Promise<void> {
  await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM OcuTalon_Data.Session WHERE IrisUser = ?","${user}")`,
      'While rs.%Next() { Set ids(rs.%Get("ID"))="" }',
      'Set id="" For { Set id=$Order(ids(id))  Quit:id=""  Do ##class(OcuTalon.Data.Session).%DeleteId(id) }',
      'Write !,"CHK|dropped|1"',
    ].join('\n'),
  );
}

/** The session rows of an IRIS user: their Refs, and how many there are. */
async function sessionRows(user: string): Promise<{ refs: string[]; count: number }> {
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser = ?","${user}")`,
      'Set n=0',
      'While rs.%Next() { Set n=n+1 Write !,"CHK|ref|",rs.%Get("Ref") }',
      'Write !,"CHK|count|",n',
    ].join('\n'),
  );
  return { refs: lines.filter((line) => line.startsWith('CHK|ref|')).map((line) => line.slice('CHK|ref|'.length)), count: Number(chk(lines, 'count')) };
}

/** S1: Sign out goes through the API with the whole envelope; signing in again gives the same epoch, chat and rail. */
test('S1: Sign out ends the session through the API, and signing in again restores the same conversation and rail', async ({ page }) => {
  const { user, password } = fixtureUser('SESSION');
  const seeded = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser("${user}",.sc)`,
      'Write !,"CHK|turn|",##class(OcuTalon.Test.Data.Fixture).Turn(s.Ref)',
      'Write !,"CHK|check|",##class(OcuTalon.Test.Data.Fixture).Check(s.Ref)',
      'Write !,"CHK|reminder|",##class(OcuTalon.Test.Data.Fixture).Reminder(s.Ref)',
    ].join('\n'),
  );
  const turn = chk(seeded, 'turn');
  const check = chk(seeded, 'check');
  const reminder = chk(seeded, 'reminder');
  expect(turn && check && reminder, `the fixture rows are seeded (${seeded.join(' ')})`).toBeTruthy();

  const firstState = page.waitForResponse((response) => isPath(response.url(), STATE));
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const before = kept((await (await firstState).json()) as Kept);
  expect(JSON.stringify(before.chat), "the seeded turn is in the chat").toContain(turn!);
  expect(before.rail.checks.map((row) => row.ref), 'the seeded check is in the rail').toContain(check!);
  expect(before.rail.reminders.map((row) => row.ref), 'the seeded reminder is in the rail').toContain(reminder!);

  const sent = page.waitForRequest((request) => isPath(request.url(), END));
  const answered = page.waitForResponse((response) => isPath(response.url(), END));
  await page.getByRole('button', { name: user, exact: true }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  const request = await sent;
  const headers = await request.allHeaders();
  expect(request.method()).toBe('POST');
  expect(headers['content-type'], 'the JSON content type').toContain('application/json');
  expect(headers['x-ocutalon-request'], 'the request header').toBe('1');
  expect(headers['origin'], "and the page's own origin").toBe(stackOrigin());
  expect((await answered).status(), 'the server answers 204').toBe(204);

  await expect(page).toHaveTitle(SIGN_IN_TITLE);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sign in to OcuTalon');
  expect((await page.request.get(STATE)).status(), 'the API session ended').toBe(401);
  const trace = await page.request.get(TRACE);
  expect(await trace.text(), 'and the trace application asks for a password').toContain('name="IRISPassword"');

  const secondState = page.waitForResponse((response) => isPath(response.url(), STATE));
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const after = kept((await (await secondState).json()) as Kept);
  expect(after, 'the epoch, the chat and the rail are the same after signing in again').toEqual(before);
});

/** S2: without the JSON type, or without the header, the sign-out call is refused and the session stays signed in. */
test('S2: POST /session/end without the envelope is refused, and the session stays', async ({ request }) => {
  const { user, password } = fixtureUser('SESSION');
  await signInOverHttp(request, user, password);
  expect((await request.get(STATE)).status()).toBe(200);

  const notJson = await request.post(END, { headers: envelope({ 'content-type': 'text/plain' }), data: '{}' });
  expect(notJson.status()).toBe(403);
  expect(((await notJson.json()) as { error: { code: string } }).error.code).toBe('not_json');
  const noHeader = await request.post(END, { headers: envelope({ 'x-ocutalon-request': undefined }), data: '{}' });
  expect(noHeader.status()).toBe(403);
  expect(((await noHeader.json()) as { error: { code: string } }).error.code).toBe('no_request_header');

  expect((await request.get(STATE)).status(), 'the session is still signed in').toBe(200);
});

/**
 * S3: the session ends somewhere else. The page's next call is answered 401, and the page goes to the sign-in page, which
 * shows the signed-out notice. A wrong password then shows the credentials error instead.
 */
test('S3: a 401 shows the sign-in page with the signed-out notice, and a wrong password then shows the credentials error', async ({ page }) => {
  const { user, password } = fixtureUser('SESSION');
  const log: string[] = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith(API)) log.push(`request ${request.method()} ${new URL(request.url()).pathname}`);
  });
  page.on('response', (response) => {
    if (new URL(response.url()).pathname.startsWith(API)) log.push(`response ${response.status()} ${new URL(response.url()).pathname}`);
  });

  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');

  const ended = await page.context().request.post(END, { headers: envelope(), data: '{}' });
  expect(ended.status(), 'the session is ended from outside the page').toBe(204);

  await expect(page).toHaveTitle(SIGN_IN_TITLE, { timeout: 10_000 });
  await expect(page.locator('#ocu-error')).toHaveText(SIGNED_OUT);
  expect(page.url(), 'the sign-in page keeps the application address and the hash').toMatch(/\/ocutalon\/\?signedOut=1#\//);
  const firstUnauthorized = log.findIndex((line) => line.startsWith('response 401'));
  expect(firstUnauthorized, 'the page met a 401').toBeGreaterThanOrEqual(0);
  expect(log.slice(firstUnauthorized + 1).filter((line) => line.startsWith('request')), 'no API call after the first 401').toEqual([]);

  await page.getByLabel('User name').fill(user);
  await page.getByLabel('Password', { exact: true }).fill('not-the-password');
  await submitSignIn(page);
  await expect(page.locator('#ocu-error'), 'a wrong password shows the credentials error instead').toHaveText(CREDENTIALS);
});

/**
 * S3: after the first 401 the page makes no API call at all. The sign-in page's navigation is cancelled here, so that the old
 * page lives on and the user can press Sign out (which would call the API) and the polls could go on; none of them sends a
 * request.
 */
test('S3: after the first 401 the page makes no further API call, whatever the user presses', async ({ page }) => {
  const { user, password } = fixtureUser('SESSION');
  const log: string[] = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith(API)) log.push(`request ${request.method()} ${new URL(request.url()).pathname}`);
  });
  page.on('response', (response) => {
    if (new URL(response.url()).pathname.startsWith(API)) log.push(`response ${response.status()} ${new URL(response.url()).pathname}`);
  });
  let navigations = 0;
  await page.route(/\/ocutalon\/\?signedOut=1/, async (route) => {
    navigations += 1;
    await route.abort('aborted');
  });

  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const ended = await page.context().request.post(END, { headers: envelope(), data: '{}' });
  expect(ended.status(), 'the session is ended from outside the page').toBe(204);

  await expect.poll(() => navigations, { timeout: 10_000, message: 'after the 401 the page goes to the sign-in page' }).toBe(1);
  const firstUnauthorized = log.findIndex((line) => line.startsWith('response 401'));
  expect(firstUnauthorized, 'the page met a 401').toBeGreaterThanOrEqual(0);

  await page.getByRole('button', { name: user, exact: true }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await page.waitForTimeout(3500);
  expect(log.slice(firstUnauthorized + 1).filter((line) => line.startsWith('request')), 'no API call after the first 401').toEqual([]);
  expect(navigations, 'and the page went to the sign-in page once').toBe(1);
});

/** S4: the first sign-in creates the user's one durable session at sign-in, with no API call; the next finds the same Ref. */
test("S4: signing in creates the user's session row, and a second sign-in finds the same one", async ({ playwright, baseURL }) => {
  const { user, password } = fixtureUser('SIGNIN');
  const none = await sessionRows(user);
  expect(none.count, 'nothing has signed this user in before').toBe(0);

  const first = await playwright.request.newContext({ baseURL });
  await signInOverHttp(first, user, password);
  const created = await sessionRows(user);
  expect(created.count, 'the sign-in alone created the row').toBe(1);
  expect(created.refs[0]).toMatch(/^[A-Za-z0-9_-]{22}$/);

  const second = await playwright.request.newContext({ baseURL });
  await signInOverHttp(second, user, password);
  const again = await sessionRows(user);
  expect(again.count, 'a later sign-in reuses it').toBe(1);
  expect(again.refs[0], 'with the same Ref').toBe(created.refs[0]);
  await first.dispose();
  await second.dispose();
});

/** S5: a sign-in at a trace application carries to /ocutalon, whose first API call attaches the user's session. */
test('S5: a group sign-in from a trace application opens the page and the API', async ({ page }) => {
  const { user, password } = fixtureUser('SESSION');
  await dropSessionRows(user);
  expect((await sessionRows(user)).count, 'the user starts with no durable session').toBe(0);
  await page.goto(TRACE);
  await page.locator('input[name=IRISUsername]').fill(user);
  await page.locator('input[name=IRISPassword]').fill(password);
  await page.locator('input[name=IRISPassword]').press('Enter');
  await expect(page, 'the trace application opens').toHaveTitle(/Message Viewer/);
  await page.goto('/ocutalon/');
  await expect(page.getByLabel('User name'), 'no sign-in form').toHaveCount(0);
  await expect(page).toHaveTitle('OcuTalon');
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const state = await page.request.get(STATE);
  expect(state.status()).toBe(200);
  const body = (await state.json()) as { user: string };
  expect(body.user.toLowerCase(), "the snapshot is the user's own").toBe(user.toLowerCase());
  expect((await sessionRows(user)).count, "the group sign-in's session is the user's one durable session").toBe(1);
});

/** S6: a user without the OcuTalon user role is shown the no-role page, and no durable session is created for them. */
test('S6: a user without the user role holds no session row', async ({ playwright, baseURL }) => {
  const { user, password } = noRoleAccount();
  const context = await playwright.request.newContext({ baseURL });
  await context.get('/ocutalon/');
  const answer = await context.post('/ocutalon/', { form: { IRISUsername: user, IRISPassword: password, IRISLogin: 'Sign in' } });
  expect(await answer.text(), 'the sign-in reached the no-role page').toContain('have the OcuTalon user role');
  expect((await sessionRows(user)).count, 'and created no row').toBe(0);
  await context.dispose();
});

/** S7: when the sign-out call fails with anything but a 401, the page leaves through IRIS's own sign-out, so Sign out always works. */
test("S7: a failed sign-out call falls back to IRIS's own sign-out", async ({ page }) => {
  const { user, password } = fixtureUser('SESSION');
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await page.route(`**${END}`, (route) =>
    route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } }),
  );

  const fallback = page.waitForRequest((request) => request.url().includes('IRISLogout=end'));
  await page.getByRole('button', { name: user, exact: true }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await fallback;
  await expect(page).toHaveTitle(SIGN_IN_TITLE);
  expect((await page.request.get(STATE)).status(), 'the session ended').toBe(401);
});
