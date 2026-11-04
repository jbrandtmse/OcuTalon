import { expect, test } from '@playwright/test';

import { unique } from '../support/floor';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted, seedTurns, turnRows } from '../support/iris';

/**
 * The floor unit's fixture hygiene (H1; Story 2.14's QA, DW-179): the turns and Decision rows that seedTurns writes are recorded for
 * Test.Data.Fixture.Clean, so a floor case that lists turnRows(seeded) in its refs leaves none of those rows behind in the floor user's
 * session (a case that does not list them still leaves its turns). It needs the stack that docker/tests/test-floor.sh starts
 * (the IRIS container that OCUTALON_E2E_IRIS_CONTAINER names) and the floor user; it opens no page.
 */
test.describe.configure({ timeout: 60_000 });

/** Whether the turn and the two Decision rows of a ref exist: "turn|triage|reply" as three 0 or 1 digits. */
async function present(turn: string, triage: string, reply: string): Promise<string> {
  const lines = await irisScript(
    [
      `Write !,"CHK|rows|",$IsObject(##class(OcuTalon.Data.Turn).RefIndexOpen(${quoted(turn)})),"|",$IsObject(##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(${quoted(triage)})),"|",$IsObject(##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(${quoted(reply)}))`,
    ].join('\n'),
  );
  return chk(lines, 'rows') ?? 'no answer';
}

/** H1: cleanFixtureRows removes a seeded turn with both of its Decision rows, and only the rows it is given. */
test('H1: the turn and the decisions that seedTurns writes are removed by cleanFixtureRows', async () => {
  const { user } = fixtureUser('FLOOR');
  const kept: string[] = [];
  const dropped: string[] = [];
  try {
    const stamp = unique('H1');
    const decision = { outcome: 'act', reasons: 'zz first reason.', confidence: 0.9, costUSD: 0.0003 };
    const first = await seedTurns(user, [{ createdAt: '2019-06-01T10:00:00Z', text: `${stamp} first`, replyText: 'zz H1 reply.', triage: decision, turn: decision }]);
    dropped.push(...turnRows(first));
    const second = await seedTurns(user, [{ createdAt: '2019-06-02T10:00:00Z', text: `${stamp} second`, replyText: 'zz H1 reply.', triage: decision, turn: decision }]);
    kept.push(...turnRows(second));
    expect(dropped, 'the turn and its two decisions are listed').toHaveLength(3);
    expect(first.decisions[0]!.triage, 'the triage decision was written').not.toBe('');
    expect(first.decisions[0]!.turn, 'and the reply decision').not.toBe('');

    const own = (seeded: typeof first): Promise<string> => present(seeded.refs[0]!, seeded.decisions[0]!.triage, seeded.decisions[0]!.turn);
    expect(await own(first), 'the seeded rows exist before the clean-up').toBe('1|1|1');
    expect(await own(second), 'and so do the others').toBe('1|1|1');

    await cleanFixtureRows(dropped);
    expect(await own(first), 'the clean-up removed the turn and both decisions').toBe('0|0|0');
    expect(await own(second), 'and left the rows it was not given').toBe('1|1|1');
  } finally {
    await cleanFixtureRows([...dropped, ...kept]);
  }
});
