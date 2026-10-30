/**
 * The texts of the online demo's Sign out dialog (Story 16.4; EXPERIENCE: Component Patterns, Frame; UX-DR30). A framework-free module: it
 * imports nothing, so Node runs it as it is and the strings test reads it. The dialog is named by its one sentence.
 */

/** The id of the sentence, which names the dialog. */
export const SIGN_OUT_TEXT_ID = 'sign-out-text';

/** The sentence, and the dialog's two buttons. */
export const SIGN_OUT_TEXTS = {
  text: 'Signing out ends this demo session. Signing in again starts a fresh one.',
  cancel: 'Cancel',
  confirm: 'Sign out',
} as const;
