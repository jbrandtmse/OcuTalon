import { publishFixtureEvent } from './devices';
import { chk, irisScript, quoted } from './iris';

/** The guide's marker endpoint (Story 4.7: trace_opened and run_again). */
export const GUIDE_MARKERS = '/ocutalon/api/v1/guide/markers';

/**
 * What the demo guide's floor cases (floor/guide.spec.ts, Story 4.4) add to the fixtures of support/iris.ts: the Orders production's
 * identity as a watch check names it, a `watch.progress` event on the user's own stream, and the removal of what a real press of Break
 * the feed leaves behind for a session that is no fixture session (the FLOOR session's: Test.Data.Fixture.Clean keeps its run rows).
 */

/** The namespace and the production that make a check the Orders watch (Demo.Guide). */
export const ORDERS = { namespace: 'OCUORDERS', production: 'OcuTalon.Demo.Orders.Production' } as const;

/**
 * Publishes a `watch.progress` event on the user's own session stream, as the incident manager will (Epic 5), and returns its Seq. Nothing
 * publishes one in this tree, so a case does it through Live.Publish, as publishCheck does for a check.
 */
export function publishWatchProgress(user: string, fields: { ref: string; stage: 'noticed' | 'settling' | 'diagnosing' }): Promise<number> {
  return publishFixtureEvent(user, 'watch.progress', 'OcuTalon.Live.Payload.WatchProgress', { Ref: fields.ref, Stage: fields.stage });
}

/**
 * Deletes the Break the feed runs of the user's session and the batches that the session's runs sent to OCUORDERS (the messages whose
 * SuperSession is the session's TraceRef, Test.Data.Fixture.RemoveMessages), so that no run of one case shows in the next case's guide.
 */
export async function dropBreakFeed(user: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set st=##class(%SQL.Statement).%New()',
      'Set sc=st.%Prepare("DELETE FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ?")',
      'Set rs=st.%Execute(s.Ref)',
      'Set tr=s.TraceRef',
      'Set rm=1',
      'If tr\'="" Set rm=##class(OcuTalon.Test.Data.Fixture).RemoveMessages([(tr)],"OCUORDERS")',
      'Write !,"CHK|dropped|",$Select($System.Status.IsOK(sc)&&(rs.%SQLCODE>=0)&&$System.Status.IsOK(rm):1,1:0)',
    ].join('\n'),
  );
  if (chk(lines, 'dropped') !== '1') throw new Error(`the Break the feed runs could not be removed (${lines.join(' ')})`);
}

/**
 * Waits until the batches that the user's session sent to OCUORDERS stop growing (two reads one second apart agree, with at least one
 * message), so that dropBreakFeed does not run while a run's messages are still arriving. It gives up after 30 reads (each a call into
 * IRIS, then a 1 s pause) and lets the removal run; a case calls it only after a press.
 */
export async function settleBatch(user: string): Promise<void> {
  let before = -1;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const lines = await irisScript(
      [
        `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
        'Set tr=s.TraceRef',
        'Set $NAMESPACE="OCUORDERS"',
        'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SuperSession = ?",tr)',
        'Do rs.%Next()',
        'Write !,"CHK|count|",rs.%GetData(1)',
      ].join('\n'),
    );
    const count = Number(chk(lines, 'count'));
    if (Number.isInteger(count) && count > 0 && count === before) return;
    before = Number.isInteger(count) ? count : -1;
    await new Promise((done) => setTimeout(done, 1000));
  }
}

/**
 * Recomputes the user's guide and publishes it when it changed (Live.Publish.RefreshGuide, the guide.state event's one publisher), so
 * that a row a case seeds directly shows in the open page: the check and reminder events refresh the guide themselves, nothing else a
 * case seeds does.
 */
export async function refreshGuide(user: string): Promise<void> {
  const lines = await irisScript(
    [`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`, 'Set sc=##class(OcuTalon.Live.Publish).RefreshGuide(s.Ref)', 'Write !,"CHK|refreshed|",$System.Status.IsOK(sc)'].join('\n'),
  );
  if (chk(lines, 'refreshed') !== '1') throw new Error(`the guide could not be refreshed (${lines.join(' ')})`);
}

/** Writes a Break the feed run of the user's session in the state, started at the UTC time (Test.Data.Fixture.BreakFeedRun); dropBreakFeed removes it. */
export async function seedBreakFeedRun(user: string, state: 'sending' | 'sent', startedAt: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      `Set r=##class(OcuTalon.Test.Data.Fixture).BreakFeedRun(s.Ref,${quoted(state)},${quoted(startedAt)})`,
      'Write !,"CHK|run|",(r=s.Ref)',
    ].join('\n'),
  );
  if (chk(lines, 'run') !== '1') throw new Error(`the Break the feed run could not be seeded (${lines.join(' ')})`);
}

