import { expect, test, type Locator, type Page, type Route } from '../support/fixtures';

import { MORE_TO_TRY_GROUPS, MORE_TO_TRY_ITEMS, groupsOf, itemsFor } from '../../src/app/guide/more-to-try-view.ts';
import { changeSnapshot, MESSAGES, STATE } from '../support/api';
import { signIn } from '../sign-in/helpers';
import { sampleChipOf } from '../support/devices';
import { loadedAfter, signInReadmeLoaded } from '../support/floor';
import { cleanFixtureRows, fixtureUser, seedIncident } from '../support/iris';
import { blockLiveSocket } from '../support/socket';

/**
 * Story 4.11, the demo guide's "Other things to try" panel and its "More to try" link, on the sign-in stack with the README account.
 * K1 reads the real stack: /v1/state's guide.features is Demo.Features.Present()'s list, and the panel shows exactly the items for it
 * (it records the list, which is Task 0 (a)). Every other case answers /state with a guide that it names (a finish or step 1, with the
 * features it names) and keeps it by dropping guide.state from the page's polls; the POSTs of items 2, 3 and 5 are routed and counted,
 * because their downstream flows are pinned by the demo-path specs. K5 uses the real Persona card, and collapses it again.
 *   - K2 (matrix 1): the routed finish: the panel is open after the links and before Try it yourself, items 1 to 4 in order;
 *   - K28 (Story 25.2): the link of the history item opens the History page;
 *   - K3 (matrix 3, 10): every id of the registry: its items in order with their look-for lines, links to the Documents page for the documents and sources items, the link to the Usage page for the usage item, the Memory heading focused by the Memory card item and the Heartbeat checklist heading by the heartbeat item;
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
 *   - K16: the panel open in the finish leaves the chat its room: the finish starts with the panel open from 680px tall and closed under it
 *     (the compact band; the link opens it), no page scroll and a chat of at least 160px (64px in the compact band, at drawer widths
 *     too) where the page fills the viewport, a window of at least the label line and one control that takes all the room the chat
 *     leaves above its floor unless it shows everything, the panel a scroll region of its own in as many columns as fit, no text
 *     clipped, and each control that Tab reaches wholly in view with its focus ring; the stacked column grows with the panel and
 *     scrolls as a page; every K16 page names its banner state (none), and K16b shows the no-model-key banner: the band is decided on the
 *     height left after it (one pixel under 680px plus the banner starts the panel closed, exactly that starts it open);
 *   - K17: the same room, and the same Tab case, when the link opens the panel before the finish (the prompt bar's branch);
 *   - K19: in the compact band the finish starts with the panel closed (the link says so) and the chat keeps at least 64px with no
 *     page scroll, at drawer widths too; K19b: at 680px tall it starts open and the link closes it;
 *   - K20: the finish's own layout where the page is framed: row 1 above the finish and on one line without "About 2 minutes" (its
 *     link and Hide guide at its right end from 680px tall), and Run again at the end of the Try it yourself row from 1024 to 1279px,
 *     below it elsewhere;
 *   - K21: with the no-model-key banner shown the finish has no sideways scroll at 1280x600, 1280x700 and 320x700, and a chat at its
 *     floor and no page scroll when framed before the panel is opened; after More to try the chat is still at its floor (the page may
 *     scroll vertically in the compact band, the Planner, 2026-11-07; both framed rows are in the band once the banner shows);
 *   - K21b: where the case squeezes the room itself (1280x600, the banner), the panel the user opens is at its shortest window, the
 *     chat keeps 64px and the page scrolls vertically, never sideways;
 *   - K22: at the narrow widths (305 to 480px, 320px at any height from 360 to 900px) the page does not scroll sideways, with the guide
 *     at step 1 (panel closed, then opened by the link) and in the finish;
 *   - K23: with wider font metrics (a wide family and letter and word spacing) at 1280x680, 1280x600, 1024x680, 320x700 and with the
 *     banner at the band's edge, the chat keeps its floor, the framed page does not scroll, and no page scrolls sideways; where the wider
 *     text leaves no room for the panel it starts closed;
 *   - K24: where the room is too small for the panel even at its shortest window (the case holds the panel's window at 900px by its own
 *     style) the finish closes the panel, and the link says so; the squeeze holds until the viewport's height changes (then the panel
 *     opens by itself) or a new finish begins (then it opens again);
 *   - K18: a focused panel group hands focus on when the finish leaves;
 *   - K27: the panel's level-4 headings are exactly the groups that have items, in order, each followed by its own list of items, and no
 *     heading takes focus;
 *   - K9c (Story 23.5, AC15): the partner warning item sends "Warn the partner about the delay." once as the user's own message and sends nothing while a turn is in flight;
 *   - K14 (matrix 5, error): item 1 focuses the Persona heading when the card has not loaded;
 *   - K15 (matrix 6, error): item 2 sends nothing while the email limit holds, and focuses the inactive chip;
 *   - K25 (Story 23.6, AC 10): the incident summary item at the finish presses the Dismiss of the newest resolved incident card: the card's chip says
 *     Closed, the incident's summary is a card in the chat and a message on the Simulated phone, and the finish is still shown;
 *   - K26 (Story 23.6, AC 16): with no resolved incident to close the same control sends "Show me the incident summary" once as the user's own message.
 */
const BREAK_FEED = '**/ocutalon/api/v1/demo/break-feed';
const SAMPLE = '**/ocutalon/api/v1/mailbox/samples/suspicious-request';
const DEMO_VIEW_KEY = 'ocutalon.demoView.off';

const FOUR = ['persona', 'suspiciousEmail', 'rejectFix', 'demoView'];
// The ids of the routed real finish (openRealFinish: K16, K16b, K19 to K23) and of K17: all four groups of the panel show, so the room is measured with the fourth heading.
const BAND_IDS = [...FOUR, 'memory', 'usage'];
// Every id of the registry, in its order, so that an item another story adds joins the K3 and K9 cases; ITEMS below is the independent text oracle.
const ALL = MORE_TO_TRY_ITEMS.map((item) => item.id);
/** The ids the panel shows for a feature list, in the order it shows them: the sets of groupsOf, flattened. */
const shown = (ids: readonly string[] | undefined): string[] => groupsOf(itemsFor(ids)).flatMap((set) => set.items.map((item) => item.id));
/** The id that the server lists first (Demo.Features, Story 23.6); a routed case names the ids it wants, so this one joins only where a case says so. */
const SUMMARY = 'incidentSummary';
const SUMMARY_PROMPT = 'Show me the incident summary';

/** The ruled texts of the items, written out here as the independent oracle of the page's own. */
const ITEMS: Record<string, { label: string; lookFor: string; button: string }> = {
  incidentSummary: {
    label: 'Read the incident summary',
    lookFor:
      'This closes the guide\'s resolved incident, as Dismiss on its card does. Look for the incident summary in the chat and on the Simulated phone: what happened and when, the cause and the evidence, each approval, the orders affected and the model cost. Later, ask "Show me the incident summary" to get it again.',
    button: 'Close the incident',
  },
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
  reroute: {
    label: 'Reroute the failed orders',
    lookFor:
      'First do "Reject a fix", so the failed orders are still waiting. This asks OcuTalon in the chat to reroute them to OrdersForReview, the review queue. The approval request shows a dry run: how many orders, one example, and where they go now and where they would go. Approve it, then read the result in the chat and press Trace to see the copies go to OrdersForReview while the originals stay unchanged. On your own install, suspend and resume work the same way.',
    button: 'Ask to reroute',
  },
  partnerWarning: {
    label: 'Warn the partner',
    lookFor:
      'This asks OcuTalon in the chat to warn the partner about an incident\'s delay, so it needs an incident that isn\'t closed: if you closed the guide\'s incident, do "Reject a fix" first. OcuTalon drafts a short notice from the incident\'s counts, times and cause, and it comes as an approval request that shows the exact text and the recipients, simulated contacts. Approve it, then open the Simulated mailbox to read the notice exactly as you approved it. Nothing goes to a real inbox.',
    button: 'Ask for a partner warning',
  },
  queueWatch: {
    label: 'Watch queue backlogs',
    lookFor:
      'This asks OcuTalon in the chat to watch the queue backlogs. Look for the Queue-backlog check under Background checks, with its schedule, last run and result. Every minute it reads the Orders production\'s queues, and when one holds more than 100 messages, or its oldest message has waited over 10 minutes, OcuTalon decides once whether to tell you. On a quiet demo it reads Passed. To stop, ask "Stop watching the queue backlogs."',
    button: 'Ask to watch queues',
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
  memoryCard: {
    label: 'Pin a memory',
    lookFor:
      'First do "Ask it to remember something". Then open All memories in the Memory card and press Pin on the memory marked Told. Open Pinned to see it: pinned facts are read at the start of each conversation, up to 1,000 tokens.',
    button: 'Go to the Memory card',
  },
  documents: {
    label: 'Ask about a document',
    lookFor:
      'On the Documents page, press Add the sample runbook, or add a short file of your own (nothing personal: Visual Trace on the demo is shared). When it reads Ready, ask in the chat "According to the runbook, what should I do when partner orders fail with a date error?", or ask about your own file, and look for the chip under the answer that names the document and its section.',
    button: 'Open the Documents page',
  },
  heartbeat: {
    label: 'Run a heartbeat check-in',
    lookFor: 'In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in\'s outcome and its cost in the card.',
    button: 'Go to the Heartbeat checklist card',
  },
  sources: {
    label: 'See where an answer came from',
    lookFor:
      'Under an answer from your documents, press the chip that names the document and section to read the passage, then Open document to see the whole file. Under an answer that recalls something you asked it to remember, press From memory to see what it remembered and when.',
    button: 'Open the Documents page',
  },
  // mutation: the registry's usage look-for reads "on your messages and incidents." -> K3 (the usage item's look-for text) red.
  usage: {
    label: 'See tokens and cost',
    lookFor:
      'On the Usage page, choose a range and group by day, agent, channel or model. The tokens and cost come from your chat turns and from the agents\' decisions on your messages, and each day shows its largest model request against the 100,000-token limit. If it reads "No model use in this period.", chat or run the guide first.',
    button: 'Open the Usage page',
  },
  // mutation: the registry's history look-for drops its last sentence ("If it reads "No decisions yet.", run the guide first.") -> K3 (the history item's look-for text) red.
  history: {
    label: 'Look back at past decisions',
    lookFor:
      'On the History page, filter the Decisions tab by outcome, channel, date or fallback, and open a decision to read its reasons, with a link to its trace. The Incidents tab lists your incidents with their state and, once an incident has closed, its summary. If it reads "No decisions yet.", run the guide first.',
    button: 'Open the History page',
  },
};
const REMEMBER = "Remember that the Results partner's contact is Lee.";
const REROUTE = 'Reroute the failed orders to OrdersForReview.';
const PARTNER = 'Warn the partner about the delay.';

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const linkOf = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'More to try', exact: true });
const panelOf = (page: Page): Locator => guideRegion(page).getByRole('group', { name: 'Other things to try', exact: true });
const itemOf = (page: Page, id: string): Locator => panelOf(page).getByRole('listitem').filter({ has: page.getByText(ITEMS[id]!.label, { exact: true }) });
const controlOf = (page: Page, id: string): Locator => itemOf(page, id).getByRole(id === 'documents' || id === 'sources' || id === 'usage' || id === 'history' ? 'link' : 'button', { name: ITEMS[id]!.button, exact: true });
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

