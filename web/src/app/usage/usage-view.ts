/**
 * The Usage page's view model (Story 37.2; FR-52; EXPERIENCE: Step 6): the fixed strings of the page, the ranges and groupings, the rows of a grouping,
 * each day's largest request, the short date, and the chart's geometry. A framework-free module: it imports only types and page-shell-view.ts (the title) and uses only erasable
 * TypeScript syntax, so Node runs it as it is. The page decides nothing (AD-12, AD-20): the buckets and the request-size limit are the server's
 * (`GET /v1/usage`), and every group is a sum of buckets, so the totals of a grouping equal the sum of the usage rows.
 *
 * - USAGE_TEXTS is the page's own fixed strings. The labels it shares with the decision details (Tokens, Cost, Input, Output (includes thinking),
 *   Cache read, Cache write) and the agent names of the Settings page (Triage agent, Diagnosis agent, Chat agent) are not copied here: the page reads them
 *   from DECISION_TEXTS and SETTINGS_TEXTS.models.agents, and groupRows takes the agent names as its third argument.
 * - groupRows(response, grouping, agentNames) is one row per group with the four token kinds, tokens (Input + Output, because Input already includes the
 *   cache tokens), the cost, estimated (every bucket of the group is an estimate) and includesEstimates (some, not all). Day lists every date of the
 *   range, in order, with zeros for a day without use; Agent, Channel and Model list only the values that have a bucket in the range, sorted by label. The
 *   retry runners count under their agent and the compaction rows are the agent "Chat summaries".
 * - costText(amount, format) is a cost as the tables show it: an exact zero is "$0", and every other amount is what `format` (the shared formatCost)
 *   makes of it, so an amount under $0.0001 that is not zero keeps "<$0.0001". The page passes formatCost, as it passes the agent names to groupRows.
 * - largestByDay is the days with use and the largest estimated request of each; dayLabel is the short date; chartGeometry places one bar and one point
 *   for each row on separate token and cost scales.
 */
import { SHELL_TEXTS } from '../shared/page-shell-view.ts';
import type { UsageBucket, UsageDays, UsageResponse } from '../api/usage-types';

/** The page's own fixed strings. The separator in the title is U+00B7. */
export const USAGE_TEXTS = {
  title: SHELL_TEXTS.usageTitle,
  heading: 'Usage',
  range: 'Range',
  rangeOptions: { 1: 'Today', 7: 'Last 7 days', 30: 'Last 30 days' },
  groupBy: 'Group by',
  groupings: { day: 'Day', agent: 'Agent', channel: 'Channel', model: 'Model' },
  chartHeading: 'Tokens and cost',
  largestHeading: 'Largest request per day',
  largestColumn: 'Largest request (estimated)',
  largestCell: '{tokens} of {limit} tokens',
  empty: 'No model use in this period.',
  error: "Couldn't load your usage.",
  retry: 'Retry',
  chatSummaries: 'Chat summaries',
  costZero: '$0',
  channels: {
    web: 'Web chat',
    phone: 'Simulated phone',
    mailbox: 'Simulated mailbox',
    telegram: 'Telegram',
    email: 'Email',
    webhook: 'Webhook',
    slack: 'Slack',
    system: 'System',
    heartbeat: 'Heartbeat',
  },
  estimated: 'estimated',
  includesEstimates: 'includes estimates',
} as const;

/** The ranges the route accepts, in days. */
export const RANGES: readonly UsageDays[] = [1, 7, 30];

/** The range the page opens with. */
export const DEFAULT_RANGE: UsageDays = 7;

export type Grouping = 'day' | 'agent' | 'channel' | 'model';

/** The groupings, in the order of the control. */
export const GROUPINGS: readonly Grouping[] = ['day', 'agent', 'channel', 'model'];

/** The grouping the page opens with. */
export const DEFAULT_GROUPING: Grouping = 'day';

/** One row of a grouping: the sums of its buckets. */
export interface UsageRow {
  /** The group's identity: the date, the canonical agent, the channel or the model id. It is the data-key of the row's bar and point. */
  key: string;
  /** The group's name as the first column shows it. */
  label: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** Input plus output tokens. */
  tokens: number;
  costUSD: number;
  /** True when every bucket of the group is an estimate (a group of no bucket is not). */
  estimated: boolean;
  /** True when some, not every, bucket of the group is an estimate. */
  includesEstimates: boolean;
}

