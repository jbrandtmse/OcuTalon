import type {
  ApprovalPayload,
  CheckPayload,
  DecisionPayload,
  DocumentPayload,
  LiveEventType,
  LivePayloads,
  ReminderPayload,
  StatusPayload,
} from '../live/payloads';

/** A live event without its place in a stream: the type and the payload that goes with it. */
export type LiveItem<T extends LiveEventType = LiveEventType> = T extends LiveEventType ? { type: T; payload: LivePayloads[T] } : never;

/** One event of the poll: the stream is the cursor that it advances, never the session's reference. */
export type LiveEnvelope<T extends LiveEventType = LiveEventType> = LiveItem<T> & {
  seq: number;
  stream: 'session' | 'instance';
  ts: string;
};

/**
 * The Telegram block of the snapshot: whether the release includes Telegram, the bot's state and the session's pairing. The server
 * builds it in Web.Api.StateBody: `included` from Channel.Telegram.In.Included(), `state` and `botUserName` from the telegramState status
 * mark (StatusMark.RecordTelegram), `paired` and `displayName` from the session's Pairing row (Data.Ownership.Pairing), and
 * `pausedUntil` from the telegramPaused mark while its time is in the future, else "".
 */
export interface TelegramState {
  included: boolean;
  state: 'off' | 'on' | 'rejected';
  botUserName: string;
  paired: boolean;
  displayName: string;
  pausedUntil: string;
}

/**
 * An entry of the snapshot's chat. An incident entry may carry `decision`, the session's own diagnose decision of the incident
 * (Web.Api.ChatItems), so that the card finds it after a load; the other entries never do.
 */
export type ChatItem = LiveItem & { decision?: DecisionPayload };

/** GET /ocutalon/api/v1/state: the snapshot that the page loads, then follows with GET /v1/events. */
export interface StateSnapshot {
  version: string;
  instanceZone: string;
  epoch: string;
  streams: { session: number; instance: number };
  chat: ChatItem[];
  rail: {
    approvals: ApprovalPayload[];
    checks: CheckPayload[];
    reminders: ReminderPayload[];
    decisions: DecisionPayload[];
  };
  user: string;
  /** True when the signed-in user holds OcuTalonAdmin; it only decides whether the header shows the Settings link (Story 33.2). */
  admin: boolean;
  onlineDemo: boolean;
  demoMode: boolean;
  models: { triage: string; diagnosis: string; chat: string };
  telegram: TelegramState;
  status: StatusPayload[];
  /** The idle cap in seconds: how long the page may go with no key press, click or sent message; present only on the online demo (Story 16.4). */
  idleSeconds?: number;
  /** The read-only Visual Trace account that the online demo publishes; present only on the online demo, never on a local install. */
  traceAccount?: { user: string; password: string };
  /** The next scheduled reset, UTC to the second; present only on the online demo with a schedule, and the last key (Story 16.8). */
  nextReset?: string;
}

/** GET /ocutalon/api/v1/events?after=<sessionSeq>&afterInstance=<instanceSeq>: the session's events, then the instance's. */
export interface EventsResponse {
  epoch: string;
  events: LiveEnvelope[];
}

/** POST /ocutalon/api/v1/messages: one message of the chat. The session is the caller's; the body never names one. */
export interface MessagePost {
  clientId: string;
  text: string;
  fromGuide: boolean;
}

/** The 202 answer to a message: its clientId, also for a repeat of one the server already holds. */
export interface MessageAccepted {
  clientId: string;
}

/** POST /ocutalon/api/v1/mailbox/incoming: one simulated email. The session is the caller's; the body never names one. */
export interface MailboxEmail {
  from: string;
  subject: string;
  body: string;
}

/** The 202 answer to a simulated email or a sample: the Ref of the email it recorded. */
export interface MailboxAccepted {
  ref: string;
}

/** POST /ocutalon/api/v1/guide/markers: the guide's two UI markers (Story 4.7). The session is the caller's; the body never names one. */
export type GuideMarker = 'trace_opened' | 'run_again';

