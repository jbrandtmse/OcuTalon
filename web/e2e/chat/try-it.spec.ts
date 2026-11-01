import { expect, test, type Locator, type Page, type Request } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { pointKeys, restoreKeys } from '../support/devices';
import { composerOf, loadedAfter, mainOf, replyOf, settled } from '../support/floor';
import { changeSnapshot, holdPoll, MESSAGES } from '../support/api';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';

/**
 * Story 4.10, the "Try it yourself" row, in a real browser against a real stack with the CI mock. The rail user's session is held empty
 * by convention (rail/rail.spec.ts), so the real empty chat shows the row and a press goes through the page's ChatOutbox to the real
 * WebChatIn, Conversation, Decide, Chat and tools, and back over the live stream; the CI mock scripts the model (scenarios
 * B/try-it-*.json, one per chip):
 *   - Y1 (routed): the row shows in the empty chat and in the finish state, in their places and in order, and nowhere with the Demo view
 *     switch off or the install not in demo mode; nothing is sent;
 *   - Y2 (routed): while the message allowance is used up every chip is aria-disabled and described by the composer's reason, and a
 *     click or Enter sends nothing;
 *   - Y3: a click on chip 1 sends the exact text once, not from the guide; focus goes to the main region; the reply has its strip and
 *     trace link, and the turn decision has one tool step;
 *   - Y4: chip 2 by Space, in a session that watches nothing: the code-built check sentence and no all-clear wording;
 *   - Y5: chip 3 in a routed finish state: while the turn is in flight (the page's poll held) every chip is aria-disabled and an
 *     Enter on the focused chip sends nothing; once the reply lands the chips are enabled again;
 *   - Y6: chip 4 by Tab and Enter: a reply without a tool step;
 *   - Y7: chip 3 in a session with no incident: the tool result that the model received is the code-built "nothing in the last 24
 *     hours" answer, and the reply holds no all-clear wording.
 * The hooks are those of reminder/chat.spec.ts: beforeAll points the runners' keys at the CI mock; afterAll drops the AI sessions that the
 * turns saved, puts the keys back and waits until the runners have recorded them, because trace/links.spec.ts runs later and expects the
 * no-key reply; the rail user's session holds no turn before and after each case. The browser runs in UTC with the en-GB locale.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const LABEL = 'Try it yourself';
const PROMPTS = ['Which productions are running?', 'Is anything wrong right now?', 'What was that failure earlier?', 'What can you do?'] as const;
const REASON_ID = 'composer-allowance-reason';
const NOTHING_WATCHED = "I'm not watching any productions yet, so I can't say. Ask me to watch one.";
const TRACE_PAGE = '/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=';

/** How long a reply may take to show after the press: the turn, the live poll and the render. */
const REPLY_MS = 30_000;

/** The mark of the saved AI sessions before the first case (RunnerFixture.SessionMark), for the clean-up. */
let mark = '';

test.beforeAll(async () => {
  test.setTimeout(240_000);
  await pointKeys();
  const lines = await irisScript('Write !,"CHK|mark|",##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()');
  mark = chk(lines, 'mark') ?? '';
  expect(mark, 'the session mark of the saved AI sessions was read').toMatch(/^\d+$/);
});

test.afterAll(async () => {
  test.setTimeout(240_000);
  try {
    if (/^\d+$/.test(mark)) {
      const lines = await irisScript(`Write !,"CHK|dropped|",$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(${mark}))`);
      expect(chk(lines, 'dropped'), `the AI sessions of the turns are dropped (${lines.join(' ')})`).toBe('1');
    }
  } finally {
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
    }
  }
});

/** Removes the rail user's turns with what the product made for them, and returns how many turns the session holds after that. */
async function clearTurns(): Promise<string> {
  const { user } = fixtureUser('RAIL');
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(s.Ref)',
      'Write !,"CHK|left|",##class(OcuTalon.Data.Ownership).Turns(s.Ref,.sc).Count()',
    ].join('\n'),
  );
  return chk(lines, 'left') ?? `no answer (${lines.join(' ')})`;
}

test.beforeEach(async () => {
  expect(await clearTurns(), "the rail user's session holds no turn before the case").toBe('0');
});

