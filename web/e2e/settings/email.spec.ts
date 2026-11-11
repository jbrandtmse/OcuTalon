import { randomBytes } from 'node:crypto';

import { expect, test, type Locator, type Page } from '../support/fixtures';

import { envelope, signInOverHttp } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';
import { chk, fixtureUser, irisScript } from '../support/iris';

/**
 * Story 21.2, the Email group of Settings > Channels, in a real browser and over real HTTP against a real stack: the README account holds OcuTalonAdmin, and
 * the live fixture user (OCUTALON_LIVE_USER) holds OcuTalonUser only. The CI mock's POP3 stub is at mock:1110 inside the compose network, and the mailbox the
 * test saves uses it with the dummy password of the run (random, never printed, never sent to a script). The save writes SSLConfig OcuTalonClient (TLS, never
 * plain), so the plain stub is polled over TLS and the poll fails with the "couldn't reach" sentence: that is the recorded outcome the test waits for.
 * The cases leave the stack as they found it: the mailbox is removed again (the credential, the settings rows of EmailIn, the keys email.address and
 * email.owner, the seen rows, the emailPoll mark and the test's decisions).
 *   - E1: a user without OcuTalonAdmin gets 403 not_admin from POST /v1/settings/channels, and nothing is offered to the hand-off, submitted or written;
 *   - E2: an admin fills the Email group in and saves: the page shows the saved text, GET /v1/settings shows passwordSet true and holds no password, a reload
 *     shows an empty password field and "Saved, and never shown again. Type a new value to replace it.", and EmailIn runs and has recorded a poll;
 *   - E3: an email item of the owner's mailbox reaches the owner's state and no other session's (isolation).
 */
const SETTINGS = '/ocutalon/api/v1/settings';
const CHANNELS = `${SETTINGS}/channels`;
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const SECRET_SET = 'Saved, and never shown again. Type a new value to replace it.';
const SECRET_NOT_SET = 'Not set.';
const DENIED = 'Only OcuTalon admins can open settings.';

interface Channels {
  address: string;
  incoming: string;
  user: string;
  passwordSet: boolean;
}

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** Signs the README admin in and opens Settings > Channels. */
async function openChannels(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Channels', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Channels' })).toBeVisible();
}

/** The counts that a refused call must not change: hand-off resources, stored SaveSettings messages, and whether email.address has a row. */
async function counts(): Promise<{ handoffs: string; saves: string; keys: string }> {
  const lines = await irisScript(
    [
      'Set l=$SYSTEM.Event.List(),n=0,p=0 While $ListNext(l,p,x) { If x["OcuTalonHandoff" Set n=n+1 }',
      'Set r=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Msg_Command.SaveSettings") Do r.%Next()',
      'Write !,"CHK|handoffs|",n',
      'Write !,"CHK|saves|",r.%GetData(1)',
      'Write !,"CHK|keys|",##class(OcuTalon.Data.Setting).KeyIndexExists("email.address")',
    ].join('\n'),
  );
  return { handoffs: chk(lines, 'handoffs') ?? '?', saves: chk(lines, 'saves') ?? '?', keys: chk(lines, 'keys') ?? '?' };
}

/** Removes the mailbox the test connected, and what it made: the settings rows of EmailIn, the credential, the keys, the seen rows, the mark, the decisions. */
async function removeMailbox(): Promise<void> {
  await irisScript(
    [
      'For n="POP3Server","POP3Port","Credentials","SSLConfig","Enabled" { Set id="OcuTalon.Production||EmailIn||*||"_n If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do ##class(Ens.Config.DefaultSettings).%DeleteId(id) }',
      'If ##class(Ens.Config.Credentials).%ExistsId("OcuTalonMail") Do ##class(Ens.Config.Credentials).%DeleteId("OcuTalonMail")',
      'For k="email.address","email.owner" { Set r=##class(OcuTalon.Data.Setting).KeyIndexOpen(k) If $IsObject(r) Do ##class(OcuTalon.Data.Setting).%DeleteId(r.%Id()) }',
      'Do ##class(OcuTalon.Data.MailSeen).%KillExtent()',
      'Do ##class(OcuTalon.Data.StatusMark).Record("emailPoll","")',
      'Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.Decision WHERE Summary LIKE ?","%E2E-email-%")',
      'Set sc=##class(Ens.Director).UpdateProduction()',
      'Write !,"CHK|removed|",$SYSTEM.Status.IsOK(sc)',
    ].join('\n'),
  );
}

/** Whether EmailIn has a live job and has recorded a poll, as "job|marked". */
async function emailInRuns(): Promise<string> {
  const lines = await irisScript(
    [
      'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Do rs.Execute() Set j=0',
      'While rs.Next() { If (rs.Get("ConfigName")="EmailIn")&&(rs.Get("State")="Alive") Set j=1 }',
      'Write !,"CHK|run|",j_"|"_(##class(OcuTalon.Data.StatusMark).Get("emailPoll")\'="")',
    ].join('\n'),
  );
  return chk(lines, 'run') ?? '?';
}

