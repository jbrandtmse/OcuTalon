import { ChangeDetectionStrategy, Component, computed, DestroyRef, inject, input, signal } from '@angular/core';
import { firstValueFrom, isObservable, type Observable } from 'rxjs';

import { Icon } from '../icon/icon';
import { Announcer } from './announcer';
import { BusyState } from './busy-state';
import { InlineNotice } from './inline-notice';

/** The notice under a server button whose call has had no answer for 10 seconds. */
export const BUSY_NOTICE = "Couldn't reach OcuTalon. Try again. Nothing was changed.";

/** The count of the buttons that have been made, which gives each one's notice an id of its own. */
let lastNotice = 0;

/** A button variant of controls.css. */
export type ButtonVariant = 'primary' | 'secondary' | 'attention' | 'ghost' | 'inactive';

/**
 * A button whose press calls the server. While the call is out it is busy: a spinner, aria-busy and aria-disabled
 * (never disabled, so it keeps its place in the tab order and its focus), and a press is ignored. The call's
 * answer, early or late, ends the busy state and clears the notice. With no answer in 10 seconds the button is
 * restored and a warning notice under it says so, and the polite announcer reads the notice once.
 *
 * A button that the server says cannot act now (`inactive`) is held aria-disabled in the same way, and a press on it makes no call; it
 * shows no spinner. The server's state, not the button's, decides when it acts again.
 *
 * The button is described (aria-describedby) by the text that explains it: the ids in `describedBy`, and the notice's id while the
 * notice shows. The notice's id is the button's own, so two buttons never share one. With neither, the button has no description.
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
      [attr.aria-disabled]="busy() || inactive() ? 'true' : null"
      [attr.aria-describedby]="described()"
      (click)="press()"
    >
      @if (busy()) {
        <app-icon class="spinner" name="loader-circle" [size]="16" />
      }
      <ng-content />
    </button>
    @if (notice()) {
      <app-inline-notice class="under" variant="warning" [id]="noticeId">{{ text }}</app-inline-notice>
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

  /** True while the server says the control is unavailable: the button is aria-disabled and a press is ignored. */
  readonly inactive = input(false);

  /** The ids of the text that explains the button, such as the error beside it. */
  readonly describedBy = input<readonly string[]>([]);

  protected readonly text = BUSY_NOTICE;
  protected readonly noticeId = `server-button-notice-${(lastNotice += 1)}`;
  protected readonly busy = signal(false);
  protected readonly notice = signal(false);

  /** The button's aria-describedby: the given ids, then the notice's while it shows; null with neither. */
  protected readonly described = computed(() => {
    const ids = this.notice() ? [...this.describedBy(), this.noticeId] : this.describedBy();
    return ids.length === 0 ? null : ids.join(' ');
  });

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
    if (this.inactive() || !this.state.press()) {
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
