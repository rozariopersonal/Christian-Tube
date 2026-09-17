import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

export interface GitTrackerOptions {
  releasesDir: string;
  seedDir?: string;
  githubRepo: string;
  githubToken?: string;
}

export class GitTracker {
  private releasesDir: string;
  private seedDir?: string;
  private githubRepo: string;
  private githubToken?: string;
  private isInitialized = false;

  constructor(opts: GitTrackerOptions) {
    this.releasesDir = opts.releasesDir;
    this.seedDir = opts.seedDir;
    this.githubRepo = opts.githubRepo;
    this.githubToken = opts.githubToken;
  }

  private runGit(cmd: string, allowFail = false, retries = 10): string {
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        return execSync(cmd, {
          cwd: this.releasesDir,
          encoding: 'utf-8',
          timeout: 120000,
          env: {
            ...process.env,
            GIT_TERMINAL_PROMPT: '0',
          },
        }).trim();
      } catch (err: any) {
        const msg = `${err.message || ''} ${err.stderr || ''}`;
        if (msg.includes('index.lock')) {
          const sleepMs = 100 * attempt;
          try {
            Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, sleepMs);
          } catch {
            // fallback
          }
          continue;
        }
        if (!allowFail) {
          throw new Error(
            `Git command failed in ${this.releasesDir} [${cmd}]: ${err.message}\n${err.stderr || ''}`
          );
        }
        return '';
      }
    }
    return '';
  }

  public init(): void {
    if (this.isInitialized) return;

    // 1. Ensure directory has .git
    let gitDir = path.join(this.releasesDir, '.git');
    if (!fs.existsSync(gitDir)) {
      if (this.seedDir && fs.existsSync(path.join(this.seedDir, '.git'))) {
        this.releasesDir = this.seedDir;
        gitDir = path.join(this.releasesDir, '.git');
      } else {
        throw new Error(`Releases repository not found at ${this.releasesDir}`);
      }
    }

    // 2. Configure identity and safe directory
    this.runGit('git config --global --add safe.directory "*"', true);
    this.runGit('git config user.name "Christian-Tube Transcriber"');
    this.runGit('git config user.email "bot@privatetube.org"');

    // Fast I/O performance over bind mounts (ignore stats for 80,000 other files)
    this.runGit('git config core.trustctime false', true);
    this.runGit('git config core.filemode false', true);
    this.runGit('git config core.checkstat minimal', true);
    this.runGit('git config status.showUntrackedFiles no', true);
    this.runGit('git config core.preloadindex false', true);

    // 3. Configure authenticated remote if token present
    if (this.githubToken) {
      const authUrl = `https://${this.githubToken}@github.com/${this.githubRepo}.git`;
      this.runGit(`git remote set-url origin "${authUrl}"`);
    }

    // 4. Ensure transcripts dir exists
    const transcriptsDir = path.join(this.releasesDir, 'transcripts');
    if (!fs.existsSync(transcriptsDir)) {
      fs.mkdirSync(transcriptsDir, { recursive: true });
    }

    this.isInitialized = true;
    console.log(`[GitTracker] Initialized at ${this.releasesDir} (branch: ${this.getCurrentBranch()})`);
  }

  public getCurrentBranch(): string {
    return this.runGit('git rev-parse --abbrev-ref HEAD', true) || 'main';
  }

  public getTranscriptPath(videoId: string): string {
    return path.join(this.releasesDir, 'transcripts', `${videoId}.md`);
  }

  public hasTranscript(videoId: string): boolean {
    return fs.existsSync(this.getTranscriptPath(videoId));
  }

  public readTranscript(videoId: string): string | null {
    const filePath = this.getTranscriptPath(videoId);
    if (!fs.existsSync(filePath)) return null;
    const content = fs.readFileSync(filePath, 'utf-8');
    const parts = content.split('\n---\n');
    return (parts[1] || parts[0] || '').trim();
  }

  public commitTranscript(
    video: { id: string; title: string | null; channelName?: string | null },
    transcriptText: string,
    detail?: any
  ): void {
    this.init();
    const filePath = this.getTranscriptPath(video.id);

    const lines = [
      `# ${video.title || video.id}`,
      '',
      `- Video: https://www.youtube.com/watch?v=${video.id}`,
      `- Channel: ${video.channelName || 'Unknown'}`,
    ];
    if (detail?.maxSec) {
      lines.push(`- Duration: ${Math.round(detail.maxSec)}s`);
    }
    if (detail?.wordCount) {
      lines.push(`- Words: ${detail.wordCount}`);
    }
    lines.push('', '---', '', transcriptText.trim(), '');
    const markdown = lines.join('\n');

    fs.writeFileSync(filePath, markdown, 'utf-8');

    const relFile = path.relative(this.releasesDir, filePath).replace(/\\/g, '/');
    this.runGit(`git add "${relFile}"`);

    const cleanTitle = (video.title || video.id).replace(/["`$]/g, '').slice(0, 50);
    this.runGit(`git commit "${relFile}" -m "transcript: add ${video.id} (${cleanTitle})"`);
    console.log(`[GitTracker] Committed transcript for ${video.id} locally`);
  }

  public bumpManifestRevision(): void {
    const manifestPath = path.join(this.releasesDir, 'manifest.json');
    let manifest: any = { revision: '1' };
    if (fs.existsSync(manifestPath)) {
      try {
        manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
      } catch {
        manifest = { revision: '1' };
      }
    }

    manifest.revision = `${Date.now()}`;
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf-8');
    this.runGit('git add manifest.json');
    this.runGit('git commit -m "chore: bump dataset revision"');
  }

  public async pushWithRetry(maxAttempts = 5): Promise<boolean> {
    this.init();
    const branch = this.getCurrentBranch();

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        console.log(`[GitTracker] Pulling latest changes (rebase) before push (attempt ${attempt}/${maxAttempts})...`);
        // 1. Pull with rebase
        this.runGit(`git pull --rebase origin ${branch}`);

        // 2. Bump manifest revision right before push
        this.bumpManifestRevision();

        // 3. Push to remote
        console.log(`[GitTracker] Pushing batch to origin ${branch}...`);
        this.runGit(`git push origin ${branch}`);
        console.log(`[GitTracker] Push succeeded.`);
        return true;
      } catch (err: any) {
        console.warn(`[GitTracker] Push attempt ${attempt} failed: ${err.message}`);

        // Handle possible rebase conflict on manifest.json
        try {
          const status = this.runGit('git status --porcelain', true);
          if (status.includes('UU manifest.json')) {
            const manifestPath = path.join(this.releasesDir, 'manifest.json');
            fs.writeFileSync(manifestPath, JSON.stringify({ revision: `${Date.now()}` }, null, 2), 'utf-8');
            this.runGit('git add manifest.json');
            this.runGit('git rebase --continue');
          } else if (status.includes('UU')) {
            // Abort rebase if unexpected conflicts occur
            this.runGit('git rebase --abort', true);
          }
        } catch {
          // ignore cleanup errors
        }

        if (attempt === maxAttempts) {
          console.error(`[GitTracker] All ${maxAttempts} push attempts failed.`);
          return false;
        }

        const delayMs = 2000 * attempt + Math.floor(Math.random() * 2000);
        console.log(`[GitTracker] Waiting ${delayMs}ms before retry...`);
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
    return false;
  }
}
