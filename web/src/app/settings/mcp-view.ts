/**
 * The Tools and MCP servers section of Settings (Story 21.4; EXPERIENCE: Settings and requests (step 4)): the fixed strings of the section and its view rules, as a
 * framework-free module that imports only types (so Node runs it as it is). The page decides nothing (AD-12): the server judges every name, address and secret and
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
 * - withClassification gives the settings with one tool's classification changed and its server's unclassified count worked out again.
 */
import type { McpSettings } from '../api/api-types';

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
  toolColumns: { tool: 'Tool', server: 'Server', status: 'Status', classification: 'Classification' },
  toolStatus: { available: 'Available', unavailable: 'Unavailable', refused: 'Refused: a built-in tool has this name' },
  noTools: 'No tools yet.',
  noUnclassified: 'No unclassified tools.',
  unclassifiedOnly: 'Unclassified only',
  classificationName: 'Classification of {tool} on {server}',
  classifications: { unclassified: 'Unclassified (counts as risky)', 'read-only': 'Read-only', risky: 'Risky' },
  saved: 'Saved',
} as const;

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
function fieldText(fields: unknown, key: 'name' | 'address' | 'secret'): string {
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

/** The settings with one tool's classification changed and its server's unclassified count worked out again; a tool that is not listed changes nothing. */
export function withClassification(settings: McpSettings, server: string, tool: string, classification: string): McpSettings {
  const tools = settings.tools.map((one) => (one.server === server && one.name === tool ? { ...one, classification } : one));
  const unclassified = tools.filter((one) => one.server === server && one.classification === 'unclassified').length;
  return { servers: settings.servers.map((one) => (one.name === server ? { ...one, unclassified } : one)), tools };
}
