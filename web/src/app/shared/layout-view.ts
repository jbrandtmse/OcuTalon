/**
 * The page's width bands and the strings that go with them (Story 2.15; FR-12, UX-DR20, UX-DR35, UX-DR128, UX-DR137, UX-DR138). A
 * framework-free module: it imports nothing and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - LAYOUT_QUERIES holds the four width queries. Every width `@media` of the page's CSS is one of these strings, and Layout calls
 *   matchMedia with them only. They are range queries, which leave no gap at a fractional width, as zoom gives. The reference band
 *   (1280 to 1439px) is the width where `framed` matches and neither `drawer` nor `wide` does.
 * - LAYOUT_TEXTS holds the fixed strings: the Status button, the spoken forms of its count, the narrow-window note and its Close name.
 * - statusCount gives the Status button's count pill and its spoken part.
 * - The note's storage keys and the value they hold when their flag is set.
 */

/** The four width queries; each is the whole text of an `@media` condition. */
export const LAYOUT_QUERIES = {
  /** Below 1024px: one column that scrolls as a page. */
  stacked: '(width < 1024px)',
  /** 1024px and wider: the page fills the viewport and each region scrolls on its own. */
  framed: '(width >= 1024px)',
  /** 1024 to 1279px: the rail is a drawer behind the Status button. */
  drawer: '(1024px <= width < 1280px)',
  /** 1440px and wider: the rail is wider. */
  wide: '(width >= 1440px)',
} as const;

/** Every fixed string of the layout, in ASCII. */
export const LAYOUT_TEXTS = {
  status: 'Status',
  approvalsOne: '1 approval request',
  approvalsMany: '{n} approval requests',
  note: 'This page is designed for a wider window. Everything still works.',
  closeNote: 'Close narrow-window note',
} as const;

/** The sessionStorage key that says the narrow-window note was shown in this tab's session. */
export const NOTE_SHOWN_KEY = 'ocutalon.narrowNote.shown';

/** The localStorage key that says the note was closed in this browser. */
export const NOTE_CLOSED_KEY = 'ocutalon.narrowNote.closed';

/** The value both keys hold when their flag is set. */
export const NOTE_FLAG = '1';

/** The Status button's count: the pill's text and the spoken part that follows "Status". */
export interface StatusCount {
  pill: string;
  spoken: string;
}

/**
 * The count of the Status button for n approval requests: none while n is unknown (the snapshot has not loaded, or failed), so that
 * the button never shows a zero that it does not know; otherwise the pill shows n and the spoken part reads "n approval requests".
 */
export function statusCount(n: number | undefined): StatusCount | undefined {
  if (n === undefined) {
    return undefined;
  }
  const spoken = n === 1 ? LAYOUT_TEXTS.approvalsOne : LAYOUT_TEXTS.approvalsMany.replace('{n}', String(n));
  return { pill: String(n), spoken };
}
