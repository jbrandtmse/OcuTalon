import { expect, test, type Locator, type Page, type Route } from '../support/fixtures';

import { itemsFor } from '../../src/app/guide/more-to-try-view.ts';
import { changeSnapshot, MESSAGES, STATE } from '../support/api';
import { sampleChipOf } from '../support/devices';
import { loadedAfter, signInReadmeLoaded } from '../support/floor';
import { blockLiveSocket } from '../support/socket';

/**
 * Story 4.11, the demo guide's "Other things to try" panel and its "More to try" link, on the sign-in stack with the README account.
 * K1 reads the real stack: /v1/state's guide.features is Demo.Features.Present()'s list, and the panel shows exactly the items for it
 * (it records the list, which is Task 0 (a)). Every other case answers /state with a guide that it names (a finish or step 1, with the
 * features it names) and keeps it by dropping guide.state from the page's polls; the POSTs of items 2, 3 and 5 are routed and counted,
 * because their downstream flows are pinned by the demo-path specs. K5 uses the real Persona card, and collapses it again.
 *   - K2 (matrix 1): the routed finish: the panel is open after the links and before Try it yourself, items 1 to 4 in order;
 *   - K3 (matrix 3, 10): seven ids: seven items in order, a link to the Documents page, and the rail focused by item 7;
 *   - K4 (matrix 2): step 1: no panel, the link in the Tab order, Enter opens and Space closes it, focus stays on the link;
 *   - K5 (matrix 5): item 1 opens the Persona card's Change and focuses it, also in the drawer band, where the drawer opens first;
 *   - K6 (matrix 6): item 2 selects the Simulated mailbox tab, sends the chip's own POST once and focuses the chip;
 *   - K7 (matrix 7): item 3 presses the box's Break the feed once; an inactive box does nothing and keeps the focus;
 *   - K8 (matrix 8): item 4 turns the Demo view switch off, with focus on it and nothing sent;
 *   - K9 (matrix 9): item 5 sends its prompt once; it sends nothing while its turn is in flight or the allowance is used up;
 *   - K10 (matrix 11): neither the link nor the panel shows with the switch off or without demo mode;
 *   - K11: leaving the finish: a panel control that holds focus hands it to the box, the panel is closed outside the finish until the
 *     link opens it, a new finish opens it again, and a press in the finish keeps it open when the finish leaves;
 *   - K12, K13: items 2 and 3 reach the chip and the box in the drawer band (1100x720) and the stacked band (800x720);
 *   - K14 (matrix 5, error): item 1 focuses the Persona heading when the card has not loaded;
 *   - K15 (matrix 6, error): item 2 sends nothing while the email limit holds, and focuses the inactive chip.
 */
const BREAK_FEED = '**/ocutalon/api/v1/demo/break-feed';
const SAMPLE = '**/ocutalon/api/v1/mailbox/samples/suspicious-request';
const DEMO_VIEW_KEY = 'ocutalon.demoView.off';

const FOUR = ['persona', 'suspiciousEmail', 'rejectFix', 'demoView'];
const SEVEN = [...FOUR, 'memory', 'documents', 'heartbeat'];

