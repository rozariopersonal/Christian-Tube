import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/auth/auth.service';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSearchService } from '../../../core/services/header-search.service';
import { AdminUser, AdminUsersService } from '../services/admin-users.service';

@Component({
  selector: 'app-admin-users-page',
  standalone: true,
  imports: [FormsModule, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="admin-users max-width-box">
      @if (!auth.isAdmin()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">lock</span>
          <h2>Admin access required</h2>
          <p class="muted">Sign in with an administrator account to manage users.</p>
          <a class="pill-chip active" routerLink="/feed">Back to Home</a>
        </div>
      } @else {
        <header class="page-head">
          <div>
            <h1 class="font-display">User Administration</h1>
            <p class="sub">Block, unblock, or remove platform users</p>
          </div>
          <button type="button" class="pill-chip" (click)="refresh()">
            <span class="material-symbols-rounded btn-icon">refresh</span>
            Refresh
          </button>
        </header>

        <div class="stats-row">
          <div class="stat-card">
            <span class="stat-val">{{ usersService.users().length }}</span>
            <span class="stat-lbl">Total</span>
          </div>
          <div class="stat-card">
            <span class="stat-val">{{ activeCount() }}</span>
            <span class="stat-lbl">Active</span>
          </div>
          <div class="stat-card">
            <span class="stat-val danger">{{ blockedCount() }}</span>
            <span class="stat-lbl">Blocked</span>
          </div>
        </div>

        @if (screen.isCompact()) {
          <div class="search-box">
            <span class="material-symbols-rounded">search</span>
            <input
              type="search"
              placeholder="Search by name or email..."
              [ngModel]="search()"
              (ngModelChange)="onSearchChange($event)"
            />
          </div>
        }

        @if (usersService.error()) {
          <div class="state-card">
            <p>{{ usersService.error() }}</p>
            <button type="button" class="pill-chip active" (click)="refresh()">
              Retry
            </button>
          </div>
        } @else if (usersService.isLoading() && usersService.users().length === 0) {
          <p class="empty-msg">Loading users...</p>
        } @else if (usersService.users().length === 0) {
          <p class="empty-msg">No users found.</p>
        } @else {
          <div class="user-list">
            @for (u of usersService.users(); track u.id) {
              <div class="user-row" [class.blocked]="u.isBlocked">
                <div class="user-main">
                  @if (u.photoUrl) {
                    <img class="avatar" [src]="u.photoUrl" [alt]="u.displayName || u.email" />
                  } @else {
                    <span class="avatar fallback">
                      {{ (u.displayName || u.email).slice(0, 1).toUpperCase() }}
                    </span>
                  }
                  <div class="user-meta">
                    <div class="name-line">
                      <span class="user-name">{{ u.displayName || 'User' }}</span>
                      @if (u.role === 'ADMIN') {
                        <span class="role-badge">ADMIN</span>
                      }
                      @if (u.isBlocked) {
                        <span class="blocked-badge">Blocked</span>
                      }
                    </div>
                    <span class="user-email">{{ u.email }}</span>
                  </div>
                </div>

                <div class="user-actions">
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="u.isBlocked"
                    (click)="usersService.toggleBlock(u)"
                  >
                    {{ u.isBlocked ? 'Unblock' : 'Block' }}
                  </button>
                  <button
                    type="button"
                    class="pill-chip danger-chip"
                    [disabled]="u.id === auth.currentUser()?.id"
                    (click)="userToRemove.set(u)"
                  >
                    Remove
                  </button>
                </div>
              </div>
            }
          </div>
        }
      }

      @if (userToRemove(); as target) {
        <div class="confirm-backdrop" (click)="userToRemove.set(null)">
          <div class="confirm-modal" (click)="$event.stopPropagation()">
            <h3>Remove User?</h3>
            <p>
              Are you sure you want to permanently remove
              <strong>{{ target.displayName || target.email }}</strong>?
            </p>
            <div class="confirm-actions">
              <button type="button" class="pill-chip" (click)="userToRemove.set(null)">
                Cancel
              </button>
              <button type="button" class="pill-chip danger-btn" (click)="confirmRemove()">
                Remove
              </button>
            </div>
          </div>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .admin-users {
        padding-top: 16px;
        padding-bottom: 40px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 16px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .sub,
      .muted {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .btn-icon {
        font-size: 18px;
      }

      .stats-row {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 10px;
        margin-bottom: 14px;
      }

      .stat-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 12px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .stat-val {
        font-size: 20px;
        font-weight: 700;
      }

      .stat-val.danger {
        color: var(--error);
      }

      .stat-lbl {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .search-box {
        display: flex;
        align-items: center;
        gap: 8px;
        height: 42px;
        padding: 0 12px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-pill);
        margin-bottom: 16px;
      }

      .search-box input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        font-size: 14px;
      }

      .user-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .user-row {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 12px 14px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
      }

      .user-row.blocked {
        border-color: color-mix(in srgb, var(--error) 40%, transparent);
      }

      .user-main {
        display: flex;
        align-items: center;
        gap: 12px;
        min-width: 0;
      }

      .avatar {
        width: 40px;
        height: 40px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .avatar.fallback {
        display: grid;
        place-items: center;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .user-meta {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }

      .name-line {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
      }

      .user-name {
        font-weight: 600;
        font-size: 14px;
      }

      .user-email {
        font-size: 12px;
        color: var(--on-surface-muted);
        overflow-wrap: anywhere;
      }

      .role-badge,
      .blocked-badge {
        padding: 1px 7px;
        border-radius: var(--radius-pill);
        font-size: 10px;
        font-weight: 700;
      }

      .role-badge {
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .blocked-badge {
        background-color: var(--error);
        color: var(--on-error);
      }

      .user-actions {
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .danger-chip {
        color: var(--error);
        border-color: color-mix(in srgb, var(--error) 45%, transparent);
      }

      .empty-msg {
        text-align: center;
        color: var(--on-surface-muted);
        padding: 32px 0;
      }

      .state-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 36px 24px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        text-align: center;
      }

      .state-icon {
        font-size: 40px;
        color: var(--on-surface-muted);
      }

      .confirm-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.55);
        display: grid;
        place-items: center;
        padding: 16px;
        z-index: 80;
      }

      .confirm-modal {
        width: 100%;
        max-width: 400px;
        background: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 18px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .confirm-modal h3 {
        margin: 0;
        font-size: 17px;
      }

      .confirm-modal p {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .confirm-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }

      .danger-btn {
        background-color: var(--error);
        border-color: var(--error);
        color: var(--on-error);
      }
    `,
  ],
})
export class AdminUsersComponent implements OnInit {
  readonly usersService = inject(AdminUsersService);
  readonly auth = inject(AuthService);
  readonly screen = inject(ScreenClassService);
  private readonly headerSearch = inject(HeaderSearchService);
  private readonly destroyRef = inject(DestroyRef);

  readonly search = signal<string>('');
  readonly userToRemove = signal<AdminUser | null>(null);

  readonly blockedCount = computed(
    () => this.usersService.users().filter((u) => u.isBlocked).length,
  );
  readonly activeCount = computed(
    () => this.usersService.users().length - this.blockedCount(),
  );

  private searchTimer: ReturnType<typeof setTimeout> | null = null;

  ngOnInit(): void {
    if (this.auth.isAdmin()) {
      void this.usersService.fetchUsers();
      const unregister = this.headerSearch.register({
        placeholder: 'Search by name or email...',
        onChange: (q) => this.onSearchChange(q),
      });
      this.destroyRef.onDestroy(unregister);
    }
  }

  refresh(): void {
    void this.usersService.fetchUsers(this.search());
  }

  onSearchChange(value: string): void {
    this.search.set(value);
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => {
      void this.usersService.fetchUsers(value);
    }, 280);
  }

  async confirmRemove(): Promise<void> {
    const target = this.userToRemove();
    if (!target) return;
    await this.usersService.removeUser(target.id);
    this.userToRemove.set(null);
  }
}
