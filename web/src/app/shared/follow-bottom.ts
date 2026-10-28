/**
 * The follow rule of a feed that scrolls on its own (the chat list, the simulated phone's feed): the feed is at the bottom when it is
 * within this many px of it, and new content then keeps it there.
 */
export const BOTTOM_SLACK_PX = 24;

/** True when the scroller is within `slack` px of its bottom. */
export function atBottom(element: { scrollHeight: number; scrollTop: number; clientHeight: number }, slack: number = BOTTOM_SLACK_PX): boolean {
  return element.scrollHeight - element.scrollTop - element.clientHeight <= slack;
}
