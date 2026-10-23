import { Overlay, type OverlayRef } from '@angular/cdk/overlay';
import { ComponentPortal } from '@angular/cdk/portal';
import { ChangeDetectionStrategy, Component, DOCUMENT, DestroyRef, Directive, ElementRef, inject, input } from '@angular/core';

/** How long the pointer rests on the host before the tooltip shows. */
export const TOOLTIP_DELAY_MS = 300;

/** How long a tooltip waits after the pointer leaves, so that the pointer can cross the gap onto the tooltip. */
const LEAVE_GRACE_MS = 100;

/** The tooltip's bubble. It is hidden from assistive technology: the text reaches assistive technology through the host's name or its description. */
@Component({
  selector: 'app-tooltip',
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { 'aria-hidden': 'true' },
  template: `{{ text() }}`,
  styles: `
    :host {
      display: block;
      max-width: 240px;
      padding: var(--space-1) var(--space-2);
      background: var(--tooltip-background);
      color: var(--tooltip-foreground);
      border-radius: var(--tooltip-radius);
      font-family: var(--font-ui);
      font-size: var(--tooltip-typography-font-size);
      font-weight: var(--tooltip-typography-font-weight);
      line-height: var(--tooltip-typography-line-height);
    }
  `,
})
export class TooltipBubble {
  readonly text = input.required<string>();
}

/**
 * A tooltip for a control, for the pointer only: it reacts to a mouse or a pen resting on the host, never to focus.
 * It shows after 300 ms, stays while the host or the tooltip is hovered, and hides when the pointer leaves, when
 * the host is pressed, or on Escape, which does not move focus. A pointer that leaves within the 300 ms shows nothing,
 * and none shows while the host's popup is open. The host carries the same text as its name, or the text also reaches assistive
 * technology another way (the strip's description).
 */
@Directive({
  selector: '[appTooltip]',
  host: {
    '(pointerenter)': 'onEnter($event)',
    '(pointerleave)': 'scheduleHide()',
    '(pointerdown)': 'hide()',
  },
})
export class Tooltip {
  readonly text = input.required<string>({ alias: 'appTooltip' });

  private readonly overlay = inject(Overlay);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef).nativeElement;
  private readonly document = inject(DOCUMENT);
  private showTimer: number | undefined;
  private hideTimer: number | undefined;
  private overlayRef: OverlayRef | undefined;

  constructor() {
    inject(DestroyRef).onDestroy(() => this.hide());
  }

  protected onEnter(event: PointerEvent): void {
    if (event.pointerType !== 'mouse' && event.pointerType !== 'pen') {
      return;
    }
    // While the host's own popup is open (a menu trigger with aria-expanded true), a tooltip would cover the popup.
    if (this.host.getAttribute('aria-expanded') === 'true') {
      return;
    }
    this.cancelHide();
    if (this.overlayRef || this.showTimer !== undefined) {
      return;
    }
    this.document.addEventListener('keydown', this.onKeydown);
    this.showTimer = window.setTimeout(() => {
      this.showTimer = undefined;
      this.show();
    }, TOOLTIP_DELAY_MS);
  }

  /** A pointer that leaves before the tooltip shows cancels it; a shown tooltip waits the grace for the pointer. */
  protected scheduleHide(): void {
    if (this.showTimer !== undefined) {
      this.hide();
      return;
    }
    this.cancelHide();
    this.hideTimer = window.setTimeout(() => this.hide(), LEAVE_GRACE_MS);
  }

  protected hide(): void {
    this.cancelHide();
    if (this.showTimer !== undefined) {
      window.clearTimeout(this.showTimer);
      this.showTimer = undefined;
    }
    this.document.removeEventListener('keydown', this.onKeydown);
    this.overlayRef?.dispose();
    this.overlayRef = undefined;
  }

  private readonly onKeydown = (event: KeyboardEvent): void => {
    if (event.key === 'Escape') {
      this.hide();
    }
  };

  private cancelHide(): void {
    if (this.hideTimer !== undefined) {
      window.clearTimeout(this.hideTimer);
      this.hideTimer = undefined;
    }
  }

  private show(): void {
    const overlayRef = this.overlay.create({
      positionStrategy: this.overlay
        .position()
        .flexibleConnectedTo(this.host)
        .withPositions([
          { originX: 'center', originY: 'bottom', overlayX: 'center', overlayY: 'top', offsetY: 6 },
          { originX: 'center', originY: 'top', overlayX: 'center', overlayY: 'bottom', offsetY: -6 },
        ]),
      scrollStrategy: this.overlay.scrollStrategies.reposition(),
    });
    const bubble = overlayRef.attach(new ComponentPortal(TooltipBubble));
    bubble.setInput('text', this.text());
    bubble.location.nativeElement.addEventListener('pointerenter', () => this.cancelHide());
    bubble.location.nativeElement.addEventListener('pointerleave', () => this.scheduleHide());
    this.overlayRef = overlayRef;
  }
}
