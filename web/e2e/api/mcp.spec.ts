import { expect, test, type APIRequestContext } from '../support/fixtures';

import { README_ACCOUNT, envelope, signInOverHttp } from '../sign-in/helpers';
import { pointKeys, restoreKeys } from '../support/devices';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { leftovers } from '../support/mcp';

/**
 * Story 21.4, the MCP settings routes over real HTTP, on the stack that test-sign-in.sh seeds. The README account holds OcuTalonAdmin; the LIVE fixture user
 * holds OcuTalonUser only. Every case makes its own `zz` servers and removes them (rows, entry, wallet key and collection) in `finally`. The mock MCP server is the
 * IRIS-side OcuTalon.Test.Mcp.Mock on a loopback port; no real server and no real credential is used.
 *   M1  the LIVE user gets 403 not_admin on all four routes and the README admin gets 200 on the list;
 *   M2  the admin adds a server at the mock with a random secret (200, MESSAGEADDED, no secret in the answer); one chat message lets a runner build; the list then
 *       holds the mock's two tools, unclassified, and the mock's log says that every request of AI Hub's client matched the credential;
 *   M3  classify answers 200 "Saved", the list shows it, and a word that is not a classification is 400 bad_classification;
 *   M4  remove answers 200; the list holds the server no more, and its row, tools, entry, key and collection are gone; an unknown name is 404;
 *   M5  each refused add is 400 bad_mcp_server with its field text, and nothing is made: no row, entry, key or collection;
 *   M6  after M2 to M4, no event log row, message body or audit entry holds the secret (35.3's W9 scan), and neither does any answer.
 * The texts are written out here as the oracle.
 */
const MCP = '/ocutalon/api/v1/settings/mcp';
const NOT_ADMIN = 'Only OcuTalon admins can open settings.';
const ADDED = 'The MCP server was added. Its tools count as risky until an admin classifies them.';
const REMOVED = "The MCP server was removed, so its tools can't be used.";
const BAD_NAME = "An MCP server's name is a letter followed by up to 39 letters, digits or underscores. Nothing was changed.";
const BAD_ADDRESS = "An MCP server's address must start with https:// (or point to this computer, for development). Nothing was changed.";
const QUERY_ADDRESS = "An MCP server's address can't hold a query string (the part after ?). Put a key in Secret instead. Nothing was changed.";
const EXISTS = 'An MCP server with that name already exists. Nothing was changed.';
const EXPANSION = "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.";
const BAD_SECRET = 'Use a secret of up to 4,096 letters, digits and punctuation, with no spaces. Nothing was changed.';
const BAD_CLASSIFICATION = 'A tool is Unclassified, Read-only or Risky. Nothing was changed.';
const NOT_SAVED = "Couldn't save. Nothing was changed.";

interface Listed {
  servers: Array<{ name: string; address: string; status: string; tools: number; unclassified: number; pending: number }>;
  tools: Array<{ server: string; name: string; classification: string; status: string }>;
}

