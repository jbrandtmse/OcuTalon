import { Injectable, signal } from '@angular/core';

/** The theme the user chose: System follows the operating system. */
export type ThemeChoice = 'system' | 'light' | 'dark';

/** The localStorage key of the choice. */
export const THEME_KEY = 'ocutalon.theme';

const CHOICES: readonly ThemeChoice[] = ['system', 'light', 'dark'];

/** The stored choice; System when nothing valid is stored or the storage cannot be read. */
export function storedTheme(): ThemeChoice {
  try {
    const value = window.localStorage.getItem(THEME_KEY);
    return CHOICES.find((choice) => choice === value) ?? 'system';
  } catch {
    return 'system';
  }
}

/** Puts the choice on the root element: System removes data-theme, Light and Dark set it. */
export function applyTheme(choice: ThemeChoice, root: HTMLElement = document.documentElement): void {
  if (choice === 'system') {
    root.removeAttribute('data-theme');
  } else {
    root.setAttribute('data-theme', choice);
  }
}

/**
 * The page's theme. A choice applies at once and is remembered in localStorage; when the storage fails the choice
 * still holds for this page.
 */
@Injectable({ providedIn: 'root' })
export class Theme {
  /** The current choice. */
  readonly choice = signal<ThemeChoice>(storedTheme());

  set(choice: ThemeChoice): void {
    this.choice.set(choice);
    applyTheme(choice);
    try {
      window.localStorage.setItem(THEME_KEY, choice);
    } catch {
      /* The choice holds for this page only. */
    }
  }
}
