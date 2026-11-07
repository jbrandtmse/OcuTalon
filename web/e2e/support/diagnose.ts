import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

import { test } from '@playwright/test';

import { asCleanup, boundedStep } from './bounds';
import { irisScript } from './iris';

/**
 * What a unit prints when the snapshot GET after a sign-in has passed its bound (DW-550, Story 11.22, Story 11.27): two reads of the stack's
 * IRIS, as `DIAG /state ...` lines on stdout, so that the next occurrence shows whether the GET waited on a held CSP session, a licence unit
 * or the web gateway. The gateway lines hold counts and states only, with no PID, IP address, port or server name.
 * - `DIAG /state licence:` the licence units: LUAvailable, LUConsumed, KeyEnforcedUnits, CSPUsers and InstanceConnections.
 * - `DIAG /state csp process:` each CSP server process (at most 30), idle or busy, with its pid, state and routine. A request that waits
 *   for a session lock shows as a process whose state is not READ.
 * - `DIAG /state <csp|lock> unavailable:` a query that could not be opened, run or read; an unread lock is never reported as none held.
 * - `DIAG /state session lock:` each ^%cspSession lock (at most 30) with the pid that holds it, its mode and count; the session id is cut to
 *   its first four characters. IRIS serialises the requests of one CSP session on that lock (wait up to 240 s). The processes that wait on a
 *   lock are not listed by %SYS.LockQuery:List, so the waiters are read from the CSP process lines, not from here.
 * - `DIAG /state gateway <g> server <s>:` per web gateway (at most 5, numbered in order) and per server it reaches (at most 30, numbered): the
 *   total, in-use and private connections and the queued requests. A request that the gateway holds in its queue shows as QueuedRequests.
 * - `DIAG /state gateway <g> connections:` the gateway's connections counted by state (Free, InUse, ...), in name order.
 * - `DIAG /state gateway: none registered`, or `DIAG /state gateway unavailable:` a read that was refused, failed, hung, or gave a value
 *   that is not a count or a state (the value is never printed).
 * The licence read and the gateway read are two irisScripts that run at once, each under asCleanup with an own bound of DIAG_BOUND_MS, so a
 * hung gateway call costs none of the first read's lines and the pair never takes longer than DIAG_BOUND_MS. The printed order is the first
 * read's lines, then the gateway lines. Both are best effort: a failure is printed as one `DIAG /state unavailable: <reason>` or
 * `DIAG /state gateway unavailable: <reason>` line and swallowed, and nothing here is part of an error text. Every line printed is also
 * appended to state-diagnosis.txt in the running test's output folder and that file is attached as `state-diagnosis`, so that it is in the
 * failure artifact when the unit's own output tail is too short to show it (DW-756); outside a test no file is written. Hermetic specs run
 * it against the OCUTALON_E2E_IRIS_EXEC stand-in.
 * Redaction: every DIAG line passes through redactLine once, before it is printed and appended, so the file equals the printed lines and no
 * line holds a cookie (a CSPSESSIONID, CSPCHD or CSPWSERVERID `name=value` or `name: value` pair, or a Cookie or Set-Cookie header), a bearer token, a request body (JSON
 * object text, also with escaped quotes), a key shape (sk-, ghp_ and its kin, github_pat_, AKIA, xox, AIza), a long opaque token (24 or more characters of letters,
 * digits, `_` and `-` with a digit among them) or more than the first four characters of a session id. A redacted value becomes
 * `[redacted]`, a Cookie header or a body through the end of its line; the counts and states of the other values are kept.
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

/** The characters that the gateway script keeps in a connection state (everything else is stripped); describeGateway's STATE_NAME also needs a leading letter. */
const STATE_CHARS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ()-';
const MAX_GATEWAYS = 5;

