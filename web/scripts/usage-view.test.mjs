// Tests the Usage page's view rules (src/app/usage/usage-view.ts; Story 37.2): the fixed strings against the ruled PUBLIC TEXT, the groupings (sums, order, zero
// days, the retry merge, the compaction and includes-estimates markers, unknown values, only the values that have rows), the largest request of each day, the
// short date, and the chart's geometry. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports
// only types and page-shell-view.ts; the shared agent names come from settings-view.ts, as the page passes them.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const app = (...parts) => pathToFileURL(join(here, '..', 'src', 'app', ...parts)).href;
const { CHART_MARGIN, DEFAULT_GROUPING, DEFAULT_RANGE, GROUPINGS, RANGES, USAGE_TEXTS, agentKey, agentLabel, channelLabel, chartGeometry, costText, dayLabel, groupRows, largestByDay, largestText, niceMax } =
  await import(app('usage', 'usage-view.ts'));
const { SETTINGS_TEXTS } = await import(app('settings', 'settings-view.ts'));
const { formatCost } = await import(app('chat', 'decision-view.ts'));

const NAMES = SETTINGS_TEXTS.models.agents;
const DAYS = ['2026-11-07', '2026-11-08', '2026-11-09'];

const bucket = (day, agent, channel, model, estimated, input, output, cacheRead, cacheWrite, costUSD, largestRequestTokens) => ({
  day,
  agent,
  channel,
  model,
  estimated,
  inputTokens: input,
  outputTokens: output,
  cacheReadTokens: cacheRead,
  cacheWriteTokens: cacheWrite,
  costUSD,
  largestRequestTokens,
});

/** The fixture: three days, the retry runner, the compaction row, three channels, two models, an unknown agent and an unknown channel. */
const RESPONSE = {
  days: DAYS,
  limit: 100000,
  buckets: [
    bucket('2026-11-07', 'ChatAgent', 'web', 'model-x', false, 100, 10, 20, 5, 0.001, 1000),
    bucket('2026-11-07', 'ChatAgentRetry', 'web', 'model-y', false, 40, 4, 0, 0, 0.0004, 4000),
    bucket('2026-11-09', 'TriageAgent', 'phone', 'model-x', false, 200, 20, 0, 0, 0.002, 500),
    bucket('2026-11-09', 'compaction', 'web', 'model-y', true, 300, 30, 0, 0, 0.003, 2000),
    bucket('2026-11-09', 'ChatAgent', 'web', 'model-y', false, 10, 1, 0, 0, 0, 100),
    bucket('2026-11-09', 'FutureAgent', 'carrier-pigeon', 'model-z', false, 7, 1, 0, 0, 0.0001, 50),
  ],
};

const EMPTY = { days: DAYS, limit: 100000, buckets: [] };

const brief = (rows) => rows.map((row) => [row.key, row.label, row.tokens, row.costUSD, row.estimated, row.includesEstimates]);

describe('the fixed strings', () => {
  it('are the ruled PUBLIC TEXT, written out here, with the middle dot U+00B7', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(USAGE_TEXTS)), {
      title: 'Usage \u00B7 OcuTalon',
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
    });
  });

  it('name the ranges 1, 7 (the default) and 30, and the groupings day (the default), agent, channel and model', () => {
    assert.deepEqual([...RANGES], [1, 7, 30]);
    assert.equal(DEFAULT_RANGE, 7);
    assert.deepEqual([...GROUPINGS], ['day', 'agent', 'channel', 'model']);
    assert.equal(DEFAULT_GROUPING, 'day');
  });

  it('use the Settings page\'s agent names, not copies of them', () => {
    assert.deepEqual({ ...NAMES }, { TriageAgent: 'Triage agent', DiagnosisAgent: 'Diagnosis agent', ChatAgent: 'Chat agent' });
    assert.equal(agentLabel('ChatAgent', NAMES), 'Chat agent');
  });
});

