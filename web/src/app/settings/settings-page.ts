import { HttpErrorResponse } from '@angular/common/http';
import { DOCUMENT } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, ViewContainerRef, computed, effect, inject, signal, untracked, viewChild } from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { map, Observable } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { AgentModels, EmailValues, Prices, ProviderRow, SettingsBody, SettingsSections } from '../api/api-types';
import { LiveState, LOAD_FAILED } from '../live/live-state';
import { telegramPaused } from '../rail/telegram-card/telegram-card-view';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { BudgetsSection, type BudgetTexts } from './budgets-section';
import { ChannelsSection } from './channels-section';
import { CheckThresholdsSection } from './check-thresholds-section';
import { DailyDigestSection } from './daily-digest-section';
import { DemoModeSection } from './demo-mode-section';
import { ModelsSection } from './models-section';
import { emailBoxShown, type ModelsForm, modelsValuesOf, sectionLabel, ROLES_SLUG, sectionPath, sectionSlug, SETTINGS_TEXTS, shownSections, telegramBoxShown, type ThresholdNumbers } from './settings-view';
import { TimeZoneSection } from './time-zone-section';

/** The id of the load error's text, which Retry is described by. */
const LOAD_ERROR_TEXT_ID = 'settings-load-error-text';

/**
 * The settings page (Story 33.2; FR-17; UX: Step 2, settings and the daily digest), for OcuTalonAdmin only. It is titled "Settings \u00B7 OcuTalon" by its
 * route, has the one h1 "Settings", a navigation landmark named "Settings sections" with the sections in the UX's order on the left (Roles, Story 25.4, only while the snapshot says an admin can assign roles; its code is a lazy chunk, loaded by a dynamic import when the section first opens), and the
 * open section on the right under its own h2. A section has its own address, #/settings/<slug>; #/settings and an unknown slug open Models (the first).
 *
 * The page asks GET /v1/settings once when it opens, and the answer decides what it shows (D10): the sections for an admin; for a 403, the denied
 * view, "Only OcuTalon admins can open settings." with a link back to the chat; for any other failure, the load error with Retry. Models, Budgets, Check
 * thresholds, Demo mode, Daily digest and Time zone have forms (Models and Budgets are Story 18.3's), and Channels shows the state of Telegram and nothing to
 * save (Story 18.2). Every section is built; an unknown address opens Models.
 *
 * Unsaved changes: the open form tells the page whether it differs from its saved values (`dirty`). While it does, leaving by a link or the browser's
 * back asks first (unsavedGuard), and a reload or a close of the tab gets the browser's own prompt, which is armed only while the form is dirty.
 */
