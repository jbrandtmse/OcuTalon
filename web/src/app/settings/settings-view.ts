/**
 * The settings page's view model (Story 33.2; EXPERIENCE: Step 2, settings and the daily digest): the fixed strings of the page, the order of its
 * sections, the Check thresholds' fields and the small rules of the page and its forms. A framework-free module: it imports nothing and uses only erasable
 * TypeScript syntax, so Node runs it as it is. The page decides nothing (AD-12): the values and the refusals are the server's (SettingsOps); the
 * form sends what was typed and the server validates every value.
 *
 * - SETTINGS_TEXTS is every fixed string of the page. The strings that EXPERIENCE.md does not write are ruled (U-269 for the unsaved prompt, the
 *   denied view's link, the "not built" line, the threshold labels, the Demo mode texts and the landmark names; U-270 for the Demo step's text).
 *   demoSaved, the Demo mode section's own confirmation, is the text of Story 33.3's AC (DW-699): a saved mode reaches an open chat page only after a reload.
 * - SETTINGS_SECTIONS is the seven sections in the UX's order, each with its address slug.
 * - sectionSlug turns an address part into a section's slug: an unknown or missing one opens Models.
 * - pageOf says which page an address is: the settings page, the Documents page or the chat.
 * - THRESHOLD_FIELDS is the five fields of Check thresholds with their ranges; bodyOf, textsOf and isDirty are the rules of its form.
 * - stepFailedText is the Demo step's text for the value that was written.
 * - The Time zone section (Story 18.2): zoneOptions lists the zones to choose from, and zoneBody is the body of a save.
 * - The Daily digest section (Story 18.2): digestChannelBoxes says which channel boxes show, digestChannelsBody builds the channels of a save from the
 *   boxes and the stored value (a hidden channel keeps its stored state, and the order is always web, phone, telegram), digestBody is the body of a save
 *   and isDigestDirty the rule of its form. The Telegram box shows only while Telegram is included and on or paused (telegramBoxShown).
 * - The Channels section (Story 18.2) is read only: channelsView says which of its views shows for the Telegram block and the Telegram card's view kind.
 */

/** Every fixed string of the settings page. The separator in the title is U+00B7. */
export const SETTINGS_TEXTS = {
  title: 'Settings \u00B7 OcuTalon',
  heading: 'Settings',
  sectionsName: 'Settings sections',
  sections: {
    models: 'Models',
    budgets: 'Budgets',
    channels: 'Channels',
    dailyDigest: 'Daily digest',
    timeZone: 'Time zone',
    checkThresholds: 'Check thresholds',
    demoMode: 'Demo mode',
  },
  notBuilt: "This part of OcuTalon isn't built yet.",
  save: 'Save changes',
  saved: 'Saved. Applies within a minute. Recorded in the audit log.',
  demoSaved: 'Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change.',
  failed: "Couldn't save. Nothing was changed.",
  denied: 'Only OcuTalon admins can open settings.',
  back: 'Back to the chat',
  unsaved: 'You have unsaved changes in this section. Leave without saving?',
  stay: 'Stay',
  leave: 'Leave without saving',
  thresholds: {
    diskFreePercent: 'Disk free space below (%)',
    journalFreePercent: 'Journal free space below (%)',
    licenseUsePercent: 'License use above (%)',
    queueMessages: 'Queue backlog above (messages)',
    queueWaitMinutes: 'Oldest queued message waiting over (minutes)',
  },
  timeZone: {
    label: 'Time zone',
    help: "Message times, reminders, the daily digest and the current time that OcuTalon gives the model use this zone. Times on this page stay in your browser's zone.",
    serverDefault: 'Server default',
  },
  dailyDigest: {
    sendAt: 'Send at',
    help: "In the instance's time zone. Applies from the next digest.",
    sendTo: 'Send to',
    web: 'The web chat',
    phone: 'The simulated phone',
    telegram: 'Telegram',
    sendNow: 'Send my digest now',
    sendNowDone: 'Sending your digest now.',
    sendNowFailed: "Couldn't send your digest. Try again.",
  },
  channels: {
    telegramOn: 'Telegram on',
  },
  on: 'On',
  off: 'Off',
  demoHelp: 'Demo mode adds the demo guide, Break the feed, and the simulated devices.',
  stepFailed: "Demo mode is set to {v}, but the switch didn't finish. OcuTalon tries again at its next start.",
} as const;

/** A section of the page: its address slug and its name in the navigation. */
export interface SettingsSection {
  slug: string;
  label: string;
}

