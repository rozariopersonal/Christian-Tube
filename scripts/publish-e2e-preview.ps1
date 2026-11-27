param(
    [Parameter(Mandatory = $true)]
    [string]$PreviewId
)

$ErrorActionPreference = "Stop"
$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StageDir = Join-Path $RootDir "e2e-results\pages-stage"
$WebReport = Join-Path $RootDir "apps\web\playwright-report"
$MobileResults = Join-Path $RootDir "e2e-results\mobile"

if (Test-Path $StageDir) { Remove-Item -Recurse -Force $StageDir }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

$hasWeb = Test-Path (Join-Path $WebReport "index.html")
$hasMobile = Test-Path $MobileResults

if (-not $hasWeb -and -not $hasMobile) {
    Write-Host "No local E2E results found in apps/web/playwright-report or e2e-results/mobile." -ForegroundColor Red
    exit 1
}

if ($hasWeb) {
    Copy-Item -Recurse -Force $WebReport (Join-Path $StageDir "web")
}
if ($hasMobile) {
    New-Item -ItemType Directory -Force -Path (Join-Path $StageDir "mobile") | Out-Null
    Get-ChildItem -Path $MobileResults -File | Where-Object { $_.Extension -in ".mp4", ".png" } | ForEach-Object {
        Copy-Item -Force $_.FullName (Join-Path $StageDir "mobile\$($_.Name)")
    }
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>E2E Preview — $PreviewId</title>
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
  <h1>E2E Test Preview — $PreviewId</h1>
"@

if ($hasWeb) {
    $html += @"
  <div class="card">
    <h2>Web E2E (Playwright)</h2>
    <p><a href="./web/index.html">Open Full Playwright HTML Report (screenshots &amp; videos) &rarr;</a></p>
  </div>
"@
}

if ($hasMobile) {
    $html += "  <div class=`"card`">`n    <h2>Mobile E2E (Emulator / Maestro)</h2>`n"
    Get-ChildItem -Path (Join-Path $StageDir "mobile") -Filter "*.mp4" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $html += "    <h3>$($_.Name)</h3>`n    <video controls src=`"./mobile/$($_.Name)`"></video>`n"
    }
    $shots = Get-ChildItem -Path (Join-Path $StageDir "mobile") -Filter "*.png" -File -ErrorAction SilentlyContinue | Sort-Object Name
    if ($shots) {
        $html += "    <h3>Scenario Screenshots</h3>`n    <div class=`"grid`">`n"
        foreach ($s in $shots) {
            $html += "      <div class=`"shot`"><a href=`"./mobile/$($s.Name)`" target=`"_blank`"><img src=`"./mobile/$($s.Name)`" alt=`"$($s.Name)`" /></a><span>$($s.Name)</span></div>`n"
        }
        $html += "    </div>`n"
    }
    $html += "  </div>`n"
}

$html += "</body></html>"
Set-Content -Path (Join-Path $StageDir "index.html") -Value $html -Encoding UTF8

# Push staged preview to gh-pages branch
$remoteUrl = (& git -C $RootDir remote get-url origin).Trim()
$ghPagesTmp = Join-Path $RootDir "e2e-results\gh-pages-tmp"
if (Test-Path $ghPagesTmp) { Remove-Item -Recurse -Force $ghPagesTmp }

$hasGhPages = (& git ls-remote --heads $remoteUrl gh-pages)
if ($hasGhPages) {
    & git clone --depth 1 --branch gh-pages $remoteUrl $ghPagesTmp | Out-Null
} else {
    New-Item -ItemType Directory -Force -Path $ghPagesTmp | Out-Null
    & git -C $ghPagesTmp init | Out-Null
    & git -C $ghPagesTmp checkout -b gh-pages | Out-Null
    & git -C $ghPagesTmp remote add origin $remoteUrl | Out-Null
}

$destDir = Join-Path $ghPagesTmp $PreviewId
if (Test-Path $destDir) { Remove-Item -Recurse -Force $destDir }
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -Recurse -Force "$StageDir\*" $destDir

Push-Location $ghPagesTmp
try {
    & git add $PreviewId
    & git commit -m "chore(e2e): publish local E2E preview for $PreviewId"
    & git push -u origin gh-pages
} finally {
    Pop-Location
}

if ($remoteUrl -match "github\.com[:/]([^/]+)/([^/.]+)") {
    $owner = $Matches[1]
    $repo = $Matches[2]
    Write-Host "`nGitHub Pages Preview URL:" -ForegroundColor Green
    Write-Host "https://$owner.github.io/$repo/$PreviewId/" -ForegroundColor Cyan
}
