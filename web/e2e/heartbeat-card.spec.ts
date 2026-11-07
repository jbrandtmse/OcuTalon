import { expect, test, type Locator, type Page } from './support/fixtures';

import { README_ACCOUNT } from './sign-in/helpers';
import { changeSnapshot } from './support/api';
import { pointKeys, restoreKeys } from './support/devices';
import { applied, railOf, signInReadmeLoaded } from './support/floor';
import { chk, irisScript, publishStatus, quoted } from './support/iris';
import { clock } from './support/page';
import { sessionRef } from './support/persona';

/**
 * Story 39.5 (HC1 to HC12, and HC3b and HC9b), the Heartbeat checklist card in the status rail, in a real browser against the stack that test-sign-in.sh seeds,
 * signed in as the README account. Every case removes the account's heartbeat keys, its HeartbeatBeat row and the decision and Usage rows of
 * its beats first and again in `finally`, because the rail and demo-path specs assert Recent decisions and the defaults. The saved line and
 * the refusals are the server's own texts (OcuTalon.Core.SettingsOps), the card's other texts are written out here as the oracle. The values
 * behind the page are read through irisScript.
 *   - HC1 to HC3, HC9: the section and its default state, the keyboard alone through Edit and Save, a refusal beside its field, Esc;
 *   - HC4 (Integration, real routes and the real tick): save a checklist with a `heartbeat-ignore` marker, run it, and see the outcome and
 *     Today arrive by the `heartbeat` event with no reload. Its describe block points the runners at the CI mock, puts them back, and waits for
 *     the status monitor's noModelKey event of the restored keys (published within 15 seconds of the change), so that no later case gets it;
 *   - HC5: the cooldown from the row's LastRunNowAt, after a reload, and the clock that enables Run again;
 *   - HC6, HC7, HC8 rewrite one answer of the real stack: /state for the unavailable reasons, the GET for the online demo and for each
 *     outcome and skip. HC7 answers the run itself with a 202, so no beat runs;
 *   - HC3b and HC10 stub the PUT and the run with a refusal or a failure, to reach the answers that the real stack gives only on a fault.
 *   - HC11 and HC12 (QA) publish `heartbeat` events with a rewritten GET (no reload; a failed read leaves the heading; the next event reads again) and fail a
 *     save's re-read, so focus goes to the heading.
 */
/** The locale and the zone the spec's page runs with; the page's clock is the locale's numeric hour in that zone. */
const LOCALE = 'en-GB';
const ZONE = 'UTC';
test.use({ timezoneId: ZONE, locale: LOCALE });

const HEARTBEAT = '/ocutalon/api/v1/heartbeat';
const RUN = '/ocutalon/api/v1/heartbeat/run';
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const BAD_CHECKLIST = 'Use up to 1,000 characters, without {{ or @{.';
const OFF = 'Off. Turn it on to have OcuTalon look at your list every 30 minutes.';
const HELP =
  'Write what OcuTalon should look for, one item per line. With an empty list, OcuTalon makes no model call. It looks at most once per interval, and only when something has changed.';
const DEMO_NOTE = "On the online demo the heartbeat is off until you turn it on, and each check-in counts toward the demo's daily cost cap.";
const SAMPLE =
  'Tell me if an Orders incident is still open or waiting for my approval.\nRemind me of anything due in the next hour.\nIgnore everything else.';
const CAP = "Today's cost limit has been reached.";
const NOKEY = 'No model key is set.';
/** How long a saved setting may take to reach the other processes: the 60 second cache of the settings and a second. */
const APPLY_MS = 61_000;

const card = (page: Page): Locator => railOf(page).locator('app-heartbeat-card');
const editOf = (page: Page): Locator => card(page).getByRole('button', { name: 'Edit', exact: true });
const saveOf = (page: Page): Locator => card(page).getByRole('button', { name: 'Save', exact: true });
const runOf = (page: Page): Locator => card(page).getByRole('button', { name: 'Run the heartbeat now', exact: true });
const onOf = (page: Page): Locator => card(page).getByRole('checkbox', { name: 'On', exact: true });
const allDayOf = (page: Page): Locator => card(page).getByRole('checkbox', { name: 'All day', exact: true });
const intervalOf = (page: Page): Locator => card(page).getByRole('combobox', { name: 'Interval', exact: true });
const fromOf = (page: Page): Locator => card(page).getByRole('combobox', { name: 'From', exact: true });
const toOf = (page: Page): Locator => card(page).getByRole('combobox', { name: 'To', exact: true });
const checklistOf = (page: Page): Locator => card(page).getByRole('textbox', { name: 'Checklist', exact: true });
/** The line of the last check-in or skip: the paragraph that holds the parts. */
const lastOf = (page: Page): Locator => card(page).locator('p.line').filter({ hasText: /^(Last check-in|Skipped at)/ });
const todayOf = (page: Page): Locator => card(page).locator('p.line').filter({ hasText: /^Today:/ });

/** The five names of a heartbeat's keys. */
type KeyName = 'on' | 'interval' | 'from' | 'to' | 'checklist';

/** The stored value of one heartbeat key of the session, or "none" when there is no row. A line feed reads as "~". */
async function stored(ref: string, name: KeyName): Promise<string> {
  const lines = await irisScript(
    [
      `Set k=##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Checks.Beat).SettingKey(${quoted(ref)},${quoted(name)}))`,
      'Write !,"CHK|value|",$Select($IsObject(k):$Translate(k.Value,$Char(10),"~"),1:"none")',
    ].join('\n'),
  );
  return chk(lines, 'value') ?? 'unread';
}

