import { expect, test } from '../support/fixtures';

import { DIAG_BOUND_MS, describeDiagnosis, diagnosisScript, stateDiagnosis } from '../support/diagnose';
import { irisScript } from '../support/iris';

/**
 * Story 11.22 (DW-550): the `DIAG /state` read against the real IRIS of the stack that test-sign-in.sh started (OCUTALON_E2E_IRIS_CONTAINER),
 * where the hermetic cases of e2e/live/helper-waits.spec.ts only see a stand-in. The script must run in the OCUTALON namespace without an
 * error, print the licence readings and the CSP processes, and end without a line that says the read was unavailable; a query that cannot
 * be opened is named as unavailable and never read as "none held"; and a container that does not exist makes each of the two reads (the
 * licence read and Story 11.27's gateway read) print one `unavailable` line, which the caller never sees as an error.
 */

/** The `DIAG /state` lines that stateDiagnosis printed (other lines, such as a slow-step notice, are left out), with console.log put back. */
async function printedLines(): Promise<string[]> {
  const printed: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => {
    printed.push(args.map(String).join(' '));
  };
  try {
    await stateDiagnosis();
  } finally {
    console.log = original;
  }
  return printed.filter((line) => line.startsWith('DIAG /state '));
}

test.describe('story 11.22: the /state diagnosis on the real stack', () => {
  test('prints the licence units and the session-lock state, with no unavailable line', async () => {
    const lines = await printedLines();
    expect(lines.filter((line) => line.includes('unavailable')), lines.join('\n')).toEqual([]);
    const licence = lines.filter((line) => line.startsWith('DIAG /state licence:'));
    expect(licence, lines.join('\n')).toHaveLength(1);
    expect(licence[0]).toMatch(/^DIAG \/state licence: LUAvailable=\S+, LUConsumed=\S+, KeyEnforcedUnits=\S+, CSPUsers=\S+, InstanceConnections=\S+$/);
    expect(lines.some((line) => line.startsWith('DIAG /state session lock:')), 'the lock state is said, held or not').toBe(true);
    expect(lines.some((line) => line.startsWith('DIAG /state csp process: pid=')), 'the stack serving this unit has CSP processes').toBe(true);
  });

  test('a query that cannot be opened is named as unavailable, and an unread lock is not reported as none held', async () => {
    const lines = describeDiagnosis(
      await irisScript(diagnosisScript({ csp: '%SYS.NoSuchQuery:CONTROLPANEL', lock: '%SYS.NoSuchQuery:List' }), DIAG_BOUND_MS),
    );
    expect(lines.filter((line) => /^DIAG \/state (csp|lock) unavailable: \S/.test(line)), lines.join('\n')).toHaveLength(2);
    expect(lines.some((line) => line.startsWith('DIAG /state session lock:')), lines.join('\n')).toBe(false);
    expect(lines.some((line) => line.startsWith('DIAG /state licence:')), 'the rest of the read still runs').toBe(true);
  });

  test('a stack that cannot be reached prints one unavailable line per read and does not throw', async () => {
    const named = process.env['OCUTALON_E2E_IRIS_CONTAINER'];
    process.env['OCUTALON_E2E_IRIS_CONTAINER'] = 'ocutalon-no-such-container';
    try {
      const lines = await printedLines();
      expect(lines, lines.join('\n')).toHaveLength(2);
      expect(lines[0]).toMatch(/^DIAG \/state unavailable: \S/);
      expect(lines[1]).toMatch(/^DIAG \/state gateway unavailable: \S/);
    } finally {
      if (named === undefined) delete process.env['OCUTALON_E2E_IRIS_CONTAINER'];
      else process.env['OCUTALON_E2E_IRIS_CONTAINER'] = named;
    }
  });
});