/** The ruled texts of the seven items, written out here as the independent oracle of the page's own. */
const ITEMS: Record<string, { label: string; lookFor: string; button: string }> = {
  persona: {
    label: 'Change how OcuTalon talks',
    lookFor:
      'In the Persona card, choose Pirate, or Another language and then Spanish, and press Save. Then ask "Is anything wrong right now?" and look for the new style in the replies. The check results under them are written by OcuTalon\'s code, so they stay the same in any style.',
    button: 'Go to the Persona card',
  },
  suspiciousEmail: {
    label: 'Send a suspicious email',
    lookFor:
      'This sends "Sample: suspicious request" to the Simulated mailbox. The email asks OcuTalon to resend every failed order and approve pending requests. Look for its decision and the reasons under it: nothing is resent or approved.',
    button: 'Send the suspicious email',
  },
  rejectFix: {
    label: 'Reject a fix',
    lookFor:
      'This presses Break the feed again. OcuTalon usually notices within a minute. When the fix waits for your approval, press Reject in the chat or on the Simulated phone, and look for "Nothing was changed."',
    button: 'Break it again',
  },
  demoView: {
    label: 'See the page as on your own install',
    lookFor: 'The demo guide, Break the feed and the Simulated devices are hidden, as on your own install. Turn Demo view back on in the top bar to return.',
    button: 'Show the page without the demo',
  },
  memory: {
    label: 'Ask it to remember something',
    lookFor: 'This sends "Remember that the Results partner\'s contact is Lee." Later, ask "Who do I call about Results?" and look for the answer it remembered.',
    button: 'Ask it to remember',
  },
  documents: {
    label: 'Ask about a document',
    lookFor:
      'On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat and look for the citation under the answer.',
    button: 'Open the Documents page',
  },
  heartbeat: {
    label: 'Run a heartbeat check-in',
    lookFor: 'In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in\'s outcome and its cost in the card.',
    button: 'Go to the Heartbeat checklist card',
  },
};
const REMEMBER = "Remember that the Results partner's contact is Lee.";

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const linkOf = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'More to try', exact: true });
const panelOf = (page: Page): Locator => guideRegion(page).getByRole('group', { name: 'Other things to try', exact: true });
const itemOf = (page: Page, id: string): Locator => panelOf(page).getByRole('listitem').filter({ has: page.getByText(ITEMS[id]!.label, { exact: true }) });
const controlOf = (page: Page, id: string): Locator => panelOf(page).getByRole(id === 'documents' ? 'link' : 'button', { name: ITEMS[id]!.button, exact: true });
const switchOf = (page: Page): Locator => page.getByRole('switch', { name: 'Demo view', exact: true });
const breakButton = (page: Page): Locator => page.locator('app-break-feed-box app-server-button button');
const hideOf = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'Hide guide', exact: true });
const stepFive = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'Step 5, Open the trace, upcoming', exact: true });
const changeOf = (page: Page): Locator => page.locator('app-persona-card').getByRole('button', { name: 'Change', exact: true });

/** A routed guide view: step 1, or the finish; `over` replaces fields of it. */
function guide(features: string[], over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    runEpoch: 1,
    step: 1,
    finished: false,
    steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: false })),
    breakFeed: { active: false, reason: 'not_watching' },
    step4Variant: 'unpaired',
    telegramRow: false,
    features,
    ...over,
  };
}

const finished = (features: string[], over: Record<string, unknown> = {}): Record<string, unknown> =>
  guide(features, { step: 5, finished: true, steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: true })), ...over });

/** Answers the page's polls without their guide.state events, so the routed guide stands. Call it before the page loads. */
async function keepRoutedGuide(page: Page): Promise<void> {
  await blockLiveSocket(page);
  await page.addInitScript(() => {
    const original = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const response = await original(input, init);
      const url = typeof input === 'string' ? input : input instanceof Request ? input.url : String(input);
      if (!/\/ocutalon\/api\/v1\/events\?/.test(url)) return response;
      try {
        const body = (await response.clone().json()) as { events: Array<{ type: string }> };
        body.events = body.events.filter((event) => event.type !== 'guide.state');
        return new Response(JSON.stringify(body), { status: response.status, statusText: response.statusText, headers: response.headers });
      } catch {
        return response;
      }
    };
  });
}

/**
 * Signs in with the guide that the case names, kept against the live polls, and waits for the loaded page. A second page of a case
 * (`again`) shares the first page's sign-in and only loads the page.
 */
async function openWith(page: Page, view: Record<string, unknown>, change?: (snapshot: Record<string, unknown>) => void, again = false): Promise<void> {
  await keepRoutedGuide(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = view;
    change?.(snapshot);
  });
  if (again) {
    await loadedAfter(page, () => page.goto('/ocutalon/'));
  } else {
    await signInReadmeLoaded(page);
  }
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

/** Records the POSTs of the page whose path ends with the suffix. */
function watchPosts(page: Page, suffix: string): string[] {
  const bodies: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname.endsWith(suffix)) bodies.push(request.postData() ?? '');
  });
  return bodies;
}

