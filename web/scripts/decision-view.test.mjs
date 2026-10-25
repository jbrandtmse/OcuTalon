// Tests the decision strip's view rules (src/app/chat/decision-view.ts): the fixed strings against the UX's wording, the cost format
// (the 14 cases of the server's Test.Msg.Catalog.TestCost and the rest of the matrix), the token, confidence and duration formats,
// the reason lines of a strip, the cost row of the details, the chip of an outcome and the view of a check row. The module is
// imported as it is: Node strips its types, which holds only while it keeps to erasable syntax and imports only types.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const {
  CHECK_KEY_PREFIX,
  DECISION_TEXTS,
  checkRowView,
  confidenceText,
  costRow,
  formatConfidence,
  formatCost,
  formatDuration,
  formatTokens,
  outcomeOf,
  reasonLines,
  sentenceOf,
  tokensLine,
} = await import(pathToFileURL(join(here, '..', 'src', 'app', 'chat', 'decision-view.ts')).href);

describe('the fixed strings', () => {
  it('are the UX\'s wording, written out here, with the middle dot U+00B7', () => {
    assert.deepEqual(
      { ...DECISION_TEXTS },
      {
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
      },
    );
    assert.equal(CHECK_KEY_PREFIX, 'checks.');
  });

  it('use no character outside printable ASCII except the middle dot', () => {
    for (const [name, text] of Object.entries(DECISION_TEXTS)) {
      assert.ok(!/[^\x20-\x7e\u00B7]/.test(text), name);
    }
  });
});

describe('formatCost', () => {
  it('is the server\'s rule: the 14 cases of Test.Msg.Catalog.TestCost', () => {
    const cases = [
      [5, '$5.00'],
      [1.24, '$1.24'],
      [0.042, '$0.042'],
      [0.0006, '$0.0006'],
      [0.00004, '<$0.0001'],
      [0, '<$0.0001'],
      [0.0001, '$0.0001'],
      [0.01, '$0.010'],
      [1, '$1.00'],
      [12.5, '$12.50'],
      [0.99996, '$1.00'],
      [0.99949, '$0.999'],
      [0.009996, '$0.010'],
      [0.009949, '$0.0099'],
    ];
    assert.equal(cases.length, 14);
    for (const [amount, shown] of cases) {
      assert.equal(formatCost(amount), shown, String(amount));
    }
  });

  it('shows the matrix\'s amounts: 0, 0.00004, 0.0006, 0.042, 0.99996 and 1.24', () => {
    assert.deepEqual([0, 0.00004, 0.0006, 0.042, 0.99996, 1.24].map(formatCost), ['<$0.0001', '<$0.0001', '$0.0006', '$0.042', '$1.00', '$1.24']);
  });

  it('takes the tier of the amount as shown, not of the amount', () => {
    assert.equal(formatCost(0.009996), '$0.010', 'not $0.0100');
    assert.equal(formatCost(0.99996), '$1.00', 'not $1.000');
  });

  it('rounds a tie up on the decimal amount, as the server does', () => {
    const ties = [
      [0.00015, '$0.0002'],
      [0.00035, '$0.0004'],
      [0.00045, '$0.0005'],
      [0.1235, '$0.124'],
      [1.005, '$1.01'],
      [0.009995, '$0.010'],
    ];
    for (const [amount, shown] of ties) {
      assert.equal(formatCost(amount), shown, String(amount));
    }
  });

  it('shows an absent amount, a negative one and one that is not a number as 0', () => {
    for (const amount of [undefined, -1, Number.NaN, Number.POSITIVE_INFINITY, null]) {
      assert.equal(formatCost(amount), '<$0.0001', String(amount));
    }
  });

  describe('over the whole range its rounding is exact: every amount of up to six decimals and under a billion dollars', () => {
    /** The cost rule on whole micro-dollars (BigInt, no binary double): the tier of the amount as shown, rounded half up. */
    const reference = (micros) => {
      if (micros < 100n) return '<$0.0001';
      const roundedAt = (places) => {
        const unit = 10n ** BigInt(6 - places);
        return (micros + unit / 2n) / unit;
      };
      let places = micros < 10_000n ? 4 : micros < 1_000_000n ? 3 : 2;
      if (places === 4 && roundedAt(4) >= 100n) places = 3;
      if (places === 3 && roundedAt(3) >= 1000n) places = 2;
      const scale = 10n ** BigInt(places);
      const rounded = roundedAt(places);
      return `$${rounded / scale}.${String(rounded % scale).padStart(places, '0')}`;
    };
    /** The amount a Usage row of scale 6 holds for these micro-dollars, as the page reads it from JSON. */
    const amountOf = (micros) => Number(micros) / 1e6;
    const check = (micros) => assert.equal(formatCost(amountOf(micros)), reference(micros), `${micros} micro-dollars`);
    const LIMIT = 999_999_999_999_999n;

    it('shows the amounts next to the limit of a billion dollars as the decimal amount rounds', () => {
      for (const micros of [LIMIT, LIMIT - 1n, 999_999_999_995_000n, 999_999_999_994_999n, 999_999_995_000_000n, 999_999_994_999_999n, 100_000_000_000_000n, 99_999_999_999_999n, 123_456_789_125_000n, 123_456_789_124_999n]) {
        check(micros);
      }
      assert.equal(formatCost(amountOf(999_999_999_995_000n)), '$1000000000.00', 'a tie at the top rounds up');
      assert.equal(formatCost(amountOf(999_999_999_994_999n)), '$999999999.99', 'and a hair under it does not');
    });

    it('rounds every tie of each tier up: the amount that ends in a 5 one place past the shown ones', () => {
      for (const [places, ks] of [
        [4, Array.from({ length: 101 }, (_, k) => k)],
        [3, Array.from({ length: 1001 }, (_, k) => k)],
        [2, [...Array.from({ length: 2001 }, (_, k) => k), 99_999, 100_000, 100_001, 12_345_678, 99_999_999, 100_000_000, 99_999_999_999]],
      ]) {
        const unit = 10n ** BigInt(6 - places);
        for (const k of ks) {
          const micros = BigInt(k) * unit + unit / 2n;
          if (micros <= LIMIT) check(micros);
        }
      }
    });

    it('agrees with the reference on 6000 amounts of every length from 1 to 15 digits', () => {
      let state = 0x2545f491n;
      const next = () => {
        state = (state * 6364136223846793005n + 1442695040888963407n) & 0xffffffffffffffffn;
        return state >> 11n;
      };
      for (let i = 0; i < 6000; i += 1) {
        const digits = 1 + (i % 15);
        const micros = next() % 10n ** BigInt(digits);
        check(micros);
      }
    });
  });
});

