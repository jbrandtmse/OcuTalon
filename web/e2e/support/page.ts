import type { Locator, Page } from '@playwright/test';

/**
 * Readings that the browser specs of the chat share: a time as the page shows it, a text with its whitespace collapsed, the
 * colour of a token as the page paints it, and the scroll position of the chat list. None of them needs a stack.
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
