const https = require('https');

https.get('https://feeds.feedburner.com/ZacPoonen-Sermons', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const items = [...data.matchAll(/<item>([\s\S]*?)<\/item>/gi)];
    console.log(`Parsed ${items.length} items from Zac Poonen Sermons feed`);
    const parsed = items.map((item, idx) => {
      const titleMatch = item[1].match(/<title>([\s\S]*?)<\/title>/i);
      const urlMatch = item[1].match(/url="([^"]+\.mp3)"/i);
      return {
        index: idx + 1,
        title: titleMatch ? titleMatch[1].trim() : `Sermon ${idx + 1}`,
        url: urlMatch ? urlMatch[1].trim() : ''
      };
    });
    console.log('Sample 5 items:', JSON.stringify(parsed.slice(0, 5), null, 2));
  });
});
