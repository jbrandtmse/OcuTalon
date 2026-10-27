import { execFileSync, spawn } from 'node:child_process';

/**
 * What the e2e specs need from the throwaway stack that their script starts (docker/tests/test-sign-in.sh, test-floor.sh for the floor
 * specs of e2e/floor/, or test-demo-path.sh): the fixture users the sign-in and floor scripts created, and a way to run a line of
 * ObjectScript in the OCUTALON namespace of the stack's IRIS container (the stack publishes no management port). The container is named
 * by OCUTALON_E2E_IRIS_CONTAINER, which the sign-in and floor scripts set, or else found by the web port of OCUTALON_URL, which the
 * demo-path script sets (irisContainer). Every variable is read when a helper is called, never at import, so that listing the specs needs none.
 */
function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set by the e2e unit's script (docker/tests/test-sign-in.sh, test-floor.sh or test-demo-path.sh)`);
  return value;
}

/** The container found by the web port, kept for the run. */
let foundContainer: string | undefined;

/**
 * The IRIS container of the stack under test. Two ways name it, in this order:
 *   - OCUTALON_E2E_IRIS_CONTAINER, which the sign-in and floor scripts set;
 *   - the web port of OCUTALON_URL, which the demo-path script sets: the one container that publishes that host port (docker ps
 *     --filter publish matches the host port; only the iris service publishes it, through the override of lib-live.sh's live_web_port,
 *     and each runner and lane uses its own port). Exactly one container must publish it, else this fails naming the variable and the port.
 */
function irisContainer(): string {
  const named = process.env['OCUTALON_E2E_IRIS_CONTAINER'];
  if (named) return named;
  if (foundContainer) return foundContainer;
  const port = new URL(required('OCUTALON_URL')).port;
  if (!port) throw new Error('OCUTALON_E2E_IRIS_CONTAINER is not set and OCUTALON_URL names no port to find the IRIS container by');
  const ids = execFileSync('docker', ['ps', '--filter', `publish=${port}`, '--format', '{{.ID}}'], { encoding: 'utf8' })
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '');
  if (ids.length !== 1) {
    throw new Error(`OCUTALON_E2E_IRIS_CONTAINER is not set, and ${ids.length} containers publish port ${port} (OCUTALON_URL): exactly one is needed`);
  }
  foundContainer = ids[0];
  return foundContainer;
}

/** The kinds of fixture user of the sign-in unit, FLOOR, the floor unit's, and ANSWERS, the answers unit's. */
export type FixtureKind = 'LIVE' | 'SESSION' | 'SIGNIN' | 'CHAT' | 'PANEL' | 'DECISION' | 'NOTICE' | 'RAIL' | 'THREAD' | 'LINKS' | 'BANNERS' | 'FLOOR' | 'ANSWERS';

/** A fixture user of the sign-in or the floor unit: OCUTALON_<kind>_USER and OCUTALON_<kind>_PASSWORD. */
export function fixtureUser(kind: FixtureKind): { user: string; password: string } {
  return { user: required(`OCUTALON_${kind}_USER`), password: required(`OCUTALON_${kind}_PASSWORD`) };
}

/** Runs one script in a session of the container and returns whatever it printed. */
function runOnce(script: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', ['exec', '-i', irisContainer(), 'iris', 'session', 'IRIS', '-U', 'OCUTALON'], {
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    let out = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk: string) => (out += chunk));
    child.on('error', reject);
    child.on('close', () => resolve(out));
    child.stdin.end(`${script}\nHalt\n`);
  });
}

/**
 * Runs a script of ObjectScript lines in the OCUTALON namespace of the IRIS container, as docker/tests/lib-live.sh's
 * iris_script does, and returns the lines that start with `CHK|` (the script prints them with Write !,"CHK|...").
 * A session that prints no such line is tried again, at most three tries 5 s apart.
 */
export async function irisScript(script: string): Promise<string[]> {
  let lines: string[] = [];
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const out = await runOnce(script);
    lines = out
      .replace(/\r/g, '')
      .split('\n')
      .flatMap((line) => {
        const at = line.indexOf('CHK|');
        return at >= 0 ? [line.slice(at)] : [];
      });
    if (lines.length > 0 || attempt === 3) break;
    await new Promise((done) => setTimeout(done, 5000));
  }
  return lines;
}

/** The value of the line `CHK|<name>|<value>` among a script's lines, or undefined. */
export function chk(lines: string[], name: string): string | undefined {
  const prefix = `CHK|${name}|`;
  return lines.find((line) => line.startsWith(prefix))?.slice(prefix.length);
}

/** An IRIS user name as a literal of a script: letters, digits and underscore only. */
function literal(user: string): string {
  if (!/^[A-Za-z0-9_]+$/.test(user)) throw new Error('a fixture user name is letters, digits and underscore');
  return `"${user}"`;
}

/**
 * What publishReminder may set on the reminder it publishes; the ref is new unless given. traceHeaderId and traceNamespace are the
 * reminder's trace target (the waiter's header once Story 8.3 stores it), which only a published payload carries: a reminder row has none.
 */
export interface ReminderFields {
  ref?: string;
  text?: string;
  dueAt?: string;
  state?: string;
  traceHeaderId?: number;
  traceNamespace?: string;
}

/**
 * Publishes one fixture reminder on the user's own session stream and returns its Seq: the text "e2e live reminder", the state
 * pending and no due time, unless fields say otherwise. The ref is a new one unless fields name it (a later event with the same ref
 * updates the row).
 */
