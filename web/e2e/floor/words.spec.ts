import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { MESSAGES, STATE, holdState } from '../support/api';
import { signIn } from '../sign-in/helpers';
import {
  CARD_MS,
  addReminder,
  addResetSoon,
  clearFullPage,
  composerOf,
  mainOf,
  openFloor,
  railOf,
  replyOf,
  seedFullPage,
  unique,
} from '../support/floor';
import { finishTurn, fixtureUser, seedTurns } from '../support/iris';

/**
 * Story 2.14, the words (W1 to W4), in a real browser against a real stack. It pins that nothing relies on colour or motion alone and
 * that text can grow: every link is underlined at rest (W1); at twice the text size no box is shorter than its text, the composer
 * still fits its lines and About scrolls (W2); under prefers-reduced-motion nothing animates or scrolls smoothly (W3); and the load
 * error, the busy notice and "Not sent" are linked to their buttons (W4). It needs the stack that docker/tests/test-floor.sh starts:
 * every case signs in as the floor user (OCUTALON_FLOOR_USER, the user role) over real HTTP, in a fresh browser context, so the Trace
 * help of a rail row is unseen in it. A case removes its rows with cleanFixtureRows, turns the conditions it publishes off and finishes
 * the turn it runs in finally. W4 answers its chat post in the browser, so no post reaches the server and no turn replies inside
 * another case's window.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll, a snapshot or a post that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';

/** The words of the load error and of the busy notice, written out here as the independent oracle of the page's own. */
const LOAD_FAILED = "Couldn't load your session.";
const BUSY_NOTICE = "Couldn't reach OcuTalon. Try again. Nothing was changed.";

/** The answer of a server that failed. */
const SERVER_ERROR = '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}';

/** The links of the page that are not underlined at rest, described. The home link is read at its wordmark, which is its text. */
function notUnderlined(page: Page): Promise<string[]> {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('a, [role=link]'))
      .filter((link) => link.getClientRects().length > 0 || link.classList.contains('skip-link'))
      .filter((link) => {
        const text = link.classList.contains('home') ? (link.querySelector('.wordmark') ?? link) : link;
        return !getComputedStyle(text).textDecorationLine.split(' ').includes('underline');
      })
      .map((link) => `${link.tagName.toLowerCase()}.${String(link.className)} "${(link.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 40)}"`),
  );
}

/** The texts of the elements that a button is described by (aria-describedby), in order. */
function describers(button: Locator): Promise<string[]> {
  return button.evaluate((el) =>
    (el.getAttribute('aria-describedby') ?? '')
      .split(/\s+/)
      .filter((id) => id !== '')
      .map((id) => (document.getElementById(id)?.textContent ?? '').replace(/\s+/g, ' ').trim()),
  );
}

/** W1: every link is underlined at rest, wherever it shows: the page, the Trace help, the Visual Trace popover and About. */
test('W1: every link is underlined at rest', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const full = await seedFullPage(user, refs);
    await openFloor(page);
    await addReminder(page, user, full.stamp);
    await addResetSoon(page, user);
    await expect(page.locator('app-banner-stack a'), 'the no-key banner has its action').not.toHaveCount(0);
    await expect(replyOf(page, full.turn).getByRole('link', { name: /the guide/ }), 'a reply holds a markdown link').toHaveCount(1);

    await page.keyboard.press('Tab');
    await expect(page.getByRole('link', { name: 'Skip to chat', exact: true }), 'the skip link has focus').toBeFocused();
    expect(await notUnderlined(page), 'on the page: the skip links, the wordmark, the banners, the rows, the strip and the reply').toEqual([]);
    expect(await page.locator('app-header a.home .wordmark').evaluate((el) => getComputedStyle(el).textDecorationLine), "the home link's wordmark").toContain('underline');

    await railOf(page).locator('app-trace-link a').first().click();
    const help = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
    await expect(help, "a row's Trace link opens the help in a fresh context").toBeVisible();
    await expect(help.getByRole('link', { name: /^Open Visual Trace/ }), 'with its link styled as a button').toHaveCount(1);
    expect(await notUnderlined(page), 'with the Trace help open').toEqual([]);
    await page.keyboard.press('Escape');
    await expect(help).toHaveCount(0);

    await page.getByRole('button', { name: 'Visual Trace', exact: true }).click();
    const inactive = page.locator('.app-popover').getByRole('link', { name: /^Open my conversation in Visual Trace/ });
    await expect(inactive, 'the Visual Trace popover has the conversation link').toHaveCount(1);
    await expect(inactive, 'which cannot act yet').toHaveAttribute('aria-disabled', 'true');
    expect(await notUnderlined(page), 'with the Visual Trace popover open, the inactive link too').toEqual([]);
    await page.keyboard.press('Escape');
    await expect(page.locator('.app-popover')).toHaveCount(0);

    await page.locator('app-header button.header-button').last().click();
    await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
    await expect(page.locator('app-about-dialog').getByRole('link', { name: /^README/ }), 'About has its README link').toHaveCount(1);
    expect(await notUnderlined(page), 'with About open').toEqual([]);
  } finally {
    await clearFullPage(user, refs);
  }
});

