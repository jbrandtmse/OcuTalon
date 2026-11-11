/**
 * The demo guide's "Other things to try" panel (Story 4.11; EXPERIENCE: Demo guide and controls): its fixed strings, the registry of
 * its sixteen items and the filter that picks the items this instance has. A framework-free module: it imports nothing, so Node runs it
 * as it is and the strings test reads it.
 *
 * The catalog is the server's (AD-12): `guide.features` is the list of feature ids that Demo.Features.Present gives, in the guide's
 * payload. The page decides nothing about which epics are merged.
 * - MORE_TO_TRY_TEXTS is the link on the guide's first row, the panel's label and the prompts that the memory item, the reroute item, the partner warning item, the queue watch item and the incident summary item (when there is no resolved incident to close) send.
 * - MORE_TO_TRY_ITEMS is the registry: one entry for each feature id, in the order the panel shows them. `action` names the hand-off
 *   that the button makes (more-to-try.ts): each one uses a control that the page already has.
 * - itemsFor(features) is the registry entries whose id the list holds, in registry order. An id the registry does not know is
 *   ignored, and no list gives none.
 * - MORE_TO_TRY_GROUPS is the panel's group headings in the order shown, and groupsOf(items) turns the items into the panel's sets:
 *   the items with no group first, then each heading in that order, then any other group in order of first appearance.
 * - inCompactBand, chatFloor and windowBound decide the panel's room: whether the page is in the compact band (the height left after the
 *   banners is under 680px), the least height of the chat's list for that band, and the tallest window that leaves the chat that floor.
 */

/**
 * The link of the guide's first row, the panel's label, the prompts that the memory item and the incident summary item send (the exact texts) and each item's label,
 * look-for line and control text. The quotes inside the lines are straight ASCII quotes.
 */
export const MORE_TO_TRY_TEXTS = {
  link: 'More to try',
  label: 'Other things to try',
  rememberPrompt: "Remember that the Results partner's contact is Lee.",
  summaryPrompt: 'Show me the incident summary',
  reroutePrompt: 'Reroute the failed orders to OrdersForReview.',
  partnerPrompt: 'Warn the partner about the delay.',
  queuePrompt: 'Watch the queue backlogs.',
  items: {
    incidentSummary: {
      label: 'Read the incident summary',
      lookFor:
        'This closes the guide\'s resolved incident, as Dismiss on its card does. Look for the incident summary in the chat and on the Simulated phone: what happened and when, the cause and the evidence, each approval, the orders affected and the model cost. Later, ask "Show me the incident summary" to get it again.',
      button: 'Close the incident',
    },
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
    reroute: {
      label: 'Reroute the failed orders',
      lookFor:
        'First do "Reject a fix", so the failed orders are still waiting. This asks OcuTalon in the chat to reroute them to OrdersForReview, the review queue. The approval request shows a dry run: how many orders, one example, and where they go now and where they would go. Approve it, then read the result in the chat and press Trace to see the copies go to OrdersForReview while the originals stay unchanged. On your own install, suspend and resume work the same way.',
      button: 'Ask to reroute',
    },
    partnerWarning: {
      label: 'Warn the partner',
      lookFor:
        'This asks OcuTalon in the chat to warn the partner about an incident\'s delay, so it needs an incident that isn\'t closed: if you closed the guide\'s incident, do "Reject a fix" first. OcuTalon drafts a short notice from the incident\'s counts, times and cause, and it comes as an approval request that shows the exact text and the recipients, simulated contacts. Approve it, then open the Simulated mailbox to read the notice exactly as you approved it. Nothing goes to a real inbox.',
      button: 'Ask for a partner warning',
    },
    queueWatch: {
      label: 'Watch queue backlogs',
      lookFor:
        'This asks OcuTalon in the chat to watch the queue backlogs. Look for the Queue-backlog check under Background checks, with its schedule, last run and result. Every minute it reads the Orders production\'s queues, and when one holds more than 100 messages, or its oldest message has waited over 10 minutes, OcuTalon decides once whether to tell you. On a quiet demo it reads Passed. To stop, ask "Stop watching the queue backlogs."',
      button: 'Ask to watch queues',
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
        'On the Documents page, press Add the sample runbook, or add a short file of your own (nothing personal: Visual Trace on the demo is shared). When it reads Ready, ask in the chat "According to the runbook, what should I do when partner orders fail with a date error?", or ask about your own file, and look for the chip under the answer that names the document and its section.',
      button: 'Open the Documents page',
    },
    heartbeat: {
      label: 'Run a heartbeat check-in',
      lookFor:
        'In the Heartbeat checklist card, write what to check and press Run the heartbeat now. Look for the check-in\'s outcome and its cost in the card.',
      button: 'Go to the Heartbeat checklist card',
    },
    webhooks: {
      label: 'Send an event through a webhook',
      lookFor:
        'In Settings, Channels, create a webhook with a name and a secret of at least 16 characters. Then send it any JSON with POST to the address it shows, with the secret in the X-OcuTalon-Webhook-Secret header. On the History page, filter by the channel Webhook to read OcuTalon\'s decision on the event, with a link to its trace.',
      button: 'Open Channels settings',
    },
    sources: {
      label: 'See where an answer came from',
      lookFor:
        'Under an answer from your documents, press the chip that names the document and section to read the passage, then Open document to see the whole file. Under an answer that recalls something you asked it to remember, press From memory to see what it remembered and when.',
      button: 'Open the Documents page',
    },
    usage: {
      label: 'See tokens and cost',
      lookFor:
        'On the Usage page, choose a range and group by day, agent, channel or model. The tokens and cost come from your chat turns and from the agents\' decisions on your messages, and each day shows its largest model request against the 100,000-token limit. If it reads "No model use in this period.", chat or run the guide first.',
      button: 'Open the Usage page',
    },
    history: {
      label: 'Look back at past decisions',
      lookFor:
        'On the History page, filter the Decisions tab by outcome, channel, date or fallback, and open a decision to read its reasons, with a link to its trace. The Incidents tab lists your incidents with their state and, once an incident has closed, its summary. If it reads "No decisions yet.", run the guide first.',
      button: 'Open the History page',
    },
  },
} as const;