/** Removes the heartbeat keys of the session, its HeartbeatBeat row, and the decision and Usage rows of its beats. */
async function reset(ref: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set ref=${quoted(ref)}`,
      'Set row=##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)',
      'Set item=$Select($IsObject(row):row.LastItemId,1:"")',
      `Set sub="SELECT ItemId FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND Channel = 'heartbeat'"`,
      'Set r=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND ItemId IN ("_sub_")",ref,ref)',
      'If item\'="" Set r=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND ItemId = ?",ref,item)',
      `Set r=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND Channel = 'heartbeat'",ref)`,
      'Do ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexDelete(ref)',
      'Set sc=##class(OcuTalon.Core.SettingsOps).ForgetPerson(ref)',
      'Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo","")',
      'Write !,"CHK|reset|",$System.Status.IsOK(sc)',
    ].join('\n'),
  );
  if (chk(lines, 'reset') !== '1') throw new Error(`the heartbeat of the session could not be removed (${lines.join(' ')})`);
}

/** The HeartbeatBeat fields that a case writes (the property names of the row). */
type RowFields = Partial<Record<'NextDueAt' | 'LastBeatAt' | 'LastOutcome' | 'LastSkipAt' | 'LastSkipReason' | 'LastRunNowAt' | 'BackoffUntil', string>>;

/** Writes the session's HeartbeatBeat row (made when there is none) with the fields. */
async function writeRow(ref: string, fields: RowFields): Promise<void> {
  const lines = await irisScript(
    [
      `Set row=##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(${quoted(ref)})`,
      `If '$IsObject(row) Set row=##class(OcuTalon.Data.HeartbeatBeat).%New(), row.SessionRef=${quoted(ref)}`,
      ...Object.entries(fields).map(([name, value]) => `Set row.${name}=${quoted(value)}`),
      'Write !,"CHK|row|",$System.Status.IsOK(row.%Save())',
    ].join('\n'),
  );
  if (chk(lines, 'row') !== '1') throw new Error(`the HeartbeatBeat row could not be saved (${lines.join(' ')})`);
}

