import { expect, test, type Locator, type Page } from '@playwright/test';

import { signInReadme } from '../sign-in/helpers';
import { changeSnapshot, STATE } from '../support/api';
import { composerOf, mainOf, railOf, signInReadmeLoaded } from '../support/floor';
import { announcedTexts, recordAnnouncements } from '../support/page';

/**
 * The Demo view switch on the real server switch (Story 4.9, matrix rows 1 to 9; docker/tests/test-demo-switch.sh runs this folder with
 * demo mode really off, then on again, OCUTALON_E2E_DEMO_MODE). V0 runs in mode 0 only: no switch on a server with demo mode off, and a
 * page that the switch turned off has the structure of that page. V1 to V9 run in mode 1: the switch itself (V1), the page with the switch
 * off against the page of a server with demo mode off (V2), a chat turn with the switch off (V3), the guide's return (V4), the header's
 * fit and markers (V5, in two cases: the online demo, and the local demo's pill), a storage that throws (V6), the Telegram card (V7), a
 * failed snapshot (V8) and the stored values (V9). The comparison is of structure (landmarks and regions, skip links, rail headings,
 * main's right edge), never pixels. The file sorts last of the folder, so V3's turn on the README session comes after every other spec
 * file and after the runner's chat checks; no case counts that session's turns.
 */
function stackMode(): '0' | '1' {
  const mode = process.env['OCUTALON_E2E_DEMO_MODE'];
  if (mode !== '0' && mode !== '1') {
    throw new Error('OCUTALON_E2E_DEMO_MODE must be 1 (demo mode on) or 0 (demo mode off)');
  }
  return mode;
}

const HELP = 'Off shows the page as it looks on your own install.';
const KEY = 'ocutalon.demoView.off';
const EMPTY_CHAT = 'Ask OcuTalon to watch a production, set a reminder, or say what you need.';
const EMPTY_CHECKS = 'Ask OcuTalon to watch a production.';
const SKIP_DEVICES = 'Skip to simulated devices';
const LABELS = ['Watch', 'Reminder', 'Break the feed', 'Approve', 'Open the trace'];

const demoView = (page: Page): Locator => page.getByRole('switch', { name: 'Demo view', exact: true });
const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const devicesRegion = (page: Page): Locator => page.getByRole('region', { name: 'Simulated devices' });
const stepName = (n: number, state: 'current' | 'done' | 'upcoming'): string => `Step ${n}, ${LABELS[n - 1]}, ${state}`;
const stepOf = (page: Page, n: number, state: 'current' | 'done' | 'upcoming'): Locator => guideRegion(page).getByRole('button', { name: stepName(n, state), exact: true });

/** What the page shows as structure: its landmarks and regions, the skip links, the rail's headings without counts, and whether main reaches the viewport's right edge. */
interface Structure {
  landmarks: string[];
  skipLinks: string[];
  railHeadings: string[];
  mainReachesRight: boolean;
}

async function structure(page: Page): Promise<Structure> {
  return page.evaluate(() => {
    const ROLES: Record<string, string> = { header: 'banner', main: 'main', nav: 'navigation', aside: 'complementary', footer: 'contentinfo', section: 'region' };
    const nameOf = (el: Element): string => {
      const label = el.getAttribute('aria-label');
      if (label !== null) return label;
      const ids = (el.getAttribute('aria-labelledby') ?? '').split(/\s+/).filter(Boolean);
      return ids.map((id) => document.getElementById(id)?.textContent?.trim() ?? '').join(' ');
    };
    const landmarks = Array.from(
      document.querySelectorAll('header, main, nav, aside, footer, section[aria-label], section[aria-labelledby], [role="region"], [role="banner"], [role="main"], [role="navigation"], [role="complementary"], [role="search"]'),
    ).map((el) => `${el.getAttribute('role') ?? ROLES[el.tagName.toLowerCase()] ?? ''}: ${nameOf(el)}`);
    const skipLinks = Array.from(document.querySelectorAll('app-skip-links a')).map((el) => el.textContent?.trim() ?? '');
    const railHeadings = Array.from(document.querySelectorAll('section.rail h3')).map((el) => (el.querySelector('span')?.textContent ?? el.textContent ?? '').replace(/\s*\(\d+\)\s*$/, '').trim());
    const main = document.querySelector('main.main')!.getBoundingClientRect();
    return { landmarks, skipLinks, railHeadings, mainReachesRight: Math.abs(main.right - document.documentElement.clientWidth) <= 1 };
  });
}

