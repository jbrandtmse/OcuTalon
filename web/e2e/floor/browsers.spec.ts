import { expect, test } from '../support/fixtures';

import { MESSAGES } from '../support/api';
import {
  MOST_STOPS,
  SKIP_STATUS,
  composerOf,
  expectStopRing,
  openFloor,
  readFocus,
  seedScrollingPage,
  settled,
  skipLink,
  stepKeys,
  unique,
} from '../support/floor';
import { cleanFixtureRows, fixtureUser } from '../support/iris';

/**
 * Story 2.16, what differs between the engines (E1 to E4), in a real browser against a real stack, in Chromium, Firefox and WebKit. It
 * pins the Visual Trace button, which closes its own menu even when the engine takes focus away from a pressed button, and a press inside
 * that menu, which reaches its control in the same case (DW-145, E1); the
 * chat list and the rail, which are tab stops named by their headings, draw their ring inside their edge and scroll by key (DW-89,
 * E2); the composer, which sends nothing for the Enter that ends an IME composition in Safari's event order (E3); and the History page's pager, whose Previous page and
 * Next page hand keyboard focus to the page's main region when they leave while the next page loads (Story 25.2, E4; the answers are stubbed in the browser, so E4
 * seeds nothing and reads no row). It needs the stack that
 * docker/tests/test-floor.sh starts: every case signs in as the floor user (OCUTALON_FLOOR_USER, the user role) over real HTTP, in a
 * fresh browser context. E2 removes the rows it seeds with cleanFixtureRows in finally, and E3 routes every chat post to an abort in the
 * browser, so none reaches the server. All four run in every engine (tag @browsers).
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'FLOOR';

/**
 * E1: a press on the Visual Trace button closes its open menu, with and without the no-focus press of Safari and Firefox on macOS, and a
 * no-focus press inside the open menu reaches its link before the menu closes.
 */
test('E1: pressing the Visual Trace button closes its menu and leaves focus on it, with a press that takes no focus too', { tag: '@browsers' }, async ({ page }) => {
  await openFloor(page);
  const trigger = page.getByRole('button', { name: 'Visual Trace', exact: true });
  const popover = page.locator('.app-popover');
  const list = page.locator('app-chat-panel .list');

  const centerOf = async (target: typeof trigger): Promise<{ x: number; y: number }> => {
    const box = (await target.boundingBox())!;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  };
  /** Presses the button the way a person does: down, 150 ms, up, and the release over `where`. */
  const press = async (where: { x: number; y: number }): Promise<void> => {
    const at = await centerOf(trigger);
    await page.mouse.move(at.x, at.y);
    await page.mouse.down();
    await page.waitForTimeout(150);
    await page.mouse.move(where.x, where.y);
    await page.mouse.up();
  };
  /** Makes the next press on the button what Safari and Firefox on macOS make it: the default is prevented and the focus is blurred. */
  const takeNoFocus = (): Promise<void> =>
    trigger.evaluate((el) =>
      el.addEventListener(
        'mousedown',
        (event) => {
          event.preventDefault();
          (document.activeElement as HTMLElement | null)?.blur();
        },
        { capture: true, once: true },
      ),
    );
  const expectClosed = async (what: string): Promise<void> => {
    await expect(popover, `${what}: the menu closes`).toHaveCount(0);
    await expect(trigger, `${what}: focus is on the button`).toBeFocused();
    await expect(trigger, `${what}: aria-expanded is false`).toHaveAttribute('aria-expanded', 'false');
  };

  for (const safari of [false, true]) {
    const what = safari ? 'a press that takes no focus' : 'a plain press';
    await trigger.click();
    await expect(popover, `${what}: the menu opens`).toHaveCount(1);
    await expect(trigger).toHaveAttribute('aria-expanded', 'true');
    if (safari) await takeNoFocus();
    await press(await centerOf(trigger));
    await expectClosed(what);
    await settled(page);
    await expectClosed(`${what}, after the page has settled`);

    if (safari) await takeNoFocus();
    await press(await centerOf(trigger));
    await expect(popover, `${what}: the next press opens it`).toHaveCount(1);
    await expect(trigger).toHaveAttribute('aria-expanded', 'true');
    await page.keyboard.press('Escape');
    await expect(popover).toHaveCount(0);
  }

  // A press inside the open menu reaches its control, even when the press takes focus away from the menu (the link holds it on open): the
  // focus that the press took closes the menu only once the press has ended. The click's default is prevented, so no tab opens.
  await trigger.click();
  await expect(popover).toHaveCount(1);
  const link = popover.getByRole('link');
  await link.evaluate((el) => {
    const counted = window as unknown as { panePresses: number };
    counted.panePresses = 0;
    el.addEventListener('click', (event) => {
      event.preventDefault();
      counted.panePresses += 1;
    }, { capture: true });
    el.addEventListener('mousedown', (event) => {
      event.preventDefault();
      (document.activeElement as HTMLElement | null)?.blur();
    }, { capture: true, once: true });
  });
  await expect(link, 'the menu has put focus on its link').toBeFocused();
  // hover() waits until the placed menu holds still under the pointer, so the press lands on the link.
  await link.hover();
  await page.mouse.down();
  await page.waitForTimeout(150);
  await page.mouse.up();
  await expect.poll(() => page.evaluate(() => (window as unknown as { panePresses: number }).panePresses), { message: 'a press inside the menu reaches its link' }).toBe(1);
  await expect(popover, 'then the menu closes, since focus has left it').toHaveCount(0);

  // A press that starts on the button and ends over the chat list is no click on the button: the menu still closes, and no pane stays open.
  // The engine's click on the two targets' common ancestor would close it as a press outside, so the case withholds that click from the
  // page: a press that ends elsewhere then closes the menu only through the popover's own end-of-press check.
  await trigger.click();
  await expect(popover).toHaveCount(1);
  await takeNoFocus();
  await page.evaluate(() => window.addEventListener('click', (event) => event.stopImmediatePropagation(), { capture: true, once: true }));
  await press(await centerOf(list));
  await expect(popover, 'released over the chat list: the menu closes').toHaveCount(0);
  await expect(page.locator('.cdk-overlay-pane'), 'and no pane is left open').toHaveCount(0);
  await expect(trigger, 'aria-expanded is false').toHaveAttribute('aria-expanded', 'false');
});

