import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { Icon } from '../icon/icon';
import { PAGE_TEXTS, renderPageText } from '../msg/catalog';
import { CHAT_TEXTS, type TurnView } from './chat-view';
import { parseReply, type ReplyBlock } from './reply-text';

/** The catalog key of the sentence for a fallback reply whose own key the page does not render. */
const FALLBACK_KEY = 'conversation.turnFallback';

/**
 * OcuTalon's side of a turn, in the reply's place (UX-DR60, UX-DR66, UX-DR42, AD-13). While the turn is in progress it is the
 * turn indicator, a row with the 24px mark and "Deciding" or "Working" followed by the one-character ellipsis U+2026 (after 10 s
 * the whole seconds instead): the ellipsis is revealed in three steps unless the user prefers reduced motion. Once the turn is done it is the
 * reply, left-aligned and unboxed under the mark and the name "OcuTalon": the catalog's fallback sentence for a fallback, else
 * the model's text as paragraphs and lists. The model's text is bound by interpolation and `[href]` only, never as HTML; its
 * links open in a new tab and say so in their names, and a labelled link shows the host it opens after its label. Nothing here is a live region, and the element takes focus only when the
 * New messages button sends it there.
 */
@Component({
  selector: 'app-ocutalon-reply',
  imports: [Icon, NgTemplateOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (turn().reply.kind !== 'none') {
      <div class="reply" data-part="reply" [attr.data-key]="turn().key" tabindex="-1">
        @if (indicator(); as shown) {
          <p class="indicator">
            <img class="mark" src="assets/brand/icon-192.png" alt="" width="24" height="24" />
            <span>
              @if (shown.seconds === undefined) {
                <span>{{ shown.text }}</span><span class="dots">{{ ellipsis }}</span>
              } @else {
                <span aria-hidden="true">{{ shown.text }}</span><span class="visually-hidden">{{ shown.spoken }}</span>
              }
            </span>
          </p>
        } @else {
          <div class="head">
            <img class="mark" src="assets/brand/icon-192.png" alt="" width="24" height="24" />
            <span class="name">{{ texts.name }}</span>
          </div>
          <div class="text">
            @if (fallback(); as sentence) {
              <p class="para">{{ sentence }}</p>
            } @else {
              @for (block of blocks(); track $index) {
                @if (block.kind === 'paragraph') {
                  <p class="para">
                    <ng-container [ngTemplateOutlet]="runs" [ngTemplateOutletContext]="{ $implicit: block.runs }" />
                  </p>
                } @else if (block.ordered) {
                  <ol class="list" [attr.start]="block.start">
                    @for (item of block.items; track $index) {
                      <li><ng-container [ngTemplateOutlet]="runs" [ngTemplateOutletContext]="{ $implicit: item }" /></li>
                    }
                  </ol>
                } @else {
                  <ul class="list">
                    @for (item of block.items; track $index) {
                      <li><ng-container [ngTemplateOutlet]="runs" [ngTemplateOutletContext]="{ $implicit: item }" /></li>
                    }
                  </ul>
                }
              }
            }
          </div>
        }
      </div>
    }
    <ng-template #runs let-list>
      @for (run of list; track $index) {
        @if (run.kind === 'link') {
          <a class="link" [href]="run.href" target="_blank" rel="noopener noreferrer"
            >{{ run.label }}@if (run.host) {<span class="host"> ({{ run.host }})</span>}<app-icon name="external-link" [size]="12" /><span class="visually-hidden"> {{ texts.opensInNewTab }}</span></a
          >
        } @else {
          <span>{{ run.text }}</span>
        }
      }
    </ng-template>
  `,
  styles: `
    :host {
      display: block;
    }
    .reply {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .head,
    .indicator {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      margin: 0;
    }
    .mark {
      display: block;
      flex: none;
      width: var(--chat-message-ocutalon-avatar-size);
      height: var(--chat-message-ocutalon-avatar-size);
    }
    .name {
      color: var(--ink);
      font-size: var(--type-body-strong-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-strong-line-height);
    }
    .indicator {
      color: var(--turn-indicator-foreground);
      font-size: var(--turn-indicator-typography-font-size);
      font-weight: var(--turn-indicator-typography-font-weight);
      line-height: var(--turn-indicator-typography-line-height);
    }
    .dots {
      display: inline-block;
      animation: reveal 1.2s steps(3, start) infinite;
    }
    @keyframes reveal {
      from {
        clip-path: inset(0 100% 0 0);
      }
      to {
        clip-path: inset(0 0 0 0);
      }
    }
    @media (prefers-reduced-motion: reduce) {
      .dots {
        animation: none;
      }
    }
    .text {
      max-width: var(--chat-panel-text-max);
      color: var(--chat-message-ocutalon-foreground);
      font-size: var(--chat-message-ocutalon-typography-font-size);
      font-weight: var(--chat-message-ocutalon-typography-font-weight);
      line-height: var(--chat-message-ocutalon-typography-line-height);
      overflow-wrap: anywhere;
    }
    .para {
      margin: 0;
      white-space: pre-wrap;
    }
    .para + .para,
    .para + .list,
    .list + .para,
    .list + .list {
      margin-top: var(--space-2);
    }
    .list {
      margin: 0;
      padding-left: var(--space-6);
    }
    .link {
      display: inline;
    }
    .link app-icon {
      margin: 0 0 0 var(--space-1);
      vertical-align: -1px;
    }
  `,
})
export class OcutalonReply {
  readonly turn = input.required<TurnView>();
  protected readonly texts = CHAT_TEXTS;
  /** The one-character ellipsis that ends "Deciding" and "Working" in CHAT_TEXTS. */
  protected readonly ellipsis = CHAT_TEXTS.deciding.slice(-1);

  /** The indicator while the turn is in progress, with its spoken form and, once past 10 s, the whole seconds. */
  protected readonly indicator = computed(() => {
    const reply = this.turn().reply;
    if (reply.kind === 'deciding') {
      return { text: CHAT_TEXTS.deciding.slice(0, -1), spoken: CHAT_TEXTS.deciding, seconds: undefined };
    }
    if (reply.kind !== 'working') {
      return undefined;
    }
    if (reply.seconds === undefined) {
      return { text: CHAT_TEXTS.working.slice(0, -1), spoken: CHAT_TEXTS.working, seconds: undefined };
    }
    const n = String(reply.seconds);
    return { text: CHAT_TEXTS.workingElapsed.replace('{n}', n), spoken: CHAT_TEXTS.workingElapsedSpoken.replace('{n}', n), seconds: reply.seconds };
  });

  /** A fallback's sentence from the catalog; a key that the page does not render gives the turn fallback's sentence with the turn's own reason. */
  protected readonly fallback = computed(() => {
    const reply = this.turn().reply;
    if (reply.kind !== 'fallback') {
      return undefined;
    }
    const key = Object.hasOwn(PAGE_TEXTS, reply.catalogKey) ? reply.catalogKey : FALLBACK_KEY;
    return renderPageText(key, { fallbackReason: reply.fallbackReason });
  });

  protected readonly blocks = computed<ReplyBlock[]>(() => {
    const reply = this.turn().reply;
    return reply.kind === 'text' ? parseReply(reply.replyText) : [];
  });
}