/** True when the first element is before the second in the document. */
function before(scope: Locator, first: string, second: string): Promise<boolean> {
  return scope.evaluate(
    (node, [a, b]) => {
      const x = node.querySelector(a!);
      const y = node.querySelector(b!);
      return x !== null && y !== null && (x.compareDocumentPosition(y) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
    },
    [first, second],
  );
}

/** K1 (real stack): /v1/state's guide.features is the server's list, and the panel shows exactly the items for it. */
test('K1: the panel shows exactly the items for the server\'s guide.features', async ({ page }) => {
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const response = await page.request.get(STATE);
  expect(response.status(), await response.text()).toBe(200);
  const features = ((await response.json()) as { guide: { features?: string[] } }).guide.features;
  expect(Array.isArray(features), 'the guide carries a list of feature ids').toBe(true);
  expect(features, 'the demo\'s own controls are always listed').toEqual(expect.arrayContaining(['suspiciousEmail', 'rejectFix', 'demoView']));
  test.info().annotations.push({ type: 'guide.features', description: (features ?? []).join(',') });
  console.log(`K1 guide.features=${(features ?? []).join(',')}`);

  const link = linkOf(page);
  if ((await link.getAttribute('aria-expanded')) !== 'true') await link.click();
  await expect(link).toHaveAttribute('aria-expanded', 'true');
  await expect(panelOf(page)).toBeVisible();
  await expect(panelOf(page).locator('.item-label'), 'the panel\'s labels are the registry\'s items for the list, in order').toHaveText(itemsFor(features).map((item) => item.label));
});

/** K2 (routed finish, four ids): the panel is open in the finish, after the links and before Try it yourself, with items 1 to 4. */
test('K2: in the finish the panel is open after the links and before Try it yourself, with items 1 to 4 and nothing sent', async ({ page }) => {
  const posts = [watchPosts(page, '/messages'), watchPosts(page, '/break-feed'), watchPosts(page, '/suspicious-request')];
  await openWith(page, finished(FOUR));

  await expect(linkOf(page), 'the link shows the open state').toHaveAttribute('aria-expanded', 'true');
  await expect(linkOf(page)).toHaveAttribute('aria-controls', /.+/);
  const panel = panelOf(page);
  await expect(panel).toBeVisible();
  const controlled = (await linkOf(page).getAttribute('aria-controls')) ?? '';
  await expect(page.locator(`[id="${controlled}"]`).getByRole('group', { name: 'Other things to try', exact: true }), 'aria-controls names the panel').toHaveCount(1);
  const finish = guideRegion(page).locator('.finish');
  expect(await before(finish, '.finish-links', 'app-more-to-try'), 'after the finish links').toBe(true);
  expect(await before(finish, 'app-more-to-try', 'app-try-it-row'), 'and before Try it yourself').toBe(true);
  await expect(panel.locator('p').first(), 'the label is a paragraph').toHaveText('Other things to try');
  await expect(guideRegion(page).getByRole('heading'), 'and no heading').toHaveCount(0);

  await expect(panel.getByRole('listitem')).toHaveCount(4);
  await expect(panel.locator('.item-label'), 'items 1 to 4 in order').toHaveText(FOUR.map((id) => ITEMS[id]!.label));
  for (const id of FOUR) {
    const item = itemOf(page, id);
    await expect(item.locator('.look-for'), `${id}: its look-for line`).toHaveText(ITEMS[id]!.lookFor);
    const control = controlOf(page, id);
    await expect(control, `${id}: one control named by its visible text`).toHaveCount(1);
    await expect(control).toHaveAttribute('type', 'button');
    await expect(control).toHaveClass(/button-secondary/);
    await expect(control).not.toHaveAttribute('aria-label', /.*/);
    await expect(item.getByRole('button'), `${id}: only that control`).toHaveCount(1);
  }
  for (const id of SEVEN.slice(4)) {
    await expect(panel.getByText(ITEMS[id]!.label, { exact: true }), `item ${id} is absent`).toHaveCount(0);
  }
  await page.waitForTimeout(500);
  expect(posts.map((one) => one.length), 'nothing was sent').toEqual([0, 0, 0]);
});

/** K3 (routed finish, seven ids): seven items in order, the Documents link and the rail focused by item 7. */
test('K3: seven ids show seven items in order, item 6 is a link to the Documents page and item 7 focuses the rail', async ({ page }) => {
  await openWith(page, finished(SEVEN));
  const panel = panelOf(page);
  await expect(panel.locator('.item-label')).toHaveText(SEVEN.map((id) => ITEMS[id]!.label));
  const documents = controlOf(page, 'documents');
  await expect(documents, 'item 6 is a link').toHaveAttribute('href', /#\/documents$/);
  await expect(controlOf(page, 'heartbeat')).toHaveAttribute('type', 'button');
  await controlOf(page, 'heartbeat').click();
  await expect(page.locator('section.rail'), 'item 7 puts focus on the rail').toBeFocused();
});

/** K4 (routed step 1): no panel; the link is in the Tab order; Enter opens, Space closes, focus stays on the link. */
test('K4: before the finish the panel is closed; the link opens it with Enter and closes it with Space, and focus stays on the link', async ({ page }) => {
  await openWith(page, guide(FOUR));
  const link = linkOf(page);
  await expect(panelOf(page)).toHaveCount(0);
  await expect(link).toHaveAttribute('aria-expanded', 'false');
  await expect(link).not.toHaveAttribute('aria-controls', /.*/);

  await stepFive(page).focus();
  await page.keyboard.press('Tab');
  await expect(link, 'Tab from the last step reaches the link').toBeFocused();
  await page.keyboard.press('Tab');
  await expect(hideOf(page), 'then Hide guide').toBeFocused();

  await link.focus();
  await page.keyboard.press('Enter');
  await expect(link).toHaveAttribute('aria-expanded', 'true');
  await expect(link, 'focus stays on the link').toBeFocused();
  await expect(panelOf(page)).toBeVisible();
  await expect(link).toHaveAttribute('aria-controls', /.+/);
  expect(await before(guideRegion(page).locator('.main'), '.prompt', 'app-more-to-try'), 'the panel sits after the prompt bar').toBe(true);
  await expect(panelOf(page).getByRole('listitem')).toHaveCount(4);

  // Tab through the open panel: Hide guide, the prompt's Send, then each control in order.
  await page.keyboard.press('Tab');
  await expect(hideOf(page)).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(guideRegion(page).locator('.prompt').getByRole('button', { name: 'Send', exact: true })).toBeFocused();
  for (const id of FOUR) {
    await page.keyboard.press('Tab');
    await expect(controlOf(page, id), `Tab reaches ${id}`).toBeFocused();
  }

  await link.focus();
  await page.keyboard.press(' ');
  await expect(link).toHaveAttribute('aria-expanded', 'false');
  await expect(panelOf(page)).toHaveCount(0);
  await expect(link, 'focus is still on the link').toBeFocused();
});

/** K5 (item 1, the real Persona card): Space on the button opens Change and focuses it. */
test.describe('K5', () => {
  test.afterEach(async ({ page }) => {
    const change = changeOf(page);
    if ((await change.count()) > 0 && (await change.getAttribute('aria-expanded')) === 'true') {
      await change.click();
      await expect(change).toHaveAttribute('aria-expanded', 'false');
    }
  });

  test('K5: item 1 opens the Persona card\'s Change and puts focus on it', async ({ page }) => {
    await openWith(page, guide(FOUR));
    await expect(changeOf(page), 'the card is loaded and closed').toHaveAttribute('aria-expanded', 'false');
    await linkOf(page).click();
    const control = controlOf(page, 'persona');
    await control.focus();
    await page.keyboard.press(' ');
    await expect(changeOf(page), 'Change is open').toHaveAttribute('aria-expanded', 'true');
    await expect(changeOf(page), 'and focused').toBeFocused();
    await expect(panelOf(page), 'the press keeps the panel open').toBeVisible();

    // A second press finds Change already open and leaves it open, with focus on it.
    await control.click();
    await page.waitForTimeout(500);
    await expect(changeOf(page), 'a second press leaves it open').toHaveAttribute('aria-expanded', 'true');
    await expect(changeOf(page)).toBeFocused();
  });

  test('K5b: in the drawer band item 1 opens the drawer, then the Persona card\'s Change, and puts focus on it', async ({ page }) => {
    await page.setViewportSize({ width: 1100, height: 720 });
    await openWith(page, guide(FOUR));
    const status = page.locator('button.status-button');
    await expect(status, 'the drawer is closed').toHaveAttribute('aria-expanded', 'false');
    await linkOf(page).click();
    await controlOf(page, 'persona').click();
    await expect(status, 'the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await expect(changeOf(page), 'Change is open').toHaveAttribute('aria-expanded', 'true');
    await expect(changeOf(page), 'and focused').toBeFocused();
  });
});

/** K6 (item 2, routed POST): Enter selects the mailbox tab and presses the chip once. */
test('K6: item 2 selects the Simulated mailbox tab, sends the chip\'s own POST once and puts focus on the chip', async ({ page }) => {
  const posts = watchPosts(page, '/mailbox/samples/suspicious-request');
  await page.route(SAMPLE, (route: Route) => route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ ref: 'zzk6' }) }));
  await openWith(page, guide(FOUR));
  await linkOf(page).click();
  await expect(page.getByRole('region', { name: 'Simulated devices' }).getByRole('tab', { name: /^Simulated phone/ }), 'the phone tab is selected first').toHaveAttribute('aria-selected', 'true');

  const control = controlOf(page, 'suspiciousEmail');
  await control.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('region', { name: 'Simulated devices' }).getByRole('tab', { name: /^Simulated mailbox/ }), 'the mailbox tab is selected').toHaveAttribute('aria-selected', 'true');
  const chip = sampleChipOf(page.locator('app-simulated-mailbox'), 'Sample: suspicious request');
  await expect(chip, 'focus is on the chip').toBeFocused();
  await expect.poll(() => posts.length, { message: 'the chip sent its request' }).toBe(1);
  await page.waitForTimeout(500);
  expect(posts, 'exactly one POST').toHaveLength(1);
});

