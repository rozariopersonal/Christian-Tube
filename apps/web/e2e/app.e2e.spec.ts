import { expect, Page, test } from '@playwright/test';

async function mockBackendAndCdn(page: Page): Promise<void> {
  await page.route('https://christianapp-zjdh.onrender.com/**', async (route) => {
    const url = route.request().url();
    if (url.includes('/api/videos/v1')) {
      return route.fulfill({
        json: {
          id: 'v1',
          title: 'Walking in the Light',
          description: 'Sermon on 1 John 1.',
          channelId: 'ch1',
          channelTitle: 'Grace Fellowship',
          viewCount: 12500,
          publishedAt: '2026-10-01T10:00:00Z',
          duration: '42:10',
          isLive: false,
        },
      });
    }
    if (url.includes('/api/videos') && url.includes('type=SHORT')) {
      return route.fulfill({
        json: {
          videos: [
            {
              id: 'sh1',
              title: '60-Second Encouragement #short',
              channelId: 'ch1',
              channelTitle: 'Grace Fellowship',
              viewCount: 3400,
              publishedAt: '2026-10-02T10:00:00Z',
              duration: '0:58',
              isLive: false,
              type: 'SHORT',
            },
          ],
        },
      });
    }
    if (url.includes('/api/videos')) {
      return route.fulfill({
        json: {
          videos: [
            {
              id: 'v1',
              title: 'Walking in the Light',
              channelId: 'ch1',
              channelTitle: 'Grace Fellowship',
              viewCount: 12500,
              publishedAt: '2026-10-01T10:00:00Z',
              duration: '42:10',
              isLive: false,
              type: 'VIDEO',
            },
          ],
        },
      });
    }
    if (url.includes('/api/channels/subscriptions')) {
      return route.fulfill({ json: [] });
    }
    if (url.includes('/api/channels/ch1/subscribe')) {
      return route.fulfill({ json: { ok: true } });
    }
    if (url.includes('/api/channels/requests')) {
      return route.fulfill({ json: [] });
    }
    if (url.includes('/api/channels')) {
      return route.fulfill({
        json: [
          {
            id: 'ch1',
            title: 'Grace Fellowship',
            description: 'Verse by verse teaching.',
            avatarUrl: '',
            videoCount: 48,
            language: 'en',
          },
        ],
      });
    }
    if (url.includes('/api/audio/catalog')) {
      return route.fulfill({
        json: {
          data: [
            {
              id: 's1',
              title: 'Foundations of Faith',
              description: 'Core Christian teachings.',
              speaker: 'Zac Poonen',
              trackCount: 2,
              category: 'Sermons',
              language: 'en',
              tracks: [],
            },
          ],
        },
      });
    }
    if (url.includes('/api/audio/series/s1')) {
      return route.fulfill({
        json: {
          data: {
            id: 's1',
            title: 'Foundations of Faith',
            description: 'Core Christian teachings.',
            speaker: 'Zac Poonen',
            trackCount: 1,
            category: 'Sermons',
            language: 'en',
            tracks: [
              {
                id: 't1',
                title: 'Part 1: Repentance',
                seriesId: 's1',
                seriesTitle: 'Foundations of Faith',
                speaker: 'Zac Poonen',
                durationSeconds: 1800,
                audioUrl: 'https://example.com/audio.mp3',
              },
            ],
          },
        },
      });
    }
    return route.fulfill({ json: {} });
  });

  await page.route('https://cdn.jsdelivr.net/**', async (route) => {
    const url = route.request().url();
    if (url.includes('manifest.json')) {
      return route.fulfill({ json: { revision: 'rv_e2e' } });
    }
    if (url.includes('books.json')) {
      return route.fulfill({
        json: [{ bookNumber: 1, name: 'Genesis', chapters: 50 }],
      });
    }
    if (url.includes('/1/1.json')) {
      return route.fulfill({
        json: [
          {
            verse: 1,
            text: 'In the beginning God created the heavens and the earth.',
          },
          { verse: 2, text: 'The earth was formless and void.' },
        ],
      });
    }
    if (url.includes('/1/2.json')) {
      return route.fulfill({
        json: [
          {
            verse: 1,
            text: 'Thus the heavens and the earth were completed.',
          },
        ],
      });
    }
    if (url.includes('cross_references/GEN/1.json')) {
      return route.fulfill({
        json: [{ v: 1, refs: [{ bt: 'JHN', c: 1, v: 1 }] }],
      });
    }
    if (url.includes('books/catalog.json')) {
      return route.fulfill({
        json: [
          {
            id: 'book1',
            title: 'A Godly Family Life',
            author: 'Zac Poonen',
            subject: 'Family',
            lang: 'en',
          },
        ],
      });
    }
    if (url.includes('books/book1/toc.json')) {
      return route.fulfill({
        json: {
          id: 'book1',
          title: 'A Godly Family Life',
          author: 'Zac Poonen',
          chapters: [{ chapterIndex: 1, title: 'Introduction' }],
        },
      });
    }
    if (url.includes('books/book1/chapters/1.json')) {
      return route.fulfill({
        json: [
          { line: 1, text: 'Chapter Introduction', isHeading: true },
          { line: 2, text: 'Building a godly home.', isHeading: false },
        ],
      });
    }
    if (url.includes('articles/articles_index.json')) {
      return route.fulfill({
        json: [
          {
            id: 'art1',
            title: 'Walking in Humility',
            date: '2026-10-15',
            year: 2026,
            lang: 'en',
          },
        ],
      });
    }
    if (url.includes('articles/wftw/art1.json')) {
      return route.fulfill({
        json: {
          id: 'art1',
          title: 'Walking in Humility',
          date: '2026-10-15',
          author: 'Zac Poonen',
          lines: [
            { line: 1, text: 'God gives grace to the humble.', isHeading: false },
          ],
        },
      });
    }
    if (url.includes('words_feed/manifest.json')) {
      return route.fulfill({
        json: {
          totalItems: 1,
          topTopics: [{ slug: 'faith', name: 'faith', count: 10 }],
        },
      });
    }
    if (url.includes('words_feed/daily.json')) {
      return route.fulfill({
        json: [
          {
            dayOfYear: 1,
            bookNumber: 1,
            bookName: 'Genesis',
            chapter: 1,
            startVerse: 1,
            endVerse: 1,
            referenceLabel: 'Genesis 1:1',
            theme: 'God Creates',
          },
        ],
      });
    }
    return route.fulfill({ status: 404, body: 'Not found' });
  });
}

