/**
 * The sentence above the check rows of a reply (DW-90, AD-28, AD-32): the catalog text of the check key, with {whatFailed} built
 * from the rows. A framework-free module: it imports only a type and uses only erasable TypeScript syntax, so Node runs it as it
 * is. The catalog and the time function are passed in, so the module holds no import of the generated catalog or of the page's time
 * format.
 *
 * - checks.allPassed, checks.everythingElsePassed and checks.nothingWatched give the catalog text as it is. The rows never make an
 *   all-clear: only the key, which the server chose in code, can say that everything passed.
 * - checks.notEverything and checks.notEverythingRestPassed fill {whatFailed} from the rows that did not pass: the failed rows
 *   first, then the others, each group in row order, and never a passed row. A row is `{entry} ({finding}, at {time})`, with the
 *   finding's first letter in lower case and an empty part left out; a row with no entry is skipped; the rows are joined with "; ".
 *   The sentence is "" when no row is left to name.
 * - Any other key gives "".
 */
import type { CheckRow } from '../live/payloads';

/** The forms of one named row and of the list. {detail} is {finding}, at {time}; with no time it is the finding, with no finding at {time}. */
export const CHECK_TEXTS = {
  entry: '{entry} ({detail})',
  detail: '{finding}, at {time}',
  detailTime: 'at {time}',
  separator: '; ',
} as const;

/** The part of the generated catalog that the sentence reads, and its renderer. */
export interface CheckCatalog {
  readonly texts: Readonly<Record<string, string>>;
  readonly slots: Readonly<Record<string, Readonly<Record<string, string>>>>;
  render(key: string, slots: Readonly<Record<string, unknown>>): string;
}

/** The keys whose text has no slot: the catalog text is the sentence. */
const PLAIN_KEYS: readonly string[] = ['checks.allPassed', 'checks.everythingElsePassed', 'checks.nothingWatched'];
/** The keys whose text names what failed. */
const WHAT_FAILED_KEYS: readonly string[] = ['checks.notEverything', 'checks.notEverythingRestPassed'];

/** A form with its {name} placeholders filled in one pass: a value is never read as a placeholder. */
function fill(form: string, values: Readonly<Record<string, string>>): string {
  return form.replace(/\{([^{}]*)\}/g, (_placeholder: string, name: string) => (Object.hasOwn(values, name) ? values[name] : ''));
}

/** A string with its ends trimmed; anything else is "". */
function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * What did not pass, as one text: every row whose result is not "passed" with an entry, the "failed" rows first and then the
 * others, each group in row order. A row is {entry} ({finding}, at {time}); `time` formats the row's checkedAt ("" for none).
 * "" when there is no such row.
 */
export function whatFailed(rows: readonly CheckRow[], time: (iso: string) => string): string {
  const failed: string[] = [];
  const other: string[] = [];
  for (const row of rows) {
    if (row === null || typeof row !== 'object' || row.result === 'passed') {
      continue;
    }
    const entry = text(row.entry);
    if (entry === '') {
      continue;
    }
    const finding = text(row.finding);
    const clock = text(time(text(row.checkedAt)));
    const lowered = finding === '' ? '' : finding.charAt(0).toLowerCase() + finding.slice(1);
    let detail = '';
    if (lowered !== '' && clock !== '') {
      detail = fill(CHECK_TEXTS.detail, { finding: lowered, time: clock });
    } else if (lowered !== '') {
      detail = lowered;
    } else if (clock !== '') {
      detail = fill(CHECK_TEXTS.detailTime, { time: clock });
    }
    const named = detail === '' ? entry : fill(CHECK_TEXTS.entry, { entry, detail });
    (row.result === 'failed' ? failed : other).push(named);
  }
  return [...failed, ...other].join(CHECK_TEXTS.separator);
}

/**
 * The sentence for a check key and its rows: the catalog text of a key without a slot, the text of checks.notEverything or
 * checks.notEverythingRestPassed with whatFailed filled in (and "" when nothing is left to name), and "" for any other key or a
 * key the catalog does not hold.
 */
export function checkSentence(key: string, rows: readonly CheckRow[], catalog: CheckCatalog, time: (iso: string) => string): string {
  if (!Object.hasOwn(catalog.texts, key)) {
    return '';
  }
  if (PLAIN_KEYS.includes(key)) {
    return catalog.texts[key] ?? '';
  }
  if (!WHAT_FAILED_KEYS.includes(key) || !Object.hasOwn(catalog.slots, key) || catalog.slots[key]?.['whatFailed'] !== 'text') {
    return '';
  }
  const failed = whatFailed(rows, time);
  return failed === '' ? '' : catalog.render(key, { whatFailed: failed });
}