/**
 * The gateway script: read-only, in one Try/Catch. It prints CHK|gw|<n> (the active gateway managers; at most MAX_GATEWAYS are read), then
 * per manager g and per server s (at most MAX_LINES) CHK|gwserver|g|s|<total>|<in use>|<private>|<queued> (each as a number, so that no text
 * can come through), and per manager CHK|gwconn|g|<state>|<count>. A status that could not be read, or any error, prints
 * CHK|error|gateway|<text> (at most 200 characters), and the script ends with CHK|done|1. g and s are ordinals, never a name or an address.
 */
export function gatewayScript(): string {
  const text = (expression: string): string => `$Extract($Translate(${expression},$Char(10,13,124),"  /"),1,200)`;
  const read = [
    'Set mgrs=$SYSTEM.CSP.GetGatewayRegistry().GetGatewayMgrs("a"),gw=mgrs.Count()',
    'Write !,"CHK|gw|",gw',
    `For g=1:1:$Select(gw>${MAX_GATEWAYS}:${MAX_GATEWAYS},1:gw) {`,
    ' Kill ss,st Set sc=mgrs.GetAt(g).GetSystemStatus(.ss,"object")',
    ` If $SYSTEM.Status.IsError(sc) { Write !,"CHK|error|gateway|",${text('$SYSTEM.Status.GetErrorText(sc)')} } Else {`,
    '  Set k="",n=0',
    `  For { Set cs=ss.CacheServers.GetNext(.k) Quit:k=""  Quit:$Increment(n)>${MAX_LINES}  Write !,"CHK|gwserver|",g,"|",n,"|",+cs.TotalConnections,"|",+cs.ConnectionsInUse,"|",+cs.PrivateConnections,"|",+cs.QueuedRequests }`,
    '  Set k=""',
    `  For { Set c=ss.Connections.GetNext(.k) Quit:k=""  Set v=c.Status,v=$Extract($Translate(v,$Translate(v,"${STATE_CHARS}"),""),1,30) Set:v="" v="Unknown" Set st(v)=$Get(st(v))+1 }`,
    '  Set v=""',
    '  For { Set v=$Order(st(v)) Quit:v=""  Write !,"CHK|gwconn|",g,"|",v,"|",st(v) }',
    ' }',
    '}',
  ].join(' ');
  return [`Try { ${read} } Catch e { Write !,"CHK|error|gateway|",${text('e.DisplayString()')} }`, 'Write !,"CHK|done|1"'].join('\n');
}

const GATEWAY_SCRIPT = gatewayScript();

const COUNT = /^\d{1,9}$/;
const STATE_NAME = /^[A-Za-z][A-Za-z0-9 ()-]{0,29}$/;

