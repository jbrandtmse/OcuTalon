import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withHashLocation, type Routes } from '@angular/router';

import { envelopeInterceptor } from './api/envelope.interceptor';
import { MainPage } from './main-page/main-page';
import { SettingsPage } from './settings/settings-page';
import { SETTINGS_TEXTS } from './settings/settings-view';
import { unsavedGuard } from './settings/unsaved-guard';

/**
 * The chat is the main page and the wildcard route, with no redirect: a deep link keeps its address. A later page adds its route before the
 * wildcard. The settings page (Story 33.2) has its own route, #/settings, and one for each section, #/settings/<slug>; both are guarded against
 * leaving with unsaved changes and titled "Settings \u00B7 OcuTalon". The wildcard is titled "OcuTalon".
 */
export const routes: Routes = [
  { path: 'settings', component: SettingsPage, title: SETTINGS_TEXTS.title, canDeactivate: [unsavedGuard] },
  { path: 'settings/:section', component: SettingsPage, title: SETTINGS_TEXTS.title, canDeactivate: [unsavedGuard] },
  { path: '**', component: MainPage, title: 'OcuTalon' },
];

/** Hash-based routing (the server only serves files). */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(withInterceptors([envelopeInterceptor])),
    provideRouter(routes, withHashLocation()),
  ],
};