/**
 * Answers the page's polls without their guide.state and status events, so the routed guide and the routed status stand: the banners
 * are whatever the case's /state says (openWith clears them; K21 sets the no-model-key one). Call it before the page loads.
 */
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
        body.events = body.events.filter((event) => event.type !== 'guide.state' && event.type !== 'status');
        return new Response(JSON.stringify(body), { status: response.status, statusText: response.statusText, headers: response.headers });
      } catch {
        return response;
      }
    };
  });
}

/**
 * Signs in with the guide that the case names, kept against the live polls, and waits for the loaded page. A second page of a case
 * (`again`) shares the first page's sign-in and only loads the page. The page's statuses are exactly the ones `change` adds (none for
 * most cases, K9's allowance) and, when `banner` is true, the no-model-key condition, whatever the stack's key state is: a banner is
 * above the guide and takes the chat's height, so a case names whether its page shows one.
 */
async function openWith(
  page: Page,
  view: Record<string, unknown>,
  change?: (snapshot: Record<string, unknown>) => void,
  again = false,
  banner = false,
): Promise<void> {
  await keepRoutedGuide(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = view;
    snapshot['status'] = banner ? [{ condition: 'noModelKey', active: true }] : [];
    change?.(snapshot);
  });
  if (again) {
    await loadedAfter(page, () => page.goto('/ocutalon/'));
  } else {
    await signInReadmeLoaded(page);
  }
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('app-banner-stack [data-banner="noModelKey"]'), banner ? 'the page shows the no-model-key banner' : 'the page shows no no-model-key banner').toHaveCount(banner ? 1 : 0);
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
  expect(features, 'the demo\'s own controls are always listed').toEqual(expect.arrayContaining([SUMMARY, 'suspiciousEmail', 'rejectFix', 'demoView']));
  expect((features ?? [])[0], 'and the incident summary is first').toBe(SUMMARY);
  expect(features, 'this tree has Epic 39\'s Run now command, so the heartbeat is listed').toEqual(expect.arrayContaining(['heartbeat']));
  test.info().annotations.push({ type: 'guide.features', description: (features ?? []).join(',') });
  console.log(`K1 guide.features=${(features ?? []).join(',')}`);

  const link = linkOf(page);
  if ((await link.getAttribute('aria-expanded')) !== 'true') await link.click();
  await expect(link).toHaveAttribute('aria-expanded', 'true');
  await expect(panelOf(page)).toBeVisible();
  await expect(panelOf(page).locator('.item-label'), 'the panel\'s labels are the registry\'s items for the list, in order').toHaveText(shown(features).map((id) => MORE_TO_TRY_ITEMS.find((item) => item.id === id)!.label));
});

/** K2 (routed finish, four ids): the panel is open in the finish, after the links and before Try it yourself, with items 1 to 4. */
test('K2: in the finish the panel is open after the links and before Try it yourself, with items 1 to 4 and nothing sent', async ({ page }) => {
  // These cases are about the panel's items, not its room: a tall viewport leaves the finish its panel whatever the page's fonts.
  await page.setViewportSize({ width: 1280, height: 900 });
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
  await expect(panel.getByRole('heading', { level: 4 }), 'the groups with an item show their heading').toHaveText(['Incidents and fixes', 'Safety and settings']);
  await expect(panel.locator('p.group-label'), 'and the label is still a paragraph').toHaveCount(1);
  await expect(guideRegion(page).getByRole('heading'), 'with no other heading in the guide').toHaveCount(2);

  await expect(panel.getByRole('listitem')).toHaveCount(4);
  await expect(panel.locator('.item-label'), 'the four items in the order shown').toHaveText(shown(FOUR).map((id) => ITEMS[id]!.label));
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
  for (const id of ALL.filter((one) => !FOUR.includes(one))) {
    await expect(panel.getByText(ITEMS[id]!.label, { exact: true }), `item ${id} is absent`).toHaveCount(0);
  }
  await page.waitForTimeout(500);
  expect(posts.map((one) => one.length), 'nothing was sent').toEqual([0, 0, 0]);
});

/** K3 (routed finish, every id): the items in order, the Documents links of the documents and sources items, the Memory heading focused by the Memory card item and the Heartbeat checklist heading by the heartbeat item. */
test('K3: every id shows its item in order, the documents and sources items are links to the Documents page, the Memory card item focuses the Memory heading and the heartbeat item the Heartbeat checklist heading', async ({ page }) => {
  // These cases are about the panel's items, not its room: a tall viewport leaves the finish its panel whatever the page's fonts.
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.route('**/ocutalon/api/v1/documents', (route) =>
    route.request().method() === 'GET'
      ? route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ documents: [{ ref: 'zzK3', name: 'k3.md', addedAt: '2025-03-02T10:00:00Z', size: 10, state: 'ready' }] }) })
      : route.fallback(),
  );
  await openWith(page, finished(ALL));
  const panel = panelOf(page);
  await expect(panel.locator('.item-label')).toHaveText(shown(ALL).map((id) => ITEMS[id]!.label));
  for (const id of ALL) await expect(itemOf(page, id).locator('.look-for'), `${id}: its look-for line`).toHaveText(ITEMS[id]!.lookFor);
  const documents = controlOf(page, 'documents');
  await expect(documents, 'the documents item is a link').toHaveAttribute('href', /#\/documents$/);
  await expect(controlOf(page, 'sources'), 'the sources item is a link to the same page').toHaveAttribute('href', /#\/documents$/);
  await expect(controlOf(page, 'usage'), 'the usage item is a link to the Usage page').toHaveAttribute('href', /#\/usage$/);
  await expect(controlOf(page, 'history'), 'the history item is a link to the History page').toHaveAttribute('href', /#\/history$/);
  await expect(controlOf(page, 'memoryCard')).toHaveAttribute('type', 'button');
  await controlOf(page, 'memoryCard').click();
  await expect(page.locator('#rail-heading-memory'), 'the Memory card item puts focus on the Memory heading').toBeFocused();
  await expect(controlOf(page, 'heartbeat')).toHaveAttribute('type', 'button');
  await controlOf(page, 'heartbeat').click();
  await expect(page.locator('#rail-heading-heartbeat'), 'the heartbeat item puts focus on the Heartbeat checklist heading').toBeFocused();
});

/** K3b (routed finish, every id): pressing the usage item's link opens the Usage page by navigation. */
test('K3b: the link of the usage item opens the Usage page', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await openWith(page, finished(ALL));
  await controlOf(page, 'usage').click();
  await expect(page, 'at the address #/usage').toHaveURL(/#\/usage$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Usage', exact: true }), 'the Usage page').toBeVisible();
});

/** K28 (routed finish, every id): pressing the history item's link opens the History page by navigation, "Open the History page", and the page is titled and headed History. */
test('K28: the link of the history item opens the History page', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.route('**/ocutalon/api/v1/history/**', (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ page: 1, pages: 1, decisions: [] }) }));
  await openWith(page, finished(ALL));
  await expect(controlOf(page, 'history'), 'its control is named by its visible text').toHaveText('Open the History page');
  await controlOf(page, 'history').click();
  await expect(page, 'at the address #/history').toHaveURL(/#\/history$/);
  await expect(page.getByRole('heading', { level: 1, name: 'History', exact: true }), 'the History page').toBeVisible();
  await expect(page, 'titled History').toHaveTitle('History \u00B7 OcuTalon');
});