/** Makes the page start with the switch off in this tab. */
async function startOff(page: Page): Promise<void> {
  await page.addInitScript((key) => sessionStorage.setItem(key, '1'), KEY);
}

/** Empties the snapshot's chat and the rail's approvals and checks, so that the empty lines show whatever the README session holds. */
function emptied(snapshot: Record<string, unknown>): void {
  snapshot['chat'] = [];
  const rail = snapshot['rail'] as { approvals: unknown[]; checks: unknown[] };
  rail.approvals = [];
  rail.checks = [];
}

/** Another tab of the page's browser, with the snapshot changed and the switch off or not, loaded. */
async function otherTab(page: Page, change: (snapshot: Record<string, unknown>) => void, off: boolean): Promise<Page> {
  const tab = await page.context().newPage();
  await changeSnapshot(tab, change);
  if (off) await startOff(tab);
  await tab.goto('/ocutalon/');
  await expect(mainOf(tab)).toHaveAttribute('data-snapshot', 'loaded');
  return tab;
}

/** A guide view whose first `done` steps are done and whose current step is the next. */
function guideOf(done: number): Record<string, unknown> {
  return {
    runEpoch: 1,
    step: Math.min(5, done + 1),
    finished: false,
    steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: step <= done })),
    breakFeed: { active: false, reason: 'not_watching' },
    step4Variant: 'unpaired',
    telegramRow: false,
  };
}

/** True when the page does not scroll across. */
const fits = (page: Page): Promise<boolean> => page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth && document.body.scrollWidth <= document.documentElement.clientWidth);

/** True when the header's right group ends inside the header. */
async function rightGroupInside(page: Page): Promise<boolean> {
  const header = (await page.locator('app-header .header').boundingBox())!;
  const right = (await page.locator('app-header .side.right').boundingBox())!;
  return right.x >= header.x - 0.5 && right.x + right.width <= header.x + header.width + 0.5;
}

test('V0: a server with demo mode off has no Demo view switch, and a page that the switch turned off has its structure', async ({ page }) => {
  test.skip(stackMode() !== '0', 'mode 0 only');
  await signInReadmeLoaded(page);
  await expect(page.getByRole('switch'), 'demo mode is off on the server: no switch').toHaveCount(0);
  const real = await structure(page);

  const tab = await otherTab(page, (snapshot) => (snapshot['demoMode'] = true), true);
  await expect(demoView(tab), 'a snapshot that says demo mode shows the switch').toBeVisible();
  await expect(demoView(tab), 'which is off in this tab').toHaveAttribute('aria-checked', 'false');
  expect(await structure(tab), 'and the page has the structure of the page of a server with demo mode off').toEqual(real);
});

test('V1: the switch is a native switch named Demo view, described by its help, kept per tab, and sends and says nothing', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await recordAnnouncements(page);
  await signInReadmeLoaded(page);

  const sw = demoView(page);
  await expect(sw, 'on by default').toHaveAttribute('aria-checked', 'true');
  await expect(sw).toHaveAccessibleName('Demo view');
  await expect(sw, 'described by the help text').toHaveAccessibleDescription(HELP);
  expect(await sw.evaluate((el) => el.tagName), 'a native button').toBe('BUTTON');
  const afterBadge = await page.evaluate(() => {
    const badge = document.querySelector('app-header .context-badge')!;
    const sw = document.querySelector('app-header [role="switch"]')!;
    return !!(badge.compareDocumentPosition(sw) & Node.DOCUMENT_POSITION_FOLLOWING);
  });
  expect(afterBadge, 'it sits after the badge').toBe(true);
  await sw.hover();
  await expect(page.locator('app-tooltip'), 'its pointer tooltip is the help text').toHaveText(HELP);
  await page.mouse.move(0, 0);
  await expect(page.locator('app-tooltip'), 'which goes when the pointer leaves').toHaveCount(0);

  const requests: string[] = [];
  page.on('request', (request) => requests.push(`${request.method()} ${new URL(request.url()).pathname}`));
  const heard = await announcedTexts(page);

  await sw.focus();
  await page.keyboard.press('Space');
  await expect(sw, 'Space turns it off').toHaveAttribute('aria-checked', 'false');
  await expect(sw, 'focus stays on it').toBeFocused();
  await page.keyboard.press('Enter');
  await expect(sw, 'Enter turns it on').toHaveAttribute('aria-checked', 'true');
  await expect(sw).toBeFocused();
  await sw.click();
  await expect(sw, 'a click turns it off').toHaveAttribute('aria-checked', 'false');
  await expect(sw).toBeFocused();
  await page.waitForTimeout(1500);

  expect(requests.filter((request) => !/^GET \/ocutalon\/api\/v1\/events$/.test(request)), 'no request but the poll').toEqual([]);
  expect(await announcedTexts(page), 'nothing was announced').toEqual(heard);

  await page.reload();
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(demoView(page), 'the reload keeps it off').toHaveAttribute('aria-checked', 'false');

  const tab = await page.context().newPage();
  await tab.goto('/ocutalon/');
  await expect(mainOf(tab)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(demoView(tab), 'a new tab starts on').toHaveAttribute('aria-checked', 'true');
});