describe('groupRows by day', () => {
  it('lists every date of the range in order, with zeros for a day without use, and sums each day\'s buckets', () => {
    const rows = groupRows(RESPONSE, 'day', NAMES);
    assert.deepEqual(rows.map((row) => row.key), DAYS);
    assert.deepEqual(rows.map((row) => row.label), ['Nov 7', 'Nov 8', 'Nov 9']);
    assert.deepEqual(rows[0], {
      key: '2026-11-07',
      label: 'Nov 7',
      inputTokens: 140,
      outputTokens: 14,
      cacheReadTokens: 20,
      cacheWriteTokens: 5,
      tokens: 154,
      costUSD: 0.0014,
      estimated: false,
      includesEstimates: false,
    });
    assert.deepEqual(rows[1], { key: '2026-11-08', label: 'Nov 8', inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, tokens: 0, costUSD: 0, estimated: false, includesEstimates: false });
    assert.deepEqual(rows[2], {
      key: '2026-11-09',
      label: 'Nov 9',
      inputTokens: 517,
      outputTokens: 52,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      tokens: 569,
      costUSD: 0.0051,
      estimated: false,
      includesEstimates: true,
    });
  });

  it('counts input plus output as the tokens, because the input already includes the cache tokens', () => {
    const [row] = groupRows({ days: ['2026-11-09'], limit: 1, buckets: [bucket('2026-11-09', 'ChatAgent', 'web', 'm', false, 100, 10, 90, 5, 0, 1)] }, 'day', NAMES);
    assert.equal(row.tokens, 110);
    assert.equal(row.cacheReadTokens, 90);
  });

  it('marks a day that has an estimated bucket among others as including estimates, and a day of estimates alone as estimated', () => {
    const rows = groupRows({ days: ['2026-11-09', '2026-11-10'], limit: 1, buckets: [bucket('2026-11-10', 'compaction', 'web', 'm', true, 5, 1, 0, 0, 0, 1)] }, 'day', NAMES);
    assert.deepEqual([rows[0].estimated, rows[0].includesEstimates, rows[1].estimated, rows[1].includesEstimates], [false, false, true, false]);
  });

  it('leaves out a bucket of a date that is not in the range, so the rows still add up to the range', () => {
    const rows = groupRows({ days: ['2026-11-09'], limit: 1, buckets: [bucket('2026-11-01', 'ChatAgent', 'web', 'm', false, 9, 9, 0, 0, 9, 9)] }, 'day', NAMES);
    assert.deepEqual(brief(rows), [['2026-11-09', 'Nov 9', 0, 0, false, false]]);
  });

  it('keeps every date for an empty answer', () => {
    assert.deepEqual(groupRows(EMPTY, 'day', NAMES).map((row) => row.key), DAYS);
    assert.deepEqual(groupRows({ days: [], limit: 1, buckets: [] }, 'day', NAMES), []);
  });
});

describe('groupRows by agent, channel and model', () => {
  it('counts the retry runner under its agent and shows the compaction rows as Chat summaries, estimated, sorted by label', () => {
    const rows = groupRows(RESPONSE, 'agent', NAMES);
    assert.deepEqual(brief(rows), [
      ['ChatAgent', 'Chat agent', 165, 0.0014, false, false],
      ['compaction', 'Chat summaries', 330, 0.003, true, false],
      ['FutureAgent', 'FutureAgent', 8, 0.0001, false, false],
      ['TriageAgent', 'Triage agent', 220, 0.002, false, false],
    ]);
  });

  it('merges all three retry runners, and gives an unknown agent as it is', () => {
    assert.equal(agentKey('TriageAgentRetry'), 'TriageAgent');
    assert.equal(agentKey('DiagnosisAgentRetry'), 'DiagnosisAgent');
    assert.equal(agentKey('ChatAgentRetry'), 'ChatAgent');
    assert.equal(agentKey('ChatAgent'), 'ChatAgent');
    assert.equal(agentKey('compaction'), 'compaction');
    assert.equal(agentKey('Retry'), 'Retry');
    assert.equal(agentKey('ChatAgentRetryX'), 'ChatAgentRetryX');
    assert.equal(agentLabel('FutureAgent', NAMES), 'FutureAgent');
    assert.equal(agentLabel('compaction', NAMES), 'Chat summaries');
    assert.equal(agentLabel('toString', NAMES), 'toString');
  });

  it('shows only the agents that have rows in the range: no zero rows for an agent the install did not use', () => {
    const rows = groupRows({ days: DAYS, limit: 1, buckets: [bucket('2026-11-09', 'ChatAgent', 'web', 'm', false, 1, 1, 0, 0, 0, 1)] }, 'agent', NAMES);
    assert.deepEqual(rows.map((row) => row.key), ['ChatAgent']);
    assert.deepEqual(groupRows(EMPTY, 'agent', NAMES), []);
  });

  it('groups by channel with the channel names, sorted by label, and an unknown channel as it is', () => {
    const rows = groupRows(RESPONSE, 'channel', NAMES);
    assert.deepEqual(brief(rows), [
      ['phone', 'Simulated phone', 220, 0.002, false, false],
      ['web', 'Web chat', 495, 0.0044, false, true],
      ['carrier-pigeon', 'carrier-pigeon', 8, 0.0001, false, false],
    ]);
    for (const [key, label] of [['web', 'Web chat'], ['phone', 'Simulated phone'], ['mailbox', 'Simulated mailbox'], ['telegram', 'Telegram'], ['email', 'Email'], ['webhook', 'Webhook'], ['slack', 'Slack'], ['system', 'System'], ['heartbeat', 'Heartbeat']]) {
      assert.equal(channelLabel(key), label);
    }
    assert.equal(channelLabel('constructor'), 'constructor');
  });

  it('groups by model with the stored id, only for models with rows, and marks a model that includes the compaction estimate', () => {
    const rows = groupRows(RESPONSE, 'model', NAMES);
    assert.deepEqual(brief(rows), [
      ['model-x', 'model-x', 330, 0.003, false, false],
      ['model-y', 'model-y', 385, 0.0034, false, true],
      ['model-z', 'model-z', 8, 0.0001, false, false],
    ]);
  });

  it('adds up, in every grouping, to the sum of the buckets', () => {
    const total = (rows) =>
      rows.reduce(
        (sum, row) => [sum[0] + row.inputTokens, sum[1] + row.outputTokens, sum[2] + row.cacheReadTokens, sum[3] + row.cacheWriteTokens, Math.round((sum[4] + row.costUSD) * 1e6) / 1e6],
        [0, 0, 0, 0, 0],
      );
    for (const grouping of GROUPINGS) {
      assert.deepEqual(total(groupRows(RESPONSE, grouping, NAMES)), [657, 66, 20, 5, 0.0065], grouping);
    }
  });

  it('sums a cost without a binary double\'s tail', () => {
    const rows = groupRows({ days: ['2026-11-09'], limit: 1, buckets: [bucket('2026-11-09', 'ChatAgent', 'web', 'a', false, 1, 1, 0, 0, 0.1, 1), bucket('2026-11-09', 'ChatAgent', 'web', 'b', false, 1, 1, 0, 0, 0.2, 1)] }, 'day', NAMES);
    assert.equal(rows[0].costUSD, 0.3);
  });
});

