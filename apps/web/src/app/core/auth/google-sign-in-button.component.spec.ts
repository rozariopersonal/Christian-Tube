import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AuthService } from './auth.service';
import { GoogleSignInButtonComponent } from './google-sign-in-button.component';

describe('GoogleSignInButtonComponent', () => {
  afterEach(() => {
    vi.useRealTimers();
    delete window.google;
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('renders Google’s button and accepts its credential without One Tap', async () => {
    let credentialCallback: ((response: { credential?: string }) => void) | undefined;
    const prompt = vi.fn();
    const renderButton = vi.fn((element: HTMLElement) => {
      const button = document.createElement('button');
      button.textContent = 'Continue with Google';
      element.appendChild(button);
    });
    window.google = { accounts: { id: {
      initialize: (options) => { credentialCallback = options.callback; },
      renderButton,
      prompt,
      disableAutoSelect: vi.fn(),
    } } };
    TestBed.configureTestingModule({
      imports: [GoogleSignInButtonComponent],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    const auth = TestBed.inject(AuthService);
    auth.markSessionRejected();
    const fixture = TestBed.createComponent(GoogleSignInButtonComponent);
    fixture.detectChanges();
    expect(renderButton).toHaveBeenCalledOnce();
    expect(fixture.nativeElement.textContent).toContain('Continue with Google');
    expect(prompt).not.toHaveBeenCalled();

    const token = `header.${btoa(JSON.stringify({ sub: 'u1', email: 'u@example.com', exp: 4102444800 }))}.signature`;
    credentialCallback?.({ credential: token });
    expect(auth.sessionNeedsSignIn()).toBe(false);
    expect(auth.currentUser()?.id).toBe('u1');
    expect(localStorage.getItem('auth_token')).toBe(token);
    const http = TestBed.inject(HttpTestingController);
    http.expectOne((request) => request.url.endsWith('/api/users/sync')).flush({});
    await Promise.resolve();
    http.match((request) => request.url.includes('/channels/check-admin')).forEach((request) => request.flush({ isAdmin: false }));
  });

  it('renders the button when Google’s script loads after the banner', () => {
    vi.useFakeTimers();
    delete window.google;
    TestBed.configureTestingModule({ imports: [GoogleSignInButtonComponent], providers: [provideHttpClient()] });
    const fixture = TestBed.createComponent(GoogleSignInButtonComponent);
    fixture.detectChanges();
    expect(fixture.componentInstance.loading()).toBe(true);
    const renderButton = vi.fn();
    window.google = { accounts: { id: { initialize: vi.fn(), renderButton, prompt: vi.fn(), disableAutoSelect: vi.fn() } } };
    vi.advanceTimersByTime(250);
    expect(renderButton).toHaveBeenCalledOnce();
    expect(fixture.componentInstance.loading()).toBe(false);
    fixture.destroy();
  });
});
