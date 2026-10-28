import type { Locator, Page } from '@playwright/test';

/**
 * Readings that the browser specs of the chat share: a time as the page shows it, a text with its whitespace collapsed, the
 * colour of a token as the page paints it, the scroll position of the chat list, the texts that the polite announcer read (and
 * when), and how often focus moved. None of them needs a stack.
 */

/**
 * A time as the page shows it for a locale and a zone (en-US and Asia/Kolkata unless given), with the narrow no-break space read as a
 * space. The page's hour is the locale's numeric hour, so in en-GB a time before ten has no leading zero (9:05, 0:28).
 */
export const clock = (iso: string, locale = 'en-US', timeZone = 'Asia/Kolkata'): string =>
  new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(new Date(iso)).replace(/\u202F/g, ' ');

/** A text with its whitespace collapsed and the narrow no-break space read as a space. */
export const plain = (text: string | null): string => (text ?? '').replace(/\u202F/g, ' ').replace(/\s+/g, ' ').trim();

/** The computed colour of a token, as the page paints it. */
export function tokenColor(page: Page, token: string): Promise<string> {
  return page.evaluate((name) => {
    const probe = document.createElement('span');
    probe.style.color = `var(${name})`;
    document.body.append(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  }, token);
}

/** The distance in px between the bottom of the list's content and the bottom of its view. */
export const fromBottom = (list: Locator): Promise<number> => list.evaluate((el) => el.scrollHeight - el.scrollTop - el.clientHeight);

/**
 * Scrolls the list to its top or its bottom, as the user would, and returns once the page has delivered the scroll event: the
 * event fires in the rendering step that precedes the animation-frame callbacks of the same frame, so the panel has measured
 * the new position by then. A test that changes the page's content next acts on a list the panel knows is scrolled, on a host
 * of any speed.
 */
export async function scrollListTo(list: Locator, where: 'top' | 'bottom'): Promise<void> {
  await list.evaluate(
    (el, target) =>
      new Promise<void>((resolve) => {
        el.scrollTop = target === 'top' ? 0 : el.scrollHeight;
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
      }),
    where,
  );
}

/**
 * Before the page's scripts run: records every text that the polite announcer's live region receives (each node added to
 * it), as window.announced, so a test can count how often a message was announced, and the page's clock (performance.now())
 * when each text landed, as window.announcedAt, in the same order.
 */
export async function recordAnnouncements(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const announced: string[] = [];
    const announcedAt: number[] = [];
    (window as unknown as { announced: string[]; announcedAt: number[] }).announced = announced;
    (window as unknown as { announced: string[]; announcedAt: number[] }).announcedAt = announcedAt;
    new MutationObserver((records) => {
      for (const record of records) {
        if (!(record.target instanceof HTMLElement) || !record.target.classList.contains('cdk-live-announcer-element')) continue;
        for (const node of Array.from(record.addedNodes)) {
          if (node.textContent) {
            announced.push(node.textContent);
            announcedAt.push(performance.now());
          }
        }
      }
    }).observe(document, { subtree: true, childList: true });
  });
}

/**
 * How many of the recorded announcements hold this text, alone or joined with others (the announcer speaks the messages of one update
 * as one text). A burst spoken as "{n} new updates" holds none of its texts: a case that says nothing is announced reads announcedTexts.
 */
export const announcements = (page: Page, text: string): Promise<number> =>
  page.evaluate((wanted) => (window as unknown as { announced: string[] }).announced.filter((entry) => entry.includes(wanted)).length, text);

/** How many announcements were recorded, whatever their text. */
export const announcementCount = (page: Page): Promise<number> => page.evaluate(() => (window as unknown as { announced: string[] }).announced.length);

/** Every text that the announcer's live region received, in order. */
export const announcedTexts = (page: Page): Promise<string[]> => page.evaluate(() => [...(window as unknown as { announced: string[] }).announced]);

/** When each of those texts landed, on the page's clock (ms), in the same order. */
export const announcedTimes = (page: Page): Promise<number[]> => page.evaluate(() => [...(window as unknown as { announcedAt: number[] }).announcedAt]);

/** Counts every focusin of the page from now on, in window.focusins; a second call starts the count again without a second listener. */
export async function countFocusins(page: Page): Promise<void> {
  await page.evaluate(() => {
    const target = window as unknown as { focusins?: number; countingFocusins?: boolean };
    target.focusins = 0;
    if (target.countingFocusins) return;
    target.countingFocusins = true;
    document.addEventListener('focusin', () => {
      target.focusins = (target.focusins ?? 0) + 1;
    });
  });
}

/** How many focusins countFocusins has counted; it fails when the page is not counting, so that a count of 0 is a real reading. */
export async function focusinCount(page: Page): Promise<number> {
  const count = await page.evaluate(() => (window as unknown as { focusins?: number }).focusins);
  if (typeof count !== 'number') throw new Error('the page is not counting focusins: countFocusins was not called on this document');
  return count;
}