describe('largestByDay', () => {
  it('lists the days with use, in the range\'s order, each with the largest request among its buckets, not their sum', () => {
    assert.deepEqual(largestByDay(RESPONSE), [
      { day: '2026-11-07', tokens: 4000 },
      { day: '2026-11-09', tokens: 2000 },
    ]);
    assert.deepEqual(largestByDay(EMPTY), []);
  });

  it('writes a cell as "{tokens} of {limit} tokens"', () => {
    assert.equal(largestText('12,345', '100,000'), '12,345 of 100,000 tokens');
  });
});

describe('costText', () => {
  // mutation: costText returns format(amount) for zero too -> "shows an exact zero as $0" red; costText returns "$0" for every amount under 0.0001 -> "keeps <$0.0001 for a non-zero amount under $0.0001" red.
  it('shows an exact zero as $0, the cost of a day or a group with no cost', () => {
    assert.equal(costText(0, formatCost), '$0');
  });

  it('keeps <$0.0001 for a non-zero amount under $0.0001', () => {
    assert.equal(costText(0.00004, formatCost), '<$0.0001');
    assert.equal(costText(0.00000001, formatCost), '<$0.0001');
  });

  it('leaves every other amount to formatCost: $0.0001, $0.0006, $0.042, $1.24', () => {
    assert.deepEqual([0.0001, 0.0006, 0.042, 1.24].map((amount) => costText(amount, formatCost)), ['$0.0001', '$0.0006', '$0.042', '$1.24']);
  });
});

describe('dayLabel', () => {
  it('is the short date: "Nov 9", with no leading zero, and the year only when it is not the year of today', () => {
    assert.equal(dayLabel('2026-11-09', '2026-11-09'), 'Nov 9');
    assert.equal(dayLabel('2026-01-05', '2026-11-09'), 'Jan 5');
    assert.equal(dayLabel('2025-12-31', '2026-01-02'), 'Dec 31, 2025');
    assert.equal(dayLabel('2026-12-31', '2026-12-31'), 'Dec 31');
  });

  it('reads the digits, so the process zone cannot shift the date', () => {
    const before = process.env.TZ;
    try {
      for (const zone of ['Pacific/Kiritimati', 'Pacific/Pago_Pago', 'UTC']) {
        process.env.TZ = zone;
        assert.equal(dayLabel('2026-03-01', '2026-03-01'), 'Mar 1', zone);
        assert.equal(dayLabel('2026-02-28', '2026-03-01'), 'Feb 28', zone);
      }
    } finally {
      if (before === undefined) delete process.env.TZ;
      else process.env.TZ = before;
    }
  });

  it('gives anything that is not a date as it is', () => {
    assert.equal(dayLabel('', '2026-11-09'), '');
    assert.equal(dayLabel('zz', '2026-11-09'), 'zz');
    assert.equal(dayLabel('2026-13-01', '2026-11-09'), '2026-13-01');
  });
});