/** W2: at twice the text size no box is shorter than its text, the composer fits its lines, and About scrolls. */
test('W2: at 200% text the boxes hold their text, the composer fits its lines and About scrolls', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 600 });
    const full = await seedFullPage(user, refs);
    await openFloor(page);
    await addResetSoon(page, user);
    await expect(replyOf(page, full.turn).locator('app-outcome-chip .chip'), "the strip shows a chip").toHaveCount(1);
    await expect(replyOf(page, full.turn).locator('app-fallback-flag .flag'), 'and the Fallback flag').toHaveCount(1);
    await expect(page.locator('app-banner-stack [data-banner]'), 'and banners').not.toHaveCount(0);

    const field = composerOf(page);
    await field.click();
    await field.pressSequentially('zz one');
    await field.press('Shift+Enter');
    await field.pressSequentially('zz two');
    await expect(field).toHaveValue('zz one\nzz two');

    const doubled = await page.evaluate(() => {
      const root = document.documentElement;
      const names = new Set<string>();
      for (const sheet of Array.from(document.styleSheets)) {
        for (const rule of Array.from(sheet.cssRules)) {
          if (rule instanceof CSSStyleRule && rule.selectorText === ':root') {
            for (const name of Array.from(rule.style)) if (name.startsWith('--') && name.endsWith('font-size')) names.add(name);
          }
        }
      }
      for (const name of names) {
        root.style.setProperty(name, `calc(2 * ${getComputedStyle(root).getPropertyValue(name).trim()})`);
      }
      return names.size;
    });
    expect(doubled, 'the font-size tokens of :root').toBeGreaterThan(10);

    // A box is shorter than its text when its content reaches past it. The chip and the flag set their text at line-height 1, so the
    // font's own content area is taller than the line and counts as overflow though nothing is cut: they are held to their line.
    const short = (selector: string, byLine: boolean): Promise<string[]> =>
      page.evaluate(
        ([css, line]) =>
          Array.from(document.querySelectorAll<HTMLElement>(css as string))
            .filter((el) => (line ? el.clientHeight + 0.5 < parseFloat(getComputedStyle(el).lineHeight) : el.scrollHeight - el.clientHeight > 1))
            .map((el) => `${css} "${(el.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 30)}" ${el.scrollHeight} > ${el.clientHeight}`),
        [selector, byLine] as const,
      );
    for (const [selector, byLine] of [['.chip', true], ['.flag', true], ['.button', false], ['[data-banner]', false], ['.header', false]] as const) {
      expect(await page.locator(selector).count(), `${selector} is on the page`).toBeGreaterThan(0);
      expect(await short(selector, byLine), `no ${selector} is shorter than its text`).toEqual([]);
    }
    const box = await field.evaluate((el) => ({ scroll: el.scrollHeight, client: el.clientHeight, line: parseFloat(getComputedStyle(el).lineHeight) }));
    expect(box.scroll - box.client, 'the composer shows both lines, with no keystroke').toBeLessThanOrEqual(1);
    expect(box.client, 'at least two doubled lines tall').toBeGreaterThanOrEqual(2 * box.line);
    expect(box.line, 'and the line is the doubled one').toBeGreaterThan(25);

    await page.locator('app-header button.header-button').last().click();
    await page.getByRole('menuitem', { name: 'About OcuTalon' }).click();
    const about = page.locator('app-about-dialog');
    await expect(about).toBeVisible();
    const scroll = await about.evaluate((el) => ({ scroll: el.scrollHeight, client: el.clientHeight, overflow: getComputedStyle(el).overflowY }));
    expect(scroll.scroll, 'About is taller than the window allows').toBeGreaterThan(scroll.client);
    expect(scroll.overflow, 'so it scrolls').toBe('auto');
    const last = about.locator('p').last();
    await last.scrollIntoViewIfNeeded();
    const seen = await about.evaluate((el) => {
      const text = el.querySelectorAll('p');
      const rect = text[text.length - 1]!.getBoundingClientRect();
      const host = el.getBoundingClientRect();
      return { top: rect.top, bottom: rect.bottom, hostTop: host.top, hostBottom: host.bottom, viewport: window.innerHeight };
    });
    expect(seen.bottom, 'its last paragraph can be scrolled into view, inside the dialog').toBeLessThanOrEqual(seen.hostBottom + 0.5);
    expect(seen.bottom, 'and inside the window').toBeLessThanOrEqual(seen.viewport + 0.5);
    expect(seen.top, 'with its top in the window').toBeGreaterThanOrEqual(-0.5);
  } finally {
    await clearFullPage(user, refs);
  }
});

