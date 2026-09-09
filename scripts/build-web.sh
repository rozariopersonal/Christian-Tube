#!/bin/bash
set -e

INSTANCE_ID="${INSTANCE_ID:-christian_tube}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.1}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_DIR="$ROOT_DIR/.flutter-sdk"
APP_DIR="$ROOT_DIR/apps/mobile"
WEB_BUILD="$APP_DIR/build/web"
OUTPUT_DIR="$ROOT_DIR/.vercel/output"

echo "==> Building Flutter web for instance: $INSTANCE_ID"

# Install Flutter SDK if not cached
if [ ! -d "$FLUTTER_DIR" ]; then
  echo "==> Downloading Flutter $FLUTTER_VERSION ($FLUTTER_CHANNEL)..."
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$FLUTTER_DIR/bin/cache/dart-sdk/bin:$PATH"
flutter --version
flutter config --no-analytics

# Ensure Flutter web is enabled
flutter precache --web

# Prepare instance config (generates app_config.json + web assets)
echo "==> Preparing instance: $INSTANCE_ID"
cd "$ROOT_DIR"
node scripts/prepare-instance.js "$INSTANCE_ID"

# Build Flutter web
echo "==> Running flutter build web..."
cd "$APP_DIR"
flutter pub get
flutter build web --release

# Copy well-known deep-link verification files into the output. Flutter's web
# build does not reliably include hidden (dot) directories, and App Links /
# Universal Links verification depends on these files being present.
if [ -d "$APP_DIR/web/.well-known" ]; then
  echo "==> Copying .well-known (deep-link verification) assets"
  mkdir -p "$WEB_BUILD/.well-known"
  cp -R "$APP_DIR/web/.well-known/." "$WEB_BUILD/.well-known/" 2>/dev/null || cp -R "$APP_DIR/web/.well-known" "$WEB_BUILD/"
fi

# ---------------------------------------------------------------
# Assemble the Vercel Build Output API directory.
# static/       -> Flutter web build (served as-is)
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
  "runtime": "edge"
}
VC

cat > "$OUTPUT_DIR/config.json" <<'CONFIG'
{
  "version": 3,
  "headers": [
    {
      "source": "/flutter_bootstrap.js",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "/flutter.js",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "/main.dart.js",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "/assets/(.*)",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "/canvaskit/(.*)",
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