describe('chartGeometry', () => {
  const rows = groupRows(RESPONSE, 'day', NAMES);

  it('has one bar and one point for each row, in the rows\' order, with the row\'s key', () => {
    const geometry = chartGeometry(rows, 640, 240);
    assert.deepEqual(geometry.bars.map((bar) => bar.key), DAYS);
    assert.deepEqual(geometry.points.map((point) => point.key), DAYS);
    assert.equal(geometry.line.split(' ').length, 3);
  });

  it('scales tokens and cost on their own scales: each series keeps its own scale top', () => {
    const geometry = chartGeometry(rows, 640, 240);
    const top = CHART_MARGIN.top;
    const bottom = 240 - CHART_MARGIN.bottom;
    assert.equal(geometry.tokenMax, 1000);
    assert.equal(geometry.costMax, 0.01);
    const plot = bottom - top;
    assert.equal(Math.round(geometry.bars[0].length), Math.round((154 / 1000) * plot), 'Nov 7: 154 of 1000');
    assert.equal(geometry.bars[1].length, 0, 'a day without use has a bar of length 0');
    assert.equal(Math.round(geometry.bars[2].length), Math.round((569 / 1000) * plot), 'Nov 9: 569 of 1000');
    assert.equal(Math.round(geometry.points[2].y), Math.round(bottom - (0.0051 / 0.01) * plot), 'the cost point is on the cost scale, 0.0051 of 0.01');
    assert.equal(geometry.points[1].y, bottom, 'no cost sits on the baseline');
    for (const bar of geometry.bars) assert.equal(Math.round((bar.y + bar.length) * 100) / 100, bottom, 'every bar stands on the baseline');
  });

  it('keeps every mark inside the plot, whatever the width', () => {
    for (const width of [0, 40, 320, 640, 1200]) {
      const geometry = chartGeometry(rows, width, 240);
      for (const bar of geometry.bars) {
        assert.ok(bar.x >= 0 && bar.x + bar.width <= geometry.width - CHART_MARGIN.right + 1e-6, `${width}: bar ${bar.key}`);
        assert.ok(bar.y >= CHART_MARGIN.top - 1e-6 && bar.length >= 0, `${width}: bar ${bar.key} length`);
      }
      for (const point of geometry.points) {
        assert.ok(point.x >= 0 && point.x <= geometry.width - CHART_MARGIN.right, `${width}: point ${point.key}`);
        assert.ok(point.y >= CHART_MARGIN.top - 1e-6 && point.y <= 240 - CHART_MARGIN.bottom + 1e-6, `${width}: point ${point.key} y`);
      }
    }
  });

  it('puts a point at the middle of its bar', () => {
    const geometry = chartGeometry(rows, 640, 240);
    geometry.bars.forEach((bar, index) => assert.ok(Math.abs(bar.x + bar.width / 2 - geometry.points[index].x) < 1e-9));
  });

  it('draws five gridlines, labels both series at the right, and keeps their labels apart', () => {
    const geometry = chartGeometry(rows, 640, 240);
    assert.equal(geometry.gridlines.length, 5);
    assert.ok(geometry.tokensLabel && geometry.costLabel);
    assert.ok(Math.abs(geometry.tokensLabel.y - geometry.costLabel.y) >= 16);
    assert.ok(geometry.tokensLabel.x > 640 - CHART_MARGIN.right);
  });

  it('draws nothing for no row, and a bar for one row', () => {
    const none = chartGeometry([], 640, 240);
    assert.deepEqual([none.bars, none.points, none.line, none.tokensLabel, none.costLabel, none.categories], [[], [], '', null, null, []]);
    assert.equal(none.tokenMax, 1);
    assert.equal(chartGeometry(rows.slice(0, 1), 640, 240).bars.length, 1);
  });

  it('labels the bands with the rows\' names, every nth when they are narrow, and cuts a long name', () => {
    const wide = chartGeometry(rows, 640, 240);
    assert.deepEqual(wide.categories.map((category) => category.text), ['Nov 7', 'Nov 8', 'Nov 9']);
    const many = Array.from({ length: 30 }, (_, index) => ({ ...rows[0], key: `k${index}`, label: `Label ${index}` }));
    const narrow = chartGeometry(many, 640, 240);
    assert.ok(narrow.categories.length < 30 && narrow.categories.length >= 5, `every nth: ${narrow.categories.length}`);
    const long = chartGeometry([{ ...rows[0], label: 'a-very-long-model-identifier-1234567890' }, ...rows.slice(1)], 300, 240);
    assert.ok(long.categories[0].text.length < 'a-very-long-model-identifier-1234567890'.length && long.categories[0].text.endsWith('\u2026'));
  });

  it('rounds a scale top up to 1, 2 or 5 times a power of ten', () => {
    assert.deepEqual([0, -1, NaN, 1, 154, 539, 1000, 1001, 2000, 4999, 5001, 0.0051, 0.0004].map(niceMax), [1, 1, 1, 1, 200, 1000, 1000, 2000, 2000, 5000, 10000, 0.01, 0.0005]);
  });
});
