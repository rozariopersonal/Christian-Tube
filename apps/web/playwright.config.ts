import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 30000,
  retries: 0,
  use: {
    baseURL: 'http://127.0.0.1:4311',
    channel: process.env['CI'] ? undefined : 'chrome',
    headless: true,
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'npx ng serve --host 127.0.0.1 --port 4311',
    url: 'http://127.0.0.1:4311',
    reuseExistingServer: false,
    timeout: 60000,
  },
});