/**
 * K1b (real stack): the server lists the heartbeat, so its item shows, and its press opens the rail (the drawer in the drawer band) and
 * puts focus on the Heartbeat checklist card's heading, with nothing pressed.
 */
for (const size of [{ name: 'default viewport', width: 0, height: 0 }, { name: 'drawer band', width: 1100, height: 720 }]) {
  test(`K1b: on the real stack the heartbeat item is listed and its press focuses the Heartbeat checklist heading (${size.name})`, async ({ page }) => {
    if (size.width > 0) await page.setViewportSize({ width: size.width, height: size.height });
    await signInReadmeLoaded(page);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    const link = linkOf(page);
    if ((await link.getAttribute('aria-expanded')) !== 'true') await link.click();
    await expect(controlOf(page, 'heartbeat'), 'the heartbeat item is in the real panel').toHaveCount(1);
    const heading = page.locator('#rail-heading-heartbeat');
    await expect(heading, 'the card\'s heading is named Heartbeat checklist').toHaveText('Heartbeat checklist');
    const writes: string[] = [];
    page.on('request', (request) => {
      if (request.method() !== 'GET' && new URL(request.url()).pathname.includes('/api/v1/heartbeat')) writes.push(request.method());
    });
    await controlOf(page, 'heartbeat').click();
    if (size.width > 0) await expect(page.locator('button.status-button'), 'the drawer is open').toHaveAttribute('aria-expanded', 'true');
    await expect(heading, 'focus is on the Heartbeat checklist heading').toBeFocused();
    await expect(panelOf(page), 'the press keeps the panel open').toBeVisible();
    await page.waitForTimeout(500);
    expect(writes, 'nothing was pressed, saved or run').toHaveLength(0);
  });
}

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

  // Tab through the open panel: Hide guide, the prompt's Send, the panel's own stop, then each control in order.
  await page.keyboard.press('Tab');
  await expect(hideOf(page)).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(guideRegion(page).locator('.prompt').getByRole('button', { name: 'Send', exact: true })).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(panelOf(page), 'the panel is a scroll region and a Tab stop of its own, before its controls').toBeFocused();
  for (const id of shown(FOUR)) {
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
  // These cases are about the panel's items, not its room: a tall viewport leaves the finish its panel whatever the page's fonts.
  await page.setViewportSize({ width: 1280, height: 900 });
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
  // These cases are about the panel's items, not its room: a tall viewport leaves the finish its panel whatever the page's fonts.
  await page.setViewportSize({ width: 1280, height: 900 });
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

/** K9 (the memory item, routed every id of the registry): one POST /messages with the prompt, from the user; none while the allowance is used up. */
test('K9: item 5 sends its prompt once as the user\'s own message, and sends nothing while the allowance is used up', async ({ page, context }) => {
  const bodies: Array<{ clientId: string; text: string; fromGuide: boolean }> = [];
  const accept = async (route: Route): Promise<void> => {
    const body = route.request().postDataJSON() as { clientId: string; text: string; fromGuide: boolean };
    bodies.push(body);
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  };
  await page.route(`**${MESSAGES}`, accept);
  await openWith(page, finished(ALL));
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
  // The allowance banner above the guide takes height, and a viewport that leaves under 680px after it starts the panel closed.
  await used.setViewportSize({ width: 1280, height: 900 });
  const usedBodies: unknown[] = [];
  await used.route(`**${MESSAGES}`, async (route: Route) => {
    usedBodies.push(route.request().postData());
    await route.fulfill({ status: 202, contentType: 'application/json', body: '{}' });
  });
  await openWith(
    used,
    finished(ALL),
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

/** K9b (Story 23.2, AC12): the reroute item sends its prompt once as the user's own message, and sends nothing while a turn is in flight. */
test('K9b: the reroute item sends its prompt once as the user\'s own message, and sends nothing while its turn is in flight', async ({ page }) => {
  const bodies: Array<{ clientId: string; text: string; fromGuide: boolean }> = [];
  await page.route(`**${MESSAGES}`, async (route: Route) => {
    const body = route.request().postDataJSON() as { clientId: string; text: string; fromGuide: boolean };
    bodies.push(body);
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  });
  await openWith(page, finished(['rejectFix', 'reroute']));
  await expect(panelOf(page).locator('.item-label'), 'the reroute item follows Reject a fix').toHaveText([ITEMS['rejectFix']!.label, ITEMS['reroute']!.label]);
  await expect(itemOf(page, 'reroute').locator('.look-for')).toHaveText(ITEMS['reroute']!.lookFor);
  const control = controlOf(page, 'reroute');
  await control.click();
  await expect.poll(() => bodies.length, { message: 'the prompt was posted' }).toBe(1);
  expect(bodies[0]!.text).toBe(REROUTE);
  expect(bodies[0]!.fromGuide, 'as the user\'s own message').toBe(false);
  await expect(control, 'while its turn is in flight the control is aria-disabled').toHaveAttribute('aria-disabled', 'true');
  await control.click({ force: true });
  await page.waitForTimeout(500);
  expect(bodies, 'and a second press sends nothing').toHaveLength(1);
});

/** K9c (Story 23.5, AC15): the partner warning item sends its prompt once as the user's own message, and sends nothing while a turn is in flight. */
test('K9c: the partner warning item sends its prompt once as the user\'s own message, and sends nothing while its turn is in flight', async ({ page }) => {
  const bodies: Array<{ clientId: string; text: string; fromGuide: boolean }> = [];
  await page.route(`**${MESSAGES}`, async (route: Route) => {
    const body = route.request().postDataJSON() as { clientId: string; text: string; fromGuide: boolean };
    bodies.push(body);
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  });
  await openWith(page, finished(['rejectFix', 'reroute', 'partnerWarning']));
  await expect(panelOf(page).locator('.item-label'), 'the partner warning item follows the reroute item').toHaveText([ITEMS['rejectFix']!.label, ITEMS['reroute']!.label, ITEMS['partnerWarning']!.label]);
  await expect(itemOf(page, 'partnerWarning').locator('.look-for')).toHaveText(ITEMS['partnerWarning']!.lookFor);
  const control = controlOf(page, 'partnerWarning');
  await control.click();
  await expect.poll(() => bodies.length, { message: 'the prompt was posted' }).toBe(1);
  expect(bodies[0]!.text).toBe(PARTNER);
  expect(bodies[0]!.fromGuide, 'as the user\'s own message').toBe(false);
  await expect(control, 'while its turn is in flight the control is aria-disabled').toHaveAttribute('aria-disabled', 'true');
  await control.click({ force: true });
  await page.waitForTimeout(500);
  expect(bodies, 'and a second press sends nothing').toHaveLength(1);
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
  // The stack's own banner takes height, and a viewport that leaves under 680px after it starts the panel closed: this case is about the open one.
  await page.setViewportSize({ width: 1280, height: 900 });
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

/**
 * The real finish: the guide's `run` is the run's total, as the demo path's finish carries it, so the finish shows its "This run: ..."
 * line. K16, K17, K19 and K20 route it, because the line is part of the finish's height.
 */
const RUN = { decisions: 2, tokens: 9850, costUSD: 0.0041, models: ['Claude Haiku 5.5'] };
const RUN_TOTAL = 'This run: 2 decisions \u00B7 9,850 tokens \u00B7 $0.0041 on Claude Haiku 5.5.';

/** Opens the routed real finish (the band ids, Break the feed active, the run total) and checks that the run total is on the page. */
async function openRealFinish(page: Page, banner = false): Promise<void> {
  await openWith(page, finished(BAND_IDS, { breakFeed: { active: true }, run: RUN }), undefined, false, banner);
  await expect(page.locator('app-demo-guide .finish .run-total'), 'the finish carries the run total').toHaveText(RUN_TOTAL);
}

/** The height of the banners above the guide, as the page has it now. */
const bannersOf = (page: Page): Promise<number> => page.locator('.banner-slot').evaluate((slot) => (slot as HTMLElement).offsetHeight);

/** How far the page scrolls sideways. */
const sidewaysOf = (page: Page): Promise<number> => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

/** The height left after the banners is under 680px: the compact band, where the panel starts closed in the finish. */
async function compactOf(page: Page): Promise<boolean> {
  return (await page.evaluate(() => window.innerHeight)) - (await bannersOf(page)) < 680;
}

/**
 * Opens the panel with the link when the finish started it closed; asserts the state each way. With `edge` set (a size just over the
 * compact band's edge, where the page's fonts decide whether the panel fits) a panel that the finish started closed because the room is
 * too small for it even at its shortest window is left closed with the link saying so, and the answer is false: the caller then holds the
 * chat to its floor with the panel closed.
 */
async function openPanel(page: Page, compact: boolean, edge = false): Promise<boolean> {
  if (compact) {
    await expect(panelOf(page), 'the compact band starts the panel closed').toHaveCount(0);
    await expect(linkOf(page), 'and the link says so').toHaveAttribute('aria-expanded', 'false');
    await linkOf(page).click();
  } else if (edge) {
    await settledChat(page);
    if ((await panelOf(page).count()) === 0) {
      await expect(linkOf(page), 'the panel the room cannot hold starts closed, and the link says so').toHaveAttribute('aria-expanded', 'false');
      return false;
    }
  }
  await expect(panelOf(page), 'the panel is open').toBeVisible();
  await expect(linkOf(page), 'and the link says so').toHaveAttribute('aria-expanded', 'true');
  return true;
}

/**
 * Holds a size whose panel started closed for lack of room to the chat's floor and to a page that does not scroll as a whole, and shows
 * that the room really is too small: the link opens the panel at its least window and the chat is then under its floor.
 */
async function expectClosedHolds(page: Page, at: string, floor: number): Promise<void> {
  const room = await settledChat(page);
  test.info().annotations.push({ type: 'squeezed', description: `${at} the panel started closed: chat=${room.chat} page scroll=${room.page}` });
  console.log(`squeezed ${at} chat=${room.chat} page scroll=${room.page}`);
  expect(room.chat, `${at}: the chat's list keeps its floor with the panel closed`).toBeGreaterThanOrEqual(floor);
  expect(room.page, `${at}: and the page does not scroll as a whole`).toBeLessThanOrEqual(1);
  // A closed start above the band is owed only where the room cannot hold the panel: opened by the link, its window is at its least and
  // the chat is still under its floor.
  await linkOf(page).click();
  await expect(panelOf(page), `${at}: the link opens the panel`).toBeVisible();
  const opened = await settledRoom(page);
  expect(
    opened.window <= opened.need + 1 && opened.chat < floor,
    `${at}: it started closed only because even its least window leaves the chat under its floor (window=${opened.window} need=${opened.need} chat=${opened.chat})`,
  ).toBe(true);
}

/**
 * What K16 and K17 measure: the least visible heights, the page's scroll, and the panel's window, columns, how far it reaches past the
 * page's width, how far its content reaches past its own width, how many of its texts are cut short, and how far it falls short of its
 * container's content width.
 */
interface Room {
  chat: number;
  page: number;
  window: number;
  holds: number;
  need: number;
  columns: number[];
  width: number;
  overflowX: number;
  sideways: number;
  clipped: number;
  overflowY: string;
  maxHeight: string;
  gap: number;
  marginTop: number;
  short: number;
}

const measureRoom = (page: Page): Promise<Room> =>
  page.evaluate(() => {
    const group = document.querySelector<HTMLElement>('app-more-to-try .group')!;
    const style = getComputedStyle(group);
    const lists = Array.from(group.querySelectorAll('ul.items')).map((list) => Array.from(list.querySelectorAll('li')).map((item) => Math.round(item.getBoundingClientRect().top)));
    return {
      chat: document.querySelector('app-chat-panel .list')!.getBoundingClientRect().height,
      page: document.scrollingElement!.scrollHeight - document.scrollingElement!.clientHeight,
      window: group.clientHeight,
      holds: group.scrollHeight - group.clientHeight,
      need:
        group.querySelector('.group-label')!.getBoundingClientRect().height +
        (parseFloat(style.rowGap) || 0) +
        group.querySelector('.button')!.getBoundingClientRect().height,
      columns: lists.map((tops) => tops.filter((top) => top === tops[0]).length),
      width: group.clientWidth,
      overflowX: Math.max(0, group.getBoundingClientRect().right, ...Array.from(group.querySelectorAll('li')).map((item) => item.getBoundingClientRect().right)) - document.documentElement.clientWidth,
      sideways: group.scrollWidth - group.clientWidth,
      clipped: Array.from(group.querySelectorAll<HTMLElement>('.set-heading, .item-label, .look-for')).filter(
        (text) => text.scrollHeight > text.clientHeight + 1 || text.scrollWidth > text.clientWidth + 1,
      ).length,
      overflowY: style.overflowY,
      maxHeight: style.maxHeight,
      gap: parseFloat(style.rowGap) || 0,
      marginTop: parseFloat(getComputedStyle(document.querySelector('app-more-to-try')!).marginTop) || 0,
      short: (() => {
        const host = document.querySelector<HTMLElement>('app-more-to-try')!;
        const parent = getComputedStyle(host.parentElement!);
        const span = host.parentElement!.clientWidth - (parseFloat(parent.paddingLeft) || 0) - (parseFloat(parent.paddingRight) || 0);
        return span - host.getBoundingClientRect().width;
      })(),
    };
  });

/** The layout once two samples in a row agree, so that no later reflow can change what the case asserts. */
async function settledRoom(page: Page): Promise<Room> {
  await page.evaluate(() => document.fonts.ready.then(() => true));
  let last = '';
  let room: Room | undefined;
  await expect
    .poll(
      async () => {
        room = await measureRoom(page);
        const now = JSON.stringify(room);
        const same = now === last;
        last = now;
        return same;
      },
      { message: 'the layout has settled' },
    )
    .toBe(true);
  return room!;
}

/**
 * The sizes at which the open panel must leave the chat a usable height: `chat` is the least visible height of `app-chat-panel .list`,
 * and `window` the least height of the panel's own window where the viewport leaves room for more than its minimum (a panel bound that is
 * tighter than the room needs fails there; 0 where the window is at its minimum, which the window-minimum check covers). The framed sizes (1024px and wider) fill the viewport, so the page itself never scrolls and the panel is a scroller of its own; the
 * stacked column scrolls as a page by design and the panel grows with its items.
 */
const ROOM = [
  { band: 'wide', width: 1440, height: 900, chat: 160, window: 100, framed: true },
  { band: 'reference', width: 1280, height: 800, chat: 160, window: 100, framed: true },
  { band: 'drawer', width: 1024, height: 768, chat: 160, window: 70, framed: true },
  { band: 'drawer', width: 1100, height: 720, chat: 160, window: 0, framed: true },
  { band: 'compact height', width: 1280, height: 650, chat: 64, window: 57, framed: true },
  { band: 'compact height', width: 1280, height: 600, chat: 64, window: 0, framed: true },
  { band: 'stacked', width: 800, height: 720, chat: 1, window: 0, framed: false },
  { band: 'stacked, narrowest', width: 320, height: 700, chat: 1, window: 0, framed: false },
] as const;

/**
 * The sizes that only K16 measures (the finish with the panel open): the compact height band at drawer widths and at the widths around
 * it, where the finish takes the guide's whole width under row 1, and the sizes just over the band's edge. `chat` is the least visible
 * height of the chat's list, 64px in the compact band and 160px from 680px tall.
 */
const FINISH_ROOM = [
  { band: 'drawer, compact height', width: 1200, height: 600, chat: 64, window: 0, framed: true },
  { band: 'drawer, compact height', width: 1100, height: 650, chat: 64, window: 57, framed: true },
  { band: 'drawer, compact height', width: 1100, height: 600, chat: 64, window: 0, framed: true },
  { band: 'drawer, compact height', width: 1024, height: 679, chat: 64, window: 86, framed: true },
  { band: 'drawer, compact height', width: 1024, height: 650, chat: 64, window: 57, framed: true },
  { band: 'drawer, compact height', width: 1024, height: 600, chat: 64, window: 0, framed: true },
  { band: 'drawer, at the compact band\'s edge', width: 1024, height: 680, chat: 160, window: 0, framed: true },
  { band: 'drawer, at the compact band\'s edge', width: 1100, height: 680, chat: 160, window: 0, framed: true },
  { band: 'reference, at the compact band\'s edge', width: 1280, height: 680, chat: 160, window: 0, framed: true },
  { band: 'wide, at the compact band\'s edge', width: 1440, height: 680, chat: 160, window: 0, framed: true },
  { band: 'drawer, just over the compact band', width: 1024, height: 700, chat: 160, window: 0, framed: true },
  { band: 'drawer, just over the compact band', width: 1024, height: 704, chat: 160, window: 0, framed: true },
  { band: 'drawer, just over the compact band', width: 1100, height: 690, chat: 160, window: 0, framed: true },
  { band: 'reference, just over the compact band', width: 1280, height: 684, chat: 160, window: 0, framed: true },
  { band: 'compact height', width: 1280, height: 590, chat: 64, window: 0, framed: true },
  { band: 'stacked, narrowest with a classic scrollbar', width: 305, height: 700, chat: 1, window: 0, framed: false },
] as const;

/** Asserts what the panel owes at a size, for K16 and K17: the chat, the page, the window, the columns and the stacked contract. */
function expectRoom(room: Room, size: { width: number; height: number; chat: number; window: number; framed: boolean }): void {
  const at = `${size.width}x${size.height} (${JSON.stringify(room)})`;
  expect(room.chat, `${at}: the chat's list keeps its height`).toBeGreaterThanOrEqual(size.chat);
  expect(room.overflowX, `${at}: the panel stays within the page's width`).toBeLessThanOrEqual(1);
  expect(room.sideways, `${at}: nothing in the panel reaches past its own width`).toBeLessThanOrEqual(1);
  expect(room.clipped, `${at}: no heading, label or look-for line is cut short`).toBe(0);
  expect(room.short, `${at}: the panel takes its container's whole width`).toBeLessThanOrEqual(1);
  if (size.framed) {
    expect(room.page, `${at}: the page does not scroll as a whole`).toBeLessThanOrEqual(1);
    expect(room.overflowY, `${at}: the panel scrolls on its own`).toBe('auto');
    expect(room.maxHeight, `${at}: and is bounded`).not.toBe('none');
    expect(room.gap, `${at}: with no gap under its label`).toBe(0);
    expect(room.marginTop, `${at}: and no margin above it`).toBe(0);
    expect(room.window, `${at}: its window shows the label line, any gap under it and one complete control`).toBeGreaterThanOrEqual(room.need - 1);
    if (size.window > 0) {
      expect(room.window, `${at}: and uses the room the viewport leaves it`).toBeGreaterThanOrEqual(size.window);
    }
    expect(room.holds <= 1 || room.chat < size.chat + 4, `${at}: its window takes all the room above the chat's floor, unless it shows everything`).toBe(true);
    const fit = Math.max(1, Math.floor((room.width - 8 + 16) / (320 + 16)));
    expect(room.columns, `${at}: the items of each list are in as many columns as fit, each at least 20rem wide`).toEqual(
      groupsOf(itemsFor(BAND_IDS)).map((set) => Math.min(set.items.length, fit)),
    );
  } else {
    expect(room.overflowY, `${at}: the stacked panel is no scroller of its own`).toBe('visible');
    expect(room.maxHeight, `${at}: and has no bound`).toBe('none');
    expect(room.marginTop, `${at}: and keeps its margin above`).toBeGreaterThan(0);
    expect(room.holds, `${at}: it grows with its items`).toBeLessThanOrEqual(1);
    expect(room.page, `${at}: and the page scrolls instead`).toBeGreaterThan(0);
  }
}

/**
 * Tab from the panel's own stop through the controls, in the order shown: each one that takes focus is wholly in view in the panel's window with its
 * focus ring (the control's box grown by the ring's offset and width, 4px), and the window has scrolled by the time the last one is reached.
 */
async function expectTabInView(page: Page, at: string): Promise<void> {
  await panelOf(page).focus();
  const scrolls = await panelOf(page).evaluate((node) => node.scrollHeight - node.clientHeight > 1);
  for (const id of shown(BAND_IDS)) {
    await page.keyboard.press('Tab');
    await expect(controlOf(page, id), `${at}: Tab reaches ${id}`).toBeFocused();
    const inView = await page.evaluate(() => {
      const node = document.querySelector<HTMLElement>('app-more-to-try .group')!;
      const group = node.getBoundingClientRect();
      const control = document.activeElement!.getBoundingClientRect();
      const top = group.top + node.clientTop;
      const left = group.left + node.clientLeft;
      const ring = 4;
      return {
        overlap: Math.min(group.bottom, control.bottom) - Math.max(group.top, control.top),
        height: control.height,
        ringOut: Math.max(top - (control.top - ring), control.bottom + ring - (top + node.clientHeight), left - (control.left - ring), control.right + ring - (left + node.clientWidth)),
      };
    });
    expect(inView.overlap, `${at}: ${id} is wholly in view in the panel`).toBeGreaterThanOrEqual(inView.height - 1);
    expect(inView.ringOut, `${at}: and so is its focus ring`).toBeLessThanOrEqual(1);
  }
  if (scrolls) {
    expect(await panelOf(page).evaluate((node) => node.scrollTop), `${at}: the panel scrolled to bring the last control into view`).toBeGreaterThan(0);
  }
}

for (const size of [...ROOM, ...FINISH_ROOM]) {
  const { band, width, height, chat } = size;
  /**
   * K16 (the panel's room): the routed finish with the band ids and no banner. The panel is open by default from 680px tall and starts
   * closed under it (the compact band), where the link opens it. The measurements are recorded as an annotation and one log line. The
   * panel is a Tab stop named "Other things to try" where it scrolls.
   */
  test(`K16: in the ${band} band (${width}x${height}) the open panel leaves the chat at least ${chat}px and the page does not scroll`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openRealFinish(page);
    if (!(await openPanel(page, height < 680, size.framed && height >= 680 && height < 760))) {
      await expectClosedHolds(page, `${width}x${height}`, chat);
      return;
    }
    if (size.framed) {
      await expect(panelOf(page), 'it is a Tab stop').toHaveAttribute('tabindex', '0');
    }
    const room = await settledRoom(page);
    const record = `${width}x${height} chat=${room.chat} window=${room.window} need=${room.need} columns=${room.columns} width=${room.width} page scroll=${room.page}`;
    test.info().annotations.push({ type: 'K16', description: record });
    console.log(`K16 ${record}`);
    expectRoom(room, size);
    if (size.framed) {
      await expectTabInView(page, `${width}x${height}`);
    }
  });
}

/**
 * The sizes at which the banner decides the band: with the no-model-key banner showing, the band starts as high as the banner is tall.
 * `edge` is 'under' for a viewport one pixel under 680px plus the banner (the compact band: the panel starts closed, the floor is 64px)
 * and 'at' for exactly 680px plus the banner (the panel starts open, the floor is 160px). The height is read from the page's banner.
 */
const BANNER_ROOM = [
  { width: 1280, edge: 'under' },
  { width: 1280, edge: 'at' },
  { width: 1024, edge: 'under' },
  { width: 1024, edge: 'at' },
  { width: 1440, edge: 'at' },
] as const;

for (const { width, edge } of BANNER_ROOM) {
  /** K16b: the band follows the height left after the banner; the floors hold with the banner showing. */
  test(`K16b: with the no-model-key banner shown, ${width}px wide, a viewport ${edge === 'under' ? 'one pixel under' : 'exactly at'} 680px plus the banner ${edge === 'under' ? 'starts the panel closed and' : 'starts it open and'} the chat keeps its floor`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await openRealFinish(page, true);
    const banner = await bannersOf(page);
    expect(banner, 'the banner takes height').toBeGreaterThan(0);
    const height = 680 + banner - (edge === 'under' ? 1 : 0);
    await page.setViewportSize({ width, height });
    await page.evaluate(() => document.fonts.ready.then(() => true));
    expect(await compactOf(page), 'the case set the viewport one pixel under or exactly at 680px plus the banner it measured').toBe(edge === 'under');
    const floor = edge === 'under' ? 64 : 160;
    if (!(await openPanel(page, edge === 'under', edge === 'at'))) {
      await expectClosedHolds(page, `${width}x${height} banner ${banner}`, floor);
      return;
    }
    const room = await settledRoom(page);
    const record = `${width}x${height} banner=${banner} chat=${room.chat} window=${room.window} page scroll=${room.page}`;
    test.info().annotations.push({ type: 'K16b', description: record });
    console.log(`K16b ${record}`);
    expectRoom(room, { width, height, chat: floor, window: 0, framed: true });
    await expectTabInView(page, `${width}x${height} with the banner`);
  });
}

/** K17: the link opens the panel before the finish (the prompt bar's branch); the same room is owed at every framed size. */
for (const size of ROOM.filter((one) => one.framed)) {
  const { width, height, chat } = size;
  test(`K17: with the link opening the panel before the finish (${width}x${height}) the chat keeps at least ${chat}px and the page does not scroll`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openWith(page, guide(BAND_IDS, { run: RUN }));
    await linkOf(page).click();
    await expect(panelOf(page), 'the link opens the panel').toBeVisible();
    const room = await settledRoom(page);
    const record = `${width}x${height} prompt branch chat=${room.chat} window=${room.window} need=${room.need} columns=${room.columns} width=${room.width} page scroll=${room.page}`;
    test.info().annotations.push({ type: 'K17', description: record });
    console.log(`K17 ${record}`);
    expectRoom(room, size);
    await expectTabInView(page, `${width}x${height} prompt branch`);
  });
}

/** K18: the panel's scrolling group holds focus when the finish leaves; focus goes to the box, as for a control, and not to the body. */
test('K18: a focused panel group hands focus to the box when the finish leaves', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await blockLiveSocket(page);
  const push = await guidePushes(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = finished(FOUR, { breakFeed: { active: true } });
  });
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await panelOf(page).focus();
  await expect(panelOf(page), 'the group holds focus').toBeFocused();
  await push(guide(FOUR, { step: 3, breakFeed: { active: true } }));
  await expect(breakButton(page), 'focus went to Break the feed when the finish left').toBeFocused();
});

/** The chat's list height and the page's scroll once two samples in a row agree, for the finish with its panel closed. */
async function settledChat(page: Page): Promise<{ chat: number; page: number }> {
  await page.evaluate(() => document.fonts.ready.then(() => true));
  let last = '';
  let seen: { chat: number; page: number } | undefined;
  await expect
    .poll(
      async () => {
        seen = await page.evaluate(() => ({
          chat: document.querySelector('app-chat-panel .list')!.getBoundingClientRect().height,
          page: document.scrollingElement!.scrollHeight - document.scrollingElement!.clientHeight,
        }));
        const now = JSON.stringify(seen);
        const same = now === last;
        last = now;
        return same;
      },
      { message: 'the layout has settled' },
    )
    .toBe(true);
  return seen!;
}

/**
 * K19: in the compact height band the finish starts with its panel closed (the Planner, 2026-11-07), and then it leaves the chat at least
 * 64px and the page does not scroll, at drawer widths too, where the finish takes the guide's whole width under row 1 and Run again sits
 * beside the Try it yourself row. The link opens the panel, and the room case K16 measures it.
 */
for (const [width, height] of [
  [1024, 600],
  [1100, 650],
  [1024, 679],
  [1280, 590],
  [1280, 600],
] as const) {
  test(`K19: the compact band starts the finish with the panel closed, and the chat keeps at least 64px with no page scroll (${width}x${height})`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openRealFinish(page);
    await expect(panelOf(page), 'the panel starts closed').toHaveCount(0);
    await expect(linkOf(page), 'and the link says so').toHaveAttribute('aria-expanded', 'false');
    const room = await settledChat(page);
    test.info().annotations.push({ type: 'K19', description: `${width}x${height} chat=${room.chat} page scroll=${room.page}` });
    expect(room.chat, `${width}x${height}: the chat's list keeps its height`).toBeGreaterThanOrEqual(64);
    expect(room.page, `${width}x${height}: the page does not scroll as a whole`).toBeLessThanOrEqual(1);
  });
}