/** The agent that a runner's stored name counts under: the retry runners count under their agent. */
const RETRY = /^(TriageAgent|DiagnosisAgent|ChatAgent)Retry$/;

/** The stored name of the compaction agent. */
const COMPACTION = 'compaction';

/** The canonical agent of a stored agent value: a retry runner is its agent; anything else is itself. */
export function agentKey(agent: string): string {
  return RETRY.exec(agent)?.[1] ?? agent;
}

/** The name of a canonical agent: the Settings page's name, "Chat summaries" for compaction, and an unknown value as it is. */
export function agentLabel(agent: string, agentNames: Readonly<Record<string, string>>): string {
  if (agent === COMPACTION) {
    return USAGE_TEXTS.chatSummaries;
  }
  return Object.prototype.hasOwnProperty.call(agentNames, agent) ? agentNames[agent] : agent;
}

/** The name of a stored channel: the page's name, and an unknown value as it is. */
export function channelLabel(channel: string): string {
  const names: Readonly<Record<string, string>> = USAGE_TEXTS.channels;
  return Object.prototype.hasOwnProperty.call(names, channel) ? names[channel] : channel;
}

/** A number the page can sum: finite, else 0. */
const finite = (value: number | undefined): number => (typeof value === 'number' && Number.isFinite(value) ? value : 0);

/** Costs are decimal amounts of up to six places; a sum is rounded to them so that a binary double's tail never shows. */
const roundCost = (value: number): number => Math.round(Number((value * 1e6).toPrecision(15))) / 1e6;

interface Accumulator {
  key: string;
  label: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  costUSD: number;
  buckets: number;
  estimatedBuckets: number;
}

const accumulator = (key: string, label: string): Accumulator => ({
  key,
  label,
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
  costUSD: 0,
  buckets: 0,
  estimatedBuckets: 0,
});

const rowOf = (sum: Accumulator): UsageRow => ({
  key: sum.key,
  label: sum.label,
  inputTokens: sum.inputTokens,
  outputTokens: sum.outputTokens,
  cacheReadTokens: sum.cacheReadTokens,
  cacheWriteTokens: sum.cacheWriteTokens,
  tokens: sum.inputTokens + sum.outputTokens,
  costUSD: roundCost(sum.costUSD),
  estimated: sum.buckets > 0 && sum.estimatedBuckets === sum.buckets,
  includesEstimates: sum.estimatedBuckets > 0 && sum.estimatedBuckets < sum.buckets,
});

/** The group of a bucket in a grouping: its key and its label. */
function groupOf(bucket: UsageBucket, grouping: Grouping, agentNames: Readonly<Record<string, string>>, today: string): { key: string; label: string } {
  switch (grouping) {
    case 'agent': {
      const key = agentKey(bucket.agent);
      return { key, label: agentLabel(key, agentNames) };
    }
    case 'channel':
      return { key: bucket.channel, label: channelLabel(bucket.channel) };
    case 'model':
      return { key: bucket.model, label: bucket.model };
    case 'day':
      return { key: bucket.day, label: dayLabel(bucket.day, today) };
  }
}

/**
 * The rows of a grouping. Day: one row for each date of the response's `days`, in order (a day with no use is zeros), labelled by dayLabel; a bucket of a
 * date outside `days` is not counted. Agent, channel and model: one row for each value that has a bucket, sorted by label (then key).
 */
