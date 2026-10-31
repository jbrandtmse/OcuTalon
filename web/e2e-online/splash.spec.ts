import { createHash } from 'node:crypto';

import { expect, test, type Locator, type Page, type Response } from '@playwright/test';

import { countdownText, pageTime, WHEN_TEXTS } from '../src/app/chat/page-time';
import { README_URL } from '../src/app/links';
import { expectRing, expectRingInside, loadedAfter, readFocus, type Reading } from '../e2e/support/floor';
import { fixtureUser } from '../e2e/support/iris';
import { plain, tokenColor } from '../e2e/support/page';
import { scanPage } from '../e2e/support/scan';
import { SIGN_IN_IMAGES, watchViolations } from '../e2e/sign-in/helpers';
import { recordSplashAnnouncements, signInFromSplash, signOutGroup, splashAnnouncements } from './support';

/**
 * Story 16.2, the online demo's splash screen in a real browser on the online-demo throwaway (S1 to S12, S2b, S6b and S8b; matrix rows 1
 * to 10). The page is the sign-in page of every request without a session, with the published values that the unit's test start values
 * wrote. Every case
 * opens the page with its own unique probe=<n> (the web gateway keeps the answer to a URL) and signs out of the whole sign-in group in
 * `finally`, whether it signed in or not.
 * - S1: the head and the sign-in card: the texts, the prefilled text inputs with their 88px labels, the four copy buttons, the session
 *   line, the warning notice just before the full-width button, no show/hide toggle.
 * - S2: the Before you start card with the reset line (the browser's zone and clock, the countdown at 1 h 42 min, 9 min and 23 s, then
 *   rolled forward), its four lines in order with the chat-only limit line and no Telegram line, the Visual Trace card and the footer.
 * - S3: the four copy buttons write the exact value, show "Copied" for about 2 seconds and announce it once.
 * - S4: a rejected write, then no clipboard at all: the failure text under that card's rows, announced once, the value selected, the line
 *   gone after the next successful copy in that card.
 * - S5: the button, and Enter in the password field, sign in without typing.
 * - S6: a wrong password is refused under the button with the user name kept and the focus on the error; the read-only account gets the
 *   no-role text and the published values.
 * - S7: the POST carries no field outside the four of AD-25's allow-list, at /ocutalon/ and with a query string.
 * - S8: 1280x600 in light and dark: the button above the fold, the canvas, the column and the cards side by side, the in-house scan.
 * - S9: the focus order, the ring at every stop, Enter and Space on a copy button.
 * - S10: the envelope: the exact policy over the hashes of the one style and the one script, no-store, no other file.
 * - S2b, S11, S12: the singular countdown words, the address's fragment through sign-in, and the cards stacked at phone width.
 * - S6b, S8b: a refused name that holds markup is kept exactly and escaped, under the same policy, with the focused error's ring; the
 *   button's whole box and the scheme's logo at 1280x600.
 * The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 120_000 });

const HEADING = 'Try OcuTalon in two minutes';
const SUBHEADING = 'Break the feed, and approve the fix from your phone.';
const DESCRIPTION =
  'OcuTalon is an assistant that lives inside InterSystems IRIS Interoperability. When a feed breaks, it reads the failed messages and the trace, names the cause in plain English, and proposes a fix that waits for your approval. For everything that arrives, an AI Hub agent makes one attention decision (ignore it, save it for your daily digest, tell you now, or act), and every decision, with its reasons and cost, is a production message you can open in Visual Trace. No API key needed.';
const SESSION_LINE = 'Your session is yours alone and lasts until the next reset. Signing in again from this browser picks it up.';
const WARNING = "Other visitors can see messages in Visual Trace, so don't type personal information.";
const SUBMIT = 'Sign in and start';
const WRONG = "That user name and password didn't work.";
const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const COPY_FAILED = "Couldn't copy. Select the text and copy it yourself.";
const OWN_LINE = 'Your chat, phone, mailbox and orders are yours alone.';
const LIMIT_LINE = 'Each session can send 50 messages an hour in the chat.';
const SHELL_LINE = "OcuTalon can't run shell commands, and every action it takes is recorded in the IRIS audit log.";
const TRACE_HEADING = 'Read-only Visual Trace account,';
const TRACE_PARAGRAPH = 'for opening Visual Trace in the portal yourself (trace links on the page are already signed in). See each decision with its cost, and every step.';
const FOOTER_NOTE = 'OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.';
const INSTALL = 'Install it yourself (README) (opens in a new tab)';

const COPY_BUTTONS = ['Copy user name', 'Copy password', 'Copy Visual Trace user name', 'Copy Visual Trace password'] as const;
/** The only fields that AD-25's proxy admits in a sign-in POST. */
const ALLOWED_FIELDS = new Set(['IRISSessionToken', 'IRISUsername', 'IRISPassword', 'IRISLogin']);

const demo = (): { user: string; password: string } => fixtureUser('DEMOACCOUNT');
const readonly = (): { user: string; password: string } => fixtureUser('READONLYACCOUNT');

let probes = 0;
/** A number that no page request of this run used. */
const probe = (): string => `${Date.now()}${(probes += 1)}`;
const splashPath = (extra = ''): string => `/ocutalon/?${extra}probe=${probe()}`;

const userInput = (page: Page): Locator => page.getByLabel('User name', { exact: true });
const passwordInput = (page: Page): Locator => page.getByLabel('Password', { exact: true });
const submitButton = (page: Page): Locator => page.getByRole('button', { name: SUBMIT, exact: true });
const copyButton = (page: Page, name: string): Locator => page.getByRole('button', { name, exact: true });
const mainOf = (page: Page): Locator => page.locator('main.main');
const sha256 = (text: string): string => createHash('sha256').update(text, 'utf8').digest('base64');

