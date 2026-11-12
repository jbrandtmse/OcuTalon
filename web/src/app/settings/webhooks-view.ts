/**
 * The Webhooks group of Settings > Channels (Story 35.3; EXPERIENCE: Settings and requests (step 4)): the view rules of its form, as a framework-free module
 * that imports nothing (so Node runs it as it is). The page decides nothing (AD-12): the server validates every name and secret and answers each refused field
 * with its text, and the page shows those texts as they come. The secret is write-only: it is typed and sent, cleared once saved, and no text of this module
 * holds one.
 * - addressText fills the accepted sentence (SETTINGS_TEXTS.webhooks.address, "Send events with POST to {address}.") with the page's origin and the webhook's path.
 * - webhookOutcome classifies a refused or failed call: 403 is denied (the group shows the page's denied text), 409 not_available is the online demo's
 *   (the group shows its own text instead of the form), a 400 bad_webhook that names a name or a secret text is a field refusal, and every other answer is a
 *   form error ("Couldn't save. Nothing was changed.").
 */
/** What a refused or failed webhook call means for the group. */
export type WebhookOutcome =
  | { kind: 'denied' }
  | { kind: 'off' }
  | { kind: 'fields'; name: string; secret: string }
  | { kind: 'form' };

/** The line under a webhook: the sentence template with the address, which is the origin of the page followed by the webhook's path. */
export function addressText(template: string, origin: string, path: string): string {
  return template.replace('{address}', `${origin}${path}`);
}

/** The text of a field in a body's `fields`, or '' when the body names none. */
function fieldText(fields: unknown, key: 'name' | 'secret'): string {
  if (fields === null || typeof fields !== 'object') {
    return '';
  }
  const value = (fields as Record<string, unknown>)[key];
  return typeof value === 'string' ? value : '';
}

/** Classifies a refused or failed call from its status and error body. */
export function webhookOutcome(status: number, body: unknown): WebhookOutcome {
  const error = body !== null && typeof body === 'object' ? (body as { error?: { code?: unknown }; fields?: unknown }) : {};
  if (status === 403) {
    return { kind: 'denied' };
  }
  if (status === 409 && error.error?.code === 'not_available') {
    return { kind: 'off' };
  }
  if (status === 400 && error.error?.code === 'bad_webhook') {
    const name = fieldText(error.fields, 'name');
    const secret = fieldText(error.fields, 'secret');
    if (name !== '' || secret !== '') {
      return { kind: 'fields', name, secret };
    }
  }
  return { kind: 'form' };
}
