import { HttpClient, HttpErrorResponse, type HttpResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { map, type Observable } from 'rxjs';

import type { GuideStatePayload } from '../live/payloads';
import type {
  AnswerBody,
  AnswerChannel,
  BreakFeedSent,
  DigestSending,
  DismissBody,
  GotItBody,
  DocumentAdded,
  DocumentRemoved,
  DocumentText,
  DocumentsList,
  EventsResponse,
  FileAccepted,
  FilePost,
  GuideMarker,
  MailSignInChecked,
  MailSignInStarted,
  MailboxAccepted,
  MailboxEmail,
  McpChanged,
  McpSettings,
  MessageAccepted,
  MessagePost,
  ModelTestAnswer,
  PairingCode,
  PublicStatus,
  RoleSaved,
  RolesList,
  SettingsBody,
  SettingsSaved,
  StateSnapshot,
  UnpairDone,
  WebhookCreated,
  WebhookSecretSaved,
  WebhooksList,
} from './api-types';
import type { HistoryDecisionsResponse, HistoryFilters, HistoryIncidentsResponse } from './history-types';
import type { HeartbeatPut, HeartbeatSaved, HeartbeatState } from './heartbeat-types';
import type { PersonaPut, PersonaSaved, PersonaState } from './persona-types';

const BASE = '/ocutalon/api/v1';

/** The address of the online demo's public status, which needs no session (Story 16.5). */
const PUBLIC_STATUS = '/ocutalon/public/status';

/** The typed client of the REST API: one method per call that the page makes. */
@Injectable({ providedIn: 'root' })
export class ApiClient {
  private readonly http = inject(HttpClient);

  /** The snapshot of the signed-in user's session. */
  state(): Observable<StateSnapshot> {
    return this.http.get<StateSnapshot>(`${BASE}/state`);
  }

  /** The settings page's values (admins only): a 403 for anyone else fails as an HttpErrorResponse whose `error` is the body. */
  settings(): Observable<SettingsBody> {
    return this.http.get<SettingsBody>(`${BASE}/settings`);
  }

  /**
   * Saves one settings section: a POST of the section's fields as a JSON object (the session and the user are the caller's, never in the body).
   * The answer is {result: 'done', sections}; a 400 `bad_settings` (with `fields`), a 409 `demo_step_failed`, a 501 and a 500 fail as an
   * HttpErrorResponse whose `error` is the body (SettingsError).
   */
  saveSettings(section: string, values: object): Observable<SettingsSaved> {
    return this.http.post<SettingsSaved>(`${BASE}/settings/${encodeURIComponent(section)}`, values);
  }

  /**
   * The signed-in admin's webhooks (Story 35.3): a GET that answers 200 `{webhooks: [{ref, name, path, createdAt}]}`. A 403 (not an admin) and a 409
   * `not_available` (the online demo) fail as an HttpErrorResponse whose `error` is the body.
   */
  webhooks(): Observable<WebhooksList> {
    return this.http.get<WebhooksList>(`${BASE}/settings/channels/webhooks`);
  }

  /**
   * Creates a webhook: a POST of `{name, secret}` that answers 200 with the new webhook. The secret is sent once and never comes back. A 400 `bad_webhook`
   * (with `fields`), a 403, a 409 and a 500 fail as an HttpErrorResponse.
   */
  createWebhook(name: string, secret: string): Observable<WebhookCreated> {
    return this.http.post<WebhookCreated>(`${BASE}/settings/channels/webhooks`, { name, secret });
  }

  /** Replaces a webhook's secret: a POST of `{secret}` that answers 200 `{result, message}`. A 404 for a webhook that is not the admin's fails as an HttpErrorResponse, as the others do. */
  setWebhookSecret(ref: string, secret: string): Observable<WebhookSecretSaved> {
    return this.http.post<WebhookSecretSaved>(`${BASE}/settings/channels/webhooks/${encodeURIComponent(ref)}/secret`, { secret });
  }

  /**
   * The users who hold an OcuTalon role (Story 25.4): a GET that answers 200 `{users: [{user, roles, managed}]}`. A 403 (not an admin), a 409 `not_available`
   * (the online demo) and a 501 fail as an HttpErrorResponse whose `error` is the body.
   */
  listRoles(): Observable<RolesList> {
    return this.http.get<RolesList>(`${BASE}/settings/roles`);
  }

  /**
   * Grants (`grant` true) or removes one of the two assignable roles of an IRIS user: a POST of `{user, role, grant}` that answers 200 `{result, changed}`. A 400
   * `bad_settings` (with `fields` and `reason`), a 403, a 409 and a 500 fail as an HttpErrorResponse.
   */
  saveRole(user: string, role: string, grant: boolean): Observable<RoleSaved> {
    return this.http.post<RoleSaved>(`${BASE}/settings/roles`, { user, role, grant });
  }

  /**
   * The MCP servers and their tools (Story 21.4): a GET that answers 200 `{servers, tools}`. A 403 (not an admin) and a 409 `not_available` (the online demo)
   * fail as an HttpErrorResponse whose `error` is the body.
   */
  mcpSettings(): Observable<McpSettings> {
    return this.http.get<McpSettings>(`${BASE}/settings/mcp`);
  }

  /**
   * Adds an MCP server: a POST of `{name, address}` and, when one was typed, `{secret}`. The secret is sent once and never comes back. A 400 `bad_mcp_server`
   * (with `fields`), a 403, a 409 and a 500 fail as an HttpErrorResponse.
   */
  addMcpServer(body: { name: string; address: string; secret?: string }): Observable<McpChanged> {
    return this.http.post<McpChanged>(`${BASE}/settings/mcp/servers`, body);
  }

  /** Removes an MCP server: a DELETE that answers 200 `{result: 'removed', message}`. A 404 (no such server), a 403, a 409 and a 500 fail as an HttpErrorResponse. */
  removeMcpServer(server: string): Observable<McpChanged> {
    return this.http.delete<McpChanged>(`${BASE}/settings/mcp/servers/${encodeURIComponent(server)}`, { body: {} });
  }

  /** Classifies one tool of an MCP server: a POST of `{server, tool, classification}` that answers 200 `{result: 'saved', message}`. */
  classifyMcpTool(server: string, tool: string, classification: string): Observable<McpChanged> {
    return this.http.post<McpChanged>(`${BASE}/settings/mcp/classify`, { server, tool, classification });
  }

  /**
   * Tests the saved first model of one agent: a POST of `{agent}` that answers 200 `{answered, seconds, reason}` (Story 18.3). The call can take most of
   * 45 seconds. A 400 `bad_settings` (an agent the server refuses), a 403 and a 500 fail as an HttpErrorResponse.
   */
  testModel(agent: string): Observable<ModelTestAnswer> {
    return this.http.post<ModelTestAnswer>(`${BASE}/settings/models/test`, { agent });
  }

  /**
   * Starts or checks the mailbox's OAuth2 sign-in (Story 21.3): a POST of `{action}` that answers 200 `{result: 'started', url}` for `start` and
   * `{result: 'checked', signedIn}` for `check`. A 400 `bad_settings` (nothing registered), a 403, a 409 and a 500 fail as an HttpErrorResponse.
   */
  signInMail(action: 'start'): Observable<MailSignInStarted>;
  signInMail(action: 'check'): Observable<MailSignInChecked>;
  signInMail(action: 'start' | 'check'): Observable<MailSignInStarted | MailSignInChecked> {
    return this.http.post<MailSignInStarted | MailSignInChecked>(`${BASE}/settings/channels/sign-in`, { action });
  }

  /**
   * Sends the signed-in admin's digest now: a POST with an empty body (Story 18.2). Only the answer 202 `{result: 'sending'}` is a success; any other
   * status fails as an error (a 403 for a user who is not an admin, a 500 `server_error`).
   */
  sendDigest(): Observable<DigestSending> {
    return this.http.post<DigestSending>(`${BASE}/settings/daily-digest/send`, {}, { observe: 'response' }).pipe(
      map((response) => {
        if (response.status !== 202 || response.body === null) {
          throw new HttpErrorResponse({ status: response.status, statusText: response.statusText, url: response.url ?? `${BASE}/settings/daily-digest/send` });
        }
        return response.body;
      }),
    );
  }

  /** Signs the user out: the server ends the CSP session and the whole sign-in group (204, no body). */
  endSession(): Observable<void> {
    return this.http.post<void>(`${BASE}/session/end`, {});
  }

  /**
   * Posts one message of the chat. Only the answer 202 is a success; any other status, a 2xx included, fails as an error.
   * A repeat of a clientId is answered 202 too, so a retry never queues a second turn.
   */
  postMessage(body: MessagePost): Observable<MessageAccepted> {
    return this.http.post<MessageAccepted>(`${BASE}/messages`, body, { observe: 'response' }).pipe(
      map((response) => {
        if (response.status !== 202 || response.body === null) {
          throw new HttpErrorResponse({ status: response.status, statusText: response.statusText, url: response.url ?? `${BASE}/messages` });
        }
        return response.body;
      }),
    );
  }

  /**
   * Sends one file of the chat: a POST of {clientId, name, content}, the file's bytes in base64 (the session is the caller's, never in the body). Only the
   * answer 202 is a success; a 400 `bad_file` (with its `reason`), a 409 `not_available`, a 413 and a 500 fail as an HttpErrorResponse whose `error` is the body
   * (FileRefusal).
   */
  sendFile(clientId: string, name: string, content: string): Observable<FileAccepted> {
    const body: FilePost = { clientId, name, content };
    return this.http.post<FileAccepted>(`${BASE}/files`, body, { observe: 'response' }).pipe(
      map((response) => {
        if (response.status !== 202 || response.body === null) {
          throw new HttpErrorResponse({ status: response.status, statusText: response.statusText, url: response.url ?? `${BASE}/files` });
        }
        return response.body;
      }),
    );
  }

  /** Simulates an incoming email in the simulated mailbox (demo mode only). Only the answer 202 is a success. */
  postMailboxIncoming(email: MailboxEmail): Observable<MailboxAccepted> {
    return this.accepted<MailboxAccepted>(`${BASE}/mailbox/incoming`, email);
  }

  /** Delivers one of the sample emails (newsletter, partner-notice, suspicious-request) into the simulated mailbox (demo mode only). Only the answer 202 is a success. */
  postMailboxSample(name: string): Observable<MailboxAccepted> {
    return this.accepted<MailboxAccepted>(`${BASE}/mailbox/samples/${encodeURIComponent(name)}`, {});
  }

  /** Writes one of the guide's UI markers (demo mode only); the answer is the guide view that /state carries, with its trace URL. */
  postGuideMarker(marker: GuideMarker): Observable<GuideStatePayload> {
    return this.http.post<GuideStatePayload>(`${BASE}/guide/markers`, { marker });
  }

  /**
   * Answers an approval request: a POST of {action, channel} (the session is the caller's, never in the body); the channel is 'web'
   * for the chat's request card and 'phone' for the simulated phone's message.
   * The whole response is observed: 200 is the answered request (AnswerBody); a 4xx or 5xx fails as an HttpErrorResponse whose
   * `error` is the body, which for a 409 also holds the request's payload (AnswerError).
   */
  answerApproval(ref: string, action: 'approve' | 'reject', channel: AnswerChannel = 'web'): Observable<HttpResponse<AnswerBody>> {
    return this.http.post<AnswerBody>(`${BASE}/approvals/${encodeURIComponent(ref)}/answer`, { action, channel }, { observe: 'response' });
  }

  /**
   * Dismisses an incident: a POST of {} (the incident is in the path and the session is the caller's, never in the body). The whole
   * response is observed: 200 is {result: 'done'}; a 4xx or 5xx fails as an HttpErrorResponse whose `error` is the body.
   */
  dismissIncident(ref: string): Observable<HttpResponse<DismissBody>> {
    return this.http.post<DismissBody>(`${BASE}/incidents/${encodeURIComponent(ref)}/dismiss`, {}, { observe: 'response' });
  }

  /**
   * Marks a tell-now notice as handled: a POST of {} for the web chat's press and {"channel":"phone"} for the simulated phone's (the
   * notice is in the path and the session is the caller's, never in the body). The whole response is observed: 200 is
   * {result: 'done', handledAt}; a 4xx or 5xx fails as an HttpErrorResponse whose `error` is the body.
   */
  gotIt(ref: string, channel: 'web' | 'phone' = 'web'): Observable<HttpResponse<GotItBody>> {
    return this.http.post<GotItBody>(`${BASE}/decisions/${encodeURIComponent(ref)}/got-it`, channel === 'phone' ? { channel } : {}, { observe: 'response' });
  }

  /**
   * Presses Break the feed (demo mode only): a POST of {} (the session is the caller's, never in the body). The answer is the run's `startedAt`.
   * A 409 fails as an HttpErrorResponse whose `error` is the body `{"error":{"code","message"}}`, with the code `not_watching` or
   * `incident_in_progress` (break-feed-view.ts's conflictOf reads it); any other failure is passed on as it is.
   */
  breakFeed(): Observable<BreakFeedSent> {
    return this.http.post<BreakFeedSent>(`${BASE}/demo/break-feed`, {});
  }

  /**
   * Asks for a Telegram pairing code (Telegram included only): a POST of {} (the session is the caller's). The answer is the code and its
   * expiry; the code is shown once and stored only as a hash. A 409 `not_available` fails as an HttpErrorResponse whose `error` is the body.
   */
  pairingCode(): Observable<PairingCode> {
    return this.http.post<PairingCode>(`${BASE}/pairing/code`, {});
  }

  /**
   * Unpairs the session's Telegram chat (Telegram included only): a DELETE with the body {}, which the envelope interceptor completes with
   * its headers. The answer is {result: 'done'}, also when nothing was paired.
   */
  unpair(): Observable<UnpairDone> {
    return this.http.delete<UnpairDone>(`${BASE}/pairing`, { body: {} });
  }

  /** The session's documents (an install's, on a local install), newest first: the Documents page's list. */
  documents(): Observable<DocumentsList> {
    return this.http.get<DocumentsList>(`${BASE}/documents`);
  }

  /** The session's own usage over the last 1, 7 or 30 local days, summed into buckets (Story 37.2): the Usage page's read. */
  usage(days: import('./usage-types').UsageDays): Observable<import('./usage-types').UsageResponse> {
    return this.http.get<import('./usage-types').UsageResponse>(`${BASE}/usage`, { params: { days } });
  }

  /**
   * One page of the session's own past decisions (Story 25.2): the Decisions tab's read. Only the filters that are set are sent. A page past the
   * last is 200 with an empty list; a 404 for a value the route does not take and a 500 fail as an HttpErrorResponse.
   */
  historyDecisions(filters: HistoryFilters & { page: number }): Observable<HistoryDecisionsResponse> {
    const params: Record<string, string> = {};
    for (const key of ['outcome', 'channel', 'day', 'fallback'] as const) {
      const value = filters[key];
      if (value !== undefined && value !== '') {
        params[key] = value;
      }
    }
    params['page'] = String(filters.page);
    return this.http.get<HistoryDecisionsResponse>(`${BASE}/history/decisions`, { params });
  }

  /** One page of the incidents the session sees (Story 25.2): the Incidents tab's read. */
  historyIncidents(page: number): Observable<HistoryIncidentsResponse> {
    return this.http.get<HistoryIncidentsResponse>(`${BASE}/history/incidents`, { params: { page: String(page) } });
  }

  /**
   * Adds one document: a POST of {name, content}, the file's bytes in base64 (the session is the caller's, never in the body). The answer is
   * {result: 'done', ref}; a 400 `bad_document` (with its `reason`), a 413, a 501 and a 500 fail as an HttpErrorResponse whose `error` is
   * the body (DocumentRefusal).
   */
  addDocument(name: string, content: string): Observable<DocumentAdded> {
    return this.http.post<DocumentAdded>(`${BASE}/documents`, { name, content });
  }

  /**
   * One document's text: a GET of /v1/documents/:ref, 200 {ref, name, text}. A 404 for a document that the session cannot see (also one that
   * was removed), and a 500, fail as an HttpErrorResponse.
   */
  documentText(ref: string): Observable<DocumentText> {
    return this.http.get<DocumentText>(`${BASE}/documents/${encodeURIComponent(ref)}`);
  }

  /**
   * Removes one document: a DELETE with the body {}, which the envelope interceptor completes with its headers. The answer is
   * {result: 'done'}; a 404 for a document that the session cannot see, a 501 and a 500 fail as an HttpErrorResponse.
   */
  removeDocument(ref: string): Observable<DocumentRemoved> {
    return this.http.delete<DocumentRemoved>(`${BASE}/documents/${encodeURIComponent(ref)}`, { body: {} });
  }

  /**
   * The online demo's public status in its trace form (Story 16.5, 29.7; AD-13, AD-25): a GET of /ocutalon/public/status?for=trace, which
   * needs no session and whose busy comes from the connection check alone, with a unique query so that no cache answers.
   * DemoBusyState's trace check and its quiet re-check read it.
   */
  publicStatus(): Observable<PublicStatus> {
    return this.http.get<PublicStatus>(`${PUBLIC_STATUS}?for=trace&t=${Date.now()}`);
  }

  /** A POST whose only success is the answer 202 with a body; any other status, a 2xx included, fails as an error. */
  private accepted<T>(url: string, body: object): Observable<T> {
    return this.http.post<T>(url, body, { observe: 'response' }).pipe(
      map((response) => {
        if (response.status !== 202 || response.body === null) {
          throw new HttpErrorResponse({ status: response.status, statusText: response.statusText, url: response.url ?? url });
        }
        return response.body;
      }),
    );
  }

  /** The events after the two cursors, one for the session's stream and one for the instance's. */
  events(after: number, afterInstance: number): Observable<EventsResponse> {
    return this.http.get<EventsResponse>(`${BASE}/events`, { params: { after, afterInstance } });
  }

  /** The signed-in session's persona (Story 40.8): the preset, the language, the person's own words, whether those are offered, and a pending proposal's Ref. */
  persona(): Observable<PersonaState> {
    return this.http.get<PersonaState>(`${BASE}/persona`);
  }

  /** Saves the persona: a PUT, which the envelope interceptor completes with its headers. A refusal fails as an HttpErrorResponse whose `error` is the body `{error:{code,message}}`. */
  savePersona(body: PersonaPut): Observable<PersonaSaved> {
    return this.http.put<PersonaSaved>(`${BASE}/persona`, body);
  }

  /** The signed-in session's heartbeat (Story 39.5): its settings, last check-in and skip, today's count and cost, the checklist and whether this is the online demo. */
  heartbeat(): Observable<HeartbeatState> {
    return this.http.get<HeartbeatState>(`${BASE}/heartbeat`);
  }

  /** Saves the heartbeat: a PUT, which the envelope interceptor completes with its headers. A refusal fails as an HttpErrorResponse whose `error` is the body `{error:{code,message}}`. */
  saveHeartbeat(body: HeartbeatPut): Observable<HeartbeatSaved> {
    return this.http.put<HeartbeatSaved>(`${BASE}/heartbeat`, body);
  }

  /** Asks for a beat now: a POST with an empty body (the envelope interceptor completes it). A 409 fails with the body `{error:{code,message},availableAt?}`. */
  runHeartbeat(): Observable<unknown> {
    return this.http.post<unknown>(`${BASE}/heartbeat/run`, {});
  }

  /** Marks the person's own tell-now notice as noise (Story 41.5): a POST of the channel the press came from. A refusal fails as an HttpErrorResponse whose `error` is the body `{error:{code,message}}`. */
  markNoise(ref: string, channel: import('./memory-types').NoiseChannel): Observable<import('./memory-types').NoiseMarked> {
    return this.http.post<import('./memory-types').NoiseMarked>(`${BASE}/decisions/${encodeURIComponent(ref)}/noise`, { channel });
  }

  /** The session's daily note for a day (Story 41.6): a GET of /memory/notes?day=today|yesterday; the lines are the server's own. */
  memoryNotes(day: import('./memory-card-types').MemoryDay): Observable<import('./memory-card-types').MemoryNotes> {
    return this.http.get<import('./memory-card-types').MemoryNotes>(`${BASE}/memory/notes`, { params: { day } });
  }

  /** The session's own precedents, newest first (Story 41.6): a GET of /memory/precedents; the server never lists another session's or a seeded row. */
  precedents(): Observable<import('./memory-card-types').PrecedentList> {
    return this.http.get<import('./memory-card-types').PrecedentList>(`${BASE}/memory/precedents`);
  }

  /**
   * Forgets one precedent (Story 41.6): a DELETE with the body {}, which the envelope interceptor completes with its headers. The answer is
   * {result: 'done'}; a 404 for a row that the session cannot see, a 501 and a 500 fail as an HttpErrorResponse.
   */
  forgetPrecedent(ref: string): Observable<import('./memory-card-types').PrecedentForgotten> {
    return this.http.delete<import('./memory-card-types').PrecedentForgotten>(`${BASE}/memory/precedents/${encodeURIComponent(ref)}`, { body: {} });
  }

  /**
   * The session's memories (Story 41.13): a GET of /memory/items, the newest 20 with no query, or with `?q=` (sent only when not blank) the best 5. A search
   * that has no answer in time fails as a 503 whose body error.code is `search_busy`; on the online demo one past the allowance fails as a 429.
   */
  memoryItems(q?: string): Observable<import('./memory-card-types').MemoryItems> {
    const query = (q ?? '').trim();
    return this.http.get<import('./memory-card-types').MemoryItems>(`${BASE}/memory/items`, query === '' ? {} : { params: { q: query } });
  }

  /** The session's pinned memories, newest pin first, and the tokens they use (Story 41.13): a GET of /memory/pinned. */
  pinnedMemories(): Observable<import('./memory-card-types').PinnedMemories> {
    return this.http.get<import('./memory-card-types').PinnedMemories>(`${BASE}/memory/pinned`);
  }

  /** Pins one memory (Story 41.13): a POST with the body {}. A 409 `over_cap` fails as an HttpErrorResponse; so does a 404 for a memory that is gone. */
  pinMemory(ref: string): Observable<import('./memory-card-types').MemoryDone> {
    return this.http.post<import('./memory-card-types').MemoryDone>(`${BASE}/memory/${encodeURIComponent(ref)}/pin`, {});
  }

  /** Unpins one memory (Story 41.13): a DELETE with the body {}. */
  unpinMemory(ref: string): Observable<import('./memory-card-types').MemoryDone> {
    return this.http.delete<import('./memory-card-types').MemoryDone>(`${BASE}/memory/${encodeURIComponent(ref)}/pin`, { body: {} });
  }

  /** Forgets one memory (Story 41.13): a DELETE with the body {}; its pin and search entries go with it. A 404 means it is already gone. */
  forgetMemory(ref: string): Observable<import('./memory-card-types').MemoryDone> {
    return this.http.delete<import('./memory-card-types').MemoryDone>(`${BASE}/memory/items/${encodeURIComponent(ref)}`, { body: {} });
  }
}
