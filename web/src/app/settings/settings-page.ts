import { HttpErrorResponse } from '@angular/common/http';
import { DOCUMENT } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, computed, effect, inject, signal, untracked } from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { map, Observable } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { SettingsBody, SettingsSections } from '../api/api-types';
import { LOAD_FAILED } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { ServerButton } from '../shared/server-button';
import { CheckThresholdsSection } from './check-thresholds-section';
import { DemoModeSection } from './demo-mode-section';
import { sectionLabel, sectionPath, sectionSlug, SETTINGS_SECTIONS, SETTINGS_TEXTS, type ThresholdNumbers } from './settings-view';

/** The id of the load error's text, which Retry is described by. */
const LOAD_ERROR_TEXT_ID = 'settings-load-error-text';

/**
 * The settings page (Story 33.2; FR-17; UX: Step 2, settings and the daily digest), for OcuTalonAdmin only. It is titled "Settings \u00B7 OcuTalon" by its
 * route, has the one h1 "Settings", a navigation landmark named "Settings sections" with the seven sections in the UX's order on the left, and the
 * open section on the right under its own h2. A section has its own address, #/settings/<slug>; #/settings and an unknown slug open Models (the first).
 *
 * The page asks GET /v1/settings once when it opens, and the answer decides what it shows (D10): the sections for an admin; for a 403, the denied
 * view, "Only OcuTalon admins can open settings." with a link back to the chat; for any other failure, the load error with Retry. Check thresholds
 * and Demo mode have forms; the other five sections show that they are not built yet (their stories add them), with no button.
 *
 * Unsaved changes: the open form tells the page whether it differs from its saved values (`dirty`). While it does, leaving by a link or the browser's
 * back asks first (unsavedGuard), and a reload or a close of the tab gets the browser's own prompt, which is armed only while the form is dirty.
 */
@Component({
  selector: 'app-settings-page',
  imports: [CheckThresholdsSection, DemoModeSection, RouterLink, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="settings" tabindex="-1" [attr.data-settings]="status()" [attr.aria-busy]="status() === 'loading' ? 'true' : null">
      <h1 class="heading">{{ texts.heading }}</h1>
      @switch (status()) {
        @case ('loaded') {
          <div class="layout">
            <nav class="sections" [attr.aria-label]="texts.sectionsName">
              <ul class="list">
                @for (section of sections; track section.slug) {
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
                    (denied)="status.set('denied')"
                  />
                }
                @case ('demo-mode') {
                  <app-demo-mode-section [value]="demoMode()" (saved)="keepDemoMode($event)" (dirtyChange)="dirty.set($event)" (denied)="status.set('denied')" />
                }
                @default {
                  <p class="not-built">{{ texts.notBuilt }}</p>
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
    .not-built,
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

  protected readonly texts = SETTINGS_TEXTS;
  protected readonly sections = SETTINGS_SECTIONS;
  protected readonly loadErrorTextId = LOAD_ERROR_TEXT_ID;
  protected readonly loadFailed = LOAD_FAILED;

  /** How the load of the page's values went: loading, loaded, denied (a 403) or failed (any other failure). */
  readonly status = signal<'loading' | 'loaded' | 'denied' | 'failed'>('loading');

  /** The values of the sections, as the server holds them. */
  private readonly data = signal<SettingsBody | undefined>(undefined);

  /** True while the open section has unsaved changes (the guard and the browser's own prompt read it). */
  readonly dirty = signal(false);

  /** The open section's slug. */
  protected readonly active = toSignal(this.route.paramMap.pipe(map((params) => sectionSlug(params.get('section')))), {
    initialValue: sectionSlug(this.route.snapshot.paramMap.get('section')),
  });

  protected readonly label = computed(() => sectionLabel(this.active()));
  protected readonly thresholds = computed<ThresholdNumbers>(() => this.data()?.sections['check-thresholds'] ?? { diskFreePercent: 10, journalFreePercent: 10, licenseUsePercent: 90, queueMessages: 100, queueWaitMinutes: 10 });
  protected readonly demoMode = computed(() => this.data()?.sections['demo-mode']?.demoMode === true);

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

  protected keepThresholds(values: SettingsSections['check-thresholds']): void {
    this.data.update((one) => (one === undefined ? one : { ...one, sections: { ...one.sections, 'check-thresholds': values } }));
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
