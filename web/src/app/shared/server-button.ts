import { ChangeDetectionStrategy, Component, DestroyRef, inject, input, signal } from '@angular/core';
import { firstValueFrom, isObservable, type Observable } from 'rxjs';

import { Icon } from '../icon/icon';
import { Announcer } from './announcer';
import { BusyState } from './busy-state';
import { InlineNotice } from './inline-notice';

/** The notice under a server button whose call has had no answer for 10 seconds. */
export const BUSY_NOTICE = "Couldn't reach OcuTalon. Try again. Nothing was changed.";

/** A button variant of controls.css. */
export type ButtonVariant = 'primary' | 'secondary' | 'attention' | 'ghost' | 'inactive';

/**
 * A button whose press calls the server. While the call is out it is busy: a spinner, aria-busy and aria-disabled
 * (never disabled, so it keeps its place in the tab order and its focus), and a press is ignored. The call's
 * answer, early or late, ends the busy state and clears the notice. With no answer in 10 seconds the button is
 * restored and a warning notice under it says so, and the polite announcer reads the notice once.
 */
@Component({
  selector: 'app-server-button',
  imports: [Icon, InlineNotice],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <button
      type="button"
      [class]="'button button-' + variant()"
      [attr.aria-busy]="busy() ? 'true' : null"
      [attr.aria-disabled]="busy() ? 'true' : null"
      (click)="press()"
    >
      <ng-content />
      @if (busy()) {
        <app-icon class="spinner" name="loader-circle" [size]="16" />
      }
    </button>
    @if (notice()) {
      <app-inline-notice class="under" variant="warning">{{ text }}</app-inline-notice>
    }
  `,
  styles: `
    :host {
      display: inline-block;
    }
    .under {
      margin-top: var(--space-2);
    }
  `,
})
export class ServerButton {
  readonly variant = input<ButtonVariant>('primary');

  /** The call that a press makes: its answer, an Observable (its first value) or a Promise, ends the busy state. */
  readonly action = input.required<() => Observable<unknown> | Promise<unknown>>();

  protected readonly text = BUSY_NOTICE;
  protected readonly busy = signal(false);
  protected readonly notice = signal(false);

  private readonly announcer = inject(Announcer);
  private readonly state = new BusyState({
    setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
    clearTimeout: (handle) => globalThis.clearTimeout(handle as number),
    onChange: (view) => {
      this.busy.set(view.busy);
      this.notice.set(view.notice);
    },
    onNotice: () => this.announcer.announce(BUSY_NOTICE),
  });

  constructor() {
    inject(DestroyRef).onDestroy(() => this.state.dispose());
  }

  protected press(): void {
    if (!this.state.press()) {
      return;
    }
    const call = this.state.call;
    const answered = () => this.state.answered(call);
    let result: Observable<unknown> | Promise<unknown>;
    try {
      result = this.action()();
    } catch {
      answered();
      return;
    }
    const settled = isObservable(result) ? firstValueFrom(result, { defaultValue: undefined }) : result;
    settled.then(answered, answered);
  }
}
