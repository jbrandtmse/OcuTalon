/**
 * The Email form's view model (Story 21.2; EXPERIENCE: Message Catalog, Settings and requests (step 4)): the fixed strings of the form, its four
 * fields and the small rules of its body and its errors. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so
 * Node runs it as it is. The page decides nothing (AD-12): the server (SettingsOps) judges every value, and the password is write-only, so the form never
 * holds the stored one.
 *
 * - EMAIL_TEXTS is every fixed string of the form: the accepted wording of the Message Catalog keys settings.emailHeading, emailHelp, emailAddress,
 *   emailAddressHelp, emailIncoming, emailUser, emailPassword, secretSet, secretNotSet and refusedExpansion.
 * - emailTextsOf turns the server's values into the form's texts (the password text is always empty); emailBody is the body of a save, which leaves
 *   the password out when nothing was typed, so that the stored one is kept; isEmailDirty is the rule of the form's unsaved state.
 * - holdsReference says that a typed value holds the characters that open a setting reference; fieldErrorText is the error under a refused field.
 */
import type { EmailValues } from '../api/api-types';

/** Every fixed string of the Email form. */
export const EMAIL_TEXTS = {
  heading: 'Email',
  help: 'Connect your mailbox. OcuTalon decides on each email that arrives after you connect it, and leaves your mail on the server.',
  address: 'Your email address',
  addressHelp: 'OcuTalon emails this address without asking.',
  incoming: 'Incoming mail server (POP3)',
  user: 'User name',
  password: 'Password',
  secretSet: 'Saved, and never shown again. Type a new value to replace it.',
  secretNotSet: 'Not set.',
  refusedExpansion: "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.",
} as const;

/** The four fields of the form, in the order of the page and of the server's refusals. */
export const EMAIL_FIELDS = ['address', 'incoming', 'user', 'password'] as const;

/** The name of a field of the form. */
export type EmailField = (typeof EMAIL_FIELDS)[number];

/** The typed texts of the form. */
export type EmailTexts = Record<EmailField, string>;

/** The characters that open a setting reference, which the server refuses in any value. */
const REFERENCE = '@{';

/** The form's texts for the server's values: the three stored texts, and an empty password text (the stored password is never sent to the page). */
export function emailTextsOf(values: Readonly<EmailValues> | undefined): EmailTexts {
  return { address: values?.address ?? '', incoming: values?.incoming ?? '', user: values?.user ?? '', password: '' };
}

/** The body of a save: the address, the server and the user name as typed, and the password only when one was typed (an absent one keeps the stored one). */
export function emailBody(texts: Readonly<EmailTexts>): Record<string, string> {
  const body: Record<string, string> = { address: texts.address, incoming: texts.incoming, user: texts.user };
  if (texts.password !== '') {
    body['password'] = texts.password;
  }
  return body;
}

/** Whether the form differs from its saved values: a changed text, or any typed password. */
export function isEmailDirty(current: Readonly<EmailTexts>, saved: Readonly<EmailTexts>): boolean {
  return current.address !== saved.address || current.incoming !== saved.incoming || current.user !== saved.user || current.password !== '';
}

/** Whether a typed value holds the characters that open a setting reference. */
export function holdsReference(text: string): boolean {
  return text.includes(REFERENCE);
}

/** The error under a refused field: the setting-reference text when the field's typed value holds one, else `failed`, the page's "Couldn't save" text. */
export function fieldErrorText(texts: Readonly<EmailTexts>, name: EmailField, failed: string): string {
  return holdsReference(texts[name]) ? EMAIL_TEXTS.refusedExpansion : failed;
}