export async function publishReminder(user: string, fields: ReminderFields = {}): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      'Set p=##class(OcuTalon.Live.Payload.Reminder).%New()',
      fields.ref === undefined ? 'Set p.Ref=##class(OcuTalon.Bridge.Ids).NewRef()' : `Set p.Ref=${quoted(fields.ref)}`,
      `Set p.Text=${quoted(fields.text ?? 'e2e live reminder')}`,
      `Set p.State=${quoted(fields.state ?? 'pending')}`,
      ...(fields.dueAt === undefined ? [] : [`Set p.DueAt=${quoted(fields.dueAt)}`]),
      ...(fields.traceHeaderId === undefined ? [] : [`Set p.TraceHeaderId=${numeric(fields.traceHeaderId, 'traceHeaderId')}`]),
      ...(fields.traceNamespace === undefined ? [] : [`Set p.TraceNamespace=${quoted(fields.traceNamespace)}`]),
      'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"reminder",p,.q)',
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the reminder could not be published (${lines.join(' ')})`);
  return seq;
}

/**
 * Publishes one fixture incident on the user's own session stream and returns its Seq: the payload (a camelCase object of
 * OcuTalon.Live.Payload.Incident, parts included: itemNoun, groups, requests, evidence, traceTargets) is imported into the payload
 * class and published as the `incident` event, as IncidentManager will (Live.Publish.Publish). A later event with the same ref
 * replaces the card. Fixture rows with the ref's incident are not written: the event is the whole of it. A payload the class cannot
 * import throws with the import's error text.
 */
export async function publishIncident(user: string, payload: Record<string, unknown>): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      'Set p=##class(OcuTalon.Live.Payload.Incident).%New()',
      `Set sc=p.%JSONImport(${quoted(JSON.stringify(payload))})`,
      'If $System.Status.IsError(sc) { Write !,"CHK|error|",$TRANSLATE($System.Status.GetErrorText(sc),$Char(13,10),"  "),!,"CHK|seq|0" Halt }',
      'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"incident",p,.q)',
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the incident could not be published (${lines.join(' ')})`);
  return seq;
}

/**
 * A string as an ObjectScript expression: runs of printable ASCII are quoted, with each double quote doubled, and every other
 * character (control characters and non-ASCII) is written with $Char(n) by UTF-16 code unit, so that a character above U+FFFF
 * reaches IRIS as its surrogate pair (IRIS's $Char of such a code point is empty) and no value reaches the script as anything
 * but those two forms. The empty string is "".
 */
export function quoted(value: string): string {
  const parts: string[] = [];
  let ascii = '';
  let codes: number[] = [];
  const flush = (): void => {
    if (ascii !== '') parts.push(`"${ascii}"`);
    if (codes.length > 0) parts.push(`$Char(${codes.join(',')})`);
    ascii = '';
    codes = [];
  };
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code >= 0x20 && code <= 0x7e) {
      if (codes.length > 0) flush();
      ascii += code === 0x22 ? '""' : value.charAt(i);
    } else {
      if (ascii !== '') flush();
      codes.push(code);
    }
  }
  flush();
  return parts.length > 0 ? parts.join('_') : '""';
}

/**
 * The fields of a Decision row that seedTurns writes (Bridge.Data.Decision, AD-20); every field is optional and a field left out
 * stays empty, except the model, which is claude-haiku-5-5.
 */
export interface SeedDecision {
  outcome?: string;
  summary?: string;
  reasons?: string;
  confidence?: number;
  fallback?: boolean;
  fallbackReason?: string;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  agentStepCount?: number;
  durationMs?: number;
  costUSD?: number;
  model?: string;
  traceSessionId?: number;
  /** The Item the decision was made for: a new Ref unless given. Only seedDecisions reads it; a turn of seedTurns has its own ItemId. */
  itemId?: string;
  /** When it was recorded (UTC, to the second); the default is now for seedDecision, and the turn's createdAt for a turn of seedTurns. */
  recordedAt?: string;
}

/** One Usage row of a seeded turn (Bridge.Data.Usage): it belongs to the turn's triage decision or its reply decision. */
export interface SeedUsage {
  of: 'triage' | 'turn';
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  costUSD?: number;
  estimated?: boolean;
}

/** One check result of a seeded reply, as Checks.Render's rows give it (Turn.CheckRows). */
export interface SeedCheck {
  result: string;
  entry: string;
  finding?: string;
  checkedAt?: string;
}

/**
 * A turn for seedTurns: when it was created (UTC, to the second), its text and reply, and where it came from. A fallback
 * reply carries the catalog key the server answered with and its reason (Turn.ReplyCatalogKey and Turn.FallbackReason); both
 * are empty for a reply of the model's own words. state is done unless it is running (a running turn has no reply). triage and
 * turn are the turn's decisions (the Decision rows are made and their Refs kept on the turn), usage its usage rows, and
 * checkKey and checks the key and rows that Checks.Render made for the reply.
 */
export interface SeedTurn {
  createdAt: string;
  text: string;
  replyText: string;
  channel?: string;
  fromGuide?: boolean;
  /** The turn's trace session (Turn.TraceHeaderId), which gives its chat.message a trace target. */
  traceHeaderId?: number;
  catalogKey?: string;
  fallbackReason?: string;
  state?: 'done' | 'running';
  triage?: SeedDecision;
  turn?: SeedDecision;
  usage?: SeedUsage[];
  checkKey?: string;
  checks?: SeedCheck[];
}

/**
 * What seedTurns made: the Ref of each turn, with publishing the Seq of its chat.message event, and the Refs of each turn's
 * decisions ("" for a decision it did not make), in the order given.
 */
export interface Seeded {
  refs: string[];
  seqs: number[];
  decisions: Array<{ triage: string; turn: string }>;
}

/** A number as an ObjectScript literal; anything that is not a finite number is refused. */
function numeric(value: number, name: string): string {
  if (!Number.isFinite(value)) throw new Error(`${name} must be a finite number`);
  return String(value);
}

/** The fields of a Decision row, as [SeedDecision key, property, type]. */
const DECISION_FIELDS: ReadonlyArray<readonly [keyof SeedDecision, string, 'string' | 'number' | 'boolean']> = [
  ['outcome', 'Outcome', 'string'],
  ['summary', 'Summary', 'string'],
  ['reasons', 'Reasons', 'string'],
  ['confidence', 'Confidence', 'number'],
  ['fallback', 'Fallback', 'boolean'],
  ['fallbackReason', 'FallbackReason', 'string'],
  ['inputTokens', 'InputTokens', 'number'],
  ['outputTokens', 'OutputTokens', 'number'],
  ['cacheReadTokens', 'CacheReadTokens', 'number'],
  ['cacheWriteTokens', 'CacheWriteTokens', 'number'],
  ['agentStepCount', 'AgentStepCount', 'number'],
  ['durationMs', 'DurationMs', 'number'],
  ['costUSD', 'CostUSD', 'number'],
  ['traceSessionId', 'TraceSessionId', 'number'],
];

