/**
 * The chat's file view model (Story 25.3; FR-54, UX-DR129, UX-DR147): the fixed strings of sending a file, the check the page makes before it sends,
 * and which controls the chat shows. A framework-free module that uses only erasable TypeScript syntax, so Node runs it as it is.
 * The page decides nothing about a file's type (AD-12): the server reads the bytes (Core.Files) and the page only pre-checks the size, the emptiness and
 * the extension, so that a 14 MB file is not sent as an 18 MB body.
 *
 * - FILES_TEXTS is every fixed string of sending a file. The reply "I got {name}, but I can't read files yet." is the server's reply text and is not here.
 * - checkFile({name, size}) is '' when the file may be sent, else the code of the first refusal: too_large, empty, wrong_type (by the extension only).
 * - refusalText(code, size) is the sentence for a code, with the size in the words of the Documents page (formatSize).
 * - fileLine(name, size) is the line under a sent file: "{name} U+00B7 {size}".
 * - fileControls(filesReadable, onlineDemo) says whether the composer shows the paperclip and what a drop on the chat does: 'off' on the online demo (the
 *   off text), 'send' while the snapshot says the install can read a file, and 'none' otherwise (the browser's own handling stays).
 */
import { formatSize } from '../documents/documents-view.ts';

/** Every fixed string of sending a file. */
export const FILES_TEXTS = {
  send: 'Send a file',
  tooLarge: 'That file is {size}; the limit is 10 MB.',
  unreadable: "I couldn't read that file: {reason}.",
  reasons: {
    wrong_type: "it isn't a PDF, Word (.docx), JPEG or PNG file",
    empty: 'the file is empty',
  },
  offOnDemo: 'Sending files is off on the online demo. It works on your own install.',
  notSent: 'File not sent',
} as const;

/** The file picker's accept list: the extensions the server reads. */
export const ACCEPT_FILES = '.pdf,.docx,.jpg,.jpeg,.png';

/** The largest file, in bytes: 10 MB, as the server's limit. */
export const FILE_MAX = 10485760;

/** The extensions (lower case, with the dot) that name an accepted type. */
const EXTENSIONS = ['.pdf', '.docx', '.jpg', '.jpeg', '.png'];

/** Why a file is refused: the codes of the server's bad_file reasons. */
export type FileRefusalCode = 'too_large' | 'empty' | 'wrong_type';

/** '' when the file may be sent, else the first refusal: its size, then no bytes, then its extension. */
export function checkFile(file: { name: string; size: number }): '' | FileRefusalCode {
  if (file.size > FILE_MAX) {
    return 'too_large';
  }
  if (file.size === 0) {
    return 'empty';
  }
  const name = file.name.trim();
  const dot = name.lastIndexOf('.');
  return dot >= 0 && EXTENSIONS.includes(name.slice(dot).toLowerCase()) ? '' : 'wrong_type';
}

/** The sentence for a refusal code and the file's size in bytes; any code but too_large and empty reads as wrong_type. */
export function refusalText(code: string, size: number): string {
  if (code === 'too_large') {
    return FILES_TEXTS.tooLarge.replace('{size}', () => formatSize(size));
  }
  const reason = code === 'empty' ? FILES_TEXTS.reasons.empty : FILES_TEXTS.reasons.wrong_type;
  return FILES_TEXTS.unreadable.replace('{reason}', () => reason);
}

/** The line under a sent file: its name, then its size, joined by the middle dot (U+00B7). The name is data, to be shown as text. */
export function fileLine(name: string, size: number): string {
  return `${name} \u00B7 ${formatSize(size)}`;
}

/** What the chat shows for files: the paperclip, and what a drop on the chat does. */
export interface FileControls {
  paperclip: boolean;
  drop: 'off' | 'send' | 'none';
}

/** The paperclip shows only while the install can read a file and it is not the online demo; a drop is refused on the demo, taken while files can be read, and otherwise left to the browser. */
export function fileControls(filesReadable: boolean, onlineDemo: boolean): FileControls {
  return { paperclip: filesReadable && !onlineDemo, drop: onlineDemo ? 'off' : filesReadable ? 'send' : 'none' };
}
