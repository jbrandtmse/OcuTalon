import { chk, cleanFixtureRows, irisScript, quoted } from './iris';
import { sessionRefOfUser } from './memory';

/**
 * Fixtures of the Usage specs (Story 37.2 api/usage.spec.ts and usage/usage.spec.ts): the Usage rows that a case seeds directly through
 * irisScript with the product's test fixture (Test.Data.Fixture.Usage), recorded at local noon of a day N days ago in the instance zone
 * (Data.Time.FromLocal), and the clean-up. Product code writes a usage row only in the runner; a fixture may save and delete rows itself.
 */

/** One Usage row a case seeds. cost null is a row with no price (a NULL cost). */
export interface UsageSeed {
  /** 0 is today; the row is recorded at local noon of that day. */
  daysAgo: number;
  agent: string;
  channel: string;
  model: string;
  estimated?: boolean;
  input: number;
  output: number;
  cacheRead?: number;
  cacheWrite?: number;
  cost: number | null;
  largest: number;
}

/** What seedUsage made: the decision Refs the rows are recorded under (for cleanUsage) and each row's local date, in the order of the rows. */
export interface SeededUsage {
  refs: string[];
  dates: string[];
}

/** Saves the rows for the owner (a session's Ref, or eval or instance) and answers their refs and local dates. */
export async function seedUsage(owner: string, rows: UsageSeed[]): Promise<SeededUsage> {
  const script = [
    'Set today=$Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()),"T",1)',
    ...rows.flatMap((row, index) => {
      const fields: Record<string, string | number> = {
        Agent: row.agent,
        Channel: row.channel,
        Model: row.model,
        Estimated: row.estimated ? 1 : 0,
        InputTokens: row.input,
        OutputTokens: row.output,
        CacheReadTokens: row.cacheRead ?? 0,
        CacheWriteTokens: row.cacheWrite ?? 0,
        LargestRequestTokens: row.largest,
        RequestCount: 1,
      };
      if (row.cost !== null) fields['CostUSD'] = row.cost;
      return [
        `Set date=$ZDate($ZDateH(today,3)-${row.daysAgo},3)`,
        `Set fields=##class(%DynamicObject).%FromJSON(${quoted(JSON.stringify(fields))})`,
        'Set fields.RecordedAt=##class(OcuTalon.Data.Time).FromLocal(date_"T12:00:00")',
        'Set ref=##class(OcuTalon.Bridge.Ids).NewRef()',
        `Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref,${quoted(owner)},fields)`,
        `Write !,"CHK|row${index}|",ref,"|",date`,
      ];
    }),
  ].join('\n');
  const lines = await irisScript(script);
  const refs: string[] = [];
  const dates: string[] = [];
  for (let index = 0; index < rows.length; index += 1) {
    const [ref, date] = (chk(lines, `row${index}`) ?? '').split('|');
    if (!ref || !date) throw new Error(`a usage row could not be seeded (${lines.join(' ')})`);
    refs.push(ref);
    dates.push(date);
  }
  return { refs, dates };
}

/** Deletes the rows seeded under these decision Refs (Test.Data.Fixture.Clean with the Refs), and no row that another test made. */
export async function cleanUsage(refs: string[]): Promise<void> {
  await cleanFixtureRows(refs);
}

/**
 * Deletes every Usage row of the user's durable session (the heartbeat card spec's direct-SQL precedent): the spec that calls it relies on
 * workers 1 and fullyParallel off (playwright.config.ts), and runs only on the e2e stack, never on a dev slot.
 */
export async function clearUsage(user: string): Promise<void> {
  const session = await sessionRefOfUser(user);
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ?",${quoted(session)})`,
      'Write !,"CHK|usage|",(rs.%SQLCODE>=0)',
    ].join('\n'),
  );
  if (chk(lines, 'usage') !== '1') throw new Error(`the Usage rows of ${user} could not be removed (${lines.join(' ')})`);
}