/** K7 (item 3): a press presses the box's Break the feed once; an inactive box does nothing and keeps the focus, described by its hint. */
test('K7: item 3 presses the box\'s Break the feed once, and does nothing while the box is inactive', async ({ page, context }) => {
  const posts = watchPosts(page, '/demo/break-feed');
  await page.route(BREAK_FEED, (route: Route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ state: 'sent', startedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z') }) }),
  );
  await openWith(page, finished(FOUR, { breakFeed: { active: true } }));
  await expect(breakButton(page), 'the box is active').not.toHaveAttribute('aria-disabled', 'true');
  await controlOf(page, 'rejectFix').click();
  await expect(breakButton(page), 'focus is on Break the feed').toBeFocused();
  await expect.poll(() => posts.length, { message: 'the box sent its request' }).toBe(1);
  await page.waitForTimeout(500);
  expect(posts, 'exactly one POST, the box\'s own').toHaveLength(1);

  const other = await context.newPage();
  const otherPosts = watchPosts(other, '/demo/break-feed');
  await other.route(BREAK_FEED, (route: Route) => route.fulfill({ status: 200, contentType: 'application/json', body: '{}' }));
  await openWith(other, finished(FOUR, { breakFeed: { active: false, reason: 'not_watching' } }), undefined, true);
  await expect(breakButton(other)).toHaveAttribute('aria-disabled', 'true');
  await controlOf(other, 'rejectFix').click();
  await expect(breakButton(other), 'focus is on the inactive box').toBeFocused();
  await other.waitForTimeout(500);
  expect(otherPosts, 'an inactive box sends nothing').toHaveLength(0);
  const hint = await other.locator('app-break-feed-box .hint').getAttribute('id');
  expect(hint, 'the hint has an id').toBeTruthy();
  expect((await breakButton(other).getAttribute('aria-describedby')) ?? '', 'and describes the button').toContain(hint!);
});

/** K8 (item 4): the switch turns off and holds focus; the demo parts go; nothing is sent. */
test('K8: item 4 turns the Demo view switch off with focus on it, hides the demo parts and sends nothing', async ({ page }) => {
  await openWith(page, finished(FOUR));
  const writes: string[] = [];
  page.on('request', (request) => {
    if (request.method() !== 'GET') writes.push(`${request.method()} ${request.url()}`);
  });
  await expect(switchOf(page)).toHaveAttribute('aria-checked', 'true');
  await controlOf(page, 'demoView').click();
  await expect(switchOf(page), 'the switch is off').toHaveAttribute('aria-checked', 'false');
  await expect(switchOf(page), 'and focused').toBeFocused();
  await expect(guideRegion(page)).toHaveCount(0);
  await expect(page.locator('app-break-feed-box')).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Simulated devices' })).toHaveCount(0);
  expect(await page.evaluate((key) => sessionStorage.getItem(key), DEMO_VIEW_KEY), 'the choice is kept for the tab').toBe('1');
  await page.waitForTimeout(500);
  expect(writes, 'the press sent nothing to the server').toEqual([]);
});

/** K9 (item 5, routed seven ids): one POST /messages with the prompt, from the user; none while the allowance is used up. */
test('K9: item 5 sends its prompt once as the user\'s own message, and sends nothing while the allowance is used up', async ({ page, context }) => {
  const bodies: Array<{ clientId: string; text: string; fromGuide: boolean }> = [];
  const accept = async (route: Route): Promise<void> => {
    const body = route.request().postDataJSON() as { clientId: string; text: string; fromGuide: boolean };
    bodies.push(body);
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  };
  await page.route(`**${MESSAGES}`, accept);
  await openWith(page, finished(SEVEN));
  const control = controlOf(page, 'memory');
  await expect(control).not.toHaveAttribute('aria-disabled', 'true');
  await control.click();
  await expect.poll(() => bodies.length, { message: 'the prompt was posted' }).toBe(1);
  await page.waitForTimeout(500);
  expect(bodies, 'exactly one POST').toHaveLength(1);
  expect(bodies[0]!.text).toBe(REMEMBER);
  expect(bodies[0]!.fromGuide, 'as the user\'s own message').toBe(false);
  await expect(control, 'while its turn is in flight the control is aria-disabled').toHaveAttribute('aria-disabled', 'true');
  await control.click({ force: true });
  await page.waitForTimeout(500);
  expect(bodies, 'and a second press sends nothing').toHaveLength(1);

  const used = await context.newPage();
  const usedBodies: unknown[] = [];
  await used.route(`**${MESSAGES}`, async (route: Route) => {
    usedBodies.push(route.request().postData());
    await route.fulfill({ status: 202, contentType: 'application/json', body: '{}' });
  });
  await openWith(
    used,
    finished(SEVEN),
    (snapshot) => {
      snapshot['status'] = [...(snapshot['status'] as unknown[]), { condition: 'allowance', active: true, slots: { limit: 20, time: '2037-07-01T12:00:00Z' } }];
    },
    true,
  );
  const blocked = controlOf(used, 'memory');
  await expect(blocked, 'aria-disabled, never disabled').toHaveAttribute('aria-disabled', 'true');
  await expect(blocked).not.toHaveAttribute('disabled', /.*/);
  const reason = await blocked.getAttribute('aria-describedby');
  expect(reason, 'and described by the composer\'s reason').toBeTruthy();
  await expect(used.locator(`[id="${reason}"]`), 'which is on the page').toHaveCount(1);
  await blocked.click({ force: true });
  await used.waitForTimeout(500);
  expect(usedBodies, 'a press sends nothing').toEqual([]);
});

/** K10: with the switch off, or without demo mode, neither the link nor the panel shows. */
test('K10: neither the link nor the panel shows with the switch off or without demo mode', async ({ page, context }) => {
  await page.addInitScript((key) => sessionStorage.setItem(key, '1'), DEMO_VIEW_KEY);
  await openWith(page, finished(FOUR));
  await expect(linkOf(page)).toHaveCount(0);
  await expect(page.getByRole('group', { name: 'Other things to try', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'More to try', exact: true })).toHaveCount(0);

  const plain = await context.newPage();
  await openWith(
    plain,
    finished(FOUR),
    (snapshot) => {
      snapshot['demoMode'] = false;
      delete snapshot['guide'];
    },
    true,
  );
  await expect(plain.getByRole('button', { name: 'More to try', exact: true })).toHaveCount(0);
  await expect(plain.getByRole('group', { name: 'Other things to try', exact: true })).toHaveCount(0);
  await expect(plain.getByRole('region', { name: 'Demo guide' })).toHaveCount(0);
});

const iso = (ms: number): string => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

/**
 * Routes the page's polls so that no real guide.state stands: each view that the returned function takes goes into the next real answer
 * as a guide.state event with the Seq that follows the answer's session events. It resolves once that answer is served. Call it before
 * the page loads.
 */
async function guidePushes(page: Page): Promise<(view: Record<string, unknown>) => Promise<void>> {
  const queue: Record<string, unknown>[] = [];
  let queued = 0;
  let served = 0;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as { events: Array<Record<string, unknown>> };
    body.events = body.events.filter((event) => event['type'] !== 'guide.state');
    const view = queue.shift();
    if (view !== undefined) {
      let seq = Number(new URL(route.request().url()).searchParams.get('after'));
      for (const event of body.events) {
        if (event['stream'] === 'session') seq = Math.max(seq, Number(event['seq']));
      }
      body.events.push({ seq: seq + 1, stream: 'session', ts: iso(Date.now()), type: 'guide.state', payload: view });
    }
    await route.fulfill({ response, json: body });
    if (view !== undefined) served += 1;
  });
  return async (view) => {
    queued += 1;
    const target = queued;
    queue.push(view);
    await expect.poll(() => served, { message: 'a poll carried the pushed guide view' }).toBeGreaterThanOrEqual(target);
  };
}