describe('formatTokens, formatConfidence and confidenceText', () => {
  it('groups thousands the en-US way, and shows an absent count as 0', () => {
    assert.deepEqual([0, 1084, 1234567, 999, 1000].map(formatTokens), ['0', '1,084', '1,234,567', '999', '1,000']);
    assert.equal(formatTokens(undefined), '0');
    assert.equal(formatTokens(Number.NaN), '0');
    assert.equal(formatTokens(-5), '0');
  });

  it('shows a confidence with two decimals', () => {
    assert.deepEqual([0.9, 0.92, 1, 0, 0.94].map(formatConfidence), ['0.90', '0.92', '1.00', '0.00', '0.94']);
    assert.equal(formatConfidence(undefined), '0.00');
    assert.equal(confidenceText(0.92), 'Confidence 0.92');
    assert.equal(confidenceText(0.9), 'Confidence 0.90');
  });
});

describe('formatDuration', () => {
  it('has one decimal under a minute and whole minutes and seconds from a minute on', () => {
    assert.deepEqual([0, 3400, 59949, 59950, 63000].map(formatDuration), ['0.0 s', '3.4 s', '59.9 s', '1 min 0 s', '1 min 3 s']);
  });

  it('takes the tier of the duration as shown: 59.95 s is a minute', () => {
    assert.equal(formatDuration(59949), '59.9 s');
    assert.equal(formatDuration(59950), '1 min 0 s');
    assert.equal(formatDuration(59999), '1 min 0 s');
  });

  it('keeps counting minutes past an hour, and shows an absent duration as 0', () => {
    assert.equal(formatDuration(3_600_000), '60 min 0 s');
    assert.equal(formatDuration(125_400), '2 min 5 s');
    assert.equal(formatDuration(undefined), '0.0 s');
    assert.equal(formatDuration(-4), '0.0 s');
  });
});

describe('tokensLine', () => {
  it('names the four kinds with their separators, in the UX\'s words', () => {
    assert.equal(
      tokensLine({ inputTokens: 1084, outputTokens: 312, cacheReadTokens: 0, cacheWriteTokens: 0 }),
      'Input 1,084 \u00B7 Output (includes thinking) 312 \u00B7 Cache read 0 \u00B7 Cache write 0',
    );
  });

  it('shows each count that is absent as 0', () => {
    assert.equal(tokensLine({}), 'Input 0 \u00B7 Output (includes thinking) 0 \u00B7 Cache read 0 \u00B7 Cache write 0');
    assert.equal(tokensLine({ cacheWriteTokens: 1234 }), 'Input 0 \u00B7 Output (includes thinking) 0 \u00B7 Cache read 0 \u00B7 Cache write 1,234');
  });
});

describe('sentenceOf', () => {
  it('starts with a capital letter and ends with a full stop', () => {
    assert.equal(sentenceOf("the model didn't answer within 60 seconds"), "The model didn't answer within 60 seconds.");
    assert.equal(sentenceOf("today's cost limit has been reached"), "Today's cost limit has been reached.");
  });

  it('leaves a sentence that is one, trims it, and gives nothing for nothing', () => {
    assert.equal(sentenceOf('Already done.'), 'Already done.');
    assert.equal(sentenceOf('  really?  '), 'Really?');
    assert.equal(sentenceOf(''), '');
    assert.equal(sentenceOf('   '), '');
  });
});

