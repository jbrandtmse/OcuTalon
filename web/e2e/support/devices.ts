import { chk, irisScript, quoted } from './iris';

/**
 * What the simulated device panel's cases (phone/, floor/devices.spec.ts, demo-switch/phone.spec.ts, Story 4.5) add to the fixtures of
 * support/iris.ts: a fixture event of any payload class on the user's own stream, the `mailbox` event (a fixture one, for the cases
 * that must not write on the server), and the removal of what real notifications leave on the phone for a session that is no fixture
 * session (the FLOOR session's and README's: Test.Data.Fixture.Clean keeps their phone rows). Story 4.6 adds the mailbox's: mailRows,
 * dropMail, mailOutcome, turnRows, and pointKeys and restoreKeys, which let Decide answer from the CI mock.
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

/**
 * Publishes a fixture `mailbox` event with the ref on the user's own stream and returns its Seq. By default it is a sent (out) mail
 * from OcuTalon with a subject and a text; `fields` (property name to string value) overrides any of it. It writes no SimMessage row.
 */
export function publishMailbox(user: string, ref: string, fields: Record<string, string> = {}): Promise<number> {
  return publishFixtureEvent(user, 'mailbox', 'OcuTalon.Live.Payload.Mailbox', {
    Ref: ref,
    Direction: 'out',
    Sender: 'OcuTalon',
    Subject: 'zz subject',
    Text: 'zz text',
    CreatedAt: new Date().toISOString().slice(0, 19) + 'Z',
    ...fields,
  });
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
  const raw = chk(lines, 'rows') ?? '';
  if (!/^\d+$/.test(raw)) throw new Error(`the phone rows could not be counted (${lines.join(' ')})`);
  return Number(raw);
}

/** The number of SimMessage rows of kind mailbox of the user's session. */
export async function mailRows(user: string): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set a=##class(%SQL.Statement).%New()',
      'Set sc=a.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = \'mailbox\'")',
      'Set r=a.%Execute(s.Ref)',
      'Do r.%Next()',
      'Write !,"CHK|rows|",r.%GetData(1)',
    ].join('\n'),
  );
  const raw = chk(lines, 'rows') ?? '';
  if (!/^\d+$/.test(raw)) throw new Error(`the mailbox rows could not be counted (${lines.join(' ')})`);
  return Number(raw);
}

/** Deletes the SimMessage rows of kind mailbox of the user's session. */
export async function dropMail(user: string): Promise<void> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set a=##class(%SQL.Statement).%New()',
      'Set sc=a.%Prepare("DELETE FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = \'mailbox\'")',
      'Set r=a.%Execute(s.Ref)',
      'Write !,"CHK|dropped|",$Select($System.Status.IsOK(sc)&&(r.%SQLCODE>=0):1,1:0)',
    ].join('\n'),
  );
  if (chk(lines, 'dropped') !== '1') throw new Error(`the mailbox rows could not be removed (${lines.join(' ')})`);
}

/** What the server holds of an incoming email whose sender is exactly `sender`: whether Decide decided it, its outcome, and the Delivery rows of its decision. */
export interface MailOutcome {
  found: boolean;
  outcome: string;
  deliveries: number;
}

/** Reads the decision of the user's incoming email with this sender from the tables: its outcome and how many Delivery rows name its decision (any channel). */
export async function mailOutcome(user: string, sender: string): Promise<MailOutcome> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set a=##class(%SQL.Statement).%New()',
      'Set sc=a.%Prepare("SELECT TOP 1 ItemId FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = \'mailbox\' AND Direction = \'in\' AND Sender = ? ORDER BY ID DESC")',
      `Set r=a.%Execute(s.Ref,${quoted(sender)})`,
      'Set item="" If r.%Next() Set item=r.%GetData(1)',
      'Set d=$Select(item="":"",1:##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(item,"decide"))',
      'Set n=0',
      'If $IsObject(d) { Set b=##class(%SQL.Statement).%New() Set sc2=b.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE DecisionRef = ?") Set r2=b.%Execute(d.Ref) Do r2.%Next() Set n=r2.%GetData(1) }',
      'Write !,"CHK|mail|",(item\'=""),"|",$Select($IsObject(d):d.Outcome,1:""),"|",n',
    ].join('\n'),
  );
  const [found = '', outcome = '', deliveries = ''] = (chk(lines, 'mail') ?? '').split('|');
  if (found === '' || !/^\d*$/.test(deliveries)) throw new Error(`the email's decision could not be read (${lines.join(' ')})`);
  return { found: found === '1', outcome, deliveries: Number(deliveries || '0') };
}

/** The number of Turn rows of the user's session. */
export async function turnRows(user: string): Promise<number> {
  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      'Set a=##class(%SQL.Statement).%New()',
      'Set sc=a.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?")',
      'Set r=a.%Execute(s.Ref)',
      'Do r.%Next()',
      'Write !,"CHK|rows|",r.%GetData(1)',
    ].join('\n'),
  );
  const raw = chk(lines, 'rows') ?? '';
  if (!/^\d+$/.test(raw)) throw new Error(`the turns could not be counted (${lines.join(' ')})`);
  return Number(raw);
}

/**
 * Points the Config Store entry of each runner at the CI mock key variable and restarts the runners, so that Decide answers from the CI
 * mock (Test.Agent.RunnerFixture.PointKeys, as Test.Demo.GuidePrompts does). Throws unless the call reports success.
 */
export async function pointKeys(): Promise<void> {
  const lines = await irisScript(['Set sc=##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()', 'Write !,"CHK|keys|",$System.Status.IsOK(sc)', 'If $System.Status.IsError(sc) Write !,"CHK|why|",$Translate($System.Status.GetErrorText(sc),$Char(13,10)," ")'].join('\n'));
  if (chk(lines, 'keys') !== '1') throw new Error(`the runners could not be pointed at the CI mock (${lines.join(' ')})`);
}

/** Puts the Config Store entries of the runners back to the placeholder of the Provider step (RunnerFixture.RestoreKeys). Throws unless the call reports success. */
export async function restoreKeys(): Promise<void> {
  const lines = await irisScript(['Set sc=##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()', 'Write !,"CHK|keys|",$System.Status.IsOK(sc)', 'If $System.Status.IsError(sc) Write !,"CHK|why|",$Translate($System.Status.GetErrorText(sc),$Char(13,10)," ")'].join('\n'));
  if (chk(lines, 'keys') !== '1') throw new Error(`the runners' keys could not be restored (${lines.join(' ')})`);
}
