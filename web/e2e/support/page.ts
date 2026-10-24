import type { Locator, Page } from '@playwright/test';

/**
 * Readings that the browser specs of the chat share: a time as the page shows it, a text with its whitespace collapsed, the
 * colour of a token as the page paints it, the scroll position of the chat list, and the texts that the polite announcer read.
 * None of them needs a stack.
 */

/** A time as the page shows it for the Asia/Kolkata zone and the en-US locale, with the narrow no-break space read as a space. */
export const clock = (iso: string): string =>
  new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Kolkata' }).format(new Date(iso)).replace(/\u202F/g, ' ');

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
 * it), as window.announced, so a test can count how often a message was announced.
 */
export async function recordAnnouncements(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const announced: string[] = [];
    (window as unknown as { announced: string[] }).announced = announced;
    new MutationObserver((records) => {
      for (const record of records) {
        if (!(record.target instanceof HTMLElement) || !record.target.classList.contains('cdk-live-announcer-element')) continue;
        for (const node of Array.from(record.addedNodes)) {
          if (node.textContent) announced.push(node.textContent);
        }
      }
    }).observe(document, { subtree: true, childList: true });
  });
}

/** How many times the recorded announcements hold exactly this text. */
export const announcements = (page: Page, text: string): Promise<number> =>
  page.evaluate((wanted) => (window as unknown as { announced: string[] }).announced.filter((entry) => entry === wanted).length, text);
