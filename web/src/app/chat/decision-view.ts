/**
 * What the decision strip, its details and the check rows say (Story 2.6): the fixed strings, the number formats and the small
 * rules that turn a decision payload into the lines of the strip. A framework-free module: it imports only types and uses only
 * erasable TypeScript syntax, so Node runs it as it is. The components render what it returns by interpolation only.
 *
 * - The formats follow the UX's Formats table: a cost keeps the tiers of the server's Msg.Catalog.Cost (so "<$0.0001" under
 *   $0.0001, four decimals under $0.01, three under $1, otherwise two, the tier being the one of the amount as shown), tokens
 *   have en-US thousands separators, a confidence has two decimals, and a duration has one decimal under a minute and whole
 *   minutes and seconds from a minute on.
 * - reasonLines puts a fallback's sentence first and then the decision's reasons, one line each, up to a maximum.
 * - outcomeOf names the chip of a decision: a fallback is always Tell now, and an outcome the page does not know has no chip.
 * - checkRowView says which result, word and icon a check row shows; only "passed" is Passed and only "failed" is Failed.
 */
import type { IconName } from '../icon/icon';
import type { Outcome } from './outcome-chip';

/** Every fixed string of the strip, the details and the check rows. The middle dot is U+00B7. */
export const DECISION_TEXTS = {
  confidence: 'Confidence {n}',
  fallbackFlag: 'Fallback',
  details: 'Details',
  detailsName: 'Decision details',
  rowTokens: 'Tokens',
  rowModel: 'Model',
  rowSteps: 'Agent steps',
  rowDuration: 'Duration',
  rowMessage: 'Decision message',
  rowCost: 'Cost',
  tokenInput: 'Input',
  tokenOutput: 'Output (includes thinking)',
  tokenCacheRead: 'Cache read',
  tokenCacheWrite: 'Cache write',
  costBoth: 'Decision {decision} \u00B7 Turn {turn}',
  costTiny: '<$0.0001',
  seconds: '{n} s',
  minutes: '{m} min {s} s',
  separator: ' \u00B7 ',
  passed: 'Passed',
  failed: 'Failed',
  notChecked: 'Not checked',
} as const;

/** The prefix of the catalog keys that are check sentences. */
export const CHECK_KEY_PREFIX = 'checks.';

/** The shape of the four token counts, as the decision and the turn cost carry them. */
export interface TokenCounts {
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
}

/** A number the page can show: finite, else 0. */
const finite = (value: number | undefined): number => (typeof value === 'number' && Number.isFinite(value) ? value : 0);

/**
 * The value rounded half up to the places on its decimal digits, as IRIS's $FNumber rounds the server's decimal amounts: 0.00015
 * is 0.0002 at four places, where the binary double behind it would round down. Fifteen significant digits are the digits a
 * double holds for a decimal amount of up to six decimals.
 */
function roundHalfUp(value: number, places: number): number {
  const scale = 10 ** places;
  return Math.round(Number((value * scale).toPrecision(15))) / scale;
}

/**
 * US dollars by the UX's rule, as the server's Msg.Catalog.Cost shows them: "<$0.0001" under $0.0001 (0 included), four decimals
 * under $0.01, three under $1, otherwise two, rounded half up on the decimal amount. The tier is the one of the amount as shown,
 * so 0.99996 is "$1.00" and 0.009996 is "$0.010". An amount that is absent or not a number is 0.
 */
export function formatCost(amount: number | undefined): string {
  const value = Math.max(0, finite(amount));
  if (value < 0.0001) {
    return DECISION_TEXTS.costTiny;
  }
  let places = value < 0.01 ? 4 : value < 1 ? 3 : 2;
  if (places === 4 && roundHalfUp(value, 4) >= 0.01) {
    places = 3;
  }
  if (places === 3 && roundHalfUp(value, 3) >= 1) {
    places = 2;
  }
  return `$${roundHalfUp(value, places).toFixed(places)}`;
}

const TOKENS = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });

/** A token count with en-US thousands separators; an absent count is 0. */
export function formatTokens(count: number | undefined): string {
  return TOKENS.format(Math.max(0, Math.round(finite(count))));
}

/** A confidence with two decimals; an absent one is 0.00. */
export function formatConfidence(confidence: number | undefined): string {
  return finite(confidence).toFixed(2);
}

