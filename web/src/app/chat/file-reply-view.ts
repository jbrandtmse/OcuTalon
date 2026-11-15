/**
 * The controls under the reply to a sent file (Story 25.6; FR-54, FR-73, UX-DR129): the fixed strings of the Add to documents button and the Saved to memory
 * chip, and which of them a turn shows. A framework-free module that uses only erasable TypeScript syntax, so Node runs it as it is. It is loaded only with the
 * file-reply component, a lazy chunk (DW-1282); the reply itself reaches it through a dynamic import.
 *
 * - FILE_REPLY_TEXTS is every fixed string of the controls. "I couldn't read that file: {reason}." is the server's reply text and is not here.
 * - controlsOf(fileRead, savedCaption) says which controls a turn shows: the button for a document that was read and can be added (read 1 and addable 1), and the
 *   chip for a photo whose caption was saved as a memory. A turn with neither shows nothing.
 */

/** Every fixed string of the controls under a file's reply. */
export const FILE_REPLY_TEXTS = {
  addToDocuments: 'Add to documents',
  added: 'Added to your documents.',
  addFailed: "Couldn't add it to your documents. Nothing was changed.",
  savedToMemory: 'Saved to memory',
} as const;

/** The members of a chat.message's fileRead that decide the button. */
export interface FileReadLike {
  read?: number;
  addable?: number;
}

/** The controls a turn shows. */
export interface FileReplyControls {
  add: boolean;
  saved: boolean;
}

/** Which controls the turn shows, from its chat.message's fileRead and caption (an object, or absent). */
export function controlsOf(fileRead: FileReadLike | undefined, savedCaption: object | undefined): FileReplyControls {
  return { add: fileRead !== undefined && fileRead.read === 1 && fileRead.addable === 1, saved: savedCaption !== undefined };
}