/** K11: when the finish leaves, the panel's focus and open state follow the rule; a new finish opens it again. */
test('K11: leaving the finish hands focus on, closes the panel unless a press kept it open, and a new finish opens it again', async ({ page }) => {
  const posts = watchPosts(page, '/demo/break-feed');
  await page.route(BREAK_FEED, (route: Route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ state: 'sent', startedAt: iso(Date.now()) }) }),
  );
  await blockLiveSocket(page);
  const push = await guidePushes(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = finished(FOUR, { breakFeed: { active: true } });
  });
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(panelOf(page), 'the finish opens the panel').toBeVisible();

  // The finish leaves while a panel control holds focus: focus goes to the box, and the panel (never pressed) closes.
  await controlOf(page, 'rejectFix').focus();
  await push(guide(FOUR, { step: 3, breakFeed: { active: true } }));
  await expect.soft(breakButton(page), 'focus went to Break the feed when the finish left').toBeFocused();
  await expect.soft(panelOf(page), 'and the panel is closed outside the finish').toHaveCount(0);

  // The user closes the panel, and the next finish opens it again.
  await linkOf(page).click();
  await expect(panelOf(page)).toBeVisible();
  await linkOf(page).click();
  await expect(panelOf(page)).toHaveCount(0);
  await push(finished(FOUR, { breakFeed: { active: true } }));
  await expect.soft(panelOf(page), 'a new finish opens the panel again').toBeVisible();

  // A press in the finish keeps the panel open when the finish leaves.
  await controlOf(page, 'rejectFix').click();
  await expect.poll(() => posts.length, { message: 'the box sent its request' }).toBe(1);
  await push(guide(FOUR, { step: 3, breakFeed: { active: true } }));
  await expect.soft(panelOf(page), 'the panel the press kept open stays').toBeVisible();
});

