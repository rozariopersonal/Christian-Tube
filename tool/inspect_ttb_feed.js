const https = require('https');

https.get('https://feeds.feedburner.com/ThroughTheBible-ZacPoonen', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const matches = [...data.matchAll(/url="([^"]+\.mp3)"/g)];
    console.log(`Found ${matches.length} MP3s in TTB RSS feed:`);
    matches.slice(0, 15).forEach(m => console.log(m[1]));
  });
}).on('error', err => console.error(err));