/** How many rows of each kind (BackgroundCheck, Reminder, Incident, Turn) have one of the refs. */
export async function rowCount(table: 'BackgroundCheck' | 'Reminder' | 'Incident' | 'Turn', refs: string[]): Promise<number> {
  if (refs.length === 0 || refs.some((ref) => !/^[A-Za-z0-9_-]+$/.test(ref))) throw new Error('rowCount takes plain refs');
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.${table} WHERE Ref IN (${refs.map(() => '?').join(',')})",${refs.map((ref) => quoted(ref)).join(',')})`,
      'Do rs.%Next()',
      'Write !,"CHK|count|",rs.%GetData(1)',
    ].join('\n'),
  );
  const raw = chk(lines, 'count');
  const count = raw === undefined || raw === '' ? Number.NaN : Number(raw);
  if (!Number.isInteger(count)) throw new Error(`the ${table} rows could not be counted (${lines.join(' ')})`);
  return count;
}

/**
 * Sets when the user's current run epoch started (GuideState.RunStartedAt) to the UTC time, and returns the time it had, so that a case
 * can put it back with the same call. A session with no GuideState row is in its first epoch, which counts every run, so nothing is
 * written and the answer is undefined.
 */
export async function startEpochAt(user: string, at: string): Promise<string | undefined> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set r=##class(OcuTalon.Data.GuideState).ForSession(s.Ref)',
      'If \'$IsObject(r) { Write !,"CHK|epoch|none" Halt }',
      'Write !,"CHK|was|",r.RunStartedAt',
      `Set r.RunStartedAt=${quoted(at)}`,
      'Write !,"CHK|epoch|",$System.Status.IsOK(r.%Save())',
    ].join('\n'),
  );
  const result = chk(lines, 'epoch');
  if (result === 'none') return undefined;
  if (result !== '1') throw new Error(`the run epoch's start could not be set (${lines.join(' ')})`);
  return chk(lines, 'was') ?? '';
}

/** Sets the state and open variant of an incident row, as the incident manager would (Lane A's table, written here for a fixture row). */
export async function setIncident(ref: string, fields: { state: string; openVariant: string }): Promise<void> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Data.Incident).RefIndexOpen(${quoted(ref)})`,
      `If '$IsObject(r) { Write !,"CHK|incident|0" Halt }`,
      `Set r.State=${quoted(fields.state)}`,
      `Set r.OpenVariant=${quoted(fields.openVariant)}`,
      'Write !,"CHK|incident|",$System.Status.IsOK(r.%Save())',
    ].join('\n'),
  );
  if (chk(lines, 'incident') !== '1') throw new Error(`the incident could not be changed (${lines.join(' ')})`);
}

/** Deletes the Usage rows of the decisions (they have no Ref of their own, so cleanFixtureRows keeps them). */
export async function dropUsage(decisionRefs: string[]): Promise<void> {
  const refs = decisionRefs.filter((ref) => /^[A-Za-z0-9_-]+$/.test(ref));
  if (refs.length === 0) return;
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef IN (${refs.map(() => '?').join(',')})",${refs.map((ref) => quoted(ref)).join(',')})`,
      'Write !,"CHK|usage|",(rs.%SQLCODE>=0)',
    ].join('\n'),
  );
  if (chk(lines, 'usage') !== '1') throw new Error(`the Usage rows could not be removed (${lines.join(' ')})`);
}
