import { Injectable, TemplateRef, signal } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class HeaderSlotService {
  readonly centerTemplate = signal<TemplateRef<unknown> | null>(null);
  readonly rightTemplate = signal<TemplateRef<unknown> | null>(null);

  setTemplates(
    center: TemplateRef<unknown> | null,
    right: TemplateRef<unknown> | null,
  ): void {
    this.centerTemplate.set(center);
    this.rightTemplate.set(right);
  }

  clear(): void {
    this.centerTemplate.set(null);
    this.rightTemplate.set(null);
  }
}
