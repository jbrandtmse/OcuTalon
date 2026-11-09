import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

import { test, type Page, type Request } from '@playwright/test';

import { STATE } from './api';
import { asCleanup, boundedStep, secs } from './bounds';
import { describeHost, readHost, swapInMark, type HostReading } from './host';
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
 * line holds a cookie (a CSPSESSIONID, CSPCHD or CSPWSERVERID `name=value` or `name: value` pair, or a header whose name ends in Cookie), a bearer token, a request body (JSON
 * object text, also with escaped quotes), a key shape (sk-, ghp_ and its kin, github_pat_, AKIA, ASIA, xox, AIza), a long opaque token (24 or more characters of letters,
 * digits, `_` and `-` with a digit among them) or more than the first four characters of a session id. A redacted value becomes
 * `[redacted]`, a Cookie header or a body through the end of its line; the counts and states of the other values are kept.
 *
 * Story 32.6 (DW-550, DW-774) adds what the page and the browser did, as lines that follow the IRIS lines:
 * - `DIAG /state request: none issued by the page since the sign-in began`, or up to five newest lines
 *   `DIAG /state request <i> of <n>: issued <s> s after the sign-in began, <no answer yet|answered <status> at <s> s|failed at <s> s (<class>)>`
 *   (the GETs of the snapshot that a watchRequests watch saw);
 * - `DIAG /state page: <n> request(s) in flight (<type>=<k>, ... in name order), the oldest issued <s> s ago`, or `no request in flight`;
 * - `DIAG /state page: the page answered in <ms> ms (readyState <complete|interactive|loading|other>)`, or `gave no answer within 2 s` or `is closed`
 *   (probePage, a document.readyState read that asks whether the renderer answers);
 * - `DIAG /state host: ...`, the worker host's load, pressure and swap-in rate (host.ts).
 * The request, page and host lines are also printed when the snapshot wait retries (floor.ts, at half of its bound, so a retried test that passes still
 * leaves state-diagnosis.txt), and `DIAG /state reload failed: <class>` says that the retry's reload was refused.
 * A page.close that passed its bound (fixtures.ts) prints, to close-diagnosis.txt and the `close-diagnosis` attachment, `DIAG page.close:` (the
 * page open or closed, the pages of its context, the browser connected or not), `DIAG page.close requests:` (the in-flight phrase),
 * `DIAG page.close renderer:` (the probe), `DIAG page.close browser:` (a Browser.getVersion over a browser CDP session, answered in <ms> ms,
 * `gave no answer within 2 s` or `not measured (not Chromium)`) and `DIAG page.close host:`. Every value that these lines print is checked: an
 * error class outside `^[A-Za-z][A-Za-z0-9_:.]{0,39}$` prints as `another error`, a resource type outside `^[a-z]{1,20}$` as `other`, and no
 * URL, query, body, header, cookie, session id, PID, address or host name is read into a line.
 * The same five lines (closeLines) are the retry-time diagnosis of a close that has not ended by half of its bound (fixtures.ts, one logged
 * re-close): they follow the `RETRY` line in the retries file and are not printed. closeTargetAgain then sends `Target.closeTarget` for the
 * page's own target through a browser CDP session; a refusal prints `DIAG page.close re-close failed: <class>` (the class checked as above).
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

/** Appends the printed lines to <name>.txt in the running test's output folder and attaches the file once as `name`. Outside a test, or on a write failure, it does nothing. */
function keepLines(lines: string[], name = 'state-diagnosis'): void {
  try {
    const info = test.info();
    const file = info.outputPath(`${name}.txt`);
    mkdirSync(dirname(file), { recursive: true });
    appendFileSync(file, `${lines.join('\n')}\n`);
    if (!info.attachments.some((attachment) => attachment.name === name)) {
      info.attachments.push({ name, path: file, contentType: 'text/plain' });
    }
  } catch {
    // Best effort: a test outside Playwright, or a folder that cannot be written, keeps only the printed lines.
  }
}

const REDACTED = '[redacted]';

