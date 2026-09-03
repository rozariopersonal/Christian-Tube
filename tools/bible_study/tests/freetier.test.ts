import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';

test('config enforces free tier pacing <= 15 RPM', () => {
  const config = loadConfig();
  const pauseMs = config.processing.pause_between_requests_ms;

  // Assuming ~1.5s API execution time + pauseMs
  const estimatedSecondsPerRequest = (pauseMs + 1500) / 1000;
  const requestsPerMinute = 60 / estimatedSecondsPerRequest;

  console.log(`Pacing delay: ${pauseMs}ms -> Estimated request rate: ${requestsPerMinute.toFixed(1)} RPM`);

  // Must be strictly <= 15 RPM for free tier
  assert.ok(
    requestsPerMinute <= 15,
    `Request rate (${requestsPerMinute.toFixed(1)} RPM) exceeds 15 RPM free tier limit`
  );
});

test('config retry delay is sufficient for rate limit window recovery', () => {
  const config = loadConfig();
  assert.ok(
    config.gemini.retry_base_delay_ms >= 5000,
    'Base retry delay should be >= 5000ms for free tier quota recovery'
  );
});
