import { randomBytes } from 'node:crypto';

import { expect, test, type Locator, type Page } from '../support/fixtures';

import { envelope, signInOverHttp } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';
import { chk, fixtureUser, irisScript } from '../support/iris';

/**
 * Stories 21.2, 21.6 and 21.3, the Email group of Settings > Channels, in a real browser and over real HTTP against a real stack: the README account holds OcuTalonAdmin, and
 * the live fixture user (OCUTALON_LIVE_USER) holds OcuTalonUser only. The CI mock's POP3 stub is at mock:1110 inside the compose network, and the mailbox the
 * test saves uses it with the dummy password of the run (random, never printed, never sent to a script). The save writes SSLConfig OcuTalonClient (TLS, never
 * plain), so the plain stub is polled over TLS and the poll fails with the "couldn't reach" sentence: that is the recorded outcome the test waits for.
 * E2 and E4 start from no mailbox (they remove one first, the emailPoll mark included, so that E2's recorded poll is its own save's) and leave the
 * stack as they found it: the mailbox is removed again (the credential, the settings rows of EmailIn, the keys email.address and email.owner, the
 * seen rows, the emailPoll mark and the test's decisions).
 *   - E1: a user without OcuTalonAdmin gets 403 not_admin from POST /v1/settings/channels, and nothing is offered to the hand-off, submitted or written;
 *   - E2: an admin fills the Email group in and saves: the page shows the saved text, GET /v1/settings shows passwordSet true and holds no password, a reload
 *     shows an empty password field and "Saved, and never shown again. Type a new value to replace it.", and EmailIn runs and has recorded a poll;
 *   - E3: an email item of the owner's mailbox reaches the owner's state and no other session's (isolation).
 * Story 21.6 adds the Outgoing mail server (SMTP) field to E2: the admin types mock:1025 (the CI mock's SMTP stub), the saved text shows, GET shows `outgoing` and
 * `passwordSet` with no password, a reload shows the saved server, and EmailOut runs within 60 seconds; E1 posts the field as the LIVE fixture user (403).
 *   - E6 (Story 21.3): the sign-in with Google against the CI mock's fake authorization server. The LIVE fixture user gets 403 on the sign-in route (both actions) and on a
 *     channels save with signIn; the admin chooses Google, fills Client ID and Client secret (the dummy pair, set on the mock through irisScript), saves, sees the
 *     redirect address (the page's origin and /csp/sys/oauth2/OAuth2.Response.cls); the browser can reach IRIS only (not http://mock:8080), so the test answers the
 *     redirect to the provider's consent page itself (a redirect back to IRIS's OAuth2.Response with a code and the same state), and everything server to server
 *     (IRIS's code exchange with the mock's token step) is real; the button opens a new tab that lands on Settings > Channels and shows "Signed in with Google."; GET shows
 *     signedIn, clientSecretSet and no secret; a second session gets 403 on GET and both routes. It puts back the OAuth2 objects and the web application's flag.
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
  outgoing: string;
  user: string;
  passwordSet: boolean;
  signIn: string;
  clientId: string;
  clientSecretSet: boolean;
  signedIn: boolean;
}

/** The members of the channels values that Story 21.3 added, for a mailbox that signs in with its password. */
const PASSWORD_MODE = { signIn: 'password', clientId: '', clientSecretSet: false, signedIn: false } as const;

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** Signs the README admin in and opens Settings > Channels. */
async function openChannels(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Channels', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Channels' })).toBeVisible();
}

/** The counts that a refused call must not change: hand-off resources, stored SaveSettings messages, whether email.address has a row, and the settings rows of EmailOut. */
async function counts(): Promise<{ handoffs: string; saves: string; keys: string; out: string }> {
  const lines = await irisScript(
    [
      'Set l=$SYSTEM.Event.List(),n=0,p=0 While $ListNext(l,p,x) { If x["OcuTalonHandoff" Set n=n+1 }',
      'Set r=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Msg_Command.SaveSettings") Do r.%Next()',
      'Write !,"CHK|handoffs|",n',
      'Write !,"CHK|saves|",r.%GetData(1)',
      'Write !,"CHK|keys|",##class(OcuTalon.Data.Setting).KeyIndexExists("email.address")',
      'Set d=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND ItemName = ?","OcuTalon.Production","EmailOut") Do d.%Next()',
      'Write !,"CHK|out|",d.%GetData(1)',
    ].join('\n'),
  );
  return { handoffs: chk(lines, 'handoffs') ?? '?', saves: chk(lines, 'saves') ?? '?', keys: chk(lines, 'keys') ?? '?', out: chk(lines, 'out') ?? '?' };
}

