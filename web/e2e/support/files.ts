import type { JSHandle, Locator, Page } from '@playwright/test';

/**
 * What the specs that send or drop files share: the drag helpers (a dispatched drag event, and a transfer that carries a PDF) and a done chat.message as a
 * stubbed snapshot holds it (changeSnapshot). files.spec.ts and viewer.spec.ts use them.
 */

/** Dispatches a drag event of that type with the transfer on the element and says whether a handler took it: true when one cancelled the browser's own handling. */
export async function taken(target: Locator, type: 'dragover' | 'drop', transfer: JSHandle<DataTransfer>): Promise<boolean> {
  return target.evaluate(
    (element, [kind, data]) => {
      const event = new DragEvent(kind, { bubbles: true, cancelable: true, dataTransfer: data });
      element.dispatchEvent(event);
      return event.defaultPrevented;
    },
    [type, transfer] as const,
  );
}

/** A transfer that carries one PDF file of that name, as a drag of a file from the desktop does. */
export async function fileTransfer(page: Page, name: string): Promise<JSHandle<DataTransfer>> {
  return page.evaluateHandle((fileName) => {
    const data = new DataTransfer();
    data.items.add(new File(['%PDF-1.4 dropped'], fileName, { type: 'application/pdf' }));
    return data;
  }, name);
}

/** A done chat.message for the stubbed snapshots, with the members that the case sets. */
export function chatItem(over: Record<string, unknown>): { type: string; payload: Record<string, unknown> } {
  return {
    type: 'chat.message',
    payload: {
      ref: 'zzStubTurn0000000000c',
      clientId: 'zzstubclient',
      channel: 'web',
      fromGuide: false,
      state: 'done',
      text: '',
      replyText: 'The CI mock read the file you sent.',
      createdAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
      ...over,
    },
  };
}
