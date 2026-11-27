import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  HostListener,
  ViewChild,
  effect,
  inject,
  signal,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from './auth.service';

@Component({
  selector: 'app-account-avatar-menu',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="avatar-menu-root">
      <button
        #triggerBtn
        type="button"
        class="avatar-trigger"
        [class.session-expired]="auth.sessionExpired()"
        [attr.aria-label]="
          auth.sessionExpired()
            ? 'Account. Sync paused, tap to resume.'
            : 'Account & Settings'
        "
        [attr.aria-expanded]="open()"
        aria-haspopup="dialog"
        (click)="toggle()"
      >
        @if (auth.currentUser()?.photoUrl) {
          <img
            class="avatar-img"
            [src]="auth.currentUser()!.photoUrl"
            [alt]="auth.currentUser()!.displayName"
          />
        } @else if (auth.currentUser()) {
          <span class="avatar-initials" aria-hidden="true">
            {{ initials(auth.currentUser()!.displayName) }}
          </span>
        } @else {
          <span class="material-symbols-rounded avatar-fallback" aria-hidden="true">
            account_circle
          </span>
        }

        @if (auth.sessionExpired()) {
          <span class="sync-badge" aria-hidden="true">
            <span class="material-symbols-rounded sync-badge-glyph">sync_problem</span>
          </span>
        }
      </button>

      @if (open()) {
        <div class="popover-backdrop" (click)="close()"></div>
        <div
          #popoverEl
          class="account-popover"
          role="dialog"
          aria-label="Account and sync status"
          tabindex="-1"
        >
          @if (auth.currentUser(); as user) {
            <div class="popover-header">
              @if (user.photoUrl) {
                <img class="popover-avatar" [src]="user.photoUrl" [alt]="user.displayName" />
              } @else {
                <span class="popover-avatar initials">{{ initials(user.displayName) }}</span>
              }
              <div class="popover-identity">
                <div class="popover-name">{{ user.displayName }}</div>
                <div class="popover-email">
                  {{ user.email }}
                </div>
              </div>
              <button
                type="button"
                class="close-btn"
                aria-label="Close account menu"
                (click)="close()"
              >
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>

            @if (auth.sessionExpired()) {
              <div class="status-pill warn">
                <span class="material-symbols-rounded" aria-hidden="true">sync_problem</span>
                <span>Sync paused · Local changes are saved on this device</span>
              </div>
              <div class="gsi-section">
                <div #gsiHost class="gsi-host"></div>
                @if (!gsiRendered()) {
                  <button
                    type="button"
                    class="primary-btn"
                    (click)="auth.promptGoogleSignIn()"
                  >
                    Resume sync
                  </button>
                }
              </div>
            } @else {
              <div class="status-pill ok">
                <span class="material-symbols-rounded" aria-hidden="true">cloud_done</span>
                <span>Synced across your devices</span>
              </div>
            }

            <div class="popover-actions">
              <a class="menu-link" routerLink="/settings" (click)="close()">
                <span class="material-symbols-rounded">tune</span>
                <span>Settings</span>
              </a>

              <div class="menu-divider"></div>

              @if (!confirmingSignOut()) {
                <button
                  type="button"
                  class="menu-link danger"
                  (click)="confirmingSignOut.set(true)"
                >
                  <span class="material-symbols-rounded">logout</span>
                  <span>Sign out</span>
                </button>
              } @else {
                <div class="signout-confirm">
                  <p class="signout-warn">
                    Signing out removes cached data and offline downloads from this browser.
                  </p>
                  <div class="confirm-row">
                    <button
                      type="button"
                      class="ghost-btn"
                      (click)="confirmingSignOut.set(false)"
                    >
                      Cancel
                    </button>
                    <button
                      type="button"
                      class="danger-btn"
                      (click)="confirmSignOut()"
                    >
                      Sign out
                    </button>
                  </div>
                </div>
              }
            </div>
          } @else {
            <div class="popover-header">
              <div class="popover-identity">
                <div class="popover-name">Not signed in</div>
                <div class="popover-email">Sign in to sync across devices</div>
              </div>
              <button
                type="button"
                class="close-btn"
                aria-label="Close account menu"
                (click)="close()"
              >
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>

            <div class="gsi-section">
              <div #gsiHost class="gsi-host"></div>
              @if (!gsiRendered()) {
                <button
                  type="button"
                  class="primary-btn"
                  (click)="auth.promptGoogleSignIn()"
                >
                  Sign in with Google
                </button>
              }
            </div>

            <div class="popover-actions">
              <a class="menu-link" routerLink="/settings" (click)="close()">
                <span class="material-symbols-rounded">tune</span>
                <span>Settings</span>
              </a>
            </div>
          }
        </div>
      }

      @if (auth.pendingAccountSwitch(); as sw) {
        <div
          class="switch-modal-backdrop"
          role="presentation"
          (click)="auth.resolveAccountSwitch(false)"
        >
          <div
            class="switch-modal"
            role="alertdialog"
            aria-modal="true"
            aria-labelledby="switch-title"
            aria-describedby="switch-desc"
            (click)="$event.stopPropagation()"
          >
            <h2 id="switch-title" class="switch-title">Switch Google account?</h2>
            <p id="switch-desc" class="switch-desc">
              Continue as <strong>{{ sw.nextUser.email || sw.nextUser.displayName }}</strong>?
              This removes local data saved for
              <strong>{{ sw.currentUser.email || sw.currentUser.displayName }}</strong>
              on this device.
            </p>
            <div class="confirm-row">
              <button
                type="button"
                class="ghost-btn"
                (click)="auth.resolveAccountSwitch(false)"
              >
                Cancel
              </button>
              <button
                type="button"
                class="primary-btn inline"
                (click)="auth.resolveAccountSwitch(true)"
              >
                Switch account
              </button>
            </div>
          </div>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .avatar-menu-root {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .avatar-trigger {
        position: relative;
        width: 36px;
        height: 36px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface);
        transition: box-shadow 150ms ease;
      }

      .avatar-trigger:hover {
        background-color: var(--surface-variant);
      }

      .avatar-trigger.session-expired {
        box-shadow: 0 0 0 2px var(--accent);
      }

      .avatar-img {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        object-fit: cover;
      }

      .avatar-initials {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        color: var(--on-surface);
        font-size: 12px;
        font-weight: 700;
        display: grid;
        place-items: center;
      }

      .avatar-fallback {
        font-size: 26px;
      }

      .sync-badge {
        position: absolute;
        right: -1px;
        bottom: -1px;
        width: 15px;
        height: 15px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--bg);
        border: 2px solid var(--surface);
        display: grid;
        place-items: center;
      }

      .sync-badge-glyph {
        font-size: 10px;
        font-weight: 700;
        line-height: 1;
      }

      .popover-backdrop {
        position: fixed;
        inset: 0;
        z-index: 90;
      }

      .account-popover {
        position: absolute;
        top: calc(100% + 8px);
        right: 0;
        width: min(328px, calc(100vw - 24px));
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: 16px;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.24);
        padding: 14px;
        z-index: 100;
        display: flex;
        flex-direction: column;
        gap: 12px;
        outline: none;
      }

      .popover-header {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .popover-avatar {
        width: 40px;
        height: 40px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .popover-avatar.initials {
        background-color: var(--surface-variant);
        color: var(--on-surface);
        display: grid;
        place-items: center;
        font-weight: 700;
        font-size: 14px;
      }

      .popover-identity {
        min-width: 0;
        flex: 1;
      }

      .popover-name {
        font-size: 14px;
        font-weight: 600;
        color: var(--on-surface);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .popover-email {
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .close-btn {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
      }

      .close-btn:hover {
        background-color: var(--surface-variant);
      }

      .status-pill {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        border-radius: 10px;
        background-color: var(--surface-variant);
        color: var(--on-surface);
        font-size: 12px;
        line-height: 1.35;
      }

      .status-pill .material-symbols-rounded {
        font-size: 18px;
        flex-shrink: 0;
      }

      .status-pill.warn {
        border: 1px solid var(--accent);
      }

      .status-pill.warn .material-symbols-rounded {
        color: var(--accent);
      }

      .gsi-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
        align-items: stretch;
      }

      .gsi-host {
        display: flex;
        justify-content: center;
        min-height: 0;
      }

      .primary-btn {
        width: 100%;
        padding: 9px 14px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--bg);
        font-size: 13px;
        font-weight: 600;
        text-align: center;
      }

      .primary-btn.inline {
        width: auto;
      }

      .ghost-btn {
        padding: 8px 12px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 13px;
        font-weight: 500;
      }

      .danger-btn {
        padding: 8px 14px;
        border-radius: var(--radius-pill);
        background-color: var(--error);
        color: var(--on-error);
        font-size: 13px;
        font-weight: 600;
      }

      .popover-actions {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      .menu-link {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 10px;
        border-radius: 10px;
        color: var(--on-surface);
        font-size: 13px;
        font-weight: 500;
        text-align: left;
      }

      .menu-link:hover {
        background-color: var(--surface-variant);
      }

      .menu-link .material-symbols-rounded {
        font-size: 18px;
      }

      .menu-link.danger {
        color: #ef4444;
      }

      .menu-divider {
        height: 1px;
        background-color: var(--surface-border);
        margin: 4px 0;
      }

      .signout-confirm {
        padding: 8px;
        border-radius: 10px;
        background-color: var(--surface-variant);
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .signout-warn {
        margin: 0;
        font-size: 12px;
        color: var(--on-surface-muted);
        line-height: 1.4;
      }

      .confirm-row {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }

      .switch-modal-backdrop {
        position: fixed;
        inset: 0;
        background-color: rgba(0, 0, 0, 0.55);
        z-index: 200;
        display: grid;
        place-items: center;
        padding: 16px;
      }

      .switch-modal {
        width: min(380px, 100%);
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: 16px;
        padding: 20px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .switch-title {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .switch-desc {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        line-height: 1.45;
      }
    `,
  ],
})
export class AccountAvatarMenuComponent {
  readonly auth = inject(AuthService);

  readonly open = signal<boolean>(false);
  readonly confirmingSignOut = signal<boolean>(false);
  readonly gsiRendered = signal<boolean>(false);

  @ViewChild('popoverEl') popoverEl?: ElementRef<HTMLElement>;
  @ViewChild('triggerBtn') triggerBtn?: ElementRef<HTMLButtonElement>;

  private gsiHostRef: ElementRef<HTMLElement> | undefined;

  @ViewChild('gsiHost')
  set gsiHost(ref: ElementRef<HTMLElement> | undefined) {
    this.gsiHostRef = ref;
    if (ref && this.open()) {
      this.tryRenderGsiButton(ref.nativeElement);
    }
  }

  constructor() {
    effect(() => {
      // Automatically close popover when auth transitions back to active
      if (!this.auth.sessionExpired() && this.auth.isAuthenticated()) {
        this.confirmingSignOut.set(false);
      }
    });
  }

  toggle(): void {
    if (this.open()) {
      this.close();
    } else {
      this.open.set(true);
      this.confirmingSignOut.set(false);
      this.gsiRendered.set(false);
      queueMicrotask(() => {
        this.popoverEl?.nativeElement.focus();
        if (this.gsiHostRef) {
          this.tryRenderGsiButton(this.gsiHostRef.nativeElement);
        }
      });
    }
  }

  close(): void {
    this.open.set(false);
    this.confirmingSignOut.set(false);
    this.triggerBtn?.nativeElement.focus();
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    if (this.auth.pendingAccountSwitch()) {
      this.auth.resolveAccountSwitch(false);
      return;
    }
    if (this.open()) {
      this.close();
    }
  }

  initials(name: string): string {
    const clean = (name || 'U').trim();
    const parts = clean.split(/\s+/);
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
    }
    return clean.slice(0, 2).toUpperCase();
  }

  confirmSignOut(): void {
    this.open.set(false);
    this.confirmingSignOut.set(false);
    this.auth.signOut();
  }

  private tryRenderGsiButton(host: HTMLElement): void {
    const ok = this.auth.initGoogleSignIn();
    if (!ok) {
      this.gsiRendered.set(false);
      return;
    }
    this.auth.renderGoogleButton(host);
    this.gsiRendered.set(host.childElementCount > 0);
  }
}
