import { isDevMode } from '@angular/core';

const localBackend = typeof window !== 'undefined' && isDevMode() &&
  (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1');

const runtimeApiBaseUrl =
  typeof window !== 'undefined'
    ? (window as { __APP_CONFIG__?: { apiBaseUrl?: string } }).__APP_CONFIG__?.apiBaseUrl
    : undefined;

export const AppConfig = {
  instanceId: 'christian_tube',
  appName: 'ChristianApp',
  apiBaseUrl: runtimeApiBaseUrl || (localBackend ? 'http://127.0.0.1:3000' : 'https://christianapp-zjdh.onrender.com'),
  releasesRepo: 'rozariopersonal/Christian-Tube-Releases',
  googleClientId: '269717576774-u01upfu4n1nit8o2t5bclteihvl9qv75.apps.googleusercontent.com',
  defaultCategories: [
    'All',
    'Worship',
    'Sermons',
    'Testimonies',
    'Bible Study',
    'Youth',
    'Gospel Music',
    'Kids',
  ],
  defaultBibleVersion: 'NASB',
} as const;