/** The lines that make one Decision row in the variable, from the identity lines given, and save it into sc. */
function decisionRowLines(variable: string, kind: 'decide' | 'turn', identity: string[], decision: SeedDecision, recordedAt: string): string[] {
  const lines = [
    `Set ${variable}=##class(OcuTalon.Bridge.Data.Decision).%New()`,
    `Set ${variable}.Ref=##class(OcuTalon.Bridge.Ids).NewRef()`,
    `Set ${variable}.Kind=${quoted(kind)}`,
    ...identity,
    `Set ${variable}.Model=${quoted(decision.model ?? 'claude-haiku-5-5')}`,
    `Set ${variable}.RecordedAt=${recordedAt}`,
  ];
  for (const [key, property, type] of DECISION_FIELDS) {
    const value = decision[key];
    if (value === undefined) continue;
    if (type === 'string') lines.push(`Set ${variable}.${property}=${quoted(String(value))}`);
    else if (type === 'boolean') lines.push(`Set ${variable}.${property}=${value ? 1 : 0}`);
    else lines.push(`Set ${variable}.${property}=${numeric(Number(value), key)}`);
  }
  lines.push(`Set sc=${variable}.%Save()`);
  return lines;
}

/** The lines that make one Decision row in the variable, for the turn in t and the session in s, and keep its status in bad. */
function decisionLines(variable: string, kind: 'decide' | 'turn', decision: SeedDecision, createdAt: string): string[] {
  return [
    ...decisionRowLines(variable, kind, [`Set ${variable}.ItemId=t.ItemId`, `Set ${variable}.OwnerRef=s.Ref`], decision, quoted(decision.recordedAt ?? createdAt)),
    'If $System.Status.IsError(sc) Set bad=1',
    `If $System.Status.IsOK(sc) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(${variable})`,
  ];
}

/** The lines that make one Usage row for the decision in the variable. */
function usageLines(variable: string, kind: 'decide' | 'turn', usage: SeedUsage, createdAt: string): string[] {
  const lines = [
    'Set u=##class(OcuTalon.Bridge.Data.Usage).%New()',
    `Set u.DecisionRef=${variable}.Ref`,
    'Set u.ItemId=t.ItemId',
    `Set u.Kind=${quoted(kind)}`,
    'Set u.Agent="zz"',
    'Set u.Channel="web"',
    'Set u.OwnerRef=s.Ref',
    'Set u.Model="claude-haiku-5-5"',
    `Set u.Estimated=${usage.estimated ? 1 : 0}`,
    `Set u.RecordedAt=${quoted(createdAt)}`,
  ];
  const counts: ReadonlyArray<readonly [keyof SeedUsage, string]> = [
    ['inputTokens', 'InputTokens'],
    ['outputTokens', 'OutputTokens'],
    ['cacheReadTokens', 'CacheReadTokens'],
    ['cacheWriteTokens', 'CacheWriteTokens'],
    ['costUSD', 'CostUSD'],
  ];
  for (const [key, property] of counts) {
    const value = usage[key];
    if (typeof value === 'number') lines.push(`Set u.${property}=${numeric(value, key)}`);
  }
  lines.push('Set sc=u.%Save()', 'If $System.Status.IsError(sc) Set bad=1');
  return lines;
}

/**
 * Writes turns into the user's own session (Session.ForUser), each with a new Ref and ItemId, done unless the seed says running.
 * A turn's decisions, usage rows and check rows are written with it (the Decision rows first, then the turn that names them).
 * With publish, each row's chat.message event (ChatMessage.FromRow) is then published on the session stream, after its save, the
 * way the production's one publisher would (AD-33); without it the turns appear on the next /state. Every turn and every Decision row
 * it writes is recorded for Test.Data.Fixture.Clean (Adopt), so that cleanFixtureRows removes them by their Refs (`refs` and
 * `decisions` of the result; `turnRows` lists both); its Usage rows have no Ref of their own and are not recorded. Every value of a
 * turn goes through quoted() or numeric(), and the user name through literal().
 */
export async function seedTurns(user: string, turns: SeedTurn[], publish = false): Promise<Seeded> {
  const lines = [`Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`];
  turns.forEach((turn, i) => {
    const running = turn.state === 'running';
    lines.push(
      'Set bad=0,dt="",dr=""',
      'Set t=##class(OcuTalon.Data.Turn).%New()',
      'Set t.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set t.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set t.SessionRef=s.Ref',
      `Set t.State=${running ? '"running"' : '"done"'}`,
      `Set t.Attempt=${running ? 1 : 0}`,
      `Set t.CreatedAt=${quoted(turn.createdAt)}`,
      `Set t.Channel=${quoted(turn.channel ?? 'web')}`,
      `Set t.FromGuide=${turn.fromGuide ? 1 : 0}`,
      ...(turn.traceHeaderId === undefined ? [] : [`Set t.TraceHeaderId=${numeric(turn.traceHeaderId, 'traceHeaderId')}`]),
      `Set t.Text=${quoted(turn.text)}`,
      `Set t.ReplyText=${quoted(turn.replyText)}`,
      `Set t.ReplyCatalogKey=${quoted(turn.catalogKey ?? '')}`,
      `Set t.FallbackReason=${quoted(turn.fallbackReason ?? '')}`,
    );
    if (turn.triage) lines.push(...decisionLines('d1', 'decide', turn.triage, turn.createdAt), 'Set dt=d1.Ref', 'Set t.TriageDecisionRef=dt');
    if (turn.turn) lines.push(...decisionLines('d2', 'turn', turn.turn, turn.createdAt), 'Set dr=d2.Ref', 'Set t.TurnDecisionRef=dr');
    for (const usage of turn.usage ?? []) {
      const variable = usage.of === 'triage' ? 'd1' : 'd2';
      if (!(usage.of === 'triage' ? turn.triage : turn.turn)) throw new Error(`turn ${i} has a usage row for a decision it does not have`);
      lines.push(...usageLines(variable, usage.of === 'triage' ? 'decide' : 'turn', usage, turn.createdAt));
    }
    if (turn.checkKey) lines.push(`Set t.CheckKey=${quoted(turn.checkKey)}`);
    if (turn.checks) lines.push(`Set t.CheckRows=${quoted(JSON.stringify(turn.checks))}`);
    lines.push('Set sc=t.%Save()', 'If $System.Status.IsError(sc) Set bad=1', 'If $System.Status.IsOK(sc) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(t)', `Write !,"CHK|ref|${i}|",t.Ref,"|",'bad`, `Write !,"CHK|dec|${i}|",dt,"|",dr`);
    if (publish) {
      lines.push(
        'Set p=##class(OcuTalon.Live.Payload.ChatMessage).FromRow(t)',
        'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"chat.message",p,.q)',
        `Write !,"CHK|seq|${i}|",q`,
      );
    }
  });
  const out = await irisScript(lines.join('\n'));
  const refs: string[] = [];
  const seqs: number[] = [];
  const decisions: Array<{ triage: string; turn: string }> = [];
  turns.forEach((_turn, i) => {
    const [ref, saved] = (chk(out, `ref|${i}`) ?? '').split('|');
    if (!ref || saved !== '1') throw new Error(`turn ${i} could not be seeded (${out.join(' ')})`);
    refs.push(ref);
    const [triage = '', turnRef = ''] = (chk(out, `dec|${i}`) ?? '').split('|');
    decisions.push({ triage, turn: turnRef });
    if (publish) {
      const seq = Number(chk(out, `seq|${i}`));
      if (!Number.isInteger(seq) || seq < 1) throw new Error(`turn ${i} could not be published (${out.join(' ')})`);
      seqs.push(seq);
    }
  });
  return { refs, seqs, decisions };
}

