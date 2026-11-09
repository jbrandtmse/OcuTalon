import { chk, irisScript } from './iris';

/**
 * The shared steps of the specs that point the runners at the CI mock (HC4 of heartbeat-card.spec.ts, MC9 of memory-card.spec.ts): after
 * `pointKeys` the ready check of the runners, and after `restoreKeys` the wait for the runners' records and for the status monitor's
 * noModelKey event, so that the event lands before the next case or file and not in it.
 */

/** The last Seq of the instance stream, where the status monitor publishes its conditions. */
export async function instanceSeq(): Promise<number> {
  const seq = Number(chk(await irisScript('Write !,"CHK|seq|",##class(OcuTalon.Live.Publish).LastSeq("instance")'), 'seq'));
  if (!Number.isInteger(seq) || seq < 0) throw new Error('the last Seq of the instance stream could not be read');
  return seq;
}

/** Waits up to 30 seconds (two runs of the status monitor) for its noModelKey event after the mark; none comes when the reading did not change. */
export async function monitorSettled(mark: number): Promise<void> {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const lines = await irisScript(
      [
        `Set r=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM OcuTalon_Live.Event WHERE Stream = 'instance' AND Seq > ? AND Type = 'status' AND Payload [ 'noModelKey'",${mark})`,
        'Do r.%Next()',
        'Write !,"CHK|events|",+r.%Get("n")',
      ].join('\n'),
    );
    if (Number(chk(lines, 'events')) > 0) return;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
}

/** The ready check of the runners after pointKeys: the production's reason (empty when ready) and whether the TriageAgent has its key. */
export async function runnersReady(): Promise<{ reason: string; keyed: string }> {
  const lines = await irisScript(
    [
      'Set reason=##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()',
      'Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))',
      'Write !,"CHK|ready|",reason',
      'Write !,"CHK|keyed|",##class(OcuTalon.Bridge.Keys).Status(##class(OcuTalon.Checks.Beat).#AGENT)',
    ].join('\n'),
  );
  return { reason: chk(lines, 'ready') ?? 'unread', keyed: chk(lines, 'keyed') ?? 'unread' };
}

/** Waits for the runners to record the restored keys (RunnerFixture.WaitRecords) and answers whether they did. */
export async function runnersRecorded(): Promise<string> {
  const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
  return `${chk(lines, 'records') ?? 'unread'}`;
}
