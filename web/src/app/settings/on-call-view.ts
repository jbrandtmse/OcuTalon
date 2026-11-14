/**
 * The On call section's rules (Story 36.4; EXPERIENCE: Settings (step 5)): a framework-free module that imports only types and uses only erasable TypeScript
 * syntax, so Node runs it as it is. The page decides nothing (AD-12): the server validates every value and names the fields it refuses. This module only
 * shapes the form from the server's values and back into a body, says whether the form differs from what is saved, and words each refusal.
 *
 * - A role (the on-call person, the backup) is a person: nobody, an OcuTalon user (a name from the server's list) or someone by email, with an email address
 *   and the channels to page by. The select's values are `nobody`, `user:<name>` and `email`, so that no user name can be mistaken for a choice.
 * - personOf reads a stored role's person from its user and address; onCallFormOf builds the form from the server's values; onCallBody is the body of a save.
 * - telegramState says whether the Telegram box can be chosen: not for a user the list shows without a paired chat. A user the list does not hold is not judged:
 *   the stored boxes stay as stored, and the server's save-time checks decide. defaultChannels is what the boxes hold when a person is chosen.
 * - fieldErrorText is the accepted text of a refused field; personOptions is the Person select's choices, and a stored user who has lost their session row
 *   stays in the list.
 * - isOnCallDirty compares a form with its saved one, ignoring what a hidden control holds.
 */
import type { OnCallValues } from '../api/api-types';
import { SETTINGS_TEXTS } from './settings-view.ts';

/** The fields that a refusal can name, in the form's order: where the first of them is, focus goes. */
export const ONCALL_FIELDS = ['primaryUser', 'primaryEmail', 'primaryChannels', 'backupUser', 'backupEmail', 'backupChannels', 'escalationMinutes'] as const;

/** The name of a field of the on-call body. */
export type OnCallField = (typeof ONCALL_FIELDS)[number];

/** The two roles, in the form's order. */
export const ONCALL_ROLES = ['primary', 'backup'] as const;

/** A role of the form. */
export type OnCallRole = (typeof ONCALL_ROLES)[number];

/** The kind of a person. */
export type Person = 'nobody' | 'user' | 'email';

/** An OcuTalon user that the server lists, and whether one of their sessions has a paired chat. */
export interface OnCallUser {
  user: string;
  paired: boolean;
}

/** One role as the form holds it: the person, the user (while the person is a user), the typed address and the two Page by boxes. */
export interface OnCallRoleForm {
  person: Person;
  user: string;
  email: string;
  telegram: boolean;
  mail: boolean;
}

/** The form: both roles and the minutes as typed. */
export interface OnCallForm {
  primary: OnCallRoleForm;
  backup: OnCallRoleForm;
  minutes: string;
}

/** Whether the Telegram box can be chosen: enabled, unpaired (a user without a paired chat, with the filled text) or emailOnly (a person by email, with its text). */
export type TelegramState = { kind: 'enabled' } | { kind: 'unpaired'; text: string } | { kind: 'emailOnly'; text: string };

/** The body of a save, as the server takes it. */
export interface OnCallBody {
  primaryPerson: Person;
  primaryUser: string;
  primaryEmail: string;
  primaryChannels: string;
  backupPerson: Person;
  backupUser: string;
  backupEmail: string;
  backupChannels: string;
  escalationMinutes: number | string;
}

/** A choice of the Person select. */
export interface PersonOption {
  value: string;
  label: string;
}

/** The person that a stored role is: a user when it has a user, else someone by email when it has an address, else nobody. */
export function personOf(user: string, email: string): Person {
  if (user !== '') {
    return 'user';
  }
  return email !== '' ? 'email' : 'nobody';
}

/** The Person select's value for a role: `nobody`, `email`, or `user:` and the name. */
export function personValue(form: Readonly<OnCallRoleForm>): string {
  return form.person === 'user' ? `user:${form.user}` : form.person;
}

/** The person and the user that a select value names (an unknown value is nobody). */
export function parsePerson(value: string): { person: Person; user: string } {
  if (value.startsWith('user:')) {
    return { person: 'user', user: value.slice('user:'.length) };
  }
  return { person: value === 'email' ? 'email' : 'nobody', user: '' };
}

/** The Person select's choices: Nobody, each user the server lists, a stored user the list lacks, then Someone else, by email. */
export function personOptions(users: readonly OnCallUser[], storedUser: string): PersonOption[] {
  const names = users.map((one) => one.user);
  const stored = storedUser !== '' && !names.includes(storedUser) ? [storedUser] : [];
  return [
    { value: 'nobody', label: SETTINGS_TEXTS.onCall.nobody },
    ...[...names, ...stored].map((name) => ({ value: `user:${name}`, label: name })),
    { value: 'email', label: SETTINGS_TEXTS.onCall.byEmail },
  ];
}

