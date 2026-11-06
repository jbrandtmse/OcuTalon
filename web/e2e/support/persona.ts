import { README_ACCOUNT } from '../sign-in/helpers';
import { chk, irisScript, quoted } from './iris';

/**
 * The persona specs' setup (Story 40.8's api/persona.spec.ts and Story 40.4's persona-card.spec.ts), on the stack that test-sign-in.sh
 * seeds: the README account's session, its persona keys and its `setting` approval requests, through irisScript.
 */

/** The README account's session Ref, found by its IRIS user (the session row the web attaches is the same). */
export async function sessionRef(): Promise<string> {
  const lines = await irisScript(`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(README_ACCOUNT.user)},.sc)\nWrite !,"CHK|ref|",$Select($IsObject(s):s.Ref,1:"")`);
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`the README account's session could not be found (${lines.join(' ')})`);
  return ref;
}

/** Removes the persona keys of the session. */
export async function forget(ref: string): Promise<void> {
  const lines = await irisScript(`Write !,"CHK|forget|",$SYSTEM.Status.IsOK(##class(OcuTalon.Core.SettingsOps).ForgetPerson(${quoted(ref)}))`);
  if (chk(lines, 'forget') !== '1') throw new Error(`the persona keys could not be removed (${lines.join(' ')})`);
}

/** Sets the state that the defaults assert on: onlineDemo off, and no setting request of the session. */
export async function prepare(ref: string): Promise<void> {
  const lines = await irisScript(
    [
      'Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo","")',
      `Set r=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ? AND Kind = 'setting'",${quoted(ref)})`,
      'Write !,"CHK|prepare|",r.%SQLCODE',
    ].join('\n'),
  );
  const code = chk(lines, 'prepare');
  if (code !== '0' && code !== '100') throw new Error(`the persona's state could not be set (${lines.join(' ')})`);
}
