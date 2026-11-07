import { afterNextRender, DestroyRef, effect, inject, untracked } from '@angular/core';

import { windowBound } from './more-to-try-view';

/** The chat's list, whose height above its floor is the room that the panel's window may take. */
const CHAT_LIST = 'app-chat-panel .list';

/** The host's custom property that the panel's window reads as its tallest height. */
const MAX_PROPERTY = '--more-max';

/**
 * Keeps the "Other things to try" panel's window within the room the page leaves (Story 4.11; the Planner, 2026-11-07): it writes the
 * bound that windowBound gives to the host's `--more-max`, from the panel's height and the chat list's height as the page has them
 * now, so the chat keeps `floor` whatever the fonts, the banners and the viewport make of the rest. It measures once after the first
 * render, whenever the floor changes, and once a frame while the page, the list or the panel changes size or the window is resized,
 * and writes only when the bound moved by a pixel or more. Where the panel is a scroller of its own (the page fills the viewport)
 * and its window is already as short as it may be while the chat is still under its floor, the room is too small for the panel at
 * all: it calls `tight` once for that state. It reads and writes no state of the page's data, and moves no focus. Call it in an
 * injection context: it ends with the injector's owner.
 */
export function keepRoom(host: HTMLElement, floor: () => number, tight: () => void): void {
  const destroyRef = inject(DestroyRef);
  let written: number | undefined;
  let squeezed = false;

  const measure = (): void => {
    const group = host.querySelector<HTMLElement>('.group');
    const list = document.querySelector<HTMLElement>(CHAT_LIST);
    if (group === null || list === null) {
      return;
    }
    const chat = list.getBoundingClientRect().height;
    const bound = windowBound(group.getBoundingClientRect().height, chat, floor());
    if (written === undefined || Math.abs(bound - written) >= 1) {
      written = bound;
      host.style.setProperty(MAX_PROPERTY, `${bound}px`);
    } else if (!squeezed && chat < floor() - 1 && getComputedStyle(group).overflowY === 'auto') {
      squeezed = true;
      tight();
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
