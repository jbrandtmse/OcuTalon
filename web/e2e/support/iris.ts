import { spawn } from 'node:child_process';

/**
 * What the specs of Story 2.2 need from the throwaway stack that docker/tests/test-sign-in.sh starts: the fixture users it
 * created, and a way to run a line of ObjectScript in the OCUTALON namespace of its IRIS container (the stack publishes no
 * management port). Every variable is read when a helper is called, never at import, so that listing the specs needs none.
 */
function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be set by docker/tests/test-sign-in.sh`);
  return value;
}

/** A fixture user of the sign-in unit: OCUTALON_<kind>_USER and OCUTALON_<kind>_PASSWORD, kind LIVE, SESSION, SIGNIN, CHAT, PANEL or DECISION. */
export function fixtureUser(kind: 'LIVE' | 'SESSION' | 'SIGNIN' | 'CHAT' | 'PANEL' | 'DECISION'): { user: string; password: string } {
  return { user: required(`OCUTALON_${kind}_USER`), password: required(`OCUTALON_${kind}_PASSWORD`) };
}

/** Runs one script in a session of the container and returns whatever it printed. */
function runOnce(script: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', ['exec', '-i', required('OCUTALON_E2E_IRIS_CONTAINER'), 'iris', 'session', 'IRIS', '-U', 'OCUTALON'], {
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

/** Publishes one fixture reminder on the user's own session stream and returns its Seq. */
export async function publishReminder(user: string): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      'Set p=##class(OcuTalon.Live.Payload.Reminder).%New()',
      'Set p.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set p.Text="e2e live reminder"',
      'Set p.State="pending"',
      'Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,"reminder",p,.q)',
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the reminder could not be published (${lines.join(' ')})`);
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

/** The lines that make one Decision row in the variable, for the turn in t and the session in s, and keep its status in bad. */
function decisionLines(variable: string, kind: 'decide' | 'turn', decision: SeedDecision, createdAt: string): string[] {
  const lines = [
    `Set ${variable}=##class(OcuTalon.Bridge.Data.Decision).%New()`,
    `Set ${variable}.Ref=##class(OcuTalon.Bridge.Ids).NewRef()`,
    `Set ${variable}.Kind=${quoted(kind)}`,
    `Set ${variable}.ItemId=t.ItemId`,
    `Set ${variable}.OwnerRef=s.Ref`,
    `Set ${variable}.Model=${quoted(decision.model ?? 'claude-haiku-5-5')}`,
    `Set ${variable}.RecordedAt=${quoted(createdAt)}`,
  ];
  for (const [key, property, type] of DECISION_FIELDS) {
    const value = decision[key];
    if (value === undefined) continue;
    if (type === 'string') lines.push(`Set ${variable}.${property}=${quoted(String(value))}`);
    else if (type === 'boolean') lines.push(`Set ${variable}.${property}=${value ? 1 : 0}`);
    else lines.push(`Set ${variable}.${property}=${numeric(Number(value), key)}`);
  }
  lines.push(`Set sc=${variable}.%Save()`, 'If $System.Status.IsError(sc) Set bad=1');
  return lines;
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
 * way the production's one publisher would (AD-33); without it the turns appear on the next /state. Every value of a turn goes
 * through quoted() or numeric(), and the user name through literal().
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
    lines.push('Set sc=t.%Save()', 'If $System.Status.IsError(sc) Set bad=1', `Write !,"CHK|ref|${i}|",t.Ref,"|",'bad`, `Write !,"CHK|dec|${i}|",dt,"|",dr`);
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

/**
 * Gives BridgeSink an event of the bridge for the user's own session, as the bridge's Decide would after its commit
 * (HostSink.OnEvent in the IRIS job that runs the script, with no bridge context), and checks that it returned OK. The payload is
 * passed as JSON through quoted().
 */
export async function sinkEvent(user: string, type: string, payload: Record<string, unknown>): Promise<void> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`,
      `Set sc=##class(OcuTalon.Core.BridgeSink).OnEvent(${quoted(type)},s.Ref,##class(%DynamicAbstractObject).%FromJSON(${quoted(JSON.stringify(payload))}))`,
      'Write !,"CHK|sink|",$System.Status.IsOK(sc)',
    ].join('\n'),
  );
  if (chk(lines, 'sink') !== '1') throw new Error(`BridgeSink did not return OK for ${type} (${lines.join(' ')})`);
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