export function groupRows(response: UsageResponse, grouping: Grouping, agentNames: Readonly<Record<string, string>>): UsageRow[] {
  const sums = new Map<string, Accumulator>();
  const today = response.days.length > 0 ? response.days[response.days.length - 1] : '';
  if (grouping === 'day') {
    for (const day of response.days) {
      sums.set(day, accumulator(day, dayLabel(day, today)));
    }
  }
  for (const bucket of response.buckets) {
    const { key, label } = groupOf(bucket, grouping, agentNames, today);
    let sum = sums.get(key);
    if (sum === undefined) {
      if (grouping === 'day') {
        continue;
      }
      sum = accumulator(key, label);
      sums.set(key, sum);
    }
    sum.inputTokens += finite(bucket.inputTokens);
    sum.outputTokens += finite(bucket.outputTokens);
    sum.cacheReadTokens += finite(bucket.cacheReadTokens);
    sum.cacheWriteTokens += finite(bucket.cacheWriteTokens);
    sum.costUSD += finite(bucket.costUSD);
    sum.buckets += 1;
    if (bucket.estimated) {
      sum.estimatedBuckets += 1;
    }
  }
  const rows = [...sums.values()].map(rowOf);
  if (grouping !== 'day') {
    rows.sort((a, b) => (a.label < b.label ? -1 : a.label > b.label ? 1 : a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  }
  return rows;
}

/** A day with use and the largest estimated request among its buckets, in tokens. */
export interface LargestDay {
  day: string;
  tokens: number;
}

/** The days that have a bucket, in the order of the response's `days`, each with the largest `largestRequestTokens` of its buckets. */
export function largestByDay(response: UsageResponse): LargestDay[] {
  const largest = new Map<string, number>();
  for (const bucket of response.buckets) {
    largest.set(bucket.day, Math.max(largest.get(bucket.day) ?? 0, finite(bucket.largestRequestTokens)));
  }
  return response.days.filter((day) => largest.has(day)).map((day) => ({ day, tokens: largest.get(day) ?? 0 }));
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

/**
 * A local date YYYY-MM-DD as the UX's short date: "Nov 9", and "Nov 9, 2025" when its year is not the year of today (also a local date). The date is a
 * calendar date: it is read from its digits, never through a time zone, so the browser's zone cannot shift it. Anything that is not a date is returned as it is.
 */
export function dayLabel(date: string, today: string): string {
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (parts === null || Number(parts[2]) < 1 || Number(parts[2]) > 12) {
    return date;
  }
  const short = `${MONTHS[Number(parts[2]) - 1]} ${Number(parts[3])}`;
  return today.slice(0, 4) === parts[1] ? short : `${short}, ${parts[1]}`;
}

/** The text of a largest-request cell: "{tokens} of {limit} tokens", the two numbers already formatted. */
export function largestText(tokens: string, limit: string): string {
  return USAGE_TEXTS.largestCell.replace('{tokens}', () => tokens).replace('{limit}', () => limit);
}

/** A bar of the chart: a rectangle for one row's tokens. */
export interface ChartBar {
  key: string;
  x: number;
  y: number;
  width: number;
  /** The bar's extent down from y to the baseline; 0 for a row with nothing. */
  length: number;
}

/** A point of the chart's cost line, at the middle of its row's band. */
export interface ChartPoint {
  key: string;
  x: number;
  y: number;
}

/** A horizontal gridline. */
export interface ChartGridline {
  y: number;
}

/** A direct label of a series, placed beside its last bar or point. */
export interface ChartLabel {
  x: number;
  y: number;
}

/** A category label under a band. */
export interface ChartCategory {
  key: string;
  x: number;
  y: number;
  text: string;
}

/** The chart's drawing for a width and a drawing height, in the same units. */
export interface ChartGeometry {
  width: number;
  /** The drawing's extent from top to bottom. */
  drawHeight: number;
  bars: ChartBar[];
  points: ChartPoint[];
  /** The cost line's points as an SVG `points` value; empty for no row. */
  line: string;
  gridlines: ChartGridline[];
  /** The token scale's top, in tokens, and the cost scale's top, in dollars. */
  tokenMax: number;
  costMax: number;
  tokensLabel: ChartLabel | null;
  costLabel: ChartLabel | null;
  categories: ChartCategory[];
}

/** The room of the plot: left and top margins, the right margin that holds the direct labels, and the bottom margin that holds the category labels. */
export const CHART_MARGIN = { left: 8, top: 12, right: 64, bottom: 28 } as const;

/** The least width of a category label, in the chart's units: a label is shown when its band, or the bands it spans, is at least this wide. */
const CATEGORY_MIN = 48;

/** The width of one character of a category label, in the chart's units. */
const CATEGORY_CHAR = 7;

const GRIDLINES = 4;

/** The least scale top above `value` that is 1, 2 or 5 times a power of ten; 1 for a value that is not positive. */
export function niceMax(value: number): number {
  if (!(value > 0) || !Number.isFinite(value)) {
    return 1;
  }
  const power = 10 ** Math.floor(Math.log10(value));
  for (const step of [1, 2, 5, 10]) {
    if (step * power >= value * (1 - 1e-9)) {
      return step * power;
    }
  }
  return 10 * power;
}

/** A category label cut to `max` characters, with U+2026 for what was cut. */
function cut(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1))}\u2026`;
}

/**
 * Where the chart's marks go in a drawing of `width` by `drawHeight`: one bar and one point for each row, in the rows' order, in equal bands. The bars use
 * the token scale (0 to tokenMax, `tokens` of each row) and the points the cost scale (0 to costMax), each scale its own, so that neither series is read
 * against the other's axis. A row with nothing has a bar of length 0. The series labels sit at the right of the last bar and the last point, apart
 * when they would meet. Category labels sit under the bands, every nth one when the bands are narrow. The marks never leave the plot, whatever the size.
 */
export function chartGeometry(rows: readonly UsageRow[], width: number, drawHeight: number): ChartGeometry {
  const w = Math.max(width, CHART_MARGIN.left + CHART_MARGIN.right + 1);
  const h = Math.max(drawHeight, CHART_MARGIN.top + CHART_MARGIN.bottom + 1);
  const left = CHART_MARGIN.left;
  const right = w - CHART_MARGIN.right;
  const top = CHART_MARGIN.top;
  const bottom = h - CHART_MARGIN.bottom;
  const plotExtent = bottom - top;
  const count = rows.length;
  const band = count > 0 ? (right - left) / count : 0;
  const tokenMax = niceMax(Math.max(0, ...rows.map((row) => row.tokens)));
  const costMax = niceMax(Math.max(0, ...rows.map((row) => row.costUSD)));
  const barWidth = Math.min(band, Math.max(1, Math.min(band * 0.6, 48)));
  const bars: ChartBar[] = [];
  const points: ChartPoint[] = [];
  rows.forEach((row, index) => {
    const middle = left + band * (index + 0.5);
    const barLength = (Math.min(row.tokens, tokenMax) / tokenMax) * plotExtent;
    bars.push({ key: row.key, x: middle - barWidth / 2, y: bottom - barLength, width: barWidth, length: barLength });
    points.push({ key: row.key, x: middle, y: bottom - (Math.min(row.costUSD, costMax) / costMax) * plotExtent });
  });
  const gridlines: ChartGridline[] = [];
  for (let line = 0; line <= GRIDLINES; line += 1) {
    gridlines.push({ y: bottom - (plotExtent * line) / GRIDLINES });
  }
  let tokensLabel: ChartLabel | null = null;
  let costLabel: ChartLabel | null = null;
  if (count > 0) {
    const lastBar = bars[count - 1];
    const lastPoint = points[count - 1];
    tokensLabel = { x: right + 6, y: Math.min(Math.max(lastBar.y, top + 12), bottom) };
    costLabel = { x: right + 6, y: Math.min(Math.max(lastPoint.y, top + 12), bottom) };
    if (Math.abs(costLabel.y - tokensLabel.y) < 16) {
      costLabel = { x: costLabel.x, y: tokensLabel.y + 16 };
    }
  }
  const categories: ChartCategory[] = [];
  if (count > 0) {
    const every = Math.max(1, Math.ceil(CATEGORY_MIN / band));
    const room = Math.max(1, Math.floor((band * every) / CATEGORY_CHAR));
    rows.forEach((row, index) => {
      if (index % every === 0) {
        categories.push({ key: row.key, x: left + band * (index + 0.5), y: bottom + 18, text: cut(row.label, room) });
      }
    });
  }
  return {
    width: w,
    drawHeight: h,
    bars,
    points,
    line: points.map((point) => `${round(point.x)},${round(point.y)}`).join(' '),
    gridlines,
    tokenMax,
    costMax,
    tokensLabel,
    costLabel,
    categories,
  };
}

/** A coordinate rounded to two places, for the SVG's attributes. */
export function round(value: number): number {
  return Math.round(value * 100) / 100;
}

/** A cost as the Usage tables show it: "$0" for an exact zero, otherwise `format` (the shared formatCost) of the amount. */
export function costText(amount: number, format: (amount: number) => string): string {
  return amount === 0 ? USAGE_TEXTS.costZero : format(amount);
}
