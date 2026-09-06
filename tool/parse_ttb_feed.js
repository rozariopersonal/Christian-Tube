const https = require('https');

https.get('https://feeds.feedburner.com/ThroughTheBible-ZacPoonen', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const items = [...data.matchAll(/<item>([\s\S]*?)<\/item>/gi)];
    console.log(`Parsed ${items.length} items from TTB feed`);
    const parsed = items.map((item, idx) => {
      const titleMatch = item[1].match(/<title>([\s\S]*?)<\/title>/i);
      const urlMatch = item[1].match(/url="([^"]+\.mp3)"/i);
      const durationMatch = item[1].match(/<itunes:duration>([^<]+)<\/itunes:duration>/i);
      return {
        index: idx + 1,
        title: titleMatch ? titleMatch[1].trim() : `Episode ${idx + 1}`,
        url: urlMatch ? urlMatch[1].trim() : '',
        duration: durationMatch ? durationMatch[1].trim() : '0'
      };
    });
    console.log('First 5 items:', JSON.stringify(parsed.slice(0, 5), null, 2));
    console.log('Last 2 items:', JSON.stringify(parsed.slice(-2), null, 2));
  });
});
