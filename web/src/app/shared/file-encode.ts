/** The file's bytes in base64, with no data-URL prefix. */
export function encode(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => resolve(String(reader.result).replace(/^[^,]*,/, ''));
    reader.readAsDataURL(file);
  });
}
