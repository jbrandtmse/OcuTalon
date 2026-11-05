import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withHashLocation, withRouterConfig, type Routes } from '@angular/router';

import { envelopeInterceptor } from './api/envelope.interceptor';
import { MainPage } from './main-page/main-page';
import { SettingsPage } from './settings/settings-page';
import { SETTINGS_TEXTS, settingsMatch } from './settings/settings-view';
import { unsavedGuard } from './settings/unsaved-guard';

/**
 * The chat is the main page and the wildcard route, with no redirect: a deep link keeps its address. A later page adds its route before the
 * wildcard. The settings page (Story 33.2) is one route for #/settings and #/settings/<slug> (settingsMatch), so a section change keeps the
 * page; it is guarded against leaving with unsaved changes and titled "Settings \u00B7 OcuTalon". The wildcard is titled "OcuTalon".
 * A navigation that a guard cancels puts the browser's history back as it was (canceledNavigationResolution 'computed'), so a back that the
 * user answered with Stay keeps the page it was going to.
 */
export const routes: Routes = [
  { matcher: settingsMatch, component: SettingsPage, title: SETTINGS_TEXTS.title, canDeactivate: [unsavedGuard] },
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
