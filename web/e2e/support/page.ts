import type { Page } from '@playwright/test';

/**
 * Readings that the browser specs of the chat share: a time as the page shows it, a text with its whitespace collapsed, and the
 * colour of a token as the page paints it. None of them needs a stack.
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