/** E2: the chat list and the rail are tab stops named "Chat" and "Status", with their ring inside, and End and PageDown scroll them. */
test('E2: the chat list and the rail are tab stops with their ring inside, and the keyboard scrolls them', { tag: '@browsers' }, async ({ page }) => {
  test.setTimeout(150_000);
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await page.setViewportSize({ width: 1280, height: 720 });
    await seedScrollingPage(user, refs, unique('E2'));
    await openFloor(page);
    const keys = await stepKeys(page);
    const regions = [
      { name: 'Status', what: 'section#status-region', locator: page.getByRole('region', { name: 'Status', exact: true }) },
      { name: 'Chat', what: 'div', locator: page.getByRole('region', { name: 'Chat', exact: true }) },
    ];
    await expect(regions[0]!.locator, 'region Status').toHaveCount(1);
    await expect(regions[1]!.locator, 'region Chat').toHaveCount(1);
    // Firefox makes a scroller a tab stop of its own; WebKit and Chromium do so only with tabindex, which both regions carry.
    await expect(regions[0]!.locator, 'the rail is a tab stop').toHaveAttribute('tabindex', '0');
    await expect(regions[1]!.locator, 'and so is the chat list').toHaveAttribute('tabindex', '0');
    const seen = new Set<string>();

    for (let i = 0; i < MOST_STOPS && seen.size < regions.length; i += 1) {
      await page.keyboard.press(keys.next);
      const reading = (await readFocus(page))!;
      expect(reading, `${keys.next} ${i + 1} lands on an element`).not.toBeNull();
      const region = regions.find((one) => reading.what.startsWith(one.what) && reading.inside);
      if (region === undefined) continue;
      await expect(region.locator, `the stop is region ${region.name}`).toBeFocused();
      await expectStopRing(page, reading);
      seen.add(region.name);

      const scrollTop = (): Promise<number> => region.locator.evaluate((el) => el.scrollTop);
      await region.locator.evaluate((el) => {
        el.scrollTop = 0;
      });
      await page.keyboard.press('PageDown');
      await expect.poll(scrollTop, { message: `PageDown scrolls region ${region.name}` }).toBeGreaterThan(0);
      const afterPage = await scrollTop();
      await page.keyboard.press('End');
      await expect.poll(scrollTop, { message: `End scrolls region ${region.name} on` }).toBeGreaterThan(afterPage);
      await expect(region.locator, `focus stays on region ${region.name}`).toBeFocused();
    }
    expect([...seen].sort(), 'the walk stopped at region Chat and region Status').toEqual(['Chat', 'Status']);

    // Below 1024px the rail does not scroll on its own: it is no tab stop, and Skip to status still focuses it.
    await page.setViewportSize({ width: 1000, height: 800 });
    const rail = page.locator('section.rail');
    await expect(rail, 'stacked, the rail is not a tab stop').toHaveAttribute('tabindex', '-1');
    await skipLink(page, SKIP_STATUS).focus();
    await page.keyboard.press('Enter');
    await expect(rail, 'Skip to status still focuses it').toBeFocused();
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** E3: Enter that ends an IME composition in Safari's order (composition events first, keyCode 229 and no isComposing) sends nothing. */
test('E3: an Enter that ends an IME composition sends nothing, in Safari\'s event order', { tag: '@browsers' }, async ({ page }) => {
  let posts = 0;
  await page.route(`**${MESSAGES}`, async (route) => {
    posts += 1;
    await route.abort();
  });
  await openFloor(page);
  const field = composerOf(page);
  await field.fill('composing');

  await field.evaluate((el) => {
    el.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true, data: '' }));
    el.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: 'composing' }));
    // Safari ends the composition before the Enter's keydown, which carries keyCode 229 and an isComposing that is already false. Whether
    // KeyboardEventInit takes keyCode differs between engines, so the event gets it as an own property.
    const committing = new KeyboardEvent('keydown', { key: 'Enter', isComposing: false, bubbles: true, cancelable: true });
    Object.defineProperty(committing, 'keyCode', { value: 229 });
    el.dispatchEvent(committing);
  });
  await settled(page);
  expect(posts, 'the committing Enter sends nothing').toBe(0);
  await expect(field, 'and the text stays').toHaveValue('composing');

  await field.evaluate((el) => {
    el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true, cancelable: true }));
  });
  await settled(page);
  expect(posts, 'an Enter inside an open composition sends nothing').toBe(0);
  await expect(field, 'and the text stays').toHaveValue('composing');
});