describe('reasonLines', () => {
  const four = 'one\ntwo\nthree\nfour';

  it('gives the newest strip three of four lines, and an older strip the first', () => {
    assert.deepEqual(reasonLines(four, undefined, 3), ['one', 'two', 'three']);
    assert.deepEqual(reasonLines(four, undefined, 1), ['one']);
  });

  it('puts a fallback\'s sentence first, inside the maximum', () => {
    assert.deepEqual(reasonLines(four, 'It timed out.', 3), ['It timed out.', 'one', 'two']);
    assert.deepEqual(reasonLines(four, 'It timed out.', 1), ['It timed out.']);
    assert.deepEqual(reasonLines('', 'It timed out.', 3), ['It timed out.']);
    assert.deepEqual(reasonLines(undefined, 'It timed out.', 3), ['It timed out.']);
  });

  it('splits on CRLF and CR too, trims each line and drops the blank ones', () => {
    assert.deepEqual(reasonLines('one\r\ntwo\rthree\n\n  \n  four  ', undefined, 10), ['one', 'two', 'three', 'four']);
    assert.deepEqual(reasonLines('\n\n  \n', undefined, 3), []);
  });

  it('gives no line for no reasons and no fallback, and none for a maximum of 0', () => {
    assert.deepEqual(reasonLines(undefined, undefined, 3), []);
    assert.deepEqual(reasonLines('', '', 3), []);
    assert.deepEqual(reasonLines(four, 'It timed out.', 0), []);
  });
});

describe('costRow', () => {
  it('shows the decision alone when the turn cost no more', () => {
    assert.equal(costRow(0.0003, 0.0003), '$0.0003');
    assert.equal(costRow(0.0003, 0.0002), '$0.0003');
    assert.equal(costRow(0.0003, undefined), '$0.0003');
    assert.equal(costRow(undefined, undefined), '<$0.0001');
  });

  it('shows the decision alone when the turn cost more by less than the shown figure', () => {
    assert.equal(costRow(0.00031, 0.00034), '$0.0003');
    assert.equal(costRow(0.00002, 0.00005), '<$0.0001');
    assert.equal(costRow(1.501, 1.504), '$1.50');
  });

  it('shows "Decision $x \u00B7 Turn $y" when the turn cost more', () => {
    assert.equal(costRow(0.0003, 0.0008), 'Decision $0.0003 \u00B7 Turn $0.0008');
    assert.equal(costRow(0.0003, 1.5), 'Decision $0.0003 \u00B7 Turn $1.50');
    assert.equal(costRow(undefined, 0.0008), 'Decision <$0.0001 \u00B7 Turn $0.0008');
  });
});

describe('outcomeOf', () => {
  it('maps tellnow to the tell-now chip and keeps the other three', () => {
    assert.deepEqual(['tellnow', 'ignore', 'digest', 'act'].map((outcome) => outcomeOf(outcome, false)), ['tell-now', 'ignore', 'digest', 'act']);
  });

  it('is Tell now for a fallback, whatever the outcome says', () => {
    for (const outcome of ['ignore', 'digest', 'act', 'tellnow', '', undefined, 'notify']) {
      assert.equal(outcomeOf(outcome, true), 'tell-now', String(outcome));
    }
  });

  it('has no chip for an outcome it does not know', () => {
    for (const outcome of ['notify', 'tell-now', 'Act', '', undefined, 'constructor']) {
      assert.equal(outcomeOf(outcome, false), undefined, String(outcome));
      assert.equal(outcomeOf(outcome, undefined), undefined, String(outcome));
    }
  });
});

describe('checkRowView', () => {
  it('shows passed, failed and not_checked with their word and icon', () => {
    assert.deepEqual(checkRowView({ result: 'passed' }), { result: 'passed', word: 'Passed', icon: 'circle-check' });
    assert.deepEqual(checkRowView({ result: 'failed' }), { result: 'failed', word: 'Failed', icon: 'circle-x' });
    assert.deepEqual(checkRowView({ result: 'not_checked' }), { result: 'not-checked', word: 'Not checked', icon: 'circle-dashed' });
  });

  it('shows a result it does not know, a different case and none as Not checked, never as Passed', () => {
    for (const row of [{ result: 'zz_unknown' }, { result: 'PASSED' }, { result: 'Passed' }, { result: ' passed' }, { result: '' }, {}, undefined, { result: 'constructor' }]) {
      assert.deepEqual(checkRowView(row), { result: 'not-checked', word: 'Not checked', icon: 'circle-dashed' }, JSON.stringify(row));
    }
  });
});
