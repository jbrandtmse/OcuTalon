/**
 * The Visual Trace links' strings and rules (Story 2.13, UX-DR38, UX-DR42, UX-DR128, UX-DR139, UX-DR140). A framework-free
 * module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - TRACE_TEXTS holds every fixed string of the trace links, the sign-in help and the Visual Trace menu, in ASCII except the arrow (U+2197).
 * - needsSignInHelp says whether the sign-in help is still to be shown: never on the online demo, never before the
 *   snapshot has said which it is, and not once it has been seen in this tab's session or switched off for the browser.
 * - signInFor is the sign-in name of a trace link with its own text (Story 4.7): the visible label first (WCAG 2.5.3), then the words of
 *   signInName; arrow is the glyph of a link that opens a new tab, always hidden from assistive technology.
 * - conversationUrl gives the link behind "Open my conversation in Visual Trace": the traceUrl of the newest chat.message
 *   that has one, which opens the current day's thread at its newest turn. The page never builds or completes a trace URL.
 */
import type { LiveItem } from '../api/api-types';

/** Every fixed string of the trace links and the Visual Trace menu. */
export const TRACE_TEXTS = {
  trace: 'Trace',
  opensInNewTab: '(opens in a new tab)',
  signInName: 'Open in Visual Trace (shows sign-in help first)',
  signInFor: '{label} (shows sign-in help first)',
  arrow: '\u2197',
  signInHeading: 'Sign in to Visual Trace',
  signInText: 'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.',
  openVisualTrace: 'Open Visual Trace',
  dontShow: "Don't show this again",
  menu: 'Visual Trace',
  openConversation: 'Open my conversation in Visual Trace',
  conversationNotYet: 'Available after your first message.',
} as const;

/** The text with each {name} replaced by its value. */
export function fillTrace(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (whole, name: string) => values[name] ?? whole);
}

/** The accessible name of a trace link while the sign-in help is needed: signInName for the default text, else signInFor with the link's text. */
export function signInNameOf(text: string): string {
  return text === TRACE_TEXTS.trace ? TRACE_TEXTS.signInName : fillTrace(TRACE_TEXTS.signInFor, { label: text });
}

/** The sessionStorage key that says the help was shown in this tab's session. */
export const TRACE_SEEN_KEY = 'ocutalon.traceHelp.seen';

/** The localStorage key that says "Don't show this again" was pressed in this browser. */
export const TRACE_DONT_SHOW_KEY = 'ocutalon.traceHelp.dontShow';

/** The value both keys hold when their flag is set. */
export const TRACE_FLAG = '1';

/**
 * Whether the sign-in help is still to be shown. onlineDemo is the snapshot's flag, undefined until the snapshot has loaded:
 * the help shows only once the snapshot says the install is local.
 */
export function needsSignInHelp(onlineDemo: boolean | undefined, seen: boolean, dontShow: boolean): boolean {
  return onlineDemo === false && !seen && !dontShow;
}

/** The traceUrl of the newest chat.message of the chat that has one; undefined for an empty chat and for turns with none. */
export function conversationUrl(chat: readonly LiveItem[] | undefined): string | undefined {
  for (let i = (chat?.length ?? 0) - 1; i >= 0; i -= 1) {
    const item = chat?.[i];
    if (item?.type === 'chat.message' && item.payload.traceUrl) {
      return item.payload.traceUrl;
    }
  }
  return undefined;
}
