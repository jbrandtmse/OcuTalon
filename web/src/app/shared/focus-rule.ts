import { afterNextRender, type Injector } from '@angular/core';

import type { Popovers } from './popover';

/** Where focus goes when nothing nearer takes it: the page's main region. */
const MAIN_REGION = 'main.main';

/** What a rule knows about the item that held focus when an update removed the focused element. */
export interface LostFocus {
  /** The host whose update it was. */
  host: HTMLElement;
  /** The item that held focus, as it was before the update; it is detached when the update removed it. */
  item: Element;
  /** The item's key. */
  key: string;
  /** The keys of the host's items before the update, in DOM order. */
  before: readonly string[];
  /** The keys of the host's items after the update, in DOM order. */
  after: readonly string[];
}

/**
 * Where a host's focus goes when an update removes the element that holds it. All selectors are matched under the host.
 * - `within` limits the rule to focus inside the first element it matches; focus elsewhere in the host is left alone.
 * - `item` is the selector of the host's items, `keyOf` gives an item's key and `whenGone` the element that takes focus when the
 *   item's key is no longer there (null for none). A rule with no `item` has none of the three.
 */
export interface FocusRule {
  within?: string;
  item?: string;
  keyOf?: (item: Element) => string;
  whenGone?: (lost: LostFocus) => HTMLElement | null;
}

/** The keys of the host's items, in DOM order, and the items. */
function itemsOf(host: HTMLElement, rule: FocusRule): { items: Element[]; keys: string[] } {
  const items = rule.item === undefined ? [] : Array.from(host.querySelectorAll(rule.item));
  return { items, keys: items.map((one) => rule.keyOf?.(one) ?? '') };
}

/**
 * The page's one focus rule (NFR-25, UX-DR126, UX-DR131). A host calls it from an effect that runs before the host renders again.
 * - Before the render: the focused element is document.activeElement, or the trigger of the open popover that holds focus
 *   (Popovers.triggerOf), since a popover's focus is its trigger's. If that element is not in the host, or not in the rule's
 *   `within`, nothing happens. Otherwise the call records the item that holds it (the closest match of `rule.item`), that item's
 *   key and the keys of all the items.
 * - After the render, only if focus was lost (document.activeElement is null or the body): when the item's key is still there,
 *   focus goes to that item, the replacement in place or the nearest container; when the key is gone, to `rule.whenGone`'s
 *   element; when that is null, or there was no item, to the main region. Every move is without scrolling.
 * - Focus that is still on an element in the page is never moved.
 */
export function keepFocus(host: HTMLElement, injector: Injector, popovers: Popovers, rule: FocusRule): void {
  const active = document.activeElement;
  const focused = active instanceof Element ? (popovers.triggerOf(active) ?? active) : null;
  if (focused === null || !host.contains(focused)) {
    return;
  }
  if (rule.within !== undefined) {
    const within = focused.closest(rule.within);
    if (within === null || !host.contains(within)) {
      return;
    }
  }
  const held = rule.item === undefined ? null : focused.closest(rule.item);
  const item = held !== null && host.contains(held) ? held : undefined;
  const before = item === undefined ? [] : itemsOf(host, rule).keys;
  const key = item === undefined ? '' : (rule.keyOf?.(item) ?? '');
  afterNextRender(
    () => {
      const now = document.activeElement;
      if (now !== null && now !== document.body) {
        return;
      }
      let target: Element | null = null;
      if (item !== undefined) {
        const { items, keys } = itemsOf(host, rule);
        const at = keys.indexOf(key);
        target = at >= 0 ? (items[at] ?? null) : (rule.whenGone?.({ host, item, key, before, after: keys }) ?? null);
      }
      const element = target ?? document.querySelector(MAIN_REGION);
      if (element instanceof HTMLElement) {
        element.focus({ preventScroll: true });
      }
    },
    { injector },
  );
}
