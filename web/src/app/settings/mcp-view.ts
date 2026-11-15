/**
 * The Tools and MCP servers section of Settings (Story 21.4; EXPERIENCE: Settings and requests (step 4)): the fixed strings of the section and its view rules, as a
 * framework-free module that imports types and, for the interval words, the rail's intervalText (so Node runs it as it is). The page decides nothing (AD-12): the server judges every name, address and secret and
 * answers each refused field with its text, and the section shows those texts as they come. The secret is write-only: it is typed and sent, cleared once the server
 * has it, and no text of this module holds one.
 * - MCP_TEXTS is every fixed string of the section. The online demo's line is the Message Catalog key settings.mcpOffOnDemo, word for word.
 * - removeQuestion(server, n, m) is the Remove dialog's sentence, in the form that the tool count n (0, 1 or more) and the pending request count m (0, 1 or more) call for.
 * - statusText and toolStatusText turn the server's status words into the section's, classificationName and removeName fill the accessible names of a row.
 * - visibleTools is the tools table's filter ("Unclassified only"); a row that the admin has just classified stays until the section is opened again.
 * - addBody is the body of an add: the name and the address trimmed, and the secret only when one was typed.
 * - mcpOutcome classifies a refused or failed call: 403 is denied (the section shows the page's denied text), 409 not_available is the online demo's (the section shows
 *   its own text), a 400 bad_mcp_server that names a name, an address or a secret text is a field refusal, and every other answer is a form error that carries the
 *   server's own message when it sent one.
 * - withClassification gives the settings with one tool's classification changed and its server's unclassified count worked out again; the sources stay as they were.
 * - changedTools is the tools that get a changed-tool banner (Story 21.9): `changed` exactly true and a status that is not refused, in the given order. Both
 *   members are the server's; skipping a refused tool is the one rule the page applies to them (the server reports `changed` for every status).
 * - toolChangedText fills that banner's sentence, the Message Catalog key settings.toolChangedBanner, word for word.
 * - withoutChange gives the settings with one tool's `changed` set to false, which the section applies once a classification has saved; the sources stay as they were.
 * - Source polls (Story 21.5): canBeSource says whether a tool gets the "Use as a source" control (Read-only and not refused), INTERVAL_CHOICES are the six "Check every"
 *   choices (labelled by the rail's intervalText, the module's one value import: the rail is in the initial bundle already), sourceBody is the body of a save, toolText,
 *   sourceName and removeSourceName fill the cell and the accessible names, and sourceOutcome is mcpOutcome plus the fields that a refused source names.
 */
import type { McpSettings, McpSourceBody, McpSourceRow, McpToolRow } from '../api/api-types';
import { intervalText } from '../rail/rail-view.ts';

/** The three forms of a Remove sentence for a count of pending requests: none, one or more. */
interface RemoveForms {
  none: string;
  one: string;
  more: string;
}

/** Every fixed string of the Tools and MCP servers section. */
export const MCP_TEXTS = {
  offOnDemo: 'MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install.',
  servers: 'Servers',
  tools: 'Tools',
  columns: { server: 'Server', address: 'Address', status: 'Status', tools: 'Tools', unclassified: 'Unclassified' },
  noServers: 'No MCP servers yet.',
  addServer: 'Add server',
  removeButton: 'Remove',
  cancel: 'Cancel',
  status: { attached: 'Connected', unavailable: 'Unavailable', unchecked: 'Not checked yet' },
  statusHelp: "A new server's tools show here once OcuTalon next uses its agents. They count as risky until you classify them.",
  form: {
    name: 'Name',
    address: 'Address',
    secret: 'Secret (optional)',
    secretHelp: 'Sent to the server with every request. It is kept in the IRIS Wallet and never shown again.',
  },
  remove: {
    manyTools: {
      none: 'Remove {server}? Its {n} tools go at once.',
      one: 'Remove {server}? Its {n} tools go at once, and 1 pending approval request for them is cancelled.',
      more: 'Remove {server}? Its {n} tools go at once, and {m} pending approval requests for them are cancelled.',
    } satisfies RemoveForms,
    oneTool: {
      none: 'Remove {server}? Its 1 tool goes at once.',
      one: 'Remove {server}? Its 1 tool goes at once, and 1 pending approval request for it is cancelled.',
      more: 'Remove {server}? Its 1 tool goes at once, and {m} pending approval requests for it are cancelled.',
    } satisfies RemoveForms,
    noTools: {
      none: 'Remove {server}? It has no tools.',
      one: 'Remove {server}? 1 pending approval request for its tools is cancelled.',
      more: 'Remove {server}? {m} pending approval requests for its tools are cancelled.',
    } satisfies RemoveForms,
    name: 'Remove {server}',
  },
  toolColumns: { tool: 'Tool', server: 'Server', status: 'Status', classification: 'Classification', source: 'Source' },
  toolStatus: { available: 'Available', unavailable: 'Unavailable', refused: 'Refused: a built-in tool has this name' },
  noTools: 'No tools yet.',
  noUnclassified: 'No unclassified tools.',
  unclassifiedOnly: 'Unclassified only',
  classificationName: 'Classification of {tool} on {server}',
  classifications: { unclassified: 'Unclassified (counts as risky)', 'read-only': 'Read-only', risky: 'Risky' },
  saved: 'Saved',
  sourceHeading: 'Use as a source',
  sourceHelp: "OcuTalon calls this tool on a schedule and decides on each new result. The source joins your digest's coverage list.",
  sourceName: 'Source name',
  sourceArguments: 'Arguments (JSON)',
  sourceInterval: 'Check every',
  sourceNotReadOnly: 'Only a Read-only tool can be a source.',
  sources: 'Your sources',
  sourceColumns: { source: 'Source', tool: 'Tool', interval: 'Check every' },
  noSources: 'No sources yet.',
  toolOn: '{tool} on {server}',
  sourceButtonName: 'Use {tool} on {server} as a source',
  removeSourceName: 'Remove the source {source}',
  toolChanged: '{tool} on {server} changed its description or inputs, so it is Unclassified again. It counts as risky until it is classified below.',
} as const;