/** The two narrower layout bands of LAYOUT_QUERIES that the default viewport does not reach: the drawer (1024 to 1279px) and the stacked column (below 1024px), each at 720px tall. */
const BANDS = [
  { band: 'drawer', width: 1100, height: 720 },
  { band: 'stacked', width: 800, height: 720 },
] as const;

for (const { band, width, height } of BANDS) {
  /** K12 (item 2 in a narrow band): the press finds the Simulated mailbox tab's chip, sends the chip's one POST and focuses the chip. */
  test(`K12: in the ${band} band (${width}x${height}) item 2 selects the mailbox tab, sends the chip's own POST once and puts focus on the chip`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    const posts = watchPosts(page, '/mailbox/samples/suspicious-request');
    await page.route(SAMPLE, (route: Route) => route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ ref: 'zzk12' }) }));
    await openWith(page, guide(FOUR));
    await linkOf(page).click();
    const control = controlOf(page, 'suspiciousEmail');
    await control.focus();
    await page.keyboard.press('Enter');
    const chip = sampleChipOf(page.locator('app-simulated-mailbox'), 'Sample: suspicious request');
    await expect(chip, `the chip is on the page in the ${band} band`).toBeVisible();
    await expect(chip, 'focus is on the chip').toBeFocused();
    await expect.poll(() => posts.length, { message: 'the chip sent its request' }).toBe(1);
    await page.waitForTimeout(500);
    expect(posts, 'exactly one POST, the chip\'s own').toHaveLength(1);
  });

  /** K13 (item 3 in a narrow band): the press finds the Break the feed box, sends its one POST and focuses its button. */
  test(`K13: in the ${band} band (${width}x${height}) item 3 presses the box's Break the feed once and puts focus on it`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    const posts = watchPosts(page, '/demo/break-feed');
    await page.route(BREAK_FEED, (route: Route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ state: 'sent', startedAt: iso(Date.now()) }) }),
    );
    await openWith(page, finished(FOUR, { breakFeed: { active: true } }));
    await expect(breakButton(page), `the box is on the page in the ${band} band`).toBeVisible();
    await expect(breakButton(page), 'the box is active').not.toHaveAttribute('aria-disabled', 'true');
    await controlOf(page, 'rejectFix').click();
    await expect(breakButton(page), 'focus is on Break the feed').toBeFocused();
    await expect.poll(() => posts.length, { message: 'the box sent its request' }).toBe(1);
    await page.waitForTimeout(500);
    expect(posts, 'exactly one POST, the box\'s own').toHaveLength(1);
  });
}

