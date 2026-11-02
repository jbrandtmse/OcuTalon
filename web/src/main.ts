import { bootstrapApplication } from '@angular/platform-browser';

import { App } from './app/app';
import { appConfig } from './app/app.config';
import { applyTheme, storedTheme } from './app/theme/theme';

applyTheme(storedTheme());
bootstrapApplication(App, appConfig).catch((error: unknown) => console.error(error));
