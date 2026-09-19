import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { execSync } from 'child_process';
import { GitTracker } from '../src/git_tracker.js';

describe('GitTracker: Local WAL and Deduplication', () => {
  const tmpDir = path.join(os.tmpdir(), `ct-test-releases-${Date.now()}`);

  before(() => {
    fs.mkdirSync(tmpDir, { recursive: true });
    execSync('git init -b main', { cwd: tmpDir });
    execSync('git config user.name "Tester"', { cwd: tmpDir });
    execSync('git config user.email "test@example.com"', { cwd: tmpDir });
    fs.writeFileSync(path.join(tmpDir, 'README.md'), '# Test Releases\n');
    execSync('git add README.md && git commit -m "initial commit"', { cwd: tmpDir });
  });

  after(() => {
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch {
      // ignore cleanup
    }
  });

  it('initializes a git repository and creates transcripts directory', () => {
    const tracker = new GitTracker({
      releasesDir: tmpDir,
      githubRepo: 'test/test-repo',
    });

    tracker.init();
    assert.ok(fs.existsSync(path.join(tmpDir, 'transcripts')));
  });

  it('commits transcript locally and detects it with hasTranscript', () => {
    const tracker = new GitTracker({
      releasesDir: tmpDir,
      githubRepo: 'test/test-repo',
    });

    assert.equal(tracker.hasTranscript('testVideo123'), false);

    tracker.commitTranscript(
      { id: 'testVideo123', title: 'Test Sermon', channelName: 'CFC' },
      'Sentence one. Sentence two.',
      { maxSec: 120, wordCount: 4 }
    );

    assert.equal(tracker.hasTranscript('testVideo123'), true);
    const read = tracker.readTranscript('testVideo123');
    assert.equal(read, 'Sentence one. Sentence two.');
  });
});