test('V2: with the switch off the page is the page of a server with demo mode off, and on brings the demo parts back', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await startOff(page);
  await changeSnapshot(page, emptied);
  await signInReadmeLoaded(page);

  await expect(demoView(page)).toHaveAttribute('aria-checked', 'false');
  await expect(guideRegion(page), 'no Demo guide').toHaveCount(0);
  await expect(page.locator('app-break-feed-box'), 'no Break the feed box').toHaveCount(0);
  await expect(devicesRegion(page), 'no Simulated devices').toHaveCount(0);
  await expect(page.getByRole('link', { name: SKIP_DEVICES, exact: true }), 'no skip link to the devices').toHaveCount(0);
  expect((await structure(page)).mainReachesRight, "main ends at the viewport's right edge").toBe(true);
  await expect(page.getByRole('main').locator('app-empty-chat .line').last(), 'the non-demo empty chat line').toHaveText(EMPTY_CHAT);
  await expect(railOf(page).locator('.empty').nth(1), 'and the non-demo empty checks line').toHaveText(EMPTY_CHECKS);
  const off = await structure(page);

  const tab = await otherTab(page, (snapshot) => {
    emptied(snapshot);
    snapshot['demoMode'] = false;
  }, false);
  await expect(tab.getByRole('switch'), 'a server with demo mode off has no switch').toHaveCount(0);
  expect(off, 'the page with the switch off has the structure of the page of a server with demo mode off').toEqual(await structure(tab));

  await demoView(page).click();
  await expect(demoView(page)).toHaveAttribute('aria-checked', 'true');
  await expect(guideRegion(page), 'on again: the Demo guide').toHaveCount(1);
  await expect(devicesRegion(page), 'and the Simulated devices').toHaveCount(1);
  await expect(page.getByRole('link', { name: SKIP_DEVICES, exact: true }), 'and the skip link').toHaveCount(1);
  expect((await structure(page)).mainReachesRight, 'main gives the devices their width back').toBe(false);
});

test('V3: with the switch off a message is sent and its reply lands', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  test.setTimeout(150_000);
  await startOff(page);
  await signInReadmeLoaded(page);
  await expect(demoView(page)).toHaveAttribute('aria-checked', 'false');

  const replies = page.locator('app-chat-panel [data-part="reply"]');
  const before = await replies.count();
  const text = `zz demo view hello ${Date.now().toString(36)}`;
  await composerOf(page).fill(text);
  await composerOf(page).press('Enter');
  await expect(page.locator('app-chat-panel [data-part="user"]').filter({ hasText: text }), 'the turn shows').toHaveCount(1, { timeout: 15_000 });
  await expect(replies, 'with one more reply').toHaveCount(before + 1, { timeout: 90_000 });
  await expect(replies.last().locator('.text'), 'whose text has landed').toBeVisible({ timeout: 90_000 });
});