/** Removes the mailbox the test connected, and what it made: the settings rows of EmailIn, the credential, the keys, the seen rows, the mark, the decisions. */
async function removeMailbox(): Promise<void> {
  await irisScript(
    [
      'For i="EmailIn","EmailOut" { For n="POP3Server","POP3Port","SMTPServer","SMTPPort","Credentials","SSLConfig","SSLCheckServerIdentity","Enabled" { Set id="OcuTalon.Production||"_i_"||*||"_n If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do ##class(Ens.Config.DefaultSettings).%DeleteId(id) } }',
      'If ##class(Ens.Config.Credentials).%ExistsId("OcuTalonMail") Do ##class(Ens.Config.Credentials).%DeleteId("OcuTalonMail")',
      'For k="email.address","email.owner","email.signIn","email.clientId","email.oauthOwned" { Set r=##class(OcuTalon.Data.Setting).KeyIndexOpen(k) If $IsObject(r) Do ##class(OcuTalon.Data.Setting).%DeleteId(r.%Id()) }',
      'Do ##class(OcuTalon.Test.Channel.EmailOAuth).Wipe()',
      'Do ##class(OcuTalon.Test.Channel.EmailOAuth).SetApp(0)',
      'Do ##class(OcuTalon.Data.StatusMark).Record("emailSignIn","")',
      'Do ##class(OcuTalon.Test.Channel.EmailLive).OAuthControl("reset",{})',
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

/** Whether EmailOut has a live job, as "1" or "0". */
async function emailOutRuns(): Promise<string> {
  const lines = await irisScript(
    [
      'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Do rs.Execute() Set j=0',
      'While rs.Next() { If (rs.Get("ConfigName")="EmailOut")&&(rs.Get("State")="Alive") Set j=1 }',
      'Write !,"CHK|runout|",j',
    ].join('\n'),
  );
  return chk(lines, 'runout') ?? '?';
}

/** E1: a user without OcuTalonAdmin gets 403 not_admin, and nothing is offered, submitted or written. */
test('E1: a user without OcuTalonAdmin is refused by POST /v1/settings/channels', async ({ playwright }) => {
  const live = fixtureUser('LIVE');
  const api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  try {
    await signInOverHttp(api, live.user, live.password);
    const before = await counts();
    const answer = await api.post(CHANNELS, { headers: envelope(), data: { address: 'live@example.com', incoming: 'mock:1110', outgoing: 'mock:1025', user: 'live', password: 'not-a-real-password' } });
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
  await removeMailbox();
  await openChannels(page);
  try {
    const group = page.locator('section[data-section="email"]');
    await expect(group.getByRole('heading', { level: 3, name: 'Email', exact: true }), 'the Email group heading').toBeVisible();
    const address = group.getByLabel('Your email address', { exact: true });
    const incoming = group.getByLabel('Incoming mail server (POP3)', { exact: true });
    const outgoing = group.getByLabel('Outgoing mail server (SMTP)', { exact: true });
    const user = group.getByLabel('User name', { exact: true });
    const password = group.locator('#email-password');
    await expect(password, 'the password field is empty').toHaveValue('');
    await expect(password, 'and a password field').toHaveAttribute('type', 'password');
    await expect(group.getByText(SECRET_NOT_SET, { exact: true }), 'no password is stored yet').toBeVisible();
    await address.fill('e2e@example.com');
    await incoming.fill('mock:1110');
    await outgoing.fill('mock:1025');
    await user.fill('e2e');
    await password.fill(dummy);
    await group.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(group.locator('p.saved'), 'the saved text shows').toHaveText(SAVED);

    const response = await page.request.get(SETTINGS);
    expect(response.status(), 'GET /v1/settings').toBe(200);
    const text = await response.text();
    expect(text.includes(dummy), 'the answer holds no password').toBe(false);
    const body = JSON.parse(text) as { sections: { channels: Channels } };
    expect(body.sections.channels, 'the channels hold the saved values and that a password is set').toEqual({ address: 'e2e@example.com', incoming: 'mock:1110', outgoing: 'mock:1025', user: 'e2e', passwordSet: true, ...PASSWORD_MODE });

    await page.reload();
    await expect(page.getByRole('heading', { level: 2, name: 'Channels' })).toBeVisible();
    const reloaded = page.locator('section[data-section="email"]');
    await expect(reloaded.getByLabel('Your email address', { exact: true }), 'a reload shows the saved address').toHaveValue('e2e@example.com');
    await expect(reloaded.getByLabel('Outgoing mail server (SMTP)', { exact: true }), 'and the saved outgoing server').toHaveValue('mock:1025');
    await expect(reloaded.locator('#email-password'), 'and an empty password field').toHaveValue('');
    await expect(reloaded.getByText(SECRET_SET, { exact: true }), 'with the line that says a password is saved and never shown again').toBeVisible();

    await expect.poll(emailInRuns, { message: 'EmailIn runs and has recorded a poll', timeout: 60_000, intervals: [2000] }).toBe('1|1');
    await expect.poll(emailOutRuns, { message: 'EmailOut runs', timeout: 60_000, intervals: [2000] }).toBe('1');

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
      // QA (21.2): the second session reads none of the saved mailbox through the settings route and cannot replace it through the channels route.
      const settings = await other.get(SETTINGS);
      expect(settings.status(), "the other session's GET /v1/settings is 403").toBe(403);
      const settingsText = await settings.text();
      expect(settingsText.includes('e2e@example.com') || settingsText.includes('mock:1110') || settingsText.includes('passwordSet'), "and holds none of the owner's mailbox").toBe(false);
      const replace = await other.post(CHANNELS, { headers: envelope(), data: { address: 'live@example.com', incoming: 'mock:1110', outgoing: 'mock:1025', user: 'live', password: 'not-a-real-password' } });
      expect(replace.status(), "the other session's POST /v1/settings/channels is 403").toBe(403);
      const kept = await page.request.get(SETTINGS);
      expect((JSON.parse(await kept.text()) as { sections: { channels: Channels } }).sections.channels, "and the owner's saved mailbox is as it was").toEqual({ address: 'e2e@example.com', incoming: 'mock:1110', outgoing: 'mock:1025', user: 'e2e', passwordSet: true, ...PASSWORD_MODE });
    } finally {
      await other.dispose();
    }
  } finally {
    await removeMailbox();
  }
});

/** E4 (QA, DW-1141): a value that holds @{ is refused by the form: the field shows the ruled text, nothing is saved and nothing is offered to the hand-off. */
test('E4: a value holding @{ is refused with the setting-reference text, and nothing changes', async ({ page }) => {
  const REFUSED = "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.";
  await removeMailbox();
  await openChannels(page);
  try {
    const before = await counts();
    const group = page.locator('section[data-section="email"]');
    await expect(group.getByRole('heading', { level: 3, name: 'Email', exact: true }), 'the Email group heading').toBeVisible();
    await group.getByLabel('Your email address', { exact: true }).fill('e2e-@{env:PATH}@example.com');
    await group.getByLabel('Incoming mail server (POP3)', { exact: true }).fill('mock:1110');
    await group.getByLabel('User name', { exact: true }).fill('e2e');
    await group.locator('#email-password').fill(`Zz-e2e-${randomBytes(9).toString('hex')}`);
    await group.getByRole('button', { name: 'Save changes', exact: true }).click();
    const error = group.locator('#email-address-error');
    await expect(error, 'the address field shows the setting-reference text').toHaveText(REFUSED);
    await expect(group.getByLabel('Your email address', { exact: true }), 'the field is marked invalid').toHaveAttribute('aria-invalid', 'true');
    await expect(group.locator('#email-incoming-error, #email-user-error, #email-password-error'), 'no other field is named').toHaveCount(0);
    await expect(group.locator('p.saved'), 'no saved text shows').toHaveCount(0);
    const response = await page.request.get(SETTINGS);
    const channels = (JSON.parse(await response.text()) as { sections: { channels: Channels } }).sections.channels;
    expect(channels.passwordSet, 'no password was stored').toBe(false);
    expect(channels.address, 'and no address').toBe('');
    expect(await counts(), 'nothing was left offered to the hand-off, and no key was written').toMatchObject({ handoffs: before.handoffs, keys: before.keys });
  } finally {
    await removeMailbox();
  }
});

/** E5 (QA, 21.6): a refused outgoing server is named on its own field, and nothing is saved: no EmailOut row, no mailbox, nothing offered to the hand-off. */
test('E5: a refused outgoing server shows the error on its own field, and nothing changes', async ({ page }) => {
  const FAILED = "Couldn't save. Nothing was changed.";
  await removeMailbox();
  await openChannels(page);
  try {
    const before = await counts();
    const group = page.locator('section[data-section="email"]');
    await expect(group.getByRole('heading', { level: 3, name: 'Email', exact: true }), 'the Email group heading').toBeVisible();
    const outgoing = group.getByLabel('Outgoing mail server (SMTP)', { exact: true });
    await group.getByLabel('Your email address', { exact: true }).fill('e2e@example.com');
    await group.getByLabel('Incoming mail server (POP3)', { exact: true }).fill('mock:1110');
    await outgoing.fill('mock:1025:7');
    await group.getByLabel('User name', { exact: true }).fill('e2e');
    await group.locator('#email-password').fill(`Zz-e2e-${randomBytes(9).toString('hex')}`);
    await group.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(group.locator('#email-outgoing-error'), 'the outgoing field shows the failed-save text').toHaveText(FAILED);
    await expect(outgoing, 'the field is marked invalid').toHaveAttribute('aria-invalid', 'true');
    await expect(outgoing, 'and described by its error').toHaveAttribute('aria-describedby', 'email-outgoing-error');
    await expect(group.locator('#email-address-error, #email-incoming-error, #email-user-error, #email-password-error'), 'no other field is named').toHaveCount(0);
    await expect(group.locator('p.saved'), 'no saved text shows').toHaveCount(0);
    const response = await page.request.get(SETTINGS);
    const channels = (JSON.parse(await response.text()) as { sections: { channels: Channels } }).sections.channels;
    expect(channels, 'the channels hold no mailbox, no outgoing server and no password').toEqual({ address: '', incoming: '', outgoing: '', user: '', passwordSet: false, ...PASSWORD_MODE });
    expect(await counts(), 'nothing was offered to the hand-off, no key and no EmailOut row was written').toMatchObject({ handoffs: before.handoffs, keys: before.keys, out: before.out });
    expect(await emailOutRuns(), 'and EmailOut does not run').toBe('0');
  } finally {
    await removeMailbox();
  }
});

/** E6 (Story 21.3): the admin signs in with Google against the CI mock's fake authorization server; the LIVE fixture user and a second session are refused. */
test('E6: an admin registers the OAuth2 client and signs in with Google, and no secret shows anywhere', async ({ page, playwright }) => {
  const clientId = `e2e-client-${randomBytes(4).toString('hex')}.example`;
  const clientSecret = `Zz-e2e-client-secret-${randomBytes(9).toString('hex')}`;
  const SIGN_IN = `${CHANNELS}/sign-in`;
  const live = fixtureUser('LIVE');

  // The LIVE fixture user is refused on the sign-in route (both actions) and on a channels save with a provider.
  const api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  try {
    await signInOverHttp(api, live.user, live.password);
    const before = await counts();
    for (const action of ['start', 'check']) {
      const answer = await api.post(SIGN_IN, { headers: envelope(), data: { action } });
      expect(answer.status(), `POST ${SIGN_IN} ${action} is 403`).toBe(403);
      expect(await answer.json(), 'not_admin with the ruled text').toEqual({ error: { code: 'not_admin', message: DENIED } });
    }
    const save = await api.post(CHANNELS, { headers: envelope(), data: { address: 'live@example.com', incoming: 'mock:1110', user: 'live', signIn: 'google', clientId: 'live-client.example', clientSecret: 'not-a-real-secret' } });
    expect(save.status(), 'a channels save with a provider is 403').toBe(403);
    expect(await counts(), 'nothing was offered, submitted or written').toEqual(before);
  } finally {
    await api.dispose();
  }

  await removeMailbox();
  await irisScript(`Do ##class(OcuTalon.Test.Channel.EmailLive).OAuthControl("client",{"clientId":"${clientId}","clientSecret":"${clientSecret}"})`);
  // The browser reaches IRIS only, and Playwright does not route a request that is the target of a server redirect, so the test answers the first hop itself: it fetches
  // IRIS's start page (which answers the redirect to the provider's consent page, with IRIS's CSRF cookie) and replies, in the provider's place, with a redirect back to
  // IRIS's OAuth2.Response with a code and the same state. IRIS's code exchange with the mock's token step, server to server, is real.
  const asked: URL[] = [];
  await page.context().route(/\/csp\/sys\/oauth2\/OAuth2\.Response\.cls\?auth=1/, async (route) => {
    const upstream = await route.fetch({ maxRedirects: 0 });
    const consent = new URL(upstream.headers()['location'] ?? 'http://invalid.example/');
    asked.push(consent);
    const back = consent.searchParams.get('redirect_uri') ?? '';
    const state = consent.searchParams.get('state') ?? '';
    await route.fulfill({ response: upstream, status: 302, headers: { ...upstream.headers(), location: `${back}?code=consent-${randomBytes(8).toString('hex')}&state=${encodeURIComponent(state)}` } });
  });
  await openChannels(page);
  try {
    const group = page.locator('section[data-section="email"]');
    const origin = new URL(page.url()).origin;
    const method = group.getByRole('radiogroup', { name: 'Sign-in method', exact: true });
    await expect(method.getByRole('radio', { name: 'Password', exact: true }), 'Password is the method of a new mailbox').toBeChecked();
    await expect(group.getByRole('button', { name: /^Sign in with/ }), 'with the Password method there is no sign-in button').toHaveCount(0);
    await group.getByLabel('Your email address', { exact: true }).fill('e2e@example.com');
    await group.getByLabel('Incoming mail server (POP3)', { exact: true }).fill('mock:1110');
    await group.getByLabel('User name', { exact: true }).fill('e2e');
    await method.getByRole('radio', { name: 'Google', exact: true }).check();
    await expect(group.locator('#email-password'), 'with a provider the password field is gone').toHaveCount(0);
    await expect(group.getByText('Add this address to your OAuth2 client at Google as an authorized redirect URI.', { exact: true }), 'the redirect help names the provider').toBeVisible();
    await expect(group.locator('#email-redirect'), 'the redirect address is this page\'s origin and IRIS\'s redirection endpoint').toHaveText(`${origin}/csp/sys/oauth2/OAuth2.Response.cls`);
    await expect(group.getByText('Not set.', { exact: true }), 'no client secret is stored yet').toBeVisible();
    await expect(group.getByText('Not signed in yet. Save, then sign in with Google.', { exact: true }), 'the state line says so').toBeVisible();
    const button = group.getByRole('button', { name: 'Sign in with Google', exact: true });
    await expect(button, 'the sign-in button waits for a saved client').toHaveAttribute('aria-disabled', 'true');
    await group.getByLabel('Client ID', { exact: true }).fill(clientId);
    const secret = group.locator('#email-clientSecret');
    await expect(secret, 'the client secret field is a password field').toHaveAttribute('type', 'password');
    await expect(secret, 'and empty').toHaveValue('');
    await secret.fill(clientSecret);
    await group.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(group.locator('p.saved'), 'the saved text shows').toHaveText(SAVED);
    await expect(secret, 'the client secret field is emptied').toHaveValue('');
    await expect(group.getByText(SECRET_SET, { exact: true }), 'and says a client secret is stored').toBeVisible();
    await expect(button, 'the sign-in button is ready').not.toHaveAttribute('aria-disabled', 'true');

    const response = await page.request.get(SETTINGS);
    const text = await response.text();
    expect(text.includes(clientSecret), 'GET holds no client secret').toBe(false);
    const channels = (JSON.parse(text) as { sections: { channels: Channels } }).sections.channels;
    expect(channels, 'the channels hold the method, the client ID and a registered client').toEqual({ address: 'e2e@example.com', incoming: 'mock:1110', outgoing: '', user: 'e2e', passwordSet: false, signIn: 'google', clientId, clientSecretSet: true, signedIn: false });

    // The press opens a new tab on IRIS's authorization address; the consent (answered here) sends it through IRIS's code exchange to Settings > Channels.
    const opened = page.context().waitForEvent('page');
    await button.click();
    const tab = await opened;
    await tab.waitForURL(/#\/settings\/channels/);
    const landed = tab.locator('section[data-section="email"]');
    await expect(landed.getByText('Signed in with Google.', { exact: true }), 'the new tab shows that the mailbox is signed in').toBeVisible({ timeout: 60_000 });
    expect(asked.length, 'the consent page was asked once').toBe(1);
    const consent = asked[0]!;
    expect(consent.searchParams.get('client_id'), 'with the dummy client ID').toBe(clientId);
    expect(consent.searchParams.get('redirect_uri'), "with IRIS's redirection endpoint on this page's origin").toBe(`${origin}/csp/sys/oauth2/OAuth2.Response.cls`);
    expect(consent.searchParams.get('scope'), "with Google's scope").toBe('https://mail.google.com/');
    expect(consent.searchParams.get('response_type'), 'for the code flow').toBe('code');
    expect(consent.searchParams.get('state') ?? '', 'with a state').not.toBe('');
    expect(consent.searchParams.get('code_challenge_method'), 'and a PKCE challenge').toBe('S256');
    await tab.close();

    const tokens = await irisScript(['Set t=##class(OcuTalon.Test.Channel.EmailLive).TokenRow()', 'Write !,"CHK|token|",$Piece(t,"|",1,3)', 'Write !,"CHK|values|",$Piece(t,"|",4,5)'].join('\n'));
    expect(chk(tokens, 'token'), "IRIS's token row holds an access token and a refresh token and no error").toBe('1|1|');
    const [accessToken, refreshToken] = (chk(tokens, 'values') ?? '').split('|');
    expect([accessToken, refreshToken].every((value) => value !== undefined && value.startsWith('mock-')), "the tokens are the fake server's dummy values").toBe(true);

    const after = await page.request.get(SETTINGS);
    const afterText = await after.text();
    expect(afterText.includes(clientSecret), 'GET holds no client secret after the sign-in either').toBe(false);
    expect(afterText.includes(accessToken!), 'GET holds no access token').toBe(false);
    expect(afterText.includes(refreshToken!), 'GET holds no refresh token').toBe(false);
    expect(/mock-(at|rt)-|consent-/.test(afterText), 'GET holds nothing of the fake server\'s tokens or authorization code').toBe(false);
    expect((JSON.parse(afterText) as { sections: { channels: Channels } }).sections.channels.signedIn, 'GET says signed in').toBe(true);

    // A second session reads none of it and cannot start or check.
    const other = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    try {
      await signInOverHttp(other, live.user, live.password);
      const settings = await other.get(SETTINGS);
      expect(settings.status(), "the other session's GET /v1/settings is 403").toBe(403);
      const otherText = await settings.text();
      expect(otherText.includes(clientId) || otherText.includes('clientSecretSet') || otherText.includes('e2e@example.com'), 'and holds none of the owner\'s mailbox').toBe(false);
      for (const action of ['start', 'check']) {
        expect((await other.post(SIGN_IN, { headers: envelope(), data: { action } })).status(), `the other session's ${action} is 403`).toBe(403);
      }
    } finally {
      await other.dispose();
    }
  } finally {
    await page.context().unroute(/\/csp\/sys\/oauth2\/OAuth2\.Response\.cls\?auth=1/);
    await removeMailbox();
  }
});
