#!/usr/bin/env node
// Prepares the Flutter app's bundled asset payload for a given app instance.
//
//   `node prepare_assets.js christian_tube`   -> materializes assets/data (bibles + words)
//   `node prepare_assets.js centum_academy`   -> removes assets/data (keeps the build slim)
//
// The bible + words JSON lives under apps/backend/data (committed) and is
// copied into apps/mobile/assets/data ONLY for the Christian App build. The
// generated folder is gitignored so it is never committed.
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..', '..');
const SRC_BIBLES = path.join(ROOT, 'apps', 'backend', 'data', 'bibles');
const SRC_SCRIPTURES = path.join(
  ROOT,
  'apps',
  'backend',
  'data',
  'scriptures.json'
);
const TARGET = path.join(ROOT, 'apps', 'mobile', 'assets', 'data');

const instance = process.argv[2] || 'christian_tube';

function rmDir(dir) {
  if (fs.existsSync(dir)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function copyIfExists(src, dst) {
  if (!fs.existsSync(src)) {
    throw new Error(`Missing source ${src}`);
  }
  fs.copyFileSync(src, dst);
}

if (instance === 'christian_tube') {
  if (!fs.existsSync(SRC_BIBLES)) {
    throw new Error(`Bible sources missing at ${SRC_BIBLES}`);
  }
  rmDir(TARGET);
  fs.mkdirSync(TARGET, { recursive: true });

  for (const file of fs.readdirSync(SRC_BIBLES)) {
    if (file.endsWith('.json')) {
      copyIfExists(path.join(SRC_BIBLES, file), path.join(TARGET, file));
    }
  }
  copyIfExists(SRC_SCRIPTURES, path.join(TARGET, 'scriptures.json'));

  const files = fs.readdirSync(TARGET);
  const total = files.reduce(
    (sum, f) => sum + fs.statSync(path.join(TARGET, f)).size,
    0
  );
  console.log(
    `Christian App: bundled ${files.length} payload files (${(total / 1024 / 1024).toFixed(1)} MB) -> ${TARGET}`
  );
} else {
  rmDir(TARGET);
  console.log(`${instance}: bible/words assets excluded from the build`);
}