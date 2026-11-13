import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import type { SentFile } from '../live/payloads';
import { fileLine } from './files-view';

/**
 * The file a message carries (Story 25.3): a chip with the file's name and size as text, never as HTML (AD-13). It is the user's message when the
 * message has no text. The name wraps anywhere, so a long one never widens the chat.
 */
@Component({
  selector: 'app-file-chip',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="chip" data-part="file">
      <svg class="icon" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
        <path d="M14 3v5h5" />
      </svg>
      <span class="line">{{ line() }}</span>
    </div>
  `,
  styles: `
    :host {
      display: block;
      max-width: min(80%, calc(var(--chat-panel-text-max) + 2 * var(--space-3)));
    }
    .chip {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      padding: var(--space-2) var(--space-3);
      background: var(--chat-message-user-background);
      color: var(--chat-message-user-foreground);
      border-radius: var(--chat-message-user-radius);
      font-size: var(--chat-message-user-typography-font-size);
      font-weight: var(--chat-message-user-typography-font-weight);
      line-height: var(--chat-message-user-typography-line-height);
    }
    .icon {
      flex: none;
    }
    .line {
      overflow-wrap: anywhere;
    }
  `,
})
export class FileChip {
  readonly file = input.required<SentFile>();

  protected readonly line = computed(() => fileLine(this.file().name ?? '', this.file().size ?? 0));
}