/** A unique tag for the case's names and secrets (letters and digits only: a server name has no hyphen). */
const tag = (): string => `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

/** An admin context signed in as the README account. */
async function admin(request: APIRequestContext): Promise<APIRequestContext> {
  const response = await signInOverHttp(request, README_ACCOUNT.user, README_ACCOUNT.password);
  expect(response.status(), 'the README account signs in').toBeLessThan(400);
  return request;
}

async function list(request: APIRequestContext): Promise<Listed> {
  const response = await request.get(MCP);
  expect(response.status(), await response.text()).toBe(200);
  return (await response.json()) as Listed;
}

/** Removes a server through the route (404 when it is not there), then whatever is left of it by hand. */
async function cleanup(request: APIRequestContext, name: string): Promise<void> {
  await request.delete(`${MCP}/servers/${name}`, { headers: envelope(), data: {} });
  await irisScript(
    [
      `Set n=${quoted(name)},c="OcuTalon_MCP_"_n,f="AI.MCP.OcuTalon_"_n`,
      'If ##class(%ConfigStore.Configuration).Exists(f) Do ##class(%ConfigStore.Configuration).Delete(f)',
      'If ##class(%Wallet.Secret).Exists(c_".Key") Do ##class(%Wallet.KeyValue).Delete(c_".Key")',
      'If ##class(%Wallet.Collection).Exists(c) Do ##class(%Wallet.Collection).Delete(c)',
      'Write !,"CHK|clean|1"',
    ].join('\n'),
  );
}

/** Starts the mock on a loopback port, checking the Authorization header against `Bearer <secret>`; returns the port. */
async function startMock(secret: string): Promise<number> {
  const out = await irisScript(
    [`Set sc=##class(OcuTalon.Test.Mcp.Mock).Start(.port,"","Authorization",${quoted(`Bearer ${secret}`)})`, 'Write !,"CHK|ok|",$System.Status.IsOK(sc)', 'Write !,"CHK|port|",port'].join('\n'),
  );
  if (chk(out, 'ok') !== '1') throw new Error('the mock MCP server did not start');
  return Number(chk(out, 'port'));
}

async function stopMock(port: number): Promise<void> {
  await irisScript(`Do ##class(OcuTalon.Test.Mcp.Mock).Stop(${port}) Do ##class(OcuTalon.Test.Mcp.Mock).Forget(${port}) Write !,"CHK|stopped|1"`);
}

/** What AI Hub's own client (not the probe of OcuTalon's, client iris) sent the mock: its requests, and how many of them carried the right header. */
async function mockRequests(port: number): Promise<{ total: number; matched: number }> {
  const out = await irisScript(
    `Set t=0,m=0,i=##class(OcuTalon.Test.Mcp.Mock).Requests(${port}).%GetIterator() While i.%GetNext(,.r) { If r.client="other" { Set t=t+1 If r.auth="matched" Set m=m+1 } } Write !,"CHK|total|",t Write !,"CHK|matched|",m`,
  );
  return { total: Number(chk(out, 'total') ?? '-1'), matched: Number(chk(out, 'matched') ?? '-1') };
}

test('M1: the LIVE user is 403 on all four routes, and the README admin lists', async ({ request, playwright, baseURL }) => {
  test.setTimeout(120_000);
  const live = await playwright.request.newContext({ baseURL });
  try {
    await admin(request);
    const body = await list(request);
    expect(Object.keys(body).sort(), 'the list has servers and tools').toEqual(['servers', 'tools']);

    const user = fixtureUser('LIVE');
    await signInOverHttp(live, user.user, user.password);
    const wanted = { error: { code: 'not_admin', message: NOT_ADMIN } };
    const calls = [
      await live.get(MCP),
      await live.post(`${MCP}/servers`, { headers: envelope(), data: { name: 'zzlive', address: 'https://127.0.0.1:1/mcp' } }),
      await live.delete(`${MCP}/servers/zzlive`, { headers: envelope(), data: {} }),
      await live.post(`${MCP}/classify`, { headers: envelope(), data: { server: 'zzlive', tool: 'x', classification: 'risky' } }),
    ];
    for (const response of calls) {
      expect(response.status(), `${response.url()} is 403 for the LIVE user`).toBe(403);
      expect(await response.json(), 'not_admin').toEqual(wanted);
    }
    expect((await leftovers('zzlive')).row, 'and the LIVE user made nothing').toBe(0);
  } finally {
    await live.dispose();
  }
});

