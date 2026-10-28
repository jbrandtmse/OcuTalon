import { createHash } from 'node:crypto';

import { expect, test, type APIResponse } from '@playwright/test';

import { README_ACCOUNT, envelope, signInOverHttp } from '../sign-in/helpers';
import { chk, irisScript, quoted, setTelegramIncluded } from '../support/iris';

/**
 * Story 10.3, the Rule 3 evidence for the pairing routes over real HTTP, on the stack that test-sign-in.sh seeds (the README account's
 * session). With Telegram not included both routes answer 404; with it included, the Telegram state on and no pause, a POST to the code
 * route answers 200 with a 22-character code and an expiry, and the session's code row holds the SHA-256 hash of that code, in base64url,
 * computed here without the product's code (AD-4); with the state off the code route answers 409 not_available and the unpair route
 * answers 200 {"result":"done"} for a session with nothing paired. The test sets the two server seams through irisScript and puts both
 * back in `finally`, and removes the code row it made, because api.spec.ts expects the defaults.
 */
const PAIRING = '/ocutalon/api/v1/pairing';
const NOT_FOUND = 'OcuTalon has nothing at this address.';
const TELEGRAM_OFF = "Telegram isn't on in this OcuTalon, so no pairing code was made.";
const MARK = 'telegramState';

/** A state-changing call with the whole browser envelope; DELETE carries the body {} as the page's client sends it. */
function call(request: Parameters<typeof signInOverHttp>[0], method: 'POST' | 'DELETE', path: string): Promise<APIResponse> {
  return request.fetch(path, { method, headers: envelope(), data: '{}' });
}

/** The error object of an answer, after checking its status and that it is the API's error shape. */
async function expectError(response: APIResponse, status: number, code: string, message: string): Promise<void> {
  expect(response.status(), await response.text()).toBe(status);
  const body = (await response.json()) as { error: { code: string; message: string } };
  expect(Object.keys(body)).toEqual(['error']);
  expect(body.error).toEqual({ code, message });
}

/** The telegramState mark's raw value ("" when there is none). */
async function readMark(): Promise<string> {
  const lines = await irisScript(`Write !,"CHK|mark|",##class(OcuTalon.Data.StatusMark).Get(${quoted(MARK)})`);
  const value = chk(lines, 'mark');
  if (value === undefined) throw new Error(`the Telegram state could not be read (${lines.join(' ')})`);
  return value;
}

/** Writes the telegramState mark through RecordTelegram, or puts a saved raw value back (an empty value removes the mark). */
async function setState(state: 'on' | 'off'): Promise<void> {
  const lines = await irisScript(`Write !,"CHK|set|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).RecordTelegram(${quoted(state)},"ocutalon_ci_bot"))`);
  if (chk(lines, 'set') !== '1') throw new Error(`the Telegram state could not be set (${lines.join(' ')})`);
}

async function restoreMark(raw: string): Promise<void> {
  const lines = await irisScript(`Write !,"CHK|put|",$SYSTEM.Status.IsOK(##class(OcuTalon.Data.StatusMark).Record(${quoted(MARK)},${quoted(raw)}))`);
  if (chk(lines, 'put') !== '1') throw new Error(`the Telegram state could not be put back (${lines.join(' ')})`);
}

/** The code row with this hash: its session and whether any other column holds the code. "" when there is none. */
async function codeRow(hash: string, code: string): Promise<string> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Data.Pairing).CodeHashIndexOpen(${quoted(hash)})`,
      `Write !,"CHK|row|",$Select($IsObject(r):r.CodeHash_"|"_(r.CodeSessionRef'="")_"|"_(r.SessionRef="")_"|"_(r.ChatId="")_"|"_((r.Ref_r.CodeSessionRef_r.DisplayName_r.CodeExpiresAt)[${quoted(code)}),1:"")`,
    ].join('\n'),
  );
  return chk(lines, 'row') ?? '';
}

async function removeCodeRow(hash: string): Promise<void> {
  await irisScript(`Set r=##class(OcuTalon.Data.Pairing).CodeHashIndexOpen(${quoted(hash)}) If $IsObject(r) Do ##class(OcuTalon.Data.Pairing).%DeleteId(r.%Id())\nWrite !,"CHK|gone|1"`);
}

test('the pairing routes: 404 while Telegram is not included, then the code route and the unpair route with it included', async ({ request }) => {
  await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  const savedMark = await readMark();
  const wasIncluded = await setTelegramIncluded(0);
  let latest = '';
  try {
    await expectError(await call(request, 'POST', `${PAIRING}/code`), 404, 'not_found', NOT_FOUND);
    await expectError(await call(request, 'DELETE', PAIRING), 404, 'not_found', NOT_FOUND);
    await setState('on');
    await expectError(await call(request, 'POST', `${PAIRING}/code`), 404, 'not_found', NOT_FOUND);

    await setTelegramIncluded(1);
    const issued = await call(request, 'POST', `${PAIRING}/code`);
    expect(issued.status(), await issued.text()).toBe(200);
    const body = (await issued.json()) as { code: string; expiresAt: string };
    expect(Object.keys(body)).toEqual(['code', 'expiresAt']);
    expect(body.code, 'a 22-character code of the Ref alphabet').toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(body.expiresAt, 'an expiry in UTC to the second').toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    const ahead = (Date.parse(body.expiresAt) - Date.now()) / 1000;
    expect(ahead, `the code lives 10 minutes: ${ahead} s`).toBeGreaterThan(540);
    expect(ahead).toBeLessThanOrEqual(601);

    const hash = createHash('sha256').update(body.code, 'utf8').digest('base64url');
    latest = hash;
    expect(hash).toHaveLength(43);
    expect(await codeRow(hash, body.code), 'the session holds the hash of the code, a code row without a chat or a session, and nothing holds the code').toBe(`${hash}|1|1|1|0`);

    const second = (await (await call(request, 'POST', `${PAIRING}/code`)).json()) as { code: string };
    expect(second.code, 'a second call makes another code').not.toBe(body.code);
    expect(await codeRow(hash, body.code), 'and replaces the first hash').toBe('');
    const secondHash = createHash('sha256').update(second.code, 'utf8').digest('base64url');
    latest = secondHash;
    expect(await codeRow(secondHash, second.code)).toBe(`${secondHash}|1|1|1|0`);

    const unpaired = await call(request, 'DELETE', PAIRING);
    expect(unpaired.status(), await unpaired.text()).toBe(200);
    expect(await unpaired.json(), 'nothing was paired, and that is no error').toEqual({ result: 'done' });

    await setState('off');
    await expectError(await call(request, 'POST', `${PAIRING}/code`), 409, 'not_available', TELEGRAM_OFF);
    const stillUnpaired = await call(request, 'DELETE', PAIRING);
    expect(stillUnpaired.status()).toBe(200);
    expect(await stillUnpaired.json()).toEqual({ result: 'done' });
  } finally {
    await setTelegramIncluded(wasIncluded);
    await restoreMark(savedMark);
    if (latest !== '') await removeCodeRow(latest);
  }
});
