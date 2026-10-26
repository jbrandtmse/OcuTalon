import { chk, irisScript, quoted } from './iris';

/**
 * What the simulated device panel's cases (phone/, floor/devices.spec.ts, demo-switch/phone.spec.ts, Story 4.5) add to the fixtures of
 * support/iris.ts: a fixture event of any payload class on the user's own stream, the `mailbox` event that nothing publishes before
 * Story 4.6, and the removal of what real notifications leave on the phone for a session that is no fixture session (the FLOOR
 * session's and README's: Test.Data.Fixture.Clean keeps their phone rows).
 */

/**
 * Publishes one fixture event of the type on the user's own session stream, through Live.Publish, with a payload of the class whose
 * properties `fields` sets (property name to string value), and returns its Seq. Nothing in this tree publishes some of these types
 * yet, so a case does it, as publishCheck does for a check.
 */
export async function publishFixtureEvent(user: string, type: string, payloadClass: string, fields: Record<string, string>): Promise<number> {
  if (!/^[A-Za-z0-9_]+$/.test(user)) throw new Error('a fixture user name is letters, digits and underscore');
  if (!/^[a-z.]+$/.test(type) || !/^[A-Za-z0-9.]+$/.test(payloadClass)) throw new Error('the event type and the payload class are plain names');
  const sets = Object.entries(fields).map(([name, value]) => {
    if (!/^[A-Za-z0-9]+$/.test(name)) throw new Error(`'${name}' is not a property name`);
    return `Set p.${name}=${quoted(value)}`;
  });
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      `Set p=##class(${payloadClass}).%New()`,
      ...sets,
      `Set sc=##class(OcuTalon.Live.Publish).Publish(s.Ref,${quoted(type)},p,.q)`,
      'Write !,"CHK|seq|",q',
    ].join('\n'),
  );
  const seq = Number(chk(lines, 'seq'));
  if (!Number.isInteger(seq) || seq < 1) throw new Error(`the ${type} event could not be published (${lines.join(' ')})`);
  return seq;
}

/** Publishes a fixture `mailbox` event with the ref on the user's own stream (Story 4.6 builds the real publisher) and returns its Seq. */
export function publishMailbox(user: string, ref: string): Promise<number> {
  return publishFixtureEvent(user, 'mailbox', 'OcuTalon.Live.Payload.Mailbox', { Ref: ref, Direction: 'in', Sender: 'zz sender', Subject: 'zz subject', CreatedAt: new Date().toISOString().slice(0, 19) + 'Z' });
}

/**
 * Deletes the user's session's SimMessage rows created at or after `sinceUtc` (a UTC ISO time to the second) and its phone and web
 * Delivery rows recorded from then on, so that a case's notifications do not stay in the next case's phone and chat.
 */
export async function dropPhone(user: string, sinceUtc: string): Promise<void> {
  if (!/^[A-Za-z0-9_]+$/.test(user)) throw new Error('a fixture user name is letters, digits and underscore');
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(sinceUtc)) throw new Error('since is a UTC time like 2026-10-26T10:00:00Z');
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set a=##class(%SQL.Statement).%New()',
      'Set sc1=a.%Prepare("DELETE FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND CreatedAt >= ?")',
      `Set r1=a.%Execute(s.Ref,${quoted(sinceUtc)})`,
      'Set b=##class(%SQL.Statement).%New()',
      'Set sc2=b.%Prepare("DELETE FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel IN (\'phone\', \'web\') AND RecordedAt >= ?")',
      `Set r2=b.%Execute(s.Ref,${quoted(sinceUtc)})`,
      'Write !,"CHK|dropped|",$Select($System.Status.IsOK(sc1)&&$System.Status.IsOK(sc2)&&(r1.%SQLCODE>=0)&&(r2.%SQLCODE>=0):1,1:0)',
    ].join('\n'),
  );
  if (chk(lines, 'dropped') !== '1') throw new Error(`the phone rows could not be removed (${lines.join(' ')})`);
}

/** The number of SimMessage rows of kind phone of the user's session. */
export async function phoneRows(user: string): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set a=##class(%SQL.Statement).%New()',
      'Set sc=a.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = \'phone\'")',
      'Set r=a.%Execute(s.Ref)',
      'Do r.%Next()',
      'Write !,"CHK|rows|",r.%GetData(1)',
    ].join('\n'),
  );
  const count = Number(chk(lines, 'rows'));
  if (!Number.isInteger(count)) throw new Error(`the phone rows could not be counted (${lines.join(' ')})`);
  return count;
}