/** K19b: from 680px tall (no banner) the finish starts with the panel open, and the link closes it. */
test('K19b: at 680px tall the finish starts with the panel open, aria-expanded true, and the link closes it', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 680 });
  await openRealFinish(page);
  await expect(panelOf(page), 'the panel starts open').toBeVisible();
  await expect(linkOf(page)).toHaveAttribute('aria-expanded', 'true');
  await linkOf(page).click();
  await expect(panelOf(page), 'the link closes it').toHaveCount(0);
  await expect(linkOf(page)).toHaveAttribute('aria-expanded', 'false');
});

/**
 * K20: the finish's own layout where the page fills the viewport. Row 1 is above the finish, starts at its left edge and takes one line
 * (it leaves out "About 2 minutes" once the guide is finished), at every size; from 680px tall, where row 1 spans the guide, More to try
 * and Hide guide stay at its right end; from 1024 to 1279px wide Run again is at the end of the Try it yourself row's last line, and elsewhere it is below the row.
 */
for (const [width, height] of [
  [1024, 700],
  [1100, 600],
  [1200, 650],
  [1280, 600],
  [1280, 684],
  [1280, 800],
  [1440, 900],
] as const) {
  const drawer = width < 1280;
  test(`K20: the finish has row 1 above it and Run again ${drawer ? 'beside' : 'below'} Try it yourself (${width}x${height})`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openRealFinish(page);
    await expect(guideRegion(page).locator('.finish'), 'the finish shows').toBeVisible();
    await page.evaluate(() => document.fonts.ready.then(() => true));
    const at = `${width}x${height}`;
    const read = () =>
      page.evaluate(() => {
        const box = (selector: string) => {
          const rect = document.querySelector(selector)!.getBoundingClientRect();
          return { top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right };
        };
        return {
          row1: box('app-demo-guide .row1'),
          hide: box('app-demo-guide .row1 [data-guide-focus="hide"]'),
          finish: box('app-demo-guide .finish'),
          tryIt: box('app-demo-guide app-try-it-row'),
          run: box('app-demo-guide .run-again'),
        };
      });
    let boxes = await read();
    let last = '';
    await expect
      .poll(
        async () => {
          boxes = await read();
          const now = JSON.stringify(boxes);
          const same = now === last;
          last = now;
          return same;
        },
        { message: 'the layout has settled' },
      )
      .toBe(true);
    await expect(guideRegion(page).locator('.row1 .duration'), `${at}: row 1 holds the duration text`).toHaveCount(1);
    await expect(guideRegion(page).locator('.row1 .duration'), `${at}: "About 2 minutes" is left out of the finish`).toBeHidden();
    expect(boxes.row1.bottom - boxes.row1.top, `${at}: row 1 takes one line`).toBeLessThanOrEqual(40);
    if (height >= 680) {
      expect(boxes.hide.right, `${at}: More to try and Hide guide stay at row 1's right end`).toBeGreaterThanOrEqual(boxes.row1.right - 1);
    }
    expect(boxes.row1.bottom, `${at}: row 1 is above the finish`).toBeLessThanOrEqual(boxes.finish.top + 1);
    expect(Math.abs(boxes.row1.left - boxes.finish.left), `${at}: and starts at its left edge`).toBeLessThanOrEqual(1);
    if (drawer) {
      expect(boxes.run.left, `${at}: Run again is to the right of the Try it yourself row`).toBeGreaterThanOrEqual(boxes.tryIt.right - 1);
      expect(boxes.run.bottom, `${at}: and on its last line`).toBeLessThanOrEqual(boxes.tryIt.bottom + 1);
      expect(boxes.run.top, `${at}: and not above it`).toBeGreaterThanOrEqual(boxes.tryIt.top);
      expect(boxes.run.bottom, `${at}: and level with its bottom edge`).toBeGreaterThanOrEqual(boxes.tryIt.bottom - 2);
    } else {
      expect(boxes.run.top, `${at}: Run again is below the Try it yourself row`).toBeGreaterThanOrEqual(boxes.tryIt.bottom - 1);
    }
  });
}