/** The Refs of the rows that seedTurns recorded (the turns and their Decision rows), for cleanFixtureRows. */
export const turnRows = (seeded: Seeded): string[] => [...seeded.refs, ...seeded.decisions.flatMap((one) => [one.triage, one.turn])].filter((ref) => ref !== '');

/**
 * Gives BridgeSink an event of the bridge, as the bridge's Decide would after its commit (HostSink.OnEvent in the IRIS job that runs
 * the script, with no bridge context), and checks that it returned OK. The owner is the user's own session, or with 'instance' the
 * owner instance (an instance request reaches the sessions that watch its incident's production). The payload is passed as JSON
 * through quoted(). Returns the last Seq of the user's session stream after the call, which is the Seq of the event it published when
 * it published one for that session.
 */
export async function sinkEvent(user: string, type: string, payload: Record<string, unknown>, owner: 'session' | 'instance' = 'session'): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set sc=##class(OcuTalon.Core.BridgeSink).OnEvent(${quoted(type)},${owner === 'instance' ? '"instance"' : 's.Ref'},##class(%DynamicAbstractObject).%FromJSON(${quoted(JSON.stringify(payload))}))`,
      'Write !,"CHK|sink|",$System.Status.IsOK(sc)',
      'Write !,"CHK|seq|",##class(OcuTalon.Live.Publish).LastSeq(s.Ref)',
    ].join('\n'),
  );
  if (chk(lines, 'sink') !== '1') throw new Error(`BridgeSink did not return OK for ${type} (${lines.join(' ')})`);
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 0) throw new Error(`the stream's last Seq could not be read (${lines.join(' ')})`);
  return seq;
}

/**
 * Ends a running turn of the user's own session with a reply, and publishes its chat.message event, as Conversation would when
 * the reply lands. The turn must be the session's own.
 */
export async function finishTurn(user: string, ref: string, replyText = 'zz finished'): Promise<void> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set t=##class(OcuTalon.Data.Turn).RefIndexOpen(${quoted(ref)})`,
      `If '$IsObject(t) || (t.SessionRef '= s.Ref) { Write !,"CHK|finish|0" Halt }`,
      'Set t.State="done"',
      `Set t.ReplyText=${quoted(replyText)}`,
      'Set sc=t.%Save()',
      'Set p=##class(OcuTalon.Live.Payload.ChatMessage).FromRow(t)',
      'Set sc2=##class(OcuTalon.Live.Publish).Publish(s.Ref,"chat.message",p,.q)',
      'Write !,"CHK|finish|",$System.Status.IsOK(sc),$System.Status.IsOK(sc2)',
    ].join('\n'),
  );
  if (chk(lines, 'finish') !== '11') throw new Error(`the turn could not be finished (${lines.join(' ')})`);
}

/** A decision for seedDecisions: its fields, and its kind (decide, the attention decision, unless it says turn). */
export type SeedDecisionRow = SeedDecision & { kind?: 'decide' | 'turn' };

/**
 * Writes Decision rows of the user's own session (Bridge.Data.Decision, AD-20) with the fields given, in one script, as Decide would
 * for an item: a new Ref and ItemId each, the owner the session, the model claude-haiku-5-5 and the time now unless recordedAt says
 * otherwise. Each row is recorded for Test.Data.Fixture.Clean, so that cleanFixtureRows removes it by Ref. Every value goes through
 * quoted() or numeric(), and the user name through literal(). Returns the Refs, in the order given.
 */
export async function seedDecisions(user: string, rows: SeedDecisionRow[]): Promise<string[]> {
  const lines = [`Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`];
  rows.forEach((row, i) => {
    lines.push(
      ...decisionRowLines(
        'd',
        row.kind ?? 'decide',
        [row.itemId === undefined ? 'Set d.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()' : `Set d.ItemId=${quoted(row.itemId)}`, 'Set d.OwnerRef=s.Ref'],
        row,
        row.recordedAt === undefined ? '##class(OcuTalon.Data.Time).NowUtc()' : quoted(row.recordedAt),
      ),
      'If $System.Status.IsOK(sc) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(d)',
      `Write !,"CHK|decision|${i}|",d.Ref,"|",$System.Status.IsOK(sc)`,
    );
  });
  const out = await irisScript(lines.join('\n'));
  return rows.map((_row, i) => {
    const [ref, saved] = (chk(out, `decision|${i}`) ?? '').split('|');
    if (!ref || saved !== '1') throw new Error(`decision ${i} could not be seeded (${out.join(' ')})`);
    return ref;
  });
}

/**
 * Writes one Decision row of the user's own session (see seedDecisions): the kind decide unless kind says turn. A card that names
 * the row (sendItemDecision's decisionRef) shows its strip. Returns the row's Ref.
 */
export async function seedDecision(user: string, fields: SeedDecision, kind: 'decide' | 'turn' = 'decide'): Promise<string> {
  const [ref] = await seedDecisions(user, [{ ...fields, kind }]);
  return ref!;
}

/** An untrusted item for sendItem. The channel is mailbox unless it says otherwise; the CatalogKey and its Slots are optional. */
export interface ItemFields {
  text?: string;
  sender?: string;
  subject?: string;
  channel?: string;
  catalogKey?: string;
  slots?: Record<string, unknown>;
}

/** An ItemDecision for sendItemDecision: what Intake would send OutcomeRouter for an item of the user's own session. */
export interface ItemDecisionFields {
  outcome: string;
  summary: string;
  decisionRef?: string;
  fallback?: boolean;
  fallbackReason?: string;
  catalogKey?: string;
  slots?: Record<string, unknown>;
  channel?: string;
}

