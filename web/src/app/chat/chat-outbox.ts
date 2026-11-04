import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { timeout } from 'rxjs';

import { ApiClient } from '../api/api-client';
import { AllowanceState } from '../live/allowance-state';
import { refusalOf } from '../live/allowance-view';
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
 * failure that comes after the live store holds the message says nothing, because the page shows it as sent (the store is read at
 * the failure itself, not the entry list, which follows the store a render later). A retry that fails
 * is a new failure, and a 401 is the session gate's and says nothing here.
 * On the online demo a 503 is the busy state, not a failure (Story 16.5): a typed message's text is offered back to the composer
 * (takeBackTo), which takes it only while its field is empty, and the entry leaves the chat; a guide prompt's entry just leaves; when
 * the composer holds other text, or none is on the page, the entry stays failed as today. None of these says "Message not sent"
 * except that last one.
 * A 429 whose error code is `allowance` (Story 16.9; the session's message allowance) is handled the same way, after the page learns
 * the window from it (AllowanceState.refused): the typed text goes back to an empty composer, a guide prompt's entry just leaves, and
 * when the composer holds other text the entry fails as today ("Message not sent"). The refusal never reaches the chat as a message.
 */
@Injectable({ providedIn: 'root' })
export class ChatOutbox {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly allowance = inject(AllowanceState);
  private readonly announcer = inject(Announcer);
  private readonly list = signal<readonly OutboxEntry[]>([]);

  private readonly sends = signal(0);

  /** The composer's offer to take a refused message's text back: true when it took it. */
  private takeBack: ((text: string) => boolean) | undefined;

  /** The messages that the store does not hold yet, in send order. */
  readonly entries = this.list.asReadonly();

  /** How many new messages this page has sent (a retry is not one): a view that follows the user's own sends watches it. */
  readonly sendCount = this.sends.asReadonly();

  constructor() {
    effect(() => {
      const held = this.held();
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

  /** The composer registers how it takes a refused message's text back; the returned function removes the registration. */
  takeBackTo(taker: (text: string) => boolean): () => void {
    this.takeBack = taker;
    return () => {
      if (this.takeBack === taker) {
        this.takeBack = undefined;
      }
    };
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
          if (error instanceof HttpErrorResponse && error.status === 503 && this.live.snapshot()?.onlineDemo === true && this.refuse(entry)) {
            return;
          }
          const refusal = refusalOf(error, 'allowance');
          if (refusal !== undefined) {
            this.allowance.refused(refusal);
            if (this.refuse(entry)) {
              return;
            }
          }
          if (!(error instanceof HttpErrorResponse && error.status === 401)) {
            const unsent = !this.held().has(entry.clientId) && this.list().some((candidate) => candidate.clientId === entry.clientId);
            this.mark(entry.clientId, 'failed');
            if (unsent) {
              this.announcer.announce(CHAT_TEXTS.messageNotSent);
            }
          }
        },
      });
  }

  /**
   * The online demo's 503 rule, also the 429 allowance rule: a guide prompt's entry leaves, and a typed message's entry leaves when the composer takes its text back.
   * True when the entry left (so nothing is announced); false leaves the entry to fail as today.
   */
  private refuse(entry: OutboxEntry): boolean {
    if (!this.list().some((candidate) => candidate.clientId === entry.clientId)) {
      return false;
    }
    if (!entry.fromGuide && this.takeBack?.(entry.text) !== true) {
      return false;
    }
    this.list.update((entries) => entries.filter((candidate) => candidate.clientId !== entry.clientId));
    return true;
  }

  /** The clientIds of the chat.message entries that the live store holds: the messages the page shows as sent (chatView). */
  private held(): Set<string> {
    const held = new Set<string>();
    for (const item of this.live.store()?.chat ?? []) {
      if (item.type === 'chat.message' && item.payload.clientId) {
        held.add(item.payload.clientId);
      }
    }
    return held;
  }

  private mark(clientId: string, status: OutboxStatus): void {
    this.list.update((entries) => entries.map((entry) => (entry.clientId === clientId ? { ...entry, status } : entry)));
  }
}