/** An ISO time to the second, the given number of milliseconds from now. */
const at = (ms: number): string => new Date(Date.now() + ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
const MINUTE = 60_000;

/** True within 40 minutes of midnight UTC, where "now plus or minus 30 minutes" would be rendered with a day word. */
const nearMidnight = (): boolean => {
  const now = new Date();
  const minutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  return minutes < 40 || minutes > 24 * 60 - 40;
};

/** Runs a case with the account's heartbeat removed before and after, and with the page signed in and loaded. */
async function withCard(page: Page, body: (ref: string) => Promise<void>, before?: (ref: string) => Promise<void>): Promise<void> {
  const ref = await sessionRef();
  await reset(ref);
  try {
    await before?.(ref);
    await signInReadmeLoaded(page);
    await expect(card(page).getByRole('button', { name: 'Run the heartbeat now', exact: true }), 'the card has read its answer').toBeVisible();
    await body(ref);
  } finally {
    await reset(ref);
  }
}

/** Turns both conditions that hold Run off on the page's store, as a real status event would. */
async function conditionsOff(page: Page): Promise<void> {
  await publishStatus(README_ACCOUNT.user, { condition: 'noModelKey', active: false });
  await applied(page, await publishStatus(README_ACCOUNT.user, { condition: 'dailyCap', active: false }));
}

/** Answers the page's GET of the heartbeat with the real answer, changed by what `override()` holds. Call it before signing in. */
async function rewriteGet(page: Page, override: () => Record<string, unknown>): Promise<void> {
  await page.route(`**${HEARTBEAT}`, async (route) => {
    if (route.request().method() !== 'GET') return route.continue();
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    return route.fulfill({ response, json: { ...body, ...override() } });
  });
}

/** The text of a line as the page renders it: a trace link at the end reads "Trace (opens in a new tab)", its hidden suffix included. */
const exactly = (text: string): RegExp => new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\$]/g, '\\$&')}${text.endsWith('Trace') ? '( \\(opens in a new tab\\))?' : ''}$`);

/** HC1: the section, before Persona; the default state; the empty-checklist skip. */
test('HC1: the Heartbeat checklist section comes before Persona with the default state line, and shows the empty-checklist skip', async ({ page }) => {
  await withCard(page, async (ref) => {
    const headings = railOf(page).getByRole('heading', { level: 3 });
    const heartbeat = headings.nth((await headings.count()) - 2);
    await expect(heartbeat, 'the second to last section is Heartbeat checklist').toHaveAccessibleName('Heartbeat checklist');
    await expect(headings.last(), 'and Persona is last').toHaveAccessibleName('Persona');
    await expect(heartbeat.locator('[aria-hidden="true"]'), 'the heading has no count').toHaveCount(0);
    await expect(card(page), 'the card is the body of the section').toHaveCount(1);
    await expect(card(page).locator('p.line').first(), 'the default is on, every 30 minutes, 08:00 to 20:00').toHaveText(/^Every 30 minutes, 08:00 to 20:00( \u00b7 Next check-in .+)?$/);
    await expect(card(page).getByText(OFF), 'it is not the off line').toHaveCount(0);
    await expect(todayOf(page), 'no check-ins today: no Today line').toHaveCount(0);
    await expect(card(page).getByText(DEMO_NOTE), 'no online-demo note on a local install').toHaveCount(0);
    await expect(editOf(page)).toHaveAttribute('aria-expanded', 'false');
    await expect(card(page).locator('.empty, .hint, [aria-live], [role="status"], [role="alert"], [role="log"]'), 'the card is no empty text, hint or live region').toHaveCount(0);

    const skippedAt = at(-5_000);
    await writeRow(ref, { LastSkipAt: skippedAt, LastSkipReason: 'empty', NextDueAt: at(24 * 60 * MINUTE) });
    await page.reload();
    await expect(lastOf(page), 'a forced skip shows the skip line').toHaveText(`Skipped at ${clock(skippedAt, LOCALE, ZONE)}: your checklist is empty.`);
  });
});

/**
 * HC2: every control of Edit in the tab order, and the stored keys. Enter opens Edit, Space toggles the checkboxes, typing fills the checklist and
 * Enter presses Save; a select takes its value through selectOption, because the arrow keys on a closed select open its native menu on some platforms.
 */
test('HC2: with the keyboard alone, Edit changes every value, Save stores them, and a reload shows them', async ({ page }) => {
  await withCard(page, async (ref) => {
    await editOf(page).focus();
    await page.keyboard.press('Enter');
    await expect(editOf(page), 'Enter on Edit opens the form').toHaveAttribute('aria-expanded', 'true');
    await expect(onOf(page), 'On starts checked (the install default)').toBeChecked();
    await expect(intervalOf(page)).toHaveValue('30');
    await expect(fromOf(page)).toHaveValue('08:00');
    await expect(toOf(page)).toHaveValue('20:00');
    await expect(card(page).getByText(HELP, { exact: true }), 'the checklist help shows').toBeVisible();
    await expect(card(page).getByText('0 of 1,000 characters', { exact: true }), 'and the counter').toBeVisible();

    await page.keyboard.press('Tab');
    await expect(onOf(page), 'Tab from Edit reaches On').toBeFocused();
    await page.keyboard.press('Space');
    await expect(onOf(page)).not.toBeChecked();
    await page.keyboard.press('Tab');
    await expect(intervalOf(page), 'then Interval').toBeFocused();
    await intervalOf(page).selectOption('120');
    await expect(intervalOf(page), 'it moves from 30 minutes to 2 hours').toHaveValue('120');
    await page.keyboard.press('Tab');
    await expect(allDayOf(page), 'then All day').toBeFocused();
    await expect(allDayOf(page)).not.toBeChecked();
    await page.keyboard.press('Tab');
    await expect(fromOf(page), 'then From').toBeFocused();
    await fromOf(page).selectOption('07:15');
    await expect(fromOf(page), 'it moves from 08:00 to 07:15').toHaveValue('07:15');
    await page.keyboard.press('Tab');
    await expect(toOf(page), 'then To').toBeFocused();
    await toOf(page).selectOption('21:45');
    await expect(toOf(page), 'it moves from 20:00 to 21:45').toHaveValue('21:45');
    await page.keyboard.press('Tab');
    await expect(checklistOf(page), 'then Checklist').toBeFocused();
    await page.keyboard.type('Look at Orders.');
    await page.keyboard.press('Enter');
    await page.keyboard.type('Be brief.');
    await expect(card(page).getByText('25 of 1,000 characters', { exact: true }), 'the counter follows the typing').toBeVisible();
    await page.keyboard.press('Tab');
    await expect(saveOf(page), 'then Save').toBeFocused();
    await page.keyboard.press('Enter');
    await expect(card(page).getByText(SAVED, { exact: true }), "the server's saved line shows under Save").toBeVisible();
    const keys: string[] = [];
    for (const name of ['on', 'interval', 'from', 'to', 'checklist'] as const) keys.push(await stored(ref, name));
    expect(keys, 'the five keys are stored').toEqual(['0', '120', '07:15', '21:45', 'Look at Orders.~Be brief.']);
    await expect(card(page).locator('p.line').first(), 'the state line follows what was read again').toHaveText(OFF);

    await page.reload();
    await expect(card(page).locator('p.line').first(), 'after a reload the card is off').toHaveText(OFF);
    await editOf(page).click();
    await expect(onOf(page)).not.toBeChecked();
    await expect(intervalOf(page)).toHaveValue('120');
    await expect(fromOf(page)).toHaveValue('07:15');
    await expect(toOf(page)).toHaveValue('21:45');
    await expect(checklistOf(page)).toHaveValue('Look at Orders.\nBe brief.');

    await allDayOf(page).focus();
    await page.keyboard.press('Space');
    await expect(allDayOf(page), 'Space checks All day').toBeChecked();
    await expect(fromOf(page), 'All day leaves out the hours').toHaveCount(0);
    await onOf(page).focus();
    await page.keyboard.press('Space');
    await expect(onOf(page), 'Space checks On').toBeChecked();
    await saveOf(page).focus();
    await page.keyboard.press('Enter');
    await expect(card(page).getByText(SAVED, { exact: true })).toBeVisible();
    expect(await stored(ref, 'from'), 'all day is stored as empty hours').toMatch(/^(|none)$/);
    expect(await stored(ref, 'to')).toMatch(/^(|none)$/);
    expect(await stored(ref, 'on')).toBe('1');
    await expect(card(page).locator('p.line').first(), 'the on line has no hours for all day').toHaveText(/^Every 2 hours( \u00b7 Next check-in .+)?$/);
  });
});

/** HC3: a checklist with {{ is refused beside the checklist. */
test('HC3: a checklist with {{ is refused beside the checklist, marked invalid and described, and nothing is stored', async ({ page }) => {
  await withCard(page, async (ref) => {
    await editOf(page).click();
    const field = checklistOf(page);
    await field.fill('Look at {{Orders}}');
    await saveOf(page).click();
    await expect(field, 'the field is marked invalid').toHaveAttribute('aria-invalid', 'true');
    const ids = ((await field.getAttribute('aria-describedby')) ?? '').split(' ');
    const errorId = ids.find((one) => one.endsWith('-checklist-error'));
    expect(errorId, `the error is among the ids that describe the field (${ids.join(' ')})`).toBeTruthy();
    await expect(page.locator(`#${errorId}`), "the server's refusal shows beside the field").toHaveText(BAD_CHECKLIST);
    await expect(field, 'the field keeps the typed text').toHaveValue('Look at {{Orders}}');
    expect(await stored(ref, 'checklist'), 'nothing was stored').toBe('none');
    await expect(card(page).getByText(SAVED, { exact: true }), 'no saved line').toHaveCount(0);
    await field.fill('Look at Orders');
    await expect(field, 'typing clears the refusal').not.toHaveAttribute('aria-invalid', 'true');
  });
});