test.afterEach(async () => {
  expect(await clearTurns(), "the rail user's session holds no turn after the case").toBe('0');
  // A later turn of the session continues the AI session that an earlier one saved, and would carry its tool results in its history: each case starts a new conversation.
  if (/^\d+$/.test(mark)) {
    const lines = await irisScript(`Write !,"CHK|dropped|",$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(${mark}))`);
    expect(chk(lines, 'dropped'), `the AI sessions of the case are dropped (${lines.join(' ')})`).toBe('1');
  }
});

/** Fails, naming what it found, unless the rail user's session has no turn, no watch and no incident. */
async function expectEmptySession(): Promise<void> {
  const { user } = fixtureUser('RAIL');
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Write !,"CHK|found|",##class(OcuTalon.Data.Ownership).Turns(s.Ref,.sc).Count(),"|",##class(OcuTalon.Data.Ownership).Checks(s.Ref,.sc).Count(),"|",##class(OcuTalon.Data.Ownership).RecentIncidents(s.Ref,100,.sc).Count()',
    ].join('\n'),
  );
  const [turns, watches, incidents] = (chk(lines, 'found') ?? '?|?|?').split('|');
  expect(`${turns} turns, ${watches} watches, ${incidents} incidents`, 'the rail user session starts with no turn, no watch and no incident').toBe('0 turns, 0 watches, 0 incidents');
}

/** The turn of a POSTed clientId as the product stored it. */
interface StoredTurn {
  state: string;
  fallback: string;
  catalogKey: string;
  reply: string;
  tools: string[];
}

/** Reads the turn of the clientId: its state, fallback reason, catalog key and reply, and the "label|status" of the tool steps of its turn decision. */
async function storedTurn(clientId: string): Promise<StoredTurn> {
  const { user } = fixtureUser('RAIL');
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      `Set t=##class(OcuTalon.Data.Ownership).TurnByClient(s.Ref,${quoted(clientId)},.sc)`,
      'If $IsObject(t) Write !,"CHK|turn|",t.State,"|",t.FallbackReason,"|",t.ReplyCatalogKey',
      'If $IsObject(t) Write !,"CHK|reply|",$Translate(t.ReplyText,$Char(13,10),"  ")',
      'If $IsObject(t) Set st=##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(t.TurnDecisionRef),out="",i=st.%GetIterator() While i.%GetNext(,.step) { If step.kind="tool" Set out=out_$Select(out="":"",1:";")_step.label_"|"_step.status }',
      'If $IsObject(t) Write !,"CHK|tools|",out',
    ].join('\n'),
  );
  const [state = '', fallback = '', catalogKey = ''] = (chk(lines, 'turn') ?? '').split('|');
  const tools = chk(lines, 'tools') ?? '';
  return { state, fallback, catalogKey, reply: chk(lines, 'reply') ?? '', tools: tools === '' ? [] : tools.split(';') };
}

/** Waits until the turn is done with the tool steps given (the steps are recorded a moment after the reply), then returns it. */
async function doneTurn(clientId: string, tools: string[]): Promise<StoredTurn> {
  let turn: StoredTurn | undefined;
  await expect
    .poll(
      async () => {
        turn = await storedTurn(clientId);
        return `${turn.state}|${turn.tools.join(';')}`;
      },
      { message: 'the turn is done, with its tool steps', timeout: REPLY_MS },
    )
    .toBe(`done|${tools.join(';')}`);
  expect(turn!.fallback, 'the turn is no fallback reply').toBe('');
  return turn!;
}

/** The phrases of the reply guard's two lists (ReplyGuard RESERVED and BANNED). */
async function guardPhrases(): Promise<string[]> {
  const lines = await irisScript('Write !,"CHK|phrases|",$Parameter("OcuTalon.Checks.ReplyGuard","RESERVED"),",",$Parameter("OcuTalon.Checks.ReplyGuard","BANNED")');
  const phrases = (chk(lines, 'phrases') ?? '').split(',').filter((one) => one !== '');
  expect(phrases.length, 'the guard lists its phrases').toBeGreaterThanOrEqual(9);
  return phrases;
}

/** Fails if the text holds a phrase of the guard's lists, ignoring case. */
async function expectNoAllClear(text: string): Promise<void> {
  for (const phrase of await guardPhrases()) {
    expect(text.toLowerCase().includes(phrase.toLowerCase()), `the reply does not say "${phrase}"`).toBe(false);
  }
}

