/**
 * The Slack group of Settings > Channels (Story 27.3; EXPERIENCE: Slack (step 7)): the view rules of its members form, as a framework-free module that imports nothing
 * (so Node runs it as it is). The page decides nothing (AD-12): the server judges every link and answers a refusal with its reason's text, and the page shows that text as it
 * comes; the one check it makes itself is the shape of a member ID, so that a typing slip costs no request.
 * - SLACK_TEXTS is every fixed string of the group; the server's own copies are the catalog keys of OcuTalon.Msg.Catalog.Core, pinned equal by a test.
 * - memberIdProblem says what is wrong with a typed member ID before it is sent: the text of slackBadMemberId, or '' when the ID has the shape the server accepts.
 * - slackOutcome classifies a refused or failed call: 403 is denied, 409 not_available is off (the online demo), a 400 bad_slack_link is the text of its reason under the
 *   field it names (or under the form, when it names none), and every other answer is failed.
 * - slackState turns the server's list into what the group draws.
 */
/** Every fixed string of the group. */
export const SLACK_TEXTS = {
  heading: 'Slack',
  notSetUp: 'Slack not set up. Add SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET to .env and restart OcuTalon.',
  howTo: 'How to set it up',
  on: 'Slack on',
  address: "Subscribe your Slack app's events to {address}.",
  offOnDemo: 'Slack is off on the online demo, so it has no public Slack address. It works on your own install.',
  membersHeading: 'Linked Slack members',
  membersHelp: 'Only direct messages to the bot from a linked member become chat turns. Everything else from Slack is recorded in Visual Trace and goes no further.',
  memberId: 'Slack member ID',
  memberUser: 'OcuTalon user',
  link: 'Link member',
  unlink: 'Unlink',
  noMembers: 'No Slack members are linked yet.',
  badMemberId: 'Enter a Slack member ID such as U012AB3CDE: a U or W followed by letters and digits. Nothing was changed.',
  memberTaken: 'That Slack member is already linked to another user. Nothing was changed.',
  userTaken: '{user} already has a linked Slack member. Unlink it first. Nothing was changed.',
  linked: 'Linked. Their direct messages to the bot now reach OcuTalon. Recorded in the audit log.',
  unlinked: 'Unlinked. Their messages no longer reach OcuTalon. Recorded in the audit log.',
  noWorkspace: "OcuTalon hasn't had an event from your Slack workspace yet. Ask the person to send the bot a direct message, then link them. Nothing was changed.",
  unknownUser: 'Choose an OcuTalon user from the list. Nothing was changed.',
} as const;

/** The shape of a Slack member ID, as the server accepts it once trimmed and upper-cased: U or W, then 2 to 31 letters or digits. */
const MEMBER_ID = /^[UW][A-Z0-9]{2,31}$/;

/** '' when the typed member ID has the accepted shape, else the text of slackBadMemberId. */
export function memberIdProblem(text: string): string {
  return MEMBER_ID.test(text.trim().toUpperCase()) ? '' : SLACK_TEXTS.badMemberId;
}

/** What a refused or failed Slack call means for the group. */
export type SlackOutcome =
  | { kind: 'denied' }
  | { kind: 'off' }
  | { kind: 'field'; field: 'member' | 'user'; text: string }
  | { kind: 'form'; text: string }
  | { kind: 'failed' };

/** Classifies a refused or failed call from its status and error body. */
export function slackOutcome(status: number, body: unknown): SlackOutcome {
  const parsed = body !== null && typeof body === 'object' ? (body as { error?: { code?: unknown; message?: unknown }; fields?: unknown }) : {};
  if (status === 403) {
    return { kind: 'denied' };
  }
  if (status === 409 && parsed.error?.code === 'not_available') {
    return { kind: 'off' };
  }
  if (status === 400 && parsed.error?.code === 'bad_slack_link' && typeof parsed.error.message === 'string' && parsed.error.message !== '') {
    const text = parsed.error.message;
    const fields = Array.isArray(parsed.fields) ? parsed.fields : [];
    if (fields.includes('member')) {
      return { kind: 'field', field: 'member', text };
    }
    if (fields.includes('user')) {
      return { kind: 'field', field: 'user', text };
    }
    return { kind: 'form', text };
  }
  return { kind: 'failed' };
}

/** One linked member as the list holds it. */
export interface SlackMember {
  ref: string;
  user: string;
  member: string;
}

/** What the group draws from the server's list: whether Slack is on, the path of its events route, the members (none is the empty text) and the users the form offers. */
export interface SlackView {
  on: boolean;
  path: string;
  members: readonly SlackMember[];
  users: readonly string[];
}

/** The group's view of the server's list: Slack is on only when the server says "on". */
export function slackState(list: { state: string; path: string; links: readonly SlackMember[]; users: readonly string[] }): SlackView {
  return { on: list.state === 'on', path: list.path, members: list.links, users: list.users };
}