/**
 * A duration in milliseconds: one decimal under a minute ("3.4 s"), whole minutes and seconds from a minute on ("1 min 3 s"). The
 * tier is the one of the amount as shown, so 59949 ms is "59.9 s" and 59950 ms is "1 min 0 s".
 */
export function formatDuration(ms: number | undefined): string {
  const value = Math.max(0, finite(ms));
  const tenths = Math.round(value / 100);
  if (tenths < 600) {
    return DECISION_TEXTS.seconds.replace('{n}', () => (tenths / 10).toFixed(1));
  }
  const total = Math.round(value / 1000);
  return DECISION_TEXTS.minutes.replace('{m}', () => String(Math.floor(total / 60))).replace('{s}', () => String(total % 60));
}

/** "Confidence 0.92". */
export function confidenceText(confidence: number | undefined): string {
  return DECISION_TEXTS.confidence.replace('{n}', () => formatConfidence(confidence));
}

/** The four token kinds with their counts, joined by the separator: Input 1,084, Output (includes thinking) 312, Cache read 0, Cache write 0. */
export function tokensLine(tokens: TokenCounts): string {
  return [
    `${DECISION_TEXTS.tokenInput} ${formatTokens(tokens.inputTokens)}`,
    `${DECISION_TEXTS.tokenOutput} ${formatTokens(tokens.outputTokens)}`,
    `${DECISION_TEXTS.tokenCacheRead} ${formatTokens(tokens.cacheReadTokens)}`,
    `${DECISION_TEXTS.tokenCacheWrite} ${formatTokens(tokens.cacheWriteTokens)}`,
  ].join(DECISION_TEXTS.separator);
}

/** The text as a sentence: its first letter in capitals and a full stop at the end, unless it ends one already. */
export function sentenceOf(text: string): string {
  const trimmed = text.trim();
  if (trimmed === '') {
    return '';
  }
  const capital = trimmed.charAt(0).toUpperCase() + trimmed.slice(1);
  return /[.!?]$/.test(capital) ? capital : `${capital}.`;
}

/**
 * The reason lines of a strip: the fallback's sentence first when there is one, then the decision's reasons split into lines,
 * trimmed, with the empty ones dropped, at most max lines in all.
 */
export function reasonLines(reasons: string | undefined, fallbackSentence: string | undefined, max: number): string[] {
  const lines = (reasons ?? '')
    .split(/\r\n|\r|\n/)
    .map((line) => line.trim())
    .filter((line) => line !== '');
  if (fallbackSentence !== undefined && fallbackSentence !== '') {
    lines.unshift(fallbackSentence);
  }
  return lines.slice(0, Math.max(0, max));
}

/**
 * The cost row of the details: "Decision $0.0003", the separator and "Turn $0.0008" when the turn's cost is above the decision's as
 * shown, otherwise the decision's cost alone: two amounts that show the same figure are shown once.
 */
export function costRow(decisionCost: number | undefined, turnCost: number | undefined): string {
  const decision = formatCost(decisionCost);
  if (turnCost === undefined || finite(turnCost) <= finite(decisionCost)) {
    return decision;
  }
  const turn = formatCost(turnCost);
  if (turn === decision) {
    return decision;
  }
  return DECISION_TEXTS.costBoth.replace('{decision}', () => decision).replace('{turn}', () => turn);
}

/** The chip a decision shows: Tell now for a fallback, else its outcome; none for an outcome the page does not know. */
export function outcomeOf(outcome: string | undefined, fallback: boolean | undefined): Outcome | undefined {
  if (fallback) {
    return 'tell-now';
  }
  switch (outcome) {
    case 'tellnow':
      return 'tell-now';
    case 'ignore':
    case 'digest':
    case 'act':
      return outcome;
    default:
      return undefined;
  }
}

/** What a check row shows for its result. */
export interface CheckRowView {
  result: 'passed' | 'failed' | 'not-checked';
  word: string;
  icon: IconName;
}

/** The result, word and icon of a check row: "passed" and "failed" are themselves; any other result, or none, is Not checked. */
export function checkRowView(row: { result?: string } | undefined): CheckRowView {
  switch (row?.result) {
    case 'passed':
      return { result: 'passed', word: DECISION_TEXTS.passed, icon: 'circle-check' };
    case 'failed':
      return { result: 'failed', word: DECISION_TEXTS.failed, icon: 'circle-x' };
    default:
      return { result: 'not-checked', word: DECISION_TEXTS.notChecked, icon: 'circle-dashed' };
  }
}
