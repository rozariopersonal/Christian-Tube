const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function getGitCommits() {
  let prevTag = '';
  try {
    // Try to find the most recent tag prior to HEAD
    prevTag = execSync('git describe --tags --abbrev=0 HEAD^', {
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8'
    }).trim();
  } catch (_) {
    try {
      // Fallback: list tags sorted by creation date
      const tags = execSync('git tag --sort=-creatordate', {
        stdio: ['ignore', 'pipe', 'ignore'],
        encoding: 'utf8'
      })
        .split('\n')
        .map(t => t.trim())
        .filter(Boolean);
      if (tags.length > 0) {
        prevTag = tags[0];
      }
    } catch (_) {}
  }

  let logRange = '';
  if (prevTag) {
    logRange = `${prevTag}..HEAD`;
  } else {
    logRange = '-n 25 HEAD';
  }

  try {
    const rawLog = execSync(`git log ${logRange} --pretty=format:"%s" --no-merges`, { encoding: 'utf8' });
    return rawLog
      .split('\n')
      .map(s => s.trim())
      .filter(Boolean);
  } catch (err) {
    console.warn(`Warning: Could not fetch git commits: ${err.message}`);
    return [];
  }
}

function parseCommits(commits) {
  const categories = {
    features: [],
    fixes: [],
    improvements: [],
    others: []
  };

  const skipPrefixes = [
    'chore',
    'ci',
    'test',
    'tests',
    'merge',
    'bump',
    'release',
    'wip'
  ];

  for (const commit of commits) {
    const lower = commit.toLowerCase();

    // Check if should be ignored
    const isIgnored = skipPrefixes.some(p => lower.startsWith(`${p}:`) || lower.startsWith(`${p}(`));
    if (isIgnored) continue;

    // Feature
    if (lower.startsWith('feat:') || lower.startsWith('feat(')) {
      categories.features.push(cleanCommitMessage(commit));
    }
    // Fix
    else if (lower.startsWith('fix:') || lower.startsWith('fix(')) {
      categories.fixes.push(cleanCommitMessage(commit));
    }
    // Performance or Refactor
    else if (
      lower.startsWith('perf:') || lower.startsWith('perf(') ||
      lower.startsWith('refactor:') || lower.startsWith('refactor(')
    ) {
      categories.improvements.push(cleanCommitMessage(commit));
    }
    // Other notable changes
    else {
      categories.others.push(commit);
    }
  }

  return categories;
}

function cleanCommitMessage(msg) {
  // Turn "feat(channels): add search" into "**channels**: Add search"
  const scopedMatch = msg.match(/^[a-z]+(\(([^)]+)\))?:\s*(.+)$/i);
  if (scopedMatch) {
    const scope = scopedMatch[2];
    const text = scopedMatch[3].trim();
    const capitalized = text.charAt(0).toUpperCase() + text.slice(1);
    return scope ? `**${scope}**: ${capitalized}` : capitalized;
  }
  return msg.charAt(0).toUpperCase() + msg.slice(1);
}

function main() {
  const args = process.argv.slice(2);
  const appName = args[0] || 'ChristianApp';
  const tag = args[1] || 'v1.0.0';
  const channel = (args[2] || 'prod').toLowerCase();
  const releaseRepo = args[3] || 'rozariopersonal/Christian-Tube-Releases';
  const apkName = args[4] || 'christian-app.apk';
  const outputPath = args[5] || 'release_body.md';

  const isBeta = channel === 'beta' || tag.includes('beta');

  console.log(`Generating release notes for ${appName} ${tag} [${channel.toUpperCase()}]...`);

  // Check if a dedicated RELEASE_NOTES.md exists in repo root
  let customNotes = '';
  const customNotesPath = path.resolve(process.cwd(), 'RELEASE_NOTES.md');
  if (fs.existsSync(customNotesPath)) {
    customNotes = fs.readFileSync(customNotesPath, 'utf8').trim();
    console.log(`Found custom RELEASE_NOTES.md`);
  }

  const rawCommits = getGitCommits();
  const parsed = parseCommits(rawCommits);

  let body = `### 🚀 What's New in ${appName} ${tag}\n\n`;

  if (isBeta) {
    body += `> ⚠️ **BETA RELEASE**: Staged for integration testing. Install side-by-side with production.\n\n`;
  }

  if (customNotes) {
    body += `${customNotes}\n\n`;
  }

  let hasChangelog = false;

  if (parsed.features.length > 0) {
    hasChangelog = true;
    body += `#### ✨ New Features\n`;
    for (const item of parsed.features) {
      body += `- ${item}\n`;
    }
    body += `\n`;
  }

  if (parsed.fixes.length > 0) {
    hasChangelog = true;
    body += `#### 🐛 Bug Fixes\n`;
    for (const item of parsed.fixes) {
      body += `- ${item}\n`;
    }
    body += `\n`;
  }

  if (parsed.improvements.length > 0) {
    hasChangelog = true;
    body += `#### ⚡ Performance & Polish\n`;
    for (const item of parsed.improvements) {
      body += `- ${item}\n`;
    }
    body += `\n`;
  }

  // If no conventional commits were found and no custom notes
  if (!hasChangelog && !customNotes) {
    if (parsed.others.length > 0) {
      body += `#### 📋 Highlights\n`;
      for (const item of parsed.others.slice(0, 8)) {
        body += `- ${item}\n`;
      }
      body += `\n`;
    } else {
      body += `#### 📋 Highlights\n`;
      body += `- Performance optimizations and video streaming stability\n`;
      body += `- In-app update enhancements\n`;
      body += `- General quality and usability improvements\n\n`;
    }
  }

  body += `---\n`;
  body += `**Direct Download**: [${apkName}](https://github.com/${releaseRepo}/releases/download/${tag}/${apkName})\n\n`;
  body += `<img src="https://github.com/${releaseRepo}/releases/download/${tag}/download-qrcode.png" width="220" alt="Scan to Download APK" />\n`;

  fs.writeFileSync(path.resolve(outputPath), body, 'utf8');
  console.log(`✅ Release notes generated and written to ${outputPath}`);
}

if (require.main === module) {
  main();
}
