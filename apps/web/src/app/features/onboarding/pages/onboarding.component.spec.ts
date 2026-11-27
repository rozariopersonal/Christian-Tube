import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { AuthService } from '../../../core/auth/auth.service';
import { ContentPreferencesService } from '../../../core/services/content-preferences.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import { ChannelService } from '../../channels/services/channel.service';
import { OnboardingComponent } from './onboarding.component';

describe('OnboardingComponent', () => {
  let fixture: ComponentFixture<OnboardingComponent>;
  let router: Router;
  let channels: ChannelService;
  let preferences: ContentPreferencesService;
  let appearance: ReaderAppearanceService;
  let auth: AuthService;
  let userSync: UserSyncService;

  beforeEach(async () => {
    localStorage.clear();
    await TestBed.configureTestingModule({
      imports: [OnboardingComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
      ],
    }).compileComponents();

    router = TestBed.inject(Router);
    channels = TestBed.inject(ChannelService);
    preferences = TestBed.inject(ContentPreferencesService);
    appearance = TestBed.inject(ReaderAppearanceService);
    auth = TestBed.inject(AuthService);
    userSync = TestBed.inject(UserSyncService);

    vi.spyOn(channels, 'fetchChannels').mockResolvedValue();
    vi.spyOn(channels, 'loadSubscriptions').mockResolvedValue();
    vi.spyOn(router, 'navigateByUrl').mockResolvedValue(true);
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('renders single-screen Quick Start without guest sign-in or multi-step wizard', () => {
    fixture = TestBed.createComponent(OnboardingComponent);
    fixture.detectChanges();

    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('Welcome to ChristianApp');
    expect(text).toContain('Sign in with Google');
    expect(text).toContain('Choose Your Languages');
    expect(text).toContain('Start Exploring');
    expect(text).not.toContain('Continue as Guest');
    expect(text).not.toContain('Step 1 of 5');
  });

  it('saves languages, auto-picks primary Bible version, auto-follows popular channels, and navigates on Start Exploring', async () => {
    channels.channels.set([
      {
        id: 'ch-en-1',
        title: 'English Ministry',
        avatarUrl: '',
        subscriberCount: 500,
        videoCount: 40,
        isSubscribed: false,
        language: 'en',
        hasShorts: false,
        isActive: true,
      },
      {
        id: 'ch-ta-1',
        title: 'Tamil Ministry',
        avatarUrl: '',
        subscriberCount: 800,
        videoCount: 60,
        isSubscribed: false,
        language: 'ta',
        hasShorts: false,
        isActive: true,
      },
    ]);
    const subscribeSpy = vi.spyOn(channels, 'subscribeMany').mockResolvedValue();

    fixture = TestBed.createComponent(OnboardingComponent);
    fixture.detectChanges();

    // Switch default 'en' -> 'ta'
    const comp = fixture.componentInstance;
    comp.toggleLanguage('ta');
    comp.toggleLanguage('en');

    await comp.startExploring();

    expect(preferences.preferredLanguages()).toEqual(['ta']);
    expect(appearance.primaryBibleVersion()).toBe('TAOBVSI');
    expect(subscribeSpy).toHaveBeenCalledWith(['ch-ta-1']);
    expect(localStorage.getItem('onboarding_completed')).toBe('true');
    expect(router.navigateByUrl).toHaveBeenCalledWith('/feed');
  });

  it('enqueues hasCompletedOnboarding when signed in and clicking Start Exploring', async () => {
    auth.currentUser.set({
      id: 'u1',
      email: 'u@example.com',
      displayName: 'Grace User',
    });
    const enqueueSpy = vi.spyOn(userSync, 'enqueuePreference');
    vi.spyOn(channels, 'subscribeMany').mockResolvedValue();

    fixture = TestBed.createComponent(OnboardingComponent);
    fixture.detectChanges();

    await fixture.componentInstance.startExploring();

    expect(enqueueSpy).toHaveBeenCalledWith('hasCompletedOnboarding', true);
    expect(localStorage.getItem('onboarding_completed')).toBe('true');
    expect(router.navigateByUrl).toHaveBeenCalledWith('/feed');
  });

  it('auto-restores and navigates to default route when a returning user signs in with Google', async () => {
    fixture = TestBed.createComponent(OnboardingComponent);
    fixture.detectChanges();

    auth.currentUser.set({
      id: 'u2',
      email: 'returning@example.com',
      displayName: 'Returning User',
    });
    TestBed.flushEffects();

    userSync.remoteState.set({
      serverTime: Date.now(),
      preferences: {
        languages: ['en'],
        defaultPage: 'bible',
        hasCompletedOnboarding: true,
      },
    });
    TestBed.flushEffects();

    expect(localStorage.getItem('onboarding_completed')).toBe('true');
    expect(router.navigateByUrl).toHaveBeenCalledWith('/bible');
  });
});