/** The six "Check every" choices in minutes, each with its words, and the one that the form starts on. */
export const INTERVAL_CHOICES: readonly { value: number; label: string }[] = [5, 15, 30, 60, 360, 1440].map((value) => ({ value, label: intervalText(value) }));
export const DEFAULT_INTERVAL = 15;

/** The three classifications in the order that the radiogroup lists them, each with the label of its radio. */
export const CLASSIFICATION_OPTIONS: readonly { value: 'unclassified' | 'read-only' | 'risky'; label: string }[] = [
  { value: 'unclassified', label: MCP_TEXTS.classifications.unclassified },
  { value: 'read-only', label: MCP_TEXTS.classifications['read-only'] },
  { value: 'risky', label: MCP_TEXTS.classifications.risky },
];

/** What a refused or failed MCP settings call means for the section. */
export type McpOutcome =
  | { kind: 'denied' }
  | { kind: 'off' }
  | { kind: 'fields'; name: string; address: string; secret: string }
  | { kind: 'form'; message: string };

/** What a refused or failed source call means: McpOutcome, with the fields that a refused source names in place of an add's. */
export type SourceOutcome = Exclude<McpOutcome, { kind: 'fields' }> | { kind: 'fields'; tool: string; name: string; arguments: string; intervalMinutes: string };

/** The Remove dialog's sentence for a server with `tools` tools and `pending` pending approval requests for them. */
export function removeQuestion(server: string, tools: number, pending: number): string {
  const forms: RemoveForms = tools > 1 ? MCP_TEXTS.remove.manyTools : tools === 1 ? MCP_TEXTS.remove.oneTool : MCP_TEXTS.remove.noTools;
  const template = pending > 1 ? forms.more : pending === 1 ? forms.one : forms.none;
  const values: Record<string, string> = { server, n: String(tools), m: String(pending) };
  return template.replace(/\{(server|n|m)\}/g, (_match, key: string) => values[key]);
}

/** The accessible name of a server's Remove button. */
export function removeName(server: string): string {
  return MCP_TEXTS.remove.name.replace('{server}', () => server);
}

/** The accessible name of a tool's classification radiogroup. */
export function classificationName(tool: string, server: string): string {
  return MCP_TEXTS.classificationName.replace('{tool}', () => tool).replace('{server}', () => server);
}

/** The sentence of a tool's changed-tool banner. */
export function toolChangedText(tool: string, server: string): string {
  return MCP_TEXTS.toolChanged.replace('{tool}', () => tool).replace('{server}', () => server);
}

/** The words for a server's status: attached is Connected, unavailable is Unavailable, and anything else (never checked) is Not checked yet. */
export function statusText(status: string): string {
  return status === 'attached' ? MCP_TEXTS.status.attached : status === 'unavailable' ? MCP_TEXTS.status.unavailable : MCP_TEXTS.status.unchecked;
}

/** The words for a tool's status; a status that the section does not know shows nothing. */
export function toolStatusText(status: string): string {
  return status === 'available' || status === 'unavailable' || status === 'refused' ? MCP_TEXTS.toolStatus[status] : '';
}

/** The key of a tool in a set of rows: its server and name (two servers can offer a tool of one name). */
export function toolKey(server: string, name: string): string {
  return `${server}\n${name}`;
}

/** The tools to list: all of them, or only the unclassified ones plus the rows in `keep` (the keys of tools classified since the section opened). */
export function visibleTools<T extends { server: string; name: string; classification: string }>(
  tools: readonly T[],
  unclassifiedOnly: boolean,
  keep: ReadonlySet<string> = new Set(),
): T[] {
  return unclassifiedOnly ? tools.filter((tool) => tool.classification === 'unclassified' || keep.has(toolKey(tool.server, tool.name))) : [...tools];
}

