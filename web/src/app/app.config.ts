import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withHashLocation, withNavigationErrorHandler, withRouterConfig, type Routes } from '@angular/router';

import { envelopeInterceptor } from './api/envelope.interceptor';
import { DocumentsPage } from './documents/documents-page';
import { DOCUMENTS_TEXTS } from './documents/documents-view';
import { MainPage } from './main-page/main-page';
import { unsavedGuard } from './settings/unsaved-guard';
import { reloadForChunkError } from './shared/chunk-reload';
import { SHELL_TEXTS, settingsMatch } from './shared/page-shell-view';

/**
 * The chat is the main page and the wildcard route, with no redirect: a deep link keeps its address. A later page adds its route before the
 * wildcard. The Documents page (Story 34.2) is the route #/documents, titled "Documents \u00B7 OcuTalon", and the History page (Story 25.2) is #/history, titled "History \u00B7 OcuTalon", and the Usage page (Story 37.2) is #/usage, titled "Usage \u00B7 OcuTalon". The settings page (Story 33.2) is one route for #/settings and #/settings/<slug> (settingsMatch), so a section change keeps the
 * page; it is guarded against leaving with unsaved changes and titled "Settings \u00B7 OcuTalon". The wildcard is titled "OcuTalon".
 * The Settings, History and Usage pages load lazily (`loadComponent`, Story 36.5; DW-1282), so their code stays out of the initial bundle: the
 * shell takes their titles and the settings matcher from page-shell-view.ts and imports nothing else from settings/ (but the guard and its dialog), history/ or usage/.
 * A navigation that a guard cancels puts the browser's history back as it was (canceledNavigationResolution 'computed'), so a back that the
 * user answered with Stay keeps the page it was going to.
 * A lazy page whose chunk can no longer be fetched (an upgrade removed the previous build's files while the tab was open) makes the router's navigation
 * error handler load the target address once more in full, at most once per address in a session (chunk-reload.ts); it shows no text.
 */
export const routes: Routes = [
  {
    matcher: settingsMatch,
    loadComponent: () => import('./settings/settings-page').then((m) => m.SettingsPage),
    title: SHELL_TEXTS.settingsTitle,
    canDeactivate: [unsavedGuard],
  },
  { path: 'documents', component: DocumentsPage, title: DOCUMENTS_TEXTS.title },
  { path: 'history', loadComponent: () => import('./history/history-page').then((m) => m.HistoryPage), title: SHELL_TEXTS.historyTitle },
  { path: 'usage', loadComponent: () => import('./usage/usage-page').then((m) => m.UsagePage), title: SHELL_TEXTS.usageTitle },
  { path: '**', component: MainPage, title: 'OcuTalon' },
];

/** Hash-based routing (the server only serves files). */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(withInterceptors([envelopeInterceptor])),
    provideRouter(
      routes,
      withHashLocation(),
      withRouterConfig({ canceledNavigationResolution: 'computed' }),
      withNavigationErrorHandler((failed) => {
        reloadForChunkError(failed.error, failed.url);
      }),
    ),
  ],
};
