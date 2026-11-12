/**
 * The Email form's view model (Stories 21.2, 21.6 and 21.3; EXPERIENCE: Message Catalog, Settings and requests (step 4)): the fixed strings of the form, its
 * fields and the small rules of its body and its errors. A framework-free module: it imports only types and uses only erasable TypeScript syntax, so
 * Node runs it as it is. The page decides nothing (AD-12): the server (SettingsOps) judges every value, and the password and the client secret are
 * write-only, so the form never holds a stored one.
 *
 * - EMAIL_TEXTS is every fixed string of the form: the accepted wording of the Message Catalog keys settings.emailHeading, emailHelp, emailAddress,
 *   emailAddressHelp, emailIncoming, emailOutgoing, emailUser, emailPassword, emailSignIn, emailClientId, emailClientSecret, secretSet, secretNotSet and
 *   refusedExpansion, and the ruled texts of the sign-in method (U-320: its label, its options, the redirect address and the state line).
 * - emailTextsOf turns the server's values into the form's texts (the password and client secret texts are always empty); emailBody is the body of a save,
 *   which names the sign-in method, sends the password only in password mode and the client ID and secret only in a provider mode, and leaves a secret out
 *   when nothing was typed, so that the stored one is kept; isEmailDirty is the rule of the form's unsaved state.
 * - SIGN_IN_METHODS, providerName, signInReady, redirectAddress, stateText and signInButtonText are the rules of the sign-in method; landedFromSignIn and
 *   withoutLanding read and clear the `signin=1` of the address that the consent returns to.
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
  outgoing: 'Outgoing mail server (SMTP)',
  user: 'User name',
  password: 'Password',
  signInMethod: 'Sign-in method',
  methodGoogle: 'Google',
  methodMicrosoft: 'Microsoft 365',
  clientId: 'Client ID',
  clientSecret: 'Client secret',
  redirect: 'Redirect address',
  redirectHelp: 'Add this address to your OAuth2 client at {provider} as an authorized redirect URI.',
  signedIn: 'Signed in with {provider}.',
  notSignedIn: 'Not signed in yet. Save, then sign in with {provider}.',
  signIn: 'Sign in with {provider}',
  secretSet: 'Saved, and never shown again. Type a new value to replace it.',
  secretNotSet: 'Not set.',
  refusedExpansion: "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.",
} as const;

/** The seven text fields of the form, in the order of the page and of the server's refusals. */
export const EMAIL_FIELDS = ['address', 'incoming', 'outgoing', 'user', 'password', 'clientId', 'clientSecret'] as const;

/** The name of a field of the form. */
export type EmailField = (typeof EMAIL_FIELDS)[number];

/** How the mailbox is signed in: the stored password, or OAuth2 with Google or Microsoft 365. */
export type SignIn = 'password' | 'google' | 'microsoft';

/** The sign-in methods, in the order of the radiogroup, each with its label. */
export const SIGN_IN_METHODS: readonly { value: SignIn; label: string }[] = [
  { value: 'password', label: EMAIL_TEXTS.password },
  { value: 'google', label: EMAIL_TEXTS.methodGoogle },
  { value: 'microsoft', label: EMAIL_TEXTS.methodMicrosoft },
];

/** The typed texts of the form and the chosen sign-in method. */
export type EmailTexts = Record<EmailField, string> & { signIn: SignIn };

/** The path of IRIS's OAuth2 redirection endpoint, which the provider sends the browser back to. */
export const REDIRECT_PATH = '/csp/sys/oauth2/OAuth2.Response.cls';

/** The characters that open a setting reference, which the server refuses in any value. */
const REFERENCE = '@{';

/** The form's texts for the server's values: the stored texts and method, and empty secrets (a stored password or client secret is never sent to the page). */
export function emailTextsOf(values: Readonly<EmailValues> | undefined): EmailTexts {
  return {
    address: values?.address ?? '',
    incoming: values?.incoming ?? '',
    outgoing: values?.outgoing ?? '',
    user: values?.user ?? '',
    password: '',
    clientId: values?.clientId ?? '',
    clientSecret: '',
    signIn: values?.signIn ?? 'password',
  };
}