test.describe('ChristianApp Web E2E', () => {
  test('navigates Videos, Watch, Channels, Bible, Books, Audio, Settings & Onboarding', async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));

    await mockBackendAndCdn(page);

    // 1. Video Feed & Watch
    await page.goto('/feed');
    await expect(page.getByText('Walking in the Light')).toBeVisible();
    await page.getByText('Walking in the Light').click();
    await expect(page).toHaveURL(/\/watch\/v1/);
    await expect(page.getByRole('heading', { name: 'Walking in the Light' })).toBeVisible();

    // 2. Channels
    await page.goto('/channels');
    await expect(page.getByText('Grace Fellowship')).toBeVisible();
    await page.getByRole('button', { name: 'Follow', exact: true }).click();
    await expect(
      page.getByRole('button', { name: 'Following', exact: true }),
    ).toBeVisible();

    // 3. Bible Reader
    await page.goto('/bible');
    await expect(
      page.getByText('In the beginning God created the heavens and the earth.'),
    ).toBeVisible();
    await page
      .getByText('In the beginning God created the heavens and the earth.')
      .click();
    await expect(page.getByRole('button', { name: /Cross-Refs/ })).toBeVisible();
    await page.getByRole('button', { name: 'Close verse actions' }).click();
    await page.getByRole('button', { name: 'Next chapter' }).click();
    await expect(
      page.getByText('Thus the heavens and the earth were completed.'),
    ).toBeVisible();

    // 4. Books Library & Reader
    await page.goto('/books');
    const bookTitle = page.locator('.book-title', { hasText: 'A Godly Family Life' });
    await expect(bookTitle).toBeVisible();
    await bookTitle.click();
    await expect(page.getByText('Building a godly home.')).toBeVisible();

    // 5. Shorts & Word Feed
    await page.goto('/shorts');
    await expect(page.getByText('60-Second Encouragement #short')).toBeVisible();

    await page.goto('/words');
    await expect(page.getByText('Genesis 1:1')).toBeVisible();

    // 6. Articles Browser & Reader
    await page.goto('/articles');
    await expect(page.getByText('Walking in Humility')).toBeVisible();
    await page.getByText('Walking in Humility').click();
    await expect(page.getByText('God gives grace to the humble.')).toBeVisible();

    // 6. Audio Library, Series & Mini-Player
    await page.goto('/audio');
    await expect(page.getByText('Foundations of Faith')).toBeVisible();
    await page.getByText('Foundations of Faith').click();
    await expect(page.getByText('Part 1: Repentance')).toBeVisible();
    await page.getByText('Part 1: Repentance').click();
    await expect(page.locator('app-mini-player')).toContainText(
      'Part 1: Repentance',
    );

    // 6. Settings: Dark + AMOLED + Royal Crimson + Guest Sign-In
    await page.goto('/settings');
    await page.getByRole('button', { name: 'Dark' }).click();
    await page.getByRole('button', { name: 'AMOLED Black' }).click();
    await page.getByRole('button', { name: 'Royal Crimson' }).click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await expect(page.locator('html')).toHaveAttribute('data-amoled', 'true');
    await page.getByRole('button', { name: 'Guest Sign-In' }).click();
    await expect(page.getByText('Guest User')).toBeVisible();

    // 7. Onboarding Wizard
    await page.goto('/onboarding');
    await expect(page.getByText('Step 1 of 5')).toBeVisible();
    await page.getByRole('button', { name: 'Continue' }).click();
    await expect(page.getByText('Step 2 of 5')).toBeVisible();

    expect(errors).toEqual([]);
  });

  test('opens exact Bible verse, Book chapter, and Video timestamp from deep links', async ({
    page,
  }) => {
    await mockBackendAndCdn(page);

    // Bible deep link (matching DeepLinkService.bible)
    await page.goto('/bible?version=kjv&book=GEN&chapter=1&verse=2');
    await expect(page.locator('#verse-2.selected')).toBeVisible();
    await expect(
      page.locator('app-bible-verse-action-bar').getByRole('button', { name: /Share/i }),
    ).toBeVisible();

    // Book deep link (matching DeepLinkService.book / chapter)
    await page.goto('/books/book1?chapter=1');
    await expect(page.getByText('Chapter Introduction')).toBeVisible();

    // Video deep link with start timestamp (matching DeepLinkService.video)
    await page.goto('/watch/v1?start=45');
    await expect(page.locator('iframe.yt-iframe')).toHaveAttribute(
      'src',
      /start=45/,
    );
  });

  for (const width of [320, 600, 840, 1400]) {
    test(`renders without horizontal overflow at ${width}px`, async ({
      page,
    }) => {
      await mockBackendAndCdn(page);
      await page.setViewportSize({ width, height: 800 });
      await page.goto('/feed');
      await expect(page.getByText('Walking in the Light')).toBeVisible();

      if (width < 600) {
        await expect(page.locator('.bottom-nav')).toBeVisible();
        await expect(page.locator('.top-nav')).toBeHidden();
      } else {
        await expect(page.locator('.top-nav')).toBeVisible();
        await expect(page.locator('.bottom-nav')).toBeHidden();
      }

      const scrollWidth = await page.evaluate(
        () => document.documentElement.scrollWidth,
      );
      expect(scrollWidth).toBeLessThanOrEqual(width);
    });
  }
});
