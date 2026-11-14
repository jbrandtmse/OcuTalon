import { chk, irisScript, quoted } from './iris';

/**
 * Fixtures of the memory specs (Story 41.2 api/memory.spec.ts, Story 41.6 memory-card.spec.ts, Story 41.9 api/memory.spec.ts): the Precedent rows, the memory rows and the note rows that a
 * case seeds directly through irisScript, and the reads that check them. Product code writes a precedent only through PrecedentOps; a
 * fixture may save and delete rows itself. Each case removes the rows it seeded by Ref in `finally`.
 */

/** The fields of a precedent row that a case sets; a field left out has the value of the memory routes' spec row. */
export interface PrecedentFields {
  answeredAt?: string;
  /** The seeded row's run Ref: set for an evaluation row (owner eval), empty for a person's row. */
  run?: string;
  channel?: string;
  matchKey?: string;
  summary?: string;
  outcome?: string;
  answer?: string;
  answeredChannel?: string;
}

/** Saves a precedent row of the owner (a session's Ref, or eval with a run) and answers its Ref. */
export async function seedPrecedent(owner: string, fields: PrecedentFields = {}): Promise<string> {
  const lines = await irisScript(
    [
      'Set r=##class(OcuTalon.Data.Precedent).%New()',
      'Set r.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set r.OwnerRef=${quoted(owner)}`,
      `Set r.Channel=${quoted(fields.channel ?? 'mailbox')}`,
      `Set r.MatchKey=${quoted(fields.matchKey ?? 'zz.memoryspec@example.com')}`,
      `Set r.Summary=${quoted(fields.summary ?? 'zz memory spec')}`,
      `Set r.Outcome=${quoted(fields.outcome ?? 'tellnow')}`,
      `Set r.Answer=${quoted(fields.answer ?? 'noise')}`,
      `Set r.AnsweredAt=${quoted(fields.answeredAt ?? '2030-01-01T10:00:00Z')}`,
      `Set r.AnsweredChannel=${quoted(fields.answeredChannel ?? 'phone')}`,
      'Set r.SourceRef=r.Ref',
      `Set r.EvalRunRef=${quoted(fields.run ?? '')}`,
      'Set sc=r.%Save()',
      'Write !,"CHK|ref|",$Select($SYSTEM.Status.IsOK(sc):r.Ref,1:"")',
    ].join('\n'),
  );
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`a precedent row could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** Deletes the precedent row with the Ref, if it is there. */
export async function removePrecedent(ref: string): Promise<void> {
  await irisScript(
    [`Set r=##class(OcuTalon.Data.Precedent).RefIndexOpen(${quoted(ref)})`, 'If $IsObject(r) Do ##class(OcuTalon.Data.Precedent).%DeleteId(r.%Id())', 'Write !,"CHK|removed|1"'].join('\n'),
  );
}

/** 1 when the precedent row with the Ref is there, else 0. */
export async function precedentExists(ref: string): Promise<number> {
  const lines = await irisScript([`Write !,"CHK|exists|",##class(OcuTalon.Data.Precedent).RefIndexExists(${quoted(ref)})`].join('\n'));
  return Number(chk(lines, 'exists') ?? Number.NaN);
}

/** The Ref of the durable session of an IRIS user (Session.ForUser, which makes it on the first call). */
export async function sessionRefOfUser(user: string): Promise<string> {
  const lines = await irisScript(`Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)\nWrite !,"CHK|ref|",$Select($IsObject(s):s.Ref,1:"")`);
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`the session of ${user} could not be found (${lines.join(' ')})`);
  return ref;
}

/**
 * Saves a memory of the session, saved now, through the memory area's own test fixture (Test.Memory.Fixture.Store: the row with the vector that the product's endpoint gives for
 * the text, so that both the list and the search find it) and answers its Ref. Product code writes a memory only through MemoryOps; a fixture may save and delete rows itself.
 */
export async function seedMemory(session: string, text: string, origin = 'tool'): Promise<string> {
  const lines = await irisScript(
    [
      'Set ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set sc=##class(OcuTalon.Test.Memory.Fixture).Store(${quoted(session)},ref,${quoted(text)},##class(OcuTalon.Data.Time).NowUtc(),${quoted(origin)})`,
      'Write !,"CHK|ref|",$Select($SYSTEM.Status.IsOK(sc):ref,1:"")',
      'Write !,"CHK|error|",$Select($SYSTEM.Status.IsOK(sc):"",1:$SYSTEM.Status.GetErrorText(sc))',
    ].join('\n'),
  );
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`a memory could not be seeded (${chk(lines, 'error') ?? lines.join(' ')})`);
  return ref;
}

