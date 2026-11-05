import { DOCUMENT } from '@angular/common';
import { inject } from '@angular/core';
import type { CanDeactivateFn } from '@angular/router';
import { map, take } from 'rxjs';

import { Dialogs } from '../shared/dialogs';
import { UNSAVED_FOCUS, UNSAVED_TEXT_ID, UnsavedDialog } from './unsaved-dialog';

/** What the guard needs of the settings page: whether its section has unsaved changes. */
export interface Unsaved {
  dirty(): boolean;
}

/**
 * Leaving the settings page, or a section of it, by a link or the browser's back, asks first when the section has unsaved changes (Story 33.2;
 * UX-DR32). The guard opens the prompt through Dialogs and lets the navigation go on only when the answer is Leave without saving; Stay, Esc and a
 * press on the backdrop keep the page and its values. Focus returns to the control that held it. A reload or a close of the tab is the browser's own
 * prompt, which the page arms only while it is dirty (SettingsPage).
 */
export const unsavedGuard: CanDeactivateFn<Unsaved> = (page) => {
  if (!page.dirty()) {
    return true;
  }
  const doc = inject(DOCUMENT);
  const opener = (doc.activeElement as HTMLElement | null) ?? doc.body;
  const ref = inject(Dialogs).open(UnsavedDialog, { labelledBy: UNSAVED_TEXT_ID, restoreFocus: opener, autoFocus: UNSAVED_FOCUS });
  return ref.closed.pipe(
    take(1),
    map((answer) => answer === true),
  );
};