/** HC5: the cooldown comes from LastRunNowAt, survives a reload, and ends by itself. */
test('HC5: Run is held for 120 seconds after LastRunNowAt, still after a reload, and enabled again when the cooldown ends', async ({ page }) => {
  test.setTimeout(180_000);
  let ran = '';
  await withCard(
    page,
    async () => {
      await conditionsOff(page);
      const ends = new Date(Date.parse(ran) + 120_000).toISOString();
      await expect(runOf(page), 'Run is held').toHaveAttribute('aria-disabled', 'true');
      await expect(runOf(page)).toHaveAccessibleDescription(`You can run it again at ${clock(ends, LOCALE, ZONE)}.`);
      await page.reload();
      await conditionsOff(page);
      await expect(runOf(page), 'after a reload it is still held, from LastRunNowAt').toHaveAttribute('aria-disabled', 'true');
      await expect(runOf(page)).toHaveAccessibleDescription(`You can run it again at ${clock(ends, LOCALE, ZONE)}.`);
      await expect(runOf(page), 'and enabled again when the cooldown ends, with no reload').not.toHaveAttribute('aria-disabled', 'true', {
        timeout: Math.max(Date.parse(ends) - Date.now(), 0) + 5_000,
      });
      await expect(card(page).getByText(/^You can run it again at/), 'the cooldown line leaves').toHaveCount(0);
    },
    async (ref) => {
      ran = at(-30_000);
      await writeRow(ref, { LastRunNowAt: ran, NextDueAt: at(24 * 60 * MINUTE) });
    },
  );
});

/** HC6: the cap and the missing key hold Run, and a press sends nothing. */
test('HC6: with dailyCap active Run is held with the cap reason, with noModelKey the key reason, the cap first, and a press sends no POST', async ({ page }) => {
  const CAPPED = { condition: 'dailyCap', active: true, slots: { cap: 20, time: '2030-01-01T17:30:00Z' } };
  let status: Array<Record<string, unknown>> = [CAPPED];
  await changeSnapshot(page, (snapshot) => {
    snapshot['status'] = status;
  });
  const posts: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === RUN) posts.push(request.url());
  });
  await withCard(page, async () => {
    await expect(runOf(page), 'with the cap active Run is held').toHaveAttribute('aria-disabled', 'true');
    await expect(runOf(page)).toHaveAccessibleDescription(CAP);
    await expect(card(page).getByText(CAP, { exact: true }), 'the reason shows').toBeVisible();
    await runOf(page).click({ force: true });
    await page.waitForTimeout(500);
    expect(posts, 'a press sends nothing').toEqual([]);

    status = [{ condition: 'noModelKey', active: true }];
    await page.reload();
    await expect(runOf(page), 'with only the key missing Run is held').toHaveAttribute('aria-disabled', 'true');
    await expect(runOf(page)).toHaveAccessibleDescription(NOKEY);
    await runOf(page).click({ force: true });
    await page.waitForTimeout(500);
    expect(posts, 'a press sends nothing').toEqual([]);

    status = [{ condition: 'noModelKey', active: true }, CAPPED];
    await page.reload();
    await expect(runOf(page)).toHaveAccessibleDescription(CAP);
    expect(posts, 'no POST in the whole case').toEqual([]);
  });
});

/** HC7: the online demo (DW-781). */
test('HC7: on the online demo the card is off with its note and the sample, and Run saves the sample first and then runs', async ({ page }) => {
  await rewriteGet(page, () => ({ onlineDemo: true, sample: true, on: false, checklist: SAMPLE }));
  const sent: string[] = [];
  page.on('request', (request) => {
    const path = new URL(request.url()).pathname;
    if ((path === HEARTBEAT || path === RUN) && request.method() !== 'GET') sent.push(`${request.method()} ${path === RUN ? 'run' : 'heartbeat'}`);
  });
  await page.route(`**${RUN}`, (route) => route.fulfill({ status: 202, json: { result: 'sent' } }));
  await withCard(page, async (ref) => {
    await conditionsOff(page);
    await expect(card(page).locator('p.line').first(), 'the card is off').toHaveText(OFF);
    await expect(card(page).getByText(DEMO_NOTE, { exact: true }), 'with the online-demo note').toBeVisible();
    await editOf(page).click();
    await expect(checklistOf(page), 'Edit holds the sample').toHaveValue(SAMPLE);
    await expect(onOf(page)).not.toBeChecked();
    await checklistOf(page).focus();
    await page.keyboard.press('Escape');
    await expect(editOf(page)).toHaveAttribute('aria-expanded', 'false');
    expect(await stored(ref, 'checklist'), 'nothing is stored before a press').toBe('none');

    await runOf(page).click();
    await expect(card(page).getByText(SAVED, { exact: true }), "the server's saved line shows").toBeVisible();
    await expect.poll(() => sent, { message: 'the card saved first and then ran' }).toEqual(['PUT heartbeat', 'POST run']);
    expect(await stored(ref, 'checklist'), 'the stored checklist is the sample').toBe(SAMPLE.replaceAll('\n', '~'));
    expect(await stored(ref, 'on'), 'with the heartbeat still off').toBe('0');
    await expect(runOf(page), 'the run is held for the cooldown').toHaveAttribute('aria-disabled', 'true');
  });
});