/** The channels a page answers an approval request from: the chat's request card, and the simulated phone's message. */
export type AnswerChannel = 'web' | 'phone';

/** POST /ocutalon/api/v1/approvals/:ref/answer: the body of the 200 answer, the answered request. The session is the caller's; the body never names one. */
export interface AnswerBody {
  result: 'done';
  approval: ApprovalPayload;
}

/** POST /ocutalon/api/v1/incidents/:ref/dismiss: the body of the 200 answer. The request body is {} and the session is the caller's. */
export interface DismissBody {
  result: 'done';
}

/** POST /ocutalon/api/v1/decisions/:ref/got-it: the body of the 200 answer. `handledAt` is when the notice was marked, UTC to the second (the first press's, also for a repeat). The request body is {} (the web chat's press) or {"channel":"phone"} (the simulated phone's) and the session is the caller's. */
export interface GotItBody {
  result: 'done';
  handledAt: string;
}

/** POST /ocutalon/api/v1/pairing/code: the 200 answer. The code is 22 characters, shown once and valid until `expiresAt` (UTC); the server stores only its hash. */
export interface PairingCode {
  code: string;
  expiresAt: string;
}

/** DELETE /ocutalon/api/v1/pairing: the body of the 200 answer, also when nothing was paired. The request body is {} and the session is the caller's. */
export interface UnpairDone {
  result: 'done';
}

/** POST /ocutalon/api/v1/demo/break-feed: the 200 answer to a press, the run's batch is sent, and when it started. The request body is {} and the session is the caller's. */
export interface BreakFeedSent {
  state: 'sent';
  startedAt: string;
}

/** The body of an error answer to an answer: the error, and the request's payload beside it for a 409 (already answered, expired). */
export interface AnswerError {
  error: { code: string; message: string };
  approval?: ApprovalPayload;
}

/** The body of every error answer. */
export interface ApiError {
  error: { code: string; message: string };
}

/**
 * The body of a 429 answer (Story 16.9; AD-20), which an `HttpErrorResponse.error` carries: `allowance` for a message the session's
 * allowance refused (with the `limit` beside `retryAt`), `email_limit` for a simulated email the mailbox refused. `retryAt` is the UTC
 * time when the session may send again.
 */
export interface ApiRefusal {
  error: { code: string; message: string };
  retryAt: string;
  limit?: number;
}

/** GET /ocutalon/public/status: no session; every key is present, null where it is not set. */
export interface PublicStatus {
  ready: boolean;
  nextReset: string | null;
  busy: boolean;
  lastReset: string | null;
  lastResetKind: string | null;
}

/** GET /ocutalon/api/v1/settings: the values of the settings page (admins only; a 403 `not_admin` for anyone else). */
export interface SettingsBody {
  sections: SettingsSections;
  /** The bridge values: the budgets and the zone as strings, and `agents`, the model of each of the three agents. */
  bridge: { agents?: Record<string, AgentModels>; [name: string]: unknown };
  /** The provider table's rows, in their fixed order. No key value is ever in it (Story 18.3). */
  providers: ProviderRow[];
  instanceZone: string;
  /** The prices of each model of each supported provider that has a Price row, in US dollars per million tokens. */
  prices?: Prices;
}

/** A row of the provider table: `keySet` says that the key variable is set; `supported` says that an agent can run on it. */
export interface ProviderRow {
  provider: string;
  defaultModel: string;
  models: string[];
  keyVariable: string;
  keySet: boolean;
  supported: boolean;
}

/** The model of one agent and its second model; the second pair is empty when the agent has none. */
export interface AgentModels {
  provider: string;
  model: string;
  secondProvider: string;
  secondModel: string;
}

/** The prices of one model that the Models section edits. */
export interface ModelPrices {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}

/** The prices by model. */
export type Prices = Record<string, ModelPrices>;