/**
 * K21: the status banner "OcuTalon has no model key..." sits above the guide on a stack without a key. Most room cases route it off; this
 * one routes it on and asks what must hold whatever is above the guide. Before the user opens the panel (the finish starts it closed in
 * the compact band, open above it) the framed page does not scroll and the chat keeps its floor (64px in the band, 160px above it).
 * After the user opens it (More to try) the chat still keeps its floor and the page does not scroll sideways; in the compact band the
 * page may scroll vertically to keep it (the Planner, 2026-11-07). With the banner shown both framed rows here are in the compact band
 * (700px less the banner is under 680px), so the no-page-scroll check after the press, kept for a framed row above the band, does not run.
 */
for (const [width, height] of [
  [1280, 600],
  [1280, 700],
  [320, 700],
] as const) {
  test(`K21: with the no-model-key banner shown the open panel leaves no sideways scroll and the chat its floor (${width}x${height})`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openRealFinish(page, true);
    const compact = await compactOf(page);
    const floor = compact ? 64 : 160;
    const start = await settledChat(page);
    if (width >= 1024) {
      expect(start.chat, `${width}x${height}: the chat's list keeps its floor with the panel as the finish starts it`).toBeGreaterThanOrEqual(floor);
      expect(start.page, `${width}x${height}: the framed page does not scroll as the finish starts`).toBeLessThanOrEqual(1);
    }
    expect(await sidewaysOf(page), `${width}x${height}: the page does not scroll sideways as the finish starts`).toBeLessThanOrEqual(0);
    await openPanel(page, compact);
    const room = await settledRoom(page);
    const sideways = await sidewaysOf(page);
    test.info().annotations.push({ type: 'K21', description: `${width}x${height} chat=${room.chat} page scroll=${room.page} sideways=${sideways}` });
    console.log(`K21 ${width}x${height} before: chat=${start.chat} page scroll=${start.page}; after: chat=${room.chat} window=${room.window} page scroll=${room.page} sideways=${sideways}`);
    expect(sideways, `${width}x${height}: the page does not scroll sideways`).toBeLessThanOrEqual(0);
    expect(room.sideways, `${width}x${height}: nothing in the panel reaches past its own width`).toBeLessThanOrEqual(1);
    expect(room.overflowX, `${width}x${height}: the panel stays within the page's width`).toBeLessThanOrEqual(1);
    if (width >= 1024) {
      expect(room.chat, `${width}x${height}: the chat's list keeps its floor with the panel the user opened (chat=${room.chat} window=${room.window} need=${room.need})`).toBeGreaterThanOrEqual(floor);
      if (!compact) {
        expect(room.page, `${width}x${height}: the framed page does not scroll as a whole`).toBeLessThanOrEqual(1);
      }
    } else {
      expect(room.chat, `${width}x${height}: the chat's list keeps some height`).toBeGreaterThan(0);
    }
  });
}