/** A Notification for sendNotification: what a producer sends Notify for the user's own session. */
export interface NotificationFields {
  kind: string;
  catalogKey: string;
  slots: Record<string, unknown>;
  decisionRef?: string;
  approvalRef?: string;
  incidentRef?: string;
}

/**
 * Sends a message from a service host that the script creates in the OCUTALON namespace (Ens.Director.CreateBusinessService, as
 * the production's tests do) to the item, asynchronously, with the session's TraceRef as the host's SuperSession (AD-26), and
 * checks both statuses. The lines build the message in the variable m from the session in s.
 */
async function sendFrom(user: string, host: string, target: string, build: string[], idProperty: string): Promise<string> {
  const lines = [
    `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
    `Set sc1=##class(Ens.Director).CreateBusinessService(${quoted(host)},.h)`,
    'Set h.%SuperSession=s.TraceRef',
    ...build,
    `Set sc2=h.SendRequestAsync(${quoted(target)},m)`,
    `Write !,"CHK|sent|",m.${idProperty},"|",$System.Status.IsOK(sc1),$System.Status.IsOK(sc2)`,
  ];
  const out = await irisScript(lines.join('\n'));
  const [id = '', status] = (chk(out, 'sent') ?? '').split('|');
  if (status !== '11') throw new Error(`the message could not be sent from ${host} to ${target} (${out.join(' ')})`);
  return id;
}

/** The lines that set a property of the message m from a string. */
const setText = (property: string, value: string | undefined): string[] => (value === undefined ? [] : [`Set m.${property}=${quoted(value)}`]);

/**
 * Sends an untrusted Item of the user's own session from a SimMailboxIn host to Intake, as the mailbox service will, with the
 * session's TraceRef as SuperSession. Returns the ItemId.
 */
export function sendItem(user: string, item: ItemFields): Promise<string> {
  return sendFrom(
    user,
    'SimMailboxIn',
    'Intake',
    [
      'Set m=##class(OcuTalon.Msg.Item).%New()',
      'Set m.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set m.SessionRef=s.Ref',
      `Set m.Channel=${quoted(item.channel ?? 'mailbox')}`,
      'Set m.Provenance="untrusted"',
      ...setText('Text', item.text ?? ''),
      ...setText('Sender', item.sender),
      ...setText('Subject', item.subject),
      ...setText('CatalogKey', item.catalogKey),
      ...setText('Slots', item.slots === undefined ? undefined : JSON.stringify(item.slots)),
    ],
    'ItemId',
  );
}

/**
 * Sends an ItemDecision of the user's own session to OutcomeRouter from a SimMailboxIn host, as Intake would, with the session's
 * TraceRef as SuperSession. Returns the ItemId.
 */
export function sendItemDecision(user: string, decision: ItemDecisionFields): Promise<string> {
  return sendFrom(
    user,
    'SimMailboxIn',
    'OutcomeRouter',
    [
      'Set m=##class(OcuTalon.Msg.ItemDecision).%New()',
      'Set m.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set m.OwnerRef=s.Ref',
      `Set m.Channel=${quoted(decision.channel ?? 'mailbox')}`,
      `Set m.Outcome=${quoted(decision.outcome)}`,
      `Set m.Summary=${quoted(decision.summary)}`,
      `Set m.Fallback=${decision.fallback ? 1 : 0}`,
      ...setText('DecisionRef', decision.decisionRef),
      ...setText('FallbackReason', decision.fallbackReason),
      ...setText('CatalogKey', decision.catalogKey),
      ...setText('Slots', decision.slots === undefined ? undefined : JSON.stringify(decision.slots)),
    ],
    'ItemId',
  );
}

/**
 * Sends a Notification for the user's own session to Notify from a NoticesIn host, as the producers of notices will, with the
 * session's TraceRef as SuperSession. Returns the session's Ref.
 */
export function sendNotification(user: string, notification: NotificationFields): Promise<string> {
  return sendFrom(
    user,
    'NoticesIn',
    'Notify',
    [
      'Set m=##class(OcuTalon.Msg.Notification).%New()',
      'Set m.SessionRef=s.Ref',
      `Set m.Kind=${quoted(notification.kind)}`,
      `Set m.CatalogKey=${quoted(notification.catalogKey)}`,
      `Set m.Slots=${quoted(JSON.stringify(notification.slots))}`,
      ...setText('DecisionRef', notification.decisionRef),
      ...setText('ApprovalRef', notification.approvalRef),
      ...setText('IncidentRef', notification.incidentRef),
    ],
    'SessionRef',
  );
}

/** Deletes the fixture rows with these Refs (Test.Data.Fixture.Clean with the Refs), and no row that another test made. */
export async function cleanFixtureRows(refs: Array<string | undefined>): Promise<void> {
  const mine = refs.filter((ref): ref is string => !!ref && /^[A-Za-z0-9_-]+$/.test(ref));
  if (mine.length === 0) return;
  await irisScript(`Do ##class(OcuTalon.Test.Data.Fixture).Clean("${mine.join(',')}")\nWrite !,"CHK|clean|1"`);
}

/** The IRIS statement that makes a Fixture row's `fields` object from the properties given: a JSON object, passed through quoted(). */
const fieldsObject = (properties: Record<string, string>): string => `##class(%DynamicObject).%FromJSON(${quoted(JSON.stringify(properties))})`;

/** The properties of an object that have a value, under the property names the rows use. */
function properties(values: Record<string, string | undefined>): Record<string, string> {
  return Object.fromEntries(Object.entries(values).filter((entry): entry is [string, string] => entry[1] !== undefined));
}

/**
 * The dry run of a fix request as the stored JSON (ApprovalRequest.DRYRUNKEYS): the count of items it affects, the noun that names
 * one and many, the count to resend (the affected count unless given), and the field with its example (the field OrderDate and an
 * empty example unless given). null gives a request with no dry run.
 */
export interface SeedDryRun {
  affected: number;
  itemNoun?: { one: string; other: string };
  resend?: number;
  field?: string;
  before?: string;
  after?: string;
}

/**
 * The fields of an approval request that seedApproval sets; a field left out keeps Fixture.Approval's default (a pending fix of 4 orders
 * raised now, expiring in 2030, with no required role). requiredRole is the IRIS role that Approval.Answer demands of the answerer
 * (OcuTalonUser for a request that the floor user may answer); the answered fields describe an answer that is already recorded.
 */
