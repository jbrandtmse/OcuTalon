/**
 * The time of a chat entry as the page shows it (EXPERIENCE: Formats): hour and minute in the browser's zone and hour
 * format, with no zone suffix. A framework-free module: it imports nothing and uses only erasable TypeScript syntax, so
 * Node runs it as it is.
 */

const formatters = new Map<string, Intl.DateTimeFormat>();

/** The formatter for a locale and zone (the browser's own when undefined), kept so that a long chat builds each once. */
function formatter(locale: string | undefined, timeZone: string | undefined): Intl.DateTimeFormat {
  const id = `${locale ?? ''}|${timeZone ?? ''}`;
  let found = formatters.get(id);
  if (found === undefined) {
    found = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone });
    formatters.set(id, found);
  }
  return found;
}

/**
 * The hour and minute of an ISO time, such as 2026-10-22T14:11:00Z. The locale and the zone default to the browser's; a test
 * names both. An empty or unreadable time gives "".
 */
export function pageTime(iso: string, locale?: string, timeZone?: string): string {
  const date = new Date(iso);
  if (iso === '' || Number.isNaN(date.getTime())) {
    return '';
  }
  return formatter(locale, timeZone).format(date);
}