interface Posted {
  clientId: string;
  text: string;
  fromGuide?: boolean;
}

/** The bodies of the page's POST /messages requests, in order, as they are made. */
function watchPosts(page: Page): () => Posted[] {
  const posted: Posted[] = [];
  page.on('request', (request: Request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === MESSAGES) posted.push(request.postDataJSON() as Posted);
  });
  return () => posted;
}

/** Signs the rail user in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('RAIL');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(composerOf(page)).toBeVisible();
}

/** A finished guide view: all five steps done, the finish state showing. */
function finishedGuide(): Record<string, unknown> {
  return {
    runEpoch: 1,
    step: 5,
    finished: true,
    steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: true })),
    breakFeed: { active: false, reason: 'not_watching' },
    step4Variant: 'unpaired',
    telegramRow: false,
  };
}

const groupIn = (scope: Locator | Page): Locator => scope.getByRole('group', { name: LABEL, exact: true });
const emptyRow = (page: Page): Locator => groupIn(page.locator('app-empty-chat'));
const finishRow = (page: Page): Locator => groupIn(page.locator('app-demo-guide .finish'));
const chipOf = (row: Locator, n: number): Locator => row.getByRole('button', { name: PROMPTS[n - 1]!, exact: true });
const userOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="user"][data-key="${key}"]`);

/** True when the element of `after` follows the element of `before` in the document. */
function follows(page: Page, before: string, after: string): Promise<boolean> {
  return page.evaluate(
    ([a, b]) => {
      const x = document.querySelector(a!);
      const y = document.querySelector(b!);
      return x !== null && y !== null && (x.compareDocumentPosition(y) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
    },
    [before, after],
  );
}

/** Expects the row to hold the four chips in order, each a button of type "button" named by its text, and none aria-disabled. */
async function expectChips(row: Locator): Promise<void> {
  await expect(row.getByRole('button'), 'four buttons').toHaveText([...PROMPTS]);
  for (let n = 1; n <= 4; n += 1) {
    const chip = chipOf(row, n);
    await expect(chip, `chip ${n} is one button`).toHaveCount(1);
    await expect(chip).toHaveAttribute('type', 'button');
    await expect(chip).not.toHaveAttribute('aria-disabled');
  }
}

/** Presses the chip, with the real empty chat showing, and returns the clientId of the one POST that it made. */
async function press(page: Page, posted: () => Posted[], chip: Locator, how: 'click' | 'Enter' | 'Space'): Promise<Posted> {
  const before = posted().length;
  if (how === 'click') await chip.click();
  else await page.keyboard.press(how);
  await expect.poll(() => posted().length, { message: 'the press made one POST /messages' }).toBe(before + 1);
  return posted()[before]!;
}

/** Records what the case measured on the stack in its annotations. */
function measured(what: string, value: string): void {
  test.info().annotations.push({ type: `measured ${what}`, description: value });
}

test('Y1: the row shows in the empty chat and in the finish state in the demo view, and nowhere else', async ({ page, context }) => {
  test.setTimeout(120_000);
  const posted = watchPosts(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['chat'] = [];
    snapshot['guide'] = finishedGuide();
  });
  await open(page);

  await expect(groupIn(page), 'two rows, one in the empty chat and one in the finish').toHaveCount(2);
  await expect(emptyRow(page)).toHaveCount(1);
  await expect(finishRow(page)).toHaveCount(1);
  const labelled = await page.locator('[role="group"][aria-labelledby]').evaluateAll((groups) =>
    groups.filter((group) => group.querySelector(`#${CSS.escape(group.getAttribute('aria-labelledby') ?? '')}`)?.textContent?.trim() === 'Try it yourself').map((group) => group.getAttribute('aria-labelledby')),
  );
  expect(labelled.length, 'each group is labelled by its own visible label').toBe(2);
  expect(new Set(labelled).size, 'with distinct label ids').toBe(2);
  expect(await follows(page, 'app-empty-chat p.line:last-of-type', 'app-empty-chat [role="group"]'), "the empty chat's row follows its last line").toBe(true);
  expect(await follows(page, '.finish .more', '.finish [role="group"]'), "the finish's row follows More to try").toBe(true);
  expect(await follows(page, '.finish [role="group"]', '.finish .run-again'), 'and precedes Run again').toBe(true);
  await expectChips(emptyRow(page));
  await expectChips(finishRow(page));

  // The switch off in this tab: no row anywhere.
  const off = await context.newPage();
  const offPosted = watchPosts(off);
  await off.addInitScript(() => sessionStorage.setItem('ocutalon.demoView.off', '1'));
  await changeSnapshot(off, (snapshot) => {
    snapshot['chat'] = [];
    snapshot['guide'] = finishedGuide();
  });
  await loadedAfter(off, () => off.goto('/ocutalon/'));
  await expect(off.locator('app-empty-chat'), 'the empty chat shows').toHaveCount(1);
  await expect(groupIn(off), 'no row with the switch off').toHaveCount(0);
  await expect(off.getByRole('button', { name: PROMPTS[0]! })).toHaveCount(0);

  // The server not in demo mode: no row anywhere.
  const plain = await context.newPage();
  const plainPosted = watchPosts(plain);
  await changeSnapshot(plain, (snapshot) => {
    snapshot['chat'] = [];
    snapshot['demoMode'] = false;
  });
  await loadedAfter(plain, () => plain.goto('/ocutalon/'));
  await expect(plain.locator('app-empty-chat'), 'the empty chat shows').toHaveCount(1);
  await expect(groupIn(plain), 'no row when the install is not in demo mode').toHaveCount(0);

  expect([...posted(), ...offPosted(), ...plainPosted()], 'nothing is sent without a press').toEqual([]);
});

