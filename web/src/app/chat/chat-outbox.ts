import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { timeout } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { LiveState } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { BUSY_TIMEOUT_MS } from '../shared/busy-state';
import { CHAT_TEXTS, newClientId, type OutboxEntry, type OutboxStatus } from './chat-view';

/**
 * The messages this page sent (AD-30, AD-4). send() makes a local entry with a new clientId and posts it at once; the body
 * names no session. The entry is sent when the server answers 202, and failed on any other answer: a network error, another
 * status, or no answer within BUSY_TIMEOUT_MS. A 401 is SessionGate's. retry() posts a failed entry again with the same
 * clientId and text, which the server dedups, so a send that did reach it is not queued twice. An entry leaves as soon as the
 * live store holds a chat.message with its clientId, whatever its status. The outbox lives in the page: a reload drops it.
 * Each post that fails is announced once, "Message not sent" (UX-DR132), while the page still shows the message as unsent: a
 * failure that comes after the live store holds the message says nothing, because the page shows it as sent. A retry that fails
 * is a new failure, and a 401 is the session gate's and says nothing here.
 */
@Injectable({ providedIn: 'root' })
export class ChatOutbox {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly announcer = inject(Announcer);
  private readonly list = signal<readonly OutboxEntry[]>([]);

  private readonly sends = signal(0);

  /** The messages that the store does not hold yet, in send order. */
  readonly entries = this.list.asReadonly();

  /** How many new messages this page has sent (a retry is not one): a view that follows the user's own sends watches it. */
  readonly sendCount = this.sends.asReadonly();

  constructor() {
    effect(() => {
      const chat = this.live.store()?.chat ?? [];
      const held = new Set<string>();
      for (const item of chat) {
        if (item.type === 'chat.message' && item.payload.clientId) {
          held.add(item.payload.clientId);
        }
      }
      untracked(() => {
        if (this.list().some((entry) => held.has(entry.clientId))) {
          this.list.update((entries) => entries.filter((entry) => !held.has(entry.clientId)));
        }
      });
    });
  }

  /** Sends the trimmed text as a new message; returns false, and sends nothing, when the text is empty. */
  send(text: string, fromGuide = false): boolean {
    const trimmed = text.trim();
    if (trimmed === '') {
      return false;
    }
    const entry: OutboxEntry = { clientId: newClientId(), text: trimmed, fromGuide, sentAt: new Date().toISOString(), status: 'sending' };
    this.list.update((entries) => [...entries, entry]);
    this.sends.update((count) => count + 1);
    this.post(entry);
    return true;
  }

  /** Posts a failed message again with the same clientId. */
  retry(clientId: string): void {
    const entry = this.list().find((candidate) => candidate.clientId === clientId);
    if (entry === undefined || entry.status !== 'failed') {
      return;
    }
    this.mark(clientId, 'sending');
    this.post(entry);
  }

  private post(entry: OutboxEntry): void {
    this.api
      .postMessage({ clientId: entry.clientId, text: entry.text, fromGuide: entry.fromGuide })
      .pipe(timeout(BUSY_TIMEOUT_MS))
      .subscribe({
        next: () => this.mark(entry.clientId, 'sent'),
        error: (error: unknown) => {
          if (!(error instanceof HttpErrorResponse && error.status === 401)) {
            const unsent = this.list().some((candidate) => candidate.clientId === entry.clientId);
            this.mark(entry.clientId, 'failed');
            if (unsent) {
              this.announcer.announce(CHAT_TEXTS.messageNotSent);
            }
          }
        },
      });
  }

  private mark(clientId: string, status: OutboxStatus): void {
    this.list.update((entries) => entries.map((entry) => (entry.clientId === clientId ? { ...entry, status } : entry)));
  }
}
