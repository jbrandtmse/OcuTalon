import { chk, irisScript, quoted } from './iris';

/**
 * Fixtures of the History specs (Story 25.2 api/history.spec.ts and history/history.spec.ts): the decide Decision rows (and their Usage rows, which give a
 * decision its channel) that a case seeds directly through irisScript with the product's test fixture (Test.Data.Fixture.Decision and Usage); support/iris.ts cleanFixtureRows removes them by their Refs.
 * Product code writes a decision only in the bridge; a fixture may save and delete rows itself. A case reads its own rows by a day that no other case uses.
 */

/** Whose decisions: a session by its Ref, an IRIS user's durable session, or the owner eval or instance. */
export type HistoryOwner = { sessionRef: string } | { user: string } | 'eval' | 'instance';

/** One decision a case seeds. */
export interface HistoryDecisionSeed {
  outcome: string;
  summary: string;
  reasons?: string;
  fallback?: boolean;
  fallbackReason?: string;
  confidence?: number;
  costUSD?: number;
  /** The channel of a usage row of the decision; none leaves the decision without one (no model call served it). */
  channel?: string;
  /** The local day N days ago and the local time "HH:MM:SS" the decision is recorded at (noon by default). */
  daysAgo?: number;
  time?: string;
  /** Instead of a day and time: this many minutes before now. */
  minutesAgo?: number;
  /** The Visual Trace session that the decision's trace link opens. */
  traceSessionId?: number;
}

/** What seedHistoryDecisions made for a row: the Ref (for cleanFixtureRows, which removes its usage rows with it) and the local date it was recorded on. */
export interface SeededDecision {
  ref: string;
  date: string;
}

/** The local date YYYY-MM-DD of the instance, N days ago (in the instance zone, as the product counts a day). */
export async function localDate(daysAgo: number): Promise<string> {
  const lines = await irisScript(
    [
      'Set today=$Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()),"T",1)',
      `Write !,"CHK|date|",$ZDate($ZDateH(today,3)-${Math.trunc(daysAgo)},3)`,
    ].join('\n'),
  );
  const date = chk(lines, 'date');
  if (!date) throw new Error(`the local date could not be read (${lines.join(' ')})`);
  return date;
}

/** Saves the decisions for the owner, in one script, and answers their Refs and local dates in the order of the rows. */
export async function seedHistoryDecisions(owner: HistoryOwner, rows: HistoryDecisionSeed[]): Promise<SeededDecision[]> {
  const head =
    typeof owner === 'string'
      ? [`Set o=${quoted(owner)}`]
      : 'sessionRef' in owner
        ? [`Set o=${quoted(owner.sessionRef)}`]
        : [`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(owner.user)},.sc)`, 'Set o=s.Ref'];
  const script = [
    'Set today=$Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()),"T",1)',
    ...head,
    ...rows.flatMap((row, index) => {
      const fields: Record<string, string | number> = {
        Outcome: row.outcome,
        Summary: row.summary,
        Fallback: row.fallback ? 1 : 0,
        TraceSessionId: row.traceSessionId ?? 42,
      };
      if (row.reasons !== undefined) fields['Reasons'] = row.reasons;
      if (row.fallbackReason !== undefined) fields['FallbackReason'] = row.fallbackReason;
      if (row.confidence !== undefined) fields['Confidence'] = row.confidence;
      if (row.costUSD !== undefined) fields['CostUSD'] = row.costUSD;
      const at =
        row.minutesAgo !== undefined
          ? `##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(),${-60 * Math.trunc(row.minutesAgo)})`
          : `##class(OcuTalon.Data.Time).FromLocal($ZDate($ZDateH(today,3)-${Math.trunc(row.daysAgo ?? 0)},3)_"T"_${quoted(row.time ?? '12:00:00')})`;
      return [
        `Set at=${at}`,
        `Set fields=##class(%DynamicObject).%FromJSON(${quoted(JSON.stringify(fields))})`,
        'Set ref=##class(OcuTalon.Test.Data.Fixture).Decision(o,"decide",at,fields)',
        ...(row.channel === undefined ? [] : [`Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref,o,{"Channel":(${quoted(row.channel)}),"RecordedAt":(at)})`]),
        `Write !,"CHK|row${index}|",ref,"|",$Piece(##class(OcuTalon.Data.Time).ToLocal(at),"T",1)`,
      ];
    }),
  ].join('\n');
  const lines = await irisScript(script);
  return rows.map((_row, index) => {
    const [ref, date] = (chk(lines, `row${index}`) ?? '').split('|');
    if (!ref || !date) throw new Error(`a decision could not be seeded (${lines.join(' ')})`);
    return { ref, date };
  });
}
