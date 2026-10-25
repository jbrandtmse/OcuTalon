import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withHashLocation, type Routes } from '@angular/router';

import { envelopeInterceptor } from './api/envelope.interceptor';
import { MainPage } from './main-page/main-page';

/**
 * Release 1 has one page, so one wildcard route and no redirect: a deep link keeps its address. A later page adds its
 * route before the wildcard.
 */
export const routes: Routes = [{ path: '**', component: MainPage }];

/** Hash-based routing (the server only serves files). */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(withInterceptors([envelopeInterceptor])),
    provideRouter(routes, withHashLocation()),
  ],
};