/** The width and the box of an element. */
async function box(locator: Locator): Promise<{ left: number; top: number; right: number; bottom: number; width: number }> {
  const found = await locator.boundingBox();
  if (found === null) throw new Error('the element has no box');
  return { left: found.x, top: found.y, right: found.x + found.width, bottom: found.y + found.height, width: found.width };
}

/** The texts announced since the count before, once the live region has made them (it speaks a moment after it is emptied). */
const announcedSince = (page: Page, before: number): Promise<string[]> => splashAnnouncements(page).then((all) => all.slice(before));

/** The status endpoint's next reset: what the page's <time datetime> must equal. */
async function nextReset(page: Page): Promise<string> {
  const status = (await (await page.request.get(`/ocutalon/public/status?probe=${probe()}`)).json()) as { nextReset: string | null };
  expect(status.nextReset, 'the stack has a next reset').toBeTruthy();
  return status.nextReset as string;
}

test.describe('S1 to S2, the page', () => {
  test.use({ locale: 'en-US', timezoneId: 'Asia/Kolkata' });

  /** S1: the head and the sign-in card. */
  test('S1: the head and the sign-in card show the demo and its published values', async ({ page }) => {
    try {
      const violations = watchViolations(page);
      await page.goto(splashPath());
      await expect(page).toHaveTitle('Try OcuTalon');
      await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      const logo = page.getByRole('img', { name: 'OcuTalon', exact: true });
      await expect(logo).toBeVisible();
      expect((await box(logo)).width, 'the logo is 240px wide').toBeCloseTo(240, 0);
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(HEADING);
      await expect(page.getByText(SUBHEADING, { exact: true })).toBeVisible();
      await expect(page.getByText(DESCRIPTION, { exact: true })).toBeVisible();
      await expect(page.getByRole('heading', { level: 2, name: 'Sign in to the demo', exact: true })).toBeVisible();

      const user = userInput(page);
      const password = passwordInput(page);
      for (const [input, value, label] of [
        [user, demo().user, 'User name'],
        [password, demo().password, 'Password'],
      ] as const) {
        await expect(input, `${label} is a text input`).toHaveAttribute('type', 'text');
        await expect(input, `${label} holds the published demo value`).toHaveValue(value);
        const labelBox = await box(page.locator(`label:text-is("${label}")`));
        expect(labelBox.width, `the ${label} label is in an 88px column`).toBeCloseTo(88, 0);
        expect(labelBox.right, `the ${label} label lies to the left of its input`).toBeLessThanOrEqual((await box(input)).left);
      }
      for (const name of COPY_BUTTONS) await expect(copyButton(page, name), name).toBeVisible();
      await expect(page.getByRole('button', { name: /show password/i }), 'no show/hide toggle').toHaveCount(0);
      await expect(page.getByText(SESSION_LINE, { exact: true })).toBeVisible();

      const button = submitButton(page);
      await expect(button).toHaveAttribute('name', 'IRISLogin');
      await expect(button, 'the button is described by the warning').toHaveAccessibleDescription(WARNING);
      const before = await button.evaluate((el) => {
        const sibling = el.previousElementSibling;
        return { text: (sibling?.textContent ?? '').trim(), notice: sibling?.classList.contains('notice') ?? false };
      });
      expect(before, 'the warning notice is the element just before the button').toEqual({ text: WARNING, notice: true });
      const formBox = await box(page.locator('form[name="Login"]'));
      expect((await box(button)).width, 'the button is as wide as the form').toBeCloseTo(formBox.width, 0);
      expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
    } finally {
      await signOutGroup(page);
    }
  });

  /** S2: the Before you start card, the Visual Trace card and the footer, with the browser's own zone and clock. */
  test('S2: the Before you start card counts down to the next reset in the browser zone; the Visual Trace card and the footer', async ({ page }) => {
    try {
      const due = await nextReset(page);
      const dueMs = Date.parse(due);
      // The clock starts 1 h 42 min 30 s before the reset, so that the minutes read 42 whatever tick the page last made.
      const start = dueMs - (102 * 60 + 30) * 1000;
      await page.clock.install({ time: start - 60_000 });
      await page.goto(splashPath());
      await page.clock.pauseAt(start);
      await page.clock.runFor(1000);

      const stamp = page.locator('#ocu-reset-time');
      await expect(stamp, 'the datetime is the status endpoint\'s next reset').toHaveAttribute('datetime', due);
      await expect(page.getByRole('heading', { level: 2, name: 'Before you start', exact: true })).toBeVisible();
      const shown = page.locator('#ocu-countdown');
      const spoken = page.locator('#ocu-countdown-spoken');
      const line = page.locator('li').filter({ has: stamp });
      const lineWithoutSpoken = (): Promise<string> =>
        line.evaluate((el) => {
          const copy = el.cloneNode(true) as HTMLElement;
          copy.querySelectorAll('.sr-only').forEach((node) => node.remove());
          return copy.textContent ?? '';
        });

      /** The page's countdown at the clock's now, or one second before it (the tick that the page last made). */
      const readCountdown = async (): Promise<{ shown: string; spoken: string; expected: Array<{ text: string; spoken: string }> }> => {
        const now = await page.evaluate(() => Date.now());
        return {
          shown: (await shown.textContent()) ?? '',
          spoken: (await spoken.textContent()) ?? '',
          expected: [countdownText(due, now), countdownText(due, now - 1000)],
        };
      };
      const expectCountdown = async (text: string, words: string): Promise<void> => {
        const read = await readCountdown();
        expect(read.shown).toBe(text);
        expect(read.spoken).toBe(words);
        expect(read.expected.map((one) => one.text), 'page-time.ts says the same').toContain(text);
        expect(read.expected.map((one) => one.spoken), 'page-time.ts says the same in words').toContain(words);
      };
      const shownTime = pageTime(due, 'en-US', 'Asia/Kolkata');
      expect(plain(await stamp.textContent()), "the reset time is the browser zone's page time").toBe(plain(shownTime));
      await expectCountdown('in 1 h 42 min', 'in 1 hour 42 minutes');
      expect(plain(await lineWithoutSpoken()), 'the reset line').toBe(`The demo resets every 4 hours. Next reset: ${plain(shownTime)} (in 1 h 42 min).`);
      await expect(shown).toHaveAttribute('aria-hidden', 'true');

      // The script's countdown words are page-time.ts's.
      const script = await page.evaluate(() => document.querySelector('script')?.textContent ?? '');
      for (const key of ['seconds', 'secondsOne', 'secondsOther', 'minutes', 'minutesOne', 'minutesOther', 'hours', 'hoursOne', 'hoursOther', 'minuteOne', 'minuteOther'] as const) {
        expect(script, `the script holds WHEN_TEXTS.${key}`).toContain(`'${WHEN_TEXTS[key]}'`);
      }

      // 9 min: from 1 h 42 min 30 s, 93 min later it is 9 min 30 s.
      await page.clock.runFor(93 * 60 * 1000);
      await expectCountdown('in 9 min', 'in 9 minutes');
      // 23 s: one second at a time, so that one tick is made per step, until the text reads 23 s.
      await page.clock.runFor(8 * 60 * 1000 + 40 * 1000);
      let seen = '';
      for (let step = 0; step < 40 && seen !== 'in 23 s'; step += 1) {
        await page.clock.runFor(1000);
        seen = (await shown.textContent()) ?? '';
      }
      await expectCountdown('in 23 s', 'in 23 seconds');
      // Past the reset it rolls forward by the interval: the next reset 4 hours on.
      await page.clock.runFor(30 * 1000);
      const rolled = dueMs + 4 * 3600 * 1000;
      await expect(stamp).toHaveAttribute('datetime', new Date(rolled).toISOString());
      expect(plain(await stamp.textContent()), 'the rolled time is the next reset in the browser zone').toBe(plain(pageTime(new Date(rolled).toISOString(), 'en-US', 'Asia/Kolkata')));
      expect((await shown.textContent()) ?? '', 'the countdown counts to the rolled reset').toMatch(/^in 3 h (5\d|4\d) min$/);

      await expect(page.getByText(OWN_LINE, { exact: true })).toBeVisible();
      const before = page.getByRole('region', { name: 'Before you start', exact: true });
      await expect(before.locator('li'), 'the list holds the reset, own, limit and shell lines').toHaveCount(4);
      await expect(before.locator('li'), 'the reset, own, chat-only limit and shell lines, in that order').toHaveText([/^The demo resets every 4 hours\. Next reset: /, OWN_LINE, LIMIT_LINE, SHELL_LINE]);
      await expect(before, 'no Telegram line').not.toContainText('Telegram');
      await expect(before, 'no QR code line').not.toContainText('QR');
      await expect(page.getByText(LIMIT_LINE, { exact: true }), 'the limit line reads the allowance of the start values').toBeVisible();
      await expect(page.getByText(SHELL_LINE, { exact: true })).toBeVisible();

      // The Visual Trace card: its heading and paragraph give the whole sentence.
      const card = page.getByRole('region', { name: TRACE_HEADING, exact: true });
      const heading = card.getByRole('heading', { level: 2 });
      await expect(heading).toHaveText(TRACE_HEADING);
      const paragraph = card.locator('.vt-text p');
      await expect(paragraph).toHaveText(TRACE_PARAGRAPH);
      expect(`${(await heading.textContent()) ?? ''} ${(await paragraph.textContent()) ?? ''}`).toBe(`${TRACE_HEADING} ${TRACE_PARAGRAPH}`);
      const rows = card.locator('.cred');
      await expect(rows).toHaveCount(2);
      await expect(rows.nth(0).locator('dt')).toHaveText('User name');
      await expect(rows.nth(1).locator('dt')).toHaveText('Password');
      await expect(card.locator('#ocu-vt-user')).toHaveText(readonly().user);
      await expect(card.locator('#ocu-vt-pass')).toHaveText(readonly().password);
      const family = await card.locator('#ocu-vt-user').evaluate((el) => getComputedStyle(el).fontFamily);
      expect(family, 'the values are in the mono type').toMatch(/mono|menlo|consolas|courier/i);
      await expect(copyButton(page, 'Copy Visual Trace user name')).toBeVisible();
      await expect(copyButton(page, 'Copy Visual Trace password')).toBeVisible();

      // The footer.
      const footer = page.getByRole('contentinfo');
      await expect(footer).toHaveCount(1);
      await expect(page.locator('main footer'), 'the footer is outside main').toHaveCount(0);
      await expect(footer.getByText(FOOTER_NOTE, { exact: true })).toBeVisible();
      const link = footer.getByRole('link', { name: INSTALL, exact: true });
      await expect(link).toHaveAttribute('href', README_URL);
      await expect(link).toHaveAttribute('target', '_blank');
      await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
      await expect(link.locator('svg'), 'the icon is hidden from assistive technology').toHaveAttribute('aria-hidden', 'true');
    } finally {
      await signOutGroup(page);
    }
  });
});