/** K14 (matrix 5, error handling): when the Persona card has not loaded, item 1 puts focus on the Persona heading. */
test('K14: item 1 puts focus on the Persona heading when the Persona card has not loaded', async ({ page }) => {
  let served = 0;
  await page.route('**/ocutalon/api/v1/persona', (route: Route) => {
    served += 1;
    return route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'zz The read failed.' } }) });
  });
  await openWith(page, guide(FOUR));
  await expect.poll(() => served, { message: 'the card\'s read was answered with its failure' }).toBeGreaterThan(0);
  await expect(changeOf(page), 'the card has not loaded').toHaveCount(0);
  await linkOf(page).click();
  await controlOf(page, 'persona').click();
  await expect(page.locator('#rail-heading-persona'), 'focus is on the Persona heading').toBeFocused();
});

/** K15 (matrix 6, error handling): while the email limit holds, item 2 selects the tab and focuses the inactive chip, and sends nothing. */
test('K15: item 2 sends nothing while the email limit holds, and focuses the chip, which is inactive and described by the limit', async ({ page }) => {
  const posts = watchPosts(page, '/mailbox/samples/suspicious-request');
  await page.route(SAMPLE, (route: Route) =>
    route.fulfill({
      status: 429,
      contentType: 'application/json',
      body: JSON.stringify({ error: { code: 'email_limit', message: 'zz limit' }, retryAt: iso(Date.now() + 3_600_000) }),
    }),
  );
  await openWith(page, guide(FOUR));
  await linkOf(page).click();
  const chip = sampleChipOf(page.locator('app-simulated-mailbox'), 'Sample: suspicious request');
  await controlOf(page, 'suspiciousEmail').click();
  await expect.poll(() => posts.length, { message: 'the first press reached the chip, which the server refused' }).toBe(1);
  await expect(chip, 'the limit made the chip inactive').toHaveAttribute('aria-disabled', 'true');

  await page.getByRole('tab', { name: /^Simulated phone/ }).click();
  await controlOf(page, 'suspiciousEmail').click();
  await expect(page.getByRole('tab', { name: /^Simulated mailbox/ }), 'the mailbox tab is selected again').toHaveAttribute('aria-selected', 'true');
  await expect(chip, 'focus is on the inactive chip').toBeFocused();
  await page.waitForTimeout(500);
  expect(posts, 'the second press sent nothing').toHaveLength(1);
  const reason = await chip.getAttribute('aria-describedby');
  expect(reason ?? '', 'the chip is described by the limit').toContain('mailbox-email-limit');
  await expect(page.locator('#mailbox-email-limit'), 'which is on the page').toHaveCount(1);
});
