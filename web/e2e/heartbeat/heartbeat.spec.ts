import { expect, test, type Locator, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { STATE } from '../support/api';
import { chk, cleanFixtureRows, fixtureUser, irisScript, seedCheck } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 8.2, the heartbeat-stalled warning that comes from the real heartbeat (FR-32, NFR-9, AD-12, AD-18, AD-33), in a real browser
 * against a real stack. It is the one case that stalls the real heartbeat: it signs in as the banners fixture user that test-sign-in.sh
 * created (OCUTALON_BANNERS_USER), with one seeded production check, and calls OcuTalon.Test.Schedule.StallFixture, each step in its own
 * iris session. Hold suspends the real task and sets the tick mark 4 minutes back; StatusMonitor's own job then publishes the condition on the
 * instance stream, and the page, which polls that stream, shows the banner and the "(late)" mark. Tick writes a real tick; /state is clear
 * at once, and StatusMonitor's next run publishes the clear. A step that checks a live update waits until the page has applied the Seq of
 * the event (data-instance-seq) and then asserts within one second. Release, in finally, puts the task and the mark back as found.
 * The two events it causes on the instance stream come after api.spec, which pins that stream at one event (Playwright runs the files in
 * path order, with one worker). The browser runs in Asia/Kolkata with the en-GB locale, so a time (instance zone UTC) reads differently.
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

const FIXTURE = 'OcuTalon.Test.Schedule.StallFixture';

const mainOf = (page: Page): Locator => page.locator('main.main');
const bannerOf = (page: Page): Locator => page.locator('.banner-slot [data-banner="heartbeatStalled"]');
const rowOf = (page: Page, marker: string): Locator => page.getByRole('region', { name: 'Status', exact: true }).locator('li.row').filter({ hasText: marker });

/** An ISO time as the page shows it: hour and minute in the browser's zone and locale, as the page's own pageTime formats it. */
const pageTime = (iso: string): string => new Intl.DateTimeFormat('en-GB', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Kolkata' }).format(new Date(iso));

/** The text of the banner for the heartbeat that last ran at this time. */
const stalledText = (time: string): string =>
  `Background checks have paused: the heartbeat last ran at ${time}. Watches and reminders may be late until it recovers.`;

/** A text no other case or run made. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

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

test('H1: the heartbeat-stalled banner and the late mark follow the real heartbeat, and clear when a real tick is written', async ({ page }) => {
  const { user, password } = fixtureUser('BANNERS');
  const refs: string[] = [];
  let released: string | undefined;
  try {
    const stamp = unique('H1');
    const ranAt = new Date(Date.now() - 60_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    refs.push(await seedCheck(user, { displayName: stamp, lastRunAt: ranAt, result: 'passed', finding: '' }));
    await recordAnnouncements(page);
    await signIn(page, user, password);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    const row = rowOf(page, stamp);
    await expect(row.locator('.meta'), 'before the stall the check reads its last run').toHaveText(`Last run ${pageTime(ranAt)}${DOT}Passed`);
    await expect(bannerOf(page), 'with no heartbeat banner').toHaveCount(0);

    const since = Number(await call('seq', `Set value=##class(${FIXTURE}).InstanceSeq()`));
    const mark = await call('mark', `Set value=##class(${FIXTURE}).Hold(240)`);
    expect(mark, 'the tick mark is a UTC time to the second').toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    const seqOn = Number(await call('seq', `Set value=##class(${FIXTURE}).WaitEvent(${since},1,30)`));
    expect(seqOn, 'StatusMonitor published the onset within 30 s').toBeGreaterThan(0);
    await applied(page, seqOn);

    const text = stalledText(pageTime(mark));
    await expect(bannerOf(page), 'the banner appears within one live update').toHaveCount(1, { timeout: ONE_UPDATE_MS });
    await expect(bannerOf(page).locator('.text'), 'with the page time of the tick').toHaveText(text);
    await expect(row.locator('.meta'), 'the check row reads (late)').toHaveText(`Last run ${pageTime(ranAt)} (late)${DOT}Passed`, { timeout: ONE_UPDATE_MS });
    await expect.poll(() => announcements(page, text), { message: 'the banner is announced', timeout: 5000 }).toBe(1);
    expect(await stalledInState(page), '/state of the session holds the condition with the tick as its time').toEqual([
      { condition: 'heartbeatStalled', active: true, slots: { time: mark } },
    ]);

    await call('tick', `Set value=##class(${FIXTURE}).Tick()`);
    expect(await stalledInState(page), 'after a real tick /state holds no heartbeatStalled at once').toEqual([]);
    const seqOff = Number(await call('seq', `Set value=##class(${FIXTURE}).WaitEvent(${seqOn},0,30)`));
    expect(seqOff, 'StatusMonitor published the clear within 30 s').toBeGreaterThan(0);
    await applied(page, seqOff);
    await expect(bannerOf(page), 'the banner is gone within one live update').toHaveCount(0, { timeout: ONE_UPDATE_MS });
    await expect(row.locator('.meta'), 'and so is the late mark').toHaveText(`Last run ${pageTime(ranAt)}${DOT}Passed`, { timeout: ONE_UPDATE_MS });
    await page.waitForTimeout(1500);
    expect(await announcements(page, text), 'the banner was announced once in the whole test').toBe(1);
  } finally {
    released = await call('release', `Set value=##class(${FIXTURE}).Release()`).catch(() => undefined);
    await cleanFixtureRows(refs);
    if (released?.trim() !== '1') throw new Error(`${FIXTURE}.Release did not end OK, so the heartbeat may still be stalled (${released ?? 'no answer'})`);
  }
});