test('M2 to M4 and M6: an added server reaches a runner with its secret, is classified and removed, and the secret is nowhere', async ({ request }) => {
  test.setTimeout(420_000);
  const name = `zz${tag()}`;
  const secret = `zz-mcp-secret-${tag()}-0123456789`;
  let port = 0;
  let pointed = false;
  try {
    await admin(request);
    const marks = await irisScript('Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(ID) m FROM Ens_Util.Log") Do rs.%Next() Write !,"CHK|m|",+rs.%Get("m")\nWrite !,"CHK|t|",$ZDateTime($ZTimeStamp,3,1,3)');
    const logMark = Number(chk(marks, 'm') ?? '0');
    const started = chk(marks, 't') ?? '';
    port = await startMock(secret);
    await pointKeys();
    pointed = true;

    // M2: the add.
    const address = `http://127.0.0.1:${port}/mcp`;
    const added = await request.post(`${MCP}/servers`, { headers: envelope(), data: { name, address, secret } });
    const addedText = await added.text();
    expect(added.status(), addedText).toBe(200);
    expect(JSON.parse(addedText), 'the answer is the result and the message').toEqual({ result: 'added', message: ADDED });
    expect(addedText, 'the answer holds no secret').not.toContain(secret);
    const found = await leftovers(name);
    expect(found, 'the row, the entry and the wallet key and collection are made').toMatchObject({ row: 1, entry: 1, key: 1, collection: 1 });
    const before = (await list(request)).servers.find((one) => one.name === name);
    expect(before, 'the list holds the server').toMatchObject({ name, address, tools: 0, unclassified: 0, pending: 0 });

    // One chat message lets a runner build, and the build attaches the server (Task 0 e: which runner is recorded in the evidence).
    const sent = await request.post('/ocutalon/api/v1/messages', { headers: envelope(), data: { clientId: `zz-mcp-${tag()}`, text: 'zz hello', fromGuide: false } });
    expect(sent.status(), await sent.text()).toBe(202);
    await expect
      .poll(async () => (await list(request)).tools.filter((tool) => tool.server === name).length, { message: 'a runner build lists the mock\'s two tools', timeout: 180_000, intervals: [3_000] })
      .toBe(2);
    const attached = await list(request);
    expect(attached.tools.filter((tool) => tool.server === name).map((tool) => tool.name).sort(), 'the mock offers zz_delete_ticket and zz_lookup').toEqual(['zz_delete_ticket', 'zz_lookup']);
    expect(attached.tools.filter((tool) => tool.server === name).every((tool) => tool.classification === 'unclassified' && tool.status === 'available'), 'unclassified and available').toBe(true);
    expect(attached.servers.find((one) => one.name === name), 'attached, with two unclassified tools').toMatchObject({ status: 'attached', tools: 2, unclassified: 2 });
    const seen = await mockRequests(port);
    expect(seen.total, 'AI Hub\'s client reached the mock').toBeGreaterThan(0);
    expect(seen.matched, 'and every request carried the credential').toBe(seen.total);
    expect(JSON.stringify(attached), 'the list holds no secret, no wallet reference and no fingerprint').not.toMatch(new RegExp(`${secret}|secret://|fingerprint`, 'i'));

    // M3: classify.
    const saved = await request.post(`${MCP}/classify`, { headers: envelope(), data: { server: name, tool: 'zz_lookup', classification: 'read-only' } });
    expect(saved.status(), await saved.text()).toBe(200);
    expect(await saved.json(), 'Saved').toEqual({ result: 'saved', message: 'Saved' });
    const classified = await list(request);
    expect(classified.tools.find((tool) => tool.server === name && tool.name === 'zz_lookup')?.classification, 'the list shows it').toBe('read-only');
    expect(classified.servers.find((one) => one.name === name)?.unclassified, 'and the count').toBe(1);
    const odd = await request.post(`${MCP}/classify`, { headers: envelope(), data: { server: name, tool: 'zz_lookup', classification: 'trusted' } });
    expect(odd.status(), 'a word that is no classification').toBe(400);
    expect(await odd.json()).toEqual({ error: { code: 'bad_classification', message: BAD_CLASSIFICATION } });
    const lost = await request.post(`${MCP}/classify`, { headers: envelope(), data: { server: name, tool: 'zz_nope', classification: 'risky' } });
    expect(lost.status(), 'a tool that the server does not have').toBe(404);

    // M4: remove.
    const removed = await request.delete(`${MCP}/servers/${name}`, { headers: envelope(), data: {} });
    expect(removed.status(), await removed.text()).toBe(200);
    expect(await removed.json()).toEqual({ result: 'removed', message: REMOVED });
    const after = await list(request);
    expect(after.servers.map((one) => one.name), 'the list holds the server no more').not.toContain(name);
    expect(after.tools.filter((tool) => tool.server === name), 'nor its tools').toEqual([]);
    expect(await leftovers(name), 'its row, tools, entry, key and collection are gone').toEqual({ row: 0, tools: 0, entry: 0, key: 0, collection: 0 });
    const again = await request.delete(`${MCP}/servers/${name}`, { headers: envelope(), data: {} });
    expect(again.status(), 'an unknown name').toBe(404);

    // M6: the secret is in no log, message body, audit entry or answer.
    const needles: Array<[string, string]> = [['the secret', secret], ['the bearer value', `Bearer ${secret}`]];
    const scan = async (label: string, script: string): Promise<void> => {
      for (const [role, needle] of needles) {
        const out = await irisScript([script, `Write !,"CHK|n|",$Length(text,${quoted(needle)})-1`].join('\n'));
        expect(chk(out, 'n'), `${label} holds neither ${role}`).toBe('0');
      }
    };
    await scan('the event log', `Set text="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Text FROM Ens_Util.Log WHERE ID > ?",${logMark}) While rs.%Next() { Set text=text_rs.%Get("Text")_$Char(10) }`);
    await scan(
      'the message bodies',
      ['Set text=""', ...['OcuTalon_Msg_Command.AddMcpServer', 'OcuTalon_Msg_Command.RemoveMcpServer', 'OcuTalon_Msg_Command.ClassifyTool', 'OcuTalon_Msg_Command.ListMcpServers', 'OcuTalon_Msg.CommandResult'].map((table) => `Set text=text_##class(OcuTalon.Test.Web.WebhookTools).Columns(${quoted(table)})`)].join('\n'),
    );
    // OcuTalon's own audit entries (source OcuTalon): IRIS's own entry "Create Configuration" holds the entry's address by design, and never the secret.
    await scan(
      'the audit entries',
      ['New $Namespace', 'Set $Namespace="%SYS"', 'Set text=""', `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT EventData, Description FROM %SYS.Audit WHERE UTCTimeStamp >= ?",${quoted(started)}) While rs.%Next() { Set text=text_rs.%Get("EventData")_rs.%Get("Description")_$Char(10) }`].join('\n'),
    );
  } finally {
    if (port !== 0) await stopMock(port);
    await cleanup(request, name);
    if (pointed) await restoreKeys();
  }
});

