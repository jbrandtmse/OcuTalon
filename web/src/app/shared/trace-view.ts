/**
 * The Visual Trace links' strings and rules (Story 2.13, UX-DR38, UX-DR42, UX-DR128, UX-DR139, UX-DR140). A framework-free
 * module: it imports only types and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - TRACE_TEXTS holds every fixed string of the trace links, the sign-in help and the Visual Trace menu, in ASCII.
 * - needsSignInHelp says whether the sign-in help is still to be shown: never on the online demo, never before the
 *   snapshot has said which it is, and not once it has been seen in this tab's session or switched off for the browser.
 * - conversationUrl gives the link behind "Open my conversation in Visual Trace": the traceUrl of the newest chat.message
 *   that has one, which opens the current day's thread at its newest turn. The page never builds or completes a trace URL.
 */
import type { LiveItem } from '../api/api-types';

/** Every fixed string of the trace links and the Visual Trace menu. */
export const TRACE_TEXTS = {
  trace: 'Trace',
  opensInNewTab: '(opens in a new tab)',
  signInName: 'Open in Visual Trace (shows sign-in help first)',
  signInHeading: 'Sign in to Visual Trace',
  signInText: 'Visual Trace opens in the IRIS Management Portal in a new tab. Sign in with your IRIS account if it asks.',
  openVisualTrace: 'Open Visual Trace',
  dontShow: "Don't show this again",
  menu: 'Visual Trace',
  openConversation: 'Open my conversation in Visual Trace',
} as const;

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