test('V4: the guide returns at the current step, selected, with its Hide guide choice as it was, and says nothing', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await recordAnnouncements(page);
  await changeSnapshot(page, (snapshot) => (snapshot['guide'] = guideOf(2)));
  await signInReadmeLoaded(page);

  const sw = demoView(page);
  const guide = guideRegion(page);
  await expect(stepOf(page, 3, 'current')).toHaveClass(/selected/);
  const requests: string[] = [];
  page.on('request', (request) => requests.push(`${request.method()} ${new URL(request.url()).pathname}`));
  await stepOf(page, 1, 'done').click();
  await expect(stepOf(page, 1, 'done'), 'the user selected step 1').toHaveClass(/selected/);
  await guide.getByRole('button', { name: 'Hide guide', exact: true }).click();
  await expect(guide).toContainText('step 3 of 5');

  await sw.click();
  await expect(guide, 'switch off: no guide').toHaveCount(0);
  await sw.click();
  await expect(guide, 'switch on: the collapsed bar shows the current step').toContainText('step 3 of 5');
  await guide.getByRole('button', { name: 'Show guide', exact: true }).click();
  await expect(stepOf(page, 3, 'current'), 'step 3 is current').toHaveAttribute('aria-current', 'step');
  await expect(stepOf(page, 3, 'current'), 'and selected').toHaveClass(/selected/);
  await expect(stepOf(page, 1, 'done'), 'not step 1 any more').not.toHaveClass(/selected/);

  await stepOf(page, 1, 'done').click();
  await expect(stepOf(page, 1, 'done')).toHaveClass(/selected/);
  await sw.click();
  await expect(guide).toHaveCount(0);
  await sw.click();
  await expect(guide.getByRole('button', { name: 'Hide guide', exact: true }), 'expanded, as it was').toBeVisible();
  await expect(stepOf(page, 3, 'current'), 'step 3 is selected').toHaveClass(/selected/);

  const heard = await announcedTexts(page);
  expect(heard.filter((text) => text.includes('Step 3 of 5')), 'no step announcement').toEqual([]);
  expect(requests.filter((request) => !/^GET \/ocutalon\/api\/v1\/events$/.test(request)), 'going off and back on, the guide sends and loads nothing but the poll').toEqual([]);
});

test('V5: the markers stay with the switch off, and the header fits from 320px up', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await startOff(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['onlineDemo'] = true;
    snapshot['nextReset'] = new Date(Date.now() + 2 * 3_600_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    snapshot['status'] = [...(snapshot['status'] as unknown[]), { condition: 'allowance', active: true, slots: { limit: 20, time: '2037-07-01T12:00:00Z' } }];
  });
  await page.setViewportSize({ width: 1280, height: 800 });
  await signInReadmeLoaded(page);

  await expect(demoView(page)).toHaveAttribute('aria-checked', 'false');
  await expect(page.locator('app-header .context-badge'), 'the Online demo pill stays').toHaveText('Online demo');
  await expect(page.locator('app-header .reset-countdown'), 'and the reset countdown').toHaveCount(1);
  await expect(page.locator('app-banner-stack [data-banner="allowance"]'), 'and the allowance banner').toHaveCount(1);
  await expect(guideRegion(page)).toHaveCount(0);

  const label = demoView(page).locator('.label');
  for (const [width, labelShows] of [[1440, true], [1280, true], [1024, false], [640, true], [320, true]] as const) {
    await page.setViewportSize({ width, height: 800 });
    await expect.poll(() => label.evaluate((el) => el.classList.contains('visually-hidden')), { message: `${width}px: the label ${labelShows ? 'shows' : 'is visually hidden'}` }).toBe(!labelShows);
    if (labelShows) expect((await label.boundingBox())?.width ?? 0, `${width}px: the label takes its width`).toBeGreaterThan(20);
    await expect(demoView(page).locator('.track'), `${width}px: the track shows`).toBeVisible();
    expect(await fits(page), `${width}px: nothing scrolls across`).toBe(true);
    expect(await rightGroupInside(page), `${width}px: the right group ends inside the header`).toBe(true);
  }
  await page.setViewportSize({ width: 1024, height: 800 });
  await expect(page.getByRole('button', { name: /^Status/ }), 'at 1024px the Status button is there with the pill and the switch').toBeVisible();
  await expect(demoView(page)).toHaveAccessibleName('Demo view');
  await demoView(page).hover();
  await expect(page.locator('app-tooltip'), 'and its pointer tooltip names the switch, as its label is hidden').toHaveText('Demo view');
});

test('V6: when sessionStorage throws, a press still toggles the view for the page', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await page.addInitScript(() => {
    Object.defineProperty(window, 'sessionStorage', {
      get() {
        throw new DOMException('blocked', 'SecurityError');
      },
    });
  });
  await signInReadmeLoaded(page);

  const sw = demoView(page);
  await expect(sw, 'on, as nothing could be read').toHaveAttribute('aria-checked', 'true');
  await expect(guideRegion(page)).toHaveCount(1);
  await sw.click();
  await expect(sw, 'a press turns it off for the page').toHaveAttribute('aria-checked', 'false');
  await expect(guideRegion(page), 'and the demo parts go').toHaveCount(0);
  await sw.click();
  await expect(sw, 'and on again').toHaveAttribute('aria-checked', 'true');
  await expect(guideRegion(page)).toHaveCount(1);
});

