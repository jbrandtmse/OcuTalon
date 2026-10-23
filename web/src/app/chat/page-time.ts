/**
 * The time of a chat entry as the page shows it (EXPERIENCE: Formats): hour and minute in the browser's zone and hour
 * format. pageTime adds no zone name; pageTimeBeside adds the browser zone's short name when that zone's UTC offset at the
 * instant differs from the instance's (UX-DR123). A framework-free module: it imports nothing and uses only erasable
 * TypeScript syntax, so Node runs it as it is.
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

/** The UTC offset in minutes of a zone at an instant, or undefined when the zone is not one that Intl knows. */
function offsetMinutes(date: Date, timeZone: string): number | undefined {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
    }).formatToParts(date);
    const field = (type: string): number => Number(parts.find((part) => part.type === type)?.value ?? Number.NaN);
    const wall = Date.UTC(field('year'), field('month') - 1, field('day'), field('hour'), field('minute'), field('second'));
    const whole = Math.floor(date.getTime() / 1000) * 1000;
    return Number.isNaN(wall) ? undefined : Math.round((wall - whole) / 60_000);
  } catch {
    return undefined;
  }
}

/**
 * The hour and minute of an ISO time as pageTime gives it, followed by a space and the short name of the browser's zone (such as
 * CEST, or GMT+5:30 where the locale has no abbreviation) when that zone's UTC offset at that instant differs from the instance
 * zone's, or when the instance zone is not a valid zone. Two zones with the same offset at the instant read the same clock, so
 * they get no suffix whatever their names. The locale and the browser's zone default to the browser's own; a test names both.
 * An empty or unreadable time gives "".
 */
export function pageTimeBeside(iso: string, instanceZone: string, locale?: string, timeZone?: string): string {
  const time = pageTime(iso, locale, timeZone);
  if (time === '') {
    return '';
  }
  const date = new Date(iso);
  const browserZone = timeZone ?? new Intl.DateTimeFormat().resolvedOptions().timeZone;
  const instance = offsetMinutes(date, instanceZone);
  if (instance !== undefined && instance === offsetMinutes(date, browserZone)) {
    return time;
  }
  const name = new Intl.DateTimeFormat(locale, { hour: 'numeric', timeZoneName: 'short', timeZone })
    .formatToParts(date)
    .find((part) => part.type === 'timeZoneName')?.value;
  return name === undefined ? time : `${time} ${name}`;
}
