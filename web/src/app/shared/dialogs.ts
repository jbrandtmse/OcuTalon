import { Dialog, type DialogRef } from '@angular/cdk/dialog';
import type { ComponentType } from '@angular/cdk/overlay';
import { Injectable, inject } from '@angular/core';

import { Popovers } from './popover';

/** How a dialog opens. */
export interface DialogOptions {
  /** The id of the heading inside the dialog that names it; focus starts on the first heading. */
  labelledBy: string;
  /** The control that opened the dialog: focus returns to it when the dialog closes. */
  restoreFocus: HTMLElement;
  /**
   * Where focus starts: the CDK's target ('first-tabbable', 'first-heading' or 'dialog') or a CSS selector inside the dialog. The default
   * is the first heading (UX-DR38); the online demo's Sign out dialog starts on Cancel (UX-DR30).
   */
  autoFocus?: string;
}

/**
 * The page's modal dialogs over the CDK dialog. Dialogs are at most one deep: opening one first closes every open
 * popover and any dialog that is open. A press on the backdrop or Escape closes the dialog. Focus starts on the first heading unless
 * the options name another place.
 */
@Injectable({ providedIn: 'root' })
export class Dialogs {
  private readonly dialog = inject(Dialog);
  private readonly popovers = inject(Popovers);

  open<C>(component: ComponentType<C>, options: DialogOptions): DialogRef<unknown, C> {
    this.popovers.closeAll();
    this.dialog.closeAll();
    return this.dialog.open<unknown, unknown, C>(component, {
      role: 'dialog',
      ariaModal: true,
      ariaLabelledBy: options.labelledBy,
      autoFocus: options.autoFocus ?? 'first-heading',
      restoreFocus: options.restoreFocus,
      hasBackdrop: true,
      backdropClass: 'app-dialog-scrim',
      panelClass: 'app-dialog',
    });
  }
}
