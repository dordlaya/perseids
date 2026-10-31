/**
 * Cloudflare Worker — Perseids frontend
 *
 * All requests are handled by Workers Assets, which serves the Flutter web
 * build from ../../frontend/build/web. Any path not matched by a real file
 * automatically falls back to index.html, which is correct for Flutter's
 * client-side router.
 *
 * The Go backend (API + WebSocket) lives on a separate origin; the browser
 * connects directly to it — this Worker is static-hosting only.
 */
export default {
  async fetch(request, env) {
    return env.ASSETS.fetch(request);
  },
};

