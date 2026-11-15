import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, afterNextRender, inject, Injector, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { RoleHolder } from '../api/api-types';
import { Icon } from '../icon/icon';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { ASSIGNABLE, heldAssignable, removeLabel, ROLES_TEXTS, roleOutcome, saveLine, type AssignableRole, type SaveLine } from './roles-view';
import { SETTINGS_TEXTS } from './settings-view';

/**
 * The Roles section of Settings (Story 25.4; FR-11; UX: Step 6, roles), for OcuTalonAdmin only, shown only while the snapshot's `rolesAssignable` is true. The
 * section's code is a lazy chunk (the settings page loads it with a dynamic import into a ViewContainerRef), so it adds nothing to the initial bundle. It lists the IRIS users who hold an OcuTalon role
 * (one group per user, named by the user), each with the roles as text and a Remove button for each assignable role the user holds, or "Managed by OcuTalon" in place of the
 * buttons; the form below it grants one of the two assignable roles to a user by name. The server judges everything: a refused call shows the text of its reason under the form, and the
 * announcer, the page's one live region, reads it once.
 *   - 200 with `changed` true: the step-2 saved text shows and is read once, and the list is asked for again (the grant the section made shows in it); after a Remove, whose button
 *     leaves with the role, the list heading takes focus once the list is drawn again;
 *   - 200 with `changed` false (the user already was in that state): "No change: {user}'s roles are already as you set them." shows instead, read once, and the list is asked for again (after a Remove, the list
 *     heading takes focus once the list is drawn again, as for a change);
 *   - 400 with a reason: that reason's text; 403: the page's denied text; 409 not_available: the section's own text in place of the form;
 *   - any other failure: "Couldn't save. Nothing was changed.".
 * A list that fails to load shows "Couldn't load the roles." with Retry in place of the form.
 */
