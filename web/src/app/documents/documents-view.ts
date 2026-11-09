/**
 * The Documents page's view model (Story 34.2; EXPERIENCE: Step 3, memory and documents; FR-42): the fixed strings of the page, the reason texts, the size
 * format and the rows the page lists. A framework-free module: it imports nothing and uses only erasable TypeScript syntax, so Node runs it as it is.
 * The page decides nothing (AD-12, AD-21): the list, the state of each document and every refusal are the server's (`GET /v1/documents`, the `document`
 * live event and the route's 400 `bad_document`); the page only shows them.
 *
 * - DOCUMENTS_TEXTS is every fixed string of the page. The UX writes the title, the empty text, the three statuses, the Add button and the removal
 *   question; the reason texts, the Remove button's name and the failure notice of the dialog are ruled (DW-722, the lead's rulings of Story 34.2),
 *   and so are Close and the line for a document that cannot be opened (Story 20.2).
 * - REASON_TEXTS says why a document could not be read, by the reason's code; any code it does not know reads as `failed`.
 * - formatSize writes a size in bytes: whole KB under 1 MB, and from 1 MB MB with one decimal, both rounded up.
 * - rows(server, live, local) is the list: the server's rows overlaid by the live payloads by ref (a payload with `removed` drops its row), the page's
 *   own pending and refused rows first, and the rows of documents the user removed hidden.
 * - ACCEPT is the file picker's accept list.
 * - docRef reads the `doc` query parameter (DOCUMENT_PARAM) of #/documents, which an answer's "Open document" sets (Story 20.2): the page then shows
 *   that document's text, as plain text, from GET /v1/documents/:ref.
 */

/** Every fixed string of the Documents page. The separator in the title is U+00B7 and the ellipsis is U+2026. */
export const DOCUMENTS_TEXTS = {
  title: 'Documents \u00B7 OcuTalon',
  heading: 'Documents',
  add: 'Add documents',
  empty: 'No documents yet. Add a runbook to get cited answers.',
  indexing: 'Indexing\u2026',
  ready: 'Ready',
  refused: "Couldn't read it: {reason}",
  remove: 'Remove',
  removeName: 'Remove {name}',
  question: "Remove '{name}'? Answers will stop citing it.",
  cancel: 'Cancel',
  removeFailed: "Couldn't remove it. Nothing was changed.",
  close: 'Close',
  openFailed: "Couldn't open that document. It may have been removed.",
} as const;

/** The query parameter of #/documents that names the document whose text the page shows. */
export const DOCUMENT_PARAM = 'doc';

