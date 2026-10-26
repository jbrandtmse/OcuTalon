import { chk, irisScript, quoted } from './iris';

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
export async function publishWatchProgress(user: string, fields: { ref: string; stage: 'noticed' | 'settling' | 'diagnosing' }): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set p=##class(OcuTalon.Live.Payload.WatchProgress).%New()',
      `Set p.Ref=${quoted(fields.ref)}`,
      `Set p.Stage=${quoted(fields.stage)}`,
      'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"watch.progress",p,.q)',
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the watch.progress event could not be published (${lines.join(' ')})`);
  return seq;
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