/** The `DIAG /state gateway` lines for the CHK lines that the gateway script printed; a value that is not a count or a state is never echoed. */
export function describeGateway(lines: string[]): string[] {
  const unexpected = ['DIAG /state gateway unavailable: an unexpected reading'];
  const error = lines.find((line) => line.startsWith('CHK|error|'));
  if (error !== undefined) {
    const [, , ...fields] = error.split('|');
    return [`DIAG /state gateway unavailable: ${fields.slice(1).join(', ').slice(0, 200)}`];
  }
  const registered = lines.find((line) => line.startsWith('CHK|gw|'));
  if (registered === undefined) return ['DIAG /state gateway unavailable: the session printed no reading'];
  const count = registered.split('|')[2] ?? '';
  if (!COUNT.test(count)) return unexpected;
  if (Number(count) === 0) return ['DIAG /state gateway: none registered'];
  const out: Array<string | { connections: string }> = [];
  const connections = new Map<string, string[]>();
  for (const line of lines) {
    const [kind, ...fields] = line.split('|').slice(1);
    if (kind === 'gwserver') {
      if (fields.length !== 6 || !fields.every((field) => COUNT.test(field))) return unexpected;
      const [g, s, total, inUse, held, queued] = fields;
      out.push(`DIAG /state gateway ${g} server ${s}: TotalConnections=${total}, ConnectionsInUse=${inUse}, PrivateConnections=${held}, QueuedRequests=${queued}`);
    } else if (kind === 'gwconn') {
      const [g = '', state = '', n = ''] = fields;
      if (fields.length !== 3 || !COUNT.test(g) || !STATE_NAME.test(state) || !COUNT.test(n)) return unexpected;
      const states = connections.get(g);
      if (states === undefined) {
        connections.set(g, [`${state}=${n}`]);
        out.push({ connections: g });
      } else states.push(`${state}=${n}`);
    }
  }
  const described = out.map((line) => (typeof line === 'string' ? line : `DIAG /state gateway ${line.connections} connections: ${(connections.get(line.connections) ?? []).join(', ')}`));
  return described.length > 0 ? described : [`DIAG /state gateway: ${count} registered, no server or connection reported`];
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

/** Runs one read and describes it: the described lines, or the one unavailable line that names why it failed. It never throws. */
async function read(script: string, describe: (lines: string[]) => string[], unavailable: string): Promise<string[]> {
  try {
    const described = describe(await asCleanup(() => boundedStep(irisScript(script, DIAG_BOUND_MS), DIAG_BOUND_MS, 'stateDiagnosis')));
    if (described.length === 0) throw new Error('the session printed no reading');
    return described;
  } catch (error) {
    return [`${unavailable}: ${(error instanceof Error ? error.message : String(error)).split('\n')[0]}`];
  }
}

/** Appends the printed lines to state-diagnosis.txt in the running test's output folder and attaches the file once. Outside a test, or on a write failure, it does nothing. */
function keepLines(lines: string[]): void {
  try {
    const info = test.info();
    const file = info.outputPath('state-diagnosis.txt');
    mkdirSync(dirname(file), { recursive: true });
    appendFileSync(file, `${lines.join('\n')}\n`);
    if (!info.attachments.some((attachment) => attachment.name === 'state-diagnosis')) {
      info.attachments.push({ name: 'state-diagnosis', path: file, contentType: 'text/plain' });
    }
  } catch {
    // Best effort: a test outside Playwright, or a folder that cannot be written, keeps only the printed lines.
  }
}

const REDACTED = '[redacted]';

/** The redactions in order: the session id is cut first, so that the rule for long tokens does not take its first four characters too. */
const REDACTIONS: ReadonlyArray<readonly [RegExp, string]> = [
  [/(on session .{0,4}).*(\.\.\.)$/, '$1$2'],
  [/\b(?:Set-)?Cookie:.*$/i, `Cookie: ${REDACTED}`],
  [/(?:CSPSESSIONID|CSPCHD|CSPWSERVERID)[^\s=:;,]*[=:]\s*[^\s;,]*/gi, `cookie=${REDACTED}`],
  [/\bBearer\s+[^\s,;]+/gi, `Bearer ${REDACTED}`],
  [/\[?\{\s*\\?".*$/, REDACTED],
  [/(?<![A-Za-z0-9])(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|(?:AKIA|ASIA)[0-9A-Z]{12,}|xox[abprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{20,})/g, REDACTED],
  [/(?<![A-Za-z0-9_-])(?=[A-Za-z_-]*\d)[A-Za-z0-9_-]{24,}/g, REDACTED],
];

/** One DIAG line with every secret-shaped value replaced (see the header). */
export function redactLine(line: string): string {
  return REDACTIONS.reduce((text, [pattern, replacement]) => text.replace(pattern, replacement), line);
}

/** Prints the diagnosis of a /state that does not answer. It never throws and never takes longer than DIAG_BOUND_MS. */
export async function stateDiagnosis(): Promise<void> {
  const [first, gateway] = await Promise.all([
    read(SCRIPT, describeDiagnosis, 'DIAG /state unavailable'),
    read(GATEWAY_SCRIPT, describeGateway, 'DIAG /state gateway unavailable'),
  ]);
  const lines = [...first, ...gateway].map(redactLine);
  for (const line of lines) console.log(line);
  keepLines(lines);
}
