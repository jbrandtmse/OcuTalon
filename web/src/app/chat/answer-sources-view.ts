/**
 * The view model of the sources under an answer (Story 20.2; FR-41, FR-42; U-280): the fixed strings of the chips and their popovers, and the pure
 * functions that turn a chat.message's `citations` and `memories` into chips. A framework-free module: it imports only types and uses only
 * erasable TypeScript syntax, so Node runs it as it is.
 *
 * The page decides nothing (AD-12, U-280): the arrays are the server's, built by code from tool results after the reply filter, and a chip is
 * made from them alone, never from the reply's text. A label states where something came from and never that it was relied on.
 *
 * - citationChips groups the citations by document and section, in the order they first appear, at most MAX_CHIPS chips; a chip has the label
 *   "{document} \u00A7 {section}" (the document alone for a passage under no heading), the accessible name "{document}, section {section}" (no
 *   section sign), and the passages of its group in order.
 * - memoryChips makes one chip for each memory, at most MAX_CHIPS: the chip says "From memory" and its accessible name adds the remembered text,
 *   cut to NAME_CUT characters with the ellipsis U+2026.
 */
import type { Citation, Memory } from '../live/payloads';

/** Every fixed string of the sources row. The section sign is U+00A7, the ellipsis U+2026. */
export const ANSWER_SOURCES_TEXTS = {
  citationLabel: '{document} \u00A7 {section}',
  citationName: '{document}, section {section}',
  group: 'Sources',
  openDocument: 'Open document',
  fromMemory: 'From memory',
  memoryName: 'From memory: {memory}',
  saved: 'Saved {when}',
} as const;

/** The most chips of each kind. */
export const MAX_CHIPS = 5;

/** The most characters of a memory's text in its chip's accessible name. */
export const NAME_CUT = 80;

/** The most lines of a passage that the popover shows. */
export const PASSAGE_LINES = 6;

/** A citation chip: one document and section, with the passages the answer's citations hold for them. */
export interface CitationChip {
  /** Unique among the chips of an answer. */
  key: string;
  documentRef: string;
  document: string;
  /** "" for a passage under no heading. */
  section: string;
  /** The visible text, and the popover's heading: "{document} \u00A7 {section}", or the document alone. */
  label: string;
  /** The accessible name: "{document}, section {section}", or the document alone. */
  name: string;
  passages: readonly string[];
}

/** A memory chip: one remembered text and when it was saved. */
export interface MemoryChip {
  key: string;
  text: string;
  /** An ISO time; "" when the memory has none. */
  savedAt: string;
  /** The visible text, and the popover's heading. */
  label: string;
  /** The accessible name: "From memory: {text}", with the text cut to NAME_CUT characters. */
  name: string;
}

/** The text with each template slot replaced by its value (a function replacement, so that "$" in a value stays as it is). */
function fill(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (whole, name: string) => values[name] ?? whole);
}

/** The label of a citation chip: the document and section, or the document alone when the section is empty. */
export function citationLabel(document: string, section: string): string {
  return section === '' ? document : fill(ANSWER_SOURCES_TEXTS.citationLabel, { document, section });
}

/** The accessible name of a citation chip: never holds the section sign. */
export function citationName(document: string, section: string): string {
  return section === '' ? document : fill(ANSWER_SOURCES_TEXTS.citationName, { document, section });
}

/** A memory's text on one line, cut to NAME_CUT characters (whole characters, never half a pair) with U+2026 when it was longer. */
export function memoryExcerpt(text: string): string {
  const characters = Array.from(text.replace(/\s+/g, ' ').trim());
  return characters.length > NAME_CUT ? `${characters.slice(0, NAME_CUT).join('')}\u2026` : characters.join('');
}

/** The accessible name of a memory chip. */
export function memoryName(text: string): string {
  return fill(ANSWER_SOURCES_TEXTS.memoryName, { memory: memoryExcerpt(text) });
}

/**
 * The citation chips of a chat.message's citations: grouped by document ref and section in first-seen order, each group's passages in the order
 * they came, at most MAX_CHIPS chips. A citation with no document ref or no document name has nothing to name or open, and makes no chip.
 */
export function citationChips(citations: readonly Citation[] | undefined): CitationChip[] {
  const chips: CitationChip[] = [];
  const byGroup = new Map<string, { chip: CitationChip; passages: string[] }>();
  for (const citation of citations ?? []) {
    const documentRef = citation.documentRef ?? '';
    const document = citation.document ?? '';
    if (documentRef === '' || document === '') {
      continue;
    }
    const section = citation.section ?? '';
    const group = JSON.stringify([documentRef, section]);
    let found = byGroup.get(group);
    if (found === undefined) {
      if (chips.length >= MAX_CHIPS) {
        continue;
      }
      const passages: string[] = [];
      const chip: CitationChip = {
        key: `cite:${chips.length}`,
        documentRef,
        document,
        section,
        label: citationLabel(document, section),
        name: citationName(document, section),
        passages,
      };
      found = { chip, passages };
      byGroup.set(group, found);
      chips.push(chip);
    }
    if (citation.passage !== undefined && citation.passage !== '') {
      found.passages.push(citation.passage);
    }
  }
  return chips;
}

/** The memory chips of a chat.message's memories: one for each, in order, at most MAX_CHIPS. A memory with no text makes no chip. */
export function memoryChips(memories: readonly Memory[] | undefined): MemoryChip[] {
  const chips: MemoryChip[] = [];
  for (const memory of memories ?? []) {
    const text = memory.text ?? '';
    if (text === '' || chips.length >= MAX_CHIPS) {
      continue;
    }
    chips.push({
      key: `memory:${chips.length}`,
      text,
      savedAt: memory.savedAt ?? '',
      label: ANSWER_SOURCES_TEXTS.fromMemory,
      name: memoryName(text),
    });
  }
  return chips;
}

/** The "Saved {when}" line of a memory popover, from the time as pageWhen wrote it; "" when there is no time. */
export function savedLine(when: string): string {
  return when === '' ? '' : fill(ANSWER_SOURCES_TEXTS.saved, { when });
}