@Component({
  selector: 'app-settings-page',
  imports: [BudgetsSection, ChannelsSection, CheckThresholdsSection, DailyDigestSection, DemoModeSection, ModelsSection, RouterLink, ServerButton, TimeZoneSection],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="settings" tabindex="-1" [attr.data-settings]="status()" [attr.aria-busy]="status() === 'loading' ? 'true' : null">
      <h1 class="heading">{{ texts.heading }}</h1>
      @switch (status()) {
        @case ('loaded') {
          <div class="layout">
            <nav class="sections" [attr.aria-label]="texts.sectionsName">
              <ul class="list">
                @for (section of sections(); track section.slug) {
                  <li>
                    <a class="section-link" [routerLink]="path(section.slug)" [attr.aria-current]="section.slug === active() ? 'true' : null">{{ section.label }}</a>
                  </li>
                }
              </ul>
            </nav>
            <section class="panel" aria-labelledby="settings-section-heading">
              <h2 id="settings-section-heading" class="section-heading">{{ label() }}</h2>
              @switch (active()) {
                @case ('check-thresholds') {
                  <app-check-thresholds-section
                    [values]="thresholds()"
                    (saved)="keepThresholds($event)"
                    (dirtyChange)="dirty.set($event)"
                    (denied)="deny()"
                  />
                }
                @case ('channels') {
                  <app-channels-section [email]="email()" (emailSaved)="keepEmail($event)" (dirtyChange)="dirty.set($event)" />
                }
                @case ('daily-digest') {
                  <app-daily-digest-section
                    [time]="digest().time"
                    [channels]="digest().channels"
                    [demoMode]="demoMode()"
                    [telegramShown]="telegramShown()"
                    [emailShown]="emailShown()"
                    (saved)="keepDailyDigest($event)"
                    (dirtyChange)="dirty.set($event)"
                    (denied)="deny()"
                  />
                }
                @case ('time-zone') {
                  <app-time-zone-section [zone]="zone()" (saved)="keepTimeZone($event)" (dirtyChange)="dirty.set($event)" (denied)="deny()" />
                }
                @case ('demo-mode') {
                  <app-demo-mode-section [value]="demoMode()" (saved)="keepDemoMode($event)" (dirtyChange)="dirty.set($event)" (denied)="deny()" />
                }
                @case ('budgets') {
                  <app-budgets-section [values]="budgets()" (saved)="keepBudgets($event)" (dirtyChange)="dirty.set($event)" (denied)="deny()" />
                }
                @case ('roles') {
                  <ng-container #rolesHost />
                }
                @case ('models') {
                  <app-models-section
                    [agentModels]="agentModels()"
                    [pricesIn]="prices()"
                    [providers]="providers()"
                    (saved)="keepModels($event)"
                    (dirtyChange)="dirty.set($event)"
                    (denied)="deny()"
                  />
                }
              }
            </section>
          </div>
        }
        @case ('denied') {
          <p class="denied">{{ texts.denied }}</p>
          <a class="link" routerLink="/">{{ texts.back }}</a>
        }
        @case ('failed') {
          <div class="load-error">
            <p class="load-error-text" [id]="loadErrorTextId">{{ loadFailed }}</p>
            <app-server-button variant="secondary" [action]="retry" [describedBy]="[loadErrorTextId]">Retry</app-server-button>
          </div>
        }
      }
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      min-height: 0;
    }
    .settings {
      flex: 1;
      min-width: 0;
      overflow: auto;
      scroll-padding: var(--space-scroll-gutter);
      padding: var(--space-6);
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
    }
    .heading {
      margin: 0;
      font-family: var(--font-display);
      font-size: var(--type-display-lg-font-size);
      font-weight: var(--type-display-lg-font-weight);
      line-height: var(--type-display-lg-line-height);
    }
    .layout {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-6);
      align-items: flex-start;
    }
    .sections {
      flex: none;
      min-width: 180px;
    }
    .list {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .section-link {
      display: flex;
      align-items: center;
      min-height: var(--space-target-min);
      padding: 0 var(--space-3);
      border-radius: var(--rounded-sm);
      color: var(--header-nav-item-foreground);
      font-family: var(--font-ui);
      font-size: var(--header-nav-item-typography-font-size);
      font-weight: var(--header-nav-item-typography-font-weight);
      line-height: var(--header-nav-item-typography-line-height);
      text-decoration-line: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
    }
    .section-link:hover {
      background: var(--action-soft);
    }
    .section-link[aria-current] {
      background: var(--action-soft);
      color: var(--header-nav-item-foreground-current);
    }
    .panel {
      flex: 1;
      min-width: 280px;
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
    }
    .section-heading {
      margin: 0;
    }
    .denied,
    .load-error-text {
      margin: 0;
    }
    .load-error {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
    }
  `,
})
export class SettingsPage {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly destroyed = inject(DestroyRef);
  private readonly route = inject(ActivatedRoute);
  private readonly live = inject(LiveState);

  protected readonly texts = SETTINGS_TEXTS;
  protected readonly loadErrorTextId = LOAD_ERROR_TEXT_ID;
  protected readonly loadFailed = LOAD_FAILED;

  /** How the load of the page's values went: loading, loaded, denied (a 403) or failed (any other failure). */
  readonly status = signal<'loading' | 'loaded' | 'denied' | 'failed'>('loading');

  /** The values of the sections, as the server holds them. */
  private readonly data = signal<SettingsBody | undefined>(undefined);

  /** True while the open section has unsaved changes (the guard and the browser's own prompt read it). */
  readonly dirty = signal(false);

  /** True while the Roles section exists: an admin, roles can be assigned (Story 26.4's roles exist) and the install is not the online demo. */
  protected readonly rolesShown = computed(() => {
    const snapshot = this.live.snapshot();
    return snapshot?.admin === true && snapshot.rolesAssignable === true && snapshot.onlineDemo !== true;
  });

  /** The Roles section's component, loaded from its own chunk the first time the section opens (a dynamic import, so the initial bundle never holds it). */
  private readonly rolesHost = viewChild('rolesHost', { read: ViewContainerRef });

  /** The sections the navigation lists. */
  protected readonly sections = computed(() => shownSections(this.rolesShown()));

  /** The section part of the address, as it was typed. */
  private readonly part = toSignal(this.route.paramMap.pipe(map((params) => params.get('section'))), {
    initialValue: this.route.snapshot.paramMap.get('section'),
  });

  /** The open section's slug: an unknown or hidden one is Models. */
  protected readonly active = computed(() => sectionSlug(this.part(), this.rolesShown()));

  protected readonly label = computed(() => sectionLabel(this.active()));
  protected readonly thresholds = computed<ThresholdNumbers>(() => this.data()?.sections['check-thresholds'] ?? { diskFreePercent: 10, journalFreePercent: 10, licenseUsePercent: 90, queueMessages: 100, queueWaitMinutes: 10 });
  protected readonly demoMode = computed(() => this.data()?.sections['demo-mode']?.demoMode === true);
  /** The mailbox values of the Email group (Story 21.2); the server sends none on the online demo. */
  protected readonly email = computed(() => this.data()?.sections.channels);
  protected readonly digest = computed(() => this.data()?.sections['daily-digest'] ?? { time: '08:00', channels: 'web,phone,telegram' });
  /** The instance zone that the server holds ("" for the server's own): the bridge value, as GET /v1/settings has it. */
  protected readonly zone = computed(() => {
    const zone = this.data()?.bridge['InstanceZone'];
    return typeof zone === 'string' ? zone : '';
  });
  /** The model of each agent, and the prices, the provider table and the budgets, as GET /v1/settings has them (Story 18.3). */
  protected readonly agentModels = computed<Readonly<Record<string, AgentModels>> | undefined>(() => this.data()?.bridge.agents);
  protected readonly prices = computed<Readonly<Prices> | undefined>(() => this.data()?.prices);
  protected readonly providers = computed<readonly ProviderRow[]>(() => this.data()?.providers ?? []);
  protected readonly budgets = computed<BudgetTexts>(() => {
    const bridge = this.data()?.bridge;
    return { tokens: String(bridge?.['DecisionTokenBudget'] ?? '0'), cap: String(bridge?.['DailyCostCapUSD'] ?? '0') };
  });
  /** True while the mailbox has an address and an outgoing mail server saved: the Daily digest's Email box shows. */
  protected readonly emailShown = computed(() => emailBoxShown(this.email()));
  /** True while the Daily digest section shows the Telegram box: Telegram is included and on, or paused. */
  protected readonly telegramShown = computed(() => telegramBoxShown(this.live.store()?.telegram, telegramPaused(this.live.store()?.status)));

  constructor() {
    this.request();
    const view = inject(DOCUMENT).defaultView;
    const unload = (event: BeforeUnloadEvent): void => {
      event.preventDefault();
      event.returnValue = '';
    };
    effect(() => {
      if (this.dirty()) {
        view?.addEventListener('beforeunload', unload);
      } else {
        view?.removeEventListener('beforeunload', unload);
      }
    });
    effect(() => {
      this.active();
      untracked(() => this.dirty.set(false));
    });
    effect(() => {
      const host = this.rolesHost();
      if (host !== undefined && this.active() === ROLES_SLUG) {
        void import('./roles-section').then((loaded) => {
          if (untracked(this.rolesHost) === host && host.length === 0) {
            host.createComponent(loaded.RolesSection);
          }
        });
      }
    });
    this.destroyed.onDestroy(() => view?.removeEventListener('beforeunload', unload));
  }

  /** The router address of the section. */
  protected path(slug: string): string[] {
    return sectionPath(slug);
  }

  /** Retry: asks again; the Observable emits once and completes when the server has answered, whatever the answer. */
  protected readonly retry = (): Observable<void> =>
    new Observable<void>((subscriber) => {
      this.request(() => {
        subscriber.next();
        subscriber.complete();
      });
    });

  /** A save answered 403: the user is no longer an admin, so the page shows the denied view and nothing is left unsaved to ask about. */
  protected deny(): void {
    this.dirty.set(false);
    this.status.set('denied');
  }

  protected keepThresholds(values: SettingsSections['check-thresholds']): void {
    this.data.update((one) => (one === undefined ? one : { ...one, sections: { ...one.sections, 'check-thresholds': values } }));
  }

  protected keepDailyDigest(values: SettingsSections['daily-digest']): void {
    this.data.update((one) => (one === undefined ? one : { ...one, sections: { ...one.sections, 'daily-digest': values } }));
  }

  protected keepTimeZone(zone: string): void {
    this.data.update((one) => (one === undefined ? one : { ...one, bridge: { ...one.bridge, InstanceZone: zone }, instanceZone: zone }));
  }

  protected keepModels(form: ModelsForm): void {
    const values = modelsValuesOf(form);
    this.data.update((one) => (one === undefined ? one : { ...one, bridge: { ...one.bridge, agents: values.agents }, prices: values.prices }));
  }

  protected keepBudgets(values: BudgetTexts): void {
    this.data.update((one) => (one === undefined ? one : { ...one, bridge: { ...one.bridge, DecisionTokenBudget: values.tokens, DailyCostCapUSD: values.cap } }));
  }

  protected keepEmail(values: EmailValues): void {
    this.data.update((one) => (one === undefined ? one : { ...one, sections: { ...one.sections, channels: values } }));
  }

  protected keepDemoMode(value: boolean): void {
    this.data.update((one) => (one === undefined ? one : { ...one, sections: { ...one.sections, 'demo-mode': { demoMode: value } } }));
  }

  /** Asks for the page's values; done is called when the server has answered. */
  private request(done?: () => void): void {
    this.api
      .settings()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (body) => {
          this.data.set(body);
          this.status.set('loaded');
          done?.();
        },
        error: (error: unknown) => {
          const denied = error instanceof HttpErrorResponse && error.status === 403;
          this.status.set(denied ? 'denied' : 'failed');
          if (!denied) {
            this.announcer.announce(LOAD_FAILED);
          }
          done?.();
        },
      });
  }
}
