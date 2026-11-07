import { afterNextRender, DestroyRef, effect, inject, untracked } from '@angular/core';

import { CHAT_FLOOR, windowBound } from './more-to-try-view';

/** The chat's list, whose height above its floor is the room that the panel's window may take. */
const CHAT_LIST = 'app-chat-panel .list';

/** The host's custom property that the panel's window reads as its tallest height. */
const MAX_PROPERTY = '--more-max';

/**
 * Keeps the "Other things to try" panel's window within the room the page leaves (Story 4.11): it writes the
 * bound that windowBound gives to the host's `--more-max`, from the panel's height and the chat list's height as the page has them
 * now, so the chat keeps `floor` whatever the fonts, the banners and the viewport make of the rest. It measures once after the first
 * render, whenever the floor changes, and once a frame while the page, the list or the panel changes size or the window is resized,
 * and writes only when the bound moved by a pixel or more. Where the panel is a scroller of its own (the page fills the viewport)
 * and its window is already as short as it may be while the chat is still under its floor, the room is too small for the panel at
 * all: it calls `tight` once for that state (implement-stage decision 13 kept by the lead's ruling, veto window, inbox U-299). In the compact band (the Planner, 2026-11-07) the chat's floor holds there too: the
 * list gets a `min-height` of the floor, so the page, not the chat, gives way and scrolls vertically (never sideways), and the
 * `min-height` is removed again when the band is left and when the panel goes. It reads and writes no state of the page's data,
 * and moves no focus. Call it in an injection context: it ends with the injector's owner.
 */
export function keepRoom(host: HTMLElement, floor: () => number, tight: () => void): void {
  const destroyRef = inject(DestroyRef);
  let written: number | undefined;
  let squeezed = false;
  let held: HTMLElement | undefined;

  const release = (): void => {
    held?.style.removeProperty('min-height');
    held = undefined;
  };
  destroyRef.onDestroy(release);

  const measure = (): void => {
    const group = host.querySelector<HTMLElement>('.group');
    const list = document.querySelector<HTMLElement>(CHAT_LIST);
    if (group === null || list === null) {
      return;
    }
    if (held !== undefined && floor() > CHAT_FLOOR.compact) {
      release();
    }
    const chat = list.getBoundingClientRect().height;
    const bound = windowBound(group.getBoundingClientRect().height, chat, floor());
    if (written === undefined || Math.abs(bound - written) >= 1) {
      written = bound;
      host.style.setProperty(MAX_PROPERTY, `${bound}px`);
    } else if (chat < floor() - 1 && getComputedStyle(group).overflowY === 'auto') {
      if (floor() <= CHAT_FLOOR.compact) {
        held = list;
        list.style.minHeight = `${floor()}px`;
      }
      if (!squeezed) {
        squeezed = true;
        tight();
      }
    }
  };

  effect(() => {
    floor();
    untracked(measure);
  });

  afterNextRender(() => {
    let frame = 0;
    const observed = new Set<Element>();
    const watch = (): void => {
      for (const element of [document.documentElement, host, document.querySelector(CHAT_LIST)]) {
        if (element !== null && !observed.has(element)) {
          observed.add(element);
          observer.observe(element);
        }
      }
    };
    const later = (): void => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        watch();
        measure();
      });
    };
    const observer = new ResizeObserver(later);
    watch();
    window.addEventListener('resize', later);
    destroyRef.onDestroy(() => {
      cancelAnimationFrame(frame);
      window.removeEventListener('resize', later);
      observer.disconnect();
    });
    measure();
  });
}
