import { asCleanup, boundedStep } from './bounds';
import { irisScript } from './iris';

/**
 * What a unit prints when the snapshot GET after a sign-in has passed its bound (DW-550, Story 11.22): one read of the stack's IRIS, as
 * `DIAG /state ...` lines on stdout, so that the next occurrence shows whether the GET waited on a held CSP session or a licence unit.
 * - `DIAG /state licence:` the licence units: LUAvailable, LUConsumed, KeyEnforcedUnits, CSPUsers and InstanceConnections.
 * - `DIAG /state csp process:` each CSP server process (at most 30), idle or busy, with its pid, state and routine. A request that waits
 *   for a session lock shows as a process whose state is not READ.
 * - `DIAG /state <csp|lock> unavailable:` a query that could not be opened, run or read; an unread lock is never reported as none held.
 * - `DIAG /state session lock:` each ^%cspSession lock (at most 30) with the pid that holds it, its mode and count; the session id is cut to
 *   its first four characters. IRIS serialises the requests of one CSP session on that lock (wait up to 240 s). The processes that wait on a
 *   lock are not listed by %SYS.LockQuery:List, so the waiters are read from the CSP process lines, not from here.
 * The read is one irisScript under asCleanup with an own bound of DIAG_BOUND_MS. It is best effort: a failure is printed as one
 * `DIAG /state unavailable: <reason>` line and swallowed, and nothing here is part of an error text. Hermetic specs run it against the
 * OCUTALON_E2E_IRIS_EXEC stand-in.
 */

/** The longest the read may take, in ms (the test's own deadline may shorten it, bounds.ts capToDeadline). */
export const DIAG_BOUND_MS = 15_000;

const MAX_LINES = 30;

/** The queries that the script reads: the CSP processes and the locks. */
export interface DiagnosisQueries {
  csp: string;
  lock: string;
}

const QUERIES: DiagnosisQueries = { csp: '%SYS.ProcessQuery:CONTROLPANEL', lock: '%SYS.LockQuery:List' };

/** Opens and runs the query into rs and sc: a query that cannot be opened is an error status like one that cannot run. */
function openQuery(query: string, argument: string): string {
  return `Set n=0,rs=##class(%ResultSet).%New("${query}"),sc=$Select($IsObject(rs):rs.Execute(${argument}),1:$SYSTEM.Status.Error(5001,"${query} could not be opened"))`;
}

/** Prints CHK|error|<kind>|<text> when the query could not be opened, run or read to its end. */
function queryError(kind: string): string {
  return `If $SYSTEM.Status.IsError(sc) { Write !,"CHK|error|${kind}|",$Translate($SYSTEM.Status.GetErrorText(sc),$Char(10,13,124),"  /") }`;
}

/**
 * The script: read-only, prints CHK|licence, CHK|csp and CHK|lock lines, and CHK|error|<csp|lock>| for a query that could not be read. A CSP
 * process is one whose routine or executable names CSP in any case: an idle one runs %SYS.cspServer, a busy one runs class code under the
 * CSP gateway's executable. The queries are a parameter for the spec that shows a failed read is reported.
 */
export function diagnosisScript(queries: DiagnosisQueries = QUERIES): string {
  return [
    'Write !,"CHK|licence|LUAvailable=",$SYSTEM.License.LUAvailable(),"|LUConsumed=",$SYSTEM.License.LUConsumed(),"|KeyEnforcedUnits=",$SYSTEM.License.KeyEnforcedUnits(),"|CSPUsers=",$SYSTEM.License.CSPUsers(),"|InstanceConnections=",$SYSTEM.License.InstanceConnections()',
    openQuery(queries.csp, ''),
    `If $SYSTEM.Status.IsOK(sc) { While rs.Next(.sc) { If ($ZConvert(rs.Get("Routine")_" "_rs.Get("EXE Name"),"L")["csp") && ($Increment(n)<=${MAX_LINES}) { Write !,"CHK|csp|",rs.Get("Pid"),"|",rs.Get("State"),"|",rs.Get("Routine") } } }`,
    queryError('csp'),
    openQuery(queries.lock, '"*"'),
    `If $SYSTEM.Status.IsOK(sc) { While rs.Next(.sc) { Set ref=rs.Get("LockString") If (ref["cspSession") && ($Increment(n)<=${MAX_LINES}) { Write !,"CHK|lock|",rs.Get("Owner"),"|",rs.Get("Mode"),"|",rs.Get("Counts"),"|",$Extract($Piece(ref,"""",2),1,4) } } }`,
    queryError('lock'),
    'Write !,"CHK|done|1"',
  ].join('\n');
}

const SCRIPT = diagnosisScript();

/** The `DIAG /state` lines for the CHK lines that SCRIPT printed. */
export function describeDiagnosis(lines: string[]): string[] {
  const out: string[] = [];
  let locks = 0;
  let lockUnread = false;
  for (const line of lines) {
    const [kind, ...fields] = line.split('|').slice(1);
    if (kind === 'licence') out.push(`DIAG /state licence: ${fields.join(', ')}`);
    else if (kind === 'csp') out.push(`DIAG /state csp process: pid=${fields[0] ?? ''} state=${fields[1] ?? ''} routine=${fields[2] ?? ''}`);
    else if (kind === 'error') {
      if (fields[0] === 'lock') lockUnread = true;
      out.push(`DIAG /state ${fields[0] ?? 'read'} unavailable: ${fields.slice(1).join(', ')}`);
    } else if (kind === 'lock') {
      locks += 1;
      out.push(`DIAG /state session lock: held by pid ${fields[0] ?? ''} (mode ${fields[1] || '?'}, count ${fields[2] || '?'}) on session ${fields[3] ?? ''}...`);
    }
  }
  if (lines.some((line) => line.startsWith('CHK|done|')) && locks === 0 && !lockUnread) out.push('DIAG /state session lock: none held');
  return out;
}

/** Prints the diagnosis of a /state that does not answer. It never throws and never takes longer than DIAG_BOUND_MS. */
export async function stateDiagnosis(): Promise<void> {
  try {
    const lines = await asCleanup(() => boundedStep(irisScript(SCRIPT, DIAG_BOUND_MS), DIAG_BOUND_MS, 'stateDiagnosis'));
    const described = describeDiagnosis(lines);
    if (described.length === 0) throw new Error('the session printed no reading');
    for (const line of described) console.log(line);
  } catch (error) {
    const reason = (error instanceof Error ? error.message : String(error)).split('\n')[0];
    console.log(`DIAG /state unavailable: ${reason}`);
  }
}
