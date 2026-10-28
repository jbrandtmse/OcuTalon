import { expect, test, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { STATE } from '../support/api';
import { banner, mainOf, rowOf, unique } from '../support/floor';
import { chk, cleanFixtureRows, fixtureUser, irisScript, seedCheck } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 8.2, the heartbeat-stalled warning that comes from the real heartbeat (FR-32, NFR-9, AD-12, AD-18, AD-33), in a real browser
 * against a real stack. It is the one case that stalls the real heartbeat: it signs in as the banners fixture user that test-sign-in.sh
 * created (OCUTALON_BANNERS_USER), with one seeded production check, and calls OcuTalon.Test.Schedule.StallFixture, each step in its own
 * iris session. Hold suspends the real task and sets the tick mark 4 minutes back; StatusMonitor's own job then publishes the condition on the
 * instance stream, and the page, which polls that stream, shows the banner and the "(late)" mark. Tick writes a real tick; /state is clear
 * at once, and StatusMonitor's next run publishes the clear. A step that checks a live update waits until the page has applied the Seq of
 * the event (data-instance-seq) and then asserts within one second, and the announcer within one live update. afterEach runs Release, also
 * after a failure or a timeout: it puts the task back as found and writes a real tick, so that the heartbeat is fresh for the specs after it.
 * The two events it causes stay on the instance stream for the rest of the run. api.spec reads that stream against a baseline that each of
 * its tests takes itself, so it passes whether or not this file ran before it. The browser runs in Asia/Kolkata with the en-GB locale, so a
 * time (instance zone UTC) reads differently.
 */
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' });

/** The case waits for StatusMonitor's runs (15 s apart) twice, and for the fixture's own waits. */
test.setTimeout(90_000);

/** The middle dot between the parts of a meta line, with its spaces. */
const DOT = ' \u00B7 ';

/** How long the page may take to apply an event after StatusMonitor published it: the live poll (1 to 2 s) and the render. */
const APPLIED_MS = 15_000;

/** The bound of "within one live update", counted from the page having applied the event. */
const ONE_UPDATE_MS = 1000;

/** The bound of the announcer reading the banner: one live update (NFR-9's 2 s), which covers the announce queue's 1 s gap after a text. */
const ANNOUNCED_MS = 2000;

const FIXTURE = 'OcuTalon.Test.Schedule.StallFixture';

/** The fixture rows that the case seeded, which afterEach removes. */
const refs: string[] = [];

/** An ISO time as the page shows it: hour and minute in the browser's zone and locale, as the page's own pageTime formats it. */
const pageTime = (iso: string): string => new Intl.DateTimeFormat('en-GB', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Kolkata' }).format(new Date(iso));

/**
 * The meta line of the seeded check: "Last run {when}", with " (late)" while the heartbeat is stalled, and its result. {when} is the page
 * time of the last run, after a day ("Saturday at 23:59") when a run just after midnight in the browser's zone puts the last run on the
 * page's previous date.
 */
const lastRun = (ranAt: string, late: boolean): RegExp =>
  new RegExp(`^Last run (?:\\S.* at )?${pageTime(ranAt)}${late ? ' \\(late\\)' : ''}${DOT}Passed$`);

/** The text of the banner for the heartbeat that last ran at this time. */
const stalledText = (time: string): string =>
  `Background checks have paused: the heartbeat last ran at ${time}. Watches and reminders may be late until it recovers.`;

/** The value that a fixture call printed as CHK|<name>|..., which it must have printed. */
async function call(name: string, statement: string): Promise<string> {
  const lines = await irisScript(`${statement}\nWrite !,"CHK|${name}|",value`);
  const value = chk(lines, name);
  if (value === undefined) throw new Error(`${FIXTURE} did not answer ${name} (${lines.join(' ')})`);
  return value;
}

/** Waits until the page has applied the event of this Seq on the instance stream. */
async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-instance-seq')), { message: `the page applied Seq ${seq} of the instance stream`, timeout: APPLIED_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** The heartbeatStalled members of the status array that /state answers to the page's own session. */
async function stalledInState(page: Page): Promise<unknown[]> {
  const response = await page.request.get(STATE);
  expect(response.status()).toBe(200);
  const body = (await response.json()) as { status: Array<{ condition: string }> };
  return body.status.filter((one) => one.condition === 'heartbeatStalled');
}

/** Release and the seeded rows' removal, also after a failure or a timeout of the case; a Release that does not end OK fails it. */
test.afterEach(async () => {
  const released = await call('release', `Set value=##class(${FIXTURE}).Release()`).catch(() => undefined);
  await cleanFixtureRows(refs.splice(0));
  if (released?.trim() !== '1') throw new Error(`${FIXTURE}.Release did not end OK, so the heartbeat may still be stalled (${released ?? 'no answer'})`);
});

test('H1: the heartbeat-stalled banner and the late mark follow the real heartbeat, and clear when a real tick is written', async ({ page }) => {
  const { user, password } = fixtureUser('BANNERS');
  const stamp = unique('H1');
  const ranAt = new Date(Date.now() - 60_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  refs.push(await seedCheck(user, { displayName: stamp, lastRunAt: ranAt, result: 'passed', finding: '' }));
  await recordAnnouncements(page);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const row = rowOf(page, stamp);
  const stalled = banner(page, 'heartbeatStalled');
  await expect(row.locator('.meta'), 'before the stall the check reads its last run').toHaveText(lastRun(ranAt, false));
  await expect(stalled, 'with no heartbeat banner').toHaveCount(0);

  const since = Number(await call('seq', `Set value=##class(${FIXTURE}).InstanceSeq()`));
  const mark = await call('mark', `Set value=##class(${FIXTURE}).Hold(240)`);
  expect(mark, 'the tick mark is a UTC time to the second').toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  const seqOn = Number(await call('seq', `Set value=##class(${FIXTURE}).WaitEvent(${since},1,30)`));
  expect(seqOn, 'StatusMonitor published the onset within 30 s').toBeGreaterThan(0);
  await applied(page, seqOn);

  const text = stalledText(pageTime(mark));
  await expect(stalled, 'the banner appears within one live update').toHaveCount(1, { timeout: ONE_UPDATE_MS });
  await expect(stalled.locator('.text'), 'with the page time of the tick').toHaveText(text, { timeout: ONE_UPDATE_MS });
  await expect(row.locator('.meta'), 'the check row reads (late)').toHaveText(lastRun(ranAt, true), { timeout: ONE_UPDATE_MS });
  await expect.poll(() => announcements(page, text), { message: 'the banner is announced within one live update', timeout: ANNOUNCED_MS }).toBe(1);
  expect(await stalledInState(page), '/state of the session holds the condition with the tick as its time').toEqual([
    { condition: 'heartbeatStalled', active: true, slots: { time: mark } },
  ]);

  expect((await call('tick', `Set value=##class(${FIXTURE}).Tick()`)).trim(), 'the real tick ended OK').toBe('1');
  expect(await stalledInState(page), 'after a real tick /state holds no heartbeatStalled at once').toEqual([]);
  const seqOff = Number(await call('seq', `Set value=##class(${FIXTURE}).WaitEvent(${seqOn},0,30)`));
  expect(seqOff, 'StatusMonitor published the clear within 30 s').toBeGreaterThan(0);
  await applied(page, seqOff);
  await expect(stalled, 'the banner is gone within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
  await expect(row.locator('.meta'), 'and so is the late mark').toHaveText(lastRun(ranAt, false), { timeout: ONE_UPDATE_MS });
  await page.waitForTimeout(1500);
  expect(await announcements(page, text), 'the banner was announced once in the whole test').toBe(1);
});