/** The Break the feed button of the box: the control that the Reject a fix item presses, and the one that the guide's focus rule hands focus to. */
export const BREAK_FEED_BUTTON = 'app-break-feed-box app-server-button button';

/**
 * Where the incident summary item finds the Dismiss to press (Story 23.6): the incident cards of the chat, the chip that says a card is resolved, and the card's
 * Dismiss button. The newest resolved card is the last one in the page.
 */
export const INCIDENT_CARD = 'article[data-part="incident"]';
export const RESOLVED_CHIP = '.chip-resolved';
export const DISMISS_BUTTON = 'app-incident-dismiss button';

/** The hand-off that an item's control makes. */
export type MoreToTryAction = 'incidentSummary' | 'persona' | 'suspiciousEmail' | 'rejectFix' | 'reroute' | 'partnerWarning' | 'queueWatch' | 'demoView' | 'memory' | 'memoryCard' | 'documents' | 'heartbeat' | 'webhooks' | 'usage' | 'history';

/**
 * One item of the panel: the feature id the server lists, the label, the line saying what to look for, the control's text and its hand-off,
 * and, optionally, the heading of the group it belongs to (the panel does not render groups yet).
 */
export interface MoreToTryItem {
  readonly id: string;
  readonly label: string;
  readonly lookFor: string;
  readonly button: string;
  readonly action: MoreToTryAction;
  /** The heading of the panel's group the item belongs to (the More to try groups ruling, 2026-11-10); none until the item declares one. */
  readonly group?: string;
}