@Component({
  selector: 'app-roles-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="group" aria-labelledby="roles-heading">
      <h3 id="roles-heading" class="heading">{{ texts.heading }}</h3>
      @switch (state()) {
        @case ('off') {
          <p class="help" data-state="off">{{ texts.off }}</p>
        }
        @case ('failed') {
          <div class="load-error" data-state="failed">
            <p class="load-error-text" id="roles-load-error-text">{{ texts.loadFailed }}</p>
            <app-server-button variant="secondary" [action]="retry" [describedBy]="['roles-load-error-text']">{{ texts.retry }}</app-server-button>
          </div>
        }
        @case ('denied') {
          <p class="field-error" data-state="denied"><app-icon name="circle-alert" [size]="16" />{{ settingsTexts.denied }}</p>
        }
        @case ('ready') {
          <p class="help">{{ texts.intro }}</p>
          <p class="help">{{ texts.perKind }}</p>
          <h4 class="list-heading" id="roles-list-heading" tabindex="-1">{{ texts.listHeading }}</h4>
          @if (users().length === 0) {
            <p class="help" data-roles="empty">{{ texts.empty }}</p>
          } @else {
            @for (holder of users(); track holder.user) {
              <div class="holder" role="group" [attr.aria-label]="holder.user" data-roles="holder">
                <p class="holder-name">{{ holder.user }}</p>
                <p class="holder-roles">{{ rolesText(holder) }}</p>
                @if (holder.managed) {
                  <p class="help">{{ texts.managed }}</p>
                } @else {
                  <div class="actions">
                    @for (role of held(holder); track role.role) {
                      <app-server-button variant="secondary" [label]="removeName(role, holder.user)" [action]="remove(holder.user, role)">{{ role.remove }}</app-server-button>
                    }
                  </div>
                }
              </div>
            }
          }
          <div class="field">
            <label for="roles-user">{{ texts.userLabel }}</label>
            <input id="roles-user" class="input" type="text" autocomplete="off" spellcheck="false" [value]="user()" (input)="typedUser($event)" />
          </div>
          <div class="field">
            <label for="roles-role">{{ texts.roleLabel }}</label>
            <select id="roles-role" class="input" (change)="pickedRole($event)">
              @for (entry of assignable; track entry.role) {
                <option [value]="entry.role" [selected]="entry.role === role()">{{ entry.option }}</option>
              }
            </select>
          </div>
          <div class="actions">
            <app-server-button variant="primary" [action]="grant">{{ texts.grant }}</app-server-button>
          </div>
        }
      }
      <p class="saved" data-roles="status">
        @if (refusal() !== '') {
          <span class="field-error"><app-icon name="circle-alert" [size]="16" />{{ refusal() }}</span>
        } @else if (line(); as shown) {
          <span [attr.data-saved]="shown.changed ? 'roles' : 'roles-no-change'">{{ shown.text }}</span>
        }
      </p>
    </section>
  `,
  styles: `
    :host {
      display: block;
      max-width: 480px;
    }
    .group {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
    }
    .heading,
    .list-heading,
    .holder-name,
    .holder-roles {
      margin: 0;
      color: var(--ink);
    }
    .holder {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      padding-top: var(--space-3);
      border-top: var(--text-input-border);
    }
    .holder-name {
      font-weight: 600;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .input {
      box-sizing: border-box;
      width: 100%;
      min-height: var(--space-target-min);
      padding: var(--space-2) var(--space-3);
      background: var(--text-input-background);
      color: var(--ink);
      border: var(--text-input-border);
      border-radius: var(--text-input-radius);
      font-family: var(--font-ui);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .help {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .field-error {
      display: flex;
      align-items: flex-start;
      gap: var(--space-1);
      margin: 0;
      color: var(--field-error-foreground);
      font-size: var(--field-error-typography-font-size);
      font-weight: var(--field-error-typography-font-weight);
      line-height: var(--field-error-typography-line-height);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      gap: var(--space-3);
    }
    .saved {
      margin: 0;
      color: var(--ink);
      min-height: 1px;
    }
    .load-error {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
    }
    .load-error-text {
      margin: 0;
      color: var(--ink);
    }
  `,
})
export class RolesSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly destroyed = inject(DestroyRef);

  protected readonly texts = ROLES_TEXTS;
  protected readonly settingsTexts = SETTINGS_TEXTS;
  protected readonly assignable = ASSIGNABLE;

  /** loading until the list answers; then ready, off (the online demo), denied, or failed (the list did not load). */
  protected readonly state = signal<'loading' | 'ready' | 'off' | 'denied' | 'failed'>('loading');
  protected readonly users = signal<readonly RoleHolder[]>([]);
  protected readonly user = signal('');
  protected readonly role = signal<AssignableRole['role']>(ASSIGNABLE[0].role);
  /** The text of the last refusal, "" when there is none. */
  protected readonly refusal = signal('');
  /** The line after the last accepted save, null when there is none. */
  protected readonly line = signal<SaveLine | null>(null);

  constructor() {
    this.load();
  }

  /** Retry: asks for the list again; the Observable emits once and completes when the server has answered, whatever the answer. */
  protected readonly retry = (): Observable<void> =>
    new Observable<void>((subscriber) => {
      this.load(() => {
        subscriber.next();
        subscriber.complete();
      });
    });

  /** Loads the list; done is called once the server has answered. */
  private load(done?: () => void): void {
    this.api
      .listRoles()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (list) => {
          this.users.set(list.users);
          this.state.set('ready');
          done?.();
        },
        error: (error: unknown) => {
          const outcome = error instanceof HttpErrorResponse ? roleOutcome(error.status, error.error) : ({ kind: 'failed' } as const);
          this.state.set(outcome.kind === 'off' ? 'off' : outcome.kind === 'denied' ? 'denied' : 'failed');
          if (outcome.kind === 'failed') {
            this.announcer.announce(ROLES_TEXTS.loadFailed);
          }
          done?.();
        },
      });
  }

  protected rolesText(holder: RoleHolder): string {
    return holder.roles.join(', ');
  }

  protected held(holder: RoleHolder): readonly AssignableRole[] {
    return heldAssignable(holder.roles);
  }

  protected removeName(role: AssignableRole, user: string): string {
    return removeLabel(role, user);
  }

  protected typedUser(event: Event): void {
    this.user.set((event.target as HTMLInputElement).value);
    this.refusal.set('');
    this.line.set(null);
  }

  protected pickedRole(event: Event): void {
    const value = (event.target as HTMLSelectElement).value;
    this.role.set(ASSIGNABLE.find((one) => one.role === value)?.role ?? ASSIGNABLE[0].role);
    this.refusal.set('');
    this.line.set(null);
  }

  /** Grant: posts the typed user and the chosen role. */
  protected readonly grant = (): Observable<unknown> => this.change(this.user().trim(), this.role(), true, true);

  /** The Remove button of one role of one user. */
  protected remove(user: string, role: AssignableRole): () => Observable<unknown> {
    return () => this.change(user, role.role, false, false);
  }

  private change(user: string, role: AssignableRole['role'], grant: boolean, fromForm: boolean): Observable<unknown> {
    this.refusal.set('');
    this.line.set(null);
    return this.api.saveRole(user, role, grant).pipe(
      tap({
        next: (answer) => {
          if (fromForm) {
            this.user.set('');
          }
          const shown = saveLine(answer, user, SETTINGS_TEXTS.saved);
          this.line.set(shown);
          this.announcer.announce(shown.text);
          this.load(fromForm ? undefined : () => this.focusLater('#roles-list-heading'));
        },
        error: (error: unknown) => this.refused(error, fromForm),
      }),
    );
  }

  private refused(error: unknown, fromForm: boolean): void {
    const outcome = error instanceof HttpErrorResponse ? roleOutcome(error.status, error.error) : ({ kind: 'failed' } as const);
    if (outcome.kind === 'denied' || outcome.kind === 'off') {
      this.state.set(outcome.kind);
      return;
    }
    const text = outcome.kind === 'refused' ? outcome.text : SETTINGS_TEXTS.failed;
    this.refusal.set(text);
    this.announcer.announce(text);
    if (fromForm) {
      this.focusLater('#roles-user');
    }
  }

  /** Moves focus to the element of the section that the selector names once the section is drawn again, for the user's own Grant or Remove. */
  private focusLater(selector: string): void {
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(selector)?.focus(), { injector: this.injector });
  }
}
