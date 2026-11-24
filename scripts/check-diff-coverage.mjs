#!/usr/bin/env node
/**
 * Diff-based LCOV coverage gate.
 * Checks that newly added or modified executable lines in `git diff <base>...HEAD`
 * meet the minimum coverage threshold (default: 80%).
 *
 * Usage:
 *   node scripts/check-diff-coverage.mjs --lcov apps/mobile/coverage/lcov.info --prefix apps/mobile/ --min 80
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = { base: 'origin/develop', min: 80, prefix: '', lcov: '' };
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--lcov') args.lcov = argv[++i];
    else if (k === '--prefix') args.prefix = argv[++i];
    else if (k === '--min') args.min = Number(argv[++i]);
    else if (k === '--base') args.base = argv[++i];
  }
  if (!args.lcov) {
    console.error('Missing --lcov <path>');
    process.exit(2);
  }
  return args;
}

function parseLcov(lcovPath, prefix) {
  const content = fs.readFileSync(lcovPath, 'utf8');
  const map = new Map(); // normalized repo-relative path -> Map<lineNum, hits>
  let currentFile = null;

  for (const raw of content.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith('SF:')) {
      let file = line.slice(3).replace(/\\/g, '/');
      if (prefix && !file.startsWith(prefix)) {
        const idx = file.indexOf(prefix);
        file = idx >= 0 ? file.slice(idx) : path.posix.join(prefix, file);
      }
      currentFile = file;
      if (!map.has(currentFile)) map.set(currentFile, new Map());
    } else if (line.startsWith('DA:') && currentFile) {
      const [lnStr, hitsStr] = line.slice(3).split(',');
      const ln = Number(lnStr);
      const hits = Number(hitsStr);
      if (Number.isFinite(ln) && Number.isFinite(hits)) {
        map.get(currentFile).set(ln, hits);
      }
    } else if (line === 'end_of_record') {
      currentFile = null;
    }
  }
  return map;
}

function getChangedLines(base, prefix) {
  let diff = '';
  try {
    diff = execFileSync(
      'git',
      ['diff', '--unified=0', `${base}...HEAD`, '--', prefix || '.'],
      { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 }
    );
  } catch {
    diff = execFileSync(
      'git',
      ['diff', '--unified=0', 'HEAD~1', '--', prefix || '.'],
      { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 }
    );
  }

  const changed = new Map(); // file -> Set<lineNum>
  let currentFile = null;
  for (const line of diff.split(/\r?\n/)) {
    if (line.startsWith('+++ b/')) {
      currentFile = line.slice(6).replace(/\\/g, '/');
      if (!changed.has(currentFile)) changed.set(currentFile, new Set());
    } else if (line.startsWith('@@ ') && currentFile) {
      const m = /\+(\d+)(?:,(\d+))?/.exec(line);
      if (m) {
        const start = Number(m[1]);
        const count = m[2] === undefined ? 1 : Number(m[2]);
        for (let ln = start; ln < start + count; ln++) {
          changed.get(currentFile).add(ln);
        }
      }
    }
  }
  return changed;
}

const args = parseArgs(process.argv);
if (!fs.existsSync(args.lcov)) {
  console.error(`LCOV file not found: ${args.lcov}`);
  process.exit(1);
}

const lcovMap = parseLcov(args.lcov, args.prefix);
const changedMap = getChangedLines(args.base, args.prefix);

let totalExecutable = 0;
let coveredExecutable = 0;
const uncoveredDetails = [];

for (const [file, lines] of changedMap.entries()) {
  const fileCov = lcovMap.get(file);
  if (!fileCov) continue;
  const missed = [];
  for (const ln of lines) {
    if (fileCov.has(ln)) {
      totalExecutable++;
      if (fileCov.get(ln) > 0) coveredExecutable++;
      else missed.push(ln);
    }
  }
  if (missed.length > 0) {
    uncoveredDetails.push(`  ${file}: lines ${missed.join(', ')}`);
  }
}

if (totalExecutable === 0) {
  console.log(`Diff coverage (${args.prefix || 'repo'}): no executable changed lines to check.`);
  process.exit(0);
}

const pct = (coveredExecutable / totalExecutable) * 100;
console.log(
  `Diff coverage (${args.prefix || 'repo'}): ${coveredExecutable}/${totalExecutable} (${pct.toFixed(1)}%) — minimum ${args.min}%`
);

if (pct < args.min) {
  console.error(`❌ Diff coverage ${pct.toFixed(1)}% is below ${args.min}% threshold.`);
  if (uncoveredDetails.length > 0) {
    console.error('Uncovered changed lines:\n' + uncoveredDetails.join('\n'));
  }
  process.exit(1);
}

console.log('✅ Diff coverage threshold passed.');
