import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { ReleaseDataService } from './core/api/release-data.service';
import { ContentPreferencesService } from './core/services/content-preferences.service';
import { UserItemsSyncService } from './core/services/user-items-sync.service';
import { UserSyncService } from './core/services/user-sync.service';
import { ThemeService } from './core/theme/theme.service';
import { ChannelService } from './features/channels/services/channel.service';

@Component({
  imports: [RouterOutlet],
  selector: 'app-root',
  template: '<router-outlet />',
})
export class App {
  // Eagerly initialize theme tokens, release manifest revision, user sync, preferences, and followed channels on boot.
  private readonly _theme = inject(ThemeService);
  private readonly _releases = inject(ReleaseDataService);
  private readonly _userSync = inject(UserSyncService);
  private readonly _userItemsSync = inject(UserItemsSyncService);
  private readonly _preferences = inject(ContentPreferencesService);
  private readonly _channels = inject(ChannelService);
}