/** The seven sections in the UX's order. */
export const SETTINGS_SECTIONS: readonly SettingsSection[] = [
  { slug: 'models', label: SETTINGS_TEXTS.sections.models },
  { slug: 'budgets', label: SETTINGS_TEXTS.sections.budgets },
  { slug: 'channels', label: SETTINGS_TEXTS.sections.channels },
  { slug: 'daily-digest', label: SETTINGS_TEXTS.sections.dailyDigest },
  { slug: 'time-zone', label: SETTINGS_TEXTS.sections.timeZone },
  { slug: 'check-thresholds', label: SETTINGS_TEXTS.sections.checkThresholds },
  { slug: 'demo-mode', label: SETTINGS_TEXTS.sections.demoMode },
];

/** The slug of the section that an address part names, or models (the first) for an unknown or missing one. */
export function sectionSlug(part: string | null | undefined): string {
  return SETTINGS_SECTIONS.find((section) => section.slug === part)?.slug ?? SETTINGS_SECTIONS[0].slug;
}

/** The name of the section with the slug (models for an unknown slug). */
export function sectionLabel(slug: string): string {
  return SETTINGS_SECTIONS.find((section) => section.slug === slug)?.label ?? SETTINGS_SECTIONS[0].label;
}

/** Which page an address (the part after the hash, such as /settings/budgets?x=1) is: settings, documents (Story 34.2) or the chat. */
export function pageOf(address: string): 'settings' | 'documents' | 'chat' {
  const path = address.replace(/^#/, '').split(/[?#;]/)[0];
  if (path === '/documents') {
    return 'documents';
  }
  return path === '/settings' || path.startsWith('/settings/') ? 'settings' : 'chat';
}

/** The address of the section, as the router takes it. */
export function sectionPath(slug: string): string[] {
  return ['/settings', slug];
}

/**
 * The route matcher of the settings page: #/settings and #/settings/<section> are one route, so that moving between sections keeps the
 * page (its values and the focus of the link pressed) instead of building it again. The section is the parameter `section`.
 */
export function settingsMatch<T extends { path: string }>(segments: T[]): { consumed: T[]; posParams: Record<string, T> } | null {
  if (segments.length < 1 || segments.length > 2 || segments[0].path !== 'settings') {
    return null;
  }
  return { consumed: segments, posParams: segments.length === 2 ? { section: segments[1] } : {} };
}

/** A field of Check thresholds: its name in the API, its label and its range. */
export interface ThresholdField {
  name: ThresholdName;
  label: string;
  min: number;
  max: number;
}

/** The names of the five thresholds, as the API has them. */
export type ThresholdName = 'diskFreePercent' | 'journalFreePercent' | 'licenseUsePercent' | 'queueMessages' | 'queueWaitMinutes';

/** The five fields in the order of the UX: whole numbers, 1 to 100 for the percents and 1 to 1000000 for the counts. */
export const THRESHOLD_FIELDS: readonly ThresholdField[] = [
  { name: 'diskFreePercent', label: SETTINGS_TEXTS.thresholds.diskFreePercent, min: 1, max: 100 },
  { name: 'journalFreePercent', label: SETTINGS_TEXTS.thresholds.journalFreePercent, min: 1, max: 100 },
  { name: 'licenseUsePercent', label: SETTINGS_TEXTS.thresholds.licenseUsePercent, min: 1, max: 100 },
  { name: 'queueMessages', label: SETTINGS_TEXTS.thresholds.queueMessages, min: 1, max: 1000000 },
  { name: 'queueWaitMinutes', label: SETTINGS_TEXTS.thresholds.queueWaitMinutes, min: 1, max: 1000000 },
];

/** The values of the five fields as the form holds them: the typed text. */
export type ThresholdTexts = Record<ThresholdName, string>;

/** The values of the five fields as the API has them. */
export type ThresholdNumbers = Record<ThresholdName, number>;

/** The form's texts for the API's numbers. */
export function textsOf(values: Readonly<ThresholdNumbers>): ThresholdTexts {
  return {
    diskFreePercent: String(values.diskFreePercent),
    journalFreePercent: String(values.journalFreePercent),
    licenseUsePercent: String(values.licenseUsePercent),
    queueMessages: String(values.queueMessages),
    queueWaitMinutes: String(values.queueWaitMinutes),
  };
}

/** The body of a save: a number for every text that is digits (the server judges its range), else the text as typed, which the server refuses. */
export function bodyOf(texts: Readonly<ThresholdTexts>): Record<string, number | string> {
  const body: Record<string, number | string> = {};
  for (const field of THRESHOLD_FIELDS) {
    const typed = texts[field.name].trim();
    body[field.name] = /^[0-9]{1,9}$/.test(typed) ? Number(typed) : typed;
  }
  return body;
}

/** True when the form's texts differ from the saved ones, ignoring the white space around a number. */
export function isDirty(current: Readonly<ThresholdTexts>, saved: Readonly<ThresholdTexts>): boolean {
  return THRESHOLD_FIELDS.some((field) => current[field.name].trim() !== saved[field.name].trim());
}

/** The Demo step's text for the value that was written: on or off in place of {v}. */
export function stepFailedText(on: boolean): string {
  return SETTINGS_TEXTS.stepFailed.replace('{v}', () => (on ? 'on' : 'off'));
}

/** The first of the field names that is in the list, in the form's order: the field that takes focus after a refusal. */
export function firstInError(names: readonly string[], order: readonly string[]): string | undefined {
  return order.find((name) => names.includes(name));
}

/** The zone choices of the Time zone select: the empty "Server default" first, then the stored zone when the browser's list lacks it, then the browser's zones. */
export function zoneOptions(supported: readonly string[], stored: string): { value: string; label: string }[] {
  const listed = supported.includes('UTC') ? [...supported] : [...supported, 'UTC'];
  const zones = stored !== '' && !listed.includes(stored) ? [stored, ...listed] : listed;
  return [{ value: '', label: SETTINGS_TEXTS.timeZone.serverDefault }, ...zones.map((zone) => ({ value: zone, label: zone }))];
}

/** The body of a Time zone save. */
export function zoneBody(zone: string): { InstanceZone: string } {
  return { InstanceZone: zone };
}

/** The digest channels in the order that a save stores them. */
export const DIGEST_CHANNELS = ['web', 'phone', 'telegram'] as const;

/** A digest channel. */
export type DigestChannel = (typeof DIGEST_CHANNELS)[number];

/** True while the Telegram box shows: Telegram is included in the release and its state is on, or it is paused (the bot is in use elsewhere). */
export function telegramBoxShown(telegram: { included: boolean; state: string } | undefined, paused: boolean): boolean {
  return telegram !== undefined && telegram.included && (telegram.state === 'on' || paused);
}

/** The channel boxes that show: the web chat always, the simulated phone only while demo mode is on, Telegram only when telegramShown. */
export function digestChannelBoxes(demoMode: boolean, telegramShown: boolean): DigestChannel[] {
  return DIGEST_CHANNELS.filter((channel) => channel === 'web' || (channel === 'phone' && demoMode) || (channel === 'telegram' && telegramShown));
}

/** The channels that a stored value names, each trimmed and lowercased; a name that is not a digest channel is dropped. */
export function storedChannels(stored: string): DigestChannel[] {
  const named = stored.split(',').map((name) => name.trim().toLowerCase());
  return DIGEST_CHANNELS.filter((channel) => named.includes(channel));
}

/**
 * The channels of a save, in the order web, phone, telegram: a shown box keeps what is checked, and a hidden channel keeps its stored state. With no shown box
 * checked the body names no channel, which the server refuses with the field error, so that a digest is never saved for hidden channels alone.
 */
export function digestChannelsBody(stored: string, shown: readonly DigestChannel[], checked: readonly DigestChannel[]): string {
  if (!shown.some((channel) => checked.includes(channel))) {
    return '';
  }
  const kept = storedChannels(stored);
  return DIGEST_CHANNELS.filter((channel) => (shown.includes(channel) ? checked.includes(channel) : kept.includes(channel))).join(',');
}

/** The body of a Daily digest save. */
export function digestBody(time: string, channels: string): { time: string; channels: string } {
  return { time: time.trim(), channels };
}

/** True when the form's time or channels differ from the saved ones (the channels compared as the channels they name). */
export function isDigestDirty(current: { time: string; channels: string }, saved: { time: string; channels: string }): boolean {
  return current.time.trim() !== saved.time.trim() || storedChannels(current.channels).join(',') !== storedChannels(saved.channels).join(',');
}

/** True when the form differs from the saved values: its time, or a shown box whose check differs from the saved channels (a hidden channel keeps its stored state). */
export function isDigestFormDirty(time: string, checked: readonly DigestChannel[], shown: readonly DigestChannel[], saved: { time: string; channels: string }): boolean {
  const kept = storedChannels(saved.channels);
  return time.trim() !== saved.time.trim() || shown.some((channel) => checked.includes(channel) !== kept.includes(channel));
}

/** Which view the read-only Channels section shows. */
export interface ChannelsView {
  kind: 'hidden' | 'not-set-up' | 'paused' | 'on';
  /** The paused view's "Trying again at {time}" line; empty in the other views. */
  retry: string;
}

/**
 * The Channels section's view of Telegram: nothing when the release does not include it, "not set up" while the Telegram card says so, "paused" while the
 * card is paused, and otherwise on. `cardKind` and `retry` are the kind and the retry line of the Telegram card's view (telegramCardView).
 */
export function channelsView(included: boolean, cardKind: string, retry: string): ChannelsView {
  if (!included) {
    return { kind: 'hidden', retry: '' };
  }
  if (cardKind === 'paused') {
    return { kind: 'paused', retry };
  }
  if (cardKind === 'not-set-up') {
    return { kind: 'not-set-up', retry: '' };
  }
  return { kind: 'on', retry: '' };
}
