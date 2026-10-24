import { Overlay, type OverlayRef } from '@angular/cdk/overlay';
import { TemplatePortal } from '@angular/cdk/portal';
import { Injectable, Injector, afterNextRender, inject, type TemplateRef, type ViewContainerRef } from '@angular/core';
import { Subject, type Observable } from 'rxjs';

/** What a popover shows and what it hangs from. */
export interface PopoverOptions {
  /** The control that opened it: the popover sits under it, and focus returns to it when the popover closes. */
  trigger: HTMLElement;
  /** The popover's content. */
  content: TemplateRef<unknown>;
  viewContainerRef: ViewContainerRef;
  /** The id of the heading inside the content that names the popover. */
  labelledBy: string;
}

/** An open popover. */
export class PopoverRef {
  private readonly done = new Subject<void>();
  private opened = true;
  private readonly onClose: () => void;
  private readonly pane: HTMLElement;

  /** The control that opened the popover. */
  readonly trigger: HTMLElement;

  /** Emits once, when the popover has closed. */
  readonly closed: Observable<void> = this.done.asObservable();

  constructor(trigger: HTMLElement, pane: HTMLElement, onClose: () => void) {
    this.trigger = trigger;
    this.pane = pane;
    this.onClose = onClose;
  }

  /** Whether the element is inside the popover's panel. */
  holds(element: Element): boolean {
    return this.pane.contains(element);
  }

  /** Whether the popover is still open. */
  get isOpen(): boolean {
    return this.opened;
  }

  /** Closes the popover and returns focus to the control that opened it. */
  close(): void {
    if (!this.opened) {
      return;
    }
    this.opened = false;
    this.onClose();
    if (this.trigger.isConnected) {
      this.trigger.focus();
    }
    this.done.next();
    this.done.complete();
  }
}

/**
 * Non-modal popovers over the CDK overlay, and the registry of the ones that are open. A popover's container is a
 * dialog named by its heading, without aria-modal. On open, focus goes to its first focusable control. Escape, a
 * press outside, or focus leaving both the trigger and the panel closes it and returns focus to the trigger.
 */
@Injectable({ providedIn: 'root' })
export class Popovers {
  private readonly overlay = inject(Overlay);
  private readonly injector = inject(Injector);
  private readonly open = new Set<PopoverRef>();

  /** Opens a popover under its trigger; any popover that is open closes first. */
  show(options: PopoverOptions): PopoverRef {
    this.closeAll();
    const { trigger } = options;
    const overlayRef = this.overlay.create({
      positionStrategy: this.overlay
        .position()
        .flexibleConnectedTo(trigger)
        .withPositions([
          { originX: 'end', originY: 'bottom', overlayX: 'end', overlayY: 'top', offsetY: 4 },
          { originX: 'end', originY: 'top', overlayX: 'end', overlayY: 'bottom', offsetY: -4 },
        ]),
      scrollStrategy: this.overlay.scrollStrategies.reposition(),
      panelClass: 'app-popover',
    });
    overlayRef.attach(new TemplatePortal(options.content, options.viewContainerRef));
    const pane = overlayRef.overlayElement;
    pane.setAttribute('role', 'dialog');
    pane.setAttribute('aria-labelledby', options.labelledBy);

    const cleanups: Array<() => void> = [];
    const ref = new PopoverRef(trigger, pane, () => {
      this.open.delete(ref);
      cleanups.forEach((cleanup) => cleanup());
      overlayRef.dispose();
    });
    this.open.add(ref);

    const escape = overlayRef.keydownEvents().subscribe((event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        ref.close();
      }
    });
    // A press on the trigger itself is the trigger's to handle, so that it can toggle the popover.
    const outside = overlayRef.outsidePointerEvents().subscribe((event) => {
      if (!(event.target instanceof Node) || !trigger.contains(event.target)) {
        ref.close();
      }
    });
    cleanups.push(() => escape.unsubscribe(), () => outside.unsubscribe());
    cleanups.push(this.closeOnFocusLeave(trigger, pane, ref));

    // The render this waits for may come after the popover has closed (Esc in the task that opened it): a closed popover's overlay is
    // disposed, so it has no panel to focus into, and focus is already back on the trigger.
    afterNextRender(
      () => {
        if (ref.isOpen) {
          this.focusFirst(overlayRef);
        }
      },
      { injector: this.injector },
    );
    return ref;
  }

  /**
   * The trigger of the open popover whose panel contains the element, else undefined. Focus inside a popover counts as focus on its
   * trigger (the focus rule of shared/focus-rule.ts), so a trigger that leaves the page with its popover open is a lost focus.
   */
  triggerOf(element: Element): HTMLElement | undefined {
    for (const ref of this.open) {
      if (ref.holds(element)) {
        return ref.trigger;
      }
    }
    return undefined;
  }

  /**
   * True while any popover is open. Esc closes the topmost layer only (Story 2.14): a disclosure whose Esc handler runs first on
   * the way up asks this before it collapses, so the Esc that closes a popover (the CDK's body-level handler, which runs after the
   * element's own) leaves the disclosure that holds the popover's trigger as it is.
   */
  hasOpen(): boolean {
    return this.open.size > 0;
  }

  /** Closes every open popover. */
  closeAll(): void {
    for (const ref of [...this.open]) {
      ref.close();
    }
  }

  /**
   * Closes the popover when focus ends up outside both the trigger and the panel. The check runs after the focus
   * change has settled, and not while the browser window itself has lost focus (the popover waits for it).
   */
  private closeOnFocusLeave(trigger: HTMLElement, pane: HTMLElement, ref: PopoverRef): () => void {
    let pending: number | undefined;
    const onFocusOut = (): void => {
      window.clearTimeout(pending);
      pending = window.setTimeout(() => {
        const active = document.activeElement;
        const inside = active !== null && (trigger.contains(active) || pane.contains(active));
        if (!inside && document.hasFocus()) {
          ref.close();
        }
      });
    };
    trigger.addEventListener('focusout', onFocusOut);
    pane.addEventListener('focusout', onFocusOut);
    return () => {
      window.clearTimeout(pending);
      trigger.removeEventListener('focusout', onFocusOut);
      pane.removeEventListener('focusout', onFocusOut);
    };
  }

  /** Moves focus to the first focusable control of the panel. */
  private focusFirst(overlayRef: OverlayRef): void {
    const first = overlayRef.overlayElement.querySelector<HTMLElement>(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    );
    first?.focus();
  }
}
