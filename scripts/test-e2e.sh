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

# 7. Run Maestro E2E Flow with video & screenshot capture
RESULTS_DIR="$ROOT_DIR/e2e-results/mobile"
mkdir -p "$RESULTS_DIR"
FLOW_BASE="${FLOW%.yaml}"
DEVICE_VIDEO="/sdcard/e2e_${FLOW_BASE}.mp4"
LOCAL_VIDEO="$RESULTS_DIR/${FLOW_BASE}.mp4"

echo "🧪 Running Maestro E2E test: $FLOW (recording to $LOCAL_VIDEO)..."
cd "$ROOT_DIR"

adb shell screenrecord --time-limit 180 "$DEVICE_VIDEO" &
RECORD_PID=$!

set +e
maestro test ".maestro/$FLOW" --debug-output "$RESULTS_DIR/maestro-debug"
MAESTRO_EXIT=$?
set -e

adb shell pkill -l INT screenrecord 2>/dev/null || true
sleep 2
kill "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" 2>/dev/null || true

adb pull "$DEVICE_VIDEO" "$LOCAL_VIDEO" 2>/dev/null || true
adb shell rm -f "$DEVICE_VIDEO" 2>/dev/null || true
find "$ROOT_DIR" -maxdepth 1 -name "*.png" -exec mv {} "$RESULTS_DIR/" \; 2>/dev/null || true

if [ "$MAESTRO_EXIT" -ne 0 ]; then
    echo "❌ Maestro E2E test failed! Media saved to $RESULTS_DIR"
    exit "$MAESTRO_EXIT"
fi

echo "🎉 E2E Quality Gate passed successfully! Media saved to $RESULTS_DIR"