test.describe('S2b, the singular countdown words', () => {
  test.use({ locale: 'en-US', timezoneId: 'Asia/Kolkata' });

  /** S2b: one hour, one minute and one second read in the singular, as page-time.ts says them. */
  test('S2b: the countdown reads 1 h 1 min, 1 min and 1 s with the singular spoken words of page-time.ts', async ({ page }) => {
    try {
      const due = await nextReset(page);
      const dueMs = Date.parse(due);
      // 1 h 1 min 30 s before the reset.
      const start = dueMs - (61 * 60 + 30) * 1000;
      await page.clock.install({ time: start - 60_000 });
      await page.goto(splashPath());
      await page.clock.pauseAt(start);
      await page.clock.runFor(1000);
      const shown = page.locator('#ocu-countdown');
      const spoken = page.locator('#ocu-countdown-spoken');
      const expectBoth = async (text: string, words: string): Promise<void> => {
        const now = await page.evaluate(() => Date.now());
        expect(await shown.textContent()).toBe(text);
        expect(await spoken.textContent()).toBe(words);
        const oracle = [countdownText(due, now), countdownText(due, now - 1000)];
        expect(oracle.map((one) => one.text), 'page-time.ts says the same').toContain(text);
        expect(oracle.map((one) => one.spoken), 'page-time.ts says the same in words').toContain(words);
      };
      await expectBoth('in 1 h 1 min', 'in 1 hour 1 minute');
      // 1 min: 90 s before the reset.
      await page.clock.runFor(3600 * 1000);
      await expectBoth('in 1 min', 'in 1 minute');
      // 1 s: one second at a time, until the text reads 1 s.
      await page.clock.runFor(84 * 1000);
      let seen = '';
      for (let step = 0; step < 10 && seen !== 'in 1 s'; step += 1) {
        await page.clock.runFor(1000);
        seen = (await shown.textContent()) ?? '';
      }
      await expectBoth('in 1 s', 'in 1 second');
    } finally {
      await signOutGroup(page);
    }
  });
});