/** The body of an add: the name and the address trimmed (the server judges them), and the secret only when one was typed. */
export function addBody(name: string, address: string, secret: string): { name: string; address: string; secret?: string } {
  const body = { name: name.trim(), address: address.trim() };
  return secret === '' ? body : { ...body, secret };
}

/** The text of a field in a body's `fields`, or '' when the body names none. */
function fieldText(fields: unknown, key: 'name' | 'address' | 'secret' | 'tool' | 'arguments' | 'intervalMinutes'): string {
  if (fields === null || typeof fields !== 'object') {
    return '';
  }
  const value = (fields as Record<string, unknown>)[key];
  return typeof value === 'string' ? value : '';
}

/** Classifies a refused or failed call from its status and error body. */
export function mcpOutcome(status: number, body: unknown): McpOutcome {
  const sent = body !== null && typeof body === 'object' ? (body as { error?: { code?: unknown; message?: unknown }; fields?: unknown }) : {};
  if (status === 403) {
    return { kind: 'denied' };
  }
  if (status === 409 && sent.error?.code === 'not_available') {
    return { kind: 'off' };
  }
  if (status === 400 && sent.error?.code === 'bad_mcp_server') {
    const name = fieldText(sent.fields, 'name');
    const address = fieldText(sent.fields, 'address');
    const secret = fieldText(sent.fields, 'secret');
    if (name !== '' || address !== '' || secret !== '') {
      return { kind: 'fields', name, address, secret };
    }
  }
  return { kind: 'form', message: typeof sent.error?.message === 'string' ? sent.error.message : '' };
}

/** Whether a tool gets the "Use as a source" control: it is Read-only and no built-in tool has its name. The server judges the rest. */
export function canBeSource(tool: { classification: string; status: string }): boolean {
  return tool.classification === 'read-only' && tool.status !== 'refused';
}

/** The body of a save: the name and the arguments trimmed (the server judges them); the interval is the number that was chosen. */
export function sourceBody(server: string, tool: string, name: string, args: string, intervalMinutes: number): McpSourceBody {
  return { server, tool, name: name.trim(), arguments: args.trim(), intervalMinutes };
}

/** "{tool} on {server}": a source's tool cell. */
export function toolText(tool: string, server: string): string {
  return MCP_TEXTS.toolOn.replace('{tool}', () => tool).replace('{server}', () => server);
}

/** The accessible name of a tool's "Use as a source" button. */
export function sourceName(tool: string, server: string): string {
  return MCP_TEXTS.sourceButtonName.replace('{tool}', () => tool).replace('{server}', () => server);
}

/** The accessible name of a source's Remove button. */
export function removeSourceName(source: McpSourceRow): string {
  return MCP_TEXTS.removeSourceName.replace('{source}', () => source.name);
}

/** Classifies a refused or failed source call: a 400 bad_source that names fields is a field refusal, and every other answer is mcpOutcome's. */
export function sourceOutcome(status: number, body: unknown): SourceOutcome {
  const sent = body !== null && typeof body === 'object' ? (body as { error?: { code?: unknown }; fields?: unknown }) : {};
  if (status === 400 && sent.error?.code === 'bad_source') {
    const tool = fieldText(sent.fields, 'tool');
    const name = fieldText(sent.fields, 'name');
    const args = fieldText(sent.fields, 'arguments');
    const intervalMinutes = fieldText(sent.fields, 'intervalMinutes');
    if (tool !== '' || name !== '' || args !== '' || intervalMinutes !== '') {
      return { kind: 'fields', tool, name, arguments: args, intervalMinutes };
    }
  }
  const outcome = mcpOutcome(status, body);
  return outcome.kind === 'fields' ? { kind: 'form', message: '' } : outcome;
}

/** The settings with one tool's classification changed and its server's unclassified count worked out again; a tool that is not listed changes nothing. */
export function withClassification(settings: McpSettings, server: string, tool: string, classification: string): McpSettings {
  const tools = settings.tools.map((one) => (one.server === server && one.name === tool ? { ...one, classification } : one));
  const unclassified = tools.filter((one) => one.server === server && one.classification === 'unclassified').length;
  return { ...settings, servers: settings.servers.map((one) => (one.name === server ? { ...one, unclassified } : one)), tools };
}

/** The tools that get a changed-tool banner: `changed` exactly true and a status that is not refused, in the given order. */
export function changedTools(tools: readonly McpToolRow[]): McpToolRow[] {
  return tools.filter((tool) => tool.changed === true && tool.status !== 'refused');
}

/** The settings with one tool's `changed` set to false; every other member and row is kept, and a tool that is not listed changes nothing. */
export function withoutChange(settings: McpSettings, server: string, tool: string): McpSettings {
  return { ...settings, tools: settings.tools.map((one) => (one.server === server && one.name === tool ? { ...one, changed: false } : one)) };
}
