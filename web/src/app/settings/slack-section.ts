import { afterNextRender, ChangeDetectionStrategy, Component, DestroyRef, ElementRef, inject, Injector, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { SlackList } from '../api/api-types';
import { CHAT_TEXTS } from '../chat/chat-view';
import { Icon } from '../icon/icon';
import { GUIDE_URL } from '../links';
import { LOAD_FAILED } from '../live/live-state';
import { readmeSection } from '../rail/rail-view';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { SETTINGS_TEXTS } from './settings-view';
import { SLACK_TEXTS, memberIdProblem, slackOutcome, slackState, type SlackView } from './slack-view';
import { addressText } from './webhooks-view';

/** The anchor of the Slack section of GUIDE.md. */
const SLACK_ANCHOR = 'slack';

/**
 * The Slack group of Settings > Channels (Story 27.3; FR-21): Slack's state, the address to subscribe the Slack app's events to, and the members that an admin has linked to
 * OcuTalon users, with the form that links one. It is a lazy chunk, made by the Channels section after the Webhooks group. The page decides nothing (AD-12): the state, the list and the
 * users the form offers come from the server in one GET, and the server judges every link and answers a refusal with its text, which the group shows as it comes.
 *   - off (the server's state): "Slack not set up. Add SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET to .env and restart OcuTalon." and the link "How to set it up" to the Slack section of
 *     GUIDE.md, in a new tab; on: "Slack on" and "Subscribe your Slack app's events to {address}." with the address on this page's origin. The members part shows in both states;
 *   - Link member: a member ID of the wrong shape shows its text under the field and sends nothing; otherwise the POST decides: a 200 announces "Linked. ..." and loads the list again,
 *     a refusal shows its text under the field that it names (the member ID or the user) or under the button, and the first takes focus;
 *   - Unlink: removes the row's link, announces "Unlinked. ..." and loads the list again. Each Unlink button is described by its row;
 *   - 403: "Only OcuTalon admins can open settings." replaces the group's body; 409 `not_available` (the online demo): only "Slack is off on the online demo, ...";
 *   - a list that fails to load for any other reason shows the accepted load error (LOAD_FAILED) with Retry, as the Webhooks group does.
 * Typing in a field clears its error and the saved line.
 */
@Component({
  selector: 'app-slack-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="group" aria-labelledby="slack-heading">
      <h3 id="slack-heading" class="heading">{{ texts.heading }}</h3>
      @switch (state()) {
        @case ('off') {
          <p class="help" data-state="off">{{ texts.offOnDemo }}</p>
        }
        @case ('failed') {
          <div class="load-error" data-state="failed">
            <p class="load-error-text" id="slack-load-error-text">{{ loadFailed }}</p>
            <app-server-button variant="secondary" [action]="retry" [describedBy]="['slack-load-error-text']">Retry</app-server-button>
          </div>
        }
        @case ('denied') {
          <p class="field-error" data-state="denied"><app-icon name="circle-alert" [size]="16" />{{ settingsTexts.denied }}</p>
        }
        @case ('ready') {
          @if (view().on) {
            <p class="status" data-state="on">{{ texts.on }}</p>
            <p class="address" data-slack="address">{{ address() }}</p>
          } @else {
            <div class="not-set-up" data-state="not-set-up">
              <span class="text">{{ texts.notSetUp }}</span>
              <a class="link" [href]="howToHref" target="_blank" rel="noopener noreferrer"
                >{{ texts.howTo }}<app-icon name="external-link" [size]="12" /><span class="visually-hidden"> {{ opensInNewTab }}</span></a
              >
            </div>
          }
          <h4 class="members-heading">{{ texts.membersHeading }}</h4>
          <p class="help">{{ texts.membersHelp }}</p>
          @for (member of view().members; track member.ref; let index = $index) {
            <div class="member" role="group" [attr.aria-label]="member.user">
              <p class="member-line" [id]="'slack-member-' + index"><span class="member-user">{{ member.user }} </span><span class="member-id">{{ member.member }}</span></p>
              <app-server-button variant="secondary" [action]="unlink(member.ref)" [describedBy]="['slack-member-' + index]">{{ texts.unlink }}</app-server-button>
            </div>
          } @empty {
            <p class="help" data-slack="none">{{ texts.noMembers }}</p>
          }
          <div class="field">
            <label for="slack-member-id">{{ texts.memberId }}</label>
            <input
              id="slack-member-id"
              class="input"
              type="text"
              autocomplete="off"
              spellcheck="false"
              [class.invalid]="memberError() !== ''"
              [attr.aria-invalid]="memberError() !== '' ? 'true' : null"
              [attr.aria-describedby]="memberError() !== '' ? 'slack-member-error' : null"
              [value]="member()"
              (input)="typedMember($event)"
            />
            @if (memberError() !== '') {
              <p class="field-error" id="slack-member-error"><app-icon name="circle-alert" [size]="16" />{{ memberError() }}</p>
            }
          </div>
          <div class="field">
            <label for="slack-member-user">{{ texts.memberUser }}</label>
            <select
              id="slack-member-user"
              class="input"
              [class.invalid]="userError() !== ''"
              [attr.aria-invalid]="userError() !== '' ? 'true' : null"
              [attr.aria-describedby]="userError() !== '' ? 'slack-user-error' : null"
              (change)="pickedUser($event)"
            >
              @for (name of view().users; track name) {
                <option [value]="name" [selected]="name === user()">{{ name }}</option>
              }
            </select>
            @if (userError() !== '') {
              <p class="field-error" id="slack-user-error"><app-icon name="circle-alert" [size]="16" />{{ userError() }}</p>
            }
          </div>
          <div class="actions">
            <app-server-button variant="primary" [action]="link" [describedBy]="linkDescribed()">{{ texts.link }}</app-server-button>
          </div>
          @if (formError() !== '') {
            <p class="field-error" id="slack-form-error"><app-icon name="circle-alert" [size]="16" />{{ formError() }}</p>
          }
          @if (line() !== '') {
            <p class="saved" data-slack="saved">{{ line() }}</p>
          }
        }
      }
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
      margin-top: var(--space-6);
    }
    .heading,
    .members-heading,
    .member-line,
    .status {
      margin: 0;
      color: var(--ink);
    }
    .not-set-up {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-1);
    }
    .link {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
    }
    .address {
      margin: 0;
      overflow-wrap: anywhere;
      color: var(--ink);
    }
    .member {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: var(--space-3);
      padding-top: var(--space-3);
      border-top: var(--text-input-border);
    }
    .member-user {
      font-weight: 600;
    }
    .member-id {
      overflow-wrap: anywhere;
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
    .input.invalid {
      border: var(--text-input-border-error);
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
export class SlackSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly destroyed = inject(DestroyRef);

  protected readonly texts = SLACK_TEXTS;
  protected readonly settingsTexts = SETTINGS_TEXTS;
  protected readonly loadFailed = LOAD_FAILED;
  protected readonly opensInNewTab = CHAT_TEXTS.opensInNewTab;
  protected readonly howToHref = readmeSection(GUIDE_URL, SLACK_ANCHOR);

  /** loading until the list answers; then ready, off (the online demo), denied, or failed (the list did not load). */
  protected readonly state = signal<'loading' | 'ready' | 'off' | 'denied' | 'failed'>('loading');
  protected readonly view = signal<SlackView>({ on: false, path: '', members: [], users: [] });

  protected readonly member = signal('');
  protected readonly user = signal('');
  protected readonly memberError = signal('');
  protected readonly userError = signal('');
  protected readonly formError = signal('');
  /** The line after the last accepted link or unlink, '' when there is none. */
  protected readonly line = signal('');

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
      .slack()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (list: SlackList) => {
          this.show(slackState(list));
          this.state.set('ready');
          done?.();
        },
        error: (error: unknown) => {
          const outcome = error instanceof HttpErrorResponse ? slackOutcome(error.status, error.error) : ({ kind: 'failed' } as const);
          const state = outcome.kind === 'off' ? 'off' : outcome.kind === 'denied' ? 'denied' : 'failed';
          this.state.set(state);
          if (state === 'failed') {
            this.announcer.announce(LOAD_FAILED);
          }
          done?.();
        },
      });
  }

  /** Takes a list: the form's user stays while the list still offers it, else it is the first user. */
  private show(view: SlackView): void {
    this.view.set(view);
    if (!view.users.includes(this.user())) {
      this.user.set(view.users[0] ?? '');
    }
  }

  /** The line under the state: the sentence with the address on this page's origin. */
  protected address(): string {
    return addressText(SLACK_TEXTS.address, window.location.origin, this.view().path);
  }

  protected linkDescribed(): readonly string[] {
    return this.formError() !== '' ? ['slack-form-error'] : [];
  }

  protected typedMember(event: Event): void {
    this.member.set((event.target as HTMLInputElement).value);
    this.clearMessages();
  }

  protected pickedUser(event: Event): void {
    this.user.set((event.target as HTMLSelectElement).value);
    this.clearMessages();
  }

  private clearMessages(): void {
    this.memberError.set('');
    this.userError.set('');
    this.formError.set('');
    this.line.set('');
  }

  /** Link member: checks the member ID's shape, then posts the member and the user; the answer decides what the group shows. */
  protected readonly link = (): Observable<unknown> => {
    this.clearMessages();
    const problem = memberIdProblem(this.member());
    if (problem !== '') {
      this.memberError.set(problem);
      this.announcer.announce(problem);
      this.moveFocusTo('#slack-member-id');
      return new Observable<void>((subscriber) => {
        subscriber.next();
        subscriber.complete();
      });
    }
    return this.api.linkSlack({ user: this.user(), member: this.member().trim() }).pipe(
      tap({
        next: () => {
          this.member.set('');
          this.line.set(SLACK_TEXTS.linked);
          this.announcer.announce(SLACK_TEXTS.linked);
          this.load();
        },
        error: (error: unknown) => this.refused(error),
      }),
    );
  };

  /** Unlink: removes the link of the row; the list is loaded again. */
  protected unlink(ref: string): () => Observable<unknown> {
    return () => {
      this.clearMessages();
      return this.api.unlinkSlack(ref).pipe(
        tap({
          next: () => {
            this.line.set(SLACK_TEXTS.unlinked);
            this.announcer.announce(SLACK_TEXTS.unlinked);
            this.load();
            this.moveFocusTo('#slack-member-id');
          },
          error: (error: unknown) => this.refused(error),
        }),
      );
    };
  }

  private refused(error: unknown): void {
    const outcome = error instanceof HttpErrorResponse ? slackOutcome(error.status, error.error) : ({ kind: 'failed' } as const);
    if (outcome.kind === 'denied' || outcome.kind === 'off') {
      this.state.set(outcome.kind);
      return;
    }
    if (outcome.kind === 'field') {
      if (outcome.field === 'member') {
        this.memberError.set(outcome.text);
      } else {
        this.userError.set(outcome.text);
      }
      this.announcer.announce(outcome.text);
      this.moveFocusTo(outcome.field === 'member' ? '#slack-member-id' : '#slack-member-user');
      return;
    }
    const text = outcome.kind === 'form' ? outcome.text : SETTINGS_TEXTS.failed;
    this.formError.set(text);
    this.announcer.announce(text);
  }

  private moveFocusTo(selector: string): void {
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(selector)?.focus(), { injector: this.injector });
  }
}