test.describe('S3 to S4, the copy buttons', () => {
  test.use({ permissions: ['clipboard-read', 'clipboard-write'] });

  /** The row's own "Copied" text of a copy button: the button's row holds it. */
  const copiedOf = (page: Page, name: string): Locator => copyButton(page, name).locator('xpath=ancestor::*[@data-row][1]').locator('[data-copied]');

  /** S3: each button writes exactly its value, shows "Copied" for about 2 seconds and announces it once. */
  test('S3: each copy button puts the exact value on the clipboard, shows Copied for about 2 seconds and announces it once', async ({ page }) => {
    try {
      await recordSplashAnnouncements(page);
      await page.goto(splashPath());
      // The button copies the input's current value, so the password is changed first.
      const typed = `typed ${probe()}`;
      await passwordInput(page).fill(typed);
      const values = [demo().user, typed, readonly().user, readonly().password];
      for (const [index, name] of COPY_BUTTONS.entries()) {
        const before = (await splashAnnouncements(page)).length;
        const pressed = Date.now();
        await copyButton(page, name).click();
        const mark = copiedOf(page, name);
        await expect(mark, `${name}: Copied shows in its row`).toBeVisible();
        expect(await page.evaluate(() => navigator.clipboard.readText()), `${name}: the clipboard holds exactly the value`).toBe(values[index]);
        await page.waitForTimeout(Math.max(0, 1000 - (Date.now() - pressed)));
        await expect(mark, `${name}: it is still there 1 s after the press`).toBeVisible();
        await expect(mark, `${name}: it is gone within 3.5 s`).toBeHidden({ timeout: 2500 });
        await expect.poll(() => announcedSince(page, before), { message: `${name}: Copied is announced once` }).toEqual(['Copied']);
        await expect(page.locator('[data-failure]:visible')).toHaveCount(0);
      }
    } finally {
      await signOutGroup(page);
    }
  });

  /** S4: a rejected write, then no clipboard: the failure line, announced once, the value selected, gone after the next success in its card. */
  test('S4: a copy that fails shows the failure line under its card, announces it once, selects the value and ends with the next success', async ({ page }) => {
    try {
      await recordSplashAnnouncements(page);
      await page.addInitScript(() => {
        (window as unknown as { rejectCopy: boolean }).rejectCopy = true;
        const original = navigator.clipboard.writeText.bind(navigator.clipboard);
        navigator.clipboard.writeText = (text: string): Promise<void> =>
          (window as unknown as { rejectCopy: boolean }).rejectCopy ? Promise.reject(new Error('denied')) : original(text);
      });
      await page.goto(splashPath());
      const signInCard = page.getByRole('region', { name: 'Sign in to the demo', exact: true });
      const traceCard = page.getByRole('region', { name: TRACE_HEADING, exact: true });
      const failure = (card: Locator): Locator => card.locator('[data-failure]');

      // The sign-in card: the rejected write selects the input's exact value.
      let before = (await splashAnnouncements(page)).length;
      await copyButton(page, 'Copy password').click();
      await expect(failure(signInCard), 'the failure text shows under the sign-in card rows').toBeVisible();
      await expect(failure(signInCard)).toHaveText(COPY_FAILED);
      await expect(failure(signInCard).locator('svg'), 'with the circle-alert icon').toHaveAttribute('aria-hidden', 'true');
      await expect.poll(() => announcedSince(page, before), { message: 'it is announced once' }).toEqual([COPY_FAILED]);
      expect(await page.evaluate(() => document.activeElement?.id), 'the input has the focus, so that its selection shows').toBe('ocu-pass');
      const selection = await page.evaluate(() => {
        const el = document.getElementById('ocu-pass') as HTMLInputElement;
        return { text: el.value.slice(el.selectionStart ?? 0, el.selectionEnd ?? 0), whole: el.value };
      });
      expect(selection.text, "the input's selection range is exactly the value").toBe(demo().password);
      expect(selection.whole).toBe(demo().password);
      await expect(failure(traceCard), 'the other card has no failure line').toBeHidden();

      // The Visual Trace card: the selection of the document is exactly the row's value.
      before = (await splashAnnouncements(page)).length;
      await copyButton(page, 'Copy Visual Trace user name').click();
      await expect(failure(traceCard)).toBeVisible();
      await expect(failure(traceCard)).toHaveText(COPY_FAILED);
      await expect.poll(() => announcedSince(page, before)).toEqual([COPY_FAILED]);
      expect(await page.evaluate(() => window.getSelection()?.toString()), "the selection is exactly the row's value").toBe(readonly().user);
      await expect(failure(signInCard), 'the sign-in card keeps its line until its next success').toBeVisible();

      // A later success in a card removes its line and leaves the other card's.
      await page.evaluate(() => {
        (window as unknown as { rejectCopy: boolean }).rejectCopy = false;
      });
      // Each success's "Copied" is spoken a moment after the press: wait for it, so that the next count starts after it.
      before = (await splashAnnouncements(page)).length;
      await copyButton(page, 'Copy user name').click();
      await expect(failure(signInCard)).toBeHidden();
      await expect.poll(() => announcedSince(page, before)).toEqual(['Copied']);
      await expect(failure(traceCard), "the other card's line stays").toBeVisible();
      before = (await splashAnnouncements(page)).length;
      await copyButton(page, 'Copy Visual Trace password').click();
      await expect(failure(traceCard)).toBeHidden();
      await expect.poll(() => announcedSince(page, before)).toEqual(['Copied']);

      // No clipboard at all.
      await page.evaluate(() => {
        Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true });
      });
      before = (await splashAnnouncements(page)).length;
      await copyButton(page, 'Copy Visual Trace password').click();
      await expect(failure(traceCard)).toBeVisible();
      await expect.poll(() => announcedSince(page, before), { message: 'it is announced once' }).toEqual([COPY_FAILED]);
      expect(await page.evaluate(() => window.getSelection()?.toString()), "the selection is exactly the row's value").toBe(readonly().password);
      await copyButton(page, 'Copy user name').click();
      await expect(failure(signInCard)).toBeVisible();
      const again = await page.evaluate(() => {
        const el = document.getElementById('ocu-user') as HTMLInputElement;
        return el.value.slice(el.selectionStart ?? 0, el.selectionEnd ?? 0);
      });
      expect(again, "an input's selection range is exactly the value").toBe(demo().user);
      expect(await page.evaluate(() => document.activeElement?.id), 'and the input has the focus').toBe('ocu-user');
    } finally {
      await signOutGroup(page);
    }
  });
});