/** The items, in the order the panel shows them: the registry's length is the count that the README and EXPERIENCE give. */
export const MORE_TO_TRY_ITEMS: readonly MoreToTryItem[] = [
  { id: 'incidentSummary', ...MORE_TO_TRY_TEXTS.items.incidentSummary, action: 'incidentSummary', group: 'Incidents and fixes' },
  { id: 'persona', ...MORE_TO_TRY_TEXTS.items.persona, action: 'persona', group: 'Safety and settings' },
  { id: 'suspiciousEmail', ...MORE_TO_TRY_TEXTS.items.suspiciousEmail, action: 'suspiciousEmail', group: 'Safety and settings' },
  { id: 'rejectFix', ...MORE_TO_TRY_TEXTS.items.rejectFix, action: 'rejectFix', group: 'Incidents and fixes' },
  { id: 'reroute', ...MORE_TO_TRY_TEXTS.items.reroute, action: 'reroute', group: 'Incidents and fixes' },
  { id: 'partnerWarning', ...MORE_TO_TRY_TEXTS.items.partnerWarning, action: 'partnerWarning', group: 'Incidents and fixes' },
  { id: 'queueWatch', ...MORE_TO_TRY_TEXTS.items.queueWatch, action: 'queueWatch', group: 'Incidents and fixes' },
  { id: 'demoView', ...MORE_TO_TRY_TEXTS.items.demoView, action: 'demoView', group: 'Safety and settings' },
  { id: 'memory', ...MORE_TO_TRY_TEXTS.items.memory, action: 'memory', group: 'Memory and documents' },
  { id: 'memoryCard', ...MORE_TO_TRY_TEXTS.items.memoryCard, action: 'memoryCard', group: 'Memory and documents' },
  { id: 'documents', ...MORE_TO_TRY_TEXTS.items.documents, action: 'documents', group: 'Memory and documents' },
  { id: 'heartbeat', ...MORE_TO_TRY_TEXTS.items.heartbeat, action: 'heartbeat', group: 'Safety and settings' },
  { id: 'webhooks', ...MORE_TO_TRY_TEXTS.items.webhooks, action: 'webhooks', group: 'Safety and settings' },
  { id: 'sources', ...MORE_TO_TRY_TEXTS.items.sources, action: 'documents', group: 'Memory and documents' },
  { id: 'usage', ...MORE_TO_TRY_TEXTS.items.usage, action: 'usage', group: 'Usage and history' },
  { id: 'history', ...MORE_TO_TRY_TEXTS.items.history, action: 'history', group: 'Usage and history' },
];

/** The registry entries whose id the server's list holds, in registry order. Unknown ids are ignored, and no list gives none. */
export function itemsFor(features: readonly string[] | undefined): readonly MoreToTryItem[] {
  if (features === undefined) {
    return [];
  }
  return MORE_TO_TRY_ITEMS.filter((item) => features.includes(item.id));
}

/** The panel's group headings, in the order the panel shows them. */
export const MORE_TO_TRY_GROUPS: readonly string[] = ['Incidents and fixes', 'Memory and documents', 'Safety and settings', 'Usage and history'];

/** One set of the panel: its heading (none for the items that declare no group) and its items, in order. */
export interface MoreToTryGroup {
  readonly heading?: string;
  readonly items: readonly MoreToTryItem[];
}

/**
 * The sets the panel shows for these items, in this order: the items with no group (undefined, empty or blank) as one set with no
 * heading; each group of MORE_TO_TRY_GROUPS that has an item; then any other group, in the order its name first appears. Every item
 * appears once and keeps its input order within its set. No items give none, and a group with no item gives no set.
 */
export function groupsOf(items: readonly MoreToTryItem[]): readonly MoreToTryGroup[] {
  const ungrouped: MoreToTryItem[] = [];
  const named = new Map<string, MoreToTryItem[]>();
  for (const item of items) {
    const name = item.group;
    if (name === undefined || name.trim() === '') {
      ungrouped.push(item);
    } else {
      const set = named.get(name);
      if (set === undefined) {
        named.set(name, [item]);
      } else {
        set.push(item);
      }
    }
  }
  const sets: MoreToTryGroup[] = ungrouped.length > 0 ? [{ items: ungrouped }] : [];
  const others = [...named.keys()].filter((name) => !MORE_TO_TRY_GROUPS.includes(name));
  for (const heading of [...MORE_TO_TRY_GROUPS, ...others]) {
    const set = named.get(heading);
    if (set !== undefined) {
      sets.push({ heading, items: set });
    }
  }
  return sets;
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
