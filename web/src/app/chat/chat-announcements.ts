/**
 * What the chat announces (Story 2.12; NFR-25, UX-DR132): a diff of the entries the chat shows against the entries it showed at the
 * last look. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is;
 * the texts and the two ways to read a reply come in through the format.
 *
 * - The first look (no `heard`) announces nothing; it only records the entries. The record holds the current entries, by view key,
 *   with whether each one has landed (a turn's reply is text or a fallback; a card has landed when it is there).
 * - A turn whose reply has landed, and had not at the last look, whether the turn is new or known, gives "OcuTalon replied:" and
 *   the first sentence of the reply as the page shows it.
 * - A tell-now card that is new gives "Tell now:" and the first sentence of its text; a reminder card that is new gives its text.
 * - Nothing else is announced: the user's own messages in any state, Deciding and Working, the seconds, a card that was there
 *   already (updated in place) and a reply that had already landed.
 * - The texts come in the chat's order.
 */
import type { ChatEntryView, ReplyView } from './chat-view';

/** True once a turn's reply has landed: the model's text or a fallback. */
const replyLanded = (reply: ReplyView): reply is Extract<ReplyView, { kind: 'text' | 'fallback' }> => reply.kind === 'text' || reply.kind === 'fallback';

/** True once an entry has landed: a turn whose reply has, or a notice card, which has landed when it is there. The chat panel's New messages button reads it too. */
export const landed = (entry: ChatEntryView): boolean => entry.entry === 'notice' || replyLanded(entry.reply);

/** The entries of the last look, by view key, each with whether it had landed. */
export type ChatHeard = ReadonlyMap<string, boolean>;

/** The texts of the announcements and the reads of a reply, from the real modules (the page) or fakes (a test). */
export interface ChatAnnounceFormat {
  /** CHAT_TEXTS.announceReplied: what is said before a reply's first sentence. */
  announceReplied: string;
  /** CHAT_TEXTS.announceTellNow: what is said before a tell-now card's first sentence. */
  announceTellNow: string;
  /** The plain text of a model reply as the page shows it: its first block, each link as its label. */
  replyText(replyText: string): string;
  /** The sentence a fallback reply shows, from the catalog. */
  fallbackText(catalogKey: string, fallbackReason: string): string;
}

/** The marks that end a sentence, when they are followed by white space or the end. */
const SENTENCE_END = /[.!?\u2026](?=\s|$)/;

/**
 * The first sentence of a text: the text up to its first line break, cut after the first ".", "!", "?" or "\u2026" that is
 * followed by white space or the end (the mark stays), trimmed. Text with no such mark is returned whole, trimmed. So "e.g. this"
 * ends after "e.g.", and an address such as "https://a.b/c" does not end.
 */
export function firstSentence(text: string): string {
  const line = text.trimStart().split(/\r\n|\r|\n/, 1)[0] ?? '';
  const end = SENTENCE_END.exec(line);
  return (end === null ? line : line.slice(0, end.index + 1)).trim();
}

/** The words of an announcement and its sentence, joined by a space; a missing sentence leaves the words alone. */
const said = (words: string, sentence: string): string => (sentence === '' ? words : `${words} ${sentence}`);

/** The texts to announce for the entries, in the chat's order, and the record to give the next look. */
export function chatAnnouncements(
  heard: ChatHeard | undefined,
  entries: readonly ChatEntryView[],
  format: ChatAnnounceFormat,
): { texts: string[]; heard: ChatHeard } {
  const now = new Map<string, boolean>();
  const texts: string[] = [];
  for (const entry of entries) {
    if (entry.entry === 'notice') {
      now.set(entry.key, true);
      if (heard !== undefined && !heard.has(entry.key)) {
        texts.push(entry.kind === 'tellnow' ? said(format.announceTellNow, firstSentence(entry.text)) : entry.text.trim());
      }
      continue;
    }
    const reply = entry.reply;
    now.set(entry.key, landed(entry));
    if (heard !== undefined && replyLanded(reply) && heard.get(entry.key) !== true) {
      const shown = reply.kind === 'text' ? format.replyText(reply.replyText) : format.fallbackText(reply.catalogKey, reply.fallbackReason);
      texts.push(said(format.announceReplied, firstSentence(shown)));
    }
  }
  return { texts, heard: now };
}
