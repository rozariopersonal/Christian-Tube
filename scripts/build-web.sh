#!/bin/bash
set -e

INSTANCE_ID="${INSTANCE_ID:-christian_tube}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/apps/web"
WEB_BUILD="$WEB_DIR/dist/web/browser"
WELL_KNOWN_SRC="$ROOT_DIR/apps/mobile/web/.well-known"
OUTPUT_DIR="$ROOT_DIR/.vercel/output"

echo "==> Building Angular web for instance: $INSTANCE_ID"

cd "$WEB_DIR"
npm ci
npm run build

# Copy well-known deep-link verification files if present (App Links / Universal Links)
if [ -d "$WELL_KNOWN_SRC" ]; then
  echo "==> Copying .well-known (deep-link verification) assets"
  mkdir -p "$WEB_BUILD/.well-known"
  cp -R "$WELL_KNOWN_SRC/." "$WEB_BUILD/.well-known/" 2>/dev/null || cp -R "$WELL_KNOWN_SRC" "$WEB_BUILD/"
fi

# ---------------------------------------------------------------
# Assemble the Vercel Build Output API directory.
# static/       -> Angular web build (served as-is)
# functions/*.func -> serverless functions (Open Graph resolver)
# config.json   -> routing (SPA fallback + deep-link -> OG)
# ---------------------------------------------------------------
echo "==> Assembling Vercel Build Output (.vercel/output)"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/static"
mkdir -p "$OUTPUT_DIR/functions/og.func"

cp -R "$WEB_BUILD/." "$OUTPUT_DIR/static/"
cp "$ROOT_DIR/serverless/og.js" "$OUTPUT_DIR/functions/og.func/index.js"
cat > "$OUTPUT_DIR/functions/og.func/.vc-config.json" <<'VC'
{
  "runtime": "edge",
  "entrypoint": "index.js"
}
VC

cat > "$OUTPUT_DIR/config.json" <<'CONFIG'
{
  "version": 3,
  "headers": [
    {
      "source": "/index.html",
      "headers": [{ "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }]
    },
    {
      "source": "/(.*\\.(?:js|css))",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "/.well-known/(.*)",
      "headers": [{ "key": "Cache-Control", "value": "no-cache, max-age=0" }]
    }
  ],
  "routes": [
    { "src": "/watch(.*)", "dest": "/og?u=/watch$1" },
    { "src": "/shorts(.*)", "dest": "/og?u=/shorts$1" },
    { "src": "/article(.*)", "dest": "/og?u=/article$1" },
    { "src": "/books(.*)", "dest": "/og?u=/books$1" },
    { "src": "/song(.*)", "dest": "/og?u=/song$1" },
    { "src": "/audio(.*)", "dest": "/og?u=/audio$1" },
    { "src": "/bible(.*)", "dest": "/og?u=/bible$1" },
    { "src": "/feed", "dest": "/og?u=/feed" },
    { "handle": "filesystem" },
    { "src": "/.*", "dest": "/index.html" }
  ]
}
CONFIG

echo "==> Build complete: $OUTPUT_DIR"
