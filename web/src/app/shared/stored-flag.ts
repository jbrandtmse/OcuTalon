/** Whether the storage holds the value under the key; false when it does not or cannot be read. */
export function readFlag(open: () => Storage, key: string, value: string): boolean {
  try {
    return open().getItem(key) === value;
  } catch {
    return false;
  }
}

/** Stores the value under the key; a storage that fails leaves the flag to the page's own memory. */
export function writeFlag(open: () => Storage, key: string, value: string): void {
  try {
    open().setItem(key, value);
  } catch {
    /* The flag holds for this page only. */
  }
}

/** The text stored under the key; empty when there is none or the storage cannot be read. */
export function readText(open: () => Storage, key: string): string {
  try {
    return open().getItem(key) ?? '';
  } catch {
    return '';
  }
}
