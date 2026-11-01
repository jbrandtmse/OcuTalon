import { appendFileSync } from 'node:fs';

/**
 * What the clean-machine rehearsal (release/rehearse.sh, Story 11.11) needs of the demo-path specs, and nothing else: page marks and the
 * choice of the IRIS channel. Both are inert unless the rehearsal asks for them, so every CI browser unit behaves as it always did.
 *
 *   - OCUTALON_E2E_MARKS names a file. Then mark(name) appends the line `<name> <Date.now()>` to it, and markWhen(name, probe, timeoutMs)
 *     waits for the probe and marks. The page clock is `Date.now()` on the machine that drives the browser. A value is never subtracted from a
 *     value of another clock (the rehearsal's server clock is the production message headers), so only two marks of this file are ever
 *     subtracted. With the variable unset, mark writes nothing, and markWhen returns at once and never calls its probe.
 *   - OCUTALON_E2E_IRIS_EXEC holds a shell command that runs an `iris session` for the OCUTALON namespace and reads the script on its standard
 *     input (the rehearsal's `rehearse.sh exec`). Then irisSessionCommand runs that command; with it unset it is today's `docker exec` into the
 *     stack's IRIS container, and the container is looked up only then.
 *
 * The mark names, written by e2e/support/demo-path.ts: step1_sent (just before the guide's Send for step 1 is clicked), step1_decision_seen
 * (the reply's decision strip shows its reason), step1_reply_seen (the reply's text shows), approve_pressed (just before Approve is clicked
 * on the simulated phone) and approval_result_seen (the incident card says "Approved from the simulated phone at"). Story 11.12 adds, written
 * by e2e-rehearsal/tell-now.spec.ts: tellnow_sent (just before the compose form's Send) and tellnow_seen (the notice card and the phone message
 * of the item show, or its row shows another outcome). Erasable TypeScript only: web/scripts/rehearsal-support.test.mjs imports this file as
 * it is.
 */

/** The environment these helpers read (a plain record, so a test passes its own). */
export type Env = Record<string, string | undefined>;

/** The page marks' file, or undefined when marks are off. */
function marksFile(): string | undefined {
  const file = process.env['OCUTALON_E2E_MARKS'];
  return file ? file : undefined;
}

/** True when the rehearsal asked for page marks. */
export function marksOn(): boolean {
  return marksFile() !== undefined;
}

/** Appends `<name> <Date.now()>` to the marks file; a no-op when marks are off. */
export function mark(name: string): void {
  const file = marksFile();
  if (file === undefined) return;
  appendFileSync(file, `${name} ${Date.now()}\n`);
}

/**
 * When marks are on, polls the async probe about every 100 ms until it is true and then marks `name`; on timeout it marks nothing and
 * returns (the rehearsal then reports the missing mark). When marks are off it returns at once and never calls the probe.
 */
export async function markWhen(name: string, probe: () => Promise<boolean>, timeoutMs: number): Promise<void> {
  if (!marksOn()) return;
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    let seen = false;
    try {
      seen = await probe();
    } catch {
      seen = false;
    }
    if (seen) {
      mark(name);
      return;
    }
    if (Date.now() >= deadline) return;
    await new Promise((done) => setTimeout(done, 100));
  }
}

/** The command that runs one `iris session` for the OCUTALON namespace: the rehearsal's exec channel when it is set, else docker exec. */
export function irisSessionCommand(env: Env, container: () => string): { cmd: string; args: string[] } {
  const exec = env['OCUTALON_E2E_IRIS_EXEC'];
  if (exec) return { cmd: 'sh', args: ['-c', exec] };
  return { cmd: 'docker', args: ['exec', '-i', container(), 'iris', 'session', 'IRIS', '-U', 'OCUTALON'] };
}
