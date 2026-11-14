/**
 * The Roles section of Settings (Story 25.4; AD-24; EXPERIENCE: Step 6, roles), as a framework-free module that imports nothing (so Node runs it as it is).
 * The page decides nothing (AD-12): the server judges every user and role and answers a refusal with its reason, and the page shows the text of that reason.
 * - ROLES_TEXTS is every fixed string of the section; the server's own copies are the parameters of OcuTalon.Web.RoleSettings, pinned equal by a test.
 * - roleOutcome classifies a refused or failed call: 403 is denied, 409 is off (the online demo), a 400 with a known `reason` is that reason's text, and
 *   every other answer is failed.
 * - saveLine says what shows after a save that the server accepted: the step-2 saved text when the roles changed, and, when they did not (a role the user already
 *   holds was granted, or one the user does not hold was removed), the no-change text with the user's name in it, which the template draws as text.
 * - ASSIGNABLE is the two roles the form offers, each with its option text and the text of its Remove button; removeLabel is the button's accessible name.
 */
/** The refusal reasons that the server names, each with the text the section shows. */
export const ROLES_REASONS = {
  user_system: "This is an IRIS system account, so its roles can't be changed here.",
  user_unknown: 'There is no IRIS user with that name.',
  user_managed: "OcuTalon manages this account, so its roles can't be changed here.",
  role: 'Only the approver and viewer roles can be changed here.',
  self_viewer: "You can't give yourself the viewer role here, because it would lock you out of Settings. Ask another admin.",
} as const;

/** Every fixed string of the section. */
export const ROLES_TEXTS = {
  heading: 'Roles',
  intro: "Approvers can answer the approval requests that reach them, for every kind of risky action. Viewers can open OcuTalon but can't chat, answer or change anything.",
  perKind: 'An approver role for one kind, such as OcuTalonApprover_resend, is granted in IRIS.',
  listHeading: 'People with an OcuTalon role',
  empty: 'No IRIS user holds an OcuTalon role yet.',
  managed: 'Managed by OcuTalon',
  userLabel: 'IRIS user name',
  roleLabel: 'Role',
  approverOption: 'Approver (all risky actions)',
  viewerOption: 'Viewer (read-only)',
  grant: 'Grant',
  removeApprover: 'Remove approver',
  removeViewer: 'Remove viewer',
  loadFailed: "Couldn't load the roles.",
  retry: 'Retry',
  off: "Roles can't be changed on the online demo.",
  noChange: "No change: {user}'s roles are already as you set them.",
  reasons: ROLES_REASONS,
} as const;

/** One of the two roles the section assigns: its IRIS name, the text of its option and the text of its Remove button. */
export interface AssignableRole {
  role: 'OcuTalonApprover' | 'OcuTalonViewer';
  option: string;
  remove: string;
  noun: 'approver' | 'viewer';
}

/** The two roles, in the order of the select. */
export const ASSIGNABLE: readonly AssignableRole[] = [
  { role: 'OcuTalonApprover', option: ROLES_TEXTS.approverOption, remove: ROLES_TEXTS.removeApprover, noun: 'approver' },
  { role: 'OcuTalonViewer', option: ROLES_TEXTS.viewerOption, remove: ROLES_TEXTS.removeViewer, noun: 'viewer' },
];

/** The accessible name of a Remove button: "Remove approver from {user}" or "Remove viewer from {user}". */
export function removeLabel(role: AssignableRole, user: string): string {
  return `Remove ${role.noun} from ${user}`;
}

/** The assignable roles that a user holds, in the order of ASSIGNABLE. */
export function heldAssignable(roles: readonly string[]): readonly AssignableRole[] {
  return ASSIGNABLE.filter((one) => roles.includes(one.role));
}

/** What a refused or failed call means for the section. */
export type RoleOutcome = { kind: 'denied' } | { kind: 'off' } | { kind: 'refused'; reason: keyof typeof ROLES_REASONS; text: string } | { kind: 'failed' };

/** Classifies a refused or failed call from its status and error body. */
export function roleOutcome(status: number, body: unknown): RoleOutcome {
  const parsed = body !== null && typeof body === 'object' ? (body as { error?: { code?: unknown }; reason?: unknown }) : {};
  if (status === 403) {
    return { kind: 'denied' };
  }
  if (status === 409 && parsed.error?.code === 'not_available') {
    return { kind: 'off' };
  }
  if (status === 400 && typeof parsed.reason === 'string' && Object.prototype.hasOwnProperty.call(ROLES_REASONS, parsed.reason)) {
    const reason = parsed.reason as keyof typeof ROLES_REASONS;
    return { kind: 'refused', reason, text: ROLES_REASONS[reason] };
  }
  return { kind: 'failed' };
}

/** What shows after an accepted save: whether the roles changed, and the line to show. */
export interface SaveLine {
  changed: boolean;
  text: string;
}

/** The line after an accepted save: `saved` when the roles changed, else the no-change text for the user (an answer without `changed: false` counts as a change). */
export function saveLine(answer: { changed?: boolean } | null | undefined, user: string, saved: string): SaveLine {
  if (answer?.changed === false) {
    return { changed: false, text: ROLES_TEXTS.noChange.replace('{user}', () => user) };
  }
  return { changed: true, text: saved };
}
