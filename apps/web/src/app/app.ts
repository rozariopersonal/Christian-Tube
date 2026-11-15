import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { ReleaseDataService } from './core/api/release-data.service';
import { ThemeService } from './core/theme/theme.service';

@Component({
  imports: [RouterOutlet],
  selector: 'app-root',
  template: '<router-outlet />',
})
export class App {
  // Eagerly initialize theme tokens and release manifest revision on boot.
  private readonly _theme = inject(ThemeService);
  private readonly _releases = inject(ReleaseDataService);
}