/**
 * K21b: the squeeze made by the case itself: at 1280x600 with the no-model-key banner the case adds height to the guide so that the chat
 * keeps its floor with the panel closed but falls under it by about half of the panel's shortest window once the panel is open (where the
 * machine's closed chat is already near the floor, the open panel squeezes it all the same). The panel the user opens is at its shortest window, the chat still keeps its 64px,
 * and the page scrolls vertically to keep it (the Planner, 2026-11-07), never sideways.
 */
test('K21b: with the room squeezed by the case, the panel the user opens leaves the chat 64px and the page scrolls vertically, never sideways', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 600 });
  await openRealFinish(page, true);
  expect(await compactOf(page), 'the banner puts 1280x600 in the compact band').toBe(true);
  await expect(panelOf(page), 'the compact band starts the panel closed').toHaveCount(0);
  const closed = await settledChat(page);
  // The panel's shortest window is about 66px: leave the closed chat 33px above the floor, so the open panel takes it 33px under.
  const extra = Math.max(0, Math.floor(closed.chat - 64 - 33));
  await page.addStyleTag({ content: `app-demo-guide .guide { padding-bottom: ${extra}px !important; }` });
  const squeezed = await settledChat(page);
  expect(squeezed.chat, 'the case leaves the chat its floor with the panel closed').toBeGreaterThanOrEqual(64);
  expect(squeezed.page, 'and the framed page does not scroll with the panel closed').toBeLessThanOrEqual(1);
  await openPanel(page, true);
  const room = await settledRoom(page);
  const sideways = await sidewaysOf(page);
  test.info().annotations.push({ type: 'K21b', description: `closed chat=${closed.chat} extra=${extra} opened chat=${room.chat} window=${room.window} need=${room.need} page scroll=${room.page} sideways=${sideways}` });
  expect(room.window, 'the panel the user opened is at its shortest window').toBeLessThanOrEqual(room.need + 1);
  expect(room.chat, 'the chat keeps its 64px floor').toBeGreaterThanOrEqual(64);
  expect(room.page, 'the page scrolls vertically to keep it').toBeGreaterThan(0);
  expect(sideways, 'and never sideways').toBeLessThanOrEqual(0);
  expect(room.overflowX, 'the panel stays within the page\'s width').toBeLessThanOrEqual(1);
  expect(await listMinHeightOf(page), 'the chat list holds the floor as a min-height while the panel is open').toBe('64px');
  await linkOf(page).click();
  await expect(panelOf(page), 'the link closes the panel').toHaveCount(0);
  expect(await listMinHeightOf(page), 'the panel going releases the chat list\'s min-height').toBe('');
  await linkOf(page).click();
  await expect(panelOf(page), 'the link opens the panel again').toBeVisible();
  await expect.poll(() => listMinHeightOf(page), { message: 'the squeeze holds the floor again' }).toBe('64px');
  await page.setViewportSize({ width: 1280, height: 900 });
  await expect(panelOf(page), 'the panel the user opened stays open as the band is left').toBeVisible();
  await expect.poll(() => listMinHeightOf(page), { message: 'leaving the compact band releases the chat list\'s min-height' }).toBe('');
});

