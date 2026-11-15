import { Routes } from '@angular/router';
import { MainShellComponent } from './core/layout/main-shell.component';
import { AudioLibraryComponent } from './features/audio/pages/audio-library.component';
import { AudioSeriesDetailComponent } from './features/audio/pages/audio-series-detail.component';
import { BibleReaderComponent } from './features/bible/pages/bible-reader.component';
import { BookReaderComponent } from './features/books/pages/book-reader.component';
import { BooksCatalogComponent } from './features/books/pages/books-catalog.component';
import { ChannelDetailComponent } from './features/channels/pages/channel-detail.component';
import { ChannelsComponent } from './features/channels/pages/channels.component';
import { OnboardingComponent } from './features/onboarding/pages/onboarding.component';
import { SettingsComponent } from './features/settings/pages/settings.component';
import { SearchComponent } from './features/videos/pages/search.component';
import { VideoFeedComponent } from './features/videos/pages/video-feed.component';
import { WatchVideoComponent } from './features/videos/pages/watch-video.component';

export const routes: Routes = [
  {
    path: 'onboarding',
    component: OnboardingComponent,
  },
  {
    path: '',
    component: MainShellComponent,
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'feed' },
      { path: 'feed', component: VideoFeedComponent },
      { path: 'watch/:id', component: WatchVideoComponent },
      { path: 'channels', component: ChannelsComponent },
      { path: 'channels/:id', component: ChannelDetailComponent },
      { path: 'search', component: SearchComponent },
      { path: 'bible', component: BibleReaderComponent },
      { path: 'bible/:version/:book/:chapter', component: BibleReaderComponent },
      { path: 'bible/:version/:book/:chapter/:verse', component: BibleReaderComponent },
      { path: 'books', component: BooksCatalogComponent },
      { path: 'books/:id', component: BookReaderComponent },
      { path: 'books/:id/chapter/:chapter', component: BookReaderComponent },
      { path: 'audio', component: AudioLibraryComponent },
      { path: 'audio/series/:id', component: AudioSeriesDetailComponent },
      { path: 'settings', component: SettingsComponent },
    ],
  },
  { path: '**', redirectTo: 'feed' },
];
