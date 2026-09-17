import { ChildProcess, spawn } from 'node:child_process';
import readline from 'node:readline';
import { WordTimestamp } from './types.js';

export class AsrClient {
  private pythonBin: string;
  private runnerScript: string;
  private proc: ChildProcess | null = null;
  private isReady = false;
  private readyPromise: Promise<void> | null = null;
  private readyResolve: (() => void) | null = null;
  private readyReject: ((err: Error) => void) | null = null;
  private pendingRequest: {
    resolve: (words: WordTimestamp[]) => void;
    reject: (err: Error) => void;
  } | null = null;

  constructor(pythonBin: string, runnerScript: string) {
    this.pythonBin = pythonBin;
    this.runnerScript = runnerScript;
  }

  public async init(): Promise<void> {
    if (this.isReady && this.proc) return;

    this.readyPromise = new Promise((resolve, reject) => {
      this.readyResolve = resolve;
      this.readyReject = reject;
    });

    this.proc = spawn(this.pythonBin, [this.runnerScript, '--pipe'], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    // Filter noisy NeMo / PyTorch dataloader warnings from stderr
    const stderrRl = readline.createInterface({
      input: this.proc.stderr!,
      crlfDelay: Infinity,
    });

    stderrRl.on('line', (line) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      if (
        trimmed.includes('dataloader:') ||
        trimmed.includes('use_start_end_token') ||
        trimmed.includes('pretokenize=True') ||
        trimmed.includes('non-tarred dataset')
      ) {
        return; // Suppress verbose warning
      }
      console.error(trimmed);
    });

    const rl = readline.createInterface({
      input: this.proc.stdout!,
      crlfDelay: Infinity,
    });

    rl.on('line', (line) => {
      const trimmed = line.trim();
      if (!trimmed) return;

      if (trimmed === 'READY') {
        this.isReady = true;
        this.readyResolve?.();
        return;
      }

      if (trimmed === 'PONG') return;

      // Extract JSON payload (ignore external library chatter like [NeMo ...] or warnings)
      let jsonPayload: string | null = null;
      if (trimmed.startsWith('RES:')) {
        jsonPayload = trimmed.slice(4).trim();
      } else if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        jsonPayload = trimmed;
      }

      if (!jsonPayload) {
        // Log chatter to debug/stderr, but never fail the pending request
        return;
      }

      if (this.pendingRequest) {
        try {
          const res = JSON.parse(jsonPayload);
          if (res.success) {
            this.pendingRequest.resolve(res.words || []);
          } else {
            this.pendingRequest.reject(new Error(res.error || 'ASR decoding failed'));
          }
        } catch (err: any) {
          this.pendingRequest.reject(new Error(`Invalid JSON from ASR runner: ${err.message}`));
        } finally {
          this.pendingRequest = null;
        }
      }
    });

    this.proc.on('close', (code) => {
      this.isReady = false;
      this.proc = null;
      if (this.pendingRequest) {
        this.pendingRequest.reject(new Error(`ASR runner exited unexpectedly (code ${code})`));
        this.pendingRequest = null;
      }
    });

    this.proc.on('error', (err) => {
      this.isReady = false;
      this.proc = null;
      this.readyReject?.(err);
      if (this.pendingRequest) {
        this.pendingRequest.reject(err);
        this.pendingRequest = null;
      }
    });

    await this.readyPromise;
  }

  public async transcribeChunk(audioPath: string, offsetSec = 0.0): Promise<WordTimestamp[]> {
    await this.init();

    if (!this.proc || !this.isReady) {
      throw new Error('ASR client is not initialized');
    }

    if (this.pendingRequest) {
      throw new Error('Concurrent requests on single ASR pipe not supported');
    }

    return new Promise((resolve, reject) => {
      this.pendingRequest = { resolve, reject };
      const payload = JSON.stringify({ audio: audioPath, offset: offsetSec }) + '\n';
      this.proc!.stdin!.write(payload);
    });
  }

  public close(): void {
    if (this.proc) {
      try {
        this.proc.stdin?.write('QUIT\n');
        this.proc.kill('SIGTERM');
      } catch {}
      this.proc = null;
      this.isReady = false;
    }
  }
}