/** The ref of the document to open from the query parameter's value: a non-empty value, else "" (nothing to open). */
export function docRef(value: string | null | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

/** Why a file could not be read, by the code of the reason (the route's, and DocumentOps' failed rows, the extraction's codes included). {size} is the file's size, as formatSize writes it. */
export const REASON_TEXTS = {
  wrong_type: "it isn't a Markdown, plain-text, PDF or Word (.docx) file.",
  too_large: 'that file is {size}; the limit is 10 MB.',
  empty: 'the file is empty.',
  unreadable: 'OcuTalon found no text in it.',
  not_built: "this part of OcuTalon isn't built yet.",
  failed: 'something went wrong inside OcuTalon.',
  contents_too_large: 'its text is too long to read.',
  encrypted: "it's protected with a password.",
  damaged: "it's damaged or incomplete.",
  no_text: 'it has no text to read, for example a scanned PDF without a text layer.',
  legacy_doc: "it's an old Word file (.doc); save it as .docx and try again.",
  timed_out: 'reading it took too long.',
} as const;

/** The extensions the file picker offers, as the route accepts them. */
export const ACCEPT = '.md,.markdown,.txt,.pdf,.docx';

/** The size in bytes as text: whole KB (rounded up) under 1 MB, otherwise MB with one decimal (rounded up, and without ".0"). */
export function formatSize(bytes: number): string {
  const size = Number.isFinite(bytes) && bytes > 0 ? bytes : 0;
  if (size < 1048576) {
    return `${Math.ceil(size / 1024)} KB`;
  }
  const tenths = Math.ceil((size * 10) / 1048576);
  const whole = Math.floor(tenths / 10);
  const decimal = tenths % 10;
  return `${whole}${decimal === 0 ? '' : `.${decimal}`} MB`;
}

/** The reason's text for a code (any unknown or empty code reads as `failed`) and a size in bytes. */
export function reasonText(code: string | undefined, size: number): string {
  const known = code !== undefined && Object.prototype.hasOwnProperty.call(REASON_TEXTS, code);
  const text: string = REASON_TEXTS[(known ? code : 'failed') as keyof typeof REASON_TEXTS];
  return text.replace('{size}', () => formatSize(size));
}

/** The status text of a refused row: "Couldn't read it: {reason}". */
export function refusedText(code: string | undefined, size: number): string {
  return DOCUMENTS_TEXTS.refused.replace('{reason}', () => reasonText(code, size));
}

/** What the server and the live event say about one document: the `document` payload (every key optional, as the generated type has them). */
export interface DocumentView {
  ref?: string;
  name?: string;
  addedAt?: string;
  size?: number;
  state?: string;
  reason?: string;
  removed?: boolean;
}

/**
 * A row of the page's own: a file that was given, while its add is in flight (`pending`) or after the route refused it (`refused`, with the
 * reason's code, or "" for a body the route could not read), or a document the user removed (`removed`, which hides its ref). A pending
 * row takes the ref of the 200 answer and shows until the server's or the live row with that ref replaces it, and never again once that
 * document is removed (by the user, or by a live payload with `removed`).
 */
export interface LocalRow {
  id: number;
  kind: 'pending' | 'refused' | 'removed';
  name: string;
  size: number;
  /** The time the file was given, as an ISO time, which orders the page's own rows. */
  at: string;
  /** The ref of the 200 answer for a pending row, and the ref of a removed document. */
  ref?: string;
  /** The code of a refused row's reason; "" for none. */
  reason?: string;
}

/** A row as the page lists it. */
export interface DocumentRow {
  /** Unique among the rows, and stable while the row changes state. */
  key: string;
  /** The document's ref; empty for a row that has none yet (a pending add, a refused file). */
  ref: string;
  name: string;
  addedAt: string;
  size: number;
  state: 'indexing' | 'ready' | 'refused';
  /** The status text: "Indexing\u2026", "Ready" or "Couldn't read it: {reason}". */
  status: string;
  /** True for a row of a document the server holds, which has Remove; a pending add and a refused file have none. */
  removable: boolean;
  /** True for a row of the page's own, which is not yet (or never) the server's. */
  local: boolean;
}

/** The row of a server or live document. */
function documentRow(view: DocumentView): DocumentRow {
  const ref = view.ref ?? '';
  const size = view.size ?? 0;
  const state = view.state === 'ready' ? 'ready' : view.state === 'failed' ? 'refused' : 'indexing';
  return {
    key: `doc:${ref}`,
    ref,
    name: view.name ?? '',
    addedAt: view.addedAt ?? '',
    size,
    state,
    status: state === 'ready' ? DOCUMENTS_TEXTS.ready : state === 'refused' ? refusedText(view.reason, size) : DOCUMENTS_TEXTS.indexing,
    removable: ref !== '',
    local: false,
  };
}

/** The row of one of the page's own entries. */
function localRow(entry: LocalRow): DocumentRow {
  const refused = entry.kind === 'refused';
  return {
    key: `local:${entry.id}`,
    ref: entry.ref ?? '',
    name: entry.name,
    addedAt: entry.at,
    size: entry.size,
    state: refused ? 'refused' : 'indexing',
    status: refused ? refusedText(entry.reason, entry.size) : DOCUMENTS_TEXTS.indexing,
    removable: false,
    local: true,
  };
}

/** Newest first by time; rows of the same time keep the order they were given in. */
function newestFirst(a: DocumentRow, b: DocumentRow): number {
  return a.addedAt < b.addedAt ? 1 : a.addedAt > b.addedAt ? -1 : 0;
}

/**
 * The page's rows. The server's list is overlaid by the live payloads by ref: a payload replaces the row with its ref, or adds one, and one with
 * `removed` takes the row away. The rows of documents the user removed are hidden, and a pending add whose ref the server or the live payloads
 * now hold is replaced by that row; one whose document was removed is gone. The page's own pending and refused rows come first, newest first,
 * then the documents, newest first.
 */
export function rows(server: readonly DocumentView[], live: Readonly<Record<string, DocumentView>>, local: readonly LocalRow[]): DocumentRow[] {
  const hidden = new Set(local.filter((entry) => entry.kind === 'removed').map((entry) => entry.ref ?? ''));
  const byRef = new Map<string, DocumentView>();
  for (const view of server) {
    byRef.set(view.ref ?? '', view);
  }
  for (const view of Object.values(live)) {
    if (view.removed === true) {
      byRef.delete(view.ref ?? '');
      hidden.add(view.ref ?? '');
    } else {
      byRef.set(view.ref ?? '', view);
    }
  }
  const documents = [...byRef.values()].filter((view) => !hidden.has(view.ref ?? '')).map(documentRow).sort(newestFirst);
  const own = local
    .filter((entry) => entry.kind !== 'removed' && !(entry.ref !== undefined && (byRef.has(entry.ref) || hidden.has(entry.ref))))
    .map(localRow)
    .sort(newestFirst);
  return [...own, ...documents];
}