/** The redactions in order: the session id is cut first, so that the rule for long tokens does not take its first four characters too. */
const REDACTIONS: ReadonlyArray<readonly [RegExp, string]> = [
  [/(on session .{0,4}).*(\.\.\.)$/s, '$1$2'],
  [/(?:Set-)?Cookie\s*:.*$/is, `Cookie: ${REDACTED}`],
  [/(?:CSPSESSIONID|CSPCHD|CSPWSERVERID)[^\s=:;,]*\s*[=:]\s*[^\s;,]*/gi, `cookie=${REDACTED}`],
  [/\bBearer\s+[^\s,;]+/gi, `Bearer ${REDACTED}`],
  [/\[?\{\s*\\?".*$/s, REDACTED],
  [/(?:(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|(?:AKIA|ASIA)[0-9A-Z]{12,}|xox[abprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{20,})/g, REDACTED],
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
  printDiagnosis([...first, ...gateway], 'state-diagnosis');
}

/** Redacts the lines (redactLine), prints them, and keeps them in <name>.txt of the test's output folder (keepLines). The file equals the printed lines. */
export function printDiagnosis(lines: string[], name: string): void {
  const redacted = lines.map(redactLine);
  for (const line of redacted) console.log(line);
  keepLines(redacted, name);
}

// --- What the page and the browser did (Story 32.6) ---

/** How long a probe of the page or the browser waits for an answer, in ms. */
export const PROBE_BOUND_MS = 2_000;

const MAX_RECORDS = 200;
const MAX_REQUEST_LINES = 5;
const ERROR_CLASS = /^[A-Za-z][A-Za-z0-9_:.]{0,39}$/;
const RESOURCE_TYPE = /^[a-z]{1,20}$/;
const READY_STATES = ['complete', 'interactive', 'loading'];

/** One request of a page: when it was issued (ms), its resource type, whether it is a GET of /state, and how it went. */
export interface RequestRecord {
  issuedAt: number;
  type: string;
  state: boolean;
  status?: number;
  answeredAt?: number;
  endedAt?: number;
  failedAt?: number;
  error?: string;
}

/** The requests that a page has issued since watchRequests began, and the host's swap-in at that time. */
export interface RequestWatch {
  records(): RequestRecord[];
  host(): HostReading;
  stop(): void;
}

/** The text as an error class if it has the shape of one, else `another error`: an odd value is never echoed. */
export function errorClass(text: unknown): string {
  return typeof text === 'string' && ERROR_CLASS.test(text) ? text : 'another error';
}

const typeName = (type: string): string => (RESOURCE_TYPE.test(type) ? type : 'other');

const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? '' : 's'}`;

const since = (at: number, began: number): string => secs(Math.max(0, at - began));

/**
 * Records every request of the page (its issue time, resource type, whether it is a GET of /state, and its status, end or failure) until
 * stop() or the page's close, at most 200 records (the finished ones are dropped first, then those that are not a GET of /state). It also reads the host's swap-in count, so that
 * host() gives the rate since the watch began. It never throws: a page with no events (a stand-in) gives a watch that records nothing.
 */
export function watchRequests(page: Page): RequestWatch {
  const list: RequestRecord[] = [];
  const by = new Map<Request, RequestRecord>();
  const mark = swapInMark();
  const onRequest = (request: Request): void => {
    try {
      const record: RequestRecord = {
        issuedAt: Date.now(),
        type: request.resourceType(),
        state: request.method() === 'GET' && new URL(request.url()).pathname === STATE,
      };
      list.push(record);
      by.set(request, record);
      if (list.length > MAX_RECORDS) {
        // The finished ones go first, then the other requests: the GETs of /state that are in flight are the last to go.
        const done = list.findIndex((item) => item.endedAt !== undefined || item.failedAt !== undefined);
        const other = done >= 0 ? done : list.findIndex((item) => !item.state);
        const [dropped] = list.splice(other >= 0 ? other : 0, 1);
        for (const [key, value] of by) if (value === dropped) by.delete(key);
      }
    } catch {
      // A request that cannot be read is left out.
    }
  };
  const onResponse = (response: { request(): Request; status(): number }): void => {
    const record = by.get(response.request());
    if (record !== undefined) {
      record.status = response.status();
      record.answeredAt = Date.now();
    }
  };
  const onFinished = (request: Request): void => {
    const record = by.get(request);
    if (record !== undefined) record.endedAt = Date.now();
  };
  const onFailed = (request: Request): void => {
    const record = by.get(request);
    if (record !== undefined) {
      record.failedAt = Date.now();
      record.error = request.failure()?.errorText;
    }
  };
  const stop = (): void => {
    try {
      page.off('request', onRequest);
      page.off('response', onResponse);
      page.off('requestfinished', onFinished);
      page.off('requestfailed', onFailed);
      page.off('close', stop);
    } catch {
      // A page with no events (a stand-in that only closes) holds none of these listeners.
    }
  };
  try {
    page.on('request', onRequest);
    page.on('response', onResponse);
    page.on('requestfinished', onFinished);
    page.on('requestfailed', onFailed);
    page.on('close', stop);
  } catch {
    // A page with no events records nothing.
    stop();
  }
  return { records: () => list.map((record) => ({ ...record })), host: () => readHost(mark), stop };
}

/** The `DIAG /state request` lines: up to the five newest GETs of /state in the records, or the line that says the page issued none. */
export function describeStateRequests(records: RequestRecord[], began: number, _now: number): string[] {
  const mine = records.filter((record) => record.state);
  if (mine.length === 0) return ['DIAG /state request: none issued by the page since the sign-in began'];
  const first = Math.max(0, mine.length - MAX_REQUEST_LINES);
  return mine.slice(first).map((record, k) => {
    const head = `DIAG /state request ${first + k + 1} of ${mine.length}: issued ${since(record.issuedAt, began)} s after the sign-in began`;
    if (record.failedAt !== undefined) return `${head}, failed at ${since(record.failedAt, began)} s (${errorClass(record.error)})`;
    if (record.status !== undefined && record.answeredAt !== undefined) {
      const status = Number.isInteger(record.status) && record.status >= 100 && record.status <= 599 ? String(record.status) : 'other';
      return `${head}, answered ${status} at ${since(record.answeredAt, began)} s`;
    }
    return `${head}, no answer yet`;
  });
}

/** The `<prefix>: <n> request(s) in flight (<type>=<k>, ... in name order), the oldest issued <s> s ago` line, or `no request in flight`. */
export function describeInFlight(prefix: string, records: RequestRecord[], now: number): string {
  const open = records.filter((record) => record.endedAt === undefined && record.failedAt === undefined);
  if (open.length === 0) return `${prefix}: no request in flight`;
  const counts = new Map<string, number>();
  for (const record of open) counts.set(typeName(record.type), (counts.get(typeName(record.type)) ?? 0) + 1);
  const types = [...counts.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([type, k]) => `${type}=${k}`);
  const oldest = Math.min(...open.map((record) => record.issuedAt));
  return `${prefix}: ${plural(open.length, 'request')} in flight (${types.join(', ')}), the oldest issued ${since(now, oldest)} s ago`;
}

/** What a probe of the page or the browser found. */
export type Probe =
  | { kind: 'answered'; ms: number; readyState?: string }
  | { kind: 'none' }
  | { kind: 'closed' }
  | { kind: 'failed'; error: string }
  | { kind: 'unmeasured' };

/** The line for a probe: `<prefix> answered in <ms> ms[ (readyState x)]`, `gave no answer within 2 s`, `is closed`, `failed (<class>)` or `not measured (not Chromium)`. */
export function describeProbe(prefix: string, probe: Probe): string {
  if (probe.kind === 'answered') {
    const ms = Number.isFinite(probe.ms) && probe.ms >= 0 ? Math.round(probe.ms) : 0;
    if (probe.readyState === undefined) return `${prefix} answered in ${ms} ms`;
    return `${prefix} answered in ${ms} ms (readyState ${READY_STATES.includes(probe.readyState) ? probe.readyState : 'other'})`;
  }
  if (probe.kind === 'none') return `${prefix} gave no answer within ${secs(PROBE_BOUND_MS)} s`;
  if (probe.kind === 'closed') return `${prefix} is closed`;
  if (probe.kind === 'unmeasured') return `${prefix} not measured (not Chromium)`;
  return `${prefix} failed (${errorClass(probe.error)})`;
}

/** Settles with the work's value, or with onTimeout after ms; the work's late outcome is dropped. */
function within<T>(work: Promise<T>, ms: number, onTimeout: T): Promise<T> {
  return new Promise<T>((resolve) => {
    const timer = setTimeout(() => resolve(onTimeout), ms);
    work.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      () => undefined,
    );
  });
}

/** Asks the page's renderer for document.readyState within ms. It never throws. */
export async function probePage(page: Page, ms: number): Promise<Probe> {
  try {
    if (page.isClosed()) return { kind: 'closed' };
    const began = Date.now();
    const asked = page.evaluate(() => document.readyState).then(
      (readyState): Probe => ({ kind: 'answered', ms: Date.now() - began, readyState: String(readyState) }),
      (error: unknown): Probe => (page.isClosed() ? { kind: 'closed' } : { kind: 'failed', error: errorClass(error instanceof Error ? error.name : undefined) }),
    );
    return await within<Probe>(asked, ms, { kind: 'none' });
  } catch {
    return { kind: 'failed', error: 'another error' };
  }
}

/** Asks the browser for Browser.getVersion over a browser CDP session within ms: only the elapsed time is kept. It never throws. */
async function probeBrowser(page: Page, ms: number): Promise<Probe> {
  try {
    const browser = page.context().browser();
    if (browser === null) return { kind: 'unmeasured' };
    const began = Date.now();
    const asked = (async (): Promise<Probe> => {
      let session;
      try {
        session = await browser.newBrowserCDPSession();
      } catch {
        return { kind: 'unmeasured' };
      }
      try {
        await session.send('Browser.getVersion');
        return { kind: 'answered', ms: Date.now() - began };
      } catch (error) {
        return { kind: 'failed', error: errorClass(error instanceof Error ? error.name : undefined) };
      } finally {
        session.detach().catch(() => undefined);
      }
    })();
    return await within<Probe>(asked, ms, { kind: 'none' });
  } catch {
    return { kind: 'unmeasured' };
  }
}

/** The page-side lines of a snapshot GET that has no answer: the request lines, the in-flight line, the page probe and the host line. */
export function pageSideLines(watch: RequestWatch, began: number, probe: Probe, now: number = Date.now()): string[] {
  const records = watch.records();
  return [
    ...describeStateRequests(records, began, now),
    describeInFlight('DIAG /state page', records, now),
    describeProbe('DIAG /state page: the page', probe),
    describeHost('DIAG /state host', watch.host()),
  ];
}

/** What closeTargetAgain did: the close was sent, the browser is not one that can be asked, or it failed with a checked error class. */
export type Reclose = { kind: 'sent' } | { kind: 'unmeasured' } | { kind: 'failed'; error: string };

/**
 * Asks the browser to close the page's target once more: the page's own CDP session gives its Target.getTargetInfo, and Target.closeTarget goes
 * through a browser CDP session (the page's session is not used for it, so that a page that does not answer cannot hold the request). Both sessions
 * that were opened are detached when the call ends, answered or not. It waits no longer than ms for the send to be answered and never throws; a
 * browser that is not Chromium is unmeasured.
 */
export async function closeTargetAgain(page: Page, ms: number = PROBE_BOUND_MS): Promise<Reclose> {
  const sessions: Array<{ detach: () => Promise<void> }> = [];
  try {
    const context = page.context();
    const browser = context.browser();
    if (browser === null || browser.browserType().name() !== 'chromium') return { kind: 'unmeasured' };
    const asked = (async (): Promise<Reclose> => {
      try {
        const own = await context.newCDPSession(page);
        sessions.push(own);
        const info = await own.send('Target.getTargetInfo');
        const session = await browser.newBrowserCDPSession();
        sessions.push(session);
        await session.send('Target.closeTarget', { targetId: info.targetInfo.targetId });
        return { kind: 'sent' };
      } catch (error) {
        return { kind: 'failed', error: errorClass(error instanceof Error ? error.name : undefined) };
      }
    })();
    return await within<Reclose>(asked, ms, { kind: 'failed', error: 'TimeoutError' });
  } catch {
    return { kind: 'failed', error: 'another error' };
  } finally {
    for (const session of sessions) session.detach().catch(() => undefined);
  }
}

/** The `DIAG page.close re-close ...` line for a re-close that was not sent, or undefined for one that was. */
export function describeReclose(result: Reclose): string | undefined {
  if (result.kind === 'sent') return undefined;
  if (result.kind === 'unmeasured') return 'DIAG page.close re-close not measured (not Chromium)';
  return `DIAG page.close re-close failed: ${errorClass(result.error)}`;
}

/**
 * The close diagnosis of a page (DW-774) as lines, unprinted: whether the page, its context and the browser are there, what is in flight, whether
 * the renderer and the browser answer, and the host. The probes run at once, so it takes PROBE_BOUND_MS at most. It throws only when the page does.
 */
export async function closeLines(page: Page, watch: RequestWatch): Promise<string[]> {
  const [renderer, browser] = await Promise.all([probePage(page, PROBE_BOUND_MS), probeBrowser(page, PROBE_BOUND_MS)]);
  const context = page.context();
  const pages = context.pages().length;
  const connected = context.browser()?.isConnected() === true;
  const records = watch.records();
  return [
    `DIAG page.close: the page is ${page.isClosed() ? 'closed' : 'open'}, ${plural(pages, 'page')} in its context, the browser is ${connected ? 'connected' : 'not connected'}`,
    describeInFlight('DIAG page.close requests', records, Date.now()),
    describeProbe('DIAG page.close renderer:', renderer),
    describeProbe('DIAG page.close browser:', browser),
    describeHost('DIAG page.close host', watch.host()),
  ];
}

/**
 * Prints the close diagnosis of a page whose close passed its bound (DW-774) to stdout and close-diagnosis.txt (closeLines). It runs as a clean-up
 * and never throws.
 */
export async function closeDiagnosis(page: Page, watch: RequestWatch): Promise<void> {
  try {
    await asCleanup(async () => {
      printDiagnosis(await closeLines(page, watch), 'close-diagnosis');
    });
  } catch {
    // A diagnosis never replaces the error that it describes.
  }
}