test('Y2: while the allowance is used up every chip is aria-disabled and described by the composer\'s reason, and a press sends nothing', async ({ page }) => {
  test.setTimeout(120_000);
  const posted = watchPosts(page);
  await changeSnapshot(page, (snapshot) => {
    snapshot['chat'] = [];
    snapshot['status'] = [...(snapshot['status'] as unknown[]), { condition: 'allowance', active: true, slots: { limit: 20, time: '2037-07-01T12:00:00Z' } }];
  });
  await open(page);

  const row = emptyRow(page);
  const reason = (await page.locator('app-composer .reason').textContent())?.trim() ?? '';
  expect(reason, "the composer's reason shows").not.toBe('');
  for (let n = 1; n <= 4; n += 1) {
    const chip = chipOf(row, n);
    await expect(chip, `chip ${n} is aria-disabled`).toHaveAttribute('aria-disabled', 'true');
    await expect(chip).not.toHaveAttribute('disabled');
    await expect(chip, `chip ${n} is described by the composer's reason`).toHaveAttribute('aria-describedby', REASON_ID);
  }
  await expect(page.locator(`#${REASON_ID}`), 'the described paragraph is the composer\'s reason').toHaveText(reason);
  await expect(chipOf(row, 1)).toHaveAccessibleDescription(reason);

  // Playwright treats an aria-disabled button as not enabled, so the click is forced: the page, not the tool, must refuse it.
  await chipOf(row, 1).click({ force: true });
  await chipOf(row, 1).focus();
  await page.keyboard.press('Enter');
  await settled(page);
  await page.waitForTimeout(500);
  expect(posted(), 'a click and an Enter send nothing').toEqual([]);
  await expect(chipOf(row, 1), 'and the chip keeps its focus').toBeFocused();
});

