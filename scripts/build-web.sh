#!/bin/bash
set -e

INSTANCE_ID="${INSTANCE_ID:-christian_tube}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.0}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_DIR="$ROOT_DIR/.flutter-sdk"
APP_DIR="$ROOT_DIR/apps/mobile"

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
flutter build web --release --web-renderer canvaskit

echo "==> Build complete: $APP_DIR/build/web"