/** The Telegram card, as the rail shows it: the section headings, the card's text and its link's address and target. */
async function telegramReading(page: Page): Promise<{ headings: string[]; card: string; href: string | null; target: string | null }> {
  const link = railOf(page).locator('app-telegram-card a');
  return {
    headings: (await structure(page)).railHeadings,
    card: (await railOf(page).locator('app-telegram-card').count()) === 0 ? '(no card)' : ((await railOf(page).locator('app-telegram-card').textContent())?.replace(/\s+/g, ' ').trim() ?? ''),
    href: (await link.count()) > 0 ? await link.getAttribute('href') : null,
    target: (await link.count()) > 0 ? await link.getAttribute('target') : null,
  };
}

test('V7: the Telegram card is the same with the switch off as with it on, on a local and on the online demo', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await signInReadmeLoaded(page);
  const cases = [
    { state: 'off', online: false, card: /^Telegram not set up\s*How to set it up/ },
    { state: 'rejected', online: false, card: /^Telegram not set up\s*How to set it up/ },
    { state: 'on', online: false, card: /^$/ },
    { state: 'off', online: true, card: /^Telegram not set up\s*How to set it up/ },
  ] as const;
  for (const one of cases) {
    const tab = await otherTab(page, (snapshot) => {
      snapshot['telegram'] = { ...(snapshot['telegram'] as object), included: true, state: one.state };
      if (one.online) {
        snapshot['onlineDemo'] = true;
        snapshot['nextReset'] = new Date(Date.now() + 2 * 3_600_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
      }
    }, false);
    const label = `${one.state}${one.online ? ', online demo' : ''}`;
    const on = await telegramReading(tab);
    expect(on.headings[0], `${label}: with the switch on the first rail section is Telegram`).toBe('Telegram');
    expect(on.card, `${label}: and the card says what its state says`).toMatch(one.card);

    await demoView(tab).click();
    await expect(demoView(tab)).toHaveAttribute('aria-checked', 'false');
    await expect(guideRegion(tab), `${label}: the demo parts are gone`).toHaveCount(0);
    expect(await telegramReading(tab), `${label}: the Telegram section, card and link are as they were`).toEqual(on);

    await demoView(tab).click();
    await expect(guideRegion(tab)).toHaveCount(1);
    expect(await telegramReading(tab), `${label}: and again with the switch back on`).toEqual(on);
    await tab.close();
  }
});

test('V8: with no snapshot (the answer failed) there is no switch, whatever this tab stored', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await startOff(page);
  await page.route(`**${STATE}`, (route) => route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } }));
  await signInReadme(page);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'failed');
  await expect(page.getByRole('button', { name: 'Account', exact: true }), 'the header is there').toBeVisible();
  await expect(page.getByRole('switch'), 'no Demo view switch without a snapshot that says demo mode').toHaveCount(0);
  await expect(guideRegion(page)).toHaveCount(0);
  await expect(devicesRegion(page)).toHaveCount(0);
});

test('V9: only a stored 1 turns the switch off; a missing, empty or other value reads on', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await signInReadmeLoaded(page);
  for (const [stored, checked] of [['1', 'false'], ['0', 'true'], ['', 'true'], ['true', 'true'], ['off', 'true']] as const) {
    const tab = await page.context().newPage();
    await tab.addInitScript(([key, value]) => sessionStorage.setItem(key, value), [KEY, stored]);
    await tab.goto('/ocutalon/');
    await expect(mainOf(tab)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(demoView(tab), `a stored ${JSON.stringify(stored)} reads ${checked === 'true' ? 'on' : 'off'}`).toHaveAttribute('aria-checked', checked);
    await expect(guideRegion(tab), 'and the Demo guide follows it').toHaveCount(checked === 'true' ? 1 : 0);
    if (checked === 'true') {
      await demoView(tab).click();
      expect(await tab.evaluate((key) => sessionStorage.getItem(key), KEY), 'a press writes 1 for off').toBe('1');
      await demoView(tab).click();
      expect(await tab.evaluate((key) => sessionStorage.getItem(key), KEY), 'and 0 for on').toBe('0');
    }
    await tab.close();
  }
});

test('V5: on a local demo the Demo mode pill stays with the switch off', async ({ page }) => {
  test.skip(stackMode() !== '1', 'mode 1 only');
  await startOff(page);
  await signInReadmeLoaded(page);
  await expect(demoView(page)).toHaveAttribute('aria-checked', 'false');
  await expect(page.locator('app-header .context-badge')).toHaveText('Demo mode');
});