test('Y3: a click on chip 1 sends its exact text once as an ordinary message and the reply has its strip and trace link', async ({ page }) => {
  test.setTimeout(120_000);
  await expectEmptySession();
  const posted = watchPosts(page);
  await open(page);
  await expectChips(emptyRow(page));

  const sent = await press(page, posted, chipOf(emptyRow(page), 1), 'click');
  expect(sent.text).toBe('Which productions are running?');
  expect(sent.fromGuide, 'not from the guide').toBe(false);
  await expect(page.locator('app-empty-chat'), 'the empty chat gives way').toHaveCount(0);
  await expect(mainOf(page), 'focus is on the main region').toBeFocused();
  const user = userOf(page, sent.clientId);
  await expect(user.locator('.bubble')).toHaveText('Which productions are running?');
  await expect(user).not.toContainText('From the demo guide');
  const reply = replyOf(page, sent.clientId);
  await expect(reply, "the scenario's reply shows").toContainText('The CI mock listed the productions.', { timeout: REPLY_MS });
  const strip = reply.locator('app-decision-strip');
  await expect(strip).toHaveCount(1);
  await expect(strip.locator('app-outcome-chip'), 'the strip has its outcome chip').toHaveCount(1);
  await expect(strip.locator('.line1 .meta > :last-child'), 'line 1 ends in the trace link').toHaveJSProperty('tagName', 'APP-TRACE-LINK');
  await expect(strip.locator('.line1 .meta > :last-child a[href]')).toHaveAttribute('href', new RegExp(`^${TRACE_PAGE.replace(/[.?]/g, '\\$&')}`));
  expect(posted().length, 'and the press made no other POST').toBe(1);

  const turn = await doneTurn(sent.clientId, ['Listing the productions|ok']);
  measured('b chip 1', `state ${turn.state}, fallback "${turn.fallback}", reply "${turn.reply}", tools ${turn.tools.join(';')}`);
  expect(turn.reply).toContain('The CI mock listed the productions.');
});

test('Y4: chip 2 by Space in a session that watches nothing is answered with the code-built sentence and no all-clear wording', async ({ page }) => {
  test.setTimeout(120_000);
  await expectEmptySession();
  const posted = watchPosts(page);
  await open(page);

  await page.locator('app-chat-panel .list').focus();
  await page.keyboard.press('Tab');
  await expect(chipOf(emptyRow(page), 1), 'chip 1 comes first after the chat list').toBeFocused();
  await page.keyboard.press('Tab');
  const chip = chipOf(emptyRow(page), 2);
  await expect(chip).toBeFocused();
  const sent = await press(page, posted, chip, 'Space');
  expect(sent.text).toBe('Is anything wrong right now?');
  expect(sent.fromGuide).toBe(false);

  const reply = replyOf(page, sent.clientId);
  await expect(reply.locator('app-check-rows .sentence'), 'the code-built sentence').toHaveText(NOTHING_WATCHED, { timeout: REPLY_MS });
  await expectNoAllClear((await reply.innerText()).replace(/\s+/g, ' '));
  const turn = await doneTurn(sent.clientId, ['Reading the check results|ok']);
  measured('b chip 2', `state ${turn.state}, fallback "${turn.fallback}", key ${turn.catalogKey}, reply "${turn.reply}", tools ${turn.tools.join(';')}`);
  await expectNoAllClear(turn.reply);
  expect(posted().length).toBe(1);
});

test('Y5: while the turn of a finish chip is in flight every chip is aria-disabled and a press sends nothing', async ({ page }) => {
  test.setTimeout(150_000);
  await expectEmptySession();
  const posted = watchPosts(page);
  await page.clock.install();
  // The routed finish stands only while no guide.state arrives, so the page's polls are answered without those events.
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
  await changeSnapshot(page, (snapshot) => {
    snapshot['guide'] = finishedGuide();
  });
  await open(page);

  const row = finishRow(page);
  await expectChips(row);
  const chip = chipOf(row, 3);
  const sent = await press(page, posted, chip, 'click');
  expect(sent.text).toBe('What was that failure earlier?');
  expect(sent.fromGuide).toBe(false);

  const release = await holdPoll(page);
  try {
    for (let n = 1; n <= 4; n += 1) {
      await expect(chipOf(row, n), `chip ${n} is aria-disabled while the turn is in flight`).toHaveAttribute('aria-disabled', 'true');
      await expect(chipOf(row, n), 'with no description').not.toHaveAttribute('aria-describedby');
    }
    await expect(chip, 'the pressed chip keeps its focus').toBeFocused();
    await page.keyboard.press('Enter');
    // The page's clock is stopped while the poll is held, so its timers cannot settle the page: a real wait lets a wrong POST show.
    await page.waitForTimeout(700);
    expect(posted().length, 'a second press posts nothing').toBe(1);
    await expect(chip, 'and focus stays on the chip').toBeFocused();
  } finally {
    await release();
  }

  await expect(replyOf(page, sent.clientId), "the scenario's reply lands").toContainText('The CI mock read the recent activity.', { timeout: REPLY_MS });
  for (let n = 1; n <= 4; n += 1) {
    await expect(chipOf(row, n), `chip ${n} is enabled again`).not.toHaveAttribute('aria-disabled');
  }
  expect(posted().length).toBe(1);
  const turn = await doneTurn(sent.clientId, ['Reading recent activity|ok']);
  measured('b chip 3', `state ${turn.state}, fallback "${turn.fallback}", reply "${turn.reply}", tools ${turn.tools.join(';')}`);
});

