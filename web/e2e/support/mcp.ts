import { chk, irisScript, quoted } from './iris';
import { sessionRef } from './persona';

/**
 * Fixtures of the MCP settings specs (Story 21.4): an MCP server as the settings page lists it, without a Config Store entry or a wallet secret (the rows a
 * runner build leaves), and the checks of what an add or a remove leaves behind. Every name is a `zz` name, and a spec drops what it made in `finally`.
 */

/** A fixture tool: its name and its classification (unclassified, read-only or risky). */
export interface FixtureTool {
  name: string;
  classification?: 'unclassified' | 'read-only' | 'risky';
}

/**
 * Makes the `Mcp.Server` row of an attached server and one `ToolClassification` row for each tool, and `pending` pending `tool_call` approval rows whose
 * ToolSource is the server's toolref (the rows that a removal cancels). Returns the Refs of the approval rows.
 */
export async function seedMcpServer(name: string, tools: FixtureTool[], pending = 0): Promise<string[]> {
  const lines = [
    `Set s=##class(OcuTalon.Mcp.Server).%New() Set s.Name=${quoted(name)},s.CreatedAt=##class(OcuTalon.Data.Time).NowUtc(),s.AttachStatus="attached" Write !,"CHK|server|",$System.Status.IsOK(s.%Save())`,
    ...tools.map(
      (tool) =>
        `Set t=##class(OcuTalon.Mcp.ToolClassification).%New() Set t.Server=${quoted(name)},t.Tool=${quoted(tool.name)},t.Classification=${quoted(tool.classification ?? 'unclassified')} Write !,"CHK|tool|",$System.Status.IsOK(t.%Save())`,
    ),
    ...Array.from(
      { length: pending },
      () =>
        `Set row=##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call","zz_call","{}",##class(OcuTalon.Mcp.Attach).Toolref(${quoted(name)})) Set sc=##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row,"pending",3600,,.ref) Write !,"CHK|ref|",ref`,
    ),
  ];
  const out = await irisScript(lines.join('\n'));
  if (out.filter((line) => line === 'CHK|server|1' || line === 'CHK|tool|1').length !== tools.length + 1) {
    throw new Error(`the fixture server ${name} could not be made (${out.join(' ')})`);
  }
  return out.filter((line) => line.startsWith('CHK|ref|')).map((line) => line.slice('CHK|ref|'.length));
}

/** Removes a fixture server's rows, and the approval rows (whatever their state), the entry, the key and the collection that the server may have. */
export async function dropMcpServer(name: string, refs: string[] = []): Promise<void> {
  const lines = [
    ...refs.map((ref) => `Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ?",${quoted(ref)})`),
    `Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?",${quoted(name)})`,
    `Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Mcp.Server WHERE Name = ?",${quoted(name)})`,
    `Set c="OcuTalon_MCP_"_${quoted(name)},f="AI.MCP.OcuTalon_"_${quoted(name)}`,
    'If ##class(%ConfigStore.Configuration).Exists(f) Do ##class(%ConfigStore.Configuration).Delete(f)',
    'If ##class(%Wallet.Secret).Exists(c_".Key") Do ##class(%Wallet.KeyValue).Delete(c_".Key")',
    'If ##class(%Wallet.Collection).Exists(c) Do ##class(%Wallet.Collection).Delete(c)',
    'Write !,"CHK|dropped|1"',
  ];
  const out = await irisScript(lines.join('\n'));
  if (chk(out, 'dropped') !== '1') throw new Error(`the fixture server ${name} could not be removed (${out.join(' ')})`);
}

/** What a server leaves: its row, its tool rows, its Config Store entry, its wallet key and its wallet collection (each a count or 0 / 1). */
export interface Leftovers {
  row: number;
  tools: number;
  entry: number;
  key: number;
  collection: number;
}

/** The leftovers of a server name. */
export async function leftovers(name: string): Promise<Leftovers> {
  const out = await irisScript(
    [
      `Set n=${quoted(name)},c="OcuTalon_MCP_"_n,f="AI.MCP.OcuTalon_"_n`,
      'Write !,"CHK|row|",##class(OcuTalon.Mcp.Server).NameIndexExists(n)',
      'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?",n) Do rs.%Next() Write !,"CHK|tools|",rs.%GetData(1)',
      'Write !,"CHK|entry|",+##class(%ConfigStore.Configuration).Exists(f)',
      'Write !,"CHK|key|",+##class(%Wallet.Secret).Exists(c_".Key")',
      'Write !,"CHK|collection|",+##class(%Wallet.Collection).Exists(c)',
    ].join('\n'),
  );
  const count = (key: string): number => Number(chk(out, key) ?? '-1');
  return { row: count('row'), tools: count('tools'), entry: count('entry'), key: count('key'), collection: count('collection') };
}

/** The state of an approval row by Ref ("<no row>" when it is gone). */
export async function approvalState(ref: string): Promise<string> {
  const out = await irisScript(`Write !,"CHK|state|",##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(${quoted(ref)},"State")`);
  return chk(out, 'state') ?? '';
}

/** The mark of the saved AI sessions (RunnerFixture.SessionMark) before a case that makes a runner build and answer a chat turn; give it to `dropReadmeTurns`. */
export async function sessionMark(): Promise<string> {
  const lines = await irisScript('Write !,"CHK|mark|",##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()');
  return chk(lines, 'mark') ?? '';
}

/**
 * Removes what a chat turn of the README account leaves, so that the specs that follow it on the same stack (chat.spec C1: the empty chat, frame.spec F1: no
 * recent decision in the rail) find the account as seeded. It waits (up to `waitMs`) until no turn of the account's session is queued or running, so that no
 * late reply or decision lands after the clean-up; then removes the session's turns with the Decision, AgentStep and Usage rows the product made for them
 * (ReminderFixture.RemoveTurns, as persona-approval.spec does), and the AI sessions the turns saved (RunnerFixture.DropSince(mark)). Returns the number of turns
 * the session holds afterwards, which is 0 when the clean-up is complete.
 */
export async function dropReadmeTurns(mark: string, waitMs = 90_000): Promise<number> {
  const ref = await sessionRef();
  const deadline = Date.now() + waitMs;
  for (;;) {
    const lines = await irisScript(
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND State IN ('queued','running')",${quoted(ref)}) Do rs.%Next() Write !,"CHK|busy|",rs.%GetData(1)`,
    );
    const busy = chk(lines, 'busy');
    if (busy === undefined) throw new Error(`the busy-turn count could not be read (${lines.join(' ')})`);
    if (busy === '0') break;
    if (Date.now() > deadline) throw new Error(`a turn of the README session was still queued or running after ${waitMs} ms`);
    await new Promise((resolve) => setTimeout(resolve, 2_000));
  }
  if (!/^\d+$/.test(mark)) throw new Error(`no AI session mark was taken (${mark})`);
  const drop = [`Write !,"CHK|dropped|",$System.Status.IsOK(##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(${mark}))`];
  const lines = await irisScript(
    [`Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(${quoted(ref)})`, ...drop, `Write !,"CHK|left|",##class(OcuTalon.Data.Ownership).Turns(${quoted(ref)},.sc).Count()`].join('\n'),
  );
  if (chk(lines, 'dropped') !== '1') throw new Error(`the AI sessions of the turn could not be dropped (${lines.join(' ')})`);
  return Number(chk(lines, 'left') ?? '-1');
}