test('M5: each refused add is 400 bad_mcp_server with its field text, and nothing is made', async ({ request }) => {
  test.setTimeout(240_000);
  const t = tag();
  const names = [`zzm5a${t}`, `zzm5b${t}`, `zzm5c${t}`, `zzm5d${t}`, `zzm5e${t}`, `zzm5f${t}`, `zzm5g${t}`, `zzm5h${t}`, `zzm5i${t}`, `zzm5dup${t}`];
  const loopback = 'https://127.0.0.1:1/mcp';
  const cases: Array<{ what: string; body: Record<string, unknown>; fields: Record<string, string> }> = [
    { what: 'a non-loopback http address', body: { name: names[0], address: 'http://example.invalid/mcp' }, fields: { address: BAD_ADDRESS } },
    { what: 'a non-loopback http address with a secret (condition B)', body: { name: names[1], address: 'http://example.invalid/mcp', secret: 'zz-secret-0123456789' }, fields: { address: BAD_ADDRESS } },
    { what: 'a query string in the address', body: { name: names[0], address: 'https://127.0.0.1:1/mcp?token=zz' }, fields: { address: QUERY_ADDRESS } },
    { what: 'a fragment in the address, with a secret', body: { name: names[1], address: 'https://127.0.0.1:1/mcp#zz', secret: 'zz-secret-0123456789' }, fields: { address: QUERY_ADDRESS } },
    { what: 'user info in the address', body: { name: names[2], address: 'https://user:pass@127.0.0.1:1/mcp' }, fields: { address: BAD_ADDRESS } },
    { what: 'a setting reference in the name', body: { name: 'zz@{x}', address: loopback }, fields: { name: EXPANSION } },
    { what: 'a setting reference in the address', body: { name: names[3], address: 'https://127.0.0.1:1/@{x}' }, fields: { address: EXPANSION } },
    { what: 'a setting reference in the secret', body: { name: names[4], address: loopback, secret: 'zz-@{x}-secret' }, fields: { secret: EXPANSION } },
    { what: 'a bad name', body: { name: '1bad name', address: loopback }, fields: { name: BAD_NAME } },
    { what: 'a secret that is not a string', body: { name: names[5], address: loopback, secret: 12345 }, fields: { secret: BAD_SECRET } },
    { what: 'a secret over 4,096 characters', body: { name: names[6], address: loopback, secret: 'x'.repeat(4097) }, fields: { secret: BAD_SECRET } },
    { what: 'a secret with a space', body: { name: names[7], address: loopback, secret: 'zz secret' }, fields: { secret: BAD_SECRET } },
    { what: 'a secret with a control character', body: { name: names[8], address: loopback, secret: 'zz\u0007secret' }, fields: { secret: BAD_SECRET } },
  ];
  try {
    await admin(request);
    const before = await list(request);
    for (const one of cases) {
      const response = await request.post(`${MCP}/servers`, { headers: envelope(), data: one.body });
      const text = await response.text();
      expect(response.status(), `${one.what}: ${text}`).toBe(400);
      const body = JSON.parse(text) as { error: { code: string; message: string }; fields: Record<string, string> };
      expect(body.error, `${one.what}: the plain refusal`).toEqual({ code: 'bad_mcp_server', message: NOT_SAVED });
      expect(body.fields, `${one.what}: the field and its text`).toEqual(one.fields);
      if (typeof one.body['secret'] === 'string' && one.body['secret'].length > 4) {
        expect(text, `${one.what}: the answer does not echo the secret`).not.toContain(one.body['secret']);
      }
    }
    for (const name of names.slice(0, 9)) {
      expect(await leftovers(name), `nothing was made for ${name}`).toEqual({ row: 0, tools: 0, entry: 0, key: 0, collection: 0 });
    }
    expect(await list(request), 'and the list is as it was').toEqual(before);

    // An existing name is refused by McpOps, mapped to its field.
    const made = await request.post(`${MCP}/servers`, { headers: envelope(), data: { name: names[9], address: loopback } });
    expect(made.status(), await made.text()).toBe(200);
    const twice = await request.post(`${MCP}/servers`, { headers: envelope(), data: { name: names[9].toUpperCase(), address: loopback } });
    expect(twice.status(), 'a name that exists, in another case').toBe(400);
    const dup = (await twice.json()) as { error: { code: string }; fields: Record<string, string> };
    expect(dup.error.code).toBe('bad_mcp_server');
    expect(dup.fields, 'maps to the name field').toEqual({ name: EXISTS });

    // Bodies of another shape are 400 with no field.
    for (const data of [{}, { name: names[0] }, { name: names[0], address: loopback, extra: 1 }, { name: 5, address: loopback }]) {
      const response = await request.post(`${MCP}/servers`, { headers: envelope(), data });
      expect(response.status(), `a body of another shape: ${JSON.stringify(data)}`).toBe(400);
      expect(((await response.json()) as { fields: unknown }).fields).toEqual({});
    }
  } finally {
    await cleanup(request, names[9]);
    await cleanup(request, names[9].toUpperCase());
  }
});
