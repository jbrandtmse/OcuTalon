// The health check of the CI model mock's container: GET http://127.0.0.1:8080/_mock/health with a 1.5 s limit.
// Exits 0 when the mock answers 200 with {"ok":true}, and 1 otherwise.

try {
  const res = await fetch('http://127.0.0.1:8080/_mock/health', { signal: AbortSignal.timeout(1500) });
  const body = await res.json();
  process.exit(res.status === 200 && body.ok === true ? 0 : 1);
} catch {
  process.exit(1);
}