/** HC8: each outcome and each skip, from a rewritten answer. */
test('HC8: each outcome and each skip reads in the UX texts, and the Today line follows the count', async ({ page }) => {
  test.skip(nearMidnight(), 'a time within 40 minutes of midnight UTC is rendered with a day word');
  test.setTimeout(150_000);
  let shown: Record<string, unknown> = {};
  await rewriteGet(page, () => shown);
  const beat = at(-5 * MINUTE);
  const checkIn = (outcome: string, extra: Record<string, unknown> = {}): Record<string, unknown> => ({
    lastBeatAt: beat,
    lastOutcome: outcome,
    lastCostUSD: 0.0012,
    traceHeaderId: 4242,
    traceNamespace: 'OCUTALON',
    traceUrl: 'https://example.test/trace/4242',
    ...extra,
  });
  const time = clock(beat, LOCALE, ZONE);
  const skipAt = at(-2 * MINUTE);
  const backoff = at(30 * MINUTE);
  const cases: Array<[string, Record<string, unknown>, string]> = [
    ['ignore', checkIn('ignore'), `Last check-in ${time} \u00b7 Stayed quiet \u00b7 $0.0012 \u00b7 Trace`],
    ['tellnow', checkIn('tellnow'), `Last check-in ${time} \u00b7 Told you now \u00b7 $0.0012 \u00b7 Trace`],
    ['digest', checkIn('digest'), `Last check-in ${time} \u00b7 Saved for the digest \u00b7 $0.0012 \u00b7 Trace`],
    ['act', checkIn('act'), `Last check-in ${time} \u00b7 Offered an action \u00b7 $0.0012 \u00b7 Trace`],
    [
      'fallback',
      checkIn('tellnow', { lastFallback: true, lastFallbackReason: 'timeout' }),
      `Last check-in ${time} \u00b7 Couldn't decide: the model didn't answer within 60 seconds \u00b7 $0.0012 \u00b7 Trace`,
    ],
    ['pending', { lastBeatAt: beat }, `Last check-in ${time}`],
    ['unknown outcome', checkIn('zz_unknown'), `Last check-in ${time}`],
    ['skip empty', { ...checkIn('ignore'), lastSkipAt: skipAt, lastSkipReason: 'empty' }, `Skipped at ${clock(skipAt, LOCALE, ZONE)}: your checklist is empty.`],
    ['skip hours', { lastSkipAt: skipAt, lastSkipReason: 'hours' }, `Skipped at ${clock(skipAt, LOCALE, ZONE)}: outside your active hours.`],
    ['skip unchanged', { lastSkipAt: skipAt, lastSkipReason: 'unchanged' }, `Skipped at ${clock(skipAt, LOCALE, ZONE)}: nothing has changed since the last quiet check-in.`],
    ['skip cap', { lastSkipAt: skipAt, lastSkipReason: 'cap' }, `Skipped at ${clock(skipAt, LOCALE, ZONE)}: today's cost limit has been reached.`],
    ['skip nokey', { lastSkipAt: skipAt, lastSkipReason: 'nokey' }, `Skipped at ${clock(skipAt, LOCALE, ZONE)}: no model key is set.`],
    [
      'skip backoff',
      { lastSkipAt: skipAt, lastSkipReason: 'backoff', backoffUntil: backoff },
      `Skipped at ${clock(skipAt, LOCALE, ZONE)}: waiting after a failed check-in, until ${clock(backoff, LOCALE, ZONE)}.`,
    ],
  ];
  await withCard(page, async () => {
    for (const [label, answer, expected] of cases) {
      shown = { lastSkipAt: null, lastSkipReason: '', ...answer };
      await page.reload();
      await expect(lastOf(page), label).toHaveText(exactly(expected));
      if (label === 'ignore') await expect(lastOf(page).locator('app-trace-link'), 'a trace link ends the check-in line').toHaveCount(1);
    }
    const nextDueAt = at(30 * MINUTE);
    shown = { ...checkIn('ignore'), today: { checkIns: 3, costUSD: 0.0036 }, on: true, interval: 60, from: '07:15', to: '21:45', nextDueAt };
    await page.reload();
    await expect(todayOf(page), 'three check-ins read in the plural').toHaveText('Today: 3 check-ins, $0.0036');
    await expect(card(page).locator('p.line').first(), 'the on line holds the interval, the hours and the next check-in').toHaveText(
      `Every 1 hour, 07:15 to 21:45 \u00b7 Next check-in ${clock(nextDueAt, LOCALE, ZONE)}`,
    );
    shown = { today: { checkIns: 1, costUSD: 0.0012 }, on: true, interval: 1440, from: '', to: '', nextDueAt: null };
    await page.reload();
    await expect(todayOf(page), 'one check-in reads in the singular').toHaveText('Today: 1 check-in, $0.0012');
    await expect(card(page).locator('p.line').first(), 'all day with no next check-in is the interval alone').toHaveText('Every 24 hours');
    shown = { today: { checkIns: 0, costUSD: 0 } };
    await page.reload();
    await expect(todayOf(page), 'none today: no Today line').toHaveCount(0);
  });
});

