#!/usr/bin/env bash
set -e

PREVIEW_ID="${1:?Usage: ./scripts/publish-e2e-preview.sh <pr-123|branch-name>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="$ROOT_DIR/e2e-results/pages-stage"
WEB_REPORT="$ROOT_DIR/apps/web/playwright-report"
MOBILE_RESULTS="$ROOT_DIR/e2e-results/mobile"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

HAS_WEB=false
HAS_MOBILE=false
[ -f "$WEB_REPORT/index.html" ] && HAS_WEB=true
[ -d "$MOBILE_RESULTS" ] && HAS_MOBILE=true

if [ "$HAS_WEB" = false ] && [ "$HAS_MOBILE" = false ]; then
    echo "No local E2E results found in apps/web/playwright-report or e2e-results/mobile."
    exit 1
fi

if [ "$HAS_WEB" = true ]; then
    cp -R "$WEB_REPORT" "$STAGE_DIR/web"
fi
if [ "$HAS_MOBILE" = true ]; then
    mkdir -p "$STAGE_DIR/mobile"
    find "$MOBILE_RESULTS" -maxdepth 1 \( -name "*.mp4" -o -name "*.png" \) -exec cp {} "$STAGE_DIR/mobile/" \;
fi

cat <<EOF > "$STAGE_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>E2E Preview — ${PREVIEW_ID}</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; max-width: 1080px; margin: 2rem auto; padding: 0 1rem; background: #0f172a; color: #e2e8f0; }
    a { color: #38bdf8; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 1.25rem; margin-bottom: 1.5rem; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1rem; margin-top: 1rem; }
    .shot { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 0.5rem; }
    .shot img { width: 100%; border-radius: 4px; display: block; }
    .shot span { display: block; margin-top: 0.4rem; font-size: 0.85rem; color: #94a3b8; word-break: break-all; }
    video { width: 100%; max-width: 420px; border-radius: 8px; border: 1px solid #334155; background: #000; }
  </style>
</head>
<body>
  <h1>E2E Test Preview — ${PREVIEW_ID}</h1>
EOF

if [ "$HAS_WEB" = true ]; then
    cat <<EOF >> "$STAGE_DIR/index.html"
  <div class="card">
    <h2>Web E2E (Playwright)</h2>
    <p><a href="./web/index.html">Open Full Playwright HTML Report (screenshots &amp; videos) &rarr;</a></p>
  </div>
EOF
fi

if [ "$HAS_MOBILE" = true ]; then
    echo "  <div class=\"card\"><h2>Mobile E2E (Emulator / Maestro)</h2>" >> "$STAGE_DIR/index.html"
    for vid in "$STAGE_DIR/mobile/"*.mp4; do
        [ -f "$vid" ] || continue
        base=$(basename "$vid")
        echo "    <h3>${base}</h3><video controls src=\"./mobile/${base}\"></video>" >> "$STAGE_DIR/index.html"
    done
    SHOTS=$(find "$STAGE_DIR/mobile" -maxdepth 1 -name "*.png" | sort)
    if [ -n "$SHOTS" ]; then
        echo "    <h3>Scenario Screenshots</h3><div class=\"grid\">" >> "$STAGE_DIR/index.html"
        for img in $SHOTS; do
            base=$(basename "$img")
            echo "      <div class=\"shot\"><a href=\"./mobile/${base}\" target=\"_blank\"><img src=\"./mobile/${base}\" alt=\"${base}\" /></a><span>${base}</span></div>" >> "$STAGE_DIR/index.html"
        done
        echo "    </div>" >> "$STAGE_DIR/index.html"
    fi
    echo "  </div>" >> "$STAGE_DIR/index.html"
fi

echo "</body></html>" >> "$STAGE_DIR/index.html"

REMOTE_URL=$(git -C "$ROOT_DIR" remote get-url origin)
GH_PAGES_TMP="$ROOT_DIR/e2e-results/gh-pages-tmp"
rm -rf "$GH_PAGES_TMP"

if git ls-remote --exit-code --heads "$REMOTE_URL" gh-pages >/dev/null 2>&1; then
    git clone --depth 1 --branch gh-pages "$REMOTE_URL" "$GH_PAGES_TMP"
else
    mkdir -p "$GH_PAGES_TMP"
    git -C "$GH_PAGES_TMP" init
    git -C "$GH_PAGES_TMP" checkout -b gh-pages
    git -C "$GH_PAGES_TMP" remote add origin "$REMOTE_URL"
fi

rm -rf "$GH_PAGES_TMP/$PREVIEW_ID"
mkdir -p "$GH_PAGES_TMP/$PREVIEW_ID"
cp -R "$STAGE_DIR/." "$GH_PAGES_TMP/$PREVIEW_ID/"

cd "$GH_PAGES_TMP"
git add "$PREVIEW_ID"
git commit -m "chore(e2e): publish local E2E preview for $PREVIEW_ID"
git push -u origin gh-pages

if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    echo ""
    echo "GitHub Pages Preview URL:"
    echo "https://${BASH_REMATCH[1]}.github.io/${BASH_REMATCH[2]}/$PREVIEW_ID/"
fi
