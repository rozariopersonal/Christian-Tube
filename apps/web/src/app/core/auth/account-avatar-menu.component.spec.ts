import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { AuthService } from './auth.service';
import { AccountAvatarMenuComponent } from './account-avatar-menu.component';

describe('AccountAvatarMenuComponent', () => {
  let fixture: ComponentFixture<AccountAvatarMenuComponent>;
  let auth: AuthService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [AccountAvatarMenuComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();

    auth = TestBed.inject(AuthService);
    fixture = TestBed.createComponent(AccountAvatarMenuComponent);
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('shows Google Sign-In and Settings without Continue as Guest when signed out', () => {
    fixture.detectChanges();
    const trigger = (fixture.nativeElement as HTMLElement).querySelector(
      '.avatar-trigger',
    ) as HTMLButtonElement;
    trigger.click();
    fixture.detectChanges();

    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('Sign in with Google');
    expect(text).toContain('Settings');
    expect(text).not.toContain('Continue as Guest');
  });

  it('shows synced status and email for signed-in users without guest labels', () => {
    auth.currentUser.set({
      id: 'u1',
      email: 'believer@example.com',
      displayName: 'Believer',
    });
    fixture.detectChanges();
    const trigger = (fixture.nativeElement as HTMLElement).querySelector(
      '.avatar-trigger',
    ) as HTMLButtonElement;
    trigger.click();
    fixture.detectChanges();

    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('believer@example.com');
    expect(text).toContain('Synced across your devices');
    expect(text).not.toContain('Guest session');
  });
});