test.describe('S5 to S7, signing in', () => {
  /** S5: the button, and Enter in the password field, sign in without typing. */
  test('S5: Sign in and start, and Enter in the password field, open the main page without typing', async ({ page }) => {
    try {
      await loadedAfter(page, () => signInFromSplash(page, undefined, undefined, splashPath()));
      await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
      await expect(page).toHaveTitle('OcuTalon');
      await signOutGroup(page);

      await page.goto(splashPath());
      await expect(page).toHaveTitle('Try OcuTalon');
      await loadedAfter(page, () => passwordInput(page).press('Enter'));
      await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    } finally {
      await signOutGroup(page);
    }
  });

  /** S6: a wrong password is refused under the button; the read-only account gets the no-role text. */
  test('S6: a wrong password and the read-only account are refused under the button', async ({ page }) => {
    try {
      const wrong = `wrong-${probe()}`;
      await signInFromSplash(page, undefined, wrong, splashPath());
      const error = page.locator('#ocu-error');
      await expect(error).toHaveText(WRONG);
      await expect(page.locator('app-root')).toHaveCount(0);
      const placed = await page.evaluate(() => {
        const el = document.getElementById('ocu-error');
        const button = document.querySelector('button[name="IRISLogin"]');
        return {
          focused: document.activeElement === el,
          after: button !== null && el !== null && (button.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0,
          tabindex: el?.getAttribute('tabindex'),
        };
      });
      expect(placed, 'the error is after the button, focusable and focused').toEqual({ focused: true, after: true, tabindex: '-1' });
      await expect(userInput(page), 'the user name is kept').toHaveValue(demo().user);
      await expect(passwordInput(page), 'the password is cleared').toHaveValue('');
      for (const input of [userInput(page), passwordInput(page)]) {
        await expect(input).toHaveAttribute('aria-invalid', 'true');
        await expect(input).toHaveAttribute('aria-describedby', 'ocu-error');
      }

      // The read-only account holds no OcuTalon role.
      await userInput(page).fill(readonly().user);
      await passwordInput(page).fill(readonly().password);
      const answered = page.waitForResponse((response) => response.request().method() === 'POST');
      await submitButton(page).click();
      // The retry is posted from the refusal page, where the browser holds a CSP session: still only the proxy's four fields.
      const retry = (await answered).request();
      const names = [...new URLSearchParams(retry.postData() ?? '').keys()];
      console.log(`MEASURED the refusal page's POST fields: ${names.join(' ')}`);
      expect(retry.headers()['content-type'], 'the retry is urlencoded').toBe('application/x-www-form-urlencoded');
      expect(names.filter((name) => !ALLOWED_FIELDS.has(name)), 'the POST from the refusal page carries no field outside the four').toEqual([]);
      for (const name of ['IRISUsername', 'IRISPassword', 'IRISLogin']) expect(names, `the retry carries ${name}`).toContain(name);
      await expect(page.locator('#ocu-error')).toHaveText(NO_ROLE);
      await expect(page.locator('app-root'), 'the shell is never served').toHaveCount(0);
      await expect(userInput(page), 'with no field marked, the fields hold the published values').toHaveValue(demo().user);
      await expect(userInput(page)).not.toHaveAttribute('aria-invalid', 'true');
    } finally {
      await signOutGroup(page);
    }
  });

  /**
   * S7: the form's POST carries no field but the four of the proxy's allow-list, and the redirect that answers it drops since and ended (Story
   * 16.8 and 16.4; the page that then loads normalizes its address to /ocutalon/#/, so the redirect's Location is where Shell.Redirect shows).
   */
  test('S7: the sign-in POST carries only IRISSessionToken, IRISUsername, IRISPassword and IRISLogin', async ({ page }) => {
    try {
      const allowed = ALLOWED_FIELDS;
      for (const path of [splashPath(), splashPath('since=2026-10-25T00:00:00Z&'), splashPath('since=2026-10-25T00:00:00Z&ended=1&')]) {
        const posts: Array<{ url: string; type: string; names: string[] }> = [];
        const watch = (request: { method: () => string; url: () => string; postData: () => string | null; headers: () => Record<string, string> }): void => {
          if (request.method() !== 'POST' || !new URL(request.url()).pathname.startsWith('/ocutalon/')) return;
          posts.push({
            url: request.url(),
            type: request.headers()['content-type'] ?? '',
            names: [...new URLSearchParams(request.postData() ?? '').keys()],
          });
        };
        page.on('request', watch);
        let answer!: Response;
        await loadedAfter(page, async () => {
          answer = await signInFromSplash(page, undefined, undefined, path);
        });
        await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
        const location = answer.headers()['location'] ?? '';
        expect(location, `the sign-in POST answers with a redirect (from ${path})`).not.toBe('');
        expect(new URL(location, page.url()).searchParams.has('since'), `the redirect after the sign-in POST drops since (from ${path}: ${location})`).toBe(false);
        expect(new URL(location, page.url()).searchParams.has('ended'), `and ended (Story 16.4; from ${path}: ${location})`).toBe(false);
        page.off('request', watch);
        const sent = posts.find((one) => new URL(one.url).pathname === '/ocutalon/');
        expect(sent, `the form was posted at ${path}`).toBeTruthy();
        expect(sent?.type, 'urlencoded').toBe('application/x-www-form-urlencoded');
        expect(sent?.names.filter((name) => !allowed.has(name)), 'no field outside the four').toEqual([]);
        for (const name of ['IRISUsername', 'IRISPassword', 'IRISLogin']) expect(sent?.names, `the POST carries ${name}`).toContain(name);
        await signOutGroup(page);
      }
    } finally {
      await signOutGroup(page);
    }
  });
});

test.describe('S11 to S12, the fragment and the phone width', () => {
  /** S11: the address's fragment is carried through sign-in by the splash's script. */
  test('S11: signing in at an address with a fragment lands on that fragment', async ({ page }) => {
    try {
      await loadedAfter(page, () => signInFromSplash(page, undefined, undefined, `${splashPath()}#/x`));
      await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
      await expect(page, 'the page lands on #/x once it has booted').toHaveURL((url) => url.hash === '#/x');
    } finally {
      await signOutGroup(page);
    }
  });

  /** S12: at phone width the cards stack, nothing scrolls sideways and the button is on the page. */
  test('S12: at 390px wide the cards stack, the page does not scroll sideways and the button is inside the width', async ({ page }) => {
    try {
      await page.setViewportSize({ width: 390, height: 800 });
      await page.goto(splashPath());
      await expect(submitButton(page)).toBeVisible();
      const cards = page.locator('.splash-cards > section');
      await expect(cards).toHaveCount(2);
      const first = await box(cards.nth(0));
      const second = await box(cards.nth(1));
      expect(first.left, 'the cards stack: their lefts are equal').toBeCloseTo(second.left, 0);
      expect(second.top, 'the second card is below the first').toBeGreaterThan(first.top + 10);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      expect(overflow, 'no horizontal scroll').toBeLessThanOrEqual(0);
      const button = await box(submitButton(page));
      expect(button.left).toBeGreaterThanOrEqual(0);
      expect(button.right, 'the whole button is inside the width').toBeLessThanOrEqual(390);
      for (const name of COPY_BUTTONS) {
        const found = await box(copyButton(page, name));
        expect(found.right, `${name} is inside the width`).toBeLessThanOrEqual(390);
      }
    } finally {
      await signOutGroup(page);
    }
  });
});

test.describe('S8 to S10, the layout, the keyboard and the envelope', () => {
  /** S8: 1280x600 in light and dark. */
  test('S8: at 1280x600 in light and dark the button is above the fold, on the canvas, with the cards side by side', async ({ page }) => {
    try {
      await page.setViewportSize({ width: 1280, height: 600 });
      for (const [scheme, background] of [
        ['light', 'rgb(255, 255, 255)'],
        ['dark', 'rgb(17, 25, 43)'],
      ] as const) {
        await page.emulateMedia({ colorScheme: scheme });
        await page.goto(splashPath());
        await expect(submitButton(page)).toBeVisible();
        expect((await box(submitButton(page))).bottom, `${scheme}: the whole button is inside the viewport`).toBeLessThanOrEqual(600);
        expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor), `${scheme}: the canvas`).toBe(background);
        expect((await box(page.locator('.splash'))).width, `${scheme}: the column is at most 960px`).toBeLessThanOrEqual(960);
        const cards = page.locator('.splash-cards > section');
        await expect(cards).toHaveCount(2);
        const first = await box(cards.nth(0));
        const second = await box(cards.nth(1));
        expect(first.top, `${scheme}: the two cards' tops are equal`).toBeCloseTo(second.top, 0);
        expect(first.left, `${scheme}: side by side`).not.toBeCloseTo(second.left, 0);
        // The logo carries the alt that the page requires, so the scan's one finding against it, a read image, is left out: exactly one.
        const scanned = await scanPage(page, scheme);
        const findings = scanned.filter((finding) => !finding.includes('- img "OcuTalon"'));
        expect(scanned.length - findings.length, `${scheme}: exactly one finding is left out, the logo's`).toBe(1);
        expect(findings, `${scheme}: the in-house scan finds nothing`).toEqual([]);
      }
    } finally {
      await signOutGroup(page);
    }
  });

  test.describe('S9', () => {
    test.use({ permissions: ['clipboard-read', 'clipboard-write'] });

    /** What the focused element is: the id of an input, else its name. */
    const stopName = (page: Page): Promise<string> =>
      page.evaluate(() => {
        const el = document.activeElement as HTMLElement | null;
        if (el === null) return '';
        return el.id !== '' && el.tagName === 'INPUT' ? `#${el.id}` : (el.getAttribute('aria-label') ?? (el.textContent ?? '').replace(/\s+/g, ' ').trim());
      });

    /** The focused input's own box, read as the ring's box: an input draws its ring on the box around it. */
    async function readInputBox(page: Page): Promise<Reading> {
      return page.evaluate(() => {
        const wrapper = (document.activeElement as HTMLElement).closest('.input') as HTMLElement;
        const style = getComputedStyle(wrapper);
        const rect = wrapper.getBoundingClientRect();
        const grow = Math.max(0, parseFloat(style.outlineOffset) + parseFloat(style.outlineWidth));
        return {
          what: 'the box of an input',
          outlineStyle: style.outlineStyle,
          outlineWidth: style.outlineWidth,
          outlineColor: style.outlineColor,
          outlineOffset: style.outlineOffset,
          boxShadow: style.boxShadow,
          clipPath: style.clipPath,
          ring: { left: rect.left - grow, top: rect.top - grow, right: rect.right + grow, bottom: rect.bottom + grow },
          viewport: { left: 0, top: 0, right: window.innerWidth, bottom: window.innerHeight },
          scrollers: [],
          inside: false,
        };
      });
    }

    /** S9: the focus order, the ring at every stop, and Enter and Space on a copy button. */
    test('S9: the stops come in order, each draws the ring, and Enter and Space copy', async ({ page }) => {
      try {
        await page.setViewportSize({ width: 1280, height: 600 });
        await page.goto(splashPath());
        const order = ['#ocu-user', 'Copy user name', '#ocu-pass', 'Copy password', SUBMIT, 'Copy Visual Trace user name', 'Copy Visual Trace password', INSTALL];
        for (const expected of order) {
          await page.keyboard.press('Tab');
          expect(await stopName(page), `the next stop is ${expected}`).toBe(expected);
          const reading = expected.startsWith('#') ? await readInputBox(page) : await readFocus(page);
          expect(reading, `${expected} has a ring to read`).not.toBeNull();
          await expectRing(page, reading as Reading, expected);
          expectRingInside(reading as Reading, expected);
        }
        expect(await tokenColor(page, '--focus'), 'the focus colour is a token').toBeTruthy();

        // Enter and Space on a copy button copy.
        await copyButton(page, 'Copy user name').focus();
        await page.evaluate(() => navigator.clipboard.writeText(''));
        await page.keyboard.press('Enter');
        await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()), { message: 'Enter copies' }).toBe(demo().user);
        await page.evaluate(() => navigator.clipboard.writeText(''));
        await page.keyboard.press('Space');
        await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()), { message: 'Space copies' }).toBe(demo().user);
      } finally {
        await signOutGroup(page);
      }
    });
  });

  /** S10: the response's envelope, and no violation in the browser. */
  test('S10: the policy pins the one style and the one script by hash, and the page loads nothing else', async ({ page }) => {
    try {
      const violations = watchViolations(page);
      const answer = await page.request.get(splashPath());
      expect(answer.status()).toBe(200);
      expect(answer.headers()['content-type']).toContain('text/html');
      const body = await answer.text();
      expect(body.match(/<style>/g)?.length, 'one inline style').toBe(1);
      expect(body.match(/<script>/g)?.length, 'one inline script').toBe(1);
      expect(body).not.toContain('<app-root');
      expect(body).not.toMatch(/ style=/i);
      expect(body).not.toContain('<script src');
      expect(body).not.toMatch(/<link[^>]*stylesheet/i);
      const style = /<style>([\s\S]*?)<\/style>/.exec(body)?.[1] ?? '';
      const script = /<script>([\s\S]*?)<\/script>/.exec(body)?.[1] ?? '';
      expect(style.length, 'the style is the splash stylesheet').toBeGreaterThan(1000);
      expect(script.length, 'the script is the splash script').toBeGreaterThan(500);
      expect(answer.headers()['content-security-policy']).toBe(
        `default-src 'none'; script-src 'sha256-${sha256(script)}'; style-src 'sha256-${sha256(style)}'; ` +
          "img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      );
      expect(answer.headers()['cache-control']).toBe('no-store');

      const allowed = new Set<string>([...SIGN_IN_IMAGES.map((image) => `/ocutalon/${image}`), README_URL]);
      const references: string[] = [];
      for (const attribute of ['src', 'srcset', 'href']) {
        for (const match of body.matchAll(new RegExp(`\\s${attribute}="([^"]*)"`, 'g'))) {
          for (const part of (match[1] ?? '').split(',')) {
            const value = part.trim().split(/\s+/)[0] ?? '';
            if (value !== '') references.push(value);
          }
        }
      }
      expect(references.length, 'the page references its images and the README').toBeGreaterThan(5);
      expect(references.filter((reference) => !allowed.has(reference)), 'every src, srcset and href is one of the five images or the README link').toEqual([]);

      // The browser draws and runs it without a violation.
      await page.goto(splashPath());
      await expect(submitButton(page)).toBeVisible();
      await expect(page.locator('#ocu-countdown')).not.toHaveText('');
      await copyButton(page, 'Copy user name').click();
      expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
    } finally {
      await signOutGroup(page);
    }
  });
});

