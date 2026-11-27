import { Injectable, signal } from '@angular/core';

export type ToastTone = 'info' | 'success' | 'error';

export interface ToastMessage {
  id: number;
  message: string;
  tone: ToastTone;
}

@Injectable({ providedIn: 'root' })
export class ToastService {
  readonly toasts = signal<ToastMessage[]>([]);

  private nextId = 1;
  private readonly timers = new Map<number, ReturnType<typeof setTimeout>>();

  show(
    message: string,
    tone: ToastTone = 'info',
    durationMs = 3000,
  ): number {
    const clean = message.trim();
    if (!clean) return -1;
    const id = this.nextId++;
    const toast: ToastMessage = { id, message: clean, tone };
    this.toasts.update((list) => [...list.slice(-3), toast]);

    if (durationMs > 0) {
      const timer = setTimeout(() => this.dismiss(id), durationMs);
      this.timers.set(id, timer);
    }
    return id;
  }

  dismiss(id: number): void {
    const timer = this.timers.get(id);
    if (timer) {
      clearTimeout(timer);
      this.timers.delete(id);
    }
    this.toasts.update((list) => list.filter((t) => t.id !== id));
  }

  clear(): void {
    for (const timer of this.timers.values()) {
      clearTimeout(timer);
    }
    this.timers.clear();
    this.toasts.set([]);
  }
}