/** E1: a user without OcuTalonAdmin gets 403 not_admin, and nothing is offered, submitted or written. */
test('E1: a user without OcuTalonAdmin is refused by POST /v1/settings/channels', async ({ playwright }) => {
  const live = fixtureUser('LIVE');
  const api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  try {
    await signInOverHttp(api, live.user, live.password);
    const before = await counts();
    const answer = await api.post(CHANNELS, { headers: envelope(), data: { address: 'live@example.com', incoming: 'mock:1110', user: 'live', password: 'not-a-real-password' } });
    expect(answer.status(), 'POST /v1/settings/channels is 403').toBe(403);
    expect(await answer.json(), 'not_admin with the ruled text').toEqual({ error: { code: 'not_admin', message: DENIED } });
    expect(await counts(), 'nothing was offered, submitted or written').toEqual(before);
  } finally {
    await api.dispose();
  }
});

/** E2 and E3: the admin connects the mailbox from the page; a second session never sees the owner's email items. */
test('E2: an admin connects a mailbox from Settings > Channels, and the password is never shown again', async ({ page, playwright }) => {
  const dummy = `Zz-e2e-${randomBytes(9).toString('hex')}`;
  await openChannels(page);
  try {
    const group = page.locator('section[data-section="email"]');
    await expect(group.getByRole('heading', { level: 3, name: 'Email', exact: true }), 'the Email group heading').toBeVisible();
    const address = group.getByLabel('Your email address', { exact: true });
    const incoming = group.getByLabel('Incoming mail server (POP3)', { exact: true });
    const user = group.getByLabel('User name', { exact: true });
    const password = group.getByLabel('Password', { exact: true });
    await expect(password, 'the password field is empty').toHaveValue('');
    await expect(password, 'and a password field').toHaveAttribute('type', 'password');
    await expect(group.getByText(SECRET_NOT_SET, { exact: true }), 'no password is stored yet').toBeVisible();
    await address.fill('e2e@example.com');
    await incoming.fill('mock:1110');
    await user.fill('e2e');
    await password.fill(dummy);
    await group.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(group.locator('p.saved'), 'the saved text shows').toHaveText(SAVED);

    const response = await page.request.get(SETTINGS);
    expect(response.status(), 'GET /v1/settings').toBe(200);
    const text = await response.text();
    expect(text.includes(dummy), 'the answer holds no password').toBe(false);
    const body = JSON.parse(text) as { sections: { channels: Channels } };
    expect(body.sections.channels, 'the channels hold the saved values and that a password is set').toEqual({ address: 'e2e@example.com', incoming: 'mock:1110', user: 'e2e', passwordSet: true });

    await page.reload();
    await expect(page.getByRole('heading', { level: 2, name: 'Channels' })).toBeVisible();
    const reloaded = page.locator('section[data-section="email"]');
    await expect(reloaded.getByLabel('Your email address', { exact: true }), 'a reload shows the saved address').toHaveValue('e2e@example.com');
    await expect(reloaded.getByLabel('Password', { exact: true }), 'and an empty password field').toHaveValue('');
    await expect(reloaded.getByText(SECRET_SET, { exact: true }), 'with the line that says a password is saved and never shown again').toBeVisible();

    await expect.poll(emailInRuns, { message: 'EmailIn runs and has recorded a poll', timeout: 60_000, intervals: [2000] }).toBe('1|1');

    // E3: an email item of the owner is the owner's only.
    const subject = `E2E-email-${randomBytes(4).toString('hex')}`;
    const sent = await irisScript(
      [
        'Set sc=##class(Ens.Director).CreateBusinessService("EmailIn",.svc)',
        'Set m=##class(OcuTalon.Channel.Email.Mail).%New() Set m.Uidl="e2e1",m.Sender="Dana <dana@example.com>",m.Text="Please look at the invoice."',
        `Set m.Subject="${subject}"`,
        'Set sc=svc.ProcessInput(m) Write !,"CHK|sent|",$SYSTEM.Status.IsOK(sc)',
      ].join('\n'),
    );
    expect(chk(sent, 'sent'), 'the email item is handed to Intake').toBe('1');
    await expect
      .poll(async () => (await (await page.request.get('/ocutalon/api/v1/state')).text()).includes(subject), { message: "the owner's state holds the email's decision", timeout: 60_000, intervals: [2000] })
      .toBe(true);
    const live = fixtureUser('LIVE');
    const other = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    try {
      await signInOverHttp(other, live.user, live.password);
      const state = await other.get('/ocutalon/api/v1/state');
      expect(state.status(), "the other session's state").toBe(200);
      expect((await state.text()).includes(subject), "holds no email item of the owner's mailbox").toBe(false);
    } finally {
      await other.dispose();
    }
  } finally {
    await removeMailbox();
  }
});