/** W3: under reduced motion the spinner and the dots stand still and nothing scrolls smoothly; without it the dots animate. */
test('W3: under prefers-reduced-motion nothing animates or scrolls smoothly', async ({ page }) => {
  const { user, password } = fixtureUser(KIND);
  let held: Route | undefined;
  let running: string | undefined;
  try {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    let answers = 0;
    await page.route(`**${STATE}`, async (route) => {
      answers += 1;
      if (answers === 1) {
        await route.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
        return;
      }
      held = route;
    });
    await signIn(page, user, password);
    const main = mainOf(page);
    await expect(main).toHaveAttribute('data-snapshot', 'failed', { timeout: CARD_MS });
    const retry = main.getByRole('button', { name: 'Retry', exact: true });
    expect(await describers(retry), 'on an error answer, Retry is described by the load error').toEqual([LOAD_FAILED]);
    await retry.click();
    await expect.poll(() => held !== undefined, { message: "Retry's request is out and held" }).toBe(true);
    await expect(retry, 'Retry is busy').toHaveAttribute('aria-busy', 'true');
    const spinner = retry.locator('.spinner');
    await expect(spinner, 'with a spinner').toHaveCount(1);
    await expect(spinner, 'which has no animation').toHaveCSS('animation-name', 'none');
    expect(await page.evaluate(() => document.getAnimations().filter((one) => one.playState === 'running').length), 'and nothing runs').toBe(0);

    await held!.continue();
    held = undefined;
    await page.unroute(`**${STATE}`);
    await expect(main).toHaveAttribute('data-snapshot', 'loaded', { timeout: CARD_MS });

    const seeded = await seedTurns(user, [{ createdAt: '2019-05-01T10:00:00Z', text: unique('W3 question'), replyText: '', state: 'running' }], true);
    running = seeded.refs[0]!;
    const dots = replyOf(page, running).locator('.indicator .dots');
    await expect(dots, 'a running turn shows its dots').toHaveCount(1, { timeout: CARD_MS });
    await expect(dots, 'which have no animation').toHaveCSS('animation-name', 'none');
    expect(await page.evaluate(() => document.getAnimations().filter((one) => one.playState === 'running').length), 'and nothing runs').toBe(0);

    const smooth = await page.evaluate(() => {
      const scrollers = Array.from(document.querySelectorAll('*')).filter((el) => {
        const style = getComputedStyle(el);
        return ['auto', 'scroll'].includes(style.overflowY) || ['auto', 'scroll'].includes(style.overflowX);
      });
      return [document.documentElement, ...scrollers].filter((el) => getComputedStyle(el).scrollBehavior !== 'auto').map((el) => el.tagName.toLowerCase());
    });
    expect(smooth, 'every scroller and the page scroll at once').toEqual([]);
    expect(await page.evaluate(() => Array.from(document.querySelectorAll('*')).filter((el) => ['auto', 'scroll'].includes(getComputedStyle(el).overflowY)).length), 'and there are scrollers to read').toBeGreaterThan(1);

    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await expect(dots, 'without reduced motion the dots animate').not.toHaveCSS('animation-name', 'none');
    expect(await page.evaluate(() => document.getAnimations().filter((one) => one.playState === 'running').length), 'and an animation runs').toBeGreaterThan(0);
  } finally {
    if (held !== undefined) await held.continue().catch(() => undefined);
    if (running !== undefined) await finishTurn(user, running, 'zz W3 finished');
  }
});