/** HC9: Esc collapses Edit and gives it the focus. */
test('HC9: Esc in the open Edit collapses it and focuses Edit', async ({ page }) => {
  await withCard(page, async () => {
    await editOf(page).click();
    await expect(editOf(page)).toHaveAttribute('aria-expanded', 'true');
    await checklistOf(page).focus();
    await page.keyboard.press('Escape');
    await expect(editOf(page), 'the disclosure is collapsed').toHaveAttribute('aria-expanded', 'false');
    await expect(editOf(page), 'and Edit has focus').toBeFocused();
    await expect(checklistOf(page)).toHaveCount(0);
  });
});

const NOT_SAVED = "Couldn't save. Nothing was changed.";
const BUSY = "Couldn't reach OcuTalon. Try again. Nothing was changed.";
const EMPTY = 'Your checklist is empty.';

/** The id, among the ids that describe the control, that ends with the suffix. */
async function describer(control: Locator, suffix: string): Promise<string> {
  const ids = ((await control.getAttribute('aria-describedby')) ?? '').split(' ');
  const id = ids.find((one) => one.endsWith(suffix));
  expect(id, `the refusal is among the ids that describe the control (${ids.join(' ')})`).toBeTruthy();
  return id ?? '';
}

/** HC3b: each refusal of the PUT shows beside its own field, and a failure with no message shows the busy sentence under Save. */
test('HC3b: bad_hours, bad_interval and bad_on are shown beside their fields, marked invalid and described, and a 500 shows the busy sentence under Save', async ({ page }) => {
  let answer: { status: number; json: unknown } = { status: 400, json: { error: { code: 'bad_hours', message: NOT_SAVED } } };
  await page.route(`**${HEARTBEAT}`, (route) => (route.request().method() === 'PUT' ? route.fulfill(answer) : route.continue()));
  await withCard(page, async (ref) => {
    await editOf(page).click();
    await saveOf(page).click();
    for (const field of [fromOf(page), toOf(page)]) {
      await expect(field, 'bad_hours marks both hours').toHaveAttribute('aria-invalid', 'true');
      await expect(page.locator(`#${await describer(field, '-hours-error')}`), 'and shows the refusal beside them').toHaveText(NOT_SAVED);
    }
    await fromOf(page).selectOption('09:00');
    await expect(fromOf(page), 'changing an hour clears the refusal').not.toHaveAttribute('aria-invalid', 'true');

    answer = { status: 400, json: { error: { code: 'bad_interval', message: NOT_SAVED } } };
    await saveOf(page).click();
    await expect(intervalOf(page), 'bad_interval marks the interval').toHaveAttribute('aria-invalid', 'true');
    await expect(page.locator(`#${await describer(intervalOf(page), '-interval-error')}`)).toHaveText(NOT_SAVED);
    await expect(fromOf(page), 'and not the hours').not.toHaveAttribute('aria-invalid', 'true');

    answer = { status: 400, json: { error: { code: 'bad_on', message: NOT_SAVED } } };
    await saveOf(page).click();
    await expect(onOf(page), 'bad_on marks On').toHaveAttribute('aria-invalid', 'true');
    await expect(page.locator(`#${await describer(onOf(page), '-on-error')}`)).toHaveText(NOT_SAVED);

    answer = { status: 500, json: {} };
    await saveOf(page).click();
    await expect(card(page).locator('.field-error').filter({ hasText: BUSY }), 'a failure with no message shows the busy sentence under Save').toHaveCount(1);
    expect(await stored(ref, 'interval'), 'nothing was stored').toBe('none');
  });
});

/** HC9b: in the drawer band, the first Esc collapses the disclosure only, and the next one closes the drawer. */
test('HC9b: in the drawer band the first Esc collapses Edit only, and the next one closes the drawer', async ({ page }) => {
  await withCard(page, async () => {
    await page.setViewportSize({ width: 1100, height: 720 });
    const status = page.locator('button.status-button');
    await status.click();
    await expect(status, 'the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await editOf(page).click();
    await checklistOf(page).focus();
    await page.keyboard.press('Escape');
    await expect(editOf(page), 'the disclosure is collapsed').toHaveAttribute('aria-expanded', 'false');
    await expect(editOf(page), 'Edit has focus').toBeFocused();
    await expect(status, 'and the drawer stays open').toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(status, 'the next Esc closes the drawer').toHaveAttribute('aria-expanded', 'false');
  });
});

/** HC10: a refused or failed Run shows what the matrix says, and on the online demo a failed save sends no run. */
test('HC10: a 409 cooldown holds Run to its time, a 409 empty and a 500 show their messages under it, and a failed save of the sample sends no POST', async ({ page }) => {
  test.skip(nearMidnight(), 'a time within 40 minutes of midnight UTC is rendered with a day word');
  const posts: string[] = [];
  let availableAt = '';
  let answer: { status: number; json: unknown } = { status: 409, json: {} };
  await page.route(`**${RUN}`, (route) => {
    posts.push(route.request().method());
    return route.fulfill(answer);
  });
  await withCard(page, async () => {
    await conditionsOff(page);
    availableAt = at(10 * MINUTE);
    answer = { status: 409, json: { error: { code: 'cooldown', message: 'zz' }, availableAt } };
    await runOf(page).click();
    await expect(runOf(page), 'a 409 cooldown holds Run').toHaveAttribute('aria-disabled', 'true');
    await expect(runOf(page)).toHaveAccessibleDescription(`You can run it again at ${clock(availableAt, LOCALE, ZONE)}.`);
    expect(posts, 'one POST').toEqual(['POST']);

    await page.reload();
    await conditionsOff(page);
    answer = { status: 409, json: { error: { code: 'empty', message: EMPTY } } };
    await runOf(page).click();
    await expect(card(page).locator('.field-error').filter({ hasText: EMPTY }), 'a 409 empty shows its message under the button').toHaveCount(1);
    await expect(runOf(page), 'and leaves Run enabled').not.toHaveAttribute('aria-disabled', 'true');

    answer = { status: 500, json: { error: { code: 'server_error', message: 'zz The run failed.' } } };
    await runOf(page).click();
    await expect(card(page).locator('.field-error').filter({ hasText: BUSY }), 'a 500 shows the busy sentence under the button').toHaveCount(1);
    await expect(card(page).getByText('zz The run failed.'), "and not the 500's own message").toHaveCount(0);
    await expect(card(page).locator('.field-error').filter({ hasText: EMPTY }), 'in place of the earlier message').toHaveCount(0);
  });
});

/** HC10b: on the online demo a refused save of the sample shows its message under Run and sends no POST. */
test('HC10b: on the online demo a refused save of the sample shows its message under Run and sends no run', async ({ page }) => {
  await rewriteGet(page, () => ({ onlineDemo: true, sample: true, on: false, checklist: SAMPLE }));
  await page.route(`**${HEARTBEAT}`, (route) =>
    route.request().method() === 'PUT' ? route.fulfill({ status: 400, json: { error: { code: 'bad_checklist', message: BAD_CHECKLIST } } }) : route.fallback(),
  );
  const posts: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === RUN) posts.push(request.url());
  });
  await withCard(page, async (ref) => {
    await conditionsOff(page);
    await runOf(page).click();
    await expect(card(page).locator('.field-error').filter({ hasText: BAD_CHECKLIST }), "the failed save's message shows under Run").toHaveCount(1);
    await page.waitForTimeout(500);
    expect(posts, 'no run was sent').toEqual([]);
    expect(await stored(ref, 'checklist'), 'nothing was stored').toBe('none');
  });
});