export interface ApprovalFields {
  kind?: string;
  state?: string;
  incidentRef?: string;
  toolName?: string;
  raisedAt?: string;
  expiresAt?: string;
  dryRun?: SeedDryRun | null;
  requiredRole?: string;
  answeredAction?: string;
  answeredChannel?: string;
  answeredBy?: string;
  answeredAt?: string;
}

/** Who owns a seeded request: the user's own session, the owner instance, or the fixture session with this Ref (seedOtherSession). */
export type ApprovalOwner = 'session' | 'instance' | { sessionRef: string };

/**
 * Writes an approval request through Test.Data.Fixture.Approval: owned by the user's own session, by the owner instance (for the
 * incident that incidentRef names) or by another fixture session. Returns its Ref; cleanFixtureRows removes it.
 */
export async function seedApproval(user: string, fields: ApprovalFields = {}, owner: ApprovalOwner = 'session'): Promise<string> {
  const dryRun =
    fields.dryRun === undefined
      ? undefined
      : fields.dryRun === null
        ? ''
        : JSON.stringify({
            affected: fields.dryRun.affected,
            resend: fields.dryRun.resend ?? fields.dryRun.affected,
            leftOut: 0,
            field: fields.dryRun.field ?? 'OrderDate',
            before: fields.dryRun.before ?? '',
            after: fields.dryRun.after ?? '',
            itemNoun: fields.dryRun.itemNoun,
          });
  const row = properties({
    Kind: fields.kind,
    ToolName: fields.toolName,
    ExpiresAt: fields.expiresAt,
    DryRun: dryRun,
    RequiredRole: fields.requiredRole,
    AnsweredAction: fields.answeredAction,
    AnsweredChannel: fields.answeredChannel,
    AnsweredBy: fields.answeredBy,
    AnsweredAt: fields.answeredAt,
  });
  const ownerExpression = owner === 'instance' ? '"instance"' : owner === 'session' ? 's.Ref' : quoted(owner.sessionRef);
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set r=##class(OcuTalon.Test.Data.Fixture).Approval(${ownerExpression},${quoted(fields.incidentRef ?? '')},${quoted(fields.state ?? 'pending')},${fields.raisedAt === undefined ? '##class(OcuTalon.Data.Time).NowUtc()' : quoted(fields.raisedAt)},${fieldsObject(row)})`,
      'Write !,"CHK|approval|",r',
    ].join('\n'),
  );
  const ref = chk(lines, 'approval');
  if (!ref) throw new Error(`the approval request could not be seeded (${lines.join(' ')})`);
  return ref;
}

/**
 * Writes a fixture session of another IRIS user (Test.Data.Fixture.Session): it belongs to no one who signs in, so what it owns is
 * invisible to the floor user. Returns its Ref; cleanFixtureRows removes it.
 */
export async function seedOtherSession(user: string): Promise<string> {
  const lines = await irisScript([`Set r=##class(OcuTalon.Test.Data.Fixture).Session(${literal(user)})`, 'Write !,"CHK|session|",r'].join('\n'));
  const ref = chk(lines, 'session');
  if (!ref) throw new Error(`the fixture session could not be seeded (${lines.join(' ')})`);
  return ref;
}

/**
 * Answers a request as the user from the script's job, with the bridge's own API and no event: the sink is the bridge's no-op
 * HostSink, so nothing reaches any stream and the page learns of the answer only when it presses, polls or reloads. Returns the
 * result (done, already_answered, expired, not_found or not_allowed). A real answer on a fixture row waits about 5 s for the hold's
 * task, which a fixture row does not have.
 */
export async function answerQuietly(user: string, ref: string, action: 'approve' | 'reject', channel: 'web' | 'phone'): Promise<string> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set r=##class(OcuTalon.Bridge.Approval).Answer(${quoted(ref)},${quoted(action)},${quoted(channel)},${literal(user)},s.Ref,.w,"OcuTalon.Bridge.Ext.HostSink")`,
      'Write !,"CHK|answer|",r',
    ].join('\n'),
  );
  const result = chk(lines, 'answer');
  if (!result) throw new Error(`the answer could not be given (${lines.join(' ')})`);
  return result;
}

/** What the row of a request holds after an answer, read back: State, AnsweredAction, AnsweredChannel, AnsweredBy and AnsweredAt. */
export async function readApproval(ref: string): Promise<{ state: string; action: string; channel: string; by: string; at: string }> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(${quoted(ref)})`,
      `If '$IsObject(r) { Write !,"CHK|row|missing" Halt }`,
      'Write !,"CHK|row|",r.State,"|",r.AnsweredAction,"|",r.AnsweredChannel,"|",r.AnsweredBy,"|",r.AnsweredAt',
    ].join('\n'),
  );
  const row = chk(lines, 'row');
  if (row === undefined || row === 'missing') throw new Error(`the approval request could not be read (${lines.join(' ')})`);
  const [state = '', action = '', channel = '', by = '', at = ''] = row.split('|');
  return { state, action, channel, by, at };
}

/**
 * The number of production messages from AnswersIn to AnswerOps in the trace sessions tagged with the session's TraceRef (the user's
 * own session), and that TraceRef: what an answer leaves in Visual Trace besides the audit entry.
 */
export async function answerHeaders(user: string): Promise<{ count: number; traceRef: string }> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SuperSession = ? AND SourceConfigName = \'AnswersIn\' AND TargetConfigName = \'AnswerOps\' AND Type = 1",s.TraceRef)',
      'Do rs.%Next()',
      'Write !,"CHK|count|",rs.%GetData(1)',
      'Write !,"CHK|trace|",s.TraceRef',
    ].join('\n'),
  );
  const count = Number(chk(lines, 'count'));
  const traceRef = chk(lines, 'trace');
  if (!Number.isInteger(count) || !traceRef) throw new Error(`the answer headers could not be counted (${lines.join(' ')})`);
  return { count, traceRef };
}

/** Sets the state of an approval request, as the bridge would when it is answered, expires or is cancelled. */
export async function setApprovalState(ref: string, state: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(${quoted(ref)})`,
      `If '$IsObject(r) { Write !,"CHK|state|0" Halt }`,
      `Set r.State=${quoted(state)}`,
      'Write !,"CHK|state|",$System.Status.IsOK(r.%Save())',
    ].join('\n'),
  );
  if (chk(lines, 'state') !== '1') throw new Error(`the approval request could not be changed (${lines.join(' ')})`);
}

