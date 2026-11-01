/** JSON whitespace keeps URLSession's inactivity timer alive without changing its decoder.
 * Fast responses retain their HTTP status. Once streaming starts, late failures also
 * carry the legacy app's reply/intake fields because headers can no longer change.
 */
export async function jsonKeepalive(work: () => Promise<Response>, headers: Record<string, string>, intervalMs = 10_000): Promise<Response> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const result = work();
  const first = await Promise.race([result, new Promise<null>(resolve => { timer = setTimeout(() => resolve(null), intervalMs); })]);
  clearTimeout(timer);
  if (first) return first;
  let stopped = false;
  let heartbeat: ReturnType<typeof setInterval>;
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = (text: string) => { if (!stopped) controller.enqueue(encoder.encode(text)); };
      send(' '.repeat(2048) + '\n');
      heartbeat = setInterval(() => send(' '.repeat(2048) + '\n'), intervalMs);
      void result.then(async response => {
        let body = await response.text();
        if (!response.ok) {
          const failure = JSON.parse(body);
          body = JSON.stringify({ ...failure, reply: failure.error ?? 'The estimate could not be completed. Please try again.', turn_stage: 'intake', structured_estimate: null, http_status: response.status });
        }
        send(body);
        if (!stopped) controller.close();
      }).catch(() => {
        send(JSON.stringify({ error: 'The estimate could not be completed. Please try again.', reply: 'The estimate could not be completed. Please try again.', turn_stage: 'intake', structured_estimate: null }));
        if (!stopped) controller.close();
      }).finally(() => { stopped = true; clearInterval(heartbeat); });
    },
    cancel() { stopped = true; clearInterval(heartbeat); },
  });
  return new Response(stream, { headers: { ...headers, 'Content-Type': 'application/json', 'Cache-Control': 'no-store, no-transform', 'X-Accel-Buffering': 'no' } });
}
