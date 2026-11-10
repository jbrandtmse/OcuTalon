/**
 * The demo guide's "Other things to try" panel (Story 4.11; EXPERIENCE: Demo guide and controls): its fixed strings, the registry of
 * its items and the filter that picks the items this instance has. A framework-free module: it imports nothing, so Node runs it
 * as it is and the strings test reads it.
 *
 * The catalog is the server's (AD-12): `guide.features` is the list of feature ids that Demo.Features.Present gives, in the guide's
 * payload. The page decides nothing about which epics are merged.
 * - MORE_TO_TRY_TEXTS is the link on the guide's first row, the panel's label and the prompt that the memory item sends.
 * - MORE_TO_TRY_ITEMS is the registry: one entry for each feature id, in the order the panel shows them. `action` names the hand-off
 *   that the button makes (more-to-try.ts): each one uses a control that the page already has.
 * - itemsFor(features) is the registry entries whose id the list holds, in registry order. An id the registry does not know is
 *   ignored, and no list gives none.
 * - inCompactBand, chatFloor and windowBound decide the panel's room: whether the page is in the compact band (the height left after the
 *   banners is under 680px), the least height of the chat's list for that band, and the tallest window that leaves the chat that floor.
 */

/**
 * The link of the guide's first row, the panel's label, the prompt that the memory item sends (the exact text) and each item's label,
 * look-for line and control text. The quotes inside the lines are straight ASCII quotes.
 */
export const MORE_TO_TRY_TEXTS = {
  link: 'More to try',
  label: 'Other things to try',
  rememberPrompt: "Remember that the Results partner's contact is Lee.",
  items: {
    persona: {
      label: 'Change how OcuTalon talks',
      lookFor:
        'In the Persona card, choose Pirate, or Another language and then Spanish, and press Save. Then ask "Is anything wrong right now?" and look for the new style in the replies. The check results under them are written by OcuTalon\'s code, so they stay the same in any style.',
      button: 'Go to the Persona card',
    },
    suspiciousEmail: {
      label: 'Send a suspicious email',
      lookFor:
        'This sends "Sample: suspicious request" to the Simulated mailbox. The email asks OcuTalon to resend every failed order and approve pending requests. Look for its decision and the reasons under it: nothing is resent or approved.',
      button: 'Send the suspicious email',
    },
    rejectFix: {
      label: 'Reject a fix',
      lookFor:
        'This presses Break the feed again. OcuTalon usually notices within a minute. When the fix waits for your approval, press Reject in the chat or on the Simulated phone, and look for "Nothing was changed."',
      button: 'Break it again',
    },
    demoView: {
      label: 'See the page as on your own install',
      lookFor:
        'The demo guide, Break the feed and the Simulated devices are hidden, as on your own install. Turn Demo view back on in the top bar to return.',
      button: 'Show the page without the demo',
    },
    memory: {
      label: 'Ask it to remember something',
      lookFor:
        'This sends "Remember that the Results partner\'s contact is Lee." Later, ask "Who do I call about Results?" and look for the answer it remembered.',
      button: 'Ask it to remember',
    },
    memoryCard: {
      label: 'Pin a memory',
      lookFor:
        'First do "Ask it to remember something". Then open All memories in the Memory card and press Pin on the memory marked Told. Open Pinned to see it: pinned facts are read at the start of each conversation, up to 1,000 tokens.',
      button: 'Go to the Memory card',
    },
    documents: {
      label: 'Ask about a document',
      lookFor:
        'On the Documents page, add a short file, such as a runbook (nothing personal: Visual Trace on the demo is shared). Then ask about it in the chat, and look for the answer that comes from your file.',
      button: 'Open the Documents page',
    },
    heartbeat: {
      label: 'Run a heartbeat check-in',
      lookFor:
        'In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in\'s outcome and its cost in the card.',
      button: 'Go to the Heartbeat checklist card',
    },
  },
} as const;

/** The Break the feed button of the box: the control that item 3 presses, and the one that the guide's focus rule hands focus to. */
export const BREAK_FEED_BUTTON = 'app-break-feed-box app-server-button button';

/** The hand-off that an item's control makes. */
export type MoreToTryAction = 'persona' | 'suspiciousEmail' | 'rejectFix' | 'demoView' | 'memory' | 'memoryCard' | 'documents' | 'heartbeat';

/** One item of the panel: the feature id the server lists, the label, the line saying what to look for, the control's text and its hand-off. */
export interface MoreToTryItem {
  readonly id: string;
  readonly label: string;
  readonly lookFor: string;
  readonly button: string;
  readonly action: MoreToTryAction;
  /** The heading of the panel's group the item belongs to (the More to try groups ruling, 2026-11-10); none until the item declares one. */
  readonly group?: string;
}

/** The items, in the order the panel shows them. */
export const MORE_TO_TRY_ITEMS: readonly MoreToTryItem[] = [
  { id: 'persona', ...MORE_TO_TRY_TEXTS.items.persona, action: 'persona' },
  { id: 'suspiciousEmail', ...MORE_TO_TRY_TEXTS.items.suspiciousEmail, action: 'suspiciousEmail' },
  { id: 'rejectFix', ...MORE_TO_TRY_TEXTS.items.rejectFix, action: 'rejectFix' },
  { id: 'demoView', ...MORE_TO_TRY_TEXTS.items.demoView, action: 'demoView' },
  { id: 'memory', ...MORE_TO_TRY_TEXTS.items.memory, action: 'memory' },
  { id: 'memoryCard', ...MORE_TO_TRY_TEXTS.items.memoryCard, action: 'memoryCard', group: 'Memory and documents' },
  { id: 'documents', ...MORE_TO_TRY_TEXTS.items.documents, action: 'documents' },
  { id: 'heartbeat', ...MORE_TO_TRY_TEXTS.items.heartbeat, action: 'heartbeat' },
];

/** The registry entries whose id the server's list holds, in registry order. Unknown ids are ignored, and no list gives none. */
export function itemsFor(features: readonly string[] | undefined): readonly MoreToTryItem[] {
  if (features === undefined) {
    return [];
  }
  return MORE_TO_TRY_ITEMS.filter((item) => features.includes(item.id));
}

/** The height, in px, left after the banners, under which the page is in the compact band: 680, the height of HEIGHT_QUERIES.compact. */
export const COMPACT_BAND_HEIGHT = 680;

/** The least height, in px, of the chat's list that the open panel leaves it: in the compact band, and from the band's edge up. */
export const CHAT_FLOOR = { compact: 64, tall: 160 } as const;

/**
 * True when the height left after the banners is under the compact band's edge (the Planner, 2026-11-07): the viewport's height less
 * the height of the banners above the guide. With a banner showing, the band therefore starts that much higher.
 */
export function inCompactBand(viewport: number, banners: number): boolean {
  return viewport - banners < COMPACT_BAND_HEIGHT;
}

/** The chat list's floor for the band the page is in. */
export function chatFloor(compact: boolean): number {
  return compact ? CHAT_FLOOR.compact : CHAT_FLOOR.tall;
}

/**
 * The tallest the panel's window may be, in whole px: its height now plus the chat list's height above its floor (a list below the
 * floor takes from it). Both are measured on the page as it is, so the bound follows whatever the rest of the page takes, whatever the fonts.
 */
export function windowBound(panel: number, chat: number, floor: number): number {
  return Math.floor(panel + chat - floor);
}
