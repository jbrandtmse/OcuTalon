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

/** A fixture user of the sign-in unit: OCUTALON_<kind>_USER and OCUTALON_<kind>_PASSWORD, kind LIVE, SESSION, SIGNIN, CHAT or PANEL. */
export function fixtureUser(kind: 'LIVE' | 'SESSION' | 'SIGNIN' | 'CHAT' | 'PANEL'): { user: string; password: string } {
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
 * A done turn for seedTurns: when it was created (UTC, to the second), its text and reply, and where it came from. A fallback
 * reply carries the catalog key the server answered with and its reason (Turn.ReplyCatalogKey and Turn.FallbackReason); both
 * are empty for a reply of the model's own words.
 */
export interface SeedTurn {
  createdAt: string;
  text: string;
  replyText: string;
  channel?: string;
  fromGuide?: boolean;
  catalogKey?: string;
  fallbackReason?: string;
}

/** What seedTurns made: the Ref of each turn, and with publishing the Seq of its chat.message event, in the order given. */
export interface Seeded {
  refs: string[];
  seqs: number[];
}

/**
 * Writes done turns into the user's own session (Session.ForUser), each with a new Ref and ItemId. With publish, each row's
 * chat.message event (ChatMessage.FromRow) is then published on the session stream, after its save, the way the production's
 * one publisher would (AD-33); without it the turns appear on the next /state. Every value of a turn goes through quoted(),
 * and the user name through literal().
 */
export async function seedTurns(user: string, turns: SeedTurn[], publish = false): Promise<Seeded> {
  const lines = [`Set s=##class(OcuTalon.Data.Session).ForUser(${literal(user)},.sc)`];
  turns.forEach((turn, i) => {
    lines.push(
      'Set t=##class(OcuTalon.Data.Turn).%New()',
      'Set t.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set t.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set t.SessionRef=s.Ref',
      'Set t.State="done"',
      `Set t.CreatedAt=${quoted(turn.createdAt)}`,
      `Set t.Channel=${quoted(turn.channel ?? 'web')}`,
      `Set t.FromGuide=${turn.fromGuide ? 1 : 0}`,
      `Set t.Text=${quoted(turn.text)}`,
      `Set t.ReplyText=${quoted(turn.replyText)}`,
      `Set t.ReplyCatalogKey=${quoted(turn.catalogKey ?? '')}`,
      `Set t.FallbackReason=${quoted(turn.fallbackReason ?? '')}`,
      'Set sc=t.%Save()',
      `Write !,"CHK|ref|${i}|",t.Ref,"|",$System.Status.IsOK(sc)`,
    );
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
  turns.forEach((_turn, i) => {
    const [ref, saved] = (chk(out, `ref|${i}`) ?? '').split('|');
    if (!ref || saved !== '1') throw new Error(`turn ${i} could not be seeded (${out.join(' ')})`);
    refs.push(ref);
    if (publish) {
      const seq = Number(chk(out, `seq|${i}`));
      if (!Number.isInteger(seq) || seq < 1) throw new Error(`turn ${i} could not be published (${out.join(' ')})`);
      seqs.push(seq);
    }
  });
  return { refs, seqs };
}
