/// Browser-side calls to the dashboard's own `/api/admin/*` pass-through. Throws the API's
/// `user_message` (already unwrapped by `proxy()`), so a screen shows the server's words.
export async function call<T>(
  path: string,
  init: { method?: string; body?: unknown; totp?: string; reason?: string } = {},
): Promise<T> {
  const headers: Record<string, string> = {};
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';
  if (init.totp) headers['x-totp'] = init.totp;
  if (init.reason) headers['x-reason'] = init.reason;

  const res = await fetch(`/api/admin/${path.replace(/^\/+/, '')}`, {
    method: init.method ?? 'GET',
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const data = (await res.json().catch(() => ({}))) as T & { error?: string };
  if (res.status === 401) window.location.href = '/login';
  if (!res.ok) throw new Error(data.error ?? `Request failed (${res.status}).`);
  return data;
}

export function errorText(e: unknown, fallback: string): string {
  return e instanceof Error ? e.message : fallback;
}
