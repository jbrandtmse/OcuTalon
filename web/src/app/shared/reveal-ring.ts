/**
 * Keeps the focus ring of a control at a scroller's edge inside the scroller (Story 2.16, NFR-25). A framework-free module: it
 * imports nothing and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * Chromium and WebKit scroll a focused control into view with the scroller's scroll-padding around it, so its ring is already inside.
 * Firefox leaves a control that sits partly past the scroller's top or bottom edge where it is when Tab reaches it, so the ring is
 * clipped. `revealRing` is called from the scroller's focusin: it moves only that scroller's scrollTop, never smoothly, and never
 * the page or another scroller, so the page's focus rule (focus that does not scroll the page) is not undone. It does nothing for the
 * scroller itself, for a target outside it, and for a scroller that has no overflow.
 *
 * In every engine the ring is kept MARGIN px inside the scroller's client box beyond the scroll-padding, and the scroll is rounded up
 * to whole pixels: an engine that scrolls by whole pixels (WebKit) never leaves a fractional shortfall that clips the ring's last
 * pixel (DW-198).
 */

/** The pixels the ring keeps inside the scroller's edge beyond the scroll-padding. */
const MARGIN = 1;

/** The pixels of a computed length, 0 for `auto` or anything else that is not a length. */
const pixels = (value: string): number => {
  const parsed = parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
};

/**
 * Scrolls the scroller, by the overflow only and in whole pixels, until the target's box grown by the scroller's own scroll-padding (the
 * ring's reach) and MARGIN lies inside the scroller's client box at the top and the bottom.
 */
export function revealRing(scroller: HTMLElement, target: EventTarget | null): void {
  if (!(target instanceof HTMLElement) || target === scroller || !scroller.contains(target) || scroller.scrollHeight <= scroller.clientHeight) {
    return;
  }
  const style = getComputedStyle(scroller);
  const box = scroller.getBoundingClientRect();
  const clientTop = box.top + scroller.clientTop;
  const clientBottom = clientTop + scroller.clientHeight;
  const rect = target.getBoundingClientRect();
  const above = clientTop - (rect.top - pixels(style.scrollPaddingTop) - MARGIN);
  const below = rect.bottom + pixels(style.scrollPaddingBottom) + MARGIN - clientBottom;
  if (above > 0) {
    scroller.scrollBy({ top: -Math.ceil(above), behavior: 'instant' });
  } else if (below > 0) {
    scroller.scrollBy({ top: Math.ceil(below), behavior: 'instant' });
  }
}
