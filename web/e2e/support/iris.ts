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

/** A fixture user of the sign-in unit: OCUTALON_<kind>_USER and OCUTALON_<kind>_PASSWORD, kind LIVE, SESSION, SIGNIN or CHAT. */
export function fixtureUser(kind: 'LIVE' | 'SESSION' | 'SIGNIN' | 'CHAT'): { user: string; password: string } {
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