/** Sets the Source of the memory with the Ref (told, or learned) on its row, as a row that the model saved on its own has it; a fixture may write the row itself. */
export async function setMemorySource(ref: string, source: 'told' | 'learned'): Promise<void> {
  const lines = await irisScript(
    [
      `Set m=##class(OcuTalon.Data.Memory).RefIndexOpen(${quoted(ref)})`,
      `If $IsObject(m) Set m.Source=${quoted(source)} Set sc=m.%Save()`,
      'Write !,"CHK|set|",$Select($IsObject(m):$SYSTEM.Status.IsOK($Get(sc)),1:0)',
    ].join('\n'),
  );
  if (chk(lines, 'set') !== '1') throw new Error(`the source of the memory could not be set (${lines.join(' ')})`);
}

/** Deletes the memory with the Ref, with its vector and keyword entries, if it is there. */
export async function removeMemory(ref: string): Promise<void> {
  await irisScript(
    [`Set m=##class(OcuTalon.Data.Memory).RefIndexOpen(${quoted(ref)})`, 'If $IsObject(m) Do ##class(OcuTalon.Data.Memory).%DeleteId(m.%Id())', 'Write !,"CHK|removed|1"'].join('\n'),
  );
}

/** 1 when the memory with the Ref is there, else 0. */
export async function memoryExists(ref: string): Promise<number> {
  const lines = await irisScript(`Write !,"CHK|exists|",##class(OcuTalon.Data.Memory).RefIndexExists(${quoted(ref)})`);
  return Number(chk(lines, 'exists') ?? Number.NaN);
}

/** The number of memories of the session that are pinned, read through the memory area's own pinned read (a row saved before Story 41.8 is not pinned). */
export async function pinnedCountOf(session: string): Promise<number> {
  const lines = await irisScript(
    [`Set sc=##class(OcuTalon.Memory).Pinned(${quoted(session)},.rows)`, 'Write !,"CHK|pinned|",$Select($SYSTEM.Status.IsOK(sc):rows.%Size(),1:"error")'].join('\n'),
  );
  return Number(chk(lines, 'pinned') ?? Number.NaN);
}

/**
 * Saves a done turn of the session (channel web) with the text and answers its Ref. `createdAtUtc` is a UTC time to the second; it is now
 * when left out. `localTimeUtc` gives the UTC time of a local time of the instance zone.
 */
export async function seedNoteTurn(session: string, text: string, createdAtUtc?: string): Promise<string> {
  const lines = await irisScript(
    [
      'Set t=##class(OcuTalon.Data.Turn).%New()',
      'Set t.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set t.SessionRef=${quoted(session)}`,
      'Set t.State="done"',
      'Set t.Channel="web"',
      createdAtUtc === undefined ? 'Set t.CreatedAt=##class(OcuTalon.Data.Time).NowUtc()' : `Set t.CreatedAt=${quoted(createdAtUtc)}`,
      'Set t.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set t.Text=${quoted(text)}`,
      'Set tsc=t.%Save()',
      'Write !,"CHK|turn|",$Select($SYSTEM.Status.IsOK(tsc):t.Ref,1:"")',
    ].join('\n'),
  );
  const ref = chk(lines, 'turn');
  if (!ref) throw new Error(`the note turn could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** Saves a decide decision of the session (recorded now) with the summary and answers its Ref. */
export async function seedNoteDecision(session: string, summary: string): Promise<string> {
  const lines = await irisScript(
    [
      'Set d=##class(OcuTalon.Bridge.Data.Decision).%New()',
      'Set d.Ref=##class(OcuTalon.Bridge.Ids).NewRef()',
      'Set d.Kind="decide"',
      'Set d.ItemId=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Set d.OwnerRef=${quoted(session)}`,
      `Set d.Summary=${quoted(summary)}`,
      'Set d.Outcome="digest"',
      'Set d.RecordedAt=##class(OcuTalon.Data.Time).NowUtc()',
      'Set dsc=d.%Save()',
      'Write !,"CHK|decision|",$Select($SYSTEM.Status.IsOK(dsc):d.Ref,1:"")',
    ].join('\n'),
  );
  const ref = chk(lines, 'decision');
  if (!ref) throw new Error(`the note decision could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** Deletes the turn and the decision with the Refs, if they are there; an empty or missing Ref stands for a row that was not saved. */
export async function removeNoteRows(rows: { turn?: string; decision?: string }): Promise<void> {
  await irisScript(
    [
      `Set t=##class(OcuTalon.Data.Turn).RefIndexOpen(${quoted(rows.turn ?? '')})`,
      'If $IsObject(t) Do ##class(OcuTalon.Data.Turn).%DeleteId(t.%Id())',
      `Set d=##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(${quoted(rows.decision ?? '')})`,
      'If $IsObject(d) Do ##class(OcuTalon.Bridge.Data.Decision).%DeleteId(d.%Id())',
      'Write !,"CHK|removed|1"',
    ].join('\n'),
  );
}