/**
 * E4 (Story 25.2): Next page and Previous page on the History page. The pager leaves while the next page loads, so a focused pager button would drop focus to the
 * body: the page hands focus to its main region first. The history answers are stubbed in the browser (25 decisions on page 1 of 2, one on page 2, the answer to a
 * page held for 400 ms so that the pager is gone while the page loads), so the case seeds nothing and needs no clean-up. The press is the keyboard's Enter on the
 * focused button, which every engine delivers as a click, and the case first shows that focus is not already on the main region.
 */
test('E4: Next page and Previous page on the History page leave keyboard focus on the page\'s main region', { tag: '@browsers' }, async ({ page }) => {
  const decisionsOf = (from: number, count: number): Array<Record<string, unknown>> =>
    Array.from({ length: count }, (_one, index) => ({
      ref: `ZzE4Ref${String(from + index).padStart(4, '0')}`,
      outcome: 'act',
      reasons: 'Stubbed.',
      fallback: false,
      fallbackReason: '',
      itemSummary: `E4 row ${from + index}`,
      recordedAt: '2030-01-01T09:00:00Z',
      channel: 'web',
    }));
  await page.route('**/ocutalon/api/v1/history/decisions*', async (route) => {
    const second = new URL(route.request().url()).searchParams.get('page') === '2';
    await new Promise((done) => setTimeout(done, 400));
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ page: second ? 2 : 1, pages: 2, decisions: second ? decisionsOf(26, 1) : decisionsOf(1, 25) }),
    });
  });
  await openFloor(page);
  await page.evaluate(() => {
    window.location.hash = '#/history';
  });
  const rows = page.locator('[data-part="history-decisions"] > li');
  const main = page.locator('main.history');
  const next = page.getByRole('button', { name: 'Next page', exact: true });
  const previous = page.getByRole('button', { name: 'Previous page', exact: true });
  await expect(rows, 'page 1 holds 25 rows').toHaveCount(25);
  await expect(page.getByText('Page 1 of 2', { exact: true })).toBeVisible();

  await next.focus();
  await expect(next, 'the pager button holds focus').toBeFocused();
  await expect(main, 'and the main region does not yet').not.toBeFocused();
  await page.keyboard.press('Enter');
  await expect(rows, 'page 2 holds its one row').toHaveCount(1);
  await expect(page.getByText('Page 2 of 2', { exact: true })).toBeVisible();
  await expect(main, 'Next page: focus is on the main region, not the body').toBeFocused();

  await previous.focus();
  await expect(previous, 'Previous page holds focus').toBeFocused();
  await page.keyboard.press('Enter');
  await expect(rows, 'page 1 is back with its 25 rows').toHaveCount(25);
  await expect(page.getByText('Page 1 of 2', { exact: true })).toBeVisible();
  await expect(main, 'Previous page: focus is on the main region, not the body').toBeFocused();
});