test.describe('QA (Story 16.2): the refusal, and the first screen at 1280x600', () => {
  /** The policy and the cache header that a response to this page must carry, over the hashes of the blocks of its own body. */
  function expectEnvelope(headers: Record<string, string>, body: string, what: string): void {
    const style = /<style>([\s\S]*?)<\/style>/.exec(body)?.[1] ?? '';
    const script = /<script>([\s\S]*?)<\/script>/.exec(body)?.[1] ?? '';
    expect(body.match(/<style>/g)?.length, `${what}: one inline style`).toBe(1);
    expect(body.match(/<script>/g)?.length, `${what}: one inline script`).toBe(1);
    const policy = headers['content-security-policy'] ?? '';
    expect(policy, `${what}: the splash's policy over its own style and script`).toBe(
      `default-src 'none'; script-src 'sha256-${sha256(script)}'; style-src 'sha256-${sha256(style)}'; ` +
        "img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
    );
    expect(policy.match(/sha256-/g)?.length, `${what}: exactly one script hash and one style hash`).toBe(2);
    expect(policy, `${what}: no unsafe keyword`).not.toMatch(/unsafe-/);
    expect(headers['cache-control'], `${what}: no-store`).toBe('no-store');
  }

  /** S6b: a refusal of a typed name that holds markup (QA, the typed-name half of AC 3 that S6 cannot tell from the prefilled name). */
  test('S6b: a refused name is kept exactly and written escaped, the answer is under the same hashed policy, and the error is on the first screen', async ({ page }) => {
    try {
      await page.setViewportSize({ width: 1280, height: 600 });
      const violations = watchViolations(page);
      const marker = `pwned-${probe()}`;
      const typed = `x"><b id="${marker}">&'`;
      const answer = await signInFromSplash(page, typed, `wrong-${probe()}`, splashPath());
      expect(answer.status(), 'the refusal is a page, not an error').toBe(200);
      expectEnvelope(answer.headers(), await answer.text(), 'the refusal');

      await expect(page.locator('#ocu-error')).toHaveText(WRONG);
      await expect(page.locator(`[id="${marker}"]`), 'the typed markup was not made an element').toHaveCount(0);
      await expect(userInput(page), 'the user field holds exactly what was typed, not the published name').toHaveValue(typed);
      await expect(passwordInput(page), 'the password field is empty').toHaveValue('');
      expect(await page.evaluate(() => document.activeElement?.id), 'the error has the focus').toBe('ocu-error');
      const ring = await readFocus(page);
      expect(ring, 'the focused error has a ring to read').not.toBeNull();
      await expectRing(page, ring as Reading, 'the focused error');
      const error = await box(page.locator('#ocu-error'));
      expect(error.top, 'the error is on the screen: top').toBeGreaterThanOrEqual(0);
      expect(error.bottom, 'the error is on the screen: bottom').toBeLessThanOrEqual(600);
      expect(await page.locator('script:not([src])').count(), 'still one script').toBe(1);
      expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
    } finally {
      await signOutGroup(page);
    }
  });

  /** S8b: the button's whole box lies inside the 1280x600 viewport at scroll 0, and the logo of the scheme is drawn (QA, AC 4). */
  test('S8b: at 1280x600 in light and dark the button box lies inside the viewport at scroll 0 and the scheme logo is loaded', async ({ page }) => {
    try {
      await page.setViewportSize({ width: 1280, height: 600 });
      for (const scheme of ['light', 'dark'] as const) {
        await page.emulateMedia({ colorScheme: scheme });
        await page.goto(splashPath());
        await expect(submitButton(page)).toBeVisible();
        const found = await box(submitButton(page));
        expect(await page.evaluate(() => window.scrollY), `${scheme}: the page is not scrolled`).toBe(0);
        expect(found.top, `${scheme}: the button's top is inside`).toBeGreaterThanOrEqual(0);
        expect(found.left, `${scheme}: the button's left is inside`).toBeGreaterThanOrEqual(0);
        expect(found.right, `${scheme}: the button's right is inside`).toBeLessThanOrEqual(1280);
        expect(found.bottom, `${scheme}: the button's bottom is inside`).toBeLessThanOrEqual(600);
        const logo = await page.getByRole('img', { name: 'OcuTalon', exact: true }).evaluate((img) => ({
          drawn: (img as HTMLImageElement).complete && (img as HTMLImageElement).naturalWidth > 0,
          src: (img as HTMLImageElement).currentSrc,
        }));
        expect(logo.drawn, `${scheme}: the logo file loaded`).toBe(true);
        expect(logo.src, `${scheme}: the logo of the scheme is the one used`).toContain(`OcuTalon-Logo-${scheme}-`);
      }
    } finally {
      await signOutGroup(page);
    }
  });
});
