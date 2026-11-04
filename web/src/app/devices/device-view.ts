/**
 * The simulated device panel's view model (Story 4.5): the fixed strings of the panel, its two tabs and the badge counts. A
 * framework-free module: it imports nothing and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - DEVICE_TEXTS holds the region's name, the two tab names, the label and the badge pattern.
 * - tabName(tab, count) is a tab's accessible name: its name, and with new content "{tab}, {n} new" (EXPERIENCE: a tab's name includes
 *   its count).
 * - otherTab(tab) is the tab an arrow key moves to; with two tabs both arrows wrap to the other one.
 * - newRefs(seen, refs) is the refs that arrived since the last look, which the panel counts on an unselected tab. Content present at
 *   the first look (the snapshot's) is in `seen` from the start and is never new.
 */

/** The device tabs, in order. */
export type DeviceTab = 'phone' | 'mailbox';

/** Every fixed string of the panel. */
export const DEVICE_TEXTS = {
  region: 'Simulated devices',
  phoneTab: 'Simulated phone',
  mailboxTab: 'Simulated mailbox',
  simulated: 'Simulated',
  badge: '{tab}, {n} new',
} as const;

/** The localStorage key that holds the device tab chosen in this browser. */
export const TAB_KEY = 'ocutalon.devices.tab';

/** The value the key holds for the mailbox; any other value, and no value, is the phone. */
export const MAILBOX_FLAG = 'mailbox';

/** The tab's own name. */
export function baseName(tab: DeviceTab): string {
  return tab === 'phone' ? DEVICE_TEXTS.phoneTab : DEVICE_TEXTS.mailboxTab;
}

/** The tab's accessible name: its name, followed by ", {n} new" while it has new content. */
export function tabName(tab: DeviceTab, count: number): string {
  const name = baseName(tab);
  return count > 0 ? DEVICE_TEXTS.badge.replace('{tab}', name).replace('{n}', String(count)) : name;
}

/** The other tab. */
export function otherTab(tab: DeviceTab): DeviceTab {
  return tab === 'phone' ? 'mailbox' : 'phone';
}

/** The refs that are not in `seen`, in order, each once. */
export function newRefs(seen: ReadonlySet<string>, refs: readonly string[]): string[] {
  const fresh: string[] = [];
  for (const ref of refs) {
    if (!seen.has(ref) && !fresh.includes(ref)) {
      fresh.push(ref);
    }
  }
  return fresh;
}
