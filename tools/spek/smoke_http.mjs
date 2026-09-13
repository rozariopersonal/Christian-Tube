async function tryPost(label, body) {
  const t0 = Date.now();
  try {
    const r = await fetch('http://localhost:11434/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const txt = await r.text();
    console.log(label, 'OK', r.status, txt.slice(0, 80), Math.round((Date.now() - t0) / 1000) + 's');
  } catch (e) {
    console.log(label, 'FAIL', e.cause?.code || e.cause?.message || e.message, Math.round((Date.now() - t0) / 1000) + 's');
  }
}
const tiny = { model: 'qwen3:14b', messages: [{ role: 'user', content: 'say ok' }], stream: false, options: { num_ctx: 4096 } };
const big = { model: 'qwen3:14b', messages: [{ role: 'user', content: 'Write a very long essay about the history of the world until you reach at least 5000 words. Some Lorem ipsum padding included ' + 'x'.repeat(20000) }], stream: false, options: { num_ctx: 16384 } };
await tryPost('tiny ', tiny);
await tryPost('big  ', big);