/** Publishes a `heartbeat` event on the session's stream, as the Checks job does after a beat. Returns its Seq. */
async function publishHeartbeat(ref: string, lastBeatAt: string): Promise<number> {
  const lines = await irisScript(
    [
      'Set p=##class(OcuTalon.Live.Payload.Heartbeat).%New()',
      'Set p.On=1, p.Interval=30',
      `Set p.LastBeatAt=${quoted(lastBeatAt)}`,
      `Set sc=##class(OcuTalon.Live.Publish).Publish(${quoted(ref)},"heartbeat",p,.q)`,
      'Write !,"CHK|seq|",$Select($System.Status.IsOK(sc):q,1:0)',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the heartbeat event could not be published (${lines.join(' ')})`);
  return seq;
}

/**
 * HC11: a `heartbeat` event makes the card read again with no reload, and a failed read leaves the section heading alone until the next event.
 * The events are published as the Checks job publishes them; the GET is rewritten, so that no real tick can change the answer.
 */
test('HC11: a heartbeat event shows the new state with no reload, a failed read leaves the heading only, and the next event reads again', async ({ page }) => {
  test.skip(nearMidnight(), 'a time within 40 minutes of midnight UTC is rendered with a day word');
  let failing = false;
  let shown: Record<string, unknown> = {};
  await page.route(`**${HEARTBEAT}`, async (route) => {
    if (route.request().method() !== 'GET') return route.continue();
    if (failing) return route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } });
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    return route.fulfill({ response, json: { ...body, ...shown } });
  });
  await withCard(page, async (ref) => {
    await page.evaluate(() => {
      (globalThis as unknown as Record<string, unknown>)['hc11'] = 'same page';
    });
    failing = true;
    const failed = page.waitForResponse((response) => new URL(response.url()).pathname === HEARTBEAT && response.request().method() === 'GET' && response.status() === 500);
    await applied(page, await publishHeartbeat(ref, at(-10 * MINUTE)));
    await failed;
    await expect(railOf(page).getByRole('heading', { level: 3, name: 'Heartbeat checklist', exact: true }), 'the heading shows').toBeVisible();
    await expect(card(page), 'the card is drawn').toHaveCount(1);
    await expect(runOf(page), 'with no Run').toHaveCount(0);
    await expect(editOf(page), 'and no Edit').toHaveCount(0);
    expect(((await card(page).textContent()) ?? '').trim(), 'and no text').toBe('');

    failing = false;
    const beat = at(-5 * MINUTE);
    shown = {
      lastSkipAt: null,
      lastSkipReason: '',
      lastBeatAt: beat,
      lastOutcome: 'ignore',
      lastCostUSD: 0.0012,
      traceHeaderId: 4242,
      traceNamespace: 'OCUTALON',
      traceUrl: 'https://example.test/trace/4242',
      today: { checkIns: 1, costUSD: 0.0012 },
    };
    await applied(page, await publishHeartbeat(ref, beat));
    await expect(lastOf(page), 'the next event reads again: the new check-in shows').toHaveText(exactly(`Last check-in ${clock(beat, LOCALE, ZONE)} \u00b7 Stayed quiet \u00b7 $0.0012 \u00b7 Trace`));
    await expect(todayOf(page), 'and Today follows').toHaveText('Today: 1 check-in, $0.0012');
    expect(await page.evaluate(() => (globalThis as unknown as Record<string, unknown>)['hc11']), 'all of it on the same page, with no reload').toBe('same page');
  });
});

/** HC12: a failed save whose re-read fails too takes the card away, and focus on Save goes to the Heartbeat heading. */
test('HC12: when a failed save reads again and that read fails, the card leaves and focus on Save goes to the Heartbeat heading', async ({ page }) => {
  let failing = false;
  await page.route(`**${HEARTBEAT}`, (route) => {
    if (route.request().method() === 'PUT') return route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The save failed.' } } });
    return failing ? route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'zz The read failed.' } } }) : route.continue();
  });
  await withCard(page, async () => {
    await editOf(page).click();
    await checklistOf(page).fill('zz hc12');
    failing = true;
    await saveOf(page).focus();
    await expect(saveOf(page), 'Save holds focus').toBeFocused();
    await page.keyboard.press('Enter');
    await expect(runOf(page), 'the card leaves with the failed read').toHaveCount(0);
    await expect(page.locator('#rail-heading-heartbeat'), 'and focus goes to the Heartbeat heading').toBeFocused();
  });
});

/** The last Seq of the instance stream, where the status monitor publishes its conditions. */
async function instanceSeq(): Promise<number> {
  const seq = Number(chk(await irisScript('Write !,"CHK|seq|",##class(OcuTalon.Live.Publish).LastSeq("instance")'), 'seq'));
  if (!Number.isInteger(seq) || seq < 0) throw new Error('the last Seq of the instance stream could not be read');
  return seq;
}

/** Waits up to 30 seconds (two runs of the status monitor) for its noModelKey event after the mark; none comes when the reading did not change. */
async function monitorSettled(mark: number): Promise<void> {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const lines = await irisScript(
      [
        `Set r=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM OcuTalon_Live.Event WHERE Stream = 'instance' AND Seq > ? AND Type = 'status' AND Payload [ 'noModelKey'",${mark})`,
        'Do r.%Next()',
        'Write !,"CHK|events|",+r.%Get("n")',
      ].join('\n'),
    );
    if (Number(chk(lines, 'events')) > 0) return;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
}

/**
 * HC4: Integration. The real routes and the real tick, with the CI mock as the model. Its afterAll waits for the status monitor's noModelKey
 * event of the restored keys, so that the event lands before the next case or file and not in it.
 */
test.describe('HC4 (Integration)', () => {
  test.beforeAll(async () => {
    test.setTimeout(240_000);
    await pointKeys();
    const lines = await irisScript(
      [
        'Set reason=##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()',
        'Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))',
        'Write !,"CHK|ready|",reason',
        'Write !,"CHK|keyed|",##class(OcuTalon.Bridge.Keys).Status(##class(OcuTalon.Checks.Beat).#AGENT)',
      ].join('\n'),
    );
    expect(chk(lines, 'ready'), `the production is ready (${lines.join(' ')})`).toBe('');
    expect(chk(lines, 'keyed'), 'and the TriageAgent has its key').toBe('1');
  });

  test.afterAll(async () => {
    test.setTimeout(240_000);
    const mark = await instanceSeq();
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
      await monitorSettled(mark);
    }
  });

  test('HC4: a saved checklist runs now, Run is held for the cooldown, and the outcome and Today arrive with no reload', async ({ page }) => {
    test.setTimeout(240_000);
    await withCard(page, async (ref) => {
      await conditionsOff(page);
      const checklist = `zz hc4 [[mock:heartbeat-ignore:${ref}]]`;
      await editOf(page).click();
      await onOf(page).uncheck();
      await checklistOf(page).fill(checklist);
      await saveOf(page).click();
      await expect(card(page).getByText(SAVED, { exact: true })).toBeVisible();
      const savedAt = Date.now();
      expect(await stored(ref, 'on'), 'the heartbeat is stored off, so that no tick runs it').toBe('0');

      await page.reload();
      await conditionsOff(page);
      await editOf(page).click();
      await expect(onOf(page), 'after a reload Edit shows the saved values').not.toBeChecked();
      await expect(checklistOf(page)).toHaveValue(checklist);
      await page.evaluate(() => {
        (globalThis as unknown as Record<string, unknown>)['hc4'] = 'same page';
      });

      // The settings are cached for 60 seconds in every process (AD-19, "Applies within a minute"), and the tick of the Checks job has read this account's
      // empty checklist since the case began: a run before the cache entry is gone would answer 409 empty and start the cooldown.
      await page.waitForTimeout(Math.max(0, savedAt + APPLY_MS - Date.now()));
      const answered = page.waitForResponse((response) => new URL(response.url()).pathname === RUN && response.request().method() === 'POST');
      await runOf(page).click();
      const response = await answered;
      expect(response.status(), `Run is accepted (${await response.text()})`).toBe(202);
      await expect(runOf(page), 'the button is held for the cooldown').toHaveAttribute('aria-disabled', 'true');
      await expect(runOf(page)).toHaveAccessibleDescription(/^You can run it again at \d{1,2}:\d\d\.$/);

      await expect(lastOf(page), 'from the tick, with no reload: the outcome, the cost and a trace link').toHaveText(/^Last check-in \d{1,2}:\d\d \u00b7 Stayed quiet \u00b7 \$\d+\.\d+ \u00b7 Trace/, {
        timeout: 120_000,
      });
      await expect(lastOf(page).locator('app-trace-link'), 'the Trace link is there').toHaveCount(1);
      await expect(todayOf(page), 'and Today counts the check-in').toHaveText(/^Today: 1 check-in, \$\d+\.\d+$/);
      await expect(runOf(page), 'Run is still held').toHaveAttribute('aria-disabled', 'true');
      expect(await page.evaluate(() => (globalThis as unknown as Record<string, unknown>)['hc4']), 'all of it on the same page, with no reload').toBe('same page');
    });
  });
});
