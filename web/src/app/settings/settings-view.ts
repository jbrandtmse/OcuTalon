/**
 * The settings page's view model (Story 33.2; EXPERIENCE: Step 2, settings and the daily digest): the fixed strings of the page, the order of its
 * sections, the Check thresholds' fields and the small rules of the page and its forms. A framework-free module: it imports nothing and uses only erasable
 * TypeScript syntax, so Node runs it as it is. The page decides nothing (AD-12): the values and the refusals are the server's (SettingsOps); the
 * form sends what was typed and the server validates every value.
 *
 * - SETTINGS_TEXTS is every fixed string of the page. The strings that EXPERIENCE.md does not write are ruled (U-269 for the unsaved prompt, the
 *   denied view's link, the "not built" line, the threshold labels, the Demo mode texts and the landmark names; U-270 for the Demo step's text).
 * - SETTINGS_SECTIONS is the seven sections in the UX's order, each with its address slug.
 * - sectionSlug turns an address part into a section's slug: an unknown or missing one opens Models.
 * - pageOf says which page an address is: the settings page or the chat.
 * - THRESHOLD_FIELDS is the five fields of Check thresholds with their ranges; bodyOf, textsOf and isDirty are the rules of its form.
 * - stepFailedText is the Demo step's text for the value that was written.
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

/** Which page an address (the part after the hash, such as /settings/budgets?x=1) is. */
export function pageOf(address: string): 'settings' | 'chat' {
  const path = address.replace(/^#/, '').split(/[?#;]/)[0];
  return path === '/settings' || path.startsWith('/settings/') ? 'settings' : 'chat';
}

/** The address of the section, as the router takes it. */
export function sectionPath(slug: string): string[] {
  return ['/settings', slug];
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
