#!/bin/bash
set -e

INSTANCE_ID="${INSTANCE_ID:-christian_tube}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/apps/web"
WEB_BUILD="$WEB_DIR/dist/web/browser"
WELL_KNOWN_SRC="$ROOT_DIR/apps/mobile/web/.well-known"
OUTPUT_DIR="$ROOT_DIR/.vercel/output"

echo "==> Building Angular web for instance: $INSTANCE_ID"

# Determine target API base URL:
# - Explicit API_BASE_URL env var wins
# - Otherwise, if Vercel preview / develop branch and STAGING_API_BASE_URL is set, use it
# - Fallback to staging URL on develop branch if not production
EFFECTIVE_API_URL="${API_BASE_URL:-}"
if [ -z "$EFFECTIVE_API_URL" ] && [ "${VERCEL_ENV:-}" != "production" ]; then
  if [ -n "${STAGING_API_BASE_URL:-}" ]; then
    EFFECTIVE_API_URL="$STAGING_API_BASE_URL"
  elif [ "${VERCEL_GIT_COMMIT_REF:-}" = "develop" ]; then
    EFFECTIVE_API_URL="https://christianapp-test.onrender.com"
  fi
fi

APP_CONFIG_TS="$WEB_DIR/src/app/core/config/app-config.ts"
RESTORE_CONFIG=0
if [ -n "$EFFECTIVE_API_URL" ] && [ -f "$APP_CONFIG_TS" ]; then
  echo "==> Patching Angular AppConfig.apiBaseUrl -> $EFFECTIVE_API_URL"
  cp "$APP_CONFIG_TS" "$APP_CONFIG_TS.bak"
  RESTORE_CONFIG=1
  node -e "
    const fs = require('fs');
    const p = process.argv[1];
    const url = process.argv[2];
    const orig = fs.readFileSync(p, 'utf8');
    const next = orig.replace(/(apiBaseUrl:[^\n]*)'https:\/\/[^']*'/, \"\$1'\" + url + \"'\");
    if (next === orig) {
      console.error('Failed to patch apiBaseUrl in', p);
      process.exit(1);
    }
    fs.writeFileSync(p, next, 'utf8');
  " "$APP_CONFIG_TS" "$EFFECTIVE_API_URL"
fi

cleanup_config() {
  if [ "$RESTORE_CONFIG" -eq 1 ] && [ -f "$APP_CONFIG_TS.bak" ]; then
    mv "$APP_CONFIG_TS.bak" "$APP_CONFIG_TS"
  fi
}
trap cleanup_config EXIT

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
