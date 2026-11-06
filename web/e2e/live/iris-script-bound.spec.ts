import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { expect, test } from '../support/fixtures';
import { irisScript } from '../support/iris';

/**
 * irisScript gives up on a session that never answers (Story 11.21, e2e/support/bounds.ts): it rejects at its bound with the script's first
 * line in the message, stops the session and does not try again, and a project that sets metadata.irisScriptMs bounds it with no argument.
 * The session is a local shell command (OCUTALON_E2E_IRIS_EXEC), so the spec needs no stack, no browser and no OCUTALON_ variable
 * beyond the one it sets itself.
 */

const SCRIPT = '  Set a=1\nWrite a';
const MESSAGE = 'irisScript: no answer within 0.5 s from the script starting "Set a=1"';

async function withSession<T>(command: string, run: () => Promise<T>): Promise<T> {
  const before = process.env['OCUTALON_E2E_IRIS_EXEC'];
  process.env['OCUTALON_E2E_IRIS_EXEC'] = command;
  try {
    return await run();
  } finally {
    if (before === undefined) delete process.env['OCUTALON_E2E_IRIS_EXEC'];
    else process.env['OCUTALON_E2E_IRIS_EXEC'] = before;
  }
}

test('a session that never answers rejects at the bound, naming the first line, and is not tried again', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'iris-script-bound-'));
  const starts = join(dir, 'starts');
  try {
    await withSession(`echo started >> '${starts}'; exec sleep 30`, async () => {
      await expect(irisScript(SCRIPT, 500)).rejects.toThrow(MESSAGE);
    });
    expect(readFileSync(starts, 'utf8').split('\n').filter(Boolean), 'the session was started once').toHaveLength(1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the project bound applies when the call passes none', async () => {
  const metadata = test.info().project.metadata as Record<string, unknown>;
  const before = metadata['irisScriptMs'];
  metadata['irisScriptMs'] = 500;
  try {
    await withSession('exec sleep 30', async () => {
      await expect(irisScript(SCRIPT)).rejects.toThrow(MESSAGE);
    });
  } finally {
    if (before === undefined) delete metadata['irisScriptMs'];
    else metadata['irisScriptMs'] = before;
  }
});

test('a session that answers inside the bound returns its CHK lines', async () => {
  const lines = await withSession("cat > /dev/null; echo 'CHK|a|1'", () => irisScript(SCRIPT, 5000));
  expect(lines).toEqual(['CHK|a|1']);
});