/** The fields of a background check that seedCheck and publishCheck set; the check is a production check unless kind says otherwise. */
export interface CheckFields {
  /** The ref of the check to publish an update for; seedCheck's row has a new one, which it returns. */
  ref?: string;
  kind?: string;
  namespace?: string;
  production?: string;
  displayName?: string;
  lastRunAt?: string;
  result?: string;
  finding?: string;
  /** The header of the check's latest run, where its trace link opens (the namespace should have a trace application, as OCUTALON has). */
  lastRunHeaderId?: number;
}

/** Writes a background check of the user's own session through Test.Data.Fixture.Check. Returns its Ref; cleanFixtureRows removes it. */
export async function seedCheck(user: string, fields: CheckFields = {}): Promise<string> {
  const row = properties({
    Kind: fields.kind,
    DisplayName: fields.displayName,
    LastRunAt: fields.lastRunAt,
    Result: fields.result,
    Finding: fields.finding,
    LastRunHeaderId: fields.lastRunHeaderId === undefined ? undefined : numeric(fields.lastRunHeaderId, 'lastRunHeaderId'),
  });
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set r=##class(OcuTalon.Test.Data.Fixture).Check(s.Ref,${quoted(fields.namespace ?? 'ZZNS')},${quoted(fields.production ?? 'Zz.Production')},${fieldsObject(row)})`,
      'Write !,"CHK|check|",r',
    ].join('\n'),
  );
  const ref = chk(lines, 'check');
  if (!ref) throw new Error(`the check could not be seeded (${lines.join(' ')})`);
  return ref;
}

/**
 * Publishes a check event on the user's own session stream, as Checks will, and returns its Seq. The payload is a Live.Payload.Check
 * with the fields given; the ref is the one given, which a seeded check's row has, so that the event updates its row in place.
 */
export async function publishCheck(user: string, fields: CheckFields & { ref: string }): Promise<number> {
  const set = (property: string, value: string | undefined): string[] => (value === undefined ? [] : [`Set p.${property}=${quoted(value)}`]);
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      'Set p=##class(OcuTalon.Live.Payload.Check).%New()',
      `Set p.Ref=${quoted(fields.ref)}`,
      `Set p.Kind=${quoted(fields.kind ?? 'production')}`,
      ...set('Namespace', fields.namespace),
      ...set('Production', fields.production),
      ...set('DisplayName', fields.displayName),
      ...set('LastRunAt', fields.lastRunAt),
      ...set('Result', fields.result),
      ...set('Finding', fields.finding),
      ...(fields.lastRunHeaderId === undefined ? [] : [`Set p.TraceHeaderId=${numeric(fields.lastRunHeaderId, 'lastRunHeaderId')}`, `Set p.TraceNamespace=${quoted(fields.namespace ?? 'ZZNS')}`]),
      'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"check",p,.q)',
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the check could not be published (${lines.join(' ')})`);
  return seq;
}

/** The slots of a status condition that publishStatus sets: the limit, the cap in dollars and the UTC time. */
export interface StatusSlots {
  limit?: number;
  cap?: number;
  time?: string;
}

/**
 * Publishes a status event on the user's own session stream, as StatusMonitor does for the instance, and returns its Seq. The
 * payload is a Live.Payload.Status with the condition, its active flag and, when given, its slots. The page applies a status event
 * of either stream alike, and a spec never publishes on the instance stream, so this is how a spec turns a condition on and off.
 */
export async function publishStatus(user: string, fields: { condition: string; active: boolean; slots?: StatusSlots }): Promise<number> {
  const slots = fields.slots;
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      'Set p=##class(OcuTalon.Live.Payload.Status).%New()',
      `Set p.Condition=${quoted(fields.condition)}`,
      `Set p.Active=${fields.active ? 1 : 0}`,
      ...(slots === undefined
        ? []
        : [
            'Set p.Slots=##class(OcuTalon.Live.Payload.Part.StatusSlots).%New()',
            ...(slots.limit === undefined ? [] : [`Set p.Slots.Limit=${numeric(slots.limit, 'limit')}`]),
            ...(slots.cap === undefined ? [] : [`Set p.Slots.Cap=${numeric(slots.cap, 'cap')}`]),
            ...(slots.time === undefined ? [] : [`Set p.Slots.Time=${quoted(slots.time)}`]),
          ]),
      'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"status",p,.q)',
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the status event could not be published (${lines.join(' ')})`);
  return seq;
}

/** Writes a reminder of the user's own session through Test.Data.Fixture.Reminder (pending, due at dueAt when given). Returns its Ref; cleanFixtureRows removes it. */
export async function seedReminder(user: string, fields: Omit<ReminderFields, 'ref' | 'traceHeaderId' | 'traceNamespace'> = {}): Promise<string> {
  const row = properties({ Text: fields.text });
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set r=##class(OcuTalon.Test.Data.Fixture).Reminder(s.Ref,${quoted(fields.dueAt ?? '')},${quoted(fields.state ?? 'pending')},${fieldsObject(row)})`,
      'Write !,"CHK|reminder|",r',
    ].join('\n'),
  );
  const ref = chk(lines, 'reminder');
  if (!ref) throw new Error(`the reminder could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** The fields of an incident that seedIncident sets; it is noticed now unless noticedAt says otherwise ("" is an incident that has not been noticed). */
export interface IncidentFields {
  namespace?: string;
  production?: string;
  noticedAt?: string;
  /** The incident's trace session, which its approval request's trace link opens (AD-26). */
  traceHeaderId?: number;
  /** The incident's state (open unless given) and its open variant (fix unless given). */
  state?: string;
  openVariant?: string;
}

/**
 * Writes an incident through Test.Data.Fixture.Incident. The owner is 'instance', the user whose own session owns it, or `{sessionRef}`,
 * the fixture session with this Ref (seedOtherSession), as seedApproval's ApprovalOwner is. Returns its Ref; cleanFixtureRows removes it.
 */
export async function seedIncident(owner: string | { sessionRef: string }, fields: IncidentFields = {}): Promise<string> {
  const row = properties({
    TraceHeaderId: fields.traceHeaderId === undefined ? undefined : numeric(fields.traceHeaderId, 'traceHeaderId'),
    State: fields.state,
    OpenVariant: fields.openVariant,
  });
  const lines = await irisScript(
    [
      ...(typeof owner === 'object'
        ? [`Set o=${quoted(owner.sessionRef)}`]
        : owner === 'instance'
          ? ['Set o="instance"']
          : [`Set s=##class(OcuTalon.Data.Session).ForUser(${literal(owner)},.sc)`, 'Set o=s.Ref']),
      `Set r=##class(OcuTalon.Test.Data.Fixture).Incident(o,${fields.noticedAt === undefined ? '##class(OcuTalon.Data.Time).NowUtc()' : quoted(fields.noticedAt)},${quoted(fields.namespace ?? 'ZZNS')},${quoted(fields.production ?? 'Zz.Production')},${fieldsObject(row)})`,
      'Write !,"CHK|incident|",r',
    ].join('\n'),
  );
  const ref = chk(lines, 'incident');
  if (!ref) throw new Error(`the incident could not be seeded (${lines.join(' ')})`);
  return ref;
}

