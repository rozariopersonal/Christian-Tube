import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';

export interface AdminUser {
  id: string;
  email: string;
  displayName?: string;
  photoUrl?: string;
  role: string;
  isBlocked: boolean;
  lastLoginAt?: string;
  createdAt?: string;
}

@Injectable({ providedIn: 'root' })
export class AdminUsersService {
  private readonly api = inject(ApiService);

  readonly users = signal<AdminUser[]>([]);
  readonly isLoading = signal<boolean>(false);
  readonly error = signal<string | null>(null);

  async fetchUsers(search?: string): Promise<void> {
    this.isLoading.set(true);
    this.error.set(null);
    try {
      const res = await firstValueFrom(
        this.api.get<AdminUser[]>('/api/users', {
          search: search?.trim() || undefined,
        }),
      );
      this.users.set(Array.isArray(res) ? res : []);
    } catch (err) {
      if (err instanceof HttpErrorResponse) {
        const serverMsg =
          typeof err.error === 'object' && err.error?.message
            ? String(err.error.message)
            : err.statusText;
        this.error.set(`Error ${err.status}: ${serverMsg || 'Unable to load users'}`);
      } else {
        this.error.set(
          err instanceof Error ? err.message : 'Unable to load users',
        );
      }
    } finally {
      this.isLoading.set(false);
    }
  }

  async toggleBlock(user: AdminUser): Promise<boolean> {
    try {
      const updated = await firstValueFrom(
        this.api.post<AdminUser>(`/api/users/${user.id}/toggle-block`, {}),
      );
      this.users.update((list) =>
        list.map((u) =>
          u.id === user.id
            ? { ...u, isBlocked: updated?.isBlocked ?? !user.isBlocked }
            : u,
        ),
      );
      return true;
    } catch {
      return false;
    }
  }

  async removeUser(userId: string): Promise<boolean> {
    try {
      await firstValueFrom(this.api.delete(`/api/users/${userId}`));
      this.users.update((list) => list.filter((u) => u.id !== userId));
      return true;
    } catch {
      return false;
    }
  }
}
