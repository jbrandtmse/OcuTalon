/**
 * The Partner contacts section's rules (Story 24.2; EXPERIENCE: Settings (step 5)): a framework-free module that imports only types and uses only erasable TypeScript
 * syntax, so Node runs it as it is. The page decides nothing (AD-12): the server validates every value and names the fields it refuses. This module only shapes a
 * form from a stored contact and back into the body of a save or a removal, says whether a form differs from what is saved, and words each refusal.
 *
 * - A contact's form is its name, its address and the productions it concerns, each production as the key of its namespace and production (productionKey).
 * - productionOptions lists the boxes of "Productions it concerns": the server's roster, labelled by display name, then any production that a stored contact still
 *   names but the roster no longer lists, labelled by its production, so that nothing stored is hidden and unticking it removes it.
 * - partnerBody is the body of a save (ref "" for a new contact) and removeBody the body of a removal; isPartnerDirty is the rule of a form.
 * - fieldErrorText is the accepted text of a refused field; removeQuestion is the Remove confirmation for a contact.
 */
import type { PartnerContact, PartnerContactBody, PartnerProduction, PartnerProductionRow } from '../api/api-types';
import { SETTINGS_TEXTS } from './settings-view.ts';

/** The fields that a refusal can name, in the form's order: where the first of them is, focus goes. */
export const PARTNER_FIELDS = ['name', 'email', 'productions'] as const;

/** The name of a field of a contact's body. */
export type PartnerField = (typeof PARTNER_FIELDS)[number];

/** One contact's form: the typed name and address, and the keys of the ticked productions. */
export interface PartnerForm {
  name: string;
  email: string;
  picked: readonly string[];
}

/** A box of the Productions it concerns group. */
export interface ProductionOption extends PartnerProduction {
  key: string;
  label: string;
}

/** The key of a production: its namespace and production as one unambiguous text. */
export function productionKey(production: PartnerProduction): string {
  return JSON.stringify([production.namespace, production.production]);
}

/** The empty form of a new contact. */
export function emptyPartnerForm(): PartnerForm {
  return { name: '', email: '', picked: [] };
}

/** The form that a stored contact fills. */
export function partnerFormOf(contact: PartnerContact): PartnerForm {
  return { name: contact.name, email: contact.email, picked: contact.productions.map(productionKey) };
}

/** The boxes for a contact: the roster's productions in the roster's order, then the stored ones that the roster lacks. */
export function productionOptions(roster: readonly PartnerProductionRow[], stored: readonly PartnerProduction[]): ProductionOption[] {
  const options: ProductionOption[] = roster.map((row) => ({ namespace: row.namespace, production: row.production, key: productionKey(row), label: row.displayName }));
  for (const one of stored) {
    const key = productionKey(one);
    if (!options.some((option) => option.key === key)) {
      options.push({ namespace: one.namespace, production: one.production, key, label: one.production });
    }
  }
  return options;
}

/** The body of a save: the ticked productions, as {namespace, production} in the boxes' order. */
export function partnerBody(ref: string, form: PartnerForm, options: readonly ProductionOption[]): PartnerContactBody {
  const productions = options.filter((option) => form.picked.includes(option.key)).map((option) => ({ namespace: option.namespace, production: option.production }));
  return { action: 'save', ref, name: form.name, email: form.email, productions };
}

/** The body of a removal. */
export function removeBody(ref: string): PartnerContactBody {
  return { action: 'remove', ref };
}

/** True when the form differs from the saved one: the name or the address (ignoring the white space around them) or the set of ticked productions. */
export function isPartnerDirty(form: PartnerForm, saved: PartnerForm): boolean {
  const now = [...new Set(form.picked)].sort();
  const before = [...new Set(saved.picked)].sort();
  return form.name.trim() !== saved.name.trim() || form.email.trim() !== saved.email.trim() || now.length !== before.length || now.some((key, at) => key !== before[at]);
}

/** The accepted text of a refused field: the name's, the address's (the On call section's) or the productions'. */
export function fieldErrorText(name: PartnerField): string {
  if (name === 'name') {
    return SETTINGS_TEXTS.partners.badName;
  }
  return name === 'email' ? SETTINGS_TEXTS.onCall.badEmail : SETTINGS_TEXTS.partners.noProduction;
}

/** The Remove confirmation: the contact's name and address in the accepted sentence. */
export function removeQuestion(contact: PartnerContact): string {
  return SETTINGS_TEXTS.partners.removeConfirm.replace(/\{(name|address)\}/g, (_match, key: string) => (key === 'name' ? contact.name : contact.email));
}