test('Y6: chip 4 by keyboard sends "What can you do?" and the reply has no tool step', async ({ page }) => {
  test.setTimeout(120_000);
  await expectEmptySession();
  const posted = watchPosts(page);
  await open(page);

  await page.locator('app-chat-panel .list').focus();
  for (let n = 1; n <= 4; n += 1) {
    await page.keyboard.press('Tab');
    await expect(chipOf(emptyRow(page), n), `Tab ${n} reaches chip ${n}`).toBeFocused();
  }
  const sent = await press(page, posted, chipOf(emptyRow(page), 4), 'Enter');
  expect(sent.text).toBe('What can you do?');
  expect(sent.fromGuide).toBe(false);

  const reply = replyOf(page, sent.clientId);
  await expect(reply, "the scenario's reply shows").toContainText('The CI mock answered what OcuTalon can do.', { timeout: REPLY_MS });
  await expect(reply.locator('app-decision-strip')).toHaveCount(1);
  await expect(reply.locator('app-decision-strip .line1 .meta > :last-child')).toHaveJSProperty('tagName', 'APP-TRACE-LINK');
  const turn = await doneTurn(sent.clientId, []);
  measured('b chip 4', `state ${turn.state}, fallback "${turn.fallback}", reply "${turn.reply}", tools ${turn.tools.join(';') || 'none'}`);
});

test('Y7: chip 3 in a session with no incident hands the model the code-built "nothing in the last 24 hours" answer', async ({ page }) => {
  test.setTimeout(120_000);
  await expectEmptySession();
  const posted = watchPosts(page);
  await open(page);

  const marked = await irisScript('Write !,"CHK|mark|",##class(OcuTalon.Test.Contract.Mock).LogMark()');
  const logMark = chk(marked, 'mark') ?? '';
  expect(logMark, 'the mock log has a mark').toMatch(/^\d+$/);
  const sent = await press(page, posted, chipOf(emptyRow(page), 3), 'click');
  const reply = replyOf(page, sent.clientId);
  await expect(reply, "the scenario's reply shows").toContainText('The CI mock read the recent activity.', { timeout: REPLY_MS });
  await doneTurn(sent.clientId, ['Reading recent activity|ok']);

  const lines = await irisScript(
    [
      `Set sc=##class(OcuTalon.Test.Contract.Mock).LogSince(${logMark},.entries)`,
      'Set n=0,second="",i=entries.%GetIterator()',
      'While i.%GetNext(,.entry) { If entry.path="/v1/messages",(","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(entry)_",")[",recent_activity," { Set n=n+1 Set:n=2 second=entry } }',
      'Write !,"CHK|requests|",n',
      'If n=2 Set r=##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(second) Write !,"CHK|results|",$ListLength(r) Write !,"CHK|result|",$Translate($List(r,1),$Char(13,10),"  ")',
      'Write !,"CHK|none|",$Parameter("OcuTalon.Tools.RecentActivity","NONE")',
    ].join('\n'),
  );
  expect(chk(lines, 'requests'), "the Chat agent's requests that offer recent_activity (the tool call and the one with its result)").toBe('2');
  expect(chk(lines, 'results'), 'the second carries one tool result').toBe('1');
  const result = JSON.parse(chk(lines, 'result') ?? 'null') as { ok: boolean; hours: number; incidents: unknown[]; message: string };
  measured('c chip 3 tool result', chk(lines, 'result') ?? '');
  expect(result.ok).toBe(true);
  expect(result.hours).toBe(24);
  expect(result.incidents).toEqual([]);
  expect(result.message, "the tool's own 'none' message").toBe(chk(lines, 'none'));
  expect(Object.keys(result).sort()).toEqual(['hours', 'incidents', 'message', 'ok']);
  await expectNoAllClear((await reply.innerText()).replace(/\s+/g, ' '));
});
