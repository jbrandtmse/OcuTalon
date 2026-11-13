import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { FileRefusal } from '../api/api-types';
import { LiveState } from '../live/live-state';
import { Announcer } from '../shared/announcer';
import { encode } from '../shared/file-encode';
import { newClientId } from './chat-view';
import { checkFile, fileControls, FILES_TEXTS, refusalText } from './files-view';

/**
 * Sending a file from the chat (Story 25.3; FR-54, UX-DR129, UX-DR147). The paperclip of the composer and a drop on the chat give their files to
 * add(), which sends them one at a time: each is checked by checkFile first (its size, no bytes, its extension), and a file that fails the check is
 * not sent. A valid one is encoded and posted to POST /v1/files, whose answer decides by the file's bytes: a 400 `bad_file` shows the refusal of its
 * reason (a renamed file that passed the check shows the wrong-type sentence), a 413 the size sentence, a 409 the off-on-the-demo sentence, and any
 * other failure "File not sent". The refusal shows above the composer (`refusal`) and is spoken once through the Announcer. A sent file appears in the
 * chat as the user's message through the live store, like any message; the page keeps no copy of it.
 * `controls` says whether the paperclip shows and what a drop does (files-view.fileControls) from the snapshot's `filesReadable` and `onlineDemo`.
 */
@Injectable({ providedIn: 'root' })
export class ChatFiles {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly announcer = inject(Announcer);

  /** The sentence of the last refusal, shown above the composer; '' while there is none. */
  readonly refusal = signal('');

  /** The paperclip and the drop, from the snapshot: both are off until the snapshot says files can be read, and on the online demo. */
  readonly controls = computed(() => {
    const snapshot = this.live.snapshot();
    return fileControls(snapshot?.filesReadable === true, snapshot?.onlineDemo === true);
  });

  /** Sends the files one after the other. */
  async add(files: readonly File[]): Promise<void> {
    this.refusal.set('');
    for (const file of files) {
      await this.send(file);
    }
  }

  /** Shows the sentence for a drop on the online demo. */
  refuseOnDemo(): void {
    this.refuse(FILES_TEXTS.offOnDemo);
  }

  private async send(file: File): Promise<void> {
    const code = checkFile(file);
    if (code !== '') {
      this.refuse(refusalText(code, file.size));
      return;
    }
    try {
      await firstValueFrom(this.api.sendFile(newClientId(), file.name, await encode(file)));
    } catch (error) {
      this.refuse(this.textOf(error, file.size));
    }
  }

  /** The sentence for a failed post: the server's reason for a 400 `bad_file`, the size for a 413, the demo's for a 409, else "File not sent". */
  private textOf(error: unknown, size: number): string {
    if (error instanceof HttpErrorResponse) {
      const body = error.error as FileRefusal | null;
      if (error.status === 400 && body?.error?.code === 'bad_file' && typeof body.reason === 'string') {
        return refusalText(body.reason, typeof body.size === 'number' ? body.size : size);
      }
      if (error.status === 413) {
        return refusalText('too_large', size);
      }
      if (error.status === 409 && body?.error?.code === 'not_available') {
        return FILES_TEXTS.offOnDemo;
      }
    }
    return FILES_TEXTS.notSent;
  }

  private refuse(text: string): void {
    this.refusal.set(text);
    this.announcer.announce(text);
  }
}