/**
 * The body of a save: the address, the two servers (the outgoing one always, so that an empty one clears it), the user name and the sign-in method as
 * typed. In password mode the password goes only when one was typed (an absent one keeps the stored one); in a provider mode the client ID always goes and
 * the client secret only when one was typed, and no password goes.
 */
export function emailBody(texts: Readonly<EmailTexts>): Record<string, string> {
  const body: Record<string, string> = { address: texts.address, incoming: texts.incoming, outgoing: texts.outgoing, user: texts.user, signIn: texts.signIn };
  if (texts.signIn === 'password') {
    if (texts.password !== '') {
      body['password'] = texts.password;
    }
    return body;
  }
  body['clientId'] = texts.clientId;
  if (texts.clientSecret !== '') {
    body['clientSecret'] = texts.clientSecret;
  }
  return body;
}

/** Whether the form differs from its saved values: a changed text or method, or a secret typed for the chosen method. */
export function isEmailDirty(current: Readonly<EmailTexts>, saved: Readonly<EmailTexts>): boolean {
  return (
    current.address !== saved.address ||
    current.incoming !== saved.incoming ||
    current.outgoing !== saved.outgoing ||
    current.user !== saved.user ||
    current.signIn !== saved.signIn ||
    current.clientId !== saved.clientId ||
    (current.signIn === 'password' ? current.password !== '' : current.clientSecret !== '')
  );
}

/** The provider's name for a sign-in method ("" for the password). */
export function providerName(signIn: SignIn): string {
  return signIn === 'google' ? EMAIL_TEXTS.methodGoogle : signIn === 'microsoft' ? EMAIL_TEXTS.methodMicrosoft : '';
}

/** Whether the "Sign in with {provider}" button can act: a provider is chosen, it is the saved one, a client is registered for it and the form is clean. */
export function signInReady(current: Readonly<EmailTexts>, saved: Readonly<EmailTexts>, registered: boolean): boolean {
  return current.signIn !== 'password' && current.signIn === saved.signIn && registered && !isEmailDirty(current, saved);
}

/** The redirect address to register at the provider: the page's origin and IRIS's redirection endpoint. */
export function redirectAddress(origin: string): string {
  return `${origin}${REDIRECT_PATH}`;
}

/** The help under the redirect address, for the provider. */
export function redirectHelpText(signIn: SignIn): string {
  return EMAIL_TEXTS.redirectHelp.replace('{provider}', providerName(signIn));
}

/** The state line under the sign-in button: signed in, or not yet, for the provider. */
export function stateText(signIn: SignIn, signedIn: boolean): string {
  return (signedIn ? EMAIL_TEXTS.signedIn : EMAIL_TEXTS.notSignedIn).replace('{provider}', providerName(signIn));
}

/** The text of the sign-in button for the provider. */
export function signInButtonText(signIn: SignIn): string {
  return EMAIL_TEXTS.signIn.replace('{provider}', providerName(signIn));
}

/** Whether the address (the part after the hash) has the `signin=1` that the consent's return address carries. */
export function landedFromSignIn(hash: string): boolean {
  const at = hash.indexOf('?');
  return at !== -1 && hash.slice(at + 1).split('&').includes('signin=1');
}

/** The address without its `signin=1` (and without a `?` left empty), so that a reload does not check again. */
export function withoutLanding(hash: string): string {
  const at = hash.indexOf('?');
  if (at === -1) {
    return hash;
  }
  const rest = hash.slice(at + 1).split('&').filter((part) => part !== 'signin=1');
  return rest.length === 0 ? hash.slice(0, at) : `${hash.slice(0, at)}?${rest.join('&')}`;
}

/** Whether a typed value holds the characters that open a setting reference. */
export function holdsReference(text: string): boolean {
  return text.includes(REFERENCE);
}

/** The error under a refused field: the setting-reference text when the field's typed value holds one, else `failed`, the page's "Couldn't save" text. */
export function fieldErrorText(texts: Readonly<EmailTexts>, name: EmailField, failed: string): string {
  return holdsReference(texts[name]) ? EMAIL_TEXTS.refusedExpansion : failed;
}