/** W4: the load error, the busy notice and "Not sent" are linked to their buttons. */
test('W4: Retry is described by the load error and its busy notice, and Retry sending by its Not sent', async ({ page }) => {
  const { user, password } = fixtureUser(KIND);
  await page.clock.install();
  const hold = await holdState(page);
  try {
    await signIn(page, user, password);
    await expect.poll(() => hold.held()).toBe(1);
    const main = mainOf(page);
    await expect(main).toHaveAttribute('data-snapshot', 'loading');
    await page.clock.runFor(10_000);
    await expect(main).toHaveAttribute('data-snapshot', 'failed');
    const retry = main.getByRole('button', { name: 'Retry', exact: true });
    await expect(retry).toBeVisible();
    expect(await describers(retry), 'after 10 s Retry is described by the load error').toEqual([LOAD_FAILED]);
    await expect(retry).toHaveAccessibleDescription(LOAD_FAILED);

    await retry.click();
    await expect.poll(() => hold.held(), { message: 'Retry asks for the snapshot again' }).toBe(2);
    await expect(retry, 'busy').toHaveAttribute('aria-busy', 'true');
    expect(await describers(retry), 'while busy it has no notice yet').toEqual([LOAD_FAILED]);
    await page.clock.runFor(10_000);
    await expect(retry, 'restored').not.toHaveAttribute('aria-busy', 'true');
    await expect(main.locator('app-inline-notice')).toHaveText(BUSY_NOTICE);
    expect(await describers(retry), 'after 10 s more it is described by the load error and the busy notice').toEqual([LOAD_FAILED, BUSY_NOTICE]);
    await expect(retry).toHaveAccessibleDescription(`${LOAD_FAILED} ${BUSY_NOTICE}`);
  } finally {
    hold.release();
  }
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('app-inline-notice'), 'an answer clears the notice').toHaveCount(0);

  let posts = 0;
  await page.route(`**${MESSAGES}`, async (route) => {
    posts += 1;
    await route.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
  });
  const typed = unique('W4');
  const field = composerOf(page);
  await field.fill(typed);
  await field.press('Enter');
  const message = page.locator('app-chat-panel [data-part="user"]').filter({ hasText: typed });
  const retrySending = message.getByRole('button', { name: 'Retry sending', exact: true });
  await expect(retrySending, 'the failed message offers Retry sending').toBeVisible({ timeout: CARD_MS });
  expect(await describers(retrySending), 'Retry sending is described by its own Not sent').toEqual(['Not sent']);
  await expect(retrySending).toHaveAccessibleDescription('Not sent');
  expect(await message.locator('.failed').getAttribute('id'), 'which is the message\'s own').toBe(await retrySending.getAttribute('aria-describedby'));

  const typedAgain = unique('W4 again');
  await field.fill(typedAgain);
  await field.press('Enter');
  const again = page.locator('app-chat-panel [data-part="user"]').filter({ hasText: typedAgain });
  const retryAgain = again.getByRole('button', { name: 'Retry sending', exact: true });
  await expect(retryAgain, 'a second failed message offers its own Retry sending').toBeVisible({ timeout: CARD_MS });
  expect(await describers(retryAgain), 'described by its own Not sent').toEqual(['Not sent']);
  const againId = await retryAgain.getAttribute('aria-describedby');
  expect(againId, 'which has an id of its own').not.toBe(await retrySending.getAttribute('aria-describedby'));
  expect(await again.locator('.failed').getAttribute('id'), 'the second message\'s').toBe(againId);
  expect(posts, 'both posts were answered in the browser').toBe(2);
});
