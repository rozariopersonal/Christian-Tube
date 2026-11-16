import { Routes } from '@angular/router';
import { MainShellComponent } from './core/layout/main-shell.component';
import { VideoFeedComponent } from './features/videos/pages/video-feed.component';

export const routes: Routes = [
  {
    path: 'onboarding',
    loadComponent: () =>
      import('./features/onboarding/pages/onboarding.component').then(
        (m) => m.OnboardingComponent,
      ),
  },
  {
    path: '',
    component: MainShellComponent,
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'feed' },
      { path: 'feed', component: VideoFeedComponent },
      {
        path: 'shorts',
        loadComponent: () =>
          import('./features/videos/pages/shorts.component').then(
            (m) => m.ShortsComponent,
          ),
      },
      {
        path: 'words',
        loadComponent: () =>
          import('./features/words/pages/words-feed.component').then(
            (m) => m.WordsFeedComponent,
          ),
      },
      {
        path: 'watch/:id',
        loadComponent: () =>
          import('./features/videos/pages/watch-video.component').then(
            (m) => m.WatchVideoComponent,
          ),
      },
      {
        path: 'channels',
        loadComponent: () =>
          import('./features/channels/pages/channels.component').then(
            (m) => m.ChannelsComponent,
          ),
      },
      {
        path: 'channels/:id',
        loadComponent: () =>
          import('./features/channels/pages/channel-detail.component').then(
            (m) => m.ChannelDetailComponent,
          ),
      },
      {
        path: 'search',
        loadComponent: () =>
          import('./features/videos/pages/search.component').then(
            (m) => m.SearchComponent,
          ),
      },
      {
        path: 'bible',
        loadComponent: () =>
          import('./features/bible/pages/bible-reader.component').then(
            (m) => m.BibleReaderComponent,
          ),
      },
      {
        path: 'bible/:version/:book/:chapter',
        loadComponent: () =>
          import('./features/bible/pages/bible-reader.component').then(
            (m) => m.BibleReaderComponent,
          ),
      },
      {
        path: 'bible/:version/:book/:chapter/:verse',
        loadComponent: () =>
          import('./features/bible/pages/bible-reader.component').then(
            (m) => m.BibleReaderComponent,
          ),
      },
      {
        path: 'books',
        loadComponent: () =>
          import('./features/books/pages/books-catalog.component').then(
            (m) => m.BooksCatalogComponent,
          ),
      },
      {
        path: 'books/:id',
        loadComponent: () =>
          import('./features/books/pages/book-reader.component').then(
            (m) => m.BookReaderComponent,
          ),
      },
      {
        path: 'books/:id/chapter/:chapter',
        loadComponent: () =>
          import('./features/books/pages/book-reader.component').then(
            (m) => m.BookReaderComponent,
          ),
      },
      {
        path: 'articles',
        loadComponent: () =>
          import('./features/articles/pages/articles-browser.component').then(
            (m) => m.ArticlesBrowserComponent,
          ),
      },
      {
        path: 'article/:id',
        loadComponent: () =>
          import('./features/articles/pages/article-reader.component').then(
            (m) => m.ArticleReaderComponent,
          ),
      },
      {
        path: 'audio',
        loadComponent: () =>
          import('./features/audio/pages/audio-library.component').then(
            (m) => m.AudioLibraryComponent,
          ),
      },
      {
        path: 'audio/series/:id',
        loadComponent: () =>
          import('./features/audio/pages/audio-series-detail.component').then(
            (m) => m.AudioSeriesDetailComponent,
          ),
      },
      {
        path: 'settings',
        loadComponent: () =>
          import('./features/settings/pages/settings.component').then(
            (m) => m.SettingsComponent,
          ),
      },
    ],
  },
  { path: '**', redirectTo: 'feed' },
];