/**
 * A local time of the instance zone on a day, as a UTC time (Data.Time.FromLocal): `daysAgo` 0 is today and 1 is yesterday in the instance
 * zone, and `time` is HH:MM:SS.
 */
export async function localTimeUtc(daysAgo: 0 | 1, time: string): Promise<string> {
  if (!/^\d{2}:\d{2}:\d{2}$/.test(time)) throw new Error(`${time} is not HH:MM:SS`);
  const lines = await irisScript(
    [
      'Set local=##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc())',
      `Set date=$ZDate($ZDateH($Piece(local,"T",1),3)-${daysAgo},3)`,
      `Write !,"CHK|utc|",##class(OcuTalon.Data.Time).FromLocal(date_"T${time}")`,
    ].join('\n'),
  );
  const utc = chk(lines, 'utc');
  if (!utc) throw new Error(`the local time ${time} could not be read (${lines.join(' ')})`);
  return utc;
}

/** The mock's log mark before a send (Test.Contract.Mock.LogMark). */
export async function logMark(): Promise<string> {
  const lines = await irisScript('Write !,"CHK|mark|",##class(OcuTalon.Test.Contract.Mock).LogMark()');
  const mark = chk(lines, 'mark') ?? '';
  if (!/^\d+$/.test(mark)) throw new Error(`the mock log has no mark (${lines.join(' ')})`);
  return mark;
}

/** What the Triage requests of the marker after the mark carried: how many there were, how many held the precedents opening, and how many held the text. */
export interface TriageRequests {
  count: number;
  withOpening: number;
  withText: number;
}

/**
 * Reads the mock's log after the mark: the requests of POST /v1/messages that carry the marker and no tools (the Triage requests of an item),
 * counted, with those that hold OcuTalon.Agent.Input's PRECEDENTSOPENING and those that hold the text (an ASCII text).
 */
export async function triageRequests(mark: string, marker: string, text: string): Promise<TriageRequests> {
  const lines = await irisScript(
    [
      `Set sc=##class(OcuTalon.Test.Contract.Mock).LogSince(${Number(mark)},.entries)`,
      'Set opening=$Parameter("OcuTalon.Agent.Input","PRECEDENTSOPENING")',
      `Set marker=${quoted(marker)},text=${quoted(text)},n=0,o=0,t=0,i=entries.%GetIterator()`,
      'While i.%GetNext(,.entry) { If (entry.method="POST")&&(entry.path="/v1/messages")&&(entry.marker=marker)&&(entry.request.tools.%Size()=0) { Set n=n+1,json=entry.%ToJSON() Set:$Find(json,opening) o=o+1 Set:$Find(json,text) t=t+1 } }',
      'Write !,"CHK|ok|",$System.Status.IsOK(sc)',
      'Write !,"CHK|n|",n',
      'Write !,"CHK|o|",o',
      'Write !,"CHK|t|",t',
    ].join('\n'),
  );
  if (chk(lines, 'ok') !== '1') throw new Error(`the mock log could not be read (${lines.join(' ')})`);
  return { count: Number(chk(lines, 'n')), withOpening: Number(chk(lines, 'o')), withText: Number(chk(lines, 't')) };
}

/** Waits (bounded) until the item has a Decision of the kind decide, and answers its Ref, or "" when none came in time. */
export async function waitDecideRef(itemId: string, ms = 90_000): Promise<string> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const lines = await irisScript(
      [
        `Set d=##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(${quoted(itemId)},"decide")`,
        'Write !,"CHK|ref|",$Select($IsObject(d):d.Ref,1:"")',
      ].join('\n'),
    );
    const ref = chk(lines, 'ref');
    if (ref) return ref;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  return '';
}

/** Deletes the Decision rows of the items (kinds decide and turn), if they are there. */
export async function removeDecisionsOf(itemIds: string[]): Promise<void> {
  const mine = itemIds.filter((id) => /^[A-Za-z0-9_-]+$/.test(id));
  if (mine.length === 0) return;
  const script = mine.flatMap((id) => [
    `For kind="decide","turn" { If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(${quoted(id)},kind,.did) Do ##class(OcuTalon.Bridge.Data.Decision).%DeleteId(did) }`,
  ]);
  await irisScript([...script, 'Write !,"CHK|removed|1"'].join('\n'));
}
