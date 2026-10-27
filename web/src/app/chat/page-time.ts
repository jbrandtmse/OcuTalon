/**
 * The times of the page as it shows them (EXPERIENCE: Formats): hour and minute in the browser's zone and hour format.
 * pageTime adds no zone name; pageTimeBeside adds the browser zone's short name when that zone's UTC offset at the
 * instant differs from the instance's (UX-DR123); pageWhen adds the day when the time is not today's, in English day and
 * month names whatever the browser's language is; countdownText says how long is left until a time (UX-DR124), in the short
 * form and in the full words that assistive technology reads. A framework-free module: it imports nothing and uses only
 * erasable TypeScript syntax, so Node runs it as it is.
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

/** The day words of pageWhen and the countdown words of countdownText. */
export const WHEN_TEXTS = {
  tomorrowAt: 'tomorrow at {time}',
  dayAt: '{day} at {time}',
  weekdays: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
  months: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  dateWithYear: '{month} {day}, {year}',
  date: '{month} {day}',
  seconds: 'in {n} s',
  secondsOne: 'in {n} second',
  secondsOther: 'in {n} seconds',
  minutes: 'in {n} min',
  minutesOne: 'in {n} minute',
  minutesOther: 'in {n} minutes',
  hours: 'in {h} h {m} min',
  hoursOne: 'in {h} hour {m} {minutes}',
  hoursOther: 'in {h} hours {m} {minutes}',
  minuteOne: 'minute',
  minuteOther: 'minutes',
  elapsedSeconds: '{n} s',
  elapsedSecondsOne: '{n} second',
  elapsedSecondsOther: '{n} seconds',
  elapsedMinutes: '{n} min',
  elapsedMinutesOne: '{n} minute',
  elapsedMinutesOther: '{n} minutes',
} as const;

const DAY_MS = 86_400_000;

const dayFormatters = new Map<string, Intl.DateTimeFormat>();

/** The calendar date of an instant in the zone (the browser's own when undefined), as a day number since 1970-01-01 and the date's parts. */
function calendarDay(ms: number, timeZone: string | undefined): { days: number; year: number; month: number; day: number } {
  const id = timeZone ?? '';
  let found = dayFormatters.get(id);
  if (found === undefined) {
    found = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: 'numeric', day: 'numeric' });
    dayFormatters.set(id, found);
  }
  const parts = found.formatToParts(new Date(ms));
  const field = (type: string): number => Number(parts.find((part) => part.type === type)?.value);
  const year = field('year');
  const month = field('month');
  const day = field('day');
  return { days: Math.round(Date.UTC(year, month - 1, day) / DAY_MS), year, month, day };
}

const fill = (template: string, values: Readonly<Record<string, string>>): string =>
  template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');

/**
 * An ISO time as the page shows a time that may be on another day, in the browser's zone and hour format (the locale and the
 * zone default to the browser's; a test names both), the clock itself from pageTime:
 * - the same date as nowMs: "14:13";
 * - the next date: "tomorrow at 14:13";
 * - up to six dates either way: "Monday at 14:13";
 * - further: "Oct 17 at 14:12", with the year after the day when it differs from nowMs's year: "Oct 17, 2025 at 14:12".
 * An empty or unreadable time gives "".
 */
export function pageWhen(iso: string, nowMs: number, locale?: string, timeZone?: string): string {
  const time = pageTime(iso, locale, timeZone);
  if (time === '') {
    return '';
  }
  const at = calendarDay(new Date(iso).getTime(), timeZone);
  const today = calendarDay(nowMs, timeZone);
  const apart = at.days - today.days;
  if (apart === 0) {
    return time;
  }
  if (apart === 1) {
    return fill(WHEN_TEXTS.tomorrowAt, { time });
  }
  if (Math.abs(apart) <= 6) {
    return fill(WHEN_TEXTS.dayAt, { day: WHEN_TEXTS.weekdays[(((at.days + 4) % 7) + 7) % 7] ?? '', time });
  }
  const date = fill(at.year === today.year ? WHEN_TEXTS.date : WHEN_TEXTS.dateWithYear, {
    month: WHEN_TEXTS.months[at.month - 1] ?? '',
    day: String(at.day),
    year: String(at.year),
  });
  return fill(WHEN_TEXTS.dayAt, { day: date, time });
}

/** The text with the count in it: the singular for 1 and the plural for any other count. */
const plural = (n: number, one: string, other: string): string => fill(n === 1 ? one : other, { n: String(n) });

/** A time span of the page, short ("in 59 s", "23 s") and spoken ("in 59 seconds", "23 seconds"). */
export interface Countdown {
  text: string;
  spoken: string;
}

/**
 * The time left from nowMs until an ISO time, counted in whole seconds rounded up and never below 0: under a minute "in 23 s",
 * under an hour in whole minutes rounded down "in 9 min", from one hour "in 1 h 42 min" (always both units); past due is "in 0 s".
 * The spoken form uses full words with singular and plural agreeing. An empty or unreadable time gives empty texts.
 */
export function countdownText(dueIso: string, nowMs: number): Countdown {
  const due = new Date(dueIso).getTime();
  if (dueIso === '' || Number.isNaN(due)) {
    return { text: '', spoken: '' };
  }
  const seconds = Math.max(0, Math.ceil((due - nowMs) / 1000));
  if (seconds < 60) {
    return { text: fill(WHEN_TEXTS.seconds, { n: String(seconds) }), spoken: plural(seconds, WHEN_TEXTS.secondsOne, WHEN_TEXTS.secondsOther) };
  }
  if (seconds < 3600) {
    const minutes = Math.floor(seconds / 60);
    return { text: fill(WHEN_TEXTS.minutes, { n: String(minutes) }), spoken: plural(minutes, WHEN_TEXTS.minutesOne, WHEN_TEXTS.minutesOther) };
  }
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return {
    text: fill(WHEN_TEXTS.hours, { h: String(hours), m: String(minutes) }),
    spoken: fill(hours === 1 ? WHEN_TEXTS.hoursOne : WHEN_TEXTS.hoursOther, {
      h: String(hours),
      m: String(minutes),
      minutes: minutes === 1 ? WHEN_TEXTS.minuteOne : WHEN_TEXTS.minuteOther,
    }),
  };
}

/**
 * The time that has passed from an ISO time to nowMs, in whole seconds rounded down and never below 0: under a minute "23 s", from a
 * minute in whole minutes rounded down "2 min". The spoken form uses full words with singular and plural agreeing. An empty or
 * unreadable time gives empty texts.
 */
export function elapsedText(sinceIso: string, nowMs: number): Countdown {
  const since = new Date(sinceIso).getTime();
  if (sinceIso === '' || Number.isNaN(since)) {
    return { text: '', spoken: '' };
  }
  const seconds = Math.max(0, Math.floor((nowMs - since) / 1000));
  if (seconds < 60) {
    return { text: fill(WHEN_TEXTS.elapsedSeconds, { n: String(seconds) }), spoken: plural(seconds, WHEN_TEXTS.elapsedSecondsOne, WHEN_TEXTS.elapsedSecondsOther) };
  }
  const minutes = Math.floor(seconds / 60);
  return { text: fill(WHEN_TEXTS.elapsedMinutes, { n: String(minutes) }), spoken: plural(minutes, WHEN_TEXTS.elapsedMinutesOne, WHEN_TEXTS.elapsedMinutesOther) };
}