/**
 * Whether the Telegram box can be chosen for the person: not for a person by email, and not for a user the list shows without a paired chat. A user the list does
 * not hold is not judged (the list may be unavailable, and the server refuses an unknown user or an unpaired Telegram at save), so it reads as enabled, as does
 * nobody, who has no boxes.
 */
export function telegramState(person: Person, user: string, users: readonly OnCallUser[]): TelegramState {
  if (person === 'email') {
    return { kind: 'emailOnly', text: SETTINGS_TEXTS.onCall.telegramEmailOnly };
  }
  const listed = person === 'user' ? users.find((one) => one.user === user) : undefined;
  if (listed !== undefined && listed.paired !== true) {
    return { kind: 'unpaired', text: SETTINGS_TEXTS.onCall.telegramUnpaired.replace('{user}', () => user) };
  }
  return { kind: 'enabled' };
}

/** The Page by boxes that a chosen person starts with: Telegram and Email, but only Email where Telegram cannot be chosen. */
export function defaultChannels(person: Person, paired: boolean): { telegram: boolean; mail: boolean } {
  return { telegram: person === 'nobody' || (person === 'user' && paired), mail: true };
}

/** The boxes that a stored channel list names. */
function boxesOf(channels: string): { telegram: boolean; mail: boolean } {
  const named = channels.split(',').map((name) => name.trim());
  return { telegram: named.includes('telegram'), mail: named.includes('email') };
}

/** One role of the form from its stored values; a Telegram box that cannot be chosen now (a user the list shows unpaired) is not checked. */
function roleFormOf(user: string, email: string, channels: string, users: readonly OnCallUser[]): OnCallRoleForm {
  const person = personOf(user, email);
  const boxes = boxesOf(channels);
  return { person, user, email, telegram: boxes.telegram && telegramState(person, user, users).kind === 'enabled', mail: boxes.mail };
}

/** The form for the server's values: the minutes as text, and a person who has nothing stored is nobody. */
export function onCallFormOf(values: Readonly<OnCallValues>): OnCallForm {
  return {
    primary: roleFormOf(values.primaryUser, values.primaryEmail, values.primaryChannels, values.users),
    backup: roleFormOf(values.backupUser, values.backupEmail, values.backupChannels, values.users),
    minutes: String(values.escalationMinutes),
  };
}

/** The channels of a role as the server takes them: the checked boxes in the order telegram, email. Nobody sends the default, which the server ignores. */
function channelsOf(form: Readonly<OnCallRoleForm>): string {
  if (form.person === 'nobody') {
    return 'telegram,email';
  }
  return [form.telegram ? 'telegram' : '', form.mail ? 'email' : ''].filter((name) => name !== '').join(',');
}

/** The body of a save: both persons and what goes with them, and the minutes as a number when they are digits (the server judges the range), else as typed. */
export function onCallBody(form: Readonly<OnCallForm>): OnCallBody {
  const typed = form.minutes.trim();
  const role = (one: Readonly<OnCallRoleForm>): { person: Person; user: string; email: string; channels: string } => ({
    person: one.person,
    user: one.person === 'user' ? one.user : '',
    email: one.person === 'nobody' ? '' : one.email.trim(),
    channels: channelsOf(one),
  });
  const primary = role(form.primary);
  const backup = role(form.backup);
  return {
    primaryPerson: primary.person,
    primaryUser: primary.user,
    primaryEmail: primary.email,
    primaryChannels: primary.channels,
    backupPerson: backup.person,
    backupUser: backup.user,
    backupEmail: backup.email,
    backupChannels: backup.channels,
    escalationMinutes: /^[0-9]{1,9}$/.test(typed) ? Number(typed) : typed,
  };
}

/** True when the form differs from the saved one: what a nobody's hidden address and boxes hold, and the white space around a typed value, do not count. */
export function isOnCallDirty(current: Readonly<OnCallForm>, saved: Readonly<OnCallForm>): boolean {
  const one = onCallBody(current);
  const was = onCallBody(saved);
  return (Object.keys(one) as (keyof OnCallBody)[]).some((name) => one[name] !== was[name]);
}

/** The accepted text of a refused field. The user's text names the user that the form holds for that role. */
export function fieldErrorText(name: OnCallField, form: Readonly<OnCallForm>): string {
  switch (name) {
    case 'primaryUser':
      return SETTINGS_TEXTS.onCall.unknownUser.replace('{user}', () => form.primary.user);
    case 'backupUser':
      return SETTINGS_TEXTS.onCall.unknownUser.replace('{user}', () => form.backup.user);
    case 'primaryEmail':
    case 'backupEmail':
      return SETTINGS_TEXTS.onCall.badEmail;
    case 'primaryChannels':
    case 'backupChannels':
      return SETTINGS_TEXTS.onCall.noChannel;
    case 'escalationMinutes':
      return SETTINGS_TEXTS.onCall.badMinutes;
  }
}
