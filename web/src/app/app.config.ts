import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withHashLocation, withRouterConfig, type Routes } from '@angular/router';

import { envelopeInterceptor } from './api/envelope.interceptor';
import { DocumentsPage } from './documents/documents-page';
import { DOCUMENTS_TEXTS } from './documents/documents-view';
import { HistoryPage } from './history/history-page';
import { HISTORY_TEXTS } from './history/history-view';
import { MainPage } from './main-page/main-page';
import { SettingsPage } from './settings/settings-page';
import { SETTINGS_TEXTS, settingsMatch } from './settings/settings-view';
import { unsavedGuard } from './settings/unsaved-guard';
import { UsagePage } from './usage/usage-page';
import { USAGE_TEXTS } from './usage/usage-view';

/**
 * The chat is the main page and the wildcard route, with no redirect: a deep link keeps its address. A later page adds its route before the
 * wildcard. The Documents page (Story 34.2) is the route #/documents, titled "Documents \u00B7 OcuTalon", and the History page (Story 25.2) is #/history, titled "History \u00B7 OcuTalon", and the Usage page (Story 37.2) is #/usage, titled "Usage \u00B7 OcuTalon". The settings page (Story 33.2) is one route for #/settings and #/settings/<slug> (settingsMatch), so a section change keeps the
 * page; it is guarded against leaving with unsaved changes and titled "Settings \u00B7 OcuTalon". The wildcard is titled "OcuTalon".
 * A navigation that a guard cancels puts the browser's history back as it was (canceledNavigationResolution 'computed'), so a back that the
 * user answered with Stay keeps the page it was going to.
 */
export const routes: Routes = [
  { matcher: settingsMatch, component: SettingsPage, title: SETTINGS_TEXTS.title, canDeactivate: [unsavedGuard] },
  { path: 'documents', component: DocumentsPage, title: DOCUMENTS_TEXTS.title },
  { path: 'history', component: HistoryPage, title: HISTORY_TEXTS.title },
  { path: 'usage', component: UsagePage, title: USAGE_TEXTS.title },
  { path: '**', component: MainPage, title: 'OcuTalon' },
];

/** Hash-based routing (the server only serves files). */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(withInterceptors([envelopeInterceptor])),
    provideRouter(routes, withHashLocation(), withRouterConfig({ canceledNavigationResolution: 'computed' })),
  ],
};
