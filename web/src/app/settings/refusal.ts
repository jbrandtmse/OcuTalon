import { HttpErrorResponse } from '@angular/common/http';

import type { SettingsError } from '../api/api-types';
import { type Refusal, refusalKind } from './settings-view';

/**
 * The one reading of a refused or failed settings call (DW-948), shared by every section that saves or sends: the status and the named fields of the
 * HttpErrorResponse, classified by refusalKind against the fields the section knows. An error that is not an HttpErrorResponse is a form error.
 * A section keeps only its own focus and announce lines.
 */
export function refusalOf(error: unknown, known: readonly string[]): Refusal {
  if (!(error instanceof HttpErrorResponse)) {
    return { kind: 'form', fields: [] };
  }
  return refusalKind(error.status, (error.error as SettingsError | undefined)?.fields, known);
}