/** The chat list's inline min-height, which the room keeper sets to the compact floor while the squeeze holds and clears after. */
async function listMinHeightOf(page: Page): Promise<string> {
  return page.evaluate(() => (document.querySelector('app-chat-panel .list') as HTMLElement | null)?.style.minHeight ?? 'missing');
}

/**
 * K22: nothing of the guide widens the page at the narrow widths (no sideways scroll at 320px wide at any height), in the compact height band
 * (360 to 679px) and above it (700 and 900px): row 1
 * with the "More to try" link, the prompt bar's Send button and the finish. A viewport of 305px is the narrowest page (320px less a
 * classic scrollbar). The guide at step 1 is measured closed and with the link's panel open; the finish with its panel open (the link opens it in the compact band).
 */
for (const [width, height] of [
  [320, 360],
  [305, 360],
  [480, 360],
  [320, 500],
  [320, 679],
  [320, 700],
  [320, 900],
  [305, 700],
] as const) {
  for (const view of ['step 1', 'finish'] as const) {
    test(`K22: the guide at ${view} does not widen the page (${width}x${height})`, async ({ page }) => {
      await page.setViewportSize({ width, height });
      const sideways = (): Promise<number> => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      if (view === 'finish') {
        await openRealFinish(page);
      } else {
        await openWith(page, guide(FOUR));
      }
      await page.evaluate(() => document.fonts.ready.then(() => true));
      await expect(guideRegion(page).getByRole('button', { name: 'Hide guide', exact: true }), 'row 1 shows its last control').toBeVisible();
      expect(await sideways(), `${width}x${height} ${view}: the page does not scroll sideways`).toBeLessThanOrEqual(0);
      if (view === 'step 1') {
        await expect(guideRegion(page).getByRole('button', { name: 'Send', exact: true }), 'the prompt bar shows its Send').toBeVisible();
        expect(await sideways(), `${width}x${height} step 1: the page does not scroll sideways`).toBeLessThanOrEqual(0);
        await linkOf(page).click();
      }
      await openPanel(page, view === 'finish' && height < 680);
      const room = await settledRoom(page);
      expect(await sideways(), `${width}x${height} ${view}, panel open: the page does not scroll sideways`).toBeLessThanOrEqual(0);
      expect(room.sideways, `${width}x${height} ${view}: nothing in the panel reaches past its own width`).toBeLessThanOrEqual(1);
      expect(room.overflowX, `${width}x${height} ${view}: the panel stays within the page's width`).toBeLessThanOrEqual(1);
    });
  }
}

/**
 * A stylesheet that makes the page's text wider than the fonts the project ships: a wide family where the machine has one and letter and
 * word spacing everywhere, so that it widens the text on a machine with no such family. The layout must not depend on the metrics of the
 * machine that measured it (the CI runner's Linux fonts are wider than a developer machine's).
 */
const WIDE_TEXT = '*, *::before, *::after { font-family: Verdana, "DejaVu Sans", Geneva, sans-serif !important; letter-spacing: 0.04em !important; word-spacing: 0.1em !important; }';

/**
 * K23: the layout holds with wider font metrics. With the wide text applied, at 1280x680, 1280x600, 1024x680 and 320x700 (and with the
 * no-model-key banner at 1280 wide, one pixel under and at the band's edge): the finish's panel is open from the band's edge up (closed
 * instead where the wider text leaves no room for it even at its shortest window) and closed under it; the chat keeps its floor (64px in
 * the compact band, 160px from the edge) with the panel as the page starts it, and in the compact band also with the panel opened by the
 * link (the page may then scroll vertically to keep it, the Planner, 2026-11-07); from the edge up a panel that started closed is only
 * opened by the link; the framed page does not scroll as a whole except with the panel opened in the compact band, and no page scrolls sideways.
 */
for (const { width, height, banner } of [
  { width: 1280, height: 680, banner: undefined },
  { width: 1280, height: 600, banner: undefined },
  { width: 1024, height: 680, banner: undefined },
  { width: 320, height: 700, banner: undefined },
  { width: 1280, height: 719, banner: 'under' },
  { width: 1280, height: 720, banner: 'at' },
] as const) {
  test(`K23: with wider font metrics${banner === undefined ? '' : ` and the banner (${banner})`} the chat keeps its floor, the page does not scroll and nothing widens it (${width}x${height})`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openRealFinish(page, banner !== undefined);
    if (banner !== undefined) {
      const edge = 680 + (await bannersOf(page)) - (banner === 'under' ? 1 : 0);
      await page.setViewportSize({ width, height: edge });
    }
    const measure = (): Promise<{ chat: number; page: number; sideways: number }> =>
      page.evaluate(() => ({
        chat: document.querySelector('app-chat-panel .list')!.getBoundingClientRect().height,
        page: document.scrollingElement!.scrollHeight - document.scrollingElement!.clientHeight,
        sideways: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      }));
    const linkWidth = (): Promise<number> => linkOf(page).evaluate((node) => node.getBoundingClientRect().width);
    const before = await linkWidth();
    await page.addStyleTag({ content: WIDE_TEXT });
    await page.evaluate(() => document.fonts.ready.then(() => true));
    await expect.poll(linkWidth, { message: 'the text got wider' }).toBeGreaterThan(before * 1.05);
    if (banner !== undefined) {
      // The wider text may wrap the banner: the edge is the band's edge for the banner as the page has it now.
      await page.setViewportSize({ width, height: 680 + (await bannersOf(page)) - (banner === 'under' ? 1 : 0) });
      await page.evaluate(() => document.fonts.ready.then(() => true));
    }
    const at = `${width}x${height}${banner === undefined ? '' : ` banner ${banner}`}`;
    const compact = await compactOf(page);
    const floor = compact ? 64 : 160;
    const framed = width >= 1024;
    const expectHolds = async (state: string, opened = false): Promise<void> => {
      if (opened && framed) {
        // A panel the user opened (compact band only): the chat keeps its floor and the page may scroll vertically to keep it, never sideways.
        const room = await settledRoom(page);
        const sideways = (await measure()).sideways;
        test.info().annotations.push({ type: 'K23', description: `${at} ${state} chat=${room.chat} window=${room.window} page scroll=${room.page} sideways=${sideways}` });
        console.log(`K23 ${at} ${state} chat=${room.chat} window=${room.window} page scroll=${room.page} sideways=${sideways}`);
        expect(sideways, `${at} ${state}: the page does not scroll sideways`).toBeLessThanOrEqual(0);
        expect(room.chat, `${at} ${state}: the chat's list keeps its floor (chat=${room.chat} window=${room.window} need=${room.need})`).toBeGreaterThanOrEqual(floor);
        return;
      }
      if (framed) {
        await expect.poll(async () => (await measure()).chat, { message: `${at} ${state}: the chat's list reaches its floor` }).toBeGreaterThanOrEqual(floor);
      }
      const room = await settledChat(page);
      const seen = await measure();
      test.info().annotations.push({ type: 'K23', description: `${at} ${state} chat=${room.chat} page scroll=${room.page} sideways=${seen.sideways}` });
      console.log(`K23 ${at} ${state} chat=${room.chat} page scroll=${room.page} sideways=${seen.sideways}`);
      expect(seen.sideways, `${at} ${state}: the page does not scroll sideways`).toBeLessThanOrEqual(0);
      if (framed) {
        expect(room.chat, `${at} ${state}: the chat's list keeps its floor`).toBeGreaterThanOrEqual(floor);
        expect(room.page, `${at} ${state}: the page does not scroll as a whole`).toBeLessThanOrEqual(1);
      } else {
        expect(room.chat, `${at} ${state}: the chat's list keeps some height`).toBeGreaterThan(0);
      }
    };
    if (compact) {
      await expectHolds('panel closed');
      await openPanel(page, true);
      await expectHolds('panel opened by the link', true);
    } else {
      // From the band's edge up the panel starts open; where the wider text leaves no room for it even at its shortest window it starts closed instead.
      await expectHolds('panel as the page starts it');
      if ((await panelOf(page).count()) === 0) {
        await expect(linkOf(page), 'the closed panel is the link\'s state').toHaveAttribute('aria-expanded', 'false');
        await linkOf(page).click();
      }
      await expect(panelOf(page), 'and the link opens it').toBeVisible();
    }
  });
}

/** The case's own squeeze: a panel window that cannot get shorter than 900px, so no bound leaves the chat's list its 160px floor. */
const SQUEEZE = 'app-more-to-try .group { min-height: 900px !important; }';