/**
 * Puts Test.Demo.IncidentManagerDouble behind the IncidentManager item of the stack's production (its Use), so that a dismissal reaches a
 * fixture owner that closes the incident and publishes its closed view (Story 6.4; AD-29). Throws with the status text when the item
 * could not take it. A spec that calls this puts the item back with restoreIncidentManager in its afterAll.
 */
export async function useIncidentManagerDouble(): Promise<void> {
  const lines = await irisScript(['Set sc=##class(OcuTalon.Test.Demo.IncidentManagerDouble).Use()', 'Write !,"CHK|use|",$System.Status.IsOK(sc),"|",$TRANSLATE($System.Status.GetErrorText(sc),$Char(13,10),"  ")'].join('\n'));
  const use = chk(lines, 'use');
  if (!use?.startsWith('1|')) throw new Error(`the IncidentManager item could not take the double (${lines.join(' ')})`);
}

/** Puts the IncidentManager item's class back as useIncidentManagerDouble found it (the double's Restore); throws when that fails. */
export async function restoreIncidentManager(): Promise<void> {
  const lines = await irisScript(['Set sc=##class(OcuTalon.Test.Demo.IncidentManagerDouble).Restore()', 'Write !,"CHK|restore|",$System.Status.IsOK(sc),"|",$TRANSLATE($System.Status.GetErrorText(sc),$Char(13,10),"  ")'].join('\n'));
  const restore = chk(lines, 'restore');
  if (!restore?.startsWith('1|')) throw new Error(`the IncidentManager item could not be restored (${lines.join(' ')})`);
}

/** A command that the double recorded: its verb, the session it came for and its origin. */
export interface DoubleCommand {
  verb: string;
  session: string;
  origin: string;
}

/** The commands about the incident that the IncidentManager double recorded, oldest first (the double's Recorded). */
export async function doubleCommands(ref: string): Promise<DoubleCommand[]> {
  const lines = await irisScript(`Write !,"CHK|commands|",##class(OcuTalon.Test.Demo.IncidentManagerDouble).Recorded(${quoted(ref)})`);
  const recorded = chk(lines, 'commands');
  if (recorded === undefined) throw new Error(`the double's commands could not be read (${lines.join(' ')})`);
  return recorded === ''
    ? []
    : recorded.split(';').map((command) => {
        const [verb = '', session = '', origin = ''] = command.split('|');
        return { verb, session, origin };
      });
}

/** The State of the incident's row ("" when there is none). */
export async function incidentState(ref: string): Promise<string> {
  const lines = await irisScript([`Set r=##class(OcuTalon.Data.Incident).RefIndexOpen(${quoted(ref)})`, 'Write !,"CHK|state|",$Select($IsObject(r):1_"|"_r.State,1:0)'].join('\n'));
  const state = chk(lines, 'state');
  if (state === undefined) throw new Error(`the incident could not be read (${lines.join(' ')})`);
  return state.startsWith('1|') ? state.slice(2) : '';
}

/**
 * Sets the test seam that says whether this release includes Telegram (Test.Data.Fixture.SetTelegramIncluded, which Channel.Telegram.In's
 * Included() reads) and returns the value it had, 0 when it was not set, so that the caller can put it back.
 */
export async function setTelegramIncluded(value: 0 | 1): Promise<0 | 1> {
  const lines = await irisScript([`Set was=##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(${value})`, 'Write !,"CHK|telegram|",was'].join('\n'));
  const was = chk(lines, 'telegram');
  if (was !== '0' && was !== '1') throw new Error(`the Telegram seam could not be set (${lines.join(' ')})`);
  return was === '1' ? 1 : 0;
}

/** The Visual Trace settings of a user that setTraceSettings reads and writes (^EnsPortal.Settings(user, "VisualTrace", ...)): the page size and "Show events". */
export interface TraceSettings {
  itemsPerPage?: string | number | null;
  showEvents?: string | number | null;
}

/** The settings of a user, with the node name of each key. */
const TRACE_SETTING_NODES: ReadonlyArray<readonly [keyof TraceSettings, string]> = [
  ['itemsPerPage', 'ItemsPerPage'],
  ['showEvents', 'ShowEvents'],
];

/**
 * Sets or kills the user's Visual Trace settings (EnsPortal.VisualTrace's own nodes, which its getters read) for each key given: a
 * value sets the node, null kills it, and a key left out stays as it is. Returns the values the nodes had before, null for a node that
 * was not set, for every key given, so that the caller can put the user's settings back with the same call: a spec that changes them
 * restores them in finally. Every value goes through quoted(), and the user name through literal().
 */
export async function setTraceSettings(user: string, settings: TraceSettings): Promise<TraceSettings> {
  const lines = [`Set u=${literal(user)}`];
  for (const [key, node] of TRACE_SETTING_NODES) {
    const value = settings[key];
    if (value === undefined) continue;
    const ref = `^EnsPortal.Settings(u,"VisualTrace","${node}")`;
    lines.push(`Write !,"CHK|was|${key}|",$Select($Data(${ref})#10:1_$Get(${ref}),1:0)`);
    lines.push(value === null ? `Kill ${ref}` : `Set ${ref}=${quoted(String(value))}`);
  }
  const out = await irisScript(lines.join('\n'));
  const was: TraceSettings = {};
  for (const [key] of TRACE_SETTING_NODES) {
    if (settings[key] === undefined) continue;
    const read = chk(out, `was|${key}`);
    if (read === undefined) throw new Error(`the Visual Trace settings of ${user} could not be set (${out.join(' ')})`);
    was[key] = read.startsWith('1') ? read.slice(1) : null;
  }
  return was;
}