/** The body of a Models save: the three agents and the prices of every listed model, the prices as typed. */
export interface ModelsBody {
  agents: Record<string, AgentModels>;
  prices: Record<string, Record<keyof ModelPrices, string>>;
}

/** The 200 answer to POST /v1/settings/models/test: `answered`, the seconds with one decimal, and the fallback reason ("" when answered). */
export interface ModelTestAnswer {
  answered: boolean;
  seconds: number;
  reason: string;
}

/** The values of the sections that hold some. */
export interface SettingsSections {
  'check-thresholds': {
    diskFreePercent: number;
    journalFreePercent: number;
    licenseUsePercent: number;
    queueMessages: number;
    queueWaitMinutes: number;
  };
  'daily-digest': { time: string; channels: string };
  'demo-mode': { demoMode: boolean };
  /** The mailbox (Story 21.2): never on the online demo. `passwordSet` says that a password is stored; the password itself is never sent. */
  channels?: EmailValues;
}

/**
 * The values of the Email form: the saved address, incoming server (host, or host:port off port 995), outgoing server (host, or host:port off port 587; empty
 * for none) and user name, whether a password is stored, and the sign-in method (Story 21.3): `password`, `google` or `microsoft`. For a provider,
 * `clientId` is the saved client ID, `clientSecretSet` says that a client is registered with IRIS (the secret itself is never sent) and `signedIn` says that
 * the last check found tokens.
 */
export interface EmailValues {
  address: string;
  incoming: string;
  outgoing: string;
  user: string;
  passwordSet: boolean;
  signIn: 'password' | 'google' | 'microsoft';
  clientId: string;
  clientSecretSet: boolean;
  signedIn: boolean;
}

/** The 200 answer to POST /ocutalon/api/v1/settings/channels/sign-in with `start` (Story 21.3): IRIS's authorization address, to open in a new tab. */
export interface MailSignInStarted {
  result: 'started';
  url: string;
}

/** The 200 answer to the same route with `check`: whether IRIS's OAuth2 client holds the mailbox's tokens. */
export interface MailSignInChecked {
  result: 'checked';
  signedIn: boolean;
}

/** The body of a Time zone save: the IANA zone name, or "" for the server's own zone. The zone is a bridge value, so the 200 answer's sections do not hold it. */
export interface TimeZoneBody {
  InstanceZone: string;
}

/** The 202 answer to POST /ocutalon/api/v1/settings/daily-digest/send: the digest is being sent. */
export interface DigestSending {
  result: 'sending';
}

/** The 200 answer to a save: `{result: 'done', sections}`. */
export interface SettingsSaved {
  result: 'done';
  sections: SettingsSections;
}

/** The error body of a refused or failed save: `{error: {code, message}}`, and for `bad_settings` the names of the refused fields. */
export interface SettingsError {
  error: { code: string; message: string };
  fields?: string[];
}

/** GET /ocutalon/api/v1/documents: the session's documents (an install's, on a local install), newest first; the same view as the `document` event. */
export interface DocumentsList {
  documents: DocumentPayload[];
}

/** The 200 answer to POST /ocutalon/api/v1/documents: the command was done, and `ref` is the new document's Ref. */
export interface DocumentAdded {
  result: 'done';
  ref: string;
}

/** The 200 answer to GET /ocutalon/api/v1/documents/:ref: the document's name and its text, as the file was read; the text is shown as plain text. */
export interface DocumentText {
  ref: string;
  name: string;
  text: string;
}

/** The 200 answer to DELETE /ocutalon/api/v1/documents/:ref. */
export interface DocumentRemoved {
  result: 'done';
}

/**
 * The error body of a refused or failed add, which an `HttpErrorResponse.error` carries: a 400 `bad_document` has the `reason` that the route
 * refused the file for (`wrong_type`, `too_large` or `empty`) and none for a body it could not read; a 413 `body_too_large`, a 501 `not_built`
 * and a 500 `server_error` have none.
 */
export interface DocumentRefusal {
  error: { code: string; message: string };
  reason?: string;
}