/** Waits until the panel is gone, asking the page to measure again (a resize) at each try: the page measures a frame after a change. */
async function expectSqueezed(page: Page, message: string): Promise<void> {
  await expect
    .poll(
      async () => {
        await page.evaluate(() => window.dispatchEvent(new Event('resize')));
        return panelOf(page).count();
      },
      { message },
    )
    .toBe(0);
}

/**
 * K24: the squeeze is ended by a taller viewport and by a new finish. The case makes the squeeze itself (it does not depend on the
 * fonts of the machine): the panel the finish opened closes, and stays closed after the squeeze is gone until the viewport's height
 * changes, which opens it; a second squeeze is ended by the next finish.
 */
test('K24: a panel the room cannot hold closes, and a taller viewport or a new finish lets it open again', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await blockLiveSocket(page);
  const push = await guidePushes(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = finished(FOUR, { breakFeed: { active: true } });
    snapshot['status'] = [];
  });
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(panelOf(page), 'the finish opens the panel where the room holds it').toBeVisible();
  const chatHeight = (): Promise<number> => page.evaluate(() => document.querySelector('app-chat-panel .list')!.getBoundingClientRect().height);

  const squeeze = await page.addStyleTag({ content: SQUEEZE });
  await expectSqueezed(page, 'the panel the room cannot hold closes');
  await expect(linkOf(page), 'and the link says so').toHaveAttribute('aria-expanded', 'false');
  await squeeze.evaluate((node) => (node as Element).remove());
  await expect.poll(chatHeight, { message: 'the chat has its room again' }).toBeGreaterThanOrEqual(160);
  await expect.soft(panelOf(page), 'the squeeze holds until the viewport or a new finish changes it').toHaveCount(0);
  await page.setViewportSize({ width: 1280, height: 900 });
  await expect.soft(panelOf(page), 'a viewport of another height lets the panel open by itself').toBeVisible();

  const again = await page.addStyleTag({ content: SQUEEZE });
  await expectSqueezed(page, 'a second squeeze closes it again');
  await again.evaluate((node) => (node as Element).remove());
  await expect.poll(chatHeight, { message: 'the chat has its room again' }).toBeGreaterThanOrEqual(160);
  await push(guide(FOUR, { step: 3, breakFeed: { active: true } }));
  await push(finished(FOUR, { breakFeed: { active: true } }));
  await expect.soft(panelOf(page), 'a new finish opens the panel again').toBeVisible();
});

/**
 * Signs the fixture user in with the guide that the case names, kept against the live polls (as openWith does for the README account), and waits for the loaded page.
 * The user's own session owns the incident that a case seeds, so the cards and messages that its Dismiss makes reach this page.
 */
async function openAs(page: Page, view: Record<string, unknown>): Promise<void> {
  const { user, password } = fixtureUser('NOTICE');
  await keepRoutedGuide(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = view;
    snapshot['status'] = [];
  });
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

/**
 * K25 (Story 23.6, AC 10): at the finish the first item's control, "Close the incident", presses the Dismiss of the newest resolved incident card. The incident
 * is the user's own, resolved, with its summary built when it closes (the rows of the incident are the fixture's): the card's chip says Closed, the chat holds a
 * summary card whose first line is the title line and the Simulated phone a message with the same title line, and the finish and the panel are still shown.
 */
test('K25: Close the incident at the finish dismisses the resolved incident, and its summary reaches the chat and the Simulated phone', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const { user } = fixtureUser('NOTICE');
  const production = `Zz.K25.${Date.now().toString(36)}`;
  const named = new RegExp(`^Incident summary: \\d+ .* failed in ${production.replace(/\./g, '\\.')}\\.$`);
  const incident = await seedIncident(user, { state: 'resolved', production });
  try {
    await openAs(page, finished([SUMMARY, ...FOUR]));
    const card = page.locator(`article[data-part="incident"][data-key="incident:${incident}"]`);
    await expect(card.locator('.chip'), 'the incident card says Resolved').toHaveText('Resolved');
    await expect(panelOf(page), 'the finish shows the panel').toBeVisible();
    await expect(guideRegion(page).locator('.finish-done'), 'and the finish').toBeVisible();
    await controlOf(page, SUMMARY).click();
    await expect(card.locator('.chip'), 'the card says Closed').toHaveText('Closed', { timeout: 20_000 });
    const noticeCard = page.locator('app-chat-panel app-notice-card .notice.summary').filter({ hasText: production });
    await expect(noticeCard, 'the chat holds the summary card').toHaveCount(1, { timeout: 20_000 });
    expect((await noticeCard.locator('.text').innerText()).split('\n')[0], 'whose first line is the title line').toMatch(named);
    const phone = page.getByRole('region', { name: 'Simulated devices' }).locator('app-simulated-phone');
    const message = phone.locator('.notification').filter({ hasText: production });
    await expect(message, 'the Simulated phone holds the summary message').toHaveCount(1, { timeout: 20_000 });
    expect((await message.locator('.text').innerText()).split('\n')[0], 'with the same title line').toMatch(named);
    await expect(message.getByRole('button'), 'and no button').toHaveCount(0);
    await expect(panelOf(page), 'the panel is still shown').toBeVisible();
    await expect(guideRegion(page).locator('.finish-done'), 'and the finish still holds').toBeVisible();
  } finally {
    await cleanFixtureRows([incident]);
  }
});

/**
 * K26 (Story 23.6, AC 16; the Planner's ruling 2): with no resolved incident card to close (already closed, or the guide not run), the first item's control
 * sends "Show me the incident summary" once, as the user's own message, and presses nothing else.
 */
test('K26: Close the incident with no resolved incident sends "Show me the incident summary" once', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const bodies: Array<{ clientId: string; text: string; fromGuide: boolean }> = [];
  await page.route(`**${MESSAGES}`, async (route: Route) => {
    const body = route.request().postDataJSON() as { clientId: string; text: string; fromGuide: boolean };
    bodies.push(body);
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  });
  await openAs(page, finished([SUMMARY, ...FOUR]));
  await expect(page.locator('article[data-part="incident"] .chip-resolved'), 'no incident card is resolved').toHaveCount(0);
  await controlOf(page, SUMMARY).click();
  await expect.poll(() => bodies.length, { message: 'the prompt was posted' }).toBe(1);
  await page.waitForTimeout(500);
  expect(bodies, 'exactly one POST').toHaveLength(1);
  expect(bodies[0]!.text).toBe(SUMMARY_PROMPT);
  expect(bodies[0]!.fromGuide, 'as the user\'s own message').toBe(false);
});

/**
 * K27 (routed finish, every id): the panel's level-4 headings are the ruled groups that have an item, in the ruled order, and the list
 * after each holds exactly the labels of the registry items that declare that group, in registry order. The label is no heading, and
 * no heading takes focus. The oracle is the ruled heading strings written out; membership comes from the registry's group fields.
 */
test('K27: the panel shows its items under the ruled group headings, each followed by its own list', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await openWith(page, finished(ALL));
  const panel = panelOf(page);
  await expect(panel).toBeVisible();
  const RULED_HEADINGS = ['Incidents and fixes', 'Memory and documents', 'Safety and settings', 'Usage and history'];
  const groupOf = (id: string): string | undefined => MORE_TO_TRY_ITEMS.find((item) => item.id === id)!.group;
  expect(ALL.filter((id) => !RULED_HEADINGS.includes(groupOf(id) ?? '')), 'every item declares a ruled group').toEqual([]);
  const expected = RULED_HEADINGS.map((group): [string, string[]] => [group, ALL.filter((id) => groupOf(id) === group)]).filter(([, ids]) => ids.length > 0);
  expect(MORE_TO_TRY_GROUPS, 'the page\'s constant is the ruled order').toEqual(RULED_HEADINGS);
  expect(groupOf('usage'), 'the usage item is in the fourth group').toBe(RULED_HEADINGS[3]);
  expect(groupOf('history'), 'the history item is in the fourth group too, after usage').toBe(RULED_HEADINGS[3]);
  expect(ALL.slice(-2), 'usage then history are the last two items').toEqual(['usage', 'history']);

  const headings = panel.getByRole('heading', { level: 4 });
  await expect(headings, 'the groups that have items, in order').toHaveText(expected.map(([group]) => group));
  await expect(panel.getByRole('heading'), 'and no other heading').toHaveCount(expected.length);
  await expect(panel.getByRole('heading', { name: 'Other things to try', exact: true }), 'the label is no heading').toHaveCount(0);
  await expect(panel.locator('p.group-label')).toHaveText('Other things to try');
  await expect(panel.locator('ul.items'), 'one list for each heading').toHaveCount(expected.length);
  for (const [at, [group, ids]] of expected.entries()) {
    const heading = headings.nth(at);
    await expect(heading, `${group}: no tabindex`).not.toHaveAttribute('tabindex', /.*/);
    await expect(heading.locator('xpath=following-sibling::ul[1]').locator('.item-label'), `${group}: its labels, in registry order`).toHaveText(ids.map((id) => ITEMS[id]!.label));
  }
  await expect(headings.last().locator('xpath=following-sibling::ul[1]'), 'the fourth heading holds the usage item').toContainText(ITEMS['usage']!.label);
  await expect(headings.last().locator('xpath=following-sibling::ul[1]').locator('.item-label'), 'then the history item').toHaveText([ITEMS['usage']!.label, ITEMS['history']!.label]);
  await expect(panel.locator('.item-label'), 'every item once').toHaveCount(ALL.length);
});
