#!/usr/bin/env bash
# ==============================================================================
# Automated E2E Test Runner for Christian-Tube APKs (Bash / CI / Linux / macOS)
# ==============================================================================
set -e

INSTANCE="${1:-christian_tube}"
FLOW="${2:-smoke_flow.yaml}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"

echo "======================================================"
echo "   Christian-Tube E2E Quality Gate (Bash/CI Runner)   "
echo "   Instance: $INSTANCE | Flow: $FLOW                  "
echo "======================================================"

# 1. Verify adb
if ! command -v adb &> /dev/null; then
    echo "❌ adb command not found in PATH!"
    exit 1
fi

# 2. Verify Maestro
if ! command -v maestro &> /dev/null; then
    if [ -f "$HOME/.maestro/bin/maestro" ]; then
        export PATH="$PATH:$HOME/.maestro/bin"
    else
        echo "❌ Maestro CLI not found. Installing..."
        curl -FsSL "https://get.maestro.mobile.dev" | bash
        export PATH="$PATH:$HOME/.maestro/bin"
    fi
fi

# 3. Check for active device/emulator
if [ -z "$(adb devices | grep -w 'device')" ]; then
    echo "❌ No active Android device or emulator detected via adb!"
    exit 1
fi
echo "✅ Target device connected: $(adb devices | grep -w 'device' | head -n 1 | awk '{print $1}')"

# 4. Prepare Instance
echo "🚀 Preparing instance: $INSTANCE..."
node "$ROOT_DIR/scripts/prepare-instance.js" "$INSTANCE"

# 5. Locate or Build APK
APK_PATH="$MOBILE_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
    APK_PATH="$ROOT_DIR/$INSTANCE.apk"
fi
if [ ! -f "$APK_PATH" ]; then
    APK_PATH="$ROOT_DIR/christian-app.apk"
fi

if [ ! -f "$APK_PATH" ]; then
    echo "📦 Building APK..."
    cd "$MOBILE_DIR"
    flutter build apk --release --target-platform=android-arm64 --android-skip-build-dependency-validation
    APK_PATH="$MOBILE_DIR/build/app/outputs/flutter-apk/app-release.apk"
fi

# 6. Install APK
echo "📲 Installing APK on target device..."
adb install -r "$APK_PATH"

# 7. Run Maestro E2E Flow
echo "🧪 Running Maestro E2E test: $FLOW..."
cd "$ROOT_DIR"
maestro test ".maestro/$FLOW"
echo "🎉 E2E Quality Gate passed successfully!"